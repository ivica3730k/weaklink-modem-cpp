// Python bindings for the public API in weaklink/api.hpp.
//
// The surface mirrors the Python reference's `weaklink.modem` one-to-one, so
// code written against the pure-Python package runs unchanged on this one.
// Audio stays entirely on the C++ side: Python either hands over samples or
// names a device and lets the modem open it.

#include <pybind11/functional.h>
#include <pybind11/numpy.h>
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <cstddef>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "weaklink/api.hpp"
#include "weaklink/exceptions.hpp"
#include "weaklink/log.hpp"
#include "weaklink/streaming.hpp"

namespace py = pybind11;
namespace wl = weaklink;

namespace {

using FloatArray = py::array_t<float, py::array::c_style | py::array::forcecast>;

/// Borrow a numpy array's buffer as modem samples.
///
/// forcecast means anything that is not already C-contiguous float32 arrives
/// here as a converted copy, so the span is always valid for the call.
wl::dsp::Samples to_samples(const FloatArray& array) {
  const py::buffer_info info = array.request();
  if (info.ndim != 1) {
    throw wl::ConfigError("samples must be a one-dimensional array");
  }
  const auto* data = static_cast<const float*>(info.ptr);
  return wl::dsp::Samples(data, data + info.size);
}

py::array_t<float> to_numpy(const wl::dsp::Samples& samples) {
  py::array_t<float> out(static_cast<py::ssize_t>(samples.size()));
  std::copy(samples.begin(), samples.end(), out.mutable_data());
  return out;
}

py::bytes to_bytes(const wl::ByteVector& data) {
  return py::bytes(reinterpret_cast<const char*>(data.data()), data.size());
}

/// Lets Ctrl-C out of a blocking call, and remembers that it did.
///
/// The modem runs with the GIL released, so KeyboardInterrupt cannot surface
/// on its own: the interpreter only notices a signal when someone asks it to.
/// The latch matters because PyErr_CheckSignals reports a given interrupt
/// once -- asking a second time comes back clean while the exception is still
/// pending, and a transmission would resume and play out its tail.
class StopFlag {
 public:
  bool operator()() {
    if (stopped_) {
      return true;
    }
    const py::gil_scoped_acquire gil;
    stopped_ = PyErr_CheckSignals() != 0;
    return stopped_;
  }

  bool stopped() const { return stopped_; }

 private:
  bool stopped_ = false;
};

/// Hand decoded bytes to a Python callable, borrowing it rather than owning
/// it.
///
/// The decoder copies its sink internally and drops those copies while the
/// GIL is released. A captured py::object would move a refcount there, which
/// is fatal; a py::handle copies and dies touching nothing. The caller keeps
/// the one owning reference, and must outlive the call.
wl::streaming::ByteSink borrow_sink(const py::object& owner) {
  if (owner.is_none()) {
    return nullptr;
  }
  const py::handle borrowed = owner;
  return [borrowed](const wl::ByteVector& chunk) {
    const py::gil_scoped_acquire gil;
    borrowed(to_bytes(chunk));
  };
}

/// Reject a missing or non-callable sink before anything is built around it.
///
/// The decoder calls its sink unconditionally when bytes land, so a Receiver
/// without one is a std::bad_function_call waiting for its first decode.
py::object checked_callback(py::object on_bytes) {
  if (on_bytes.is_none()) {
    throw wl::ConfigError("Receiver needs on_bytes= to deliver decoded bytes to");
  }
  if (PyCallable_Check(on_bytes.ptr()) == 0) {
    throw wl::ConfigError("on_bytes must be callable");
  }
  return on_bytes;
}

wl::api::ModemOptions default_options() { return wl::api::ModemOptions{}; }

py::object tx_wrapper(const py::object& data, const wl::api::ModemOptions& options,
                      int tx_volume, const py::object& wav, const py::object& audio_output,
                      const py::object& ptt, bool tune) {
  wl::api::TxTarget target;
  if (!wav.is_none()) {
    target.wav_path = py::str(wav);
  }
  if (!audio_output.is_none()) {
    target.audio_output = py::str(audio_output);
    target.to_audio_device = true;
  }
  if (!ptt.is_none()) {
    target.ptt = py::str(ptt);
  }
  target.tune = tune;

  wl::ByteVector payload;
  if (!data.is_none()) {
    const auto buffer = data.cast<std::string>();
    payload.assign(buffer.begin(), buffer.end());
  } else if (!tune) {
    throw wl::ConfigError("tx() requires data= unless tune=True");
  }

  wl::dsp::Samples samples;
  StopFlag stop;
  {
    const py::gil_scoped_release release;
    bool sent = false;
    const wl::codec::ByteSource source = [&](wl::ByteVector& chunk) {
      if (sent) {
        return false;
      }
      chunk = payload;
      sent = true;
      return true;
    };
    samples = wl::api::tx(source, options, tx_volume, target,
                          [&stop] { return stop(); });
  }
  if (stop.stopped()) {
    // The modem has unwound and any device is closed; now let the pending
    // KeyboardInterrupt out.
    throw py::error_already_set();
  }

  // A sink was named, so the audio has already gone there and there is nothing
  // to hand back. Only the no-sink form returns the waveform.
  if (!target.wav_path.empty() || target.to_audio_device) {
    return py::none();
  }
  return to_numpy(samples);
}

py::object rx_wrapper(const py::object& samples, const wl::api::ModemOptions& options,
                      const py::object& wav, const py::object& audio_input,
                      const py::object& on_bytes) {
  const int sources = (samples.is_none() ? 0 : 1) + (wav.is_none() ? 0 : 1) +
                      (audio_input.is_none() ? 0 : 1);
  if (sources == 0) {
    throw wl::ConfigError("rx() requires one of samples=, wav=, audio_input=");
  }
  if (sources > 1) {
    throw wl::ConfigError("pass at most one of samples=, wav=, audio_input=");
  }

  wl::api::RxSource source;
  wl::dsp::Samples buffer;
  if (!samples.is_none()) {
    buffer = to_samples(samples.cast<FloatArray>());
    source.samples = &buffer;
  }
  if (!wav.is_none()) {
    source.wav_path = py::str(wav);
  }
  const bool live = !audio_input.is_none();
  if (live) {
    source.audio_input = py::str(audio_input);
    source.from_audio_device = true;
  }

  const wl::streaming::ByteSink sink = borrow_sink(on_bytes);
  wl::ByteVector decoded;
  StopFlag stop;
  {
    const py::gil_scoped_release release;
    decoded = wl::api::rx(source, options, sink, [&stop] { return stop(); });
  }
  if (stop.stopped()) {
    throw py::error_already_set();
  }

  // Live reception ends only when the caller interrupts it, and its bytes went
  // to the callback as they landed.
  if (live) {
    return py::none();
  }
  return to_bytes(decoded);
}

/// Streaming receiver: audio in, decoded bytes out through a callback.
///
/// Wraps the same decoder the CLI drives, so there is no second decode path to
/// keep in step with the first.
class Receiver {
 public:
  Receiver(const wl::api::ModemOptions& options, py::object on_bytes)
      : config_(wl::api::build_config(options)),
        options_(options),
        // Held before the decoder is built and destroyed after it, because
        // the decoder's sink borrows this reference for its whole life.
        on_bytes_(checked_callback(std::move(on_bytes))),
        decoder_(std::make_unique<wl::streaming::StreamingRxDecoder>(
            config_, borrow_sink(on_bytes_))) {}

  void push(const FloatArray& chunk) {
    const wl::dsp::Samples samples = to_samples(chunk);
    const Busy busy(*this);
    const py::gil_scoped_release release;
    decoder_->push(samples);
  }

  void drain() {
    const Busy busy(*this);
    const py::gil_scoped_release release;
    decoder_->drain();
  }

  /// Open an input device and decode until interrupted. Blocks.
  void listen(const std::string& audio_input) {
    // Built while the GIL is still held; the sink itself only borrows.
    const wl::streaming::ByteSink sink = borrow_sink(on_bytes_);
    StopFlag stop;
    {
      const Busy busy(*this);
      const py::gil_scoped_release release;
      wl::streaming::live_stream_decode(config_, audio_input, sink,
                                        [&stop] { return stop(); });
    }
    if (stop.stopped()) {
      throw py::error_already_set();
    }
  }

  int sample_rate() const { return decoder_->sample_rate(); }
  const wl::api::ModemOptions& options() const { return options_; }

 private:
  /// One thread in the decoder at a time.
  ///
  /// The decoder guards its audio queue but advances its cursor and streaming
  /// state outside that lock, so two threads in push/drain/listen would lose
  /// or duplicate bytes. Rejecting the second caller beats blocking it: a
  /// push waiting behind a listen would wait forever.
  class Busy {
   public:
    explicit Busy(Receiver& receiver) : lock_(receiver.in_use_, std::try_to_lock) {
      if (!lock_.owns_lock()) {
        throw wl::ConfigError("this Receiver is already in use by another thread");
      }
    }

   private:
    std::unique_lock<std::mutex> lock_;
  };

  wl::codec::ModemConfig config_;
  wl::api::ModemOptions options_;
  py::object on_bytes_;
  std::unique_ptr<wl::streaming::StreamingRxDecoder> decoder_;
  std::mutex in_use_;
};

}  // namespace

PYBIND11_MODULE(_core, module) {
  module.doc() = "C++ backend for the weaklink MFSK modem.";

  // Mirrors the reference's exception hierarchy so `except ConfigError` keeps
  // catching what it used to.
  static const py::exception<wl::WeaklinkError> base(module, "WeaklinkError", PyExc_RuntimeError);
  static const py::exception<wl::ConfigError> config(module, "ConfigError", base.ptr());
  static const py::exception<wl::NyquistError> nyquist(module, "NyquistError", config.ptr());
  static const py::exception<wl::EncodeError> encode(module, "EncodeError", base.ptr());
  static const py::exception<wl::PTTError> ptt(module, "PTTError", base.ptr());

  py::register_exception_translator([](std::exception_ptr pointer) {
    try {
      if (pointer) {
        std::rethrow_exception(pointer);
      }
    } catch (const wl::NyquistError& error) {
      py::set_error(nyquist, error.what());
    } catch (const wl::ConfigError& error) {
      py::set_error(config, error.what());
    } catch (const wl::EncodeError& error) {
      py::set_error(encode, error.what());
    } catch (const wl::PTTError& error) {
      py::set_error(ptt, error.what());
    } catch (const wl::WeaklinkError& error) {
      py::set_error(base, error.what());
    }
  });

  py::class_<wl::api::ModemOptions>(module, "ModemOptions",
                                    "Modem-layer parameters shared by tx and rx.\n\n"
                                    "Fields left as None fall back to the baud preset.")
      .def(py::init([](double baud, int num_tones, std::optional<int> rs_data_bytes,
                       std::optional<int> rs_parity_bytes, bool rs_crc_enabled,
                       std::optional<int> block_repeats, std::optional<int> sync_every_blocks,
                       std::optional<double> tone_spacing_hz) {
             wl::api::ModemOptions options;
             options.baud = baud;
             options.num_tones = num_tones;
             options.rs_data_bytes = rs_data_bytes;
             options.rs_parity_bytes = rs_parity_bytes;
             options.rs_crc_enabled = rs_crc_enabled;
             options.block_repeats = block_repeats;
             options.sync_every_blocks = sync_every_blocks;
             options.tone_spacing_hz = tone_spacing_hz;
             return options;
           }),
           py::kw_only(), py::arg("baud") = 300.0, py::arg("num_tones") = 4,
           py::arg("rs_data_bytes") = py::none(), py::arg("rs_parity_bytes") = py::none(),
           py::arg("rs_crc_enabled") = true, py::arg("block_repeats") = py::none(),
           py::arg("sync_every_blocks") = py::none(), py::arg("tone_spacing_hz") = py::none())
      .def_readwrite("baud", &wl::api::ModemOptions::baud)
      .def_readwrite("num_tones", &wl::api::ModemOptions::num_tones)
      .def_readwrite("rs_data_bytes", &wl::api::ModemOptions::rs_data_bytes)
      .def_readwrite("rs_parity_bytes", &wl::api::ModemOptions::rs_parity_bytes)
      .def_readwrite("rs_crc_enabled", &wl::api::ModemOptions::rs_crc_enabled)
      .def_readwrite("block_repeats", &wl::api::ModemOptions::block_repeats)
      .def_readwrite("sync_every_blocks", &wl::api::ModemOptions::sync_every_blocks)
      .def_readwrite("tone_spacing_hz", &wl::api::ModemOptions::tone_spacing_hz)
      .def("__repr__", [](const wl::api::ModemOptions& options) {
        return "ModemOptions(baud=" + std::to_string(options.baud) +
               ", num_tones=" + std::to_string(options.num_tones) + ")";
      });

  module.def("tx", &tx_wrapper, py::arg("data") = py::none(),
             py::arg("options") = default_options(), py::kw_only(), py::arg("tx_volume") = 100,
             py::arg("wav") = py::none(), py::arg("audio_output") = py::none(),
             py::arg("ptt") = py::none(), py::arg("tune") = false,
             "Encode data and dispatch it to the requested sink.\n\n"
             "With no sink, the encoded samples come back as a float32 array.");

  module.def("rx", &rx_wrapper, py::arg("samples") = py::none(),
             py::arg("options") = default_options(), py::kw_only(), py::arg("wav") = py::none(),
             py::arg("audio_input") = py::none(), py::arg("on_bytes") = py::none(),
             "Decode from the requested source.\n\n"
             "Returns the decoded bytes, or None for the live path, which ends\n"
             "only when interrupted.");

  py::class_<Receiver>(module, "Receiver",
                       "Streaming receiver: push audio in, decoded bytes come out.")
      .def(py::init<const wl::api::ModemOptions&, py::object>(),
           py::arg("options") = default_options(), py::arg("on_bytes"))
      .def("push", &Receiver::push, py::arg("samples"),
           "Feed a chunk of float32 mono audio at sample_rate.")
      .def("drain", &Receiver::drain,
           "Flush the tail once no more audio is coming.")
      .def("listen", &Receiver::listen, py::arg("audio_input") = std::string{},
           "Open an input device and decode until interrupted. Blocks.")
      .def_property_readonly("sample_rate", &Receiver::sample_rate,
                             "Sample rate the pushed audio has to be at.")
      .def_property_readonly("options", &Receiver::options);

  module.def(
      "sample_rate",
      [](const wl::api::ModemOptions& options) {
        return static_cast<int>(wl::api::build_config(options).waveform().sample_rate());
      },
      py::arg("options") = default_options(),
      "Sample rate these options resolve to, for setting up a capture.");

  module.def(
      "set_log_file",
      [](const std::string& path, bool debug) {
        wl::Logger::configure_file(path, debug ? wl::LogLevel::kDebug : wl::LogLevel::kInfo);
      },
      py::arg("path"), py::arg("debug") = false,
      "Send modem diagnostics to a log file. Nothing is written until this is\n"
      "called: a library must not scribble on a caller's stdout or stderr.");
}

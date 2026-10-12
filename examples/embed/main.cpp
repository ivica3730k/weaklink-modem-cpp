// Using weaklink-modem as a library rather than through its CLI: encode a
// payload to a WAV, read that WAV back, and compare. No audio device is opened,
// so this runs anywhere -- including CI.

#include <cstdio>
#include <string>

#include "weaklink/api.hpp"
#include "weaklink/exceptions.hpp"

using namespace weaklink;

int main(int argc, char** argv) {
  const std::string message = argc > 1 ? argv[1] : "the quick brown fox";
  const std::string wav_path = "embed-example.wav";

  api::ModemOptions options;
  options.baud = 300.0;
  options.num_tones = 4;

  const ByteVector payload(message.begin(), message.end());

  try {
    // A TxTarget with a wav_path writes the file; leaving the target empty
    // would return the samples in memory instead.
    api::TxTarget target;
    target.wav_path = wav_path;
    api::tx(payload, options, 100, target);

    api::RxSource source;
    source.wav_path = wav_path;
    const ByteVector decoded = api::rx(source, options);

    std::printf("sent    : %s\n", message.c_str());
    std::printf("received: %.*s\n", static_cast<int>(decoded.size()),
                reinterpret_cast<const char*>(decoded.data()));
    return decoded == payload ? 0 : 1;
  } catch (const WeaklinkError& error) {
    std::fprintf(stderr, "weaklink: %s\n", error.what());
    return 2;
  }
}

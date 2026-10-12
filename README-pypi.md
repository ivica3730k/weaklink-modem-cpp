# weaklink-modem

Streaming MFSK modem: bytes in → audio → bytes back. Reed-Solomon +
convolutional K=7 r=1/2 + soft Viterbi, per-block interleaver, soft-LLR
combining across block repeats. Modes: **OOK** and **2/4/8/16-FSK** at
**45 / 300 / 1200 baud**.

This is the C++ implementation, behind a Python API and a native CLI. It is
wire compatible with the pure-Python `weaklink-modem` it replaces: audio from
one decodes on the other, bit for bit.

---

## Install

```bash
pip install weaklink-modem
```

Wheels: Linux x86_64 / aarch64, macOS arm64 / x86_64, CPython 3.9–3.13. Other
platforms build from the sdist and need CMake 3.18+ and a C++17 compiler.

The wheel carries the `weaklink-modem` CLI as a native executable, not a
Python launcher, so there is no interpreter startup in front of it.

---

## Quickstart

```python
from weaklink.modem import ModemOptions, rx, tx

options = ModemOptions(baud=300, num_tones=4)

samples = tx(b"hello weaklink", options)      # float32 numpy array
print(rx(samples, options).rstrip(b"\x00"))   # b'hello weaklink'
```

Through a WAV:

```python
tx(b"hello", wav="hello.wav")
data = rx(wav="hello.wav")
```

From the shell, same binary the releases ship:

```bash
echo -n "hello weaklink" | weaklink-modem tx --modem-wav /tmp/hello.wav
weaklink-modem rx --modem-wav /tmp/hello.wav
```

**Both sides must agree on the mode.** There is no handshake: a receiver
running different `baud` or `num_tones` hears nothing and tells you nothing.
It is the first thing to check when a decode comes back empty.

Decoded bytes are NUL-padded to the block size, which is why the examples
strip them.

---

## Why this one

Both implementations encode the same 210-byte payload and decode the *same*
WAV, at 4 tones. Apple M3 Pro, release build against CPython 3.14 + NumPy,
CPU time as charged by `wait4`, minimum of five runs:

| Baud | Audio | Decode CPU (C++ / Python) | Decode load at real time | Speedup |
|---:|---:|---|---|---:|
| 45 | 164.1 s | 0.44 s / 2.86 s | 0.27% / 1.7% of one core | 7x |
| 300 | 12.4 s | 0.05 s / 1.33 s | 0.38% / 10.7% of one core | 28x |
| 1200 | 3.2 s | 0.02 s / 1.18 s | 0.66% / 36.6% of one core | 56x |

Decoding is the figure that matters, because a receiver has to keep up with
audio as it arrives. At 1200 baud the pure-Python implementation spends about
37% of a core to stay real time; this one spends under 1% — the difference
between needing a laptop and running on a Pi alongside everything else.

---

## Presets

The three baud rates are **presets**, not fixed configurations: every
parameter is overridable through `ModemOptions`, and both sides have to carry
the same overrides. Defaults are 4-FSK with RS(16,8) + CRC-32.

| Baud | Default tones | Bandwidth | Repeats | 13 B | 100 B | 1 kB |
|---:|---|---:|---:|---:|---:|---:|
| 45 | 1200 / 1400 / 1600 / 1800 Hz | 600 Hz | 4x | 26.3 s | 205.5 s | 32.9 min |
| 300 | 1050 / 1350 / 1650 / 1950 Hz | 900 Hz | 2x | 2.0 s | 15.5 s | 2.5 min |
| 1200 | 500 / 1700 / 2900 / 4100 Hz | 3600 Hz | 2x | 0.5 s | 3.9 s | 37.0 s |

Time on air is measured, at 18 kHz mono. Slower bauds are not merely slower:
they repeat each block more and spread it over a narrower band, which is what
buys their noise tolerance. Raising `block_repeats` buys a few more dB of
margin at proportional air time.

`num_tones=M` means **M frequencies to choose from per symbol**, not M playing
at once. One sinusoid is on air at any instant, hopping at the symbol clock,
so higher M carries log₂(M) bits per symbol at no cost in peak power.
`num_tones=1` is OOK: one carrier, symbol 0 silent.

---

## Streaming

Audio never crosses into Python. Either hand over samples as they arrive:

```python
from weaklink.modem import ModemOptions, Receiver

receiver = Receiver(ModemOptions(baud=300), on_bytes=lambda b: print(b, flush=True))
print(receiver.sample_rate)        # 18000 -- what your capture must produce

for chunk in my_audio_source():    # float32 mono, any chunk size
    receiver.push(chunk)
receiver.drain()                   # flush the tail; nothing more is coming
```

or name a device and let the modem open it, with no audio library on the
Python side at all:

```python
receiver.listen("default")         # blocks until Ctrl-C
```

Device hints take an index, a name substring, or a pulse identifier; an empty
hint means the OS default.

### Threads

A `Receiver` belongs to one thread. `push`, `drain` and `listen` refuse to run
concurrently on the same instance and raise `ConfigError` rather than let two
callers corrupt a decode. Use one `Receiver` per thread if you need several.

`on_bytes` runs on the decoder's thread, never the audio callback thread, and
always with the GIL held — ordinary Python work is fine inside it.

---

## Options

```python
ModemOptions(
    baud=300.0,              # 45, 300 or 1200
    num_tones=4,             # 1 (OOK), 2, 4, 8 or 16
    rs_data_bytes=None,      # None means the baud preset's value
    rs_parity_bytes=None,
    rs_crc_enabled=True,
    block_repeats=None,
    sync_every_blocks=None,
    tone_spacing_hz=None,
)
```

Not every combination fits: 16 tones at 1200 baud needs more bandwidth than
18 kHz allows, and raises `NyquistError`.

---

## Diagnostics

Nothing is written anywhere until you ask for it — a library has no business
writing to a caller's stdout:

```python
from weaklink.modem import set_log_file

set_log_file("modem.log", debug=True)
```

---

## Errors

`WeaklinkError` is the base. `ConfigError` (and its subclass `NyquistError`),
`EncodeError` and `PTTError` sit under it.

```python
from weaklink.modem import ConfigError, rx

try:
    rx()
except ConfigError as error:
    print(error)       # rx() requires one of samples=, wav=, audio_input=
```

---

## Source

<https://github.com/ivica3730k/weaklink-modem-cpp>

The C++ library is consumable on its own through CMake, via `find_package`,
`FetchContent` or `add_subdirectory`.

MIT licensed.

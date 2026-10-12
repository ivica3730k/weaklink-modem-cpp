# weaklink-modem

Streaming MFSK modem: bytes in, audio out, bytes back. Reed-Solomon +
convolutional K=7 r=1/2 + soft Viterbi + per-block interleaving, with soft-LLR
combining across block repeats. Modes: OOK and 2/4/8/16-FSK at 45 / 300 / 1200
baud.

This is the C++ implementation behind a Python API. It is wire compatible with
the pure-Python `weaklink-modem`: audio produced by one decodes on the other.

## Install

```bash
pip install weaklink-modem
```

Wheels are published for Linux (x86_64, aarch64) and macOS (arm64, x86_64) on
CPython 3.9 through 3.13. Other platforms build from the sdist and need CMake
and a C++17 compiler.

## Encode and decode in memory

```python
from weaklink.modem import ModemOptions, rx, tx

samples = tx(b"hello over audio", ModemOptions(baud=300, num_tones=4))
print(rx(samples, ModemOptions(baud=300, num_tones=4)).rstrip(b"\x00"))
```

`tx` hands back a `float32` numpy array. Decoded bytes come back padded with
NULs to the block size, which is why the example strips them.

## Through a WAV

```python
tx(b"hello", wav="message.wav")
data = rx(wav="message.wav")
```

## Streaming: push audio as it arrives

```python
from weaklink.modem import ModemOptions, Receiver

receiver = Receiver(ModemOptions(baud=300), on_bytes=lambda b: print(b, flush=True))
print(receiver.sample_rate)        # what your capture has to produce

for chunk in my_audio_source():    # float32 mono
    receiver.push(chunk)
receiver.drain()                   # flush the tail
```

## Streaming: let the modem own the device

```python
receiver = Receiver(ModemOptions(baud=300), on_bytes=print)
receiver.listen("default")         # blocks until Ctrl-C
```

No audio library needed on the Python side — PortAudio is built into the
wheel.

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

## Diagnostics

Nothing is written anywhere until you ask for it — a library has no business
writing to a caller's stdout:

```python
from weaklink.modem import set_log_file

set_log_file("modem.log", debug=True)
```

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

## Source

<https://github.com/ivica3730k/weaklink-modem-cpp>

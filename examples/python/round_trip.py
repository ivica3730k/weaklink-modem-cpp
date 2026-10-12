#!/usr/bin/env python3
"""Encode a payload to audio and decode it back, without touching a file.

The shortest thing that proves the install works.
"""

from weaklink.modem import ModemOptions, rx, tx

PAYLOAD = b"bytes in, audio out, bytes back"


def main() -> None:
    options = ModemOptions(baud=300, num_tones=4)

    samples = tx(PAYLOAD, options)
    seconds = samples.size / 18000
    print(f"encoded {len(PAYLOAD)} bytes -> {samples.size} samples ({seconds:.1f} s of audio)")

    # Blocks are a fixed size, so a short payload comes back NUL-padded.
    decoded = rx(samples, options).rstrip(b"\x00")
    print(f"decoded: {decoded.decode()}")
    assert decoded == PAYLOAD


if __name__ == "__main__":
    main()

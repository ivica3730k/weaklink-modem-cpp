#!/usr/bin/env python3
"""Feed audio to the decoder in pieces, the way a capture delivers it.

This is the interface to use when the audio comes from somewhere the modem
does not know about: a socket, a file being written, another library's
callback. Hand over float32 mono at ``receiver.sample_rate`` and decoded bytes
arrive through the callback as they land, not at the end.
"""

from weaklink.modem import ModemOptions, Receiver, tx

PAYLOAD = b"arriving in pieces, decoded as it lands"


def main() -> None:
    options = ModemOptions(baud=300, num_tones=4)
    samples = tx(PAYLOAD, options)

    received = bytearray()

    def on_bytes(chunk: bytes) -> None:
        # Called from the decoder's polling thread, never the audio callback
        # thread, and always with the GIL held.
        received.extend(chunk)
        print(f"  <- {len(chunk)} bytes")

    receiver = Receiver(options, on_bytes=on_bytes)
    print(f"pushing at {receiver.sample_rate} Hz")

    # A tenth of a second at a time, which is roughly what a live capture
    # hands over per callback.
    step = receiver.sample_rate // 10
    for start in range(0, samples.size, step):
        receiver.push(samples[start : start + step])

    # Nothing more is coming: flush whatever the tail still holds.
    receiver.drain()

    print(f"decoded: {bytes(received).rstrip(chr(0).encode()).decode()}")


if __name__ == "__main__":
    main()

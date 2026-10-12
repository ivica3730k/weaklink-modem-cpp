#!/usr/bin/env python3
"""Transmit and receive through real audio devices.

Nothing here imports an audio library: PortAudio is inside the extension, so
Python only names a device and the modem opens it.

    python live_audio.py rx            # listen on the default input
    python live_audio.py tx "hello"    # send on the default output

Device hints take the same syntax the CLI accepts: an index, a name
substring, or a pulse identifier. An empty hint means the OS default.
"""

import sys

from weaklink.modem import ModemOptions, Receiver, set_log_file, tx

OPTIONS = ModemOptions(baud=300, num_tones=4)


def receive(device: str) -> None:
    def on_bytes(chunk: bytes) -> None:
        sys.stdout.write(chunk.decode(errors="replace"))
        sys.stdout.flush()

    receiver = Receiver(OPTIONS, on_bytes=on_bytes)
    print(f"listening at {receiver.sample_rate} Hz -- Ctrl-C to stop", file=sys.stderr)
    try:
        # Blocks inside C++ with the GIL released. Ctrl-C still works: the
        # binding polls the interpreter for pending signals.
        receiver.listen(device)
    except KeyboardInterrupt:
        print("\nstopped", file=sys.stderr)


def transmit(message: str, device: str) -> None:
    print(f"sending {len(message)} bytes", file=sys.stderr)
    tx(message.encode(), OPTIONS, audio_output=device)


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in {"rx", "tx"}:
        print(__doc__)
        raise SystemExit(2)

    # Diagnostics go to a file or nowhere. stdout carries payload bytes.
    set_log_file("weaklink.log")

    if sys.argv[1] == "rx":
        receive(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        if len(sys.argv) < 3:
            raise SystemExit("tx needs a message")
        transmit(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")


if __name__ == "__main__":
    main()

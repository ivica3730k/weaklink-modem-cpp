"""Weaklink modem: MFSK + convolutional FEC + soft Viterbi, audio I/O.

A C++ backend behind the same API as the pure-Python ``weaklink.modem``. The
two are wire compatible, so audio produced by one decodes on the other.

Audio stays on the C++ side. Either hand over samples::

    rx = Receiver(ModemOptions(baud=300), on_bytes=print)
    rx.push(chunk)          # float32 mono at rx.sample_rate
    rx.drain()

or name a device and let the modem open it::

    rx.listen("default")    # blocks until Ctrl-C
"""

from weaklink.modem._core import (
    ConfigError,
    EncodeError,
    ModemOptions,
    NyquistError,
    PTTError,
    Receiver,
    WeaklinkError,
    rx,
    sample_rate,
    set_log_file,
    tx,
)

__all__ = [
    # Public API
    "tx",
    "rx",
    "Receiver",
    "sample_rate",
    "set_log_file",
    # Config objects
    "ModemOptions",
    # Exceptions
    "WeaklinkError",
    "ConfigError",
    "NyquistError",
    "EncodeError",
    "PTTError",
]

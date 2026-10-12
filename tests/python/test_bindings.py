"""Smoke tests for the weaklink.modem bindings.

These check the binding layer, not the modem: the C++ suite already covers the
signal chain. What matters here is that arguments cross the boundary intact,
that audio comes back as a usable array, and that failures arrive as the right
Python exception.
"""

from __future__ import annotations

import threading

import numpy as np
import pytest

from weaklink.modem import (
    ConfigError,
    ModemOptions,
    NyquistError,
    Receiver,
    WeaklinkError,
    rx,
    sample_rate,
    tx,
)

PAYLOAD = b"the quick brown fox jumps over the lazy dog"


def test_round_trip_in_memory():
    samples = tx(PAYLOAD)
    assert isinstance(samples, np.ndarray)
    assert samples.dtype == np.float32
    assert samples.size > 0
    # Trailing NULs are the block padding, not lost data.
    assert rx(samples).rstrip(b"\x00") == PAYLOAD


def test_round_trip_through_a_wav(tmp_path):
    wav = tmp_path / "message.wav"
    assert tx(PAYLOAD, wav=str(wav)) is None
    assert wav.exists()
    assert rx(wav=str(wav)).rstrip(b"\x00") == PAYLOAD


@pytest.mark.parametrize(
    "options",
    [
        ModemOptions(baud=45, num_tones=4),
        ModemOptions(baud=300, num_tones=8),
        ModemOptions(baud=1200, num_tones=8),
    ],
    ids=["45/4", "300/8", "1200/8"],
)
def test_round_trip_across_modes(options):
    assert rx(tx(PAYLOAD, options), options).rstrip(b"\x00") == PAYLOAD


def test_options_reach_the_modem():
    # Two modes produce different amounts of audio for the same payload, which
    # is the cheapest proof the options are not being silently ignored.
    slow = tx(PAYLOAD, ModemOptions(baud=45)).size
    fast = tx(PAYLOAD, ModemOptions(baud=1200)).size
    assert slow > fast


def test_receiver_streams_in_chunks():
    samples = tx(PAYLOAD)
    received = bytearray()

    receiver = Receiver(ModemOptions(), on_bytes=received.extend)
    assert receiver.sample_rate == sample_rate()

    step = receiver.sample_rate // 10
    for start in range(0, samples.size, step):
        receiver.push(samples[start : start + step])
    receiver.drain()

    assert bytes(received).rstrip(b"\x00") == PAYLOAD


def test_receiver_accepts_a_wider_dtype():
    # float64 has to be converted rather than reinterpreted, or the decoder
    # reads half a sample at a time.
    samples = tx(PAYLOAD)
    received = bytearray()
    receiver = Receiver(ModemOptions(), on_bytes=received.extend)
    receiver.push(np.asarray(samples, dtype=np.float64))
    receiver.drain()
    assert bytes(received).rstrip(b"\x00") == PAYLOAD


def test_receiver_accepts_a_strided_view():
    # A view with a gap between samples carries the right audio at the wrong
    # stride. Reading it as contiguous would decode interleaved padding.
    samples = tx(PAYLOAD)
    padded = np.zeros(samples.size * 2, dtype=np.float32)
    padded[::2] = samples
    strided = padded[::2]
    assert not strided.flags["C_CONTIGUOUS"]

    received = bytearray()
    receiver = Receiver(ModemOptions(), on_bytes=received.extend)
    receiver.push(strided)
    receiver.drain()
    assert bytes(received).rstrip(b"\x00") == PAYLOAD


def test_receiver_requires_a_callback():
    # The decoder calls its sink unconditionally; without one the first
    # decoded block would take the interpreter down.
    with pytest.raises(ConfigError, match="on_bytes"):
        Receiver(ModemOptions(), on_bytes=None)
    with pytest.raises(ConfigError, match="callable"):
        Receiver(ModemOptions(), on_bytes="not callable")


def test_receiver_rejects_overlapping_calls():
    # The decoder advances its cursor outside the lock that guards its audio
    # queue, so two threads inside it would lose or duplicate bytes. The
    # second caller is turned away rather than left to block.
    samples = tx(PAYLOAD)
    entered = threading.Event()
    rejected: list[Exception] = []
    release = threading.Event()

    def slow_callback(chunk: bytes) -> None:
        entered.set()
        release.wait(timeout=5)

    blocking = Receiver(ModemOptions(), on_bytes=slow_callback)

    def feed() -> None:
        blocking.push(samples)
        blocking.drain()

    worker = threading.Thread(target=feed, daemon=True)
    worker.start()
    try:
        if entered.wait(timeout=5):
            try:
                blocking.push(samples)
            except ConfigError as error:
                rejected.append(error)
    finally:
        release.set()
        worker.join(timeout=10)

    assert rejected, "a second thread was allowed into the same Receiver"
    assert "already in use" in str(rejected[0])


def test_rx_rejects_no_source():
    with pytest.raises(ConfigError, match="requires one of"):
        rx()


def test_rx_rejects_two_sources():
    with pytest.raises(ConfigError, match="at most one"):
        rx(np.zeros(16, dtype=np.float32), wav="unused.wav")


def test_tx_rejects_no_data():
    with pytest.raises(ConfigError, match="requires data"):
        tx()


def test_config_error_is_a_weaklink_error():
    # The hierarchy is what lets callers catch broadly, so it has to survive
    # the trip across the binding.
    assert issubclass(ConfigError, WeaklinkError)
    with pytest.raises(WeaklinkError):
        rx()


def test_unsupported_mode_raises_config_error():
    with pytest.raises(WeaklinkError):
        tx(PAYLOAD, ModemOptions(num_tones=3))


def test_mode_over_nyquist_raises_nyquist_error():
    # 16 tones at 1200 baud does not fit under half the sample rate. The
    # subclass has to survive the binding, not collapse into ConfigError.
    with pytest.raises(NyquistError, match="Nyquist"):
        tx(PAYLOAD, ModemOptions(baud=1200, num_tones=16))
    assert issubclass(NyquistError, ConfigError)


def test_missing_wav_raises_rather_than_crashing():
    with pytest.raises(WeaklinkError):
        rx(wav="no-such-file.wav")


def test_samples_must_be_one_dimensional():
    with pytest.raises(ConfigError, match="one-dimensional"):
        rx(np.zeros((4, 4), dtype=np.float32))

"""Sample-free instrumental synthesis from an explicit, original symbolic score.

This module accepts no recordings, soundfonts, MIDI files or reference melodies.
Its caller supplies only duration, a tonal centre and a stable random seed.
"""
from dataclasses import dataclass, asdict

import numpy as np
from scipy.signal import lfilter

RATE = 48000


@dataclass(frozen=True)
class Note:
    instrument: str
    frame: int
    duration: int
    midi: int
    gain: float
    pan: float


def _sound(note, seed):
    """Modal percussion, additive plucks and a quiet breath flute; no samples."""
    n = note.duration
    t = np.arange(n, dtype=np.float64) / RATE
    hz = 440 * 2 ** ((note.midi - 69) / 12)
    rng = np.random.default_rng(seed)
    if note.instrument == "pluck":
        signal = np.zeros(n)
        for k in range(1, 11):
            signal += np.sin(2 * np.pi * hz * k * (1 + .00008 * k * k) * t) * np.exp(-t * (2.4 + k * .65)) / k ** 1.55
        signal *= 1 - np.exp(-t * 180)
    elif note.instrument == "flute":
        phase = 2 * np.pi * hz * t + .012 * np.sin(2 * np.pi * 4.3 * t)
        signal = np.sin(phase) + .13 * np.sin(2 * phase) + .035 * np.sin(3 * phase)
        signal += .012 * lfilter([.1], [1, -.9], rng.normal(size=n))
        window = np.sin(np.pi * np.arange(n) / max(n - 1, 1))
        signal *= np.clip(window, 0, 1) ** 1.4
    elif note.instrument == "drum":
        phase = 2 * np.pi * (hz * t + hz * .011 * (1 - np.exp(-t * 35)))
        signal = (np.sin(phase) + .12 * np.sin(1.53 * phase)) * np.exp(-t * 16)
        signal += .035 * rng.normal(size=n) * np.exp(-t * 80)
    elif note.instrument == "wood":
        signal = (np.sin(2 * np.pi * 880 * t) + .38 * np.sin(2 * np.pi * 1427 * t)) * np.exp(-t * 65)
    elif note.instrument == "gong":
        signal = np.zeros(n)
        for k, ratio in enumerate([1, 1.47, 2.09, 2.73, 3.91, 5.11]):
            signal += np.sin(2 * np.pi * hz * ratio * (t + .00015 * np.sin(2 * np.pi * 3 * t))) * np.exp(-t * (1.5 + k * .7)) / (k + 1) ** 1.4
        signal *= 1 - np.exp(-t * 500)
    else:
        raise ValueError(note.instrument)
    # Every sound starts and ends at zero; tails are composed inside the clip.
    fade = min(240, n // 4)
    signal[:fade] *= np.linspace(0, 1, fade)
    signal[-fade:] *= np.linspace(1, 0, fade)
    return signal.astype(np.float32) * note.gain


def compose(frames, *, seed, tonic=62, scene="gentle", loop=False):
    if frames <= 0:
        raise ValueError("Music duration must be positive")
    duration = frames / RATE
    beat = 60 / (84 if scene == "gentle" else 76)
    notes = []

    def add(instrument, second, length, midi, gain, pan=0):
        start = round(second * RATE)
        count = min(round(length * RATE), frames - start)
        if start >= 0 and count >= 480:
            notes.append(Note(instrument, start, count, midi, gain, pan))

    # Newly authored pentatonic figures. No event is transcribed from the old
    # accompaniment. Sparse fifths avoid fighting the retained free-rhythm song.
    figures = [[0, 7, 2, 9], [4, 2, 7, 0], [9, 7, 4, 2], [2, 4, 0, 7]]
    for bar, start in enumerate(np.arange(.08, max(.09, duration - .3), beat * 4)):
        if scene == "close":
            break
        figure = figures[(bar + seed) % len(figures)]
        add("pluck", start, min(2.2, beat * 3), tonic - 12, .042, -.24)
        for i, degree in enumerate(figure):
            add("pluck", start + beat * (i + .5), 1.8, tonic + degree, .026 if i % 2 else .035, .3)
        add("drum", start, .38, 43 if scene == "gentle" else 40, .042)
        add("wood", start + beat * 2, .12, 81, .016, -.2)
        if bar % 4 == 0:
            add("gong", start, min(2.8, duration - start), tonic - 7, .022, .05)
        if scene == "instrumental" and bar % 2 == 0:
            for i, degree in enumerate([7, 9, 4, 2]):
                add("flute", start + beat * (i + .2), beat * .85, tonic + 12 + degree, .021, -.1)
    if scene == "close":
        add("gong", .015, duration - .015, tonic - 7, .20)
        add("drum", .015, min(.4, duration - .015), 40, .12)
    output = np.zeros((frames, 2), dtype=np.float32)
    for index, note in enumerate(notes):
        signal = _sound(note, seed + index * 313)
        # Pan conserves centre energy; small room taps are entirely synthetic.
        gains = np.sqrt(np.array([1 - note.pan, 1 + note.pan]) / 2)
        output[note.frame:note.frame + note.duration] += signal[:, None] * gains
        for delay, wet in [(.031, .10), (.057, .06)]:
            start = note.frame + round(delay * RATE)
            count = min(len(signal), frames - start)
            if count > 0:
                output[start:start + count] += signal[:count, None] * gains[::-1] * wet
    if loop:
        # Circularly fold a short tail and make the boundary amplitude continuous.
        fade = min(round(.04 * RATE), frames // 8)
        output[:fade] *= np.linspace(0, 1, fade)[:, None]
        output[-fade:] *= np.linspace(1, 0, fade)[:, None]
    else:
        fade = min(round(.16 * RATE), frames // 4)
        output[:fade] *= np.linspace(0, 1, fade)[:, None]
        output[-fade:] *= np.linspace(1, 0, fade)[:, None]
    # Singing stays in front; exposed instrumental passages match speech level.
    master_gain = 7.0 if scene == "instrumental" else 1.0 if scene == "close" else 3.0
    output *= master_gain
    if not np.isfinite(output).all() or np.abs(output).max() >= .8:
        raise ValueError("Invalid synthesized accompaniment")
    return output, dict(seed=seed, sample_rate_hz=RATE, frames=frames, tonic_midi=tonic,
        scene=scene, external_audio_inputs=[], instruments=["additive pluck", "modal drum", "modal gong", "wood block", "breath flute"],
        events=[asdict(n) for n in notes], loop=loop, master_gain=master_gain)

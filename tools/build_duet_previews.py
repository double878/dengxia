"""Build review-only original opera-style backing; never installs game assets.

No external instruments, recordings, MIDI or reference melodies enter compose().
Existing vocal PCM is used only in the final additive preview mix.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import lfilter

from compose_original_accompaniment import Note, RATE, _sound


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8", newline="\n")


def bowed(note, seed):
    """Additive bowed-string approximation; not a recording of a jinghu."""
    n = note.duration
    t = np.arange(n) / RATE
    hz = 440 * 2 ** ((note.midi - 69) / 12)
    # Small scoop at the onset and delayed vibrato model a light bowed attack.
    cents = -36 * np.exp(-t / .045)
    cents += 13 * np.minimum(t / .18, 1) * np.sin(2 * np.pi * 5.1 * t)
    phase = np.cumsum(2 * np.pi * hz * 2 ** (cents / 1200) / RATE)
    signal = np.zeros(n)
    for k in range(1, min(30, int(19000 / hz))):
        # Bright nasal partials; no samples or nonlinear clipping.
        body = .5 + 1.5 * np.exp(-((hz * k - 1700) / 850) ** 2)
        signal += np.sin(k * phase) * body / k ** 1.12
    signal /= 2.5
    noise = np.random.default_rng(seed).normal(size=n)
    signal += .015 * lfilter([1, -1], [1, -.6], noise)
    envelope = (1 - np.exp(-t / .025)) * np.minimum((n / RATE - t) / .07, 1)
    signal *= np.clip(envelope, 0, 1) * note.gain
    return signal.astype(np.float32)


def cymbal(note, seed):
    t = np.arange(note.duration) / RATE
    signal = np.zeros(len(t))
    for k, ratio in enumerate([1, 1.38, 1.91, 2.57, 3.62, 4.93, 6.89]):
        signal += np.sin(2 * np.pi * 420 * ratio * t) / (k + 1) ** .6
    noise = np.random.default_rng(seed).normal(size=len(t))
    signal += .15 * lfilter([1, -1], [1, -.3], noise)
    signal *= np.exp(-t * 7) * (1 - np.exp(-t * 900)) * note.gain
    signal[-min(240, len(t)):] *= np.linspace(1, 0, min(240, len(t)))
    return signal.astype(np.float32)


def compose(frames, act):
    """Explicit authored pentatonic gestures, sparse under the retained voice."""
    duration = frames / RATE
    beat = 60 / (82 if act == 1 else 90)
    tonic = 65 if act == 1 else 62
    notes = []

    def add(inst, at, length, midi, gain, pan=0):
        start = round(at * RATE)
        count = min(round(length * RATE), frames - start)
        if 0 <= start < frames and count >= 480:
            notes.append(Note(inst, start, count, int(midi), gain, pan))

    # These are new motifs. The composer never examines the vocal melody.
    phrases = [
        [(0, 0, .8), (1, 2, .4), (1.5, 7, .7), (2.5, 4, 1.0)],
        [(0, 9, 1.2), (1.5, 7, .5), (2.5, 2, 1.0)],
        [(.5, 4, .6), (1.5, 2, .7), (3, 0, .8)],
        [(0, 7, 1.1), (1.5, 9, .45), (2, 7, .45), (3, 2, .8)],
        [(.5, 2, .5), (1.5, 4, 1), (3, 7, .8)],
        [(0, 9, .8), (1.5, 4, .5), (2.5, 2, .5), (3.25, 0, .65)],
    ]
    bar_starts = np.arange(.06, duration - .35, beat * 4)
    for bar, at in enumerate(bar_starts):
        progress = at / duration
        uneasy = max(0, (progress - .48) / .52) if act == 2 else 0
        # Low open fifths and light plucks leave room for the complete vocals.
        add("pluck", at, 2.2, tonic - 12, .09, -.3)
        if bar % 2 == 0:
            add("pluck", at + beat * 2, 1.6, tonic - 5, .055, -.3)
        for tick, degree in enumerate([0, 7, 2, 7]):
            # The hall's latter half gradually thins the celebratory pulse.
            if uneasy > .65 and tick in [1, 3]:
                continue
            add("pluck", at + beat * (tick + .5), 1.1,
                tonic + degree, .05 * (1 - .3 * uneasy), .28)
        add("drum", at, .3, 48, .04 + .015 * uneasy)
        add("wood", at + beat * 2, .11, 81, .014, -.12)
        if act == 2 and progress < .5 and bar % 2 == 0:
            add("cymbal", at + beat * 3, .75, 60, .018, .15)
        if bar % 4 == 0:
            add("gong", at, 2.6, tonic - 12, .025 + uneasy * .03)
        # A different phrase every bar; alternate bowed responses and breath.
        for offset, degree, length in phrases[(bar + act) % len(phrases)]:
            if act == 2 and degree in [4, 9] and progress > .45:
                degree -= 1 if degree == 4 else 2
            inst = "bowed" if bar % 3 != 2 else "flute"
            add(inst, at + beat * offset, beat * length,
                tonic + degree + (12 if inst == "flute" else 0),
                .032 if inst == "bowed" else .025, -.12)
        if uneasy > .3:
            add("bowed", at + beat * 1.25, beat * 2.2,
                tonic - 12, .022 * uneasy, .12)
    output = np.zeros((frames, 2), np.float32)
    for index, note in enumerate(notes):
        seed = 2026102200 + act * 1000 + index
        renderer = bowed if note.instrument == "bowed" else cymbal if note.instrument == "cymbal" else _sound
        signal = renderer(note, seed)
        gain = np.sqrt(np.array([1 - note.pan, 1 + note.pan]) / 2)
        output[note.frame:note.frame + note.duration] += signal[:, None] * gain
        for delay, wet in [(0.029, .09), (.053, .055)]:
            start = note.frame + round(delay * RATE)
            count = min(len(signal), frames - start)
            if count > 0:
                output[start:start + count] += signal[:count, None] * gain[::-1] * wet
    fade = min(9600, frames // 4)
    output[:fade] *= np.linspace(0, 1, fade)[:, None]
    output[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return output, dict(act=act, frames=frames, sample_rate_hz=RATE,
                        tempo_bpm=60 / beat, tonic_midi=tonic,
                        instruments=["synthetic bowed string", "additive pluck", "breath flute",
                                     "modal gong", "modal drum", "wood", "modal cymbal"],
                        external_audio_inputs=[], events=[asdict(note) for note in notes])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    batch = args.batch.resolve()
    batch.mkdir(parents=True, exist_ok=True)
    report = dict(version=1, status="preview_pending_user_listening", game_assets_installed=False,
                  tools={p: sha(root / "tools" / p) for p in
                         ["build_duet_previews.py", "compose_original_accompaniment.py"]}, acts=[])
    provenance = json.loads((root / "assets/audio/original-audio-sources.json").read_text(encoding="utf-8"))
    for act, folder, region_id in [(1, "act1-natural", "act1"),
                                    (2, "act2-hall", "act2-hall")]:
        config = json.loads((root / "assets/audio" / folder / "score.json").read_text(encoding="utf-8"))
        if config.get("background_music") is not False:
            raise ValueError("This preview requires the current clean-vocal master")
        region = next(r for r in provenance["replaced_regions"][region_id] if r["name"] == "singing")
        start, count = region["start_frame"], region["end_frame"] - region["start_frame"]
        source = root / "assets/audio" / folder / "main.wav"
        master, rate = sf.read(source, dtype="float32", always_2d=True)
        if rate != RATE or master.shape[1] != 2 or start + count > len(master):
            raise ValueError(f"Unexpected master format/region: {source}")
        # The current no-backing master is the exact shipped vocal baseline.
        vocal = master[start:start + count].copy()
        backing, score = compose(count, act)
        # Backing fixed RMS sits below the unmodified voice, without ducking it.
        target = 10 ** (-30 / 20)
        gain = target / max(float(np.sqrt(np.mean(backing ** 2))), 1e-9)
        backing *= gain
        mix = vocal + backing
        assets = {}
        for name, audio in [("backing", backing), ("with-vocals", mix)]:
            if not np.isfinite(audio).all() or np.abs(audio).max() >= .98:
                raise ValueError(f"Invalid audio: act{act}-{name}")
            path = batch / f"act{act}-{name}.wav"
            sf.write(path, audio, RATE, subtype="PCM_16")
            assets[name] = dict(path=str(path), sha256=sha(path), frames=len(audio),
                                peak=float(np.abs(audio).max()))
        score.update(master_gain=gain, source_sha256=sha(source),
                     vocal_region=dict(start_frame=start, frames=count,
                                       pcm_sha256=hashlib.sha256((vocal * 32768).astype('<i2').tobytes()).hexdigest()))
        dump(batch / f"act{act}-composition.json", score)
        report["acts"].append(dict(act=act, duration_seconds=count / RATE, source=str(source),
                                   source_sha256=sha(source), assets=assets,
                                   human_listening_verified=False))
    dump(batch / "duet-preview-manifest.json", report)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()

"""Create a review-only, pitch-following accompaniment for the first two sung groups.

Only the current retained vocal is read. Instrumental sounds are synthesized;
no previous accompaniment, recording, soundfont or external score is imported.
"""
import argparse
import hashlib
import json
from pathlib import Path
import wave

import librosa
import numpy as np
from scipy.ndimage import gaussian_filter1d, median_filter
from scipy.signal import lfilter, resample_poly
import soundfile as sf

from compose_original_accompaniment import Note, RATE, _sound

ROOT = Path(__file__).resolve().parents[1]
ANALYSIS_RATE, HOP = 16000, 160
FRAMES = 1082400  # 22.55 seconds: the complete Xu group, then the complete Bai group.
ROLE_CHANGE = 11.25


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def wav(path, data):
    with wave.open(str(path), "wb") as output:
        output.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(np.asarray(data, dtype="<i2").tobytes())


def pcm(path):
    with wave.open(str(path), "rb") as source:
        assert source.getparams()[:3] == (2, 2, RATE)
        return np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").reshape(-1, 2)


def analyze(vocal, batch, source_digest):
    cache = batch / "pitch-analysis.npz"
    if cache.exists():
        saved = np.load(cache)
        assert str(saved["source_digest"]) == source_digest, "Pitch cache belongs to another input"
        return {key: saved[key] for key in ["time", "f0", "voiced", "probability", "rms", "onsets"]}
    mono = resample_poly(vocal.mean(axis=1), 1, 3)
    print("Analyzing retained vocal pitch and onsets", flush=True)
    f0, voiced, probability = librosa.pyin(
        mono, sr=ANALYSIS_RATE, fmin=90, fmax=1000, frame_length=1024,
        hop_length=HOP, n_thresholds=48, resolution=.1, max_transition_rate=22,
    )
    rms = librosa.feature.rms(y=mono, frame_length=1024, hop_length=HOP)[0]
    voiced &= (probability >= .45) & (rms > .009)
    assert voiced.mean() > .35, "Insufficient reliable sung pitch; do not compose from guesses"
    times = librosa.times_like(f0, sr=ANALYSIS_RATE, hop_length=HOP)
    onsets = librosa.onset.onset_detect(
        y=mono, sr=ANALYSIS_RATE, hop_length=HOP, units="time", wait=36, delta=.14,
    )
    result = dict(time=times, f0=f0, voiced=voiced, probability=probability, rms=rms, onsets=onsets)
    np.savez_compressed(cache, source_digest=source_digest, **result)
    return result


def bowed_follow(analysis):
    """A continuous harmonic bow model follows the sung contour and its ornaments."""
    times, valid = analysis["time"], analysis["voiced"]
    midi = 69 + 12 * np.log2(analysis["f0"][valid] / 440)
    contour = np.interp(times, times[valid], midi)
    contour = gaussian_filter1d(median_filter(contour, size=3), 1.25)
    # Upper octave under Xu, unison under Bai: both follow the same pitch class.
    contour += np.where(times < ROLE_CHANGE, 12, 0)
    sample_times = np.arange(FRAMES) / RATE
    frequency = 440 * 2 ** ((np.interp(sample_times - .035, times, contour) - 69) / 12)
    phase = 2 * np.pi * np.cumsum(frequency) / RATE
    tone = np.zeros(FRAMES)
    for harmonic in range(1, 25):
        hz = harmonic * frequency
        body = .55 + .65 * np.exp(-((hz - 1450) / 850) ** 2)
        body += .25 * np.exp(-((hz - 2800) / 1100) ** 2)
        amplitude = body / harmonic ** 1.3 * np.exp(-(hz / 6500) ** 2)
        tone += np.sin(harmonic * phase + .08 / harmonic) * amplitude
    rng = np.random.default_rng(2026102241)
    noise = lfilter([1, -1], [1, -.55], rng.normal(size=FRAMES))
    tone += noise * .009
    # Retain breath gaps rather than holding interpolated pitches through rests.
    gate = gaussian_filter1d(valid.astype(float), 2.0)
    envelope = np.interp(sample_times - .035, times, gate, left=0, right=0)
    energy = np.interp(sample_times, times, analysis["rms"])
    envelope *= np.clip(energy / max(np.median(analysis["rms"][valid]), .01), .2, 1.5) ** .25
    tone *= envelope
    stereo = np.stack([tone * .74, tone * .67], axis=1)
    # Small early reflections on the instrument only. Original vocal stays dry.
    for delay, gain in [(1296, .07), (2832, .04)]:
        stereo[delay:] += np.stack([tone[:-delay] * .67, tone[:-delay] * .74], axis=1) * gain
    return stereo, frequency


def pluck(hz, duration, seed):
    """Two gently detuned modal strings approximate a light round lute."""
    time = np.arange(duration) / RATE
    signal = np.zeros(duration)
    rng = np.random.default_rng(seed)
    for detune in [-.0009, .0012]:
        for harmonic in range(1, 18):
            frequency = hz * harmonic * (1 + detune + .000015 * harmonic ** 2)
            if frequency >= RATE * .45:
                continue
            decay = np.exp(-time * (2.5 + harmonic * .55))
            signal += np.cos(2 * np.pi * frequency * time + .11 * harmonic) * decay / harmonic ** 1.18
    signal += .035 * rng.normal(size=duration) * np.exp(-time * 180)
    signal *= 1 - np.exp(-time * 1100)
    fade = min(960, duration // 4)
    signal[-fade:] *= np.linspace(1, 0, fade)
    return signal


def accents(analysis):
    plucked, percussion = np.zeros((FRAMES, 2)), np.zeros((FRAMES, 2))
    notes = []
    last = -1
    for onset in analysis["onsets"]:
        if onset - last < .5 or onset > FRAMES / RATE - .35:
            continue
        window = (analysis["time"] >= onset + .04) & (analysis["time"] <= onset + .24)
        window &= analysis["voiced"]
        if window.sum() < 3:
            continue
        sung_hz = float(np.median(analysis["f0"][window]))
        midi = round(float(librosa.hz_to_midi(sung_hz))) - 12
        while midi < 45:
            midi += 12
        while midi > 67:
            midi -= 12
        at = round((float(onset) + .015) * RATE)
        duration = min(round(1.25 * RATE), FRAMES - at)
        note = pluck(float(librosa.midi_to_hz(midi)), duration, 2026102242 + len(notes))
        plucked[at:at + duration] += note[:, None] * np.array([.64, .80])
        # Light accents at phrase entries; no independent rigid metronome.
        if not notes or onset - last > 1.05 or abs(onset - ROLE_CHANGE) < .3:
            count = min(round(.16 * RATE), FRAMES - at)
            hit = _sound(Note("wood", at, count, 81, .25, 0), 2026102243 + len(notes))
            percussion[at:at + count] += hit[:, None]
        notes.append(dict(at_s=float(onset), midi=midi, duration_s=duration / RATE))
        last = onset
    assert len(notes) >= 10, "Too few reliable vocal attacks for the plucked part"
    return plucked, percussion, notes


def set_rms(signal, target):
    level = float(np.sqrt(np.mean(signal ** 2)))
    assert level > 1e-8 and np.isfinite(signal).all()
    return signal * target / level


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--analyze-only", action="store_true")
    args = parser.parse_args()
    batch = args.batch.resolve()
    batch.mkdir(parents=True, exist_ok=True)
    assert not (batch / "preview-manifest.json").exists(), "Use a new batch; previous preview is immutable"
    audio_root = ROOT / "assets/audio"
    baseline = {str(path.relative_to(audio_root)): sha(path) for path in audio_root.rglob("*")
                if path.is_file() and path.suffix in [".wav", ".json"]}
    manifest = json.loads((audio_root / "original-audio-sources.json").read_text(encoding="utf-8"))
    region = next(row for row in manifest["replaced_regions"]["act1"] if row["name"] == "singing")
    master = audio_root / "act1-natural/main.wav"
    assert sha(master) == manifest["outputs"]["act1-natural/main.wav"]
    source = pcm(master)[region["start_frame"]:region["end_frame"]]
    assert hashlib.sha256(source.tobytes()).hexdigest() == manifest["music"]["act1-duet"]["pcm_sha256"]
    original = source[:FRAMES].copy()
    vocal = original.astype(np.float64) / 32768
    digest = hashlib.sha256(original.tobytes()).hexdigest()
    analysis = analyze(vocal, batch, digest)
    summary = dict(voiced_fraction=float(analysis["voiced"].mean()),
                   pitch_hz_percentiles=np.percentile(analysis["f0"][analysis["voiced"]], [5, 50, 95]).tolist(),
                   onset_count=len(analysis["onsets"]), duration_s=FRAMES / RATE)
    print(json.dumps(summary), flush=True)
    if args.analyze_only:
        return
    bowed, _ = bowed_follow(analysis)
    plucked, percussion, notes = accents(analysis)
    stems = dict(bowed=set_rms(bowed, .024), plucked=set_rms(plucked, .010),
                 percussion=set_rms(percussion, .0014))
    backing = sum(stems.values())
    # A gentle level reduction acts on the accompaniment alone under loud syllables.
    envelope = np.interp(np.arange(FRAMES) / RATE, analysis["time"], analysis["rms"])
    duck = 1 / (1 + np.clip(envelope - .07, 0, .25) * 2)
    fade = np.ones(FRAMES)
    fade[:4800] = np.linspace(0, 1, 4800)
    fade[-7200:] = np.linspace(1, 0, 7200)
    backing *= (duck * fade)[:, None]
    assert np.isfinite(backing).all() and np.max(np.abs(backing)) < .5
    backing_pcm = np.rint(backing * 32768).astype("<i2")
    mixed = original.astype(np.int32) + backing_pcm.astype(np.int32)
    assert np.max(np.abs(mixed)) < round(.98 * 32768), "Reject clipping; never normalize the original voice"
    wav(batch / "act1-original-vocals.wav", original)
    wav(batch / "act1-accompaniment.wav", backing_pcm)
    wav(batch / "act1-with-accompaniment.wav", mixed)
    for name, signal in stems.items():
        wav(batch / (name + ".wav"), np.rint(signal * 32768))
    outputs = {path.name: dict(sha256=sha(path), frames=len(pcm(path)),
                              peak=float(np.abs(pcm(path).astype(float)).max() / 32768))
               for path in batch.glob("*.wav")}
    assert np.array_equal(pcm(batch / "act1-original-vocals.wav"), original)
    assert np.array_equal(pcm(batch / "act1-with-accompaniment.wav").astype(np.int32),
                          original.astype(np.int32) + pcm(batch / "act1-accompaniment.wav").astype(np.int32))
    assert all(sha(audio_root / name) == value for name, value in baseline.items())
    report = dict(status="preview_pending_user_listening", game_assets_installed=False,
                  human_listening_verified=False, source=str(master), source_sha256=sha(master),
                  vocal_start_frame=region["start_frame"], vocal_frames=FRAMES,
                  vocal_pcm_sha256=digest, original_vocal_pcm_preserved=True,
                  additive_mix_verified=True, game_audio_unchanged=True, game_audio_baseline=baseline,
                  instruments="Synthesized bow, round-lute plucks and sparse wood accents; not recorded jinghu/yueqin",
                  external_instrumental_audio_inputs=[], pitch_follower_delay_ms=35,
                  role_change_s=ROLE_CHANGE, analysis=summary, plucked_notes=notes,
                  tool_sha256=sha(Path(__file__)), synthesizer_sha256=sha(ROOT / "tools/compose_original_accompaniment.py"),
                  analysis_sha256=sha(batch / "pitch-analysis.npz"), outputs=outputs)
    dump(batch / "preview-manifest.json", report)
    print(json.dumps({key: value for key, value in report.items() if key not in ["game_audio_baseline", "plucked_notes"]}), flush=True)


if __name__ == "__main__":
    main()

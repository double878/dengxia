"""Audit audio delivery against the immutable baseline, stems and symbolic score.

Requires local production inputs in --batch. Does not install or change assets.
The opening-specific audit additionally checks subtitles, turn gaps and imports.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import wave

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

from compose_original_accompaniment import compose


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf8"))


def pcm(path):
    with wave.open(str(path), "rb") as src:
        assert src.getparams()[:3] == (2, 2, 48000), path
        return src.readframes(src.getnframes())


def quantize(data):
    buffer = io.BytesIO()
    sf.write(buffer, data, 48000, subtype="PCM_16", format="WAV")
    buffer.seek(0)
    with wave.open(buffer, "rb") as src:
        return src.readframes(src.getnframes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--audio-root", type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root, batch = args.project.resolve(), args.batch.resolve()
    audio_root = args.audio_root or root / "assets/audio"
    old = batch / "before"
    manifest = read_json(audio_root / "original-audio-sources.json")
    assert manifest["baseline"] == read_json(old / "inputs.json")
    for rel, expected in manifest["baseline"].items():
        assert sha(old / rel) == expected, ("Changed baseline", rel)
    for name, expected in manifest["tools"].items():
        assert sha(root / "tools" / name) == expected, ("Changed production tool", name)
    for rel, expected in manifest["outputs"].items():
        assert sha(audio_root / rel) == expected, ("Changed delivery", rel)
        if rel.endswith(".json"):
            assert b"\r\n" not in (audio_root / rel).read_bytes(), "Provenance must survive Git LF normalization"

    music = {}
    for name, row in manifest["music"].items():
        assert row["external_audio_inputs"] == [] and row["events"], name
        data, score = compose(row["frames"], seed=row["seed"], tonic=row["tonic_midi"], scene=row["scene"], loop=row["loop"])
        assert score == row, ("Score not reproducible", name)
        music[name] = data

    vocals = {}
    for row in manifest["retained_vocals"]:
        path = audio_root / "retained-vocals" / Path(row["path"]).name
        assert sha(path) == row["sha256"], "Retained stem changed"
        data, rate = sf.read(path, dtype="float32", always_2d=True)
        from math import gcd
        common = gcd(rate, 48000)
        vocals[row["act"]] = data if rate == 48000 else resample_poly(data, 48000 // common, rate // common, axis=0)
    assert set(vocals) == {"act1", "act2"}

    preserved = 0
    for folder in ["act1-natural", "act2-hall", "act2-opening"]:
        score = read_json(audio_root / folder / "score.json")
        previous = read_json(old / folder / "score.json")
        if folder != "act2-opening":
            assert score["lines"] == previous["lines"], "Existing subtitles changed"
        for line in score["lines"]:
            if line["delivery"] != "speech" or line["role_id"] == "fahai":
                continue
            name = line["line_id"] + ".wav"
            assert pcm(audio_root / folder / name) == pcm(old / folder / name), name
            preserved += 1
        if folder == "act2-opening":
            continue
        before = pcm(old / folder / "main.wav")
        after = pcm(audio_root / folder / "main.wav")
        assert len(before) == len(after), "Existing act timing changed"
        regions = sorted(manifest["replaced_regions"]["act1" if folder == "act1-natural" else "act2-hall"], key=lambda r: r["start_frame"])
        cursor = 0
        for row in regions:
            start, end = row["start_frame"], row["end_frame"]
            assert cursor <= start < end <= len(after) // 4
            assert before[cursor * 4:start * 4] == after[cursor * 4:start * 4], "Unrelated main PCM changed"
            if folder == "act1-natural":
                data = music["act1-" + row["name"]].copy()
                if row["retained_vocals"]:
                    data += vocals["act1"]
            else:
                data = music["act2-wine"] + vocals["act2"] * np.float32(10 ** (row["vocal_gain_db"] / 20))
                assert pcm(audio_root / folder / "wine-duet.wav") == quantize(data)
            assert after[start * 4:end * 4] == quantize(data), ("Replacement does not reconstruct", row["name"])
            cursor = end
        assert before[cursor * 4:] == after[cursor * 4:]

    for name, rel in {
        "act1-wait": "act1-natural/wait_loop.wav", "act1-take-close": "act1-natural/take_close.wav",
        "act2-fahai-entry": "act2-hall/fahai-entry.wav", "act2-xu-fall-hit": "act2-hall/xu-fall-hit.wav",
        "act2-intro": "act2-opening/intro.wav", "act2-entrance-loop": "act2-opening/entrance-loop.wav",
    }.items():
        assert pcm(audio_root / rel) == quantize(music[name]), rel
        assert pcm(audio_root / rel) != pcm(old / rel), "Old recording still installed"

    request = read_json(batch / "fahai-request.json")
    assert request == manifest["fahai"]["request"] and request["recording_references"] == []
    assert sha(batch / "fahai-request.json") == manifest["fahai"]["request_sha256"]
    for name, expected in request["files"].items():
        assert sha(batch / "models" / name) == expected, name
    for row in manifest["fahai"]["lines"]:
        path = audio_root / "act2-opening" / (row["line_id"] + ".wav")
        assert sha(path) == row["sha256"] and pcm(path) == pcm(batch / "fahai" / path.name)
        assert pcm(path) != pcm(old / "act2-opening" / path.name)

    files = list(audio_root.glob("act[12]-*/*.wav")) + list((audio_root / "retained-vocals").glob("*.wav"))
    peaks = {}
    for path in files:
        data, rate = sf.read(path, always_2d=True)
        assert data.shape[1] == 2 and len(data) and np.isfinite(data).all(), path
        peak = float(np.abs(data).max())
        assert peak < .98, ("Clipping", path, peak)
        peaks[str(path.relative_to(audio_root))] = peak
        subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"], check=True, timeout=60)
    report = dict(passed=True, decoded_files=len(files), preserved_speech_clips=preserved,
        retained_singing_stems=2, sample_exact_reconstruction=True, accompaniment_recording_inputs=[],
        reproducible_symbolic_cues=len(music), fahai_recording_references=[], subtitle_timing="unchanged Act1/hall; opening audited separately",
        peaks=peaks, human_listening_verified=False, residual_rights=manifest["residual_rights"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({k: v for k, v in report.items() if k != "peaks"}, ensure_ascii=False))


if __name__ == "__main__":
    main()

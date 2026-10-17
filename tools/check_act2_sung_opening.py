"""Independently check protected Fahai PCM, complete new word onsets and delivery files."""
import argparse
import hashlib
import json
from math import gcd
from pathlib import Path
import subprocess
import tempfile

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def audio(path):
    wave, rate = sf.read(path, dtype="float64", always_2d=True)
    assert np.isfinite(wave).all() and wave.size
    if rate != 48000:
        factor = gcd(rate, 48000)
        wave = resample_poly(wave, 48000 // factor, rate // factor, axis=0)
    return wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()
    target = args.project / "assets/audio/act2-opening"
    score = json.loads((target / "score.json").read_text(encoding="utf-8"))
    request = json.loads((args.work / "request.json").read_text(encoding="utf-8"))
    main_path = target / "main.wav"
    main_wave = audio(main_path)
    assert len(score["lines"]) == 9
    for asset in score["assets"]:
        path = args.project / asset["path"].removeprefix("res://")
        info = sf.info(path)
        assert sha(path) == asset["sha256"]
        assert info.samplerate == 48000 and info.channels == 2 and info.subtype == "PCM_16"
        assert info.frames == asset["frames"] and np.max(np.abs(audio(path))) < .99
        settings = path.with_name(path.name + ".import").read_text(encoding="utf-8")
        for setting in ["edit/trim=false", "edit/normalize=false", "edit/loop_mode=0", "compress/mode=0"]:
            assert setting in settings
    baseline = request["unchanged_before"]
    current = {str(path.relative_to(args.project)): sha(path)
        for directory in ["act1-natural", "act2-hall"]
        for path in (args.project / "assets/audio" / directory).rglob("*") if path.is_file()}
    assert current == baseline, "First-act or hall resources changed"
    original = next(row for row in score["segments"] if row["id"] == "fahai-original-body")
    assert not original["voice_conversion"] and not original["lyrics_changed"]
    body = audio(original["path"])
    video_available = Path(original["video_path"]).exists()
    if args.ffmpeg and video_available:
        assert sha(original["video_path"]) == original["video_sha256"]
        with tempfile.TemporaryDirectory(prefix="act2-fahai-") as directory:
            decoded = Path(directory)/"fahai.wav"
            subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror",
                "-i", original["video_path"], "-map", "0:a:0", "-vn", "-ar", "48000", "-ac", "2",
                "-c:a", "pcm_s16le", str(decoded)], check=True, timeout=60)
            independently_decoded = audio(decoded)
        assert np.array_equal(body, independently_decoded), "Saved original PCM differs from a fresh source decode"
        body = independently_decoded
    assert hashlib.sha256((body*32768).astype('<i2').tobytes()).hexdigest() == original["source_pcm_sha256"]
    assert original["source_pcm_sha256"] == "15fcbc6afc8b17e7c9cf38cd5bd3070feb5cf10f17ddc82c589d09339445feec", "PCM differs from the previously independently audited source"
    start = original["start_frame"]
    # Exclude only the declared 40 ms incoming and 150 ms outgoing overlaps.
    first = original["edge_overlap_frames"]
    last = len(body) - round(.15 * 48000)
    difference = np.max(np.abs(main_wave[start+first:start+last] - body[first:last] * score["common_gain"]))
    assert difference <= 1 / 32768, "Protected original Fahai PCM differs beyond PCM16 quantization"
    fahai = [row for row in score["lines"] if row["delivery"] == "original"]
    assert len(fahai) == 7 and all(row["role_id"] == "fahai" for row in fahai)
    head_results = []
    source_backing = audio(request["reference"]["outputs"]["backing"]["path"])
    template = source_backing[4*48000:22*48000]
    for segment in score["segments"]:
        if segment["id"] == "fahai-original-body":
            continue
        assert sha(segment["path"]) == segment["sha256"]
        assert segment["original_vocal_gain"] == 0 and not segment["original_vocal_blend"]
        voice = audio(segment["path"])
        assert len(voice) == segment["full_generated_frames"]
        if segment["identity"]["role_id"] != "xuxian":
            continue
        assert sha(segment["identity"]["path"]) == segment["identity"]["sha256"]
        active = np.flatnonzero(np.max(np.abs(voice), axis=1) > max(.01, np.max(np.abs(voice)) * .03))
        first = int(active[0])
        assert first >= segment["incoming_overlap_frames"], "A word onset would enter the musical crossfade"
        end = min(first + 4800, len(template), len(voice))
        expected = (template[first:end] + voice[first:end] * segment["vocal_gain"]) * score["common_gain"]
        start = segment["start_frame"]
        error = float(np.max(np.abs(main_wave[start+first:start+end] - expected)))
        assert error <= 1/32768, "A generated word onset was faded or mixed with an original voice"
        head_results.append(dict(id=segment["id"],generated_onset_frame=first,head_max_error=error,original_voice_gain=0))
    assert len(head_results) == 2
    for previous, following in zip(score["lines"], score["lines"][1:]):
        assert previous["end_frame"] <= following["start_frame"]
    assert all(row["start_frame"] < row["end_frame"] <= len(main_wave) - 96000 for row in score["lines"])
    assert np.max(np.abs(main_wave[-96000:])) == 0
    assert abs(len(main_wave)/48-score["duration_ms"]) <= .5
    opening = score["segments"][0]
    assert opening["delivery"] == "original" and not opening["lyrics_changed"]
    original_vocals = audio(request["reference"]["outputs"]["vocals"]["path"])[4*48000:22*48000]
    stored_original = audio(opening["path"])
    assert np.max(np.abs(stored_original - original_vocals)) < 6e-8
    assert opening["vocal_gain"] == 1.0
    first = opening["incoming_overlap_frames"]
    start = opening["start_frame"]
    # Mixing reads the saved FLOAT stem; first bound its float32 storage error above.
    expected = (template[first:] + stored_original[first:]) * score["common_gain"]
    opening_difference = float(np.max(np.abs(main_wave[start+first:start+len(template)] - expected)))
    assert opening_difference <= 1/32768, "Original Fahai opening differs beyond the declared gain and overlap"
    report = dict(passed=True,protected_fahai_lines=7,fahai_max_pcm_error=float(difference),
        fahai_opening_max_pcm_error=opening_difference,
        xuxian_heads=head_results,unchanged_first_act_and_hall_files=len(current),
        peak=float(np.max(np.abs(main_wave))),clipping_samples=int(np.count_nonzero(np.abs(main_wave)>=1)),
        full_decode=True,source_video_redecoded=bool(args.ffmpeg and video_available),
        source_pcm_matches_prior_independent_audit=True,subtitle_rows=9,human_listening_verified=False)
    (args.work/"technical-audit.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False))


if __name__=="__main__":
    main()

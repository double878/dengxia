"""Independently decode the original videos and audit the full Act 2 opening PCM."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import wave


def sha(data):
    return hashlib.sha256(data).hexdigest()


def pcm(path):
    with wave.open(str(path), "rb") as source:
        assert source.getparams()[:3] == (2, 2, 48000), path
        assert source.getcomptype() == "NONE", path
        return source.readframes(source.getnframes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs=2, type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--edit-manifest", type=Path)
    args = parser.parse_args()
    target = args.project / "assets/audio/act2-opening"
    score = json.loads((target / "score.json").read_text(encoding="utf-8"))
    main_path = target / "main.wav"
    data = pcm(main_path)
    assert len(score["sources"]) == 2
    assert sha(main_path.read_bytes()) == score["assets"][0]["sha256"]
    assert sha(data) == score["assets"][0]["pcm_sha256"]
    assert len(data) // 4 == score["assets"][0]["frames"]
    assert abs(len(data) / 4 / 48 - score["duration_ms"]) <= .5
    cursor = 0
    recipe = json.loads(args.edit_manifest.read_text(encoding="utf-8")) if args.edit_manifest else None
    originals = []
    with tempfile.TemporaryDirectory(prefix="act2-original-") as work:
        for index, (video, row) in enumerate(zip(args.sources, score["sources"])):
            assert video.name == row["file_name"] and sha(video.read_bytes()) == row["video_sha256"]
            decoded = Path(work) / f"source-{index}.wav"
            subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-y",
                            "-i", str(video), "-vn", "-ar", "48000", "-ac", "2",
                            "-c:a", "pcm_s16le", str(decoded)], check=True, timeout=60)
            expected = pcm(decoded)
            originals.append(expected)
            assert sha(expected) == row["decoded_pcm_sha256"]
            assert row["source_start_frame"] == 0 and row["source_end_frame"] == len(expected) // 4
            if not recipe:
                assert row["main_start_frame"] == cursor
                assert data[cursor * 4:cursor * 4 + len(expected)] == expected, "Original voice truncated/changed"
            cursor += len(expected) // 4
            if not recipe:
                assert row["main_end_frame"] == cursor
    if recipe:
        import numpy as np
        import soundfile as sf
        edited = [bytearray(part) for part in originals]
        assert len(recipe["voice_edits"]) == len(score["voice_edits"]) == 2
        assert recipe["video_sha256"] == [row["video_sha256"] for row in score["sources"]]
        conversion = score["voice_conversion"]
        assert conversion["method"] == "Seed-VC direct voice conversion; no text synthesis"
        for reference in conversion["reference_sources"]:
            path = args.project / reference["path"].removeprefix("res://")
            assert sha(path.read_bytes()) == reference["sha256"], "First-act identity changed"
        for edit, saved in zip(recipe["voice_edits"], score["voice_edits"]):
            assert edit["role_id"] == saved["role_id"] == "xuxian" and edit["part"] == 0
            start, end = edit["start_frame"], edit["end_frame"]
            assert start == saved["start_frame"] and end == saved["end_frame"]
            replacement = Path(edit["replacement_path"])
            assert sha(replacement.read_bytes()) == saved["replacement_sha256"]
            replacement_pcm = pcm(replacement)
            assert len(replacement_pcm) == (end-start)*4
            composition = edit["composition"]
            voice, rate = sf.read(composition["original_vocals"], dtype="float64", always_2d=True)
            converted, converted_rate = sf.read(composition["aligned_vocals"], dtype="float64", always_2d=True)
            assert rate == converted_rate == 48000 and converted.shape == voice[start:end].shape
            for field in ["original_vocals", "aligned_vocals"]:
                assert sha(Path(composition[field]).read_bytes()) == composition[field+"_sha256"]
            fade = int(composition["fade_frames"])
            envelope = np.ones((end-start, 1), dtype=np.float64)
            ramp = np.sin(np.linspace(0, np.pi/2, fade))**2
            envelope[:fade, 0] = ramp
            envelope[-fade:, 0] = ramp[::-1]
            raw = np.frombuffer(originals[0], dtype="<i2").reshape(-1,2)[start:end].astype(np.float64)/32768
            calculated = np.rint((raw + envelope * (converted*composition["gain"]-voice[start:end]))*32768)
            assert np.max(np.abs(calculated)) < 32767
            assert calculated.astype("<i2").tobytes() == replacement_pcm, "Accompaniment/voice composition differs"
            assert replacement_pcm != originals[0][start*4:end*4], "Xu voice was never replaced"
            edited[0][start*4:end*4] = replacement_pcm
        overlap = int(score["splice_overlap_frames"])
        assert overlap == recipe["splice_overlap_frames"] and 0 < overlap <= 2400
        cursor -= overlap
        splice = len(edited[0])//4-overlap
        assert score["sources"][1]["main_start_frame"] == splice
        assert data[:splice*4] == edited[0][:splice*4]
        assert data[(splice+overlap)*4:cursor*4] == originals[1][overlap*4:], "Fahai original changed"
        left = np.frombuffer(edited[0][-overlap*4:], dtype="<i2").reshape(-1,2).astype(np.float64)
        right = np.frombuffer(originals[1][:overlap*4], dtype="<i2").reshape(-1,2).astype(np.float64)
        weight = np.array([(1-math.cos(math.pi*i/(overlap-1)))/2 for i in range(overlap)])[:,None]
        expected_join = np.rint(left*(1-weight)+right*weight).astype("<i2").tobytes()
        assert data[splice*4:(splice+overlap)*4] == expected_join, "Source join does not match declared fade"
        assert score["entrance_music_enabled"] is False
    assert score["splice_frame"] == score["sources"][1]["main_start_frame"]
    assert score["dark_start_ms"] == round(cursor / 48)
    assert data[cursor * 4:] == bytes(48000 * 2 * 4), "Scene fade must follow every original frame"
    previous = 0
    for row in score["lines"]:
        assert previous <= row["start_frame"] < row["end_frame"] <= cursor
        assert row["start_ms"] == round(row["start_frame"] / 48)
        assert row["end_ms"] == round(row["end_frame"] / 48)
        assert row["role_id"] in ["fahai", "xuxian"]
        expected_delivery = "voice_converted" if recipe and row["role_id"] == "xuxian" else "original"
        assert row["delivery"] == expected_delivery
        previous = row["end_frame"]
    assert score["lines"][0]["role_id"] == ("fahai" if recipe else "xuxian")
    assert score["lines"][-1]["text"] == ("现出原形在你的身边" if recipe else "告辞了。")
    settings = (target / "main.wav.import").read_text(encoding="utf-8")
    for setting in ["edit/trim=false", "edit/normalize=false", "edit/loop_mode=0", "compress/mode=0"]:
        assert setting in settings, setting
    subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i",
                    str(main_path), "-f", "null", "-"], check=True, timeout=60)
    report = dict(passed=True, complete_original_sources=2, original_frames=cursor,
                  main_frames=len(data) // 4, splice_frame=score["splice_frame"],
                  unchanged_original_pcm=not bool(recipe), full_decode=True, subtitle_rows=len(score["lines"]),
                  dark_follows_complete_sources=True, import_protects_audio=True,
                  xuxian_edits=len(recipe["voice_edits"]) if recipe else 0,
                  unchanged_fahai_outside_declared_join=True,
                  human_listening_verified=False)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()

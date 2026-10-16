"""Independently decode the original videos and audit the full Act 2 opening PCM."""
import argparse
import hashlib
import json
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
    with tempfile.TemporaryDirectory(prefix="act2-original-") as work:
        for index, (video, row) in enumerate(zip(args.sources, score["sources"])):
            assert video.name == row["file_name"] and sha(video.read_bytes()) == row["video_sha256"]
            decoded = Path(work) / f"source-{index}.wav"
            subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-y",
                            "-i", str(video), "-vn", "-ar", "48000", "-ac", "2",
                            "-c:a", "pcm_s16le", str(decoded)], check=True, timeout=60)
            expected = pcm(decoded)
            assert sha(expected) == row["decoded_pcm_sha256"]
            assert row["source_start_frame"] == 0 and row["source_end_frame"] == len(expected) // 4
            assert row["main_start_frame"] == cursor
            assert data[cursor * 4:cursor * 4 + len(expected)] == expected, "Original voice truncated/changed"
            cursor += len(expected) // 4
            assert row["main_end_frame"] == cursor
    assert score["splice_frame"] == score["sources"][1]["main_start_frame"]
    assert score["dark_start_ms"] == round(cursor / 48)
    assert data[cursor * 4:] == bytes(48000 * 2 * 4), "Scene fade must follow every original frame"
    previous = 0
    for row in score["lines"]:
        assert previous <= row["start_frame"] < row["end_frame"] <= cursor
        assert row["start_ms"] == round(row["start_frame"] / 48)
        assert row["end_ms"] == round(row["end_frame"] / 48)
        assert row["role_id"] in ["fahai", "xuxian"] and row["delivery"] == "original"
        previous = row["end_frame"]
    assert score["lines"][0]["role_id"] == "xuxian"
    assert score["lines"][-1]["text"] == "告辞了。"
    settings = (target / "main.wav.import").read_text(encoding="utf-8")
    for setting in ["edit/trim=false", "edit/normalize=false", "edit/loop_mode=0", "compress/mode=0"]:
        assert setting in settings, setting
    subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i",
                    str(main_path), "-f", "null", "-"], check=True, timeout=60)
    report = dict(passed=True, complete_original_sources=2, original_frames=cursor,
                  main_frames=len(data) // 4, splice_frame=score["splice_frame"],
                  unchanged_original_pcm=True, full_decode=True, subtitle_rows=len(score["lines"]),
                  dark_follows_complete_sources=True, import_protects_audio=True,
                  human_listening_verified=False)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()

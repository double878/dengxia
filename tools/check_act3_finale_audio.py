"""Verify source integrity, complete crane tail and exact voice-only selections."""
import argparse
import hashlib
import json
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "assets/audio/act3-mountain"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pcm(name):
    with wave.open(str(ROOT / name), "rb") as stream:
        assert (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) == (48000, 2, 2)
        return stream.readframes(stream.getnframes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path)
    args = parser.parse_args()
    source = json.loads((ROOT / "finale-source.json").read_text(encoding="utf-8"))
    fight = json.loads((ROOT / "fight-source.json").read_text(encoding="utf-8"))
    score = json.loads((ROOT / "score.json").read_text(encoding="utf-8"))
    combined = pcm("performance.wav")
    old = pcm("original.wav")[:fight["splice_ms"] * 48 * 4] + pcm("fight-original.wav")[fight["incoming_trim_frames"] * 4:]
    cursor = source["preserved_prefix_frames"]
    assert cursor * 4 == len(old), "The full crane recording must be retained"
    assert combined[:cursor * 4] == old
    assert digest(old) == source["preserved_prefix_pcm_sha256"]
    names = ["performance.wav"]
    for clip in source["clips"]:
        data = pcm(clip["wav"])
        assert len(data) == clip["decoded_frames"] * 4 and digest(data) == clip["pcm_sha256"]
        voice = pcm(clip["voice_wav"])
        assert len(voice) == len(data) and digest(voice) == clip["voice_pcm_sha256"]
        assert voice != data, "Do not pass the original music mix off as voice-only"
        if args.source_dir:
            assert digest((args.source_dir / clip["filename"]).read_bytes()) == clip["sha256"]
        names += [clip["wav"], clip["voice_wav"]]
    for row in source["segments"]:
        count = row["selected_frames"]
        start = row["source_start_frame"]
        selected = bytes(count * 4) if row["kind"] == "silence" else pcm(row["wav"])[start * 4:(start + count) * 4]
        assert row["start_frame"] == cursor
        assert len(selected) == count * 4 and digest(selected) == row["pcm_sha256"]
        assert combined[cursor * 4:(cursor + count) * 4] == selected
        cursor += count
    assert cursor == source["performance_frames"] == len(combined) // 4
    assert digest(combined) == source["performance_pcm_sha256"]
    assert abs(cursor / 48 - score["duration_ms"]) < 1
    assert score["complete"] and score["finale"]["end_ms"] == score["duration_ms"]
    crane = next(line for line in score["lines"] if line["text"].startswith("休走"))
    assert sum(line["text"].startswith("休走") for line in score["lines"]) == 1
    assert crane["end_ms"] == source["crane_end_ms"]
    assert score["finale"]["start_ms"] >= crane["end_ms"] + 299
    assert source["response_gap_frames"] == 14400
    for name in names:
        settings = (ROOT / (name + ".import")).read_text(encoding="utf-8")
        for setting in ["edit/normalize=false", "edit/trim=false", "edit/loop_mode=0", "compress/mode=0"]:
            assert setting in settings, f"{name}: {setting}"
    print(json.dumps(dict(passed=True, performance_frames=cursor, duration_ms=score["duration_ms"],
        complete_crane_prefix=True, voice_only_segments=2, original_source_files_verified=bool(args.source_dir))))


if __name__ == "__main__":
    main()

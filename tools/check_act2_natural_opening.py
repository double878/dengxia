"""Read-only audit of complete intro PCM, approved sample, dialogue and pauses."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import wave


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pcm(path):
    with wave.open(str(path), "rb") as source:
        assert source.getparams()[:3] == (2, 2, 48000) and source.getcomptype() == "NONE", path
        return source.readframes(source.getnframes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--music-video", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = args.project.resolve()
    folder = root / "assets/audio/act2-opening"
    score = json.loads((folder / "score.json").read_text(encoding="utf-8"))
    data = {}
    for row in score["assets"]:
        path = root / row["path"].removeprefix("res://")
        assert digest(path.read_bytes()) == row["sha256"]
        data[row["asset_id"]] = raw = pcm(path)
        assert digest(raw) == row["pcm_sha256"] and len(raw) // 4 == row["frames"]
        subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"], check=True, timeout=60)
        values = memoryview(raw).cast("h")
        assert max(values) < 32767 and min(values) > -32768, path
        settings = path.with_suffix(".wav.import").read_text(encoding="utf-8")
        for setting in ["edit/trim=false", "edit/normalize=false", "edit/loop_mode=0", "compress/mode=0"]:
            assert setting in settings, (path, setting)
    assert len(data) == 8 and score["intro_once"] is True
    assert not score["pitch_shift"] and not score["time_stretch"] and not score["reverb"]
    assert digest((folder / "dialogue-01.wav").read_bytes()) == "7e13574fd107ede34f539cb37c3fceb8ff223fc71be307c0bc2dee6c942f7bbf"
    if "xuxian_production" in score:
        assert digest((folder / "dialogue-02.wav").read_bytes()) == "122ad6246b0c039994c1a9b9d75321d56c7bf52c7c1bd5e1cc124df54e7284b1", "Approved Xu sample changed"
        production = score["xuxian_production"]
        manifest_path = Path(production["delivery_manifest"])
        assert digest(manifest_path.read_bytes()) == production["delivery_manifest_sha256"]
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        assert len(manifest["lines"]) == 3
        for row in manifest["lines"]:
            original = Path(row["path"])
            assert digest(original.read_bytes()) == row["sha256"]
            assert pcm(original) == data[row["line_id"]], "Xu delivery changed or truncated"
            assert next(line for line in score["lines"] if line["line_id"] == row["line_id"])["text"] == row["text"]
    assert digest(args.music_video.read_bytes()) == score["music_source"]["video_sha256"]
    with tempfile.TemporaryDirectory(prefix="act2-intro-audit-") as temp:
        independent = Path(temp) / "intro.wav"
        subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i", str(args.music_video),
            "-map", "0:a:0", "-vn", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", str(independent)], check=True, timeout=60)
        assert pcm(independent) == data["intro"], "Video music changed or truncated"
    cursor = 0
    assert len(score["lines"]) == 6
    for number, line in enumerate(score["lines"], 1):
        begin, end = line["start_frame"], line["end_frame"]
        assert not any(data["main"][cursor * 4:begin * 4]), "Unexpected music or speech in turn gap"
        assert begin >= cursor and begin < end <= score["dark_start_frame"]
        assert line["delivery"] == "speech" and line["role_id"] == ("fahai" if number % 2 else "xuxian")
        assert line["start_ms"] == round(begin / 48) and line["end_ms"] == round(end / 48)
        assert data["main"][begin * 4:end * 4] == data[line["line_id"]], "Incomplete line"
        for pause in score["production"][line["line_id"]].get("pauses", []):
            assert not any(data[line["line_id"]][pause["start_frame"] * 4:pause["end_frame"] * 4])
        cursor = end
    assert not any(data["main"][cursor * 4:])
    assert len(data["main"]) // 4 - score["dark_start_frame"] == 96000
    assert score["duration_ms"] == round(len(data["main"]) / 4 / 48)
    for ref in score["xuxian_identity"]["source_assets"]:
        assert digest((root / ref["path"].removeprefix("res://")).read_bytes()) == ref["sha256"]
    report = dict(passed=True, assets=8, strict_decode=True, complete_video_music=True,
        approved_sample_byte_identical=True, complete_dialogue_lines=6, silence_and_subtitles_verified=True,
        intro_frames=len(data["intro"]) // 4, main_frames=len(data["main"]) // 4,
        approved_xuxian_sample_byte_identical="xuxian_production" in score,
        human_listening_scope=score["human_listening_scope"])
    args.report.parent.mkdir(exist_ok=True, parents=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()

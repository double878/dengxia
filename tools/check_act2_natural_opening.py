"""Read-only audit of intro provenance, Fahai identity and complete dialogue."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
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
    parser.add_argument("--audio-root", type=Path, help="Optional staging directory")
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = args.project.resolve()
    audio_root = args.audio_root or root / "assets/audio"
    folder = audio_root / "act2-opening"
    manifest = json.loads((audio_root / "original-audio-sources.json").read_text(encoding="utf8"))
    score = json.loads((folder / "score.json").read_text(encoding="utf-8"))
    data = {}
    for row in score["assets"]:
        path = folder / Path(row["path"]).name
        assert digest(path.read_bytes()) == row["sha256"]
        data[row["asset_id"]] = raw = pcm(path)
        assert digest(raw) == row["pcm_sha256"] and len(raw) // 4 == row["frames"]
        subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"], check=True, timeout=60)
        values = memoryview(raw).cast("h")
        assert max(values) < 32767 and min(values) > -32768, path
        settings = (root / "assets/audio/act2-opening" / path.name).with_suffix(".wav.import").read_text(encoding="utf-8")
        for setting in ["edit/trim=false", "edit/normalize=false", "edit/loop_mode=0", "compress/mode=0"]:
            assert setting in settings, (path, setting)
    assert len(data) == 8 and score["intro_once"] is True
    assert not score["pitch_shift"] and not score["time_stretch"] and not score["reverb"]
    user_recordings = score["identity_reference"]["kind"] == "user_provided_recordings"
    assert score["music_source"]["kind"] == ("restored_historical_recording" if user_recordings else "none" if score.get("background_music") is False else "original_symbolic_composition")
    if score.get("background_music") is False:
        assert not any(data["intro"]) and score["intro_duration_ms"] == 100
    identity = score["identity_reference"]
    if user_recordings:
        assert score["music_source"]["external_audio_inputs"] == ["existing_original_intro"]
        assert digest((folder / "intro.wav").read_bytes()) == manifest["music"]["act2-intro"]["sha256"]
        assert len(identity["recording_references"]) == 3
        assert not manifest["fahai"]["pitch_shift"] and not manifest["fahai"]["time_stretch"]
        assert not manifest["fahai"]["voice_conversion"]
    else:
        assert score["music_source"]["external_audio_inputs"] == []
        assert identity["kind"] == "licensed_preset_synthetic_voice" and identity["recording_references"] == []
        assert identity["voice"] == "zm_010" and identity["license"] == "Apache-2.0"
        request = manifest["fahai"]["request"]
        assert request["recording_references"] == [] and request["pitch_shift"] == 0
        assert request["voice"] == identity["voice"] and request["model"] == identity["model"]
    assert len(data["intro"]) // 4 == manifest["music"]["act2-intro"]["frames"]
    assert score["intro_duration_ms"] == round(len(data["intro"]) / 4 / 48)
    for line in manifest["fahai"]["lines"]:
        path = folder / (line["line_id"] + ".wav")
        assert digest(path.read_bytes()) == line["sha256"]
        assert len(data[line["line_id"]]) // 4 == line["frames"]
        if user_recordings:
            assert line["frames"] == line["retained_end_frame"] - line["retained_start_frame"]
            assert abs(line["measured_lufs"] + 18) <= .3
            continue
        assert line["complete_phrases"][-1]["end_frame"] == line["frames"]
        assert [p["text"] for p in line["complete_phrases"]] == request["phrases"][line["line_id"]]
        pauses = [(a["end_frame"], b["start_frame"]) for a, b in zip(line["complete_phrases"], line["complete_phrases"][1:])]
        for begin, end in pauses:
            assert end - begin == 26400 and not any(data[line["line_id"]][begin * 4:end * 4])
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
    report = dict(passed=True, assets=8, strict_decode=True, original_music_manifest=True,
        preset_fahai_without_recording_reference=not user_recordings, user_fahai_recordings=user_recordings,
        complete_dialogue_lines=6, silence_and_subtitles_verified=True,
        intro_frames=len(data["intro"]) // 4, main_frames=len(data["main"]) // 4,
        human_listening_scope=score["human_listening_scope"])
    args.report.parent.mkdir(exist_ok=True, parents=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()

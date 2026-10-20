"""Assemble complete natural dialogue and full one-shot video music, without time edits."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_pcm(path):
    with wave.open(str(path), "rb") as source:
        assert source.getparams()[:3] == (2, 2, 48000), path
        return source.readframes(source.getnframes())


def write_pcm(path, data):
    with wave.open(str(path), "wb") as target:
        target.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        target.writeframes(data)


def main():
    import numpy as np
    import soundfile as sf
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--music-video", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    project, batch = args.project.resolve(), args.batch.resolve()
    target = project / "assets/audio/act2-opening"
    approved = project / "builds/act2-fahai-slower-sample-20261017/法海慢速断句小样.wav"
    assert sha(approved) == "7e13574fd107ede34f539cb37c3fceb8ff223fc71be307c0bc2dee6c942f7bbf"
    request = read_json(batch / "game-request.json")
    converted = read_json(batch / "conversion-result.json")
    assert len(converted) == len(request["lines"]) == 6
    for row, line in zip(converted, request["lines"]):
        assert all(row[k] == line[k] for k in ["line_id", "role_id", "text", "seed"])
        assert sha(row["converted_path"]) == row["converted_sha256"]
        assert sha(row["path"]) == row["sha256"]
    identities = read_json(batch / "conversion-inputs.json")
    for ref in [identities["identity_reference"], *request["references"].values()]:
        assert sha(ref["path"]) == ref["sha256"]
    old = project / "builds/act2-voice-revision"
    old_request = read_json(old / "game-request.json")
    old_score = read_json(old / "delivery/score.json")
    old_rows = read_json(old / "game-generation-result.json")
    xu = [r for r in old_rows if r["role_id"] == "xuxian"]
    assert len(xu) == 3
    for row in xu:
        wanted = next(r for r in old_request["lines"] if r["line_id"] == row["line_id"])
        assert row["text"] == wanted.get("generation_text", wanted["text"])
        assert row["reference_sha256"] == old_request["identity_references"]["xuxian"]["sha256"]
        assert sha(row["reference_path"]) == row["reference_sha256"]
    for ref in old_request["identity_references"]["xuxian"]["source_assets"]:
        assert sha(project / ref["path"].removeprefix("res://")) == ref["sha256"]
    scratch = batch / "assembly"
    scratch.mkdir(exist_ok=True)
    recovered = {}
    for row in xu:
        asset = next(a for a in old_score["assets"] if a["asset_id"] == row["line_id"])
        revision = "4999956b9782a83dffd7a10d0c8e33fb9f75a6fc"
        content = subprocess.run(["git", "show", revision + ":" + asset["path"].removeprefix("res://")],
            cwd=project, capture_output=True, check=True, timeout=30).stdout
        assert hashlib.sha256(content).hexdigest() == asset["sha256"], "Historical Xu delivery changed"
        path = scratch / (row["line_id"] + "-restored.wav")
        path.write_bytes(content)
        assert len(read_pcm(path)) // 4 == asset["frames"]
        recovered[row["line_id"]] = dict(path=path, sha256=asset["sha256"], git_revision=revision)

    def ffmpeg(*options):
        subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-y", *map(str, options)], check=True, timeout=60)

    def resample(row):
        path = scratch / (row["line_id"] + "-48k-float.wav")
        ffmpeg("-i", row["converted_path"], "-ar", "48000", "-ac", "2", "-c:a", "pcm_f32le", path)
        data, rate = sf.read(path, dtype="float32", always_2d=True)
        assert rate == 48000 and data.shape[1] == 2 and len(data) and np.isfinite(data).all()
        return data

    def level(parts, line_id):
        pieces, pauses, cursor = [], [], 0
        for row, pause in parts:
            data = resample(row)
            pieces.append(data)
            cursor += len(data)
            if pause:
                pauses.append(dict(start_frame=cursor, end_frame=cursor + pause * 48))
                pieces.append(np.zeros((pause * 48, 2), dtype="float32"))
                cursor += pause * 48
        data = np.concatenate(pieces)
        raw = scratch / (line_id + "-assembled-float.wav")
        sf.write(raw, data, 48000, subtype="FLOAT")
        measured = subprocess.run([str(args.ffmpeg), "-nostdin", "-i", str(raw), "-af",
            "loudnorm=I=-18:TP=-2:LRA=11:print_format=json", "-f", "null", "-"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", check=True, timeout=60)
        meter, _ = json.JSONDecoder().raw_decode(measured.stderr[measured.stderr.rfind("{"):])
        gain_db = min(-18 - float(meter["input_i"]), -2 - float(meter["input_tp"]))
        output = target / (line_id + ".wav")
        ffmpeg("-i", raw, "-af", f"volume={gain_db:.6f}dB", "-c:a", "pcm_s16le", output)
        pcm = read_pcm(output)
        assert len(pcm) // 4 == len(data)
        for pause in pauses:
            assert not any(pcm[pause["start_frame"] * 4:pause["end_frame"] * 4])
        return dict(constant_gain_db=gain_db, pauses=pauses, complete_converted_frames=True,
            inputs=[dict(source=row["converted_path"], sha256=row["converted_sha256"], pause_after_ms=pause) for row, pause in parts])

    target.mkdir(exist_ok=True)
    shutil.copyfile(approved, target / "dialogue-01.wav")
    production = {"dialogue-01": dict(source=str(approved), sha256=sha(approved), user_approved=True, byte_identical=True)}
    texts = ["许施主。你家娘子，并非凡人。贫僧今日，正是为此而来。", xu[0]["text"],
        "人妖有别。莫被她的温情，蒙蔽了双眼。", xu[1]["text"],
        "端午将至。你劝她，喝杯雄黄酒。是人是妖。一试，便知。", xu[2]["text"]]
    for number, row in zip([2, 4, 6], xu):
        cached = recovered[row["line_id"]]
        shutil.copyfile(cached["path"], target / f"dialogue-{number:02d}.wav")
        production[f"dialogue-{number:02d}"] = dict(source=str(cached["path"]), sha256=cached["sha256"],
            git_revision=cached["git_revision"], byte_identical=True, complete_converted_frames=True)
    for number, parts in [(3, [(r, l["pause_after_ms"]) for r, l in zip(converted[:2], request["lines"][:2])]),
        (5, [(r, l["pause_after_ms"]) for r, l in zip(converted[2:], request["lines"][2:])])]:
        production[f"dialogue-{number:02d}"] = level(parts, f"dialogue-{number:02d}")
    ffmpeg("-i", args.music_video, "-map", "0:a:0", "-vn", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", target / "intro.wav")
    intro = read_pcm(target / "intro.wav")
    main_pcm, lines = bytearray(250 * 48 * 4), []
    for index, text in enumerate(texts, 1):
        line_id = f"dialogue-{index:02d}"
        data = read_pcm(target / (line_id + ".wav"))
        start = len(main_pcm) // 4
        main_pcm.extend(data)
        end = len(main_pcm) // 4
        role = "fahai" if index % 2 else "xuxian"
        lines.append(dict(line_id=line_id, role_id=role, role_name="法海" if role == "fahai" else "许仙", text=text,
            delivery="speech", start_frame=start, end_frame=end, start_ms=round(start / 48), end_ms=round(end / 48)))
        main_pcm.extend(bytes((850 if index < 6 else 500) * 48 * 4))
    dark = len(main_pcm) // 4
    main_pcm.extend(bytes(2000 * 48 * 4))
    write_pcm(target / "main.wav", main_pcm)
    assets = []
    for asset_id in ["main", "intro", *[l["line_id"] for l in lines]]:
        path = target / (asset_id + ".wav")
        pcm = read_pcm(path)
        assets.append(dict(asset_id=asset_id, path="res://" + path.relative_to(project).as_posix(),
            sha256=sha(path), frames=len(pcm) // 4, pcm_sha256=hashlib.sha256(pcm).hexdigest()))
    score = dict(audio_version="act2-natural-opening-" + assets[0]["sha256"][:12], stage_id=2, scene_id="fahai_advice",
        main_path=assets[0]["path"], intro_path=assets[1]["path"], intro_once=True, intro_duration_ms=round(len(intro) / 4 / 48),
        greeting_gate_ms=0, duration_ms=round(len(main_pcm) / 4 / 48), dark_start_ms=round(dark / 48),
        dark_start_frame=dark, lines=lines, assets=assets, production=production,
        music_source=dict(file_name=args.music_video.name, video_sha256=sha(args.music_video),
            decoded_pcm_sha256=hashlib.sha256(intro).hexdigest(), complete_audio=True),
        identity_reference=identities["identity_reference"], xuxian_identity=old_request["identity_references"]["xuxian"],
        inference=dict(f5_steps=32, f5_cfg=2.0, seed_vc_steps=25, seed_vc_cfg=.7, length_adjust=1.0,
            f0_condition=False, auto_f0_adjust=False, semi_tone_shift=0),
        request_sha256=sha(batch / "game-request.json"), pitch_shift=False, time_stretch=False, reverb=False,
        phrase_request=request["lines"], synthesis_inputs=read_json(batch / "tts-inputs.json"),
        conversion_inputs=identities,
        human_listening_scope="Only dialogue-01 directly heard and approved by user; other lines follow its production recipe")
    write_json(target / "score.json", score)
    write_json(batch / "delivery-report.json", score)
    print(json.dumps(dict(assets=len(assets), duration_ms=score["duration_ms"], intro_duration_ms=score["intro_duration_ms"])))


if __name__ == "__main__":
    main()

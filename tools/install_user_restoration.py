"""Install approved duet previews and the staged user Fahai assets, with backup."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave

RATE = 48000
FOLDERS = ["act1-natural", "act2-hall", "act2-opening"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def dump(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def pcm(path):
    with wave.open(str(path), "rb") as source:
        if source.getparams()[:3] != (2, 2, RATE):
            raise ValueError(f"Unexpected format: {path}")
        return source.readframes(source.getnframes())


def refresh(folder, config):
    for row in config["assets"]:
        path = folder / Path(row["path"]).name
        data = pcm(path)
        row.update(sha256=sha(path), frames=len(data)//4,
                   pcm_sha256=hashlib.sha256(data).hexdigest())
    dump(folder / "score.json", config)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--intro", type=Path, required=True)
    parser.add_argument("--approved-duets", action="store_true", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    batch = args.batch.resolve()
    before, delivery = batch / "before", batch / "delivery"
    previous_puppets = {name: sha(delivery / "puppets" / name)
        for name in ["fahai.png", "puppet_assets.json"] if (delivery / "puppets" / name).exists()}
    before.mkdir(exist_ok=True)
    baseline_path = before / "inputs.json"
    if not baseline_path.exists():
        baseline = {}
        for folder in FOLDERS:
            target = before / folder
            target.mkdir(exist_ok=True)
            for path in (root / "assets/audio" / folder).iterdir():
                if path.suffix in [".wav", ".json"]:
                    shutil.copyfile(path, target / path.name)
                    baseline[f"{folder}/{path.name}"] = sha(path)
        shutil.copyfile(root / "assets/audio/original-audio-sources.json", before / "original-audio-sources.json")
        art = before / "puppets"
        art.mkdir(exist_ok=True)
        for name in ["fahai.png", "puppet_assets.json"]:
            shutil.copyfile(root / "assets/puppets" / name, art / name)
        dump(baseline_path, baseline)
    baseline = load(baseline_path)
    delivery.mkdir(exist_ok=True)
    for rel, expected in baseline.items():
        if sha(before / rel) != expected:
            raise ValueError("Changed backup: " + rel)
        target = delivery / rel
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(before / rel, target)
    provenance = load(before / "original-audio-sources.json")
    previews = load(batch / "duet-preview-manifest.json")
    manifest = dict(version=2, batch="user-restoration-20261022-v1",
        scope="Act1/2 singing accompaniment, restored Act2 intro and user Fahai recordings",
        duet_listening_approved=True, approval="User selected A: both supplied previews accepted",
        background_music=True, baseline=baseline, music={}, replaced_regions={},
        residual_rights=provenance.get("residual_rights", "Existing retained performances retain their prior source status"))
    for act, folder, region_id in [(1, "act1-natural", "act1"), (2, "act2-hall", "act2-hall")]:
        score = load(delivery / folder / "score.json")
        preview = previews["acts"][act-1]
        if preview["source_sha256"] != baseline[f"{folder}/main.wav"]:
            raise ValueError("Preview vocal master changed")
        region = next(r for r in provenance["replaced_regions"][region_id] if r["name"] == "singing")
        start, end = region["start_frame"], region["end_frame"]
        song_path = batch / f"act{act}-with-vocals.wav"
        if sha(song_path) != preview["assets"]["with-vocals"]["sha256"]:
            raise ValueError("Approved preview changed")
        song = pcm(song_path)
        if len(song)//4 != end-start:
            raise ValueError("Approved song duration changed")
        path = delivery / folder / "main.wav"
        original = pcm(path)
        with wave.open(str(path), "wb") as dest:
            dest.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
            dest.writeframes(original[:start*4] + song + original[end*4:])
        if act == 2:
            shutil.copyfile(song_path, delivery / folder / "wine-duet.wav")
            score["singing_source"]["backing"] = "Approved new symbolic opera-style composition; no external instrumental recordings"
        score.update(audio_version=f"act{act}-user-approved-backing-" + sha(path)[:12],
            background_music=True, accompaniment_source="res://assets/audio/original-audio-sources.json",
            accompaniment_scope="singing_only; other cues retain the previous configuration",
            human_listening_scope="User accepted this exact complete vocal+backing preview")
        score["rights_status"] = "new_sample_free_backing; retained_performances_keep_prior_source_status"
        refresh(delivery / folder, score)
        manifest["replaced_regions"][region_id] = [region]
        composition = load(batch / f"act{act}-composition.json")
        composition["preview_mix_sha256"] = sha(song_path)
        manifest["music"][f"act{act}-duet"] = composition
    # Six turns retain their exact individual PCM; timings come from frame counts.
    folder = delivery / "act2-opening"
    score = load(folder / "score.json")
    recordings = load(batch / "fahai-recordings/recordings-manifest.json")
    for row in recordings["lines"]:
        path = batch / "fahai-recordings" / (row["line_id"] + ".wav")
        if sha(path) != row["sha256"]:
            raise ValueError("Fahai recording changed")
        shutil.copyfile(path, folder / path.name)
        row["path"] = "assets/audio/act2-opening/" + path.name
    parts = [bytes(12000*4)]
    cursor, production = 12000, {}
    for number, line in enumerate(score["lines"]):
        path = folder / (line["line_id"] + ".wav")
        raw = pcm(path)
        line.update(start_frame=cursor, end_frame=cursor+len(raw)//4,
                    start_ms=round(cursor/48), end_ms=round((cursor+len(raw)//4)/48))
        gap = 24000 if number == 5 else 40800
        parts.extend([raw, bytes(gap*4)])
        cursor += len(raw)//4 + gap
        production[line["line_id"]] = dict(source="User-provided recording; mild noise/EQ/compression/loudness processing" if line["role_id"] == "fahai" else "Unchanged shipped Xuxian PCM", sha256=sha(path), complete_converted_frames=True)
    score.update(dark_start_frame=cursor, dark_start_ms=round(cursor/48))
    parts.append(bytes(96000*4))
    cursor += 96000
    with wave.open(str(folder / "main.wav"), "wb") as dest:
        dest.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        dest.writeframes(b"".join(parts))
    intro_frames = len(pcm(args.intro))//4
    if intro_frames != 380928:
        raise ValueError("Expected the historical 7.936-second intro")
    shutil.copyfile(args.intro, folder / "intro.wav")
    manifest["music"]["act2-intro"] = dict(kind="restored_historical_recording", frames=intro_frames,
        sha256=sha(args.intro), source="Original intro from the existing project backup; explicitly requested restoration")
    score.update(audio_version="act2-user-recordings-restored-intro-" + sha(folder / "main.wav")[:12],
        intro_duration_ms=round(intro_frames/48), duration_ms=round(cursor/48), production=production,
        background_music=True, music_source=dict(kind="restored_historical_recording", sha256=sha(args.intro),
            manifest="res://assets/audio/original-audio-sources.json", external_audio_inputs=["existing_original_intro"]),
        identity_reference=dict(kind="user_provided_recordings", recording_references=[dict(line_id=r["line_id"], filename=r["source_filename"], sha256=r["source_sha256"]) for r in recordings["lines"]]),
        human_listening_scope="User recording performance retained; new cleanup not separately approved by ear",
        rights_status="user_requested_original_intro_and_recordings; prior_external_source_status_retained")
    refresh(folder, score)
    recordings["game_assets_installed"] = True
    manifest["fahai"] = recordings
    # Stage the atlas and source without changing the existing skeleton contract.
    art = load(batch / "art/fahai-manifest.json")
    puppet = load(before / "puppets/puppet_assets.json")
    puppet["characters"]["fahai"] = art["character"]
    art_dir = delivery / "puppets"
    art_dir.mkdir(exist_ok=True)
    dump(art_dir / "puppet_assets.json", puppet)
    shutil.copyfile(batch / "art/fahai.png", art_dir / "fahai.png")
    manifest["puppet_outputs"] = {name: sha(art_dir / name) for name in ["fahai.png", "puppet_assets.json"]}
    manifest["tools"] = {name: sha(root / "tools" / name) for name in [
        "build_duet_previews.py", "compose_original_accompaniment.py", "prepare_fahai_recordings.py",
        "prepare_fahai_photo.py", "build_fahai_assets.py", "install_user_restoration.py"]}
    manifest["outputs"] = {str(p.relative_to(delivery)).replace("\\", "/"): sha(p)
        for name in FOLDERS for p in (delivery / name).iterdir() if p.suffix in [".wav", ".json"]}
    dump(delivery / "original-audio-sources.json", manifest)
    # Reject changed runtime files unless they are this exact interrupted install.
    for rel, expected in baseline.items():
        if sha(root / "assets/audio" / rel) not in [expected, manifest["outputs"][rel]]:
            raise ValueError("Concurrent audio edit: " + rel)
    for name in ["fahai.png", "puppet_assets.json"]:
        if sha(root / "assets/puppets" / name) not in [sha(before / "puppets" / name), sha(art_dir / name), previous_puppets.get(name)]:
            raise ValueError("Concurrent puppet edit: " + name)
    for name in FOLDERS:
        for path in (delivery / name).iterdir():
            target = root / "assets/audio" / name / path.name
            if sha(path) != sha(target):
                shutil.copyfile(path, target)
    shutil.copyfile(delivery / "original-audio-sources.json", root / "assets/audio/original-audio-sources.json")
    for name in ["fahai.png", "puppet_assets.json"]:
        shutil.copyfile(art_dir / name, root / "assets/puppets" / name)
    shutil.copyfile(batch / "art/fahai-reference.jpg", root / "assets/puppets/source/fahai-reference-20261022.jpg")
    print(json.dumps(dict(installed=True, opening_frames=cursor, intro_frames=intro_frames)))


if __name__ == "__main__":
    main()

"""Restore exact clean-vocal duet PCM, retaining the restored intro and voices."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def pcm(path):
    with wave.open(str(path), "rb") as src:
        if src.getparams()[:3] != (2, 2, 48000):
            raise ValueError(f"Unexpected PCM format: {path}")
        return src.readframes(src.getnframes())


def write_pcm(path, data):
    with wave.open(str(path), "wb") as dest:
        dest.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        dest.writeframes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--clean-batch", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    audio = root / "assets/audio"
    batch = args.batch.resolve()
    before = batch / "before/audio"
    manifest_path = audio / "original-audio-sources.json"
    source_manifest = load(manifest_path)
    if source_manifest.get("duet_accompaniment_enabled") is False:
        raise ValueError("Already revised; audit the installed output instead of overwriting backups")
    if before.exists():
        raise ValueError("Backup already exists; inspect it before attempting another installation")
    jobs = []
    for folder, key in [("act1-natural", "act1"), ("act2-hall", "act2-hall")]:
        clean = args.clean_batch / "before" / folder / "main.wav"
        rel = folder + "/main.wav"
        if sha(clean) != source_manifest["baseline"][rel] or sha(audio / rel) != source_manifest["outputs"][rel]:
            raise ValueError("Unexpected baseline or current master: " + rel)
        region = source_manifest["replaced_regions"][key][0]
        start, end = region["start_frame"], region["end_frame"]
        old, vocal = pcm(audio / rel), pcm(clean)
        if len(old) != len(vocal) or old[:start*4] != vocal[:start*4] or old[end*4:] != vocal[end*4:]:
            raise ValueError("Changes outside duet: " + rel)
        jobs.append((folder, key, old[:start*4] + vocal[start*4:end*4] + old[end*4:], vocal[start*4:end*4]))
    # Save all PCM/score inputs before the first runtime edit.
    before.mkdir(parents=True)
    for folder in ["act1-natural", "act2-hall", "act2-opening"]:
        shutil.copytree(audio / folder, before / folder, ignore=shutil.ignore_patterns("*.import"))
    shutil.copyfile(manifest_path, before / manifest_path.name)
    manifest = load(manifest_path)
    manifest.update(version=3, duet_accompaniment_enabled=False, duet_listening_approved=False,
        duet_approval_history="Both backing previews were approved, then the user explicitly canceled duet accompaniment",
        background_music=True, background_music_scope="Act2 original intro only; duets use clean retained vocals",
        current_revision="vocal-only-reference-puppets-20261022")
    for folder, key, master, duet in jobs:
        write_pcm(audio / folder / "main.wav", master)
        if folder == "act2-hall":
            write_pcm(audio / folder / "wine-duet.wav", duet)
        config = load(audio / folder / "score.json")
        config.update(background_music=False, accompaniment_scope="none; clean retained vocals only",
            audio_version=folder + "-vocal-only-" + sha(audio / folder / "main.wav")[:12],
            human_listening_scope="Original clean vocal PCM restored exactly at the user's request",
            rights_status="retained_performances_keep_prior_source_status")
        if "singing_source" in config:
            config["singing_source"]["backing"] = "None; clean original vocal PCM"
        for row in config["assets"]:
            path = audio / folder / Path(row["path"]).name
            data = pcm(path)
            row.update(sha256=sha(path), frames=len(data)//4, pcm_sha256=hashlib.sha256(data).hexdigest())
        dump(audio / folder / "score.json", config)
        music_key = "act1-duet" if key == "act1" else "act2-duet"
        previous = manifest["music"][music_key]
        manifest["music"][music_key] = dict(kind="retained_vocals_without_backing", accompaniment_enabled=False,
            clean_master_sha256=source_manifest["baseline"][folder + "/main.wav"],
            frames=len(duet)//4, pcm_sha256=hashlib.sha256(duet).hexdigest(),
            previous_preview_composition=previous)
        for rel in list(manifest["outputs"]):
            if rel.startswith(folder + "/"):
                manifest["outputs"][rel] = sha(audio / rel)
    manifest["tools"][Path(__file__).name] = sha(Path(__file__))
    dump(manifest_path, manifest)
    print(json.dumps(dict(installed=True, duets_without_backing=2, original_intro_and_fahai_retained=True)))


if __name__ == "__main__":
    main()

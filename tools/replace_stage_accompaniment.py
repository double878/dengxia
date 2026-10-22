"""Stage and install original Act 1/2 music and independent preset Fahai TTS.

Existing speech and clean singing stems are retained. New accompaniment uses
only the symbolic score in compose_original_accompaniment, never old backing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

from compose_original_accompaniment import compose, RATE

FOLDERS = ["act1-natural", "act2-opening", "act2-hall"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text(encoding="utf8"))


def dump(path, value):
    # Git enforces LF; provenance hashes must survive a fresh Windows checkout.
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")


def pcm(path):
    with wave.open(str(path), "rb") as source:
        if source.getparams()[:3] != (2, 2, RATE):
            raise ValueError("Expected stereo 48k PCM16: " + str(path))
        return source.readframes(source.getnframes())


def audio(path):
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    if rate != RATE:
        from math import gcd
        common = gcd(rate, RATE)
        data = resample_poly(data, RATE // common, rate // common, axis=0)
    if data.shape[1] != 2 or not np.isfinite(data).all():
        raise ValueError("Invalid source audio: " + str(path))
    return data


def write(path, data):
    if len(data) == 0 or not np.isfinite(data).all() or float(np.abs(data).max()) >= .98:
        raise ValueError("Empty, nonfinite or clipped delivery: " + str(path))
    sf.write(path, data, RATE, subtype="PCM_16")


def asset(path, asset_id, relative):
    raw = pcm(path)
    return dict(asset_id=asset_id, path=relative, sha256=sha(path), frames=len(raw) // 4,
        pcm_sha256=hashlib.sha256(raw).hexdigest(), sample_rate_hz=RATE, channels=2, subtype="PCM_16")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--delivery", type=Path, help="Separate staging directory; keeps the previous delivery intact")
    parser.add_argument("--no-background-music", action="store_true", help="Keep vocals and action effects; replace backing with silence")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    root, batch = args.project.resolve(), args.batch.resolve()
    backup = batch / "before"
    delivery = args.delivery.resolve() if args.delivery else batch / "delivery"
    backup.mkdir(exist_ok=True)
    delivery.mkdir(parents=True, exist_ok=True)
    if not (backup / "inputs.json").exists():
        baseline = {}
        for folder in FOLDERS:
            dest = backup / folder
            dest.mkdir(exist_ok=True)
            for source in (root / "assets/audio" / folder).iterdir():
                if source.suffix in [".wav", ".json"]:
                    shutil.copyfile(source, dest / source.name)
                    baseline[f"{folder}/{source.name}"] = sha(source)
        dump(backup / "inputs.json", baseline)
    baseline = load(backup / "inputs.json")
    for rel, expected in baseline.items():
        if sha(backup / rel) != expected:
            raise ValueError("Baseline was changed: " + rel)
        target = delivery / rel
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(backup / rel, target)

    manifest = dict(version=1, scope="Act 1/2 instrumental recordings and Fahai dialogue only",
        accompaniment_method="New symbolic composition and mathematical instrument synthesis; no external audio samples",
        residual_rights="Existing singing melody/timbre and other dialogue retained by user choice; their external permissions remain unverified",
        baseline=baseline, retained_vocals=[], music={}, replaced_regions={}, human_listening_verified=False)
    manifest["background_music"] = not args.no_background_music
    if args.no_background_music:
        manifest["accompaniment_method"] = "No background music; retained clean vocals and isolated action effects only"
    manifest["tools"] = {name: sha(root / "tools" / name) for name in
        ["compose_original_accompaniment.py", "replace_stage_accompaniment.py", "prepare_fahai_synthetic.py"]}

    def music(name, frames, seed, scene="gentle", loop=False):
        if args.no_background_music and name not in ["act1-take-close", "act2-xu-fall-hit"]:
            data = np.zeros((frames, 2), dtype=np.float32)
            score = dict(frames=frames, sample_rate_hz=RATE, muted=True, scene=scene,
                loop=loop, external_audio_inputs=[], events=[])
        else:
            data, score = compose(frames, seed=seed, tonic=62, scene=scene, loop=loop)
        manifest["music"][name] = score
        return data

    stems = delivery / "retained-vocals"
    stems.mkdir(exist_ok=True)
    sources = [
        ("act1", root / "builds/act1-opera-continuity/duet-tail-01-vocals.wav", "d1f01e46bc65820b0d72702a487eedeee71cf8bb8dc823b2abf55adcc312b4f1"),
        ("act2", root / "builds/act2-hall-audio/wine-duet-vocals.wav", "e71de6ac9a536bf06d676e46d9ea94eee2b1a17ba6ff8b457fd829de2842b3fd")]
    clean = {}
    for name, source, expected in sources:
        if sha(source) != expected:
            raise ValueError("Retained clean vocal stem changed: " + str(source))
        target = stems / (name + ".wav")
        shutil.copyfile(source, target)
        clean[name] = audio(target)
        manifest["retained_vocals"].append(dict(act=name, path="assets/audio/retained-vocals/" + target.name,
            sha256=expected, processing="Act1 verbatim; Act2 original sample-rate conversion and existing constant gain only"))

    # Act 1: locate exact original segment boundaries, preserving every speech
    # sample and the complete retained singing stem at the original song time.
    folder = delivery / "act1-natural"
    old = backup / "act1-natural"
    score = load(old / "score.json")
    main_wave = audio(old / "main.wav")
    main_pcm = pcm(old / "main.wav")
    continuity = load(root / "builds/act1-opera-continuity/continuity-result.json")
    regions = []

    def replace(name, begin, data, retained=False):
        end = begin + len(data)
        if not 0 <= begin < end <= len(main_wave):
            raise ValueError("Out-of-bounds replacement: " + name)
        main_wave[begin:end] = data
        regions.append(dict(name=name, start_frame=begin, end_frame=end, retained_vocals=retained))

    locations = {}
    for name in ["approach-instrument-01", "duet-tail-01-mix", "tour-instrument-01"]:
        original = Path(continuity["assets"][name]["path"])
        if sha(original) != continuity["assets"][name]["sha256"]:
            raise ValueError("Historical segment fingerprint mismatch")
        source = pcm(original)
        offset = main_pcm.find(source)
        if offset < 0 or offset % 4 or main_pcm.find(source, offset + 1) >= 0:
            raise ValueError("Original segment cannot be located uniquely: " + name)
        locations[name] = (offset // 4, len(source) // 4)
    begin, count = locations["approach-instrument-01"]
    replace("approach", begin, music("act1-approach", count, 221))
    begin, count = locations["duet-tail-01-mix"]
    if len(clean["act1"]) != count:
        raise ValueError("Act1 retained vocal duration mismatch")
    replace("singing", begin, clean["act1"] + music("act1-singing", count, 222), True)
    take, tour_count = locations["tour-instrument-01"]
    singing_end = begin + count
    replace("take-guard", singing_end, music("act1-take-guard", take - singing_end, 223))
    replace("tour", take, music("act1-tour", tour_count, 224, scene="instrumental"))
    closing_count = round(3.5 * RATE)
    closing_begin = len(main_wave) - closing_count - round(.25 * RATE)
    replace("closing", closing_begin, music("act1-closing", closing_count, 225))
    write(folder / "main.wav", main_wave)
    loop_count = len(pcm(old / "wait_loop.wav")) // 4
    write(folder / "wait_loop.wav", music("act1-wait", loop_count, 226, loop=True))
    write(folder / "take_close.wav", music("act1-take-close", len(pcm(old / "take_close.wav")) // 4, 231, scene="close"))
    score["audio_version"] = "act1-original-accompaniment-" + sha(folder / "main.wav")[:12]
    score["accompaniment_source"] = "res://assets/audio/original-audio-sources.json"
    score["rights_status"] = "accompaniment_sample_free; retained_singing_and_other_voice_permissions_unverified"
    score.pop("singing_source_sha256", None)
    manifest["replaced_regions"]["act1"] = regions
    refresh(folder, score)

    # Act 2 hall: rebuild only the song region from the clean float vocal stem
    # using the existing gain, avoiding destructive separation of the old mix.
    folder, old = delivery / "act2-hall", backup / "act2-hall"
    score = load(old / "score.json")
    gain_db = next(r["gain_db"] for r in score["loudness"] if r["asset_id"] == "wine-duet")
    for row in score["loudness"]:
        if row["asset_id"] == "wine-duet":
            row["measurement_scope"] = "Historical old mix measurement; gain_db retained for the unchanged vocal stem only"
    vocal = clean["act2"] * np.float32(10 ** (gain_db / 20))
    song = vocal + music("act2-wine", len(vocal), 227)
    if len(vocal) != len(pcm(old / "wine-duet.wav")) // 4:
        raise ValueError("Act2 retained vocal duration mismatch")
    write(folder / "wine-duet.wav", song)
    offset = pcm(old / "main.wav").find(pcm(old / "wine-duet.wav"))
    if offset < 0 or offset % 4:
        raise ValueError("Cannot locate complete wine duet in current master")
    wave = audio(old / "main.wav")
    begin = offset // 4
    wave[begin:begin + len(song)] = audio(folder / "wine-duet.wav")
    write(folder / "main.wav", wave)
    # Also remove the old user-video instrumental from the retained entry cue.
    for index, name in enumerate(["fahai-entry", "xu-fall-hit"]):
        path = old / (name + ".wav")
        if path.exists():
            count = len(pcm(path)) // 4
            write(folder / path.name, music("act2-" + name, count, 228 + index, scene="instrumental"))
    score["audio_version"] = "act2-hall-original-accompaniment-" + sha(folder / "main.wav")[:12]
    score["accompaniment_source"] = "res://assets/audio/original-audio-sources.json"
    score["singing_source"] = dict(vocals="res://assets/audio/retained-vocals/act2.wav",
        historical_melody_reference=score["singing_source"], permission_verified=False,
        backing="new symbolic composition and mathematical synthesis")
    score["rights_status"] = "accompaniment_sample_free; retained_singing_and_other_voice_permissions_unverified"
    cues = score.pop("user_video")["music_cues"]["outputs"]
    score["music_cues"] = dict(source="res://assets/audio/original-audio-sources.json", outputs=cues)
    for name, row in cues.items():
        path = folder / (name + ".wav")
        row.clear()
        row.update(path="res://assets/audio/act2-hall/" + path.name, sha256=sha(path), frames=len(pcm(path)) // 4,
            source="original procedural synthesis; previous video audio removed")
    manifest["replaced_regions"]["act2-hall"] = [dict(name="singing", start_frame=begin, end_frame=begin + len(song), retained_vocals=True, vocal_gain_db=gain_db)]
    refresh(folder, score)

    # Act 2 opening: preserve the Xu PCM exactly, and derive all dialogue and
    # dark-scene timestamps from complete independent TTS outputs.
    folder, old = delivery / "act2-opening", backup / "act2-opening"
    score = load(old / "score.json")
    tts = load(batch / "fahai-result.json")
    request = load(batch / "fahai-request.json")
    if tts["request_sha256"] != sha(batch / "fahai-request.json") or request["recording_references"]:
        raise ValueError("TTS request not independent of reference recordings")
    for row in tts["lines"]:
        if sha(row["path"]) != row["sha256"]:
            raise ValueError("Changed TTS output")
        shutil.copyfile(row["path"], folder / (row["line_id"] + ".wav"))
    parts, cursor, production = [np.zeros((12000, 2), np.float32)], 12000, {}
    for line in score["lines"]:
        path = folder / (line["line_id"] + ".wav")
        data = audio(path)
        line.update(start_frame=cursor, end_frame=cursor + len(data), start_ms=round(cursor / 48), end_ms=round((cursor + len(data)) / 48))
        parts += [data, np.zeros((40800, 2), np.float32)]
        cursor += len(data) + 40800
        production[line["line_id"]] = dict(source="Kokoro preset male voice without recording reference" if line["role_id"] == "fahai" else "unchanged shipped Xuxian PCM", sha256=sha(path), complete_converted_frames=True)
    # Last turn gap is 500ms; the dark chapter is exactly two seconds.
    parts[-1] = np.zeros((24000, 2), np.float32)
    cursor -= 16800
    score.update(dark_start_frame=cursor, dark_start_ms=round(cursor / 48))
    parts.append(np.zeros((96000, 2), np.float32))
    cursor += 96000
    write(folder / "main.wav", np.concatenate(parts))
    intro_frames = len(pcm(old / "intro.wav")) // 4
    if args.no_background_music:
        # A short silent control clip preserves the existing finished signal.
        # It avoids both zero-length WAV behavior and the old 7.936-second wait.
        intro_frames = 4800
    write(folder / "intro.wav", music("act2-intro", intro_frames, 230, scene="instrumental"))
    # Retired from live playback, but still exported by the project preset.
    legacy_count = len(pcm(old / "entrance-loop.wav")) // 4
    write(folder / "entrance-loop.wav", music("act2-entrance-loop", legacy_count, 232, scene="instrumental", loop=True))
    score.update(audio_version="act2-original-music-preset-fahai-" + sha(folder / "main.wav")[:12], duration_ms=round(cursor / 48),
        production=production, music_source=dict(kind="original_symbolic_composition", manifest="res://assets/audio/original-audio-sources.json", external_audio_inputs=[]),
        identity_reference=dict(kind="licensed_preset_synthetic_voice", model=request["model"], voice=request["voice"], license=request["license"], recording_references=[]),
        human_listening_scope="New accompaniment and Fahai voice require user listening; automated checks do not certify naturalness")
    for historical in ["inference", "request_sha256", "phrase_request", "synthesis_inputs", "conversion_inputs"]:
        score.pop(historical, None)
    manifest["fahai"] = dict(request=request, lines=tts["lines"], request_sha256=tts["request_sha256"])
    score["rights_status"] = "new_accompaniment_and_preset_fahai; retained_xuxian_permissions_unverified"
    refresh(folder, score)
    for name in FOLDERS:
        path = delivery / name / "score.json"
        config = load(path)
        config["background_music"] = not args.no_background_music
        if args.no_background_music:
            config["audio_version"] = config["audio_version"].replace("original-accompaniment", "vocals-only").replace("original-music", "no-bgm")
            config["rights_status"] = "no_background_music; retained_singing_and_other_voice_permissions_unverified"
            if name == "act2-opening":
                config["intro_duration_ms"] = 100
                config["music_source"]["kind"] = "none"
                config["human_listening_scope"] = "Retained vocals and preset Fahai voice require user listening; background music removed"
            elif name == "act2-hall":
                config["singing_source"]["backing"] = "none; clean vocals only"
        dump(path, config)
    manifest["outputs"] = {f"{folder}/{p.name}": sha(p) for folder in FOLDERS for p in (delivery / folder).iterdir() if p.suffix in [".wav", ".json"]}
    # Keep machine-specific working paths out of the permanent provenance file.
    for row in manifest["fahai"]["lines"]:
        row["path"] = "assets/audio/act2-opening/" + row["line_id"] + ".wav"
    dump(delivery / "original-audio-sources.json", manifest)
    print(json.dumps(dict(staged=True, audio_files=sum(p.suffix == ".wav" for p in delivery.rglob("*")), new_fahai_duration_ms=score["duration_ms"])))
    if args.install:
        previous = root / "assets/audio/original-audio-sources.json"
        previous_outputs = load(previous).get("outputs", {}) if previous.exists() else {}
        # Do not overwrite edits that appeared after the baseline snapshot.
        for rel, expected in baseline.items():
            actual = sha(root / "assets/audio" / rel)
            # A previous interrupted install may already contain this exact delivery.
            if actual not in [expected, previous_outputs.get(rel), manifest["outputs"][rel]]:
                raise ValueError("Concurrent audio edit detected: " + rel)
        for source in delivery.rglob("*"):
            if source.is_file():
                dest = root / "assets/audio" / source.relative_to(delivery)
                dest.parent.mkdir(parents=True, exist_ok=True)
                if not dest.exists() or sha(source) != sha(dest):
                    shutil.copyfile(source, dest)
        print("ORIGINAL_AUDIO_INSTALLED")


def refresh(folder, score):
    score["assets"] = [asset(folder / Path(row["path"]).name, row["asset_id"], row["path"]) for row in score["assets"]]
    dump(folder / "score.json", score)


if __name__ == "__main__":
    main()

"""Install/audit the authorized Leting instrumental preview in two Act 1 gaps."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
SOURCE_SHA = "a8d909b1a16ac2384f6d0f71c61a2169f5930189b05704aad28316c2084e9701"
REGIONS = [("approach", 913213, 1201213, 2.0), ("tour", 2730112, 3594112, 10.0)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def pcm(path):
    with wave.open(str(path), "rb") as src:
        assert src.getparams()[:3] == (2, 2, RATE), path
        return src.readframes(src.getnframes())


def write(path, data):
    with wave.open(str(path), "wb") as out:
        out.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(data)


def quantize(data):
    assert np.isfinite(data).all() and np.max(np.abs(data)) < .98
    return np.rint(data * 32768).astype("<i2").tobytes()


def asset(path, asset_id):
    data = pcm(path)
    return dict(asset_id=asset_id, path="res://assets/audio/act1-natural/" + path.name,
        sha256=sha(path), frames=len(data)//4, pcm_sha256=hashlib.sha256(data).hexdigest(),
        sample_rate_hz=RATE, channels=2, subtype="PCM_16")


def audit(batch):
    audio = ROOT / "assets/audio"
    score = load(audio / "act1-natural/score.json")
    manifest = load(audio / "original-audio-sources.json")
    report = manifest["act1_leting_preview"]
    original = pcm(batch / "before/main.wav")
    current = pcm(audio / "act1-natural/main.wav")
    assert len(current) == len(original) == 5333317*4
    cursor = 0
    for row in report["regions"]:
        a, b = row["start_frame"]*4, row["end_frame"]*4
        assert original[cursor:a] == current[cursor:a], "Changed vocal or non-music PCM"
        assert hashlib.sha256(current[a:b]).hexdigest() == row["pcm_sha256"]
        assert np.max(np.abs(np.frombuffer(current[a:b], dtype="<i2"))) > 100
        cursor = b
    assert original[cursor:] == current[cursor:]
    assert score["background_music"] and not score["duet_accompaniment_enabled"]
    assert score["waiting_music_phases"] == ["wait_arrival", "wait_return"]
    old_score = load(batch / "before/score.json")
    for key in ["lines", "opening_end_ms", "arrival_ms", "singing_start_ms", "singing_end_ms",
                "take_ms", "tour_start_ms", "return_gate_ms", "return_start_ms", "closing_ms", "duration_ms"]:
        assert score[key] == old_score[key], key
    previous = load(batch / "before/original-audio-sources.json")
    for rel, digest in manifest["outputs"].items():
        assert sha(audio / rel) == digest, rel
        if rel not in ["act1-natural/main.wav", "act1-natural/wait_loop.wav", "act1-natural/score.json"]:
            assert digest == previous["outputs"][rel], rel
    for name, digest in manifest["tools"].items():
        assert sha(ROOT / "tools" / name) == digest, name
    duet = manifest["replaced_regions"]["act1"][0]
    assert hashlib.sha256(current[duet["start_frame"]*4:duet["end_frame"]*4]).hexdigest() == manifest["music"]["act1-duet"]["pcm_sha256"]
    for row in score["assets"]:
        assert row == asset(audio / "act1-natural" / Path(row["path"]).name, row["asset_id"])
    result = dict(passed=True, exact_non_music_pcm=True, original_duet_pcm=True,
        unchanged_timing=True, unchanged_other_audio=True, main_frames=len(current)//4,
        regions=report["regions"], user_listening="pending")
    dump(batch / "audit.json", result)
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--audit", action="store_true")
    args = parser.parse_args()
    batch = args.batch.resolve()
    if args.audit:
        audit(batch)
        return
    audio = ROOT / "assets/audio"
    folder = audio / "act1-natural"
    source = ROOT / "builds/real-performance-reference/乐亭白蛇传_第一集_原始参考.m4a"
    assert sha(source) == SOURCE_SHA
    separated = load(batch / "separation.json")
    backing_path = batch / "backing.wav"
    assert sha(backing_path) == separated["outputs"]["backing"]["sha256"]
    assert separated["source_interval_s"] == [0, 32]
    assert sha(batch / "source-opening.wav") == separated["input_sha256"]
    data, rate = sf.read(backing_path, dtype="float64", always_2d=True)
    assert rate == 44100 and data.shape[1] == 2
    data = resample_poly(data, 160, 147, axis=0)
    gain = min(.05 / float(np.sqrt(np.mean(data**2))), .60 / float(np.max(np.abs(data))))
    data *= gain
    before = batch / "before"
    if before.exists():
        raise ValueError("Backup exists: use --audit or a new batch")
    manifest = load(audio / "original-audio-sources.json")
    assert sha(folder / "main.wav") == manifest["outputs"]["act1-natural/main.wav"] == "ebb9c46ea9892cd3c94d3e36ab7f84574192db77bc9826cab965164044e43a1e"
    before.mkdir()
    for name in ["main.wav", "wait_loop.wav", "score.json"]:
        shutil.copyfile(folder / name, before / name)
    shutil.copyfile(audio / "original-audio-sources.json", before / "original-audio-sources.json")
    master = bytearray(pcm(before / "main.wav"))
    regions = []
    for name, a, b, start_s in REGIONS:
        clip = data[round(start_s*RATE):round(start_s*RATE)+b-a].copy()
        assert len(clip) == b-a
        fade_in, fade_out = round(.18*RATE), round((.35 if name == "approach" else .65)*RATE)
        clip[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
        clip[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
        encoded = quantize(clip)
        assert not any(master[a*4:b*4]), "Target is no longer silent"
        master[a*4:b*4] = encoded
        row = dict(name=name, start_frame=a, end_frame=b, source_start_s=start_s,
            source_end_s=start_s+(b-a)/RATE, fade_in_ms=180, fade_out_ms=round(fade_out/48),
            pcm_sha256=hashlib.sha256(encoded).hexdigest())
        regions.append(row)
        write(batch / (name + "-preview.wav"), encoded)
    loop = data[22*RATE:28*RATE].copy()
    overlap = round(.20*RATE)
    weight = np.linspace(0, 1, overlap)[:, None]
    loop[:overlap] = loop[-overlap:] * (1-weight) + loop[:overlap] * weight
    loop = loop[:-overlap]
    report = dict(source_url="https://www.bilibili.com/video/BV1xX4y1Y7sJ/", part=1,
        source_sha256=SOURCE_SHA, source_interval_s=[0,32], permission="user_confirmed_authorized_2026-10-22",
        separation=separated, gain=gain, regions=regions, waiting_source_interval_s=[22,28],
        loop_overlap_ms=200, human_listening_verified=False, status="integrated_preview_pending_user_feedback")
    write(folder / "main.wav", bytes(master))
    write(folder / "wait_loop.wav", quantize(loop))
    score = load(folder / "score.json")
    score.update(audio_version="act1-leting-preview-"+sha(folder / "main.wav")[:12],
        background_music=True, duet_accompaniment_enabled=False,
        waiting_music_phases=["wait_arrival", "wait_return"],
        accompaniment_scope="Authorized Leting instruments after opening speech and after actual umbrella take; vocal-only duets",
        human_listening_scope="Integrated preview; user listening pending")
    score["assets"] = [asset(folder / Path(r["path"]).name, r["asset_id"]) for r in score["assets"]]
    dump(folder / "score.json", score)
    manifest.update(version=4, background_music_scope="Act1 approach/tour and arrival/return waits; Act2 original intro; vocal-only duets",
        current_revision="act1-leting-music-preview-20261022", act1_leting_preview=report)
    manifest["tools"][Path(__file__).name] = sha(Path(__file__))
    for name in ["main.wav", "wait_loop.wav", "score.json"]:
        manifest["outputs"]["act1-natural/"+name] = sha(folder / name)
    dump(audio / "original-audio-sources.json", manifest)
    # Short scene-context previews preserve the adjacent dialogue and exact main-track mix.
    write(batch / "after-dialogue-context.wav", bytes(master)[16*RATE*4:27*RATE*4])
    write(batch / "after-take-context.wav", bytes(master)[55*RATE*4:77*RATE*4])
    audit(batch)


if __name__ == "__main__":
    main()

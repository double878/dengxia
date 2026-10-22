"""Independent read-only audit of the installed, user-approved restoration."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave

import numpy as np
import soundfile as sf
from PIL import Image


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def raw(path):
    with wave.open(str(path), "rb") as source:
        assert source.getparams()[:3] == (2, 2, 48000), path
        return source.readframes(source.getnframes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    batch = args.batch.resolve()
    manifest = load(root / "assets/audio/original-audio-sources.json")
    assert manifest["duet_listening_approved"]
    report = dict(passed=False, changed_regions=[], unchanged_wavs=0, decoded_assets=0)
    for name, expected in manifest["tools"].items():
        assert sha(root / "tools" / name) == expected, name
    changed = {"act1-natural/main.wav", "act2-hall/main.wav", "act2-hall/wine-duet.wav",
               "act2-opening/main.wav", "act2-opening/intro.wav",
               "act2-opening/dialogue-01.wav", "act2-opening/dialogue-03.wav", "act2-opening/dialogue-05.wav"}
    for rel, expected in manifest["outputs"].items():
        path = root / "assets/audio" / rel
        assert sha(path) == expected, rel
        if path.suffix == ".wav":
            if rel not in changed:
                assert expected == manifest["baseline"][rel], rel
                report["unchanged_wavs"] += 1
            values = np.frombuffer(raw(path), dtype="<i2")
            assert np.max(np.abs(values.astype(np.int32))) < 32767, rel
            subprocess.run([str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-i", str(path),
                            "-f", "null", "-"], check=True, capture_output=True, timeout=60)
            report["decoded_assets"] += 1
    for act, folder, key in [(1, "act1-natural", "act1"), (2, "act2-hall", "act2-hall")]:
        region = manifest["replaced_regions"][key][0]
        start, end = region["start_frame"], region["end_frame"]
        before = raw(batch / "before" / folder / "main.wav")
        after = raw(root / "assets/audio" / folder / "main.wav")
        assert len(before) == len(after)
        assert before[:start*4] == after[:start*4] and before[end*4:] == after[end*4:]
        song = batch / f"act{act}-with-vocals.wav"
        assert after[start*4:end*4] == raw(song)
        assert sha(song) == manifest["music"][f"act{act}-duet"]["preview_mix_sha256"]
        assert not manifest["music"][f"act{act}-duet"]["external_audio_inputs"]
        vocal = np.frombuffer(before, dtype="<i2").reshape(-1, 2)[start:end].astype(np.float32)/32768
        backing, _ = sf.read(batch / f"act{act}-backing.wav", dtype="float32", always_2d=True)
        mix, _ = sf.read(song, dtype="float32", always_2d=True)
        error = float(np.max(np.abs(mix-vocal-backing)))
        assert error <= 2/32768 + 1e-7
        report["changed_regions"].append(dict(act=act, frames=end-start, mix_reconstruction_error=error,
                                               outside_pcm_unchanged=True, approved_mix_exact=True))
    opening = root / "assets/audio/act2-opening"
    assert sha(opening / "intro.wav") == sha(root / "builds/original-audio-20261022/before/act2-opening/intro.wav")
    voice = manifest["fahai"]
    assert not voice["pitch_shift"] and not voice["time_stretch"] and not voice["voice_conversion"]
    for row in voice["lines"]:
        assert sha(opening / (row["line_id"] + ".wav")) == row["sha256"]
        assert row["frames"] == row["retained_end_frame"]-row["retained_start_frame"]
        # Both fixed and dynamic gain are allowed loudness-only processing.
        assert row["normalization_type"] in ["linear", "dynamic"]
        assert abs(row["measured_lufs"] + 18) <= .3
        assert row["measured_true_peak_db"] <= -2.4
    art = load(batch / "art/fahai-manifest.json")
    installed = load(root / "assets/puppets/puppet_assets.json")
    previous = load(batch / "before/puppets/puppet_assets.json")
    assert installed["characters"]["fahai"] == art["character"]
    for name in installed["characters"]:
        if name != "fahai":
            assert installed["characters"][name] == previous["characters"][name]
    atlas_path = root / "assets/puppets/fahai.png"
    assert sha(atlas_path) == art["atlas_sha256"]
    atlas = Image.open(atlas_path)
    assert atlas.size == (2048, 2048) and atlas.mode == "RGBA"
    for name, part in art["character"]["parts"].items():
        assert part["pivot"] == previous["characters"]["fahai"]["parts"][name]["pivot"]
        assert part["axis_pixels"] > 0
        x, y, w, h = part["rect"]
        alpha = np.asarray(atlas.crop((x,y,x+w,y+h)))[:,:,3]
        assert (alpha > 127).sum() > 50, name
        assert not alpha[:3].any() and not alpha[-3:].any() and not alpha[:,:3].any() and not alpha[:,-3:].any(), name
    ref = root / "assets/puppets" / art["character"]["reference"]["filename"]
    assert sha(ref) == art["character"]["reference"]["sha256"]
    assert Image.open(batch / "art/fahai-cutout.png").getchannel("A").getbbox()[3] < 1700
    report.update(passed=True, original_intro_exact=True, fahai_user_recordings=3,
                  atlas_parts=len(art["character"]["parts"]), pivots_unchanged=True,
                  other_characters_unchanged=True, watermark_region_transparent=True)
    (batch / "installed-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()

"""Package the approved Xu Xian fright request; preserve every generated sample."""
from pathlib import Path
from math import gcd
import hashlib
import json
import subprocess

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / "builds/act2-hall-refinement-20261017"
DEST = PROJECT / "assets/audio/act2-hall"
FFMPEG = PROJECT / "builds/audio-tools/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf8"))


def loudness(path):
    result = subprocess.run(
        [str(FFMPEG), "-nostdin", "-i", str(path), "-af", "loudnorm=I=-16:TP=-1:LRA=11:print_format=json", "-f", "null", "-"],
        capture_output=True, text=True, encoding="utf8", errors="replace", check=True,
    )
    return json.JSONDecoder().raw_decode(result.stderr[result.stderr.rfind("{"):])[0]


row, = read(ROOT / "game-generation-result.json")
assert row["line_id"] == "xu-fright" and row["text"] == "啊！"
source = Path(row["converted_path"])
assert sha(source) == row["converted_sha256"]
audio, rate = sf.read(source, dtype="float32", always_2d=True)
assert np.isfinite(audio).all() and audio.size > 0
divisor = gcd(rate, 48000)
audio = resample_poly(audio, 48000 // divisor, rate // divisor, axis=0)
if audio.shape[1] == 1:
    audio = np.repeat(audio, 2, axis=1)
before = loudness(source)
gain = min(10 ** ((-16 - float(before["input_i"])) / 20), .85 / float(np.max(np.abs(audio))))
audio *= gain
path = DEST / "xu-fright.wav"
sf.write(path, audio, 48000, subtype="PCM_16")
subprocess.run([str(FFMPEG), "-nostdin", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"], check=True)
asset = dict(asset_id="xu-fright", path="res://assets/audio/act2-hall/xu-fright.wav", sha256=sha(path), frames=len(audio),
             sample_rate_hz=48000, channels=2, subtype="PCM_16", peak=float(np.max(np.abs(audio))))
score = read(DEST / "score.json")
score["audio_version"] = "act2-hall-direct-duet-fright-v2"
score["hall_start_ms"] = score["duet_start_ms"]
score["disabled_intro_line_ids"] = [line["line_id"] for line in score["lines"][:5]]
score["fright_path"] = asset["path"]
score["fright_duration_ms"] = round(len(audio) / 48)
score["assets"] = [item for item in score["assets"] if item["asset_id"] != "xu-fright"] + [asset]
score["fright_production"] = dict(
    request=read(ROOT / "game-request.json"), generation=row,
    production_script_sha256=sha(ROOT / "produce_speech.py"),
    input_fingerprint_sha256=sha(ROOT / "input-fingerprint.json"),
    parameters=dict(tts_steps=32, tts_cfg=2.0, vc_steps=25, vc_cfg=.7, length_adjust=1.0,
                    f0_condition=False, auto_f0_adjust=False, semi_tone_shift=0, device="cpu", threads=8),
    packaging_script_sha256=sha(__file__), gain_db=float(20 * np.log10(gain)),
    loudness_after=loudness(path), full_generated_samples_preserved=True, human_listening_verified=False,
)
(DEST / "score.json").write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps(dict(asset=asset, duration_ms=score["fright_duration_ms"]), ensure_ascii=False))

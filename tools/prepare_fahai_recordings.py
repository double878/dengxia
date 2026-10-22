"""Prepare the user's three Fahai recordings in a review-only batch directory."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
import soundfile as sf

RATE = 48000
NAMES = {"dialogue-01": "2026年10月22日 14点43分.m4a",
         "dialogue-03": "2026年10月22日 14点45分.m4a",
         "dialogue-05": "2026年10月22日 14点45分(2).m4a"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(ffmpeg, args):
    return subprocess.run([str(ffmpeg), "-hide_banner", "-nostdin", "-y", *args],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", check=True, timeout=60)


def measurement(ffmpeg, path):
    log = run(ffmpeg, ["-i", str(path), "-af", "loudnorm=I=-18:TP=-2.5:LRA=9:print_format=json",
                       "-f", "null", "-"]).stderr
    return json.loads(log[log.rfind("{"):log.rfind("}") + 1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--batch", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    out = args.batch.resolve() / "fahai-recordings"
    out.mkdir(parents=True, exist_ok=True)
    manifest = dict(version=1, tool_sha256=sha(__file__), game_assets_installed=False,
                    human_listening_verified=False, pitch_shift=False, time_stretch=False,
                    voice_conversion=False, reverb=False, lines=[])
    for line_id, name in NAMES.items():
        source = args.source_dir / name
        decoded = out / (line_id + "-decoded.wav")
        run(args.ffmpeg, ["-v", "error", "-xerror", "-i", str(source), "-ar", str(RATE),
                           "-ac", "2", "-c:a", "pcm_f32le", str(decoded)])
        audio, rate = sf.read(decoded, dtype="float32", always_2d=True)
        window = 480
        energy = np.sqrt(np.mean(audio[:len(audio)//window*window].reshape(-1, window, 2)**2, axis=(1, 2)))
        active = np.flatnonzero(energy > 10 ** (-42 / 20))
        if len(active) < 20:
            raise ValueError(f"No usable spoken recording: {source}")
        # Only external margins are removed; all pauses inside remain intact.
        begin = max(0, int(active[0]) * window - round(.22 * RATE))
        end = min(len(audio), (int(active[-1]) + 1) * window + round(.30 * RATE))
        prepared = out / (line_id + "-filtered.wav")
        filters = (f"atrim=start_sample={begin}:end_sample={end},asetpts=PTS-STARTPTS,"
                   "highpass=f=65,afftdn=nr=8:nf=-50:tn=1,"
                   "equalizer=f=220:t=q:w=1:g=-1.8,"
                   "equalizer=f=2800:t=q:w=0.8:g=1.2,lowpass=f=11000,"
                   "acompressor=threshold=0.125:ratio=1.7:attack=18:release=150:makeup=1")
        run(args.ffmpeg, ["-v", "error", "-xerror", "-i", str(decoded), "-af", filters,
                           "-ar", str(RATE), "-ac", "2", "-c:a", "pcm_f32le", str(prepared)])
        measured = measurement(args.ffmpeg, prepared)
        target = out / (line_id + ".wav")
        normalizer = ("loudnorm=I=-18:TP=-2.5:LRA=9:linear=true:"
                      f"measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:"
                      f"measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}:"
                      f"offset={measured['target_offset']}:print_format=json")
        log = run(args.ffmpeg, ["-v", "info", "-xerror", "-i", str(prepared), "-af", normalizer,
                               "-ar", str(RATE), "-ac", "2", "-c:a", "pcm_s16le", str(target)]).stderr
        stats = json.loads(log[log.rfind("{"):log.rfind("}") + 1])
        result, rate = sf.read(target, dtype="float32", always_2d=True)
        if rate != RATE or len(result) != end - begin or not np.isfinite(result).all() or np.abs(result).max() >= .98:
            raise ValueError(f"Unexpected length, invalid samples or clipping: {target}")
        after = measurement(args.ffmpeg, target)
        if abs(float(after["input_i"]) + 18) > .3:
            raise ValueError(f"Loudness normalization failed: {target}")
        manifest["lines"].append(dict(line_id=line_id, source_filename=name,
            source_sha256=sha(source), source_decoded_frames=len(audio),
            retained_start_frame=begin, retained_end_frame=end,
            duration_ms=len(result)/48, frames=len(result), sample_rate_hz=rate,
            channels=2, subtype="PCM_16", sha256=sha(target),
            filters=filters, normalization=normalizer, normalization_type=stats["normalization_type"],
            measured_lufs=float(after["input_i"]), measured_true_peak_db=float(after["input_tp"]),
            path=str(target)))
    path = out / "recordings-manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(dict(lines=len(manifest["lines"]), output=str(out),
                         duration_ms=[r["duration_ms"] for r in manifest["lines"]])))


if __name__ == "__main__":
    main()

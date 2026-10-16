"""Offline extraction of the user's original finale voices; no synthesis."""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    sys.path.insert(0, str(args.model_root / "YingMusic-Singer-Plus"))
    import numpy as np
    import soundfile as sf
    import torch
    import torchaudio
    from src.third_party.MusicSourceSeparationTraining.inference_api import Separator

    weights = args.model_root / "weights/ckpts/MelBandRoformer.ckpt"
    config = args.model_root / "weights/ckpts/config_vocals_mel_band_roformer_kj.yaml"
    sources = [ROOT / "assets/audio/act3-mountain" / name for name in
               ["finale-arrival-original.wav", "finale-blessing-original.wav"]]
    fingerprint = dict(weights_sha256=sha(weights), config_sha256=sha(config),
                       sources={p.name: sha(p) for p in sources},
                       script_sha256=sha(__file__))
    args.output.mkdir(parents=True, exist_ok=True)
    report_path = args.output / "separation.json"
    if report_path.exists():
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if report["inputs"] != fingerprint:
            raise ValueError("Inputs changed; use a new output directory")
        for row in report["outputs"]:
            assert sha(args.output / row["file"]) == row["sha256"]
        print("Verified existing voice separation", flush=True)
        return
    torch.set_num_threads(6)
    started = time.monotonic()
    separator = Separator(config_path=str(config), checkpoint_path=str(weights), device="cpu")
    outputs = []
    for source in sources:
        data, rate = sf.read(source, dtype="float32", always_2d=True)
        print("Separating " + source.name, flush=True)
        with torch.inference_mode():
            voice, backing, out_rate = separator.separate(torch.from_numpy(data.T), rate)
        for label, array in [("vocals", voice), ("backing", backing)]:
            assert np.isfinite(array).all()
            original = array
            if out_rate != rate:
                array = torchaudio.functional.resample(torch.from_numpy(array), out_rate, rate).numpy()
            array = array[:, :len(data)]
            if array.shape[1] != len(data):
                raise ValueError("Separation changed duration")
            path = args.output / source.name.replace("original", label)
            if path.exists():
                raise ValueError("Unverified partial output exists: " + str(path))
            sf.write(path, array.T, rate, subtype="FLOAT")
            outputs.append(dict(file=path.name, sha256=sha(path), source=source.name,
                                rate=rate, frames=len(data), peak=float(np.abs(array).max()),
                                model_rate=out_rate, model_frames=original.shape[1]))
    report_path.write_text(json.dumps(dict(inputs=fingerprint, outputs=outputs,
        seconds=time.monotonic() - started, processing="MelBandRoformer voice extraction; resample to source rate; preserve source frame count; no synthesis, voice conversion or time stretching"),
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Voice separation complete", flush=True)


if __name__ == "__main__":
    main()

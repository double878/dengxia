"""Generate Fahai with licensed preset TTS; never load any reference recording."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=Path, required=True)
    args = parser.parse_args()
    batch = args.batch.resolve()
    sys.path.insert(0, str(batch / "deps"))
    os.environ["OMP_NUM_THREADS"] = "4"
    import numpy as np
    import onnxruntime as ort
    import soundfile as sf
    from scipy.signal import resample_poly
    from misaki import zh
    from kokoro_onnx import Kokoro

    models = batch / "models"
    model = models / "kokoro-v1.1-zh.onnx"
    if sha(model) != "859f9ded9f53be16c24857cdab3254a45da53c3afd5ba6ef134c7de3f822e326":
        raise ValueError("ONNX model does not match its published release SHA256")
    files = {p.name: sha(p) for p in [model, models / "voices-v1.1-zh.bin", models / "config.json"]}
    request = dict(model="hexgrad/Kokoro-82M-v1.1-zh", model_revision="01e7505bd6a7a2ac4975463114c3a7650a9f7218",
        license="Apache-2.0", model_card="https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh",
        onnx_release="https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1",
        files=files, voice="zm_010", speed=.86, recording_references=[], pitch_shift=0,
        phrases={"dialogue-01": ["许施主。", "你家娘子，并非凡人。", "贫僧今日，正是为此而来。"],
            "dialogue-03": ["人妖有别。", "莫被她的温情，蒙蔽了双眼。"],
            "dialogue-05": ["端午将至。", "你劝她，喝杯雄黄酒。", "是人是妖。", "一试，便知。"]})
    request_path = batch / "fahai-request.json"
    if request_path.exists() and json.loads(request_path.read_text(encoding="utf8")) != request:
        raise ValueError("Existing request differs; use a new output batch")
    request_path.write_text(json.dumps(request, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    g2p = zh.ZHG2P(version="1.1")
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    # Supply a bounded CPU session instead of ONNX Runtime's default full-host pool.
    session = ort.InferenceSession(str(model), sess_options=options, providers=["CPUExecutionProvider"])
    engine = Kokoro.from_session(session, str(models / "voices-v1.1-zh.bin"), vocab_config=str(models / "config.json"))
    output = batch / "fahai"
    output.mkdir(exist_ok=True)
    result = []
    for line_id, phrases in request["phrases"].items():
        chunks, segments, cursor = [], [], 0
        for i, text in enumerate(phrases):
            phonemes, _ = g2p(text)
            if not phonemes.strip():
                raise ValueError("Empty phonemes: " + text)
            samples, rate = engine.create(phonemes, voice=request["voice"], speed=request["speed"], is_phonemes=True)
            wave = resample_poly(samples, 2, 1).astype(np.float32)
            if rate != 24000 or not len(wave) or not np.isfinite(wave).all():
                raise ValueError("Invalid TTS output")
            chunks.append(wave)
            segments.append(dict(text=text, start_frame=cursor, end_frame=cursor + len(wave), phonemes=phonemes))
            cursor += len(wave)
            if i + 1 < len(phrases):
                pause = round(.55 * 48000)
                chunks.append(np.zeros(pause, np.float32))
                cursor += pause
        wave = np.concatenate(chunks)
        gain = min(.75 / max(float(np.abs(wave).max()), 1e-6), 2.0)
        wave = np.repeat((wave * gain)[:, None], 2, axis=1)
        path = output / (line_id + ".wav")
        sf.write(path, wave, 48000, subtype="PCM_16")
        result.append(dict(line_id=line_id, path=str(path), sha256=sha(path), frames=len(wave),
            complete_phrases=segments, constant_gain=gain, voice=request["voice"], human_listening_verified=False))
        print(json.dumps(dict(generated=line_id, seconds=len(wave) / 48000), ensure_ascii=False), flush=True)
    (batch / "fahai-result.json").write_text(json.dumps(dict(request_sha256=sha(request_path), lines=result), ensure_ascii=False, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    main()

"""Read-only ASR and pause evidence. ASR does not certify voice naturalness."""
import argparse
import json
import os
from pathlib import Path
import sys

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
sys.stdout.reconfigure(encoding='utf8')
PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT / 'builds/baisuzhen-speech-song-comparison'
sys.path.insert(0, str(BASE / 'f5-game-dialogue/deps'))


def main():
    import numpy as np
    import soundfile as sf
    import torch
    import torchaudio
    from transformers import WhisperProcessor, WhisperForConditionalGeneration
    parser = argparse.ArgumentParser()
    parser.add_argument('request', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = json.loads(args.request.read_text(encoding='utf8'))
    torch.set_num_threads(4)
    weights = str(BASE / 'seed-vc-speech/weights/whisper')
    processor = WhisperProcessor.from_pretrained(weights, local_files_only=True)
    model = WhisperForConditionalGeneration.from_pretrained(weights, local_files_only=True).eval()
    results = []
    for row in rows:
        wave, sr = sf.read(row['path'], dtype='float32', always_2d=True)
        assert np.isfinite(wave).all() and len(wave)
        mono = wave.mean(axis=1)
        block = max(1, round(sr * .02))
        rms = np.array([np.sqrt(np.mean(mono[i:i+block] ** 2)) for i in range(0, len(mono), block)])
        silent = rms < max(float(rms.max()) * .025, .001)
        pauses, start = [], None
        for i, quiet in enumerate(np.append(silent, False)):
            if quiet and start is None:
                start = i
            if not quiet and start is not None:
                if (i-start)*.02 >= .14:
                    pauses.append([round(start*.02, 2), round(min(i*.02,len(wave)/sr), 2)])
                start = None
        tensor = torchaudio.functional.resample(torch.from_numpy(mono), sr, 16000)
        inputs = processor(tensor.numpy(), sampling_rate=16000, return_tensors='pt')
        with torch.inference_mode():
            ids = model.generate(inputs.input_features, language='zh', task='transcribe', max_new_tokens=128)
        result = dict(row, transcript=processor.batch_decode(ids, skip_special_tokens=True)[0],
                      seconds=len(wave)/sr, quiet_intervals_s=pauses,
                      human_listening_verified=False)
        results.append(result)
        args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n',encoding='utf8')
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()

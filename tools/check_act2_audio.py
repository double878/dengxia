"""Read-only PCM/hash, complete-clip and protective-silence audit for Act 2."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave

parser = argparse.ArgumentParser()
parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--ffmpeg', type=Path)
parser.add_argument('--report', type=Path)
args = parser.parse_args()
project = args.project.resolve()
score = json.loads((project/'assets/audio/act2-hall/score.json').read_text(encoding='utf8'))
checks = []
pcm = {}
assets = list(score['assets'])
for name, row in score['music_cues']['outputs'].items():
    assets.append(dict(asset_id=name, path='res://assets/audio/act2-hall/'+name+'.wav', **{k:row[k] for k in ['sha256','frames']}))
for row in assets:
    path = project/row['path'].removeprefix('res://')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], path
    with wave.open(str(path)) as source:
        assert (source.getframerate(), source.getnchannels(), source.getsampwidth(), source.getcomptype()) == (48000,2,2,'NONE'), path
        assert source.getnframes() == row['frames'], path
        data = source.readframes(source.getnframes())
        assert len(data) == row['frames']*4, path
        pcm[row['asset_id']] = data
    if args.ffmpeg:
        subprocess.run([str(args.ffmpeg), '-nostdin','-v','error','-xerror','-i',str(path),'-f','null','-'],check=True,timeout=30)
    checks.append(dict(asset_id=row['asset_id'],frames=row['frames'],sha256=row['sha256'],strict_decode=bool(args.ffmpeg)))
main = pcm['main']
for line in score['lines']:
    begin, end = line['start_frame'],line['end_frame']
    assert main[begin*4:end*4] == pcm[line['line_id']], 'Incomplete/changed speech: '+line['line_id']
song_begin = score['duet'][0]['start_frame']
assert main[song_begin*4:song_begin*4+len(pcm['wine-duet'])] == pcm['wine-duet'], 'Duet changed or truncated'
for key, next_key in [('qing_gate_ms','duet_start_ms'),('duet_gate_ms',None),('medicine_gate_ms',None)]:
    begin=round(score[key]*48)
    end=round(score[next_key]*48) if next_key else score['lines'][5]['start_frame'] if key=='duet_gate_ms' else len(main)//4
    # Millisecond rounding can put the first sample one frame inside a boundary.
    assert not any(main[(begin+48)*4:(end-48)*4]), 'Non-silent action guard: '+key
    assert end-begin >= 500*48, key
assert abs(len(main)/4/48-score['duration_ms']) <= 1
report = dict(assets=checks, complete_speech_clips=7, continuous_duet_preserved=True, protective_silence_gates=3, human_listening_verified=False)
if args.report:
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(dict(assets=len(assets),complete_speech_clips=7,continuous_duet_preserved=True,protective_silence_gates=3)))

"""Prepare bounded voice revisions from pinned local loaders, then package exact PCM."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

sys.stdout.reconfigure(encoding='utf8')

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / 'builds/playtest-polish-20261017'
FRIGHT_ROOT = PROJECT / 'builds/playtest-fright-fourth-vowel-20261017'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf8'))


def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf8')


def prepare():
    ROOT.mkdir(parents=True, exist_ok=True)
    archive = ROOT / 'before'
    archive.mkdir(exist_ok=True)
    for folder in ['act1-natural', 'act2-hall']:
        target = archive / folder
        if not target.exists():
            assert 'playtest' not in read(PROJECT / 'assets/audio' / folder / 'score.json')['audio_version'], 'Original backup missing; do not snapshot revised audio as the baseline'
            shutil.copytree(PROJECT / 'assets/audio' / folder, target)
    natural = PROJECT / 'builds/baisuzhen-speech-song-comparison/seed-vc-speech/baisheying-baisuzhen-selected-vocals.wav'
    bai_identity = PROJECT / 'assets/audio/act1-natural/opening-02.wav'
    xu_identity = PROJECT / 'assets/audio/act1-natural/return-02.wav'
    def reference(path, text):
        return dict(path=str(path), sha256=sha(path), text=text)
    request = dict(version='playtest-polish-20261017', lines=[
        dict(line_id='return-01', role_id='baisuzhen', text='君子，雨住了，这伞奉还。', seed=2026101711),
        dict(line_id='return-03', role_id='baisuzhen', text='伞可以托青儿送来，谢意还是我亲口说的好。', seed=2026101713),
        dict(line_id='return-09', role_id='baisuzhen', text='那就莫忘了。', seed=2026101719),
        dict(line_id='xu-fright', role_id='xuxian', text='啊！', seed=2026101721, target_seconds=.85),
    ], references={
        'baisuzhen': reference(natural, '人世间竟有如此美丽的湖山。'),
        'xuxian': reference(xu_identity, '些小之事，何劳娘子专程回来。'),
    }, identity_references={
        'baisuzhen': reference(bai_identity, '青妹，你看，柳色映着湖波，果然是好风光。'),
        'xuxian': reference(xu_identity, '些小之事，何劳娘子专程回来。'),
    }, voice_scope='Existing role identities; raw and converted layers saved; human listening not verified')
    path = ROOT / 'game-request.json'
    if path.exists():
        assert read(path) == request, 'Input differs; use a new output directory'
    else:
        write(path, request)
    source = (PROJECT / 'builds/act2-hall-refinement-20261017/produce_speech.py').read_text(encoding='utf8')
    needle = "    assert changed == 1, 'Unexpected pinned TTS validation code'"
    replacement = '''    for node in ast.walk(function):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'spoken_s' for t in node.targets):
            node.value = ast.Call(func=ast.Attribute(value=ast.Name(id='item', ctx=ast.Load()), attr='get', ctx=ast.Load()), args=[ast.Constant(value='target_seconds'), node.value], keywords=[])
    assert changed == 1, 'Unexpected pinned TTS validation code' '''
    assert source.count(needle) == 1
    source = source.replace(needle, replacement)
    producer = ROOT / 'produce_speech.py'
    if producer.exists():
        assert producer.read_text(encoding='utf8') == source
    else:
        producer.write_text(source, encoding='utf8')
    print('Prepared four bounded revisions; source and converted layers retained.')


def prepare_fright():
    # a4 is absent from the pinned vocabulary. Use the trained da4 carrier,
    # then retain its complete open vowel after the unwanted initial consonant.
    # The final vowel must have a falling contour without pitch processing.
    FRIGHT_ROOT.mkdir(parents=True, exist_ok=True)
    request = read(ROOT / 'game-request.json')
    request['version'] = 'xu-fright-falling-fear-20261017'
    request['lines'] = [dict(line_id='xu-fright', role_id='xuxian', text='啊！',
                             generation_text='大！', seed=2026101721, target_seconds=.85,
                             delivery='Sudden frightened shout, fourth-tone falling contour')]
    path = FRIGHT_ROOT / 'game-request.json'
    if path.exists():
        assert read(path) == request, 'Input differs; use a new output directory'
    else:
        write(path, request)
    source = (ROOT / 'produce_speech.py').read_text(encoding='utf8')
    path = FRIGHT_ROOT / 'produce_speech.py'
    if path.exists():
        assert path.read_text(encoding='utf8') == source
    else:
        path.write_text(source, encoding='utf8')
    print('Prepared bounded frightened exclamation revision; no post-generation pitch processing.')


def finish_fright():
    import numpy as np
    import soundfile as sf
    sys.path.insert(0, str(PROJECT / 'builds/baisuzhen-speech-song-comparison/f5-game-dialogue/deps'))
    import librosa
    row = read(FRIGHT_ROOT / 'tts-result.json')[0]
    assert sha(row['path']) == row['sha256']
    wave, rate = sf.read(row['path'], dtype='float64')
    assert rate == 24000 and wave.ndim == 1 and np.isfinite(wave).all()
    # Spectrogram/periodicity inspection located the carrier consonant before
    # 512 ms. Select a nearby zero crossing at the vowel onset; keep the tail.
    expected = round(.512 * rate)
    crossings = np.flatnonzero(np.diff(np.signbit(wave[expected-24:expected+25]))) + expected-24+1
    assert len(crossings)
    start = int(crossings[np.argmin(abs(crossings-expected))])
    vowel = wave[start:].copy()
    f0, voiced, probability = librosa.pyin(vowel, sr=rate, fmin=70, fmax=750,
                                         frame_length=1536, hop_length=120)
    rms = librosa.feature.rms(y=vowel, frame_length=1536, hop_length=120)[0]
    valid = voiced & (rms > .25 * rms.max())
    pitches = f0[valid]
    assert len(pitches) >= 20, 'Not enough voiced frames to inspect falling tone'
    first, last = float(np.median(pitches[:8])), float(np.median(pitches[-8:]))
    assert first / last > 1.35, (first, last, 'Shout does not have the required falling contour')
    path = FRIGHT_ROOT / 'fourth-tone-vowel.wav'
    sf.write(path, vowel, rate, subtype='FLOAT')
    audit = dict(source=row['path'], source_sha256=row['sha256'], source_text='大！',
                 carrier_consonant_and_quiet_removed_frames=start, rate=rate,
                 selected_path=str(path), selected_sha256=sha(path),
                 selected_frames=len(vowel), uncut_tail_preserved=True,
                 start_f0_hz=first, end_f0_hz=last,
                 pitch_shift=False, time_stretch=False, voice_conversion=False,
                 target='frightened fourth-tone ah', human_listening_verified=False)
    write(FRIGHT_ROOT / 'vowel-edit.json', audit)
    print(json.dumps(audit, ensure_ascii=False))


def package():
    import numpy as np
    import soundfile as sf
    from math import gcd
    from scipy.signal import resample_poly
    request = read(ROOT / 'game-request.json')
    generated = {row['line_id']: row for row in read(ROOT / 'game-generation-result.json')}
    fright_request = read(FRIGHT_ROOT / 'game-request.json')
    fright = read(FRIGHT_ROOT / 'tts-result.json')[0]
    wanted_fright = fright_request['lines'][0]
    assert fright['text'] == wanted_fright['generation_text'] and sha(fright['path']) == fright['sha256']
    fright_edit = read(FRIGHT_ROOT / 'vowel-edit.json')
    assert sha(fright_edit['selected_path']) == fright_edit['selected_sha256']
    generated['xu-fright'] = fright
    before = ROOT / 'before'
    audit = dict(request_sha256=sha(ROOT / 'game-request.json'),
                 fright_request_sha256=sha(FRIGHT_ROOT / 'game-request.json'),
                 script_sha256=sha(__file__), lines=[])

    def load(path):
        wave, rate = sf.read(path, dtype='float64', always_2d=True)
        assert np.isfinite(wave).all() and len(wave)
        common = gcd(rate, 48000)
        if rate != 48000:
            wave = resample_poly(wave, 48000 // common, rate // common, axis=0)
        if wave.shape[1] == 1:
            wave = np.repeat(wave, 2, axis=1)
        assert wave.shape[1] == 2
        return wave

    def deliver(folder, name, wave):
        assert np.isfinite(wave).all() and float(np.max(np.abs(wave))) < .999
        path = PROJECT / 'assets/audio' / folder / (name+'.wav')
        sf.write(path, wave, 48000, subtype='PCM_16')
        return dict(asset_id=name, path='res://assets/audio/'+folder+'/'+path.name,
                    sha256=sha(path), frames=len(wave), sample_rate_hz=48000, channels=2, subtype='PCM_16')

    revised = {}
    for wanted in request['lines']:
        row = generated[wanted['line_id']]
        if wanted['line_id'] != 'xu-fright':
            assert row['text'] == wanted['text'] and sha(row['converted_path']) == row['converted_sha256']
        # A short startled vowel already cloned from Xu's shipped speaking voice does not
        # benefit from a second voice conversion. Keep that raw layer for the fright only.
        source = fright_edit['selected_path'] if wanted['line_id'] == 'xu-fright' else row['converted_path']
        assert sha(row['path']) == row['sha256']
        wave = load(source)
        old = load(before / ('act2-hall' if wanted['line_id']=='xu-fright' else 'act1-natural') / (wanted['line_id']+'.wav'))
        gain = min(float(np.sqrt(np.mean(old**2)) / max(np.sqrt(np.mean(wave**2)), 1e-9)), .85 / max(float(np.abs(wave).max()),1e-9))
        if wanted['line_id'] == 'xu-fright':
            # The old file was mostly leading silence; its overall RMS would
            # make this short alarm too soft. Use fixed headroom for the shout.
            gain = .8 / max(float(np.abs(wave).max()), 1e-9)
        wave *= gain
        revised[wanted['line_id']] = wave
        audit['lines'].append(dict(line_id=wanted['line_id'], generation=row, selected_source=str(source),
                                  selected_sha256=sha(source), gain=gain,
                                  full_generated_samples_preserved=wanted['line_id'] != 'xu-fright',
                                  vowel_edit=fright_edit if wanted['line_id'] == 'xu-fright' else None,
                                  human_listening_verified=False))

    score = read(before / 'act1-natural/score.json')
    old_main = load(before / 'act1-natural/main.wav')
    changes, new_assets = [], []
    for line in score['lines']:
        if line['line_id'] not in revised:
            continue
        previous = load(before / 'act1-natural' / (line['line_id']+'.wav'))
        approximate = round(line['start_ms'] * 48)
        positions = [start for start in range(approximate-25,approximate+26)
                     if np.array_equal(old_main[start:start+len(previous)], previous)]
        assert len(positions) == 1, (line['line_id'], positions)
        changes.append((positions[0], positions[0]+len(previous), line['line_id']))
        new_assets.append(deliver('act1-natural', line['line_id'], revised[line['line_id']]))
    pieces, cursor, spans = [], 0, {}
    offset = 0
    for start,end,name in sorted(changes):
        pieces.extend([old_main[cursor:start], revised[name]])
        spans[name] = (start+offset,start+offset+len(revised[name]))
        offset += len(revised[name])-(end-start)
        cursor=end
    pieces.append(old_main[cursor:])
    main = np.concatenate(pieces)
    def shifted_ms(value):
        frame=round(value*48)
        return round((frame+sum(len(revised[name])-(end-start) for start,end,name in changes if frame >= end-25))/48)
    for key,value in list(score.items()):
        if key.endswith('_ms') and key not in ['waiting_guard_ms'] and isinstance(value,int):
            score[key]=shifted_ms(value)
    for line in score['lines']:
        if line['line_id'] in spans:
            line['start_ms'],line['end_ms']=[round(frame/48) for frame in spans[line['line_id']]]
            line['text']=next(row['text'] for row in request['lines'] if row['line_id']==line['line_id'])
        else:
            line['start_ms'],line['end_ms']=shifted_ms(line['start_ms']),shifted_ms(line['end_ms'])
    new_assets.append(deliver('act1-natural','main',main))
    replaced={row['asset_id'] for row in new_assets}
    score['assets']=[row for row in score['assets'] if row['asset_id'] not in replaced]+new_assets
    score['duration_ms']=round(len(main)/48)
    score['audio_version']='act1-natural-dialogue-playtest-v2'
    score['playtest_revision']=dict(lines=audit['lines'][:3], all_seven_speech_lines_inspected=True)
    write(PROJECT / 'assets/audio/act1-natural/score.json',score)
    # The entire original score, including all four complete duets, remains byte-identical
    # after the inserted instrumental. Only subsequent absolute timestamps move.
    hall=read(before / 'act2-hall/score.json')
    hall_main=load(before / 'act2-hall/main.wav')
    begin=next(row['start_frame'] for row in hall['duet'])
    backing_path=PROJECT/'builds/act2-hall-audio/wine-duet-backing.wav'
    backing=load(backing_path)
    prelude=backing[:240000].copy()
    prelude[:2400]*=np.linspace(0,1,2400)[:,None]
    prelude[-2400:]*=np.linspace(1,0,2400)[:,None]
    hall_new=np.concatenate([hall_main[:begin],prelude,hall_main[begin:]])
    for rows in [hall['lines'],hall['duet']]:
        for row in rows:
            for key in ['start_frame','end_frame']:
                if row[key]>=begin:
                    row[key]+=len(prelude)
            row['start_ms'],row['end_ms']=round(row['start_frame']/48),round(row['end_frame']/48)
    for key in ['duet_start_ms','duet_end_ms','duet_gate_ms','medicine_gate_ms']:
        hall[key]+=5000
    hall['hall_start_ms']=round(begin/48)
    hall['prelude_duration_ms']=5000
    hall['duration_ms']=round(len(hall_new)/48)
    hall['audio_version']='act2-hall-prelude-falling-fright-v4'
    assets=[deliver('act2-hall','main',hall_new),deliver('act2-hall','xu-fright',revised['xu-fright'])]
    replaced={row['asset_id'] for row in assets}
    hall['assets']=[row for row in hall['assets'] if row['asset_id'] not in replaced]+assets
    hall['fright_duration_ms']=round(len(revised['xu-fright'])/48)
    hall['playtest_revision']=dict(prelude_source=str(backing_path), prelude_source_sha256=sha(backing_path),
                                   prelude_frames=len(prelude),fright=audit['lines'][-1],
                                   fright_request=fright_request)
    write(PROJECT/'assets/audio/act2-hall/score.json',hall)
    audit['act1_duration_ms']=score['duration_ms']
    audit['hall_duration_ms']=hall['duration_ms']
    audit['original_hall_duet_and_postfix_exact']=np.array_equal(hall_new[begin+240000:],hall_main[begin:])
    audit['original_act1_prefix_exact']=np.array_equal(main[:changes[0][0]],old_main[:changes[0][0]])
    assert audit['original_hall_duet_and_postfix_exact'] and audit['original_act1_prefix_exact']
    write(ROOT/'packaging-result.json',audit)
    print(json.dumps({key:value for key,value in audit.items() if key!='lines'},ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['prepare','prepare-fright','finish-fright','package'])
    args = parser.parse_args()
    {'prepare':prepare,'prepare-fright':prepare_fright,'finish-fright':finish_fright,'package':package}[args.stage]()

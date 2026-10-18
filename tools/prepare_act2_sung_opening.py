"""Assemble a sung opening while preserving the user's complete Fahai recording."""
import argparse
import hashlib
import json
from math import gcd
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

RATE = 48000


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    wave, rate = sf.read(path, dtype="float64", always_2d=True)
    assert wave.size and wave.shape[1] == 2 and np.isfinite(wave).all()
    if rate != RATE:
        common = gcd(rate, RATE)
        wave = resample_poly(wave, RATE // common, rate // common, axis=0)
    return wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    request = json.loads((args.work / "request.json").read_text(encoding="utf-8"))
    generated = json.loads((args.work / "generated.json").read_text(encoding="utf-8"))
    assert len(generated) == 3
    reference = request["reference"]["outputs"]
    for row in reference.values():
        assert sha(row["path"]) == row["sha256"]
    backing = read(reference["backing"]["path"])
    vocals = read(reference["vocals"]["path"])
    sources = json.loads((args.work.parent / "act2-xuxian-voice-20261016/sources.json").read_text(encoding="utf-8"))
    body = read(sources[1]["audio"])
    if Path(sources[1]["video"]).exists():
        assert sha(sources[1]["video"]) == sources[1]["sha256"]
    else:
        # WeChat temporary sources can expire; require the prior independently verified PCM digest.
        assert hashlib.sha256((body*32768).astype('<i2').tobytes()).hexdigest() == "15fcbc6afc8b17e7c9cf38cd5bd3070feb5cf10f17ddc82c589d09339445feec"
    # The complete source phase is used. A short overlap closes a cyclic instrumental loop.
    loop = backing[:round(4 * RATE)].copy()
    overlap = round(.15 * RATE)
    weights = .5 - .5 * np.cos(np.linspace(0, np.pi, overlap))
    loop[:overlap] = loop[-overlap:] * (1 - weights[:, None]) + loop[:overlap] * weights[:, None]
    loop = loop[:-overlap]
    # Match new verses to the adjacent original voice, then apply one common gain to the whole delivery.
    template = backing[4 * RATE:22 * RATE].copy()
    original_voice = vocals[4 * RATE:22 * RATE]
    active = np.max(np.abs(original_voice), axis=1) > .02
    target_rms = float(np.sqrt(np.mean(original_voice[active] ** 2)))
    opening_path = args.work / "fahai-opening-original.wav"
    sf.write(opening_path, original_voice, RATE, subtype="FLOAT")
    generated[0] = dict(generated[0], path=str(opening_path), sha256=sha(opening_path),
        text="许施主不请到此地", seed=None, delivery="original")
    track = loop.copy()
    lines, segments, joins = [], [], []

    def append(wave, overlap_ms=150):
        nonlocal track
        count = round(overlap_ms * RATE / 1000)
        start = len(track) - count
        weight = (.5 - .5 * np.cos(np.linspace(0, np.pi, count)))[:, None]
        track[-count:] = track[-count:] * (1 - weight) + wave[:count] * weight
        track = np.concatenate([track, wave[count:]])
        joins.append(dict(start_frame=start, overlap_frames=count))
        return start

    for index, item in enumerate(generated):
        assert sha(item["path"]) == item["sha256"]
        new = read(item["path"])
        level = np.max(np.abs(new), axis=1)
        voiced = level > max(.01, float(np.max(level)) * .03)
        assert np.any(voiced)
        gain = 1.0 if item.get("delivery") == "original" else target_rms / float(np.sqrt(np.mean(new[voiced] ** 2)))
        assert .1 < gain < 5
        # The whole generated utterance, including its first consonant, is mixed at one gain.
        # No envelope ever blends an original voice into a new character's word onset.
        duration = max(len(template), len(new)) + round(.25 * RATE)
        mixed = np.zeros((duration, 2), dtype="float64")
        mixed[:len(template)] += template
        mixed[:len(new)] += new * gain
        # Continue an instrumental tail to avoid cutting the voice or leaving dead air.
        extension = duration - len(template)
        mixed[len(template):] += backing[22 * RATE:22 * RATE + extension]
        first, last = np.flatnonzero(voiced)[[0, -1]]
        # Keep each incoming overlap entirely before the generated voice onset.
        overlap_ms = min(150, max(1, int(first * 1000 / RATE) - 30))
        start = append(mixed, overlap_ms=overlap_ms)
        lines.append(dict(line_id=item["id"], role_id=item["role_id"],
            role_name="许仙" if item["role_id"] == "xuxian" else "法海",
            text=item["text"] + "。", delivery=item.get("delivery", "singing"),
            start_frame=start + int(first), end_frame=start + int(last) + 1))
        segments.append(dict(id=item["id"], path=item["path"], sha256=item["sha256"],
            identity=item["identity"], start_frame=start, frames=len(mixed), vocal_gain=gain,
            original_vocal_blend=False, original_vocal_gain=0, full_generated_frames=len(new), seed=item["seed"],
            incoming_overlap_frames=joins[-1]["overlap_frames"],
            delivery=item.get("delivery", "singing"),lyrics_changed=item.get("delivery") != "original"))
        if index == 1:
            # Fahai's six body lines stay as one untouched PCM segment; fades are outside words.
            begin = append(body, overlap_ms=40)
            for number, (a, b, text) in enumerate([
                (0, 11.25, "可记得保和堂里点化你"),
                (11.25, 18.75, "说你被那妖魔缠"),
                (18.75, 25.5, "你妻本是妖蛇变"),
                (25.5, 33.5, "变化人形在你的身边"),
                (33.5, 40.25, "五月端阳可曾应验"),
                (40.25, len(body) / RATE, "现出原形在你的身边")]):
                lines.append(dict(line_id=f"fahai-original-{number+1:02}",role_id="fahai",role_name="法海",
                    text=text,delivery="original",start_frame=begin+round(a*RATE),end_frame=begin+round(b*RATE)))
            segments.append(dict(id="fahai-original-body",start_frame=begin,frames=len(body),
                path=sources[1]["audio"],video_path=sources[1]["video"],video_sha256=sources[1]["sha256"],source_pcm_sha256=hashlib.sha256((body*32768).astype('<i2').tobytes()).hexdigest(),
                voice_conversion=False,lyrics_changed=False,edge_overlap_frames=round(.04*RATE)))

    # A short natural instrumental release follows the last whole syllable, before the established dark scene.
    tail = backing[22 * RATE:24 * RATE].copy()
    tail *= np.cos(np.linspace(0, np.pi / 2, len(tail)))[:, None] ** 2
    append(tail)
    dark_frame = len(track)
    track = np.concatenate([track, np.zeros((2 * RATE, 2))])
    # The entrance and main both share this gain, so the switch cannot cause a gain jump.
    common_gain = min(1., .89 / max(float(np.max(np.abs(track))), float(np.max(np.abs(loop)))))
    track *= common_gain
    loop *= common_gain
    track[:round(.25 * RATE)] *= np.linspace(0, 1, round(.25 * RATE))[:, None]
    args.output.mkdir(parents=True,exist_ok=True)
    assets=[]
    for name,wave in [("main",track),("entrance-loop",loop)]:
        path=args.output/(name+".wav")
        sf.write(path,wave,RATE,subtype="PCM_16")
        decoded,sr=sf.read(path,dtype="float64",always_2d=True)
        assert sr==RATE and len(decoded)==len(wave) and np.max(np.abs(decoded)) < .99
        assets.append(dict(asset_id=name,path="res://assets/audio/act2-opening/"+path.name,
            sha256=sha(path),frames=len(wave),pcm_sha256=hashlib.sha256((decoded*32768).astype('<i2').tobytes()).hexdigest()))
    for row in lines:
        row.update(start_ms=round(row["start_frame"]/48),end_ms=round(row["end_frame"]/48))
    assert all(left["end_frame"]<=right["start_frame"] for left,right in zip(lines,lines[1:])),"Overlapping words at a join"
    score=dict(audio_version="act2-sung-opening-"+assets[0]["sha256"][:12],stage_id=2,scene_id="fahai_advice",
        main_path=assets[0]["path"],duration_ms=round(len(track)/48),dark_start_ms=round(dark_frame/48),
        greeting_gate_ms=0,entrance_loop_path=assets[1]["path"],entrance_crossfade_ms=250,
        splice_frame=next(row["start_frame"] for row in segments if row["id"]=="fahai-original-body"),
        lines=lines,assets=assets,segments=segments,joins=joins,common_gain=common_gain,
        reference_url=request["source_url"],reference_context_sha256=request["reference"]["source"]["sha256"],
        reference_selection_s=[2730,2756],
        fahai_policy="Original reference opening and all six original body lines retain lyrics, voice and speed; only common gain, source separation for the opening and declared edge overlaps.",
        xuxian_policy="Entire new sung phrases use the accepted first-act singing identity; no original Xu Xian words or vocal heads are mixed.",
        synthesis=dict(model="YingMusic-Singer-Plus",source_revision="baa409c2e7e5e775f09b4e92a220808f4827d2cc",
            weights_revision="7443a818cb43c5ece9976a78ec8b625660bc522d",parameters=request["parameters"],
            complete_utterances=True,word_onset_original_voice_blend=False),
        human_listening_verified=False)
    score["splice_ms"]=round(score["splice_frame"]/48)
    (args.output/"score.json").write_text(json.dumps(score,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    sf.write(args.work/"opening-preview.wav",track[:score["splice_frame"]+round(7*RATE)],RATE,subtype="PCM_16")
    print(json.dumps(dict(duration_ms=score["duration_ms"],lines=len(lines),common_gain=common_gain,
        fahai_original_lines=sum(row["role_id"] == "fahai" and row["delivery"] == "original" for row in lines))))


if __name__=="__main__":
    main()

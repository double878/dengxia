"""Build Act 2 opening from the user's two original recordings, without synthesis."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    pcm, sources = [], []
    cursor = 0
    for index, video in enumerate([args.first, args.second], 1):
        decoded = args.work / f"source-{index}.wav"
        subprocess.run([
            str(args.ffmpeg), "-nostdin", "-v", "error", "-xerror", "-y",
            "-i", str(video), "-map", "0:a:0", "-vn", "-ar", "48000",
            "-ac", "2", "-c:a", "pcm_s16le", str(decoded)
        ], check=True, timeout=60)
        with wave.open(str(decoded), "rb") as source:
            assert (source.getframerate(), source.getnchannels(), source.getsampwidth()) == (48000, 2, 2)
            frames = source.getnframes()
            data = source.readframes(frames)
        assert frames > 0 and len(data) == frames * 4
        sources.append(dict(
            source_id=f"video-{index}", file_name=video.name,
            video_sha256=digest(video.read_bytes()), decoded_pcm_sha256=digest(data),
            source_start_frame=0, source_end_frame=frames,
            main_start_frame=cursor, main_end_frame=cursor + frames,
            processing="Full decoded original PCM; no trim, gain, crossfade, voice conversion or time stretching."
        ))
        pcm.append(data)
        cursor += frames

    # Times follow the visible subtitles in each supplied recording.
    # A subtitle can precede its voice in the source; it is not an ASR claim.
    captions = [
        (0, .9, 4.7, "xuxian", "原来是位老师父，请了。"),
        (0, 4.7, 10.9, "fahai", "请了，足下莫非就是许官人么？"),
        (0, 10.9, 15.1, "xuxian", "正是卑人，请问师父上下？"),
        (0, 15.1, 19.2, "fahai", "老僧法海。"),
        (0, 19.2, None, "xuxian", "哦，原来是法海老禅师。"),
        (1, .8, 3.4, "fahai", "老僧查明，"),
        (1, 3.4, 11.5, "fahai", "你那妻子乃是千年蛇妖所化。"),
        (1, 21.1, 24.4, "xuxian", "哎，师父！"),
        (1, 24.4, 29.1, "xuxian", "我那娘子乃是贤德之人，"),
        (1, 29.1, 31.4, "xuxian", "怎说是蛇妖所化？"),
        (1, 31.4, 35.2, "xuxian", "师父讲话太无理了！"),
        (1, 35.2, 39.0, "fahai", "看你入迷已深，"),
        (1, 39.0, 41.2, "fahai", "待等端阳佳节，"),
        (1, 41.2, 47.0, "fahai", "与她多饮几杯雄黄酒，"),
        (1, 49.0, 55.0, "fahai", "方知我言不谬矣。"),
        (1, 55.0, 59.0, "fahai", "告辞了。"),
    ]
    lines = []
    for index, (part, begin, end, role, text) in enumerate(captions, 1):
        src = sources[part]
        first = src["main_start_frame"] + round(begin * 48000)
        last = src["main_end_frame"] if end is None else src["main_start_frame"] + round(end * 48000)
        assert src["main_start_frame"] <= first < last <= src["main_end_frame"]
        lines.append(dict(
            line_id=f"act2_original_{index:02d}", role_id=role,
            role_name="法海" if role == "fahai" else "许仙", text=text,
            delivery="original", source_id=src["source_id"],
            start_frame=first, end_frame=last,
            start_ms=round(first / 48), end_ms=round(last / 48)
        ))
    original = b"".join(pcm)
    # Keep all source tails before the established two-second scene fade.
    data = original + bytes(2 * 48000 * 4)
    main_path = args.output / "main.wav"
    with wave.open(str(main_path), "wb") as output:
        output.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        output.writeframes(data)
    score = dict(
        audio_version="act2-opening-original-" + digest(data)[:12],
        stage_id=2, scene_id="fahai_advice",
        main_path="res://assets/audio/act2-opening/main.wav",
        duration_ms=round(len(data) / 4 / 48),
        dark_start_ms=round(cursor / 48), greeting_gate_ms=0,
        splice_frame=sources[1]["main_start_frame"],
        splice_ms=round(sources[1]["main_start_frame"] / 48),
        lines=lines, sources=sources,
        assets=[dict(asset_id="main", path="res://assets/audio/act2-opening/main.wav",
                     frames=len(data) // 4, sha256=digest(main_path.read_bytes()),
                     pcm_sha256=digest(data))],
        subtitle_basis="Visible source subtitles, manually checked against extracted video frames; not ASR-certified speech alignment.",
        listening_scope="Original user recordings; technical and Windows playback checks recorded separately. No human listening certification."
    )
    (args.output / "score.json").write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(frames=len(data) // 4, original_frames=cursor,
                          splice_frame=score["splice_frame"], duration_ms=score["duration_ms"])))


if __name__ == "__main__":
    main()

"""Build Act 2 opening from the user's two original recordings, without synthesis."""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import wave


def digest(data):
    return hashlib.sha256(data).hexdigest()


def apply_edits(parts, sources, recipe_path):
    recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    assert [row["video_sha256"] for row in sources] == recipe["video_sha256"]
    edits = []
    previous = {}
    for item in recipe["voice_edits"]:
        index = int(item["part"])
        begin, end = int(item["start_frame"]), int(item["end_frame"])
        assert 0 <= index < len(parts) and previous.get(index, 0) <= begin < end <= len(parts[index]) // 4
        assert item["role_id"] == "xuxian"
        path = Path(item["replacement_path"])
        assert digest(path.read_bytes()) == item["replacement_sha256"]
        with wave.open(str(path), "rb") as stream:
            assert stream.getparams()[:3] == (2, 2, 48000)
            replacement = stream.readframes(stream.getnframes())
        assert len(replacement) == (end - begin) * 4
        parts[index] = parts[index][:begin * 4] + replacement + parts[index][end * 4:]
        previous[index] = end
        edits.append({key: value for key, value in item.items() if key not in ["replacement_path", "composition"]})
    overlap = int(recipe["splice_overlap_frames"])
    assert 0 < overlap <= 4800 and overlap < min(len(part) // 4 for part in parts)
    left, right = array("h"), array("h")
    left.frombytes(parts[0][-overlap * 4:])
    right.frombytes(parts[1][:overlap * 4])
    blended = array("h")
    for frame in range(overlap):
        amount = (1 - math.cos(math.pi * frame / (overlap - 1))) / 2
        for channel in range(2):
            value = round(left[frame * 2 + channel] * (1 - amount) + right[frame * 2 + channel] * amount)
            assert -32768 < value < 32767
            blended.append(value)
    splice = len(parts[0]) // 4 - overlap
    sources[1]["main_start_frame"] = splice
    sources[1]["main_end_frame"] = splice + len(parts[1]) // 4
    for row in sources:
        row["processing"] = "Original decoded PCM outside declared Xu Xian edits and 40 ms source overlap."
    original = parts[0][:-overlap * 4] + blended.tobytes() + parts[1][overlap * 4:]
    captions = [(int(row["part"]), row["start_s"], row["end_s"], row["role_id"], row["text"]) for row in recipe["captions"]]
    return original, captions, dict(voice_edits=edits, voice_conversion=recipe["voice_conversion"],
        splice_overlap_frames=overlap, entrance_music_enabled=False,
        production_recipe_sha256=digest(recipe_path.read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--edit-manifest", type=Path)
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
    metadata = {}
    if args.edit_manifest:
        original, captions, metadata = apply_edits(pcm, sources, args.edit_manifest)
        cursor = len(original) // 4
    else:
        original = b"".join(pcm)
    lines = []
    for index, (part, begin, end, role, text) in enumerate(captions, 1):
        src = sources[part]
        first = src["main_start_frame"] + round(begin * 48000)
        last = src["main_end_frame"] if end is None else src["main_start_frame"] + round(end * 48000)
        assert src["main_start_frame"] <= first < last <= src["main_end_frame"]
        lines.append(dict(
            line_id=f"act2_original_{index:02d}", role_id=role,
            role_name="法海" if role == "fahai" else "许仙", text=text,
            delivery="voice_converted" if args.edit_manifest and role == "xuxian" else "original", source_id=src["source_id"],
            start_frame=first, end_frame=last,
            start_ms=round(first / 48), end_ms=round(last / 48)
        ))
    # Keep all source tails before the established two-second scene fade.
    data = original + bytes(2 * 48000 * 4)
    main_path = args.output / "main.wav"
    with wave.open(str(main_path), "wb") as output:
        output.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        output.writeframes(data)
    score = dict(
        audio_version=("act2-opening-act1-xuxian-" if args.edit_manifest else "act2-opening-original-") + digest(data)[:12],
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
    score.update(metadata)
    (args.output / "score.json").write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(frames=len(data) // 4, original_frames=cursor,
                          splice_frame=score["splice_frame"], duration_ms=score["duration_ms"])))


if __name__ == "__main__":
    main()

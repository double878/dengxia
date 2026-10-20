"""Keep the complete crane line, then append the user's separated elder voice."""
import argparse
import hashlib
import json
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/act3-mountain"
GAP_FRAMES = 14400
ARRIVAL_START = 48000  # Quiet gap 0.9-1.2s, before the elder voice around 1.3s.
BLESSING_VOICE_FRAMES = 21800 * 48


def pcm(name):
    with wave.open(str(DEST / name), "rb") as stream:
        if (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) != (48000, 2, 2):
            raise ValueError("Expected 48k stereo PCM16: " + name)
        return stream.readframes(stream.getnframes())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("arrival", type=Path)
    parser.add_argument("blessing", type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--voice-dir", type=Path, required=True)
    args = parser.parse_args()
    provenance = json.loads((args.voice_dir / "separation.json").read_text(encoding="utf-8"))
    previous = json.loads((DEST / "finale-source.json").read_text(encoding="utf-8"))
    clips = []
    for source, stem in [(args.arrival, "arrival"), (args.blessing, "blessing")]:
        name = "finale-" + stem + "-original.wav"
        if source.is_file():
            subprocess.run([str(args.ffmpeg), "-nostdin", "-y", "-v", "error", "-i", str(source),
                "-map", "0:a:0", "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", str(DEST / name)], check=True)
        data = pcm(name)
        original = next(row for row in previous["clips"] if row["filename"] == source.name)
        if digest(data) != original["pcm_sha256"]:
            raise ValueError("Cached original PCM changed: " + name)
        if digest((DEST / name).read_bytes()) != provenance["inputs"]["sources"][name]:
            raise ValueError("Voice separation used a different original: " + name)
        row = next(r for r in provenance["outputs"] if r["file"] == name.replace("original", "vocals"))
        float_path = args.voice_dir / row["file"]
        if digest(float_path.read_bytes()) != row["sha256"]:
            raise ValueError("Unverified separated voice: " + str(float_path))
        voice_name = name.replace("original", "voice")
        subprocess.run([str(args.ffmpeg), "-nostdin", "-y", "-v", "error", "-i", str(float_path),
            "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", str(DEST / voice_name)], check=True)
        if len(pcm(voice_name)) != len(data):
            raise ValueError("Voice conversion changed duration")
        clips.append(dict(filename=source.name, sha256=digest(source.read_bytes()) if source.is_file() else original["sha256"], wav=name,
            decoded_frames=len(data) // 4, pcm_sha256=digest(data), voice_wav=voice_name,
            voice_pcm_sha256=digest(pcm(voice_name)), source_video_verified_now=source.is_file()))

    fight_source = json.loads((DEST / "fight-source.json").read_text(encoding="utf-8"))
    opening, fight = pcm("original.wav"), pcm("fight-original.wav")
    if digest(fight) != fight_source["pcm_sha256"]:
        raise ValueError("Saved original fight recording changed")
    cut = int(fight_source["splice_ms"]) * 48
    prefix = opening[:cut * 4] + fight[int(fight_source["incoming_trim_frames"]) * 4:]
    if digest(prefix) != fight_source["performance_pcm_sha256"]:
        raise ValueError("Full opening/fight prefix changed")
    chunks, segments = [prefix], []
    cursor = len(prefix) // 4

    def append(name, start, count, kind):
        nonlocal cursor
        data = bytes(count * 4) if kind == "silence" else pcm(name)[start * 4:(start + count) * 4]
        if len(data) != count * 4:
            raise ValueError("Invalid source selection: " + name)
        segments.append(dict(wav=name, kind=kind, source_start_frame=start, start_frame=cursor,
            selected_frames=count, pcm_sha256=digest(data)))
        chunks.append(data)
        cursor += count

    append("", 0, GAP_FRAMES, "silence")
    arrival_frame = cursor
    append(clips[0]["voice_wav"], ARRIVAL_START, clips[0]["decoded_frames"] - ARRIVAL_START, "voice")
    second_frame = cursor
    blessing_trim = 448
    append(clips[1]["voice_wav"], blessing_trim, BLESSING_VOICE_FRAMES, "voice")
    tail_start = blessing_trim + BLESSING_VOICE_FRAMES
    append(clips[1]["wav"], tail_start, clips[1]["decoded_frames"] - tail_start, "original")
    combined = b"".join(chunks)
    with wave.open(str(DEST / "performance.wav"), "wb") as stream:
        stream.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        stream.writeframes(combined)
    crane_start, crane_end = 136560, round(len(prefix) / 4 / 48)
    arrival_ms, second_ms, duration = [round(n / 48) for n in [arrival_frame, second_frame, cursor]]
    score = json.loads((DEST / "score.json").read_text(encoding="utf-8"))
    score["lines"] = [line for line in score["lines"] if line["start_ms"] < crane_start]
    score["lines"][-1]["end_ms"] = crane_start
    score["lines"] += [
        dict(start_ms=crane_start, end_ms=crane_end, role_name="鹤童", text="休走！是你看剑！"),
        dict(start_ms=arrival_ms, end_ms=second_ms, role_name="仙翁", text="徒儿住手！"),
        dict(start_ms=second_ms, end_ms=second_ms + 12500, role_name="仙翁", text="白蛇，你夫许仙危在旦夕。"),
        dict(start_ms=second_ms + 12500, end_ms=second_ms + 21800, role_name="仙翁", text="速到镇江救夫去吧。"),
        dict(start_ms=second_ms + 21800, end_ms=duration, role_name="白素贞", text="多谢仙翁，我就此去也！"),
    ]
    score.update(duration_ms=duration, audio_duration_ms=duration, complete=True,
        audio_version="finale-voice-" + digest(combined)[:12],
        finale=dict(start_ms=arrival_ms, stop_ms=arrival_ms + 300,
            gather_ms=arrival_ms + 2100, gift_ms=second_ms,
            advice_ms=second_ms + 12500, farewell_ms=second_ms + 21800, end_ms=duration))
    manifest = dict(clips=clips, preserved_prefix_frames=len(prefix) // 4,
        preserved_prefix_pcm_sha256=digest(prefix), performance_frames=cursor,
        performance_pcm_sha256=digest(combined), segments=segments, voice_extraction=provenance,
        crane_end_ms=crane_end, response_gap_frames=GAP_FRAMES,
        arrival_source_start_frame=ARRIVAL_START,
        join_basis="Keep the complete previous fight recording including the crane final line and tail. Insert 300ms silence. Start the incoming elder voice inside its 0.9-1.2s quiet interval, before vocal activity around 1.3s; omit the repeated opening crane tail.",
        timing_basis="Vocal RMS and video observations; mixed-opera ASR was unreliable and was not used to cut words. Not a human listening assessment.",
        processing="MelBandRoformer extraction of original elder voice, resampled to 48k stereo PCM16. No synthesis, voice conversion or time stretching. Preserve all earlier audio and the final Bai source tail verbatim. No backing track is mixed into elder selections.")
    (DEST / "score.json").write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (DEST / "finale-source.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(duration_ms=duration, finale=score["finale"], crane_end_ms=crane_end, frames=cursor), ensure_ascii=False))


if __name__ == "__main__":
    main()

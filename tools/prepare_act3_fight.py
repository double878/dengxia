"""Join original recordings, removing only the incoming recording's digital silence."""
import argparse
import hashlib
import json
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/act3-mountain"
SPLICE_MS = 99625


def read_pcm(path):
    with wave.open(str(path), "rb") as stream:
        if (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) != (48000, 2, 2):
            raise ValueError(f"Expected PCM16 48k stereo: {path}")
        return stream.readframes(stream.getnframes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, nargs="?")
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()
    if args.source is not None:
        if args.ffmpeg is None:
            parser.error("--ffmpeg is required to decode a new source")
        subprocess.run([
            str(args.ffmpeg), "-nostdin", "-y", "-v", "error", "-i", str(args.source),
            "-map", "0:a:0", "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2",
            str(DEST / "fight-original.wav"),
        ], check=True)
    old = read_pcm(DEST / "original.wav")
    new = read_pcm(DEST / "fight-original.wav")
    if not new:
        raise ValueError("The supplied video contains no decoded samples")
    pcm_hash = hashlib.sha256(new).hexdigest()
    if args.source is None:
        source = json.loads((DEST / "fight-source.json").read_text(encoding="utf-8"))
        if source["pcm_sha256"] != pcm_hash:
            raise ValueError("Saved original PCM does not match its source manifest")
    else:
        source = dict(filename=args.source.name,
                      sha256=hashlib.sha256(args.source.read_bytes()).hexdigest())
    trim_bytes = next((i for i in range(0, len(new), 4) if new[i:i + 4] != bytes(4)), len(new))
    if trim_bytes >= len(new) or trim_bytes > 48000 * 4:
        raise ValueError("Incoming recording has no sound within the first second; inspect the source")
    trim_frames = trim_bytes // 4
    trim_ms = trim_frames / 48
    combined = old[:SPLICE_MS * 48 * 4] + new[trim_bytes:]
    with wave.open(str(DEST / "performance.wav"), "wb") as stream:
        stream.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        stream.writeframes(combined)
    duration = round(len(combined) / 4 / 48)
    manifest = {
        "filename": source["filename"],
        "sha256": source["sha256"],
        "decoded_audio_frames": len(new) // 4,
        "pcm_sha256": pcm_hash,
        "splice_ms": SPLICE_MS,
        "incoming_trim_frames": trim_frames,
        "incoming_trim_ms": trim_ms,
        "splice_basis": "Keep the opening cut before 说罢分心刺 and remove only the incoming screen recording's exact-zero prefix. All non-silent PCM is retained. Subtitle annotations remain approximately 0.25s precision, not ASR-aligned.",
        "processing": "AAC decode to PCM16 48k stereo; concatenate after removing leading all-zero frames only; no gain, normalization, synthesis, fades, denoise, time stretching or voice conversion",
        "performance_frames": len(combined) // 4,
        "performance_pcm_sha256": hashlib.sha256(combined).hexdigest(),
    }
    (DEST / "fight-source.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    score = json.loads((DEST / "score.json").read_text(encoding="utf-8"))
    # This tool is repeatable: the original opening annotations precede the splice.
    score["lines"] = [line for line in score["lines"] if line["start_ms"] < 99500]
    score["lines"][-1]["end_ms"] = SPLICE_MS
    for start, end, role, text in [
        (0, 2250, "鹿童", "说罢分心刺。"),
        (2250, 3500, "白素贞", "急忙用剑迎。"),
        (3500, 14000, "唱词", "拼命山前大战。"),
        (14000, 16750, "鹿童", "呀！不好，一剑刺中身形。"),
        (16750, 20000, "鹿童", "不敢恋战往下败。"),
        (20000, 25000, "唱词", "白鹤一见不容情。"),
        (25000, 33750, "唱词", "不容分说交了手。"),
        (33750, 37500, "白素贞", "哎呀不好，一跤跌倒地流平。"),
        (37500, round(len(new) / 4 / 48), "鹤童", "休走！是你看剑！"),
    ]:
        score["lines"].append(dict(start_ms=max(SPLICE_MS, round(SPLICE_MS + start - trim_ms)),
                                   end_ms=round(SPLICE_MS + end - trim_ms), role_name=role, text=text))
    score.update(
        main_path="res://assets/audio/act3-mountain/performance.wav",
        audio_version="continuous-" + manifest["performance_pcm_sha256"][:12],
        audio_duration_ms=duration, duration_ms=duration, complete=False,
        timing_basis="Opening jump at final accent onset 27.56s. Incoming recording's exact-zero prefix removed; fight subtitles and choreography shifted together. Video annotations approximately 0.25s precision; no forced fall.",
        fight=dict(start_ms=SPLICE_MS, draw_ms=round(SPLICE_MS + 2250 - trim_ms),
                   defeat_ms=round(SPLICE_MS + 14500 - trim_ms), retreat_ms=round(SPLICE_MS + 16750 - trim_ms),
                   crane_ms=round(SPLICE_MS + 20000 - trim_ms), duel_ms=round(SPLICE_MS + 25000 - trim_ms)),
    )
    (DEST / "score.json").write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for filename in ["fight-original.wav.import", "performance.wav.import"]:
        settings = DEST / filename
        if settings.exists():
            settings.write_text(settings.read_text(encoding="utf-8").replace("compress/mode=2", "compress/mode=0"), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()

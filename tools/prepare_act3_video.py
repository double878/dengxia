"""Extract supplied original audio; never manufacture sound for an empty track."""
import argparse
import hashlib
import json
import struct
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/act3-mountain"


def boxes(data, begin=0, end=None):
    end = len(data) if end is None else end
    while begin + 8 <= end:
        size, kind = struct.unpack_from(">I4s", data, begin)
        header = 8
        if size == 1:
            size = struct.unpack_from(">Q", data, begin + 8)[0]
            header = 16
        elif size == 0:
            size = end - begin
        if size < header or begin + size > end:
            raise ValueError("Malformed MP4 box")
        yield kind.decode("ascii"), begin + header, begin + size
        begin += size


def audio_table(data):
    result = []
    for kind, start, end in boxes(data):
        if kind != "moov":
            continue
        for child, a, b in boxes(data, start, end):
            if child != "trak":
                continue
            values = {}
            def visit(lo, hi):
                for name, left, right in boxes(data, lo, hi):
                    if name == "hdlr":
                        values["handler"] = data[left + 8:left + 12].decode("ascii")
                    if name == "stsz":
                        values["sample_count"] = struct.unpack_from(">I", data, left + 8)[0]
                    if name in {"mdia", "minf", "stbl"}:
                        visit(left, right)
            visit(a, b)
            if values.get("handler") == "soun":
                result.append(values)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--duration-ms", type=int, default=107200)
    args = parser.parse_args()
    blob = args.source.read_bytes()
    DEST.mkdir(parents=True, exist_ok=True)
    temp = DEST / "original.pending.wav"
    process = subprocess.run([
        str(args.ffmpeg.resolve()), "-nostdin", "-y", "-v", "warning", "-i", str(args.source),
        "-map", "0:a:0", "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", str(temp)
    ], capture_output=True, text=True, encoding="utf-8", errors="replace")
    frames = 0
    if temp.exists() and process.returncode == 0:
        with wave.open(str(temp), "rb") as audio:
            frames = audio.getnframes()
            assert audio.getnchannels() == 2 and audio.getsampwidth() == 2 and audio.getframerate() == 48000
    available = frames > 0
    pcm_hash = ""
    if available:
        with wave.open(str(temp), "rb") as audio:
            pcm_hash = hashlib.sha256(audio.readframes(frames)).hexdigest()
        temp.replace(DEST / "original.wav")
    elif temp.exists():
        temp.unlink()
    source = {
        "filename": args.source.name, "sha256": hashlib.sha256(blob).hexdigest(),
        "video_duration_ms": args.duration_ms, "decoded_audio_frames": frames,
        "audio_sample_tables": audio_table(blob) if args.source.suffix.lower() == ".mp4" else [],
        "decode_returncode": process.returncode, "decode_message": process.stderr.strip(),
        "processing": "FFmpeg AAC decode to PCM16, 48k stereo; no gain, synthesis, denoise or voice conversion",
        "audio_available": available, "pcm_sha256": pcm_hash,
    }
    (DEST / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Supplying new audio updates the existing choreography; no subtitle or gate guessing here.
    score_path = DEST / "score.json"
    if score_path.exists():
        score = json.loads(score_path.read_text(encoding="utf-8"))
        score.update(audio_available=available, audio_version="source-" + source["sha256"][:12],
                     main_path="res://assets/audio/act3-mountain/original.wav" if available else "",
                     audio_duration_ms=round(frames / 48), source_sha256=source["sha256"])
        score_path.write_text(json.dumps(score, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(source, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

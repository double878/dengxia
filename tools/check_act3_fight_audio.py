"""Verify that the performance contains exact source PCM, without hidden gain."""
import hashlib
import json
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "assets/audio/act3-mountain"


def pcm(name):
    with wave.open(str(ROOT / name), "rb") as stream:
        assert (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) == (48000, 2, 2)
        return stream.readframes(stream.getnframes())


source = json.loads((ROOT / "fight-source.json").read_text(encoding="utf-8"))
score = json.loads((ROOT / "score.json").read_text(encoding="utf-8"))
old, new, combined = [pcm(name) for name in ["original.wav", "fight-original.wav", "performance.wav"]]
cut = source["splice_ms"] * 48 * 4
trim = int(source.get("incoming_trim_frames", 0)) * 4
assert trim > 0 and new[:trim] == bytes(trim), "Only the recording's leading digital silence may be removed"
assert new[trim:trim + 4] != bytes(4), "The join must not retain the recording's silent prefix"
assert combined[:cut] == old[:cut], "Opening samples were altered"
old_performance = old[:cut] + new[trim:]
if score.get("finale"):
    finale = json.loads((ROOT / "finale-source.json").read_text(encoding="utf-8"))
    retained = finale["preserved_prefix_frames"] * 4
    assert combined[:retained] == old_performance[:retained], "Retained opening/fight samples were altered"
else:
    assert combined[cut:] == new[trim:], "Non-silent fight samples were altered or truncated"
assert hashlib.sha256(new).hexdigest() == source["pcm_sha256"]
assert hashlib.sha256(old_performance).hexdigest() == source["performance_pcm_sha256"]
assert abs(len(combined) / 4 / 48 - score["duration_ms"]) < 1
for name in ["performance.wav.import", "fight-original.wav.import"]:
    settings = (ROOT / name).read_text(encoding="utf-8")
    assert "edit/normalize=false" in settings and "compress/mode=0" in settings
    assert "edit/trim=false" in settings and "edit/loop_mode=0" in settings
print(json.dumps(dict(passed=True, performance_frames=len(combined) // 4, duration_ms=score["duration_ms"], splice_ms=source["splice_ms"])))

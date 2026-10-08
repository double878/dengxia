extends RefCounted
class_name StageLight
## 只读状态与显式双时钟；暂停可重现，补救时自然火光仍继续。

static func unit(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


static func sample(lamp: LampState, real_ms: int, song_ms: int, bpm: float = 96.0) -> Dictionary:
	var oil: float = unit(lamp.oil) if lamp != null else 1.0
	var feedback: float = unit(lamp.flame_feedback) if lamp != null else 0.5
	var time: float = maxf(float(real_ms), 0.0) * 0.001
	var wave: float = (sin(time * 3.7 + 0.8) * 0.52 + sin(time * 8.3 + 2.1) * 0.30
		+ sin(time * 17.1 + 0.4) * 0.18)
	var beat_phase: float = fposmod(float(song_ms) * 0.001 * maxf(bpm, 1.0) / 60.0, 1.0)
	var pulse: float = exp(-beat_phase * 16.0)
	var shake: float = lerpf(4.8, 0.7, feedback)
	return {
		"visual_seconds": time,
		"shake_amplitude": shake,
		"tip_x": wave * shake,
		"cloth_flicker": 1.0 + wave * lerpf(0.035, 0.010, feedback),
		"glow_flicker": 1.0 + wave * lerpf(0.10, 0.04, feedback),
		"flame_height": 33.0 + 9.0 * oil + 3.2 * wave + 1.4 * pulse,
		"flame_width": 10.0 + 2.4 * oil - 0.7 * wave,
		"environment": 0.58 + 0.42 * oil,
	}

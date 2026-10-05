extends RefCounted
class_name TestLevel1Audio

const ATestBaseScript := preload("res://tests/a/a_test_base.gd")
const MetronomeScript := preload("res://scripts/a_test/metronome.gd")


func run_all() -> Dictionary:
	var t: ATestBase = ATestBaseScript.new()
	t.begin("第一关临时音轨持续有声且有节奏变化")
	var music: Metronome = MetronomeScript.new()
	t.check(music.has_method("sample_at"), "临时音轨应能生成连续的采样")
	if music.has_method("sample_at"):
		var energies: Array[float] = []
		for second in [0.2, 1.2, 4.2, 12.2, 28.2]:
			var energy: float = 0.0
			for i in 300:
				var sample: float = music.call("sample_at", second + float(i) / 44100.0)
				energy += sample * sample
			energies.append(energy / 300.0)
		for energy in energies:
			t.check(energy > 0.001, "每个时间段都应输出可听量级的信号")
		t.check(absf(energies[0] - energies[1]) > 0.0001,
			"节拍位置不同，音轨能量应变化")
	t.finish("第一关有持续的临时音乐信号")
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed,
		"failures": t.failures}

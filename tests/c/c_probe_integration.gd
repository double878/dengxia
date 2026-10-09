extends SceneTree
## 切片 3 集成探针：用**真实 A 端 Level1Runtime** 跑完整第一关时间线，
## 验证 CStageRecorder 接线层在真实数据源上是否正确工作。
##
## 与单元测试的分工：单元测试用假 runtime 穷举边界，本探针用真 runtime
## 证明「A 端真数据 → C 侧记录」这条链真的通。两类证据互不替代。
##
## 运行：
##   godot.exe --headless --path . --script res://tests/c/c_probe_integration.gd
## 退出码 0 表示全通过，1 表示有失败。
##
## 音频说明：无头模式用虚拟音频驱动，时钟用自由计时（不挂 AudioStreamPlayer），
## 与 A 端 tests/a 的跑法一致。真实音频时钟的表现需在图形环境另行验证。
##
## 本探针是验证脚本，不是常驻回归测试：它跑满 35 秒时间线，
## 单元测试套件仍是每次提交都跑的门禁。

const Level1RuntimeScript := preload("res://scripts/a/level1_runtime.gd")
const MusicClockScript := preload("res://scripts/a/music_clock.gd")
const StageDefScript := preload("res://scripts/a/stage_def.gd")
const CStageRecorderScript := preload("res://scripts/c/c_stage_recorder.gd")

## 与 A 端 level1_harness 相同的固定步长，保证 35 秒 = 2100 步。
const FIXED_DELTA: float = 1.0 / 60.0
## 无头下不挂音频播放器，用自由计时跑满时间线。
const RUN_STEPS: int = 2100

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	print("")
	print("======== 切片 3 集成探针：真实 Level1Runtime → CStageRecorder ========")

	var stage_def: Variant = StageDefScript.make_level1()
	var duration_ms: int = int(stage_def.duration_ms)

	# 自由计时时钟：无头模式没有真实音频播放，set_player(null) 让
	# MusicClock 走 update(delta) 自由计时，与 A 端探针同一跑法。
	var clock: Variant = MusicClockScript.new()
	clock.set_player(null, stage_def.bpm)
	clock.start()

	var runtime: Variant = Level1RuntimeScript.new()
	_expect(runtime.setup(clock), "Level1Runtime 建立成功")
	if runtime == null:
		_finish()
		return
	runtime.start()

	# 接线层接管：从这一行起，C 侧开始录制。
	var recorder: Variant = CStageRecorderScript.new()
	recorder.begin(0, duration_ms)
	_expect(recorder.is_begun(), "CStageRecorder 已 begin")

	# 推进整场演出。capture 由 CStageRecorder 内部按契约顺序完成。
	#
	# 不在 is_over() 为真时 break：CStageRecorder 是在**下一次** advance() 入口
	# 才发现结束并自动 finish 的，立刻 break 就测不到自动收尾这条路径。
	# 多推进几帧无妨——收尾后 advance() 直接返回 0，不会多写一条。
	var over_step: int = -1
	for step in RUN_STEPS:
		recorder.advance(runtime, FIXED_DELTA)
		if over_step < 0 and runtime.is_over():
			over_step = step

	_expect(over_step >= 0, "演出在 35 秒内正常结束（第 %d 步）" % over_step)
	_expect(recorder.is_finished(), "结束时已自动收尾")

	var record: Variant = recorder.get_record()
	_expect(record != null, "收尾后仍可取到记录（回放端需要）")
	if record == null:
		_finish()
		return

	# ---- 采样密度 ----
	# 35 秒 @ 30 Hz ≈ 1050 帧，是**下界**而非期望值。
	# 跳变补采样的优先级高于常规采样（TECH_DESIGN 第 4 节）：
	# A 端 lamp.oil 在演出中每帧递减、影人 stance 随操控变化，
	# 因此几乎每帧都触发跳变采样，60 Hz 输入下实测 2100 帧。
	# 这里验的是「不低于 30Hz 网格，且不超过帧数上限」——
	# 上界就是 ran_steps 本身，每帧至多一条，不存在重采样。
	var snapshots: int = record.snapshots.size()
	var expected: int = int(ceil(float(duration_ms) / 1000.0 * 30.0))
	_expect(snapshots >= expected, "快照数 %d 不低于 30Hz 理论值 %d" % [snapshots, expected])
	_expect(snapshots <= RUN_STEPS, "快照数 %d 不超过推进帧数 %d（每帧至多一条）"
		% [snapshots, RUN_STEPS])

	# ---- 时间轴覆盖 ----
	var last_snap: Variant = record.snapshots[snapshots - 1]
	_expect(int(last_snap.time_ms) <= duration_ms, "末帧时间未超出关卡时长")
	_expect(int(last_snap.time_ms) >= duration_ms - 200,
		"末帧覆盖到时长末端（实际 %d / %d）" % [int(last_snap.time_ms), duration_ms])

	# ---- 事件完整性 ----
	var events: int = record.events.size()
	_expect(events > 0, "记录到离散事件（%d 条）" % events)
	_expect(_count_kind(record, "stage_start") == 1, "恰好一条 stage_start")
	_expect(_count_kind(record, "stage_end") == 1, "恰好一条 stage_end")
	_expect(_count_kind(record, "cue_hint") > 0, "有关键动作提示事件")
	_expect(_count_kind(record, "lamp_oil_changed") > 0, "有油量变化事件")

	# ---- 契约不变量（PRD 5.2.3 忠实性）----
	var problems: Array = record.validate_invariants()
	_expect(problems.is_empty(), "不变量自检通过（%d 项问题）" % problems.size())
	for p in problems:
		print("    不变量问题：%s" % str(p))

	# ---- 单向数据流：录制不得改写 A 端状态 ----
	# 记录里 distance 越大表示灯越近，这里只验证取值合法，
	# 不做方向换算——换算是回放表现层的事（见 CRecorder 类注释）。
	var lamp_ok: bool = true
	for s in record.snapshots:
		for key in ["distance", "exposure", "oil", "flame_feedback"]:
			var v: float = float(s.lamp.get(key, -1.0))
			if v < 0.0 or v > 1.0:
				lamp_ok = false
				break
	_expect(lamp_ok, "灯态四字段全程落在 [0,1]")

	var puppet_ok: bool = true
	for s in record.snapshots:
		if (s.puppets as Array).size() != 3:
			puppet_ok = false
			break
	_expect(puppet_ok, "每帧都是三具影人")

	# ---- 准入闸门 ----
	_expect(recorder.is_ready_for_replay(), "不变量通过，回放准入闸门放行")

	var stats: Dictionary = recorder.get_stats()
	print("")
	print("  快照 %d 帧 / 事件 %d 条 / 帧数 %d"
		% [snapshots, events, int(stats.get("frame_count", 0))])
	print("  时钟倒退 %d 次 / 末帧 t=%dms"
		% [int(stats.get("backwards_clock_count", 0)), int(last_snap.time_ms)])

	# ---- 释放：记录不留存，符合「不做录像库」约定 ----
	recorder.discard()
	_expect(recorder.get_record() == null, "discard 后记录已释放")

	_finish()


func _count_kind(record: Variant, kind: String) -> int:
	var count: int = 0
	for e in record.events:
		if str(e.kind) == kind:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [通过] %s" % message)
	else:
		_failures += 1
		print("  [失败] %s" % message)


func _finish() -> void:
	print("")
	print("======== 探针结论：%d 项检查，%d 项失败 ========" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

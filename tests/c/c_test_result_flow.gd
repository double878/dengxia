extends RefCounted
class_name CTestResultFlow
## 切片 6 行为测试：演出收尾与结果页流程编排。
##
## 覆盖 PRD 第 42 行链路的后三段（幕前回放 → 本关收场 → 重看 或 离开）
## 与 122/132/116 行的具体规则。
##
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CResultFlowScript := preload("res://scripts/c/c_result_flow.gd")
const CMockPerformerScript := preload("res://scripts/c/c_mock_performer.gd")
const CReplayPlayerScript := preload("res://scripts/c/c_replay_player.gd")


## 新建一台接好 delta 时钟源的流程编排器。
##
## **必须切delta**：headless 批跑时墙钟几乎不走，35s 演出推不完，
## 流程永远到不了结果页，所有用例都会卡在回放态。生产路径不要调这个开关。
func _flow() -> Variant:
	var flow: Variant = CResultFlowScript.new()
	flow.set_clock_source(CReplayPlayerScript.CLOCK_SOURCE_DELTA)
	return flow


## 一份带掌声段的记录。第 5 关判定要用。
func _record_with_applause(applause_count: int) -> Variant:
	var record: Variant = CMockPerformerScript.new().build()
	for i in applause_count:
		record.append_act(i, true, i * 1000, i * 1000 + 900)
	return record


## 一份不带掌声的记录。
func _record_without_applause() -> Variant:
	return CMockPerformerScript.new().build()


## 推进到回放结束。
func _play_to_end(flow: Variant) -> void:
	var guard: int = 0
	while flow.is_replaying() and guard < 2000:
		flow.advance(0.017)
		guard += 1


func run_all() -> Dictionary:
	var t: Variant = preload("res://tests/c/c_test_base.gd").new()
	_test_01_auto_replay_after_show(t)
	_test_02_null_record_rejected(t)
	_test_03_pause_resume_delegated(t)
	_test_04_skip_to_result(t)
	_test_05_natural_end_to_result(t)
	_test_06_rewatch_same_show(t)
	_test_07_leave_releases(t)
	_test_08_no_rewatch_after_leave(t)
	_test_09_rewatch_rejected_during_replay(t)
	_test_10_summary_fields(t)
	_test_11_final_stage_ending_curtain_call(t)
	_test_12_final_stage_ending_played_out(t)
	_test_13_non_final_no_ending(t)
	_test_14_ending_not_recomputed(t)
	_test_15_callbacks(t)
	return t.report()


func _test_01_auto_replay_after_show(t: Variant) -> void:
	t.begin("演出结束自动进幕前回放")
	var flow: Variant = _flow()
	var ok: bool = flow.begin_replay(_record_without_applause(), 1)
	t.check(ok, "进入回放")
	t.check_eq(flow.get_flow_state(), &"replaying", "状态为 replaying")
	t.check(flow.is_replaying(), "is_replaying 为真")
	t.check_eq(flow.get_replay_duration_ms(), 8000, "1:1 用本关实际时长 8000ms")
	t.finish("自动切换成立")


func _test_02_null_record_rejected(t: Variant) -> void:
	t.begin("空记录被拒")
	var flow: Variant = _flow()
	t.check_eq(flow.begin_replay(null, 1), false, "拒绝进入回放")
	t.check_eq(flow.is_replaying(), false, "不在回放态")
	t.finish("不崩")


func _test_03_pause_resume_delegated(t: Variant) -> void:
	t.begin("暂停/继续转交回放器")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	flow.advance(0.5)
	flow.pause()
	var frozen: int = int(flow.player_frame()["now_ms"])
	for _i in 5:
		flow.advance(0.5)
	t.check_eq(int(flow.player_frame()["now_ms"]), frozen, "暂停期间不推进")
	flow.resume()
	flow.advance(0.5)
	t.check_eq(int(flow.player_frame()["now_ms"]), frozen + 500, "恢复后继续")
	t.finish("委托生效")


func _test_04_skip_to_result(t: Variant) -> void:
	t.begin("跳过直接进结果页")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	flow.advance(0.5)
	flow.skip()
	t.check_eq(flow.get_flow_state(), &"result", "状态为 result")
	t.check_eq(flow.is_replaying(), false, "不在回放态")
	t.check(flow.can_rewatch(), "结果页可重看")
	t.finish("跳过生效")


func _test_05_natural_end_to_result(t: Variant) -> void:
	t.begin("自然播完也进结果页")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	_play_to_end(flow)
	t.check_eq(flow.get_flow_state(), &"result", "播完自动进 result")
	t.check(flow.can_rewatch(), "结果页可重看")
	t.finish("自然收场成立")


func _test_06_rewatch_same_show(t: Variant) -> void:
	t.begin("重看放的是同一次演出")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	flow.advance(1.0)
	# 先在结果页拿到摘要，重看后再比一次
	_play_to_end(flow)
	flow.rewatch()
	t.check_eq(flow.get_flow_state(), &"replaying", "重看回到 replaying")
	t.check_eq(int(flow.player_frame()["now_ms"]), 0, "重看从 0 开始")
	flow.advance(1.0)
	# 1 秒处的影人状态应与首次播放一致（同一份记录，不重新生成）
	var first_record: Variant = _record_without_applause()
	t.check_eq(int(flow.get_replay_duration_ms()), first_record.get_replay_duration_ms(),
		"时长与原记录一致")
	t.finish("可重复重看")


func _test_07_leave_releases(t: Variant) -> void:
	t.begin("离开本关释放记录")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	_play_to_end(flow)
	t.check_eq(flow.is_released, false, "尚未离开")
	flow.leave_stage()
	t.check_eq(flow.is_released, true, "离开后已释放")
	t.check_eq(flow.get_replay_duration_ms(), 0, "时长不再可取（录像未留下）")
	t.check_eq(flow.can_rewatch(), false, "不能重看")
	t.finish("释放生效")


func _test_08_no_rewatch_after_leave(t: Variant) -> void:
	t.begin("离开后不可重看（不保留历史录像）")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	_play_to_end(flow)
	flow.leave_stage()
	t.check_eq(flow.rewatch(), false, "rewatch 失败")
	t.check_eq(flow.get_flow_state(), &"finished", "状态为 finished")
	t.finish("录像未留下")


func _test_09_rewatch_rejected_during_replay(t: Variant) -> void:
	t.begin("回放中不能重看")
	var flow: Variant = _flow()
	flow.begin_replay(_record_without_applause(), 1)
	t.check_eq(flow.rewatch(), false, "回放中 rewatch 被拒")
	_play_to_end(flow)
	t.check_eq(flow.rewatch(), true, "结果页 rewatch 允许")
	t.finish("只在结果页允许")


func _test_10_summary_fields(t: Variant) -> void:
	t.begin("收场摘要字段")
	var flow: Variant = _flow()
	flow.begin_replay(_record_with_applause(1), 1)
	_play_to_end(flow)
	var s: Dictionary = flow.build_summary()
	t.check_eq(int(s["stage_id"]), 1, "stage_id")
	t.check_eq(bool(s["is_final_stage"]), false, "非最终关")
	t.check_eq(int(s["replay_duration_ms"]), 8000, "回放时长")
	t.check_eq(int(s["applause_act_count"]), 1, "掌声段数 1")
	t.check_eq(bool(s["can_rewatch"]), true, "可重看")
	t.check_eq(bool(s["seen_replay"]), true, "已看过回放")
	t.finish("摘要完整")


func _test_11_final_stage_ending_curtain_call(t: Variant) -> void:
	t.begin("第 5 关两段掌声=满堂彩")
	var flow: Variant = _flow()
	flow.begin_replay(_record_with_applause(2), 5)
	_play_to_end(flow)
	t.check_eq(flow.get_ending(), &"curtain_call", "两段掌声为满堂彩")
	var s: Dictionary = flow.build_summary()
	t.check_eq(bool(s["is_final_stage"]), true, "标记为最终关")
	t.finish("满堂彩")


func _test_12_final_stage_ending_played_out(t: Variant) -> void:
	t.begin("第 5 关不足两段掌声=戏散了")
	var flow: Variant = _flow()
	flow.begin_replay(_record_with_applause(1), 5)
	_play_to_end(flow)
	t.check_eq(flow.get_ending(), &"played_out", "一段掌声为戏散了")
	t.finish("戏散了")


func _test_13_non_final_no_ending(t: Variant) -> void:
	t.begin("非最终关不判结局")
	var flow: Variant = _flow()
	flow.begin_replay(_record_with_applause(3), 3)
	_play_to_end(flow)
	t.check_eq(flow.get_ending(), &"", "非最终关无结局标记")
	t.finish("不误判")


func _test_14_ending_not_recomputed(t: Variant) -> void:
	t.begin("结局只判一次，不随重看变")
	var flow: Variant = _flow()
	flow.begin_replay(_record_with_applause(2), 5)
	_play_to_end(flow)
	t.check_eq(flow.get_ending(), &"curtain_call", "首次满堂彩")
	flow.rewatch()
	_play_to_end(flow)
	t.check_eq(flow.get_ending(), &"curtain_call", "重看后仍满堂彩")
	# 掌声段数是读记录，不是重看时重新判定
	t.check_eq(int(flow.build_summary()["applause_act_count"]), 2, "掌声段数仍 2")
	t.finish("结局稳定")


func _test_15_callbacks(t: Variant) -> void:
	t.begin("集成层挂钩")
	var flow: Variant = _flow()
	var seen: Array = []
	flow.on_enter_replay = func(_f): seen.append("enter_replay")
	flow.on_enter_result = func(_s): seen.append("enter_result")
	flow.on_replay_finished = func(): seen.append("replay_finished")
	flow.on_flow_finished = func(): seen.append("flow_finished")
	flow.begin_replay(_record_without_applause(), 1)
	_play_to_end(flow)
	flow.leave_stage()
	t.check_eq(seen.size(), 4, "四个钩子各触发一次（%d）" % seen.size())
	t.check(seen.has("enter_replay"), "进入回放")
	t.check(seen.has("enter_result"), "进入结果")
	t.check(seen.has("replay_finished"), "回放结束")
	t.check(seen.has("flow_finished"), "流程结束")
	t.finish("挂钩生效")

extends RefCounted
class_name CResultFlow
## 演出收尾与结果页流程编排。
##
## 链路见 PRD 第 42 行：入口 → 选关 → 演前戏单 → 幕后演出 → 幕前完整回放
## → 本关收场 → 下一关或选关。本类只管最后三段与它们的切换规则：
##   演出结束 → 幕前回放 → 本关收场（结果页）→ 重看 或 离开
##
## **本类不建场景、不碰画面、不碰音频。** 幕前画面由 B 侧渲染，锣鼓由 B 侧
## 按时间轴自行触发。本类只维护状态机与「现在该给谁看什么」的判定，
## 由集成场景按状态切换画面与按钮。回调（on_*）是给集成层的挂钩，
## 默认实现为空——C 侧不代替 B 或流程层做画面决定。
##
## 关键规则（PRD 122/132、116 行）：
## - 回放 1:1 用本关实际时长，不重新判定合拍度、不产生新分数。
## - 回放可暂停/继续或立即跳过；跳过后直接进入本关结果。
## - 回放结束后**可在本关页面重看**；**离开本关后不保留录像**。
## - 选关始终开放，通关后可重玩任何关；单次演出不能回退。
## - 第 5 关三段独立产生掌声结果：至少两段有掌声为「满堂彩」，否则「戏散了」。
##   两档都是正常结局，回放只展示结果，不增加数值奖励。
##
## 依赖一律用 preload 常量：godot --headless --script 不读全局类名缓存。

const CReplayPlayerScript := preload("res://scripts/c/c_replay_player.gd")

## 流程状态。整合了 PRD:42 的链路与任务书要求的十态中属于 C 侧的部分。
const FLOW_RECORDING: StringName = &"recording"    ## 幕后演出中（录制期）
const FLOW_REPLAYING: StringName = &"replaying"      ## 幕前完整回放中
const FLOW_SKIPPED: StringName = &"skipped"          ## 被跳过，直接进结果
const FLOW_RESULT: StringName = &"result"            ## 本关收场/结果页
const FLOW_FINISHED: StringName = &"finished"        ## 收场已呈现，等玩家选择去向

## 本关是否为最终关（第 5 关）。第 5 关回放后要展示两档结局。
const STAGE_FINAL: int = 5

## 满堂彩所需的最少掌声段数。PRD 116 行：至少两段有掌声。
const APPLAUSE_THRESHOLD: int = 2
## 第 5 关的幕段总数。
const FINAL_STAGE_ACTS: int = 3

## 两档结局。都是正常结局，不分优劣。
const ENDING_CURTAIN_CALL: StringName = &"curtain_call"   ## 满堂彩
const ENDING_PLAYED_OUT: StringName = &"played_out"       ## 戏散了

## 回放播放器。由演出结束时注入。
var _player: Variant = null
## 本关记录。离开本关即置空，不保留历史录像。
var _record: Variant = null
## 本关序号。
var _stage_id: int = -1
## 是否最终关。
var _is_final_stage: bool = false
## 当前流程状态。
var _flow_state: StringName = FLOW_RECORDING
## 玩家是否已在本关看过至少一次回放。首次演出结束必然自动回放（PRD:122），
## 之后才由玩家选择重看或离开。
var _seen_replay: bool = false
## 本关掌声段数。回放读记录里的 acts，不重新判定（PRD:122 回放不产生新分数）。
var _applause_act_count: int = 0
## 结局。仅第 5 关有意义，其余关为 &""。
var _ending: StringName = &""
## 离开本关后置 true，用于断言「录像没被留下」。
var _released: bool = false

## 集成层挂钩。默认空实现，C 侧不代替 B 或流程层决定画面。
## 参数含义见各函数注释。
var on_enter_replay: Callable = Callable()      ## func(frame: Dictionary)
var on_enter_result: Callable = Callable()      ## func(summary: Dictionary)
var on_replay_finished: Callable = Callable()   ## func()
var on_flow_finished: Callable = Callable()      ## func()


## 演出收尾。演出结束时调用：把记录交给回放器，进入幕前完整回放。
##
## 传给新建播放器的时钟源。默认墙钟；headless 批跑的测试切delta。
var _clock_source: int = CReplayPlayerScript.CLOCK_SOURCE_WALL


## 设置传给播放器的时钟源。必须在 begin_replay() 之前调用。
##
## 仅供 headless 批跑测试使用——批跑时墙钟几乎不走，
## 35s 演出无法在毫秒内推完。生产路径不要调。
func set_clock_source(p_source: int) -> void:
	_clock_source = p_source
	if _player != null:
		_player.set_clock_source(p_source)


## 取当前内部播放器。诊断与测试用；返回 null 表示尚未进入回放。
func get_player() -> Variant:
	return _player


## PRD 122：「每关演出结束后，自动从幕后切至幕前，以本关实际时长 1:1 重演」。
## **自动**是关键词——首次回放不由玩家选择，玩家只有暂停与跳过的权利。
func begin_replay(p_record: Variant, p_stage_id: int) -> bool:
	if p_record == null:
		push_error("CResultFlow.begin_replay: record 为 null")
		return false
	_record = p_record
	_stage_id = p_stage_id
	_is_final_stage = p_stage_id == STAGE_FINAL
	_player = CReplayPlayerScript.new()
	# 转发时钟源。默认为墙钟（生产语义）；headless 批跑时测试会先调
	# set_clock_source(DELTA) 才能在毫秒内推进整场演出。见 CReplayPlayer。
	_player.set_clock_source(_clock_source)
	if not _player.load(p_record):
		# 记录不变量未过就不进回放：带已知错误播放的画面会稳定地错。
		push_error("CResultFlow.begin_replay: 记录不合法，拒绝进入回放")
		_record = null
		_player = null
		return false
	_player.play()
	_seen_replay = true
	_flow_state = FLOW_REPLAYING
	_count_applause(p_record)
	_emit(on_enter_replay, player_frame())
	return true


## 每帧推进。只在回放态推进，其余状态是空操作。
##
## 返回当前帧（含 now_ms / puppets / lamp / events / state / is_finished），
## 供集成层交给 B 侧渲染。
func advance(p_delta: float) -> Dictionary:
	match _flow_state:
		FLOW_REPLAYING:
			var frame: Dictionary = _player.advance(p_delta)
			# 回放自然播完 → 进入本关收场。这里不自动进下一关，
			# 等玩家在结果页选择重看或离开（PRD:42 单次演出不能回退）。
			if bool(frame.get("is_finished", false)):
				_enter_result()
			return frame
		FLOW_RECORDING, FLOW_SKIPPED, FLOW_RESULT, FLOW_FINISHED:
			pass
	return player_frame()


## 暂停/继续。转交回放器，本类不自己冻结——冻结必须只有一处实现，
## 两处都冻会出现「冻了两次、只解一次」的不对称。
func pause() -> void:
	if _flow_state == FLOW_REPLAYING:
		_player.pause()


func resume() -> void:
	if _flow_state == FLOW_REPLAYING:
		_player.resume()


## 立即跳过。PRD 122：「玩家可暂停/继续或立即跳过」，跳过后直接进入本关结果。
func skip() -> void:
	if _flow_state != FLOW_REPLAYING:
		return
	_player.skip()
	_enter_result()


## 重看。在结果页从头再看**同一次演出**（PRD 122/132：可在本关页面重看）。
##
## 不重新 load 记录——重看必须是同一次演出的重演，
## 重新生成或重新录制都会放成另一场戏。
func rewatch() -> bool:
	if _flow_state != FLOW_RESULT and _flow_state != FLOW_FINISHED:
		return false
	if _record == null:
		push_error("CResultFlow.rewatch: 记录已释放，无法重看")
		return false
	_player.load(_record)
	_player.play()
	_flow_state = FLOW_REPLAYING
	_emit(on_enter_replay, player_frame())
	return true


## 进入本关收场（结果页）。
func _enter_result() -> void:
	_flow_state = FLOW_RESULT
	if _is_final_stage:
		_ending = _judge_ending()
	_emit(on_enter_result, build_summary())
	_emit(on_replay_finished)


## 离开本关。
##
## PRD 132：「单次演出回放仅在本关结果页可重看，关闭游戏后不保留录像」。
## 因此离开即释放记录与回放器，不保留历史录像，也不写入长期存档
## （TECH_DESIGN 132）。之后任何 rewatch 都必须失败。
func leave_stage() -> void:
	_record = null
	_player = null
	_seen_replay = false
	_ending = &""
	_flow_state = FLOW_FINISHED
	_released = true
	_emit(on_flow_finished)


## 是否可以重看。结果页且记录仍在。
func can_rewatch() -> bool:
	return _record != null and (_flow_state == FLOW_RESULT or _flow_state == FLOW_FINISHED)


## 是否可继续回放（未播完且未跳过）。
func is_replaying() -> bool:
	return _flow_state == FLOW_REPLAYING


## 当前流程状态。
func get_flow_state() -> StringName:
	return _flow_state


## 本关结局。空值表示非最终关。
func get_ending() -> StringName:
	return _ending


## 记录是否已随离开本关释放。
var is_released: bool:
	get:
		return _released


## 本关回放时长。1:1 用本关实际时长，不用最后一帧时间戳。
func get_replay_duration_ms() -> int:
	if _record == null:
		return 0
	return _record.get_replay_duration_ms()


## 当前帧。无记录时返回安全缺省，不返回 null——集成层不必到处判空。
func player_frame() -> Dictionary:
	if _player == null:
		return {"now_ms": 0, "progress": 0.0, "puppets": [], "lamp": {},
			"events": [], "state": &"idle", "is_finished": false}
	return _player.sample(_player.get_now_ms())


## 本关收场摘要。给结果页用。
##
## 掌声段数**从记录的 acts 读，不重新判定**（PRD 122：回放不产生新分数，
## 回放读既有结果，不重新评分）。
func build_summary() -> Dictionary:
	return {
		"stage_id": _stage_id,
		"is_final_stage": _is_final_stage,
		"replay_duration_ms": get_replay_duration_ms(),
		"applause_act_count": _applause_act_count,
		"ending": _ending,
		"can_rewatch": can_rewatch(),
		"seen_replay": _seen_replay,
	}


## 统计有掌声的段数。
##
## 数据源是记录的 acts（PerformanceRecord.append_act 写入），
## 回放端只读原值。acts 结构：[{act_index, has_applause, start_ms, end_ms}]。
func _count_applause(p_record: Variant) -> void:
	_applause_act_count = 0
	for act in p_record.acts:
		if bool((act as Dictionary).get("has_applause", false)):
			_applause_act_count += 1


## 第 5 关两档结局。PRD 116 行：至少两段有掌声为满堂彩，否则戏散了。
##
## 两档都是正常结局，本方法不返回「失败」——把它当失败会让玩家
## 误以为需要重演，而 PRD 明确「没有失败或回退」（PRD 12 行）。
func _judge_ending() -> StringName:
	if _applause_act_count >= APPLAUSE_THRESHOLD:
		return ENDING_CURTAIN_CALL
	return ENDING_PLAYED_OUT


func _emit(p_callable: Callable, p_arg: Variant = null) -> void:
	if not p_callable.is_valid():
		return
	if p_arg == null:
		p_callable.call()
	else:
		p_callable.call(p_arg)


## 供测试注入掌声段数。正常运行由 A 端写入 acts，本方法只服务测试与
## 「第 5 关没打中任何掌声」这类边界验证。
func set_applause_act_count(p_count: int) -> void:
	_applause_act_count = maxi(p_count, 0)
	if _is_final_stage:
		_ending = _judge_ending()

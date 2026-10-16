extends RefCounted
## 正式第一幕（戏腔正式音源版）流程的门禁测试。
##
## 🔴 2026-10-16 第四轮用户定案后的流程：**唱段听完 → 提示借伞 → 接到伞（即收关）→ 收场（对话）**。
##   「走回小青身旁」环节已退役——接伞判据本就要求她处在许仙旁的交接窗口里，
##   因此接到伞那一帧流程直接前跳 closing_ms。还伞与「游湖对白」两段更早已退役，
##   本文件不再有 `return_dialogue` / `tour` / `return_home` 之类的阶段断言。
##
## 锚点表（与 `Act1OperaFlow.setup` 的校验、`Act1OperaStage.make_stage` 的段界一一对应，必须严格递增）：
##   opening_end_ms 唱段结束、开始提示借伞 ｜ arrival_ms 期望她已进交接窗口 ｜ take_ms 期望已接到伞
##   closing_ms 收势点 ｜ duration_ms 整轨长度

const TestBase := preload("res://tests/a/a_test_base.gd")
const FLOW_PATH := "res://scripts/a/act1_opera_flow.gd"
const CONFIG := {
	"audio_version": "test-natural-v1",
	"opening_end_ms": 3000,
	"arrival_ms": 5000,
	"take_ms": 6000,
	"closing_ms": 10000,
	"duration_ms": 12000
}


func run_all() -> Dictionary:
	var t := TestBase.new()
	t.begin("正式第一幕：唱完才提示借伞，接到伞即收关")
	if not ResourceLoader.exists(FLOW_PATH):
		t.check(false, "尚未接入第一幕借伞流程")
		return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}
	var clock := MusicClock.new()
	clock.start()
	# 站位**直接取关卡数据**（不写死数字：站位一改就与现实脱钩）。
	var def: StageDef = StageDef.make_level1()
	var slots: Dictionary = def.initial["positions"]
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		var slot: Array = slots[i]
		puppets[i].stage_pos = Vector2(float(slot[0]), float(slot[1]))
	puppets[UmbrellaController.XUXIAN_ID].hand_angle.y = StageDef.LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD
	var umbrella := UmbrellaController.new()
	umbrella.setup(def, puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	t.check(flow.setup(CONFIG, clock, umbrella), "时间表有效")
	flow.start()
	# 位置全部由判据与关卡数据算出、不写死：交接 = 窗口中心（她站在许仙旁接伞）。
	var window: Vector2 = UmbrellaController.join_window_x(StageDef.LEVEL1_XUXIAN_X)
	var at_join: float = (window.x + window.y) * 0.5
	puppets[UmbrellaController.BAISUZHEN_ID].stage_pos.x = at_join
	puppets[UmbrellaController.BAISUZHEN_ID].hand_angle.x = PI / 2.0

	# —— 唱段尚未结束：即使两手已经相接，也不许换手 ——
	# 这一段是「多谢君子唱完才开始提示玩家借伞」那条需求的直接落点：
	# 判定条件（位置 + 手高）此刻都已成立，唯一的拦阻就是「唱段没完」。
	clock.set_free_time_ms(2800)
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), UmbrellaController.XUXIAN_ID, "唱段尚未结束，即使两手相接也不换伞")

	# —— 唱段收尾（opening_end_ms）：从这里起提示玩家借伞，真实条件一成立就换手 ——
	clock.set_free_time_ms(3200)
	_step(flow, umbrella, clock)
	t.check_eq(
		umbrella.holder_id_of(), UmbrellaController.BAISUZHEN_ID, "唱完后按真实条件交接（位置 + 手高齐平）"
	)
	# 🔴 第四轮定案：接到伞即收关（她此刻就在许仙旁的交接窗口里，不用再走回小青身旁）。
	t.check_eq(flow.phase, "closing", "接到伞即收关（不用返回，站在许仙旁对话）")
	t.check_eq(clock.get_song_time_ms(), int(CONFIG["closing_ms"]), "歌曲时间前向跳到收场点")

	# —— 收关之后不再有交接：伞留在白素贞手上，不会自己回到许仙 ——
	puppets[UmbrellaController.BAISUZHEN_ID].stage_pos.x = at_join
	clock.set_free_time_ms(9000)
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), UmbrellaController.BAISUZHEN_ID, "收关后伞不会自己回到许仙手上")

	var events: Array = flow.take_events()
	var take_count := 0
	for event in events:
		if event.kind == "opera_take_close":
			take_count += 1
	t.check_eq(take_count, 1, "独立接伞收锣仅一次")
	t.finish("唱完才提示借伞，接到伞即收关（站在许仙旁，对话待接入）")
	_test_timeout(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}


## 唱段结束后她迟迟走不到许仙身旁：冻住歌曲时钟等她，最多 8 秒真实时间；
## 菜单暂停不消耗这 8 秒；超时则跳到收势点收场，且**不伪造一次交接**。
func _test_timeout(t: ATestBase) -> void:
	t.begin("等待与菜单暂停、超时不伪造交接")
	var clock := MusicClock.new()
	clock.start()
	var def: StageDef = StageDef.make_level1()
	var slots: Dictionary = def.initial["positions"]
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		var slot: Array = slots[i]
		puppets[i].stage_pos = Vector2(float(slot[0]), float(slot[1]))
	var umbrella := UmbrellaController.new()
	umbrella.setup(def, puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	flow.setup(CONFIG, clock, umbrella)
	flow.start()
	# 她仍站在开局位置（0.32），在交接窗口（0.4318~0.5518）之外
	clock.set_free_time_ms(int(CONFIG["arrival_ms"]))
	_step(flow, umbrella, clock)
	t.check(clock.is_song_frozen(), "未到许仙身旁，歌曲时间冻结")
	clock.update(3.0)
	clock.pause()
	clock.update(30.0)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "wait_arrival", "菜单暂停不消耗 8 秒等待")
	t.check_eq(clock.get_real_time_ms(), 3000, "真实时间一起暂停")
	clock.resume()
	clock.update(5.0)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "closing", "8 秒只等一次，超时直接收场")
	t.check_eq(clock.get_song_time_ms(), int(CONFIG["closing_ms"]), "只前向跳到收势点")
	t.check_eq(clock.get_real_time_ms(), 8000, "跳段保留真实时间")
	t.check_eq(umbrella.holder_id_of(), UmbrellaController.XUXIAN_ID, "超时不自动移交道具")
	t.finish("超时与双时钟语义正确")


func _step(flow: RefCounted, umbrella: UmbrellaController, clock: MusicClock) -> void:
	flow.before_update()
	if not clock.is_paused():
		umbrella.update(clock.get_song_time_ms(), [])
		flow.after_update(umbrella.take_events())

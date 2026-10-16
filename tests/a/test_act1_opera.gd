extends RefCounted
## 正式第一幕（戏腔正式音源版）流程的门禁测试。
##
## 🔴 2026-10-16 用户定案后的流程：**唱段听完 → 提示借伞 → 接到伞 → 走回小青身旁 → 结束**。
##   还伞与「游湖对白」两段已退役，因此本文件不再有 `return_dialogue` / `tour` 之类的阶段断言。
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
	t.begin("正式第一幕：唱完才提示借伞，归位即收关")
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
	# 位置全部由判据与关卡数据算出、不写死：
	#   交接 = 窗口中心；归位 = 小青的开局站位（她站哪儿、「身旁」就在哪儿）。
	var window: Vector2 = UmbrellaController.join_window_x(StageDef.LEVEL1_XUXIAN_X)
	var at_join: float = (window.x + window.y) * 0.5
	var at_xiaoping: float = StageDef.LEVEL1_XIAOPING_X
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
	t.check_eq(flow.phase, "return_home", "接伞后进入「回到小青身旁」")
	t.check(not umbrella.is_at_home(), "刚接过伞时她还在交接窗口里，不该已判为归位")

	# —— 走回小青身旁：这就是本关的完成条件，到位即收关 ——
	# 控制器在**判定之后**才刷新位置，所以归位标记要到下一帧才被流程读到（真实运行里是 1 帧，≈16 ms）。
	puppets[UmbrellaController.BAISUZHEN_ID].stage_pos.x = at_xiaoping
	clock.set_free_time_ms(6000)
	_step(flow, umbrella, clock)
	t.check(umbrella.is_at_home(), "走到小青身旁后控制器应已判为归位")
	clock.set_free_time_ms(6100)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "closing", "走回小青身旁即收关（用户：「操作完成即结束」）")
	t.check_eq(clock.get_song_time_ms(), int(CONFIG["closing_ms"]), "歌曲时间前向跳到收势点")

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
	t.finish("唱完才提示借伞，接到伞后走回小青身旁即收关")
	_test_timeout(t)
	_test_home_timeout(t)
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
	# 她仍站在开局位置（0.32），在交接窗口（0.3803~0.5003）之外
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


## 接到伞之后一直不回到小青身旁：到 closing_ms 由**时间轴**收场，不伪造「已完成」。
func _test_home_timeout(t: ATestBase) -> void:
	t.begin("持伞未归位的超时：按时收场，不伪造完成")
	var clock := MusicClock.new()
	clock.start()
	var def: StageDef = StageDef.make_level1()
	var slots: Dictionary = def.initial["positions"]
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		var slot: Array = slots[i]
		puppets[i].stage_pos = Vector2(float(slot[0]), float(slot[1]))
	# 白素贞挪到交接窗口中心（站在许仙身旁、手抬平），其余人保持关卡开演站位
	var window: Vector2 = UmbrellaController.join_window_x(StageDef.LEVEL1_XUXIAN_X)
	puppets[UmbrellaController.BAISUZHEN_ID].stage_pos.x = (window.x + window.y) * 0.5
	puppets[UmbrellaController.BAISUZHEN_ID].hand_angle.x = PI / 2.0
	puppets[UmbrellaController.XUXIAN_ID].hand_angle.y = StageDef.LEVEL1_XUXIAN_UMBRELLA_RAISE_RAD
	var umbrella := UmbrellaController.new()
	umbrella.setup(def, puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	flow.setup(CONFIG, clock, umbrella)
	flow.start()
	clock.set_free_time_ms(3200)
	_step(flow, umbrella, clock)
	t.check(flow.taken, "真实接到伞")
	# 站在原地不动（仍在交接窗口里，够不到小青身旁）→ 归位标记不会置起
	clock.set_free_time_ms(9900)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "return_home", "没走回小青身旁时不应收关")
	t.check(not umbrella.is_at_home(), "停在交接窗口里不该被判为已归位")
	clock.set_free_time_ms(10100)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "closing", "歌曲时间到收势点仍按时收场")
	t.check_eq(
		umbrella.holder_id_of(), UmbrellaController.BAISUZHEN_ID, "由时间轴收场，伞仍在白素贞手上"
	)
	t.finish("未归位时由时间轴收场，不伪造完成")

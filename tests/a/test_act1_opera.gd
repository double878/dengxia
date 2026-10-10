extends RefCounted

const TestBase := preload("res://tests/a/a_test_base.gd")
const FLOW_PATH := "res://scripts/a/act1_opera_flow.gd"
const CONFIG := {"audio_version": "test-natural-v1", "opening_end_ms": 1000,
	"arrival_ms": 2000, "singing_start_ms": 2400, "singing_end_ms": 3500,
	"take_ms": 3900, "tour_start_ms": 3900, "return_gate_ms": 8000,
	"return_start_ms": 8500, "closing_ms": 11000, "duration_ms": 12000}


func run_all() -> Dictionary:
	var t := TestBase.new()
	t.begin("正式第一幕的对白和真实交接门禁")
	if not ResourceLoader.exists(FLOW_PATH):
		t.check(false, "尚未接入唱完接伞、真实还伞后对白的流程")
		return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}
	var clock := MusicClock.new()
	clock.start()
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		puppets[i].stage_pos = Vector2(0.8 if i != 1 else 0.13, 0.5)
	puppets[1].hand_angle.y = PI / 2.0
	var umbrella := UmbrellaController.new()
	umbrella.setup(StageDef.make_level1(), puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	t.check(flow.setup(CONFIG, clock, umbrella), "时间表有效")
	flow.start()
	puppets[0].stage_pos.x = 0.24
	puppets[0].hand_angle.x = PI / 2.0
	clock.set_free_time_ms(2800)
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), 1, "唱段尚未结束，即使两手相接也不换伞")
	clock.set_free_time_ms(3900)
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), 0, "唱完后按当前手位交接")
	t.check_eq(flow.phase, "tour", "真实接伞才进入游湖")
	puppets[0].stage_pos.x = 0.75
	clock.set_free_time_ms(6000)
	_step(flow, umbrella, clock)
	puppets[0].stage_pos.x = 0.24
	clock.set_free_time_ms(7000)
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), 1, "到过小青身旁才能实际还伞")
	clock.set_free_time_ms(8000)
	_step(flow, umbrella, clock)
	t.check(not clock.is_song_frozen(), "已实际还伞，无需等候")
	clock.set_free_time_ms(8500)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "return_dialogue", "只有实际还伞后播放奉还对白")
	puppets[0].stage_pos.x = 0.5
	_step(flow, umbrella, clock)
	puppets[0].stage_pos.x = 0.24
	_step(flow, umbrella, clock)
	t.check_eq(umbrella.holder_id_of(), 1, "还伞后不会再次借走或响第二次锣")
	var events: Array = flow.take_events()
	var take_count := 0
	for event in events:
		if event.kind == "opera_take_close":
			take_count += 1
	t.check_eq(take_count, 1, "独立接伞收锣仅一次")
	t.finish("唱说与道具条件保持一致")
	_test_timeout(t)
	_test_return_timeout(t)
	return {"exit_code": t.report(), "passed": t.passed, "failed": t.failed}


func _test_timeout(t: ATestBase) -> void:
	t.begin("等待与菜单暂停、超时不伪造奉还")
	var clock := MusicClock.new()
	clock.start()
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		puppets[i].stage_pos = Vector2(0.8 if i != 1 else 0.13, 0.5)
	var umbrella := UmbrellaController.new()
	umbrella.setup(StageDef.make_level1(), puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	flow.setup(CONFIG, clock, umbrella)
	flow.start()
	clock.set_free_time_ms(2000)
	_step(flow, umbrella, clock)
	t.check(clock.is_song_frozen(), "未到许仙身旁，歌曲时间冻结")
	clock.update(3.0)
	clock.pause()
	clock.update(30.0)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "wait_arrival", "菜单暂停不消耗8秒等待")
	t.check_eq(clock.get_real_time_ms(), 3000, "真实时间一起暂停")
	clock.resume()
	clock.update(5.0)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "closing", "8秒只等一次，超时无对白收场")
	t.check_eq(clock.get_song_time_ms(), 11000, "只前向跳到器乐尾声")
	t.check_eq(clock.get_real_time_ms(), 8000, "跳段保留真实时间")
	t.check_eq(umbrella.holder_id_of(), 1, "超时不自动移交道具")
	t.check(not flow.returned, "不伪造实际还伞")
	t.finish("超时与双时钟语义正确")


func _step(flow: RefCounted, umbrella: UmbrellaController, clock: MusicClock) -> void:
	flow.before_update()
	if not clock.is_paused():
		umbrella.update(clock.get_song_time_ms(), [])
		flow.after_update(umbrella.take_events())


func _test_return_timeout(t: ATestBase) -> void:
	t.begin("持伞未还的超时不会播放奉还对白")
	var clock := MusicClock.new()
	clock.start()
	var puppets: Array = [PuppetState.new(), PuppetState.new(), PuppetState.new()]
	for i in puppets.size():
		puppets[i].puppet_id = i
		puppets[i].stage_pos = Vector2(0.24 if i == 0 else 0.13, 0.5)
	puppets[0].hand_angle.x = PI / 2.0
	puppets[1].hand_angle.y = PI / 2.0
	var umbrella := UmbrellaController.new()
	umbrella.setup(StageDef.make_level1(), puppets)
	var flow: RefCounted = load(FLOW_PATH).new()
	flow.setup(CONFIG, clock, umbrella)
	flow.start()
	clock.set_free_time_ms(3900)
	_step(flow, umbrella, clock)
	t.check(flow.taken, "真实接到伞")
	clock.set_free_time_ms(8000)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "wait_return", "未走完往返，等待实际还伞")
	clock.update(8.0)
	_step(flow, umbrella, clock)
	t.check_eq(flow.phase, "closing", "不播还伞对白，跳到器乐收束")
	t.check_eq(umbrella.holder_id_of(), 0, "超时仍由白素贞实际持伞")
	t.check(not flow.returned, "未伪造成功归还")
	t.finish("未还伞时安全跳过九句对白")

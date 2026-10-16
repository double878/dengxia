extends RefCounted
class_name Act1OperaStage
## 根据已制作音源建第一幕；旧 StageDef 工厂仍供其他关卡和旧测试使用。
##
## 🔴 2026-10-16：这里曾有一个 `XUXIAN_SHORE_X = 0.28` 的硬编码覆盖（「许仙站岸边」）。
##   用户当天定案改为**许仙站桥头**后，那份覆盖已删除——许仙站位现在只由
##   `StageDef.LEVEL1_XUXIAN_X`（0.5285 = 桥左端）一处决定，正式画面与生产数据重新合一。
##   ⚠️ 别再在这里加站位覆盖：两套数据一旦分叉，A 侧判据、落点带与游戏画面就会各说各话
##   （`tests/a/test_level1_cues.gd` 与 `test_umbrella.gd` 的「对表」断言都在防这个）。


static func make_stage(config: Dictionary) -> StageDef:
	var def := StageDef.make_level1()
	def.duration_ms = int(config.duration_ms)
	def.track_path = str(config.main_path)
	def.title = "第一幕 · 游湖借伞"
	def.roles = ["白素贞", "许仙", "小青"]
	def.segments = []
	# 段落表 = 「唱段 → 移步借伞 → 接伞 → 回到小青身旁 → 收势」。
	# ⚠️ 2026-10-16 流程简化（用户「借伞 → 回到小青身旁 → 结束」，不再还伞）后，
	# 原「游湖 / 还伞对白」两段合并为「回到小青身旁」；段界用锚点派生，不手写毫秒。
	var starts: Array = [
		0,
		int(config.opening_end_ms),
		int(config.arrival_ms),
		int(config.take_ms),
		int(config.closing_ms),
		def.duration_ms
	]
	var names: Array = ["湖上唱段", "移步借伞", "接伞", "回到小青身旁", "收势"]
	for i in names.size():
		def.segments.append({"name": names[i], "start_ms": starts[i], "end_ms": starts[i + 1]})
	# 交接改为真实条件触发，不用固定拍点考玩家；对白期间不安排评分动作。
	# 🔴 2026-10-16 用户定案「最后白素贞手不用放下」：原「收势落手」cue
	# （l1_opera_lower_hand，closing_ms+900 判落手）**下线**——她走回小青身旁的那一刻
	# Act1OperaFlow 直接收关，不再要求任何落手动作。cue 表随之清空； UmbrellaController
	# 的交接事件照常走 PerformanceSystem（与其它动作同一条判定路径）。
	def.cues = []
	return def

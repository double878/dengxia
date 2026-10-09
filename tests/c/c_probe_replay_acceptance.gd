extends SceneTree
## 回放验收探针（无头）。
##
## 运行：
##   godot.exe --headless --path . --script res://tests/c/c_probe_replay_acceptance.gd
##
## 职责：拿一份内容已知的模拟演出，跑完整回放验收，打印报告并按结论定退出码。
## 这是 TECH_DESIGN 第 4 节末段验收的可执行形态——不必开画面，可回归、可进 CI。
##
## 用 SceneTree 而非普通脚本：需要 _initialize 在无头模式下跑一次就退出。
## 依赖一律用 preload 常量：--headless --script 不读全局类名缓存。

const CMockPerformerScript := preload("res://scripts/c/c_mock_performer.gd")
const CReplayVerifierScript := preload("res://scripts/c/c_replay_verifier.gd")

## 验收用的关卡号。取第 5 关：它是唯一有两档结局的关卡，
## 因此「掌声 → 结局」这条链路也一并被验收，不会空过。
const VERIFY_STAGE_ID: int = 5


func _initialize() -> void:
	print("《灯下》回放验收")
	print("=".repeat(52))

	var performer: Variant = CMockPerformerScript.new()
	var record: Variant = performer.build(VERIFY_STAGE_ID, true)

	print("模拟演出：第 %d 关 / %dms / 快照 %d 帧 / 事件 %d 条 / 幕 %d 段"
		% [int(record.stage_id), int(record.duration_ms),
			record.snapshots.size(), record.events.size(), record.acts.size()])
	print("验收要素：" + ", ".join(CMockPerformerScript.covered_features()))
	print("")

	var verifier: Variant = CReplayVerifierScript.new()
	var report: Dictionary = verifier.verify(record, CReplayVerifierScript.DEFAULT_STEP_MS)
	print(verifier.describe_report(report))

	print("")
	print("=".repeat(52))
	if bool(report["ok"]):
		print("回放验收通过：原演出与幕前回放是同一场戏。")
		quit(0)
	else:
		print("回放验收未通过：共 %d 项问题，详见上方。" % report["problems"].size())
		quit(1)

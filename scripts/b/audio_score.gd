extends RefCounted
class_name AudioScore
## 剧情时间表与唱腔分轨契约；不参与动作判定。

var stage_id: int = 1
var duration_ms: int = 55000
var bpm: float = 96.0
var audio_version: String = "act1-ai-v1"
var tracks: Array[Dictionary] = []
var lines: Array[Dictionary] = []
var slow_path: String = "res://assets/audio/act1/remedy_slow.wav"


static func make_act1() -> AudioScore:
	var score := AudioScore.new()
	for item in [["drums", ""], ["instrumental", ""], ["vocal_xuxian", "xuxian"],
			["vocal_baisuzhen", "baisuzhen"], ["vocal_xiaoqing", "xiaoqing"]]:
		score.tracks.append({"asset_id": item[0], "role_id": item[1],
			"path": "res://assets/audio/act1/%s.wav" % item[0]})
	var rows: Array = [
		["xiaoqing_01", "xiaoqing", 5000, 10000, "姐姐移步到亭前。", "l1_c2_move_left"],
		["xuxian_01", "xuxian", 12500, 20000, "一柄青伞遮春雨。", "l1_c3_hand_raise"],
		["baisuzhen_01", "baisuzhen", 22500, 30000, "借伞归来再奉还。", "l1_c4_take_umbrella"],
		["baisuzhen_02", "baisuzhen", 37500, 45000, "青伞还君情未了。", "l1_c6_return_umbrella"],
		["xuxian_02", "xuxian", 47500, 52500, "他朝有缘再相见。", ""],
	]
	for row in rows:
		score.lines.append({"line_id": row[0], "role_id": row[1], "start_ms": row[2],
			"end_ms": row[3], "text": row[4], "cue_id": row[5],
			"vocal_asset_id": "vocal_%s" % row[1]})
	return score


func line_at(song_ms: int) -> Dictionary:
	for line in lines:
		if song_ms >= int(line["start_ms"]) and song_ms < int(line["end_ms"]):
			return line.duplicate(true)
	return {}


func validate() -> Array[String]:
	var problems: Array[String] = []
	if stage_id <= 0 or duration_ms <= 0 or not is_finite(bpm) or bpm <= 0.0:
		problems.append("音频幕次、时长或 BPM 非法")
	if audio_version.is_empty() or tracks.is_empty() or tracks.size() > 16:
		problems.append("音频版本或轨道数量非法")
	var assets := {}
	var roles := {}
	for track in tracks:
		var asset: String = str(track.get("asset_id", ""))
		var role: String = str(track.get("role_id", ""))
		if asset.is_empty() or assets.has(asset) or str(track.get("path", "")).is_empty():
			problems.append("空或重复音轨：%s" % asset)
		assets[asset] = true
		if not role.is_empty():
			if roles.has(role):
				problems.append("重复角色音轨：%s" % role)
			roles[role] = asset
	if not assets.has("drums") or not assets.has("instrumental") or slow_path.is_empty():
		problems.append("缺少锣鼓、器乐或补救慢鼓配置")
	var seen := {}
	var previous_end: int = 0
	for line in lines:
		var id: String = str(line.get("line_id", ""))
		var role: String = str(line.get("role_id", ""))
		var begin: int = int(line.get("start_ms", -1))
		var end: int = int(line.get("end_ms", -1))
		if id.is_empty() or seen.has(id):
			problems.append("空或重复唱句：%s" % id)
		seen[id] = true
		if begin < previous_end or end <= begin or end > duration_ms:
			problems.append("唱句 %s 时间越界、倒序或重叠" % id)
		previous_end = end
		if not roles.has(role) or str(line.get("vocal_asset_id", "")) != str(roles.get(role, "")):
			problems.append("唱句 %s 的角色与声轨不一致" % id)
		if str(line.get("text", "")).is_empty():
			problems.append("唱句 %s 缺少唱词" % id)
	return problems


## 所有正式运行文件使用 48 kHz / 16-bit WAV，关掉自动裁头与循环。
func validate_streams(streams: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for track in tracks:
		var id: String = str(track["asset_id"])
		_check_wav(id, streams.get(id), float(duration_ms) / 1000.0, problems)
	_check_wav("remedy_slow", streams.get("remedy_slow"), 0.0, problems)
	return problems


func _check_wav(id: String, stream: Variant, expected_s: float, problems: Array[String]) -> void:
	if not (stream is AudioStreamWAV):
		problems.append("缺少 PCM WAV 音轨：%s" % id)
		return
	var wav: AudioStreamWAV = stream
	if wav.mix_rate != 48000 or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		problems.append("%s 须为 48 kHz / 16-bit 运行 WAV" % id)
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		problems.append("%s 导入资源须关闭循环，由播放器管理慢鼓循环" % id)
	if wav.get_length() <= 0.0 or (expected_s > 0.0 and absf(wav.get_length() - expected_s) > 0.001):
		problems.append("%s 长度错误：%.6f s，要求 %.3f s" % [id, wav.get_length(), expected_s])


func load_bundle() -> Dictionary:
	var streams := {}
	var problems: Array[String] = validate()
	var paths := {}
	for track in tracks:
		paths[track["asset_id"]] = track["path"]
	paths["remedy_slow"] = slow_path
	for id in paths:
		var path: String = str(paths[id])
		if ResourceLoader.exists(path):
			streams[id] = load(path)
		else:
			problems.append("尚未交付 %s：%s" % [id, path])
	problems.append_array(validate_streams(streams))
	return {"streams": streams, "problems": problems}

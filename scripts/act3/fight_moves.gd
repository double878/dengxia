extends RefCounted
## 参考视频的蓄势、腾空、进剑、收势。高度/步幅交给搭戏器按舞台与目标定位。
## 每行：拍内进度、右肩、右肘、蹲、腾空比例、张腿、朝前倾角、进退比例、左臂。
enum Key { TIME, SHOULDER, ELBOW, CROUCH, AIR, SPREAD, TILT, TRAVEL, FREE_ARM }
const DEER := [
	{
		"name": "跃身进刺",
		"duration": 2.45,
		"reach": 175.0,
		"height": 145.0,
		"keys":
		[
			[0, 1.4, 1.0, .08, 0, 0, 0, 0, .7],
			[.20, 1.9, .75, .40, 0, 0, -.12, 0, 1.0],
			[.42, 1.35, .12, .02, 1, 1, .85, .75, 2.2],
			[.57, 1.25, .08, .02, .65, .8, .55, 1, 1.7],
			[.75, 1.9, .45, .18, 0, 0, -.12, .6, 1.2],
			[1, 1.4, 1.0, .08, 0, 0, 0, 0, .7]
		]
	},
	{
		"name": "下扫接上挑",
		"duration": 2.65,
		"reach": 115.0,
		"height": 70.0,
		"keys":
		[
			[0, 1.4, 1.0, .08, 0, 0, 0, 0, .7],
			[.20, .85, .8, .50, 0, 0, .15, 0, 1.8],
			[.36, .55, .12, .60, 0, 0, .35, .85, 1.6],
			[.57, 2.15, .20, .04, .75, .75, -.15, 1, .4],
			[.72, 1.4, .08, .03, 1, 1, .4, .85, 2.0],
			[.85, 1.6, .5, .20, 0, 0, .05, .5, 1.0],
			[1, 1.4, 1.0, .08, 0, 0, 0, 0, .7]
		]
	},
	{
		"name": "转身横扫",
		"duration": 2.5,
		"reach": 145.0,
		"height": 100.0,
		"keys":
		[
			[0, 1.4, 1.0, .08, 0, 0, 0, 0, .7],
			[.20, 2.35, .5, .3, 0, 0, -.2, 0, 1.3],
			[.40, 1.7, .1, .04, 1, 1, .35, .9, 2.3],
			[.56, .9, .15, .2, .4, .7, .7, 1, 1.8],
			[.72, 2.2, .6, .25, 0, 0, -.3, .5, .4],
			[1, 1.4, 1.0, .08, 0, 0, 0, 0, .7]
		]
	}
]
const CRANE := [
	{
		"name": "架剑反挑",
		"duration": 2.95,
		"reach": 110.0,
		"height": 55.0,
		"keys":
		[
			[0, 1.9, .85, .08, 0, 0, -.08, 0, 1.0],
			[.20, 2.15, .65, .18, 0, 0, -.15, -.1, 1.3],
			[.37, .5, .45, .48, 0, 0, .1, -.2, 1.9],
			[.62, 2.25, .25, .03, 1, .8, .28, 1, .45],
			[.78, 2.2, .65, .16, 0, 0, -.12, .5, 1.1],
			[1, 1.9, .85, .08, 0, 0, -.08, 0, 1.0]
		]
	},
	{
		"name": "腾挪回身剑",
		"duration": 2.85,
		"reach": 155.0,
		"height": 130.0,
		"keys":
		[
			[0, 1.9, .85, .08, 0, 0, -.08, 0, 1.0],
			[.20, 2.35, .5, .30, 0, 0, -.25, 0, 1.5],
			[.38, 1.2, .25, .02, 1, 1, -.65, -.65, 2.2],
			[.56, 1.3, .75, .04, .6, .85, -.4, -.8, 1.3],
			[.70, 1.45, .08, .14, 0, 0, .35, .6, .5],
			[.84, 1.5, .15, .14, 0, 0, .25, .7, .6],
			[1, 1.9, .85, .08, 0, 0, -.08, 0, 1.0]
		]
	},
	{
		"name": "跃起劈剑",
		"duration": 2.75,
		"reach": 140.0,
		"height": 150.0,
		"keys":
		[
			[0, 1.9, .85, .08, 0, 0, -.08, 0, 1.0],
			[.20, 2.45, .4, .42, 0, 0, -.2, 0, 1.4],
			[.42, 1.75, .4, .01, 1, 1, .25, .65, 2.25],
			[.60, 1.2, .12, .04, .7, .8, .65, 1, .6],
			[.77, .85, .4, .36, 0, 0, .25, .6, .8],
			[1, 1.9, .85, .08, 0, 0, -.08, 0, 1.0]
		]
	}
]


static func at_time(actor_id: int, seconds: float) -> Dictionary:
	var moves: Array = DEER if actor_id == 1 else CRANE
	var total: float = 0.0
	for move: Dictionary in moves:
		total += float(move.duration)
	var cycle: int = int(floor(seconds / total))
	var remaining: float = fmod(maxf(seconds, 0.0), total)
	for i in moves.size():
		var move: Dictionary = moves[i]
		if remaining < float(move.duration) or i == moves.size() - 1:
			return {
				"move": move,
				"index": i,
				"cycle": cycle * moves.size() + i,
				"progress": remaining / float(move.duration)
			}
		remaining -= float(move.duration)
	return {}


static func sample(move: Dictionary, progress: float) -> Dictionary:
	var keys: Array = move["keys"]
	var row: Array = keys[-1]
	for i in range(1, keys.size()):
		if progress > float(keys[i][Key.TIME]):
			continue
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		var t: float = smoothstep(float(a[Key.TIME]), float(b[Key.TIME]), progress)
		row = []
		for j in b.size():
			row.append(lerpf(float(a[j]), float(b[j]), t))
		break
	return {
		"shoulder": row[Key.SHOULDER],
		"elbow": row[Key.ELBOW],
		"crouch": row[Key.CROUCH],
		"air": row[Key.AIR],
		"spread": row[Key.SPREAD],
		"tilt": row[Key.TILT],
		"travel": row[Key.TRAVEL],
		"free_arm": row[Key.FREE_ARM]
	}

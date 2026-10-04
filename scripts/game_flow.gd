extends Node

# GameFlow：游戏入口。
#
# 职责见 TECH_DESIGN.md 第 1.1 节「最小模块边界」：保持轻量，不建立通用剧情、
# 任务或存档框架。选关、演前戏单、幕前回放与收场属后续里程碑（PRD 第 3 节）。
#
# 当前形态：直接进入幕后演出场景（前四关共用同一个场景，只换关卡数据）。
# 之所以先接这一条，是因为在此之前主场景是一个空 Node——双击运行游戏只会得到一个
# 黑窗口，实际能玩的只有编辑器里手动打开的测试场景，这正是「第一关看不见/听不见」
# 的一个直接来源。选关菜单做出来之后，这里改成进选关即可，演出场景本身不受影响。
#
# 开发时切关：`dengxia.exe -- stage=2`（1–4，缺省第 1 关）。这是命令行开关而不是按键，
# 因为 PRD 第 4.1 节只定义了一套键位，演出场景里不该出现测试专用键。

const PERFORMANCE_SCENE := preload("res://scenes/a_test/level1_a.tscn")

var _level: Node = null


func _ready() -> void:
	_level = PERFORMANCE_SCENE.instantiate()
	add_child(_level)

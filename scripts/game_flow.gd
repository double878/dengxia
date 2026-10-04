extends Node

# GameFlow：游戏入口。
#
# 职责见 TECH_DESIGN.md 第 1.1 节「最小模块边界」：保持轻量，不建立通用剧情、
# 任务或存档框架。选关、演前戏单、幕前回放与收场属后续里程碑（PRD 第 3 节）。
#
# 当前形态：直接进入第一关「入手」。之所以先接这一条，是因为在此之前主场景是一个
# 空 Node——双击运行游戏只会得到一个黑窗口，实际能玩的只有编辑器里手动打开的
# 测试场景，这正是「第一关看不见/听不见」的一个直接来源。
# 选关菜单做出来之后，这里改成进选关即可，第一关场景本身不受影响。

const LEVEL1_SCENE := preload("res://scenes/a_test/level1_a.tscn")

var _level: Node = null


func _ready() -> void:
	_level = LEVEL1_SCENE.instantiate()
	add_child(_level)

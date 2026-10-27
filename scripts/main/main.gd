## 入口：按命令行参数走自动化验证路径，否则只装配会话并显示主菜单。
## 命令行以「--」分隔传入：
##   godot --headless --path . -- --smoke            全流程冒烟断言
##   godot --headless --path . -- --combat           战斗与平衡模拟
##   godot --path . -- --shot=/tmp/shots/island   截图
## 注意：导出包（export/windows）exclude_filter 已排除 tests/ 与 reports/，
## 因此测试脚本只在源码工程内可用，不会进入发行包。
extends Node

const SMOKE_SCRIPT := "res://tests/smoke_runner.gd"
const SHOT_SCRIPT := "res://tests/screenshot_runner.gd"
const COMBAT_SCRIPT := "res://tests/combat_runner.gd"

var session: Node = null


func _ready() -> void:
	session = load("res://scripts/main/game_session.gd").new()
	session.name = "Session"
	add_child(session)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--smoke" and ResourceLoader.exists(SMOKE_SCRIPT):
			var runner: Node = load(SMOKE_SCRIPT).new()
			runner.set("session", session)
			add_child(runner)
			return
		if a.begins_with("--shot=") and ResourceLoader.exists(SHOT_SCRIPT):
			var shot: Node = load(SHOT_SCRIPT).new()
			shot.set("session", session)
			shot.set("out_path", a.substr(7))
			add_child(shot)
			return
		if a == "--combat" and ResourceLoader.exists(COMBAT_SCRIPT):
			var combat: Node = load(COMBAT_SCRIPT).new()
			combat.set("session", session)
			add_child(combat)
			return

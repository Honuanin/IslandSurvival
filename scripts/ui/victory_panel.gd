## 胜利结算：用时、死亡、击杀、建筑数量；继续自由游玩或新游戏（GDD 10.2、FLOW-003）。
## @trace FLOW-003
class_name VictoryPanel
extends Control

signal continue_requested
signal new_game_requested

var _info: Label


## 让控件撑满父级：显式锚点 + offset，不依赖 set_anchors_preset 的父级尺寸推断
static func _fill_parent(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _ready() -> void:
	# 挂在 CanvasLayer 下时没有父 Control，set_anchors_preset 不会撑开自身 size，
	# 因此必须显式给出四个 offset，否则锚点百分比按 0 尺寸计算会让子控件偏移到屏幕外。
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.09, 0.07, 0.9)
	_fill_parent(bg)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -380.0
	vb.offset_top = -240.0
	vb.offset_right = 380.0
	vb.offset_bottom = 240.0
	vb.add_theme_constant_override("separation", 16)
	add_child(vb)
	var t := Label.new()
	t.text = "信 号 火 台 已 点 燃"
	t.add_theme_font_size_override("font_size", 56)
	t.add_theme_color_override("font_color", Color("#F2C14E"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := Label.new()
	sub.text = "远处船影回应了火光。你可以留在岛上继续补全营地与升级。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(700, 0)
	vb.add_child(sub)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size = Vector2(700, 0)
	vb.add_child(_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vb.add_child(row)
	var b1 := Button.new()
	b1.text = "继续自由游玩"
	b1.custom_minimum_size = Vector2(300, 58)
	b1.pressed.connect(func(): continue_requested.emit())
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "新游戏"
	b2.custom_minimum_size = Vector2(300, 58)
	b2.pressed.connect(func(): new_game_requested.emit())
	row.add_child(b2)


func show_result(stats: Dictionary) -> void:
	visible = true
	var secs := float(stats.get("play_time", 0.0))
	_info.text = "用时 %d 分 %d 秒　｜　死亡 %d 次　｜　击败敌人 %d　｜　建造 %d 座" % [
		int(secs / 60.0), int(secs) % 60,
		int(stats.get("deaths", 0)), int(stats.get("kills", 0)), int(stats.get("buildings", 0)),
	]

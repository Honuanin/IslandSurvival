## 暂停 / 死亡 / 胜利 三个全屏面板（GDD 10.2）。
## @trace MECH-010 FLOW-003
class_name PausePanel
extends Control

signal resume_requested
signal save_requested
signal quit_requested


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
	bg.color = Color(0.03, 0.05, 0.06, 0.82)
	_fill_parent(bg)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -240.0
	vb.offset_top = -200.0
	vb.offset_right = 240.0
	vb.offset_bottom = 200.0
	vb.add_theme_constant_override("separation", 16)
	add_child(vb)
	var t := Label.new()
	t.text = "已暂停"
	t.add_theme_font_size_override("font_size", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var note := Label.new()
	note.text = "暂停时世界时间停止。背包与建造界面不会暂停世界。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#9FB3B8"))
	vb.add_child(note)
	_btn(vb, "继续游戏").pressed.connect(func(): resume_requested.emit())
	_btn(vb, "保存").pressed.connect(func(): save_requested.emit())
	_btn(vb, "返回主菜单").pressed.connect(func(): quit_requested.emit())


func _btn(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b

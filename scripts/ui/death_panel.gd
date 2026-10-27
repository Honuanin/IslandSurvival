## 死亡界面：死因、尸体规则、复活（GDD 6.9、10.2）。
## @trace MECH-008
class_name DeathPanel
extends Control

signal respawn_requested

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
	bg.color = Color(0.12, 0.03, 0.03, 0.86)
	_fill_parent(bg)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -380.0
	vb.offset_top = -220.0
	vb.offset_right = 380.0
	vb.offset_bottom = 220.0
	vb.add_theme_constant_override("separation", 16)
	add_child(vb)
	var t := Label.new()
	t.text = "你 倒 下 了"
	t.add_theme_font_size_override("font_size", 60)
	t.add_theme_color_override("font_color", Color("#D95555"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(700, 0)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info)
	var b := Button.new()
	b.text = "复活"
	b.custom_minimum_size = Vector2(400, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): respawn_requested.emit())
	vb.add_child(b)


func show_death(reason: String, deaths: int) -> void:
	visible = true
	_info.text = "死因：%s\n死亡次数：%d\n\n规则：背包与装备已留在死亡地点；任务物品保留。\n再次死亡会清除上一具遗体。"
	_info.text = _info.text % [reason, deaths]

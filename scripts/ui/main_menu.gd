## 主菜单：继续 / 新游戏 / 操作说明 / 退出（GDD 10.2）。
## @trace UI-001 FLOW-001
class_name MainMenu
extends Control

signal start_new
signal continue_game

var _continue_btn: Button
var _help: Label


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
	bg.color = Color("#101A1F")
	_fill_parent(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := VBoxContainer.new()
	center.anchor_left = 0.5
	center.anchor_top = 0.5
	center.anchor_right = 0.5
	center.anchor_bottom = 0.5
	center.position = Vector2(-380, -330)
	center.custom_minimum_size = Vector2(760, 0)
	center.add_theme_constant_override("separation", 14)
	add_child(center)
	var title := Label.new()
	title.text = "孤 岛 求 生"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", Color("#F2C14E"))
	center.add_child(title)
	var sub := Label.new()
	sub.text = "纵向切片 v0.1 · Godot 4.3 · 采集 / 制作 / 建造 / 战斗 / 火台结局"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("#9FB3B8"))
	center.add_child(sub)
	_continue_btn = _button(center, "继续游戏")
	_continue_btn.pressed.connect(func(): continue_game.emit())
	_button(center, "新游戏").pressed.connect(func(): start_new.emit())
	var help_btn := _button(center, "操作说明")
	help_btn.pressed.connect(_toggle_help)
	_button(center, "退出").pressed.connect(func(): get_tree().quit())
	_help = Label.new()
	_help.text = "移动 WASD ｜ 冲刺 Shift ｜ 交互 E ｜ 攻击/采集 左键 ｜ 闪避 右键\n" \
		+ "背包/制作 Tab（世界继续运行）｜ 建造 B ｜ 旋转 R ｜ 拆除 X ｜ 快捷栏 1–5 ｜ 暂停 Esc\n" \
		+ "目标：工作台 → 湿地透镜 → 击败遗迹守卫 → 在信号点建造并点燃信号火台"
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(720, 0)
	_help.add_theme_color_override("font_color", Color("#CFE0E6"))
	_help.visible = false
	center.add_child(_help)


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


func _toggle_help() -> void:
	_help.visible = not _help.visible


func set_has_save(has_save: bool) -> void:
	_continue_btn.disabled = not has_save
	_continue_btn.text = "继续游戏" if has_save else "继续游戏（无存档）"

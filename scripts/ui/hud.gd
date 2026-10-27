## HUD：左上状态、右上时间与区域、下方快捷栏、右侧主线、中央交互/危险/建造提示。
## 只订阅状态并发出请求，不直接改世界数据（GDD 11.2）。
## @trace UI-001 UI-002 SIG-001
class_name Hud
extends Control

signal build_requested
signal toggle_inventory_requested
signal toggle_build_requested
signal use_hotbar_requested(index: int)
signal toggle_pause_requested

var player: Player = null
var _bars: Dictionary = {}
var _labels: Dictionary = {}
var _toast_box: VBoxContainer
var _interact_panel: PanelContainer
var _interact_label: Label
var _danger_panel: PanelContainer
var _danger_label: Label
var _build_panel: PanelContainer
var _build_label: Label
var _objective_box: VBoxContainer
var _time_label: Label
var _region_label: Label
var _slot_labels: Array = []
var _hp_bar: ProgressBar
var _stamina_bar: ProgressBar
var _hunger_bar: ProgressBar
var _thirst_bar: ProgressBar
var _temp_label: Label
var _temp_bar: ProgressBar
var _objective_dirty: bool = true


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
	_fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_static()


func _build_static() -> void:
	# ---- 左上状态块 ----
	var stats_panel := PanelContainer.new()
	stats_panel.position = Vector2(28, 24)
	stats_panel.custom_minimum_size = Vector2(360, 0)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stats_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	stats_panel.add_child(vb)
	_hp_bar = _add_bar(vb, "生命", Color("#D95555"))
	_stamina_bar = _add_bar(vb, "体力", Color("#68C3A3"))
	_hunger_bar = _add_bar(vb, "饥饿", Color("#C9A227"))
	_thirst_bar = _add_bar(vb, "口渴", Color("#4A90C2"))
	var temp_row := HBoxContainer.new()
	vb.add_child(temp_row)
	var tl := Label.new()
	tl.text = "体温"
	tl.custom_minimum_size = Vector2(64, 0)
	temp_row.add_child(tl)
	_temp_bar = ProgressBar.new()
	_temp_bar.min_value = 30.0
	_temp_bar.max_value = 41.0
	_temp_bar.value = 37.0
	_temp_bar.show_percentage = false
	_temp_bar.custom_minimum_size = Vector2(200, 20)
	temp_row.add_child(_temp_bar)
	_temp_label = Label.new()
	_temp_label.text = "37.0℃"
	temp_row.add_child(_temp_label)

	# ---- 右上时间/区域 ----
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-260, 24)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_right)
	_time_label = Label.new()
	_time_label.text = "08:00"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 30)
	top_right.add_child(_time_label)
	_region_label = Label.new()
	_region_label.text = "搁浅海滩"
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_region_label.add_theme_color_override("font_color", Color("#F2C14E"))
	top_right.add_child(_region_label)

	# ---- 右侧主线 ----
	var obj_panel := PanelContainer.new()
	obj_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	obj_panel.position = Vector2(-400, 110)
	obj_panel.custom_minimum_size = Vector2(360, 0)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(obj_panel)
	_objective_box = VBoxContainer.new()
	obj_panel.add_child(_objective_box)
	var ot := Label.new()
	ot.text = "主线"
	ot.add_theme_color_override("font_color", Color("#F2C14E"))
	_objective_box.add_child(ot)

	# ---- 中央交互提示 ----
	_interact_panel = PanelContainer.new()
	_interact_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_panel.position = Vector2(-220, -230)
	_interact_panel.custom_minimum_size = Vector2(440, 0)
	_interact_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.visible = false
	add_child(_interact_panel)
	_interact_label = Label.new()
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_panel.add_child(_interact_label)

	# ---- 危险提示 ----
	_danger_panel = PanelContainer.new()
	_danger_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_danger_panel.position = Vector2(-260, 150)
	_danger_panel.custom_minimum_size = Vector2(520, 0)
	_danger_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_panel.visible = false
	add_child(_danger_panel)
	_danger_label = Label.new()
	_danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger_panel.add_child(_danger_label)

	# ---- 建造提示 ----
	_build_panel = PanelContainer.new()
	_build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_panel.position = Vector2(-300, -170)
	_build_panel.custom_minimum_size = Vector2(600, 0)
	_build_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel.visible = false
	add_child(_build_panel)
	_build_label = Label.new()
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_panel.add_child(_build_label)

	# ---- 快捷栏 ----
	var hotbar := HBoxContainer.new()
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.position = Vector2(-270, -120)
	hotbar.add_theme_constant_override("separation", 8)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotbar)
	for i in range(5):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(104, 74)
		hotbar.add_child(slot)
		var sl := Label.new()
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.text = "%d" % (i + 1)
		slot.add_child(sl)
		_slot_labels.append(sl)

	# ---- Toast ----
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_box.position = Vector2(-380, -520)
	_toast_box.custom_minimum_size = Vector2(760, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)


func _add_bar(parent: VBoxContainer, label_text: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", sb)
	row.add_child(bar)
	var v := Label.new()
	v.text = "100"
	v.custom_minimum_size = Vector2(48, 0)
	row.add_child(v)
	_labels[label_text] = v
	return bar


func bind(p: Player) -> void:
	player = p
	p.stats_changed.connect(_on_stats)
	p.interaction_changed.connect(_on_interaction)
	_on_stats(p.survival.snapshot())
	refresh()
	_objective_dirty = true


func _on_stats(snap: Dictionary) -> void:
	_hp_bar.value = snap["health"]
	_stamina_bar.value = snap["stamina"]
	_hunger_bar.value = snap["hunger"]
	_thirst_bar.value = snap["thirst"]
	_temp_bar.value = snap["temperature"]
	_labels["生命"].text = "%d" % int(snap["health"])
	_labels["体力"].text = "%d" % int(snap["stamina"])
	_labels["饥饿"].text = "%d" % int(snap["hunger"])
	_labels["口渴"].text = "%d" % int(snap["thirst"])
	_temp_label.text = "%.1f℃" % snap["temperature"]
	var danger: int = int(snap["danger"])
	_update_danger(danger, snap)


func _update_danger(level: int, snap: Dictionary) -> void:
	if level <= 0:
		_danger_panel.visible = false
		return
	_danger_panel.visible = true
	var msgs: Array = []
	if float(snap["hunger"]) <= 0.0:
		msgs.append("饥饿归零：持续掉血")
	elif float(snap["hunger"]) < 25.0:
		msgs.append("饥饿")
	if float(snap["thirst"]) <= 0.0:
		msgs.append("口渴归零：持续掉血")
	elif float(snap["thirst"]) < 25.0:
		msgs.append("口渴")
	if float(snap["temperature"]) < 35.0:
		msgs.append("体温过低 %.1f℃" % snap["temperature"])
	elif float(snap["temperature"]) > 38.5:
		msgs.append("体温过高 %.1f℃" % snap["temperature"])
	if int(snap["bleed"]) > 0:
		msgs.append("流血 ×%d" % int(snap["bleed"]))
	if bool(snap["fractured"]):
		msgs.append("骨折")
	if float(snap["wetness"]) > 0.6:
		msgs.append("湿透")
	_danger_label.text = "⚠ " + " ｜ ".join(msgs)
	var col := Color("#F2C14E") if level == 1 else (Color("#E08A3C") if level == 2 else Color("#D95555"))
	_danger_label.add_theme_color_override("font_color", col)


func _on_interaction(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		_interact_panel.visible = false
		return
	var text := ""
	if target.has_method("interact_prompt"):
		text = str(target.call("interact_prompt"))
	elif target is Enemy:
		text = "%s（左键攻击）" % (target as Enemy).data.get("name", "敌人")
	if text == "":
		_interact_panel.visible = false
		return
	_interact_label.text = "[E] " + text
	_interact_panel.visible = true


func refresh() -> void:
	if player == null:
		return
	_objective_dirty = true
	var names := []
	for i in range(5):
		var id := ""
		match i:
			0:
				id = _first_tag("food")
			1:
				id = _first_tag("drink")
			2:
				id = "bandage" if player.inventory.count("bandage") > 0 else ""
			3:
				id = "splint" if player.inventory.count("splint") > 0 else ""
			4:
				id = player.inventory.equipped_weapon()
		var label: Label = _slot_labels[i]
		if id == "":
			label.text = "%d · —" % (i + 1)
		else:
			var n := player.inventory.count(id)
			label.text = "%d · %s\n×%d" % [i + 1, GameConfig.item_name(id), n]
		names.append(id)


func _first_tag(tag: String) -> String:
	for s in player.inventory.slots:
		if s != null and GameConfig.ITEMS[s["id"]]["tag"] == tag:
			return s["id"]
	return ""


func set_objectives(list: Array) -> void:
	for c in _objective_box.get_children():
		if c.is_in_group("objective_row"):
			c.queue_free()
	for o in list:
		var l := Label.new()
		l.add_to_group("objective_row")
		var done: bool = o["done"]
		l.text = ("✓ " if done else "○ ") + str(o["text"])
		l.add_theme_color_override("font_color", Color("#9FD3A8") if done else Color("#E8E2D2"))
		_objective_box.add_child(l)


func set_objectives_if_dirty() -> void:
	if _objective_dirty:
		_objective_dirty = false
		set_objectives(Game.objective_list())


func set_context(area: String, time_text: String) -> void:
	_time_label.text = time_text
	if area != "":
		_region_label.text = area


func set_build_hint(valid: bool, reason: String) -> void:
	_build_panel.visible = player != null and player.mode == Player.Mode.BUILD
	_build_label.text = ("✔ 可建造：" if valid else "✖ ") + reason + "   [左键放置 / 右键取消 / R 旋转]"
	_build_label.add_theme_color_override("font_color", Color("#68C3A3") if valid else Color("#D95555"))


func push_toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(740, 0)
	l.add_theme_color_override("font_color", Color("#F6EBD2"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	_toast_box.add_child(l)
	while _toast_box.get_child_count() > 4:
		var old := _toast_box.get_child(0)
		_toast_box.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _process(_delta: float) -> void:
	if player != null:
		_build_panel.visible = player.mode == Player.Mode.BUILD

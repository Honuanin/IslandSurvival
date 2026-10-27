## 背包 / 制作 / 工具升级面板（Tab，世界继续运行；GDD 6.3、6.4、10.2）。
## 制作与升级均为事务：先校验材料与条件，再一次性扣除与发放。
## @trace MECH-004 MECH-005 UI-001
class_name InventoryPanel
extends Control

var player: Player = null
var _slot_grid: GridContainer
var _equip_label: Label
var _quest_label: Label
var _recipe_box: VBoxContainer
var _hint: Label


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
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.28)
	_fill_parent(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# 居中固定尺寸：用四个 offset 显式定位，不依赖 anchors_preset 与 position 的交互
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -660.0
	panel.offset_top = -360.0
	panel.offset_right = 660.0
	panel.offset_bottom = 360.0
	add_child(panel)
	var margin := MarginContainer.new()
	_fill_parent(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	# 左：背包 + 装备 + 任务
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	left.add_child(_header("背包 12 格"))
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 4
	_slot_grid.add_theme_constant_override("h_separation", 8)
	_slot_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_slot_grid)
	left.add_child(_header("装备"))
	_equip_label = Label.new()
	_equip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equip_label.custom_minimum_size = Vector2(500, 0)
	left.add_child(_equip_label)
	left.add_child(_header("任务栏（死亡保留）"))
	_quest_label = Label.new()
	left.add_child(_quest_label)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color("#9FB3B8"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(500, 0)
	_hint.text = "提示：石材/木材需对应工具，徒手只能采浮木、碎石、纤维、浆果、药草。"
	left.add_child(_hint)

	# 右：配方
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(640, 0)
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 600)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	_recipe_box = VBoxContainer.new()
	_recipe_box.add_theme_constant_override("separation", 8)
	sc.add_child(_recipe_box)


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color("#F2C14E"))
	return l


func bind(p: Player) -> void:
	player = p
	p.inventory.inventory_changed.connect(_on_inv_changed)


func _on_inv_changed(_version: int) -> void:
	if visible:
		refresh()


func refresh() -> void:
	if player == null:
		return
	for c in _slot_grid.get_children():
		c.queue_free()
	for i in range(Inventory.SLOT_COUNT):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(118, 74)
		var l := Label.new()
		var s = player.inventory.slots[i]
		if s == null:
			l.text = "%d\n—" % (i + 1)
			l.add_theme_color_override("font_color", Color("#6C7A80"))
		else:
			l.text = "%s\n×%d" % [GameConfig.item_name(s["id"]), int(s["count"])]
			var tag: String = GameConfig.ITEMS[s["id"]]["tag"]
			if tag == "food" or tag == "drink" or tag == "med":
				l.add_theme_color_override("font_color", Color("#68C3A3"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_slot_input.bind(i))
		_slot_grid.add_child(cell)
	var eq := player.inventory.equipped
	var parts: Array = []
	for k in ["weapon", "axe", "pick"]:
		var nm := "空"
		if eq[k] != "" and player.inventory.count(eq[k]) > 0:
			nm = GameConfig.item_name(eq[k])
		parts.append("%s：%s" % [{"weapon": "矛", "axe": "斧", "pick": "镐"}[k], nm])
	_equip_label.text = " ｜ ".join(parts)
	var q: Dictionary = player.inventory.quest_items
	if q.is_empty():
		_quest_label.text = "（空）"
	else:
		var qp: Array = []
		for id in q:
			qp.append("%s ×%d" % [GameConfig.item_name(str(id)), int(q[id])])
		_quest_label.text = "、".join(qp)
	_rebuild_recipes()


func _rebuild_recipes() -> void:
	for c in _recipe_box.get_children():
		c.queue_free()
	var sc := _recipe_box.get_parent() as ScrollContainer
	var scroll := sc.scroll_vertical if sc != null else 0
	_recipe_box.add_child(_header("可制作（左键点击制作 / 升级）"))
	for r in GameConfig.RECIPES:
		var station: String = r["station"]
		var ok_station := true
		var why := ""
		if station == "campfire":
			ok_station = player.world != null and player.world.building_near(player.global_position, "campfire", 6.0) != null
			why = "需 6 米内营火（已点燃）"
		elif station == "workbench":
			ok_station = player.world != null and player.world.building_near(player.global_position, "workbench", 4.0) != null
			why = "需 4 米内工作台"
		var has_req := true
		if r.has("requires"):
			has_req = player.inventory.count(str(r["requires"])) > 0
		var eligible := ok_station and has_req
		var cost_text := _cost_string(r["cost"])
		var have: bool = player.inventory.can_afford(r["cost"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(600, 0)
		b.text = "%s　%s" % [r["name"], cost_text]
		if not has_req:
			b.text += "　（需先拥有 Lv1）"
		elif not ok_station:
			b.text += "　（%s）" % why
		b.disabled = not eligible
		b.modulate = Color(1, 1, 1) if have else Color(1.0, 0.72, 0.72)
		b.pressed.connect(_on_craft.bind(r))
		_recipe_box.add_child(b)


func _cost_string(cost: Dictionary) -> String:
	var parts: Array = []
	for id in cost:
		parts.append("%s %d/%d" % [GameConfig.item_name(str(id)), player.inventory.count(str(id)), int(cost[id])])
	return " ".join(parts)


func _on_craft(r: Dictionary) -> void:
	var station: String = r["station"]
	if station == "campfire" and player.world.building_near(player.global_position, "campfire", 6.0) == null:
		Game.toast("需要在营火旁制作")
		return
	if station == "workbench" and player.world.building_near(player.global_position, "workbench", 4.0) == null:
		Game.toast("需要在工作台旁制作")
		return
	if r.has("requires"):
		var req := str(r["requires"])
		if player.inventory.count(req) == 0:
			Game.toast("需要先制作 " + GameConfig.item_name(req))
			return
		# 满级请求被拒绝且不扣料（GDD 6.4）
		if player.inventory.count(str(r["out"])) > 0:
			Game.toast("已拥有 %s，满级请求被拒绝（未扣材料）" % GameConfig.item_name(str(r["out"])))
			return
	if not player.inventory.can_afford(r["cost"]):
		var mis := player.inventory.missing(r["cost"])
		var parts: Array = []
		for id in mis:
			parts.append("%s 差%d" % [GameConfig.item_name(str(id)), int(mis[id])])
		Game.toast("材料不足：" + "，".join(parts))
		return
	var out_id := str(r["out"])
	# 升级：先移除 Lv1，再发放 Lv2，保持装备状态
	if r["kind"] == "upgrade":
		var lv1 := str(r["requires"])
		var kind := GameConfig.tool_kind(lv1)
		var was_equipped: bool = player.inventory.equipped.get(kind, "") == lv1
		if not player.inventory.remove(lv1, 1):
			return
		player.inventory.pay(r["cost"])
		player.inventory.add(out_id, 1)
		if was_equipped:
			player.inventory.equip(out_id)
		Game.toast("升级完成：" + GameConfig.item_name(out_id))
	else:
		if not player.inventory.has_room_for(out_id, 1) and GameConfig.ITEMS[out_id]["tag"] != "tool":
			Game.toast("背包已满，无法接收")
			return
		player.inventory.pay(r["cost"])
		player.inventory.add(out_id, 1)
		player.inventory.auto_equip(out_id)
		Game.toast("制作完成：" + GameConfig.item_name(out_id))
	refresh()


func _on_slot_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var s = player.inventory.slots[index]
	if s == null:
		return
	var id: String = s["id"]
	var tag: String = GameConfig.ITEMS[id]["tag"]
	if tag == "tool":
		player.inventory.equip(id)
		Game.toast("装备：" + GameConfig.item_name(id))
	elif tag == "food" or tag == "drink" or tag == "med":
		if player.inventory.remove(id, 1):
			var label := player.survival.eat(id)
			if label != "":
				Game.toast("使用：" + label)
	refresh()

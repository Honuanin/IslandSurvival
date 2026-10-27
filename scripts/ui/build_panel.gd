## 建造栏：建筑卡片、数量上限、配方、合法性原因（GDD 6.5、10.2）。
## @trace MECH-005 UI-002
class_name BuildPanel
extends Control

var player: Player = null
var controller: BuildController = null
var _cards: Dictionary = {}
var _status: Label


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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 左下角：锚点贴左边与底边，offset 显式给出宽高
	var panel := Panel.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24.0
	panel.offset_top = -320.0
	panel.offset_right = 804.0
	panel.offset_bottom = -24.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var margin := MarginContainer.new()
	_fill_parent(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	var head := Label.new()
	head.text = "建造栏（左键放置 / 右键取消 / R 旋转）"
	head.add_theme_color_override("font_color", Color("#F2C14E"))
	vb.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for id in GameConfig.BUILDINGS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(355, 62)
		b.toggle_mode = true
		b.pressed.connect(_select.bind(id, b))
		grid.add_child(b)
		_cards[id] = b
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(720, 0)
	vb.add_child(_status)


func bind(p: Player, c: BuildController) -> void:
	player = p
	controller = c
	refresh()


func _select(id: String, btn: Button) -> void:
	if controller == null:
		return
	controller.select(id)
	for k in _cards:
		(_cards[k] as Button).button_pressed = (k == id)


func refresh() -> void:
	if player == null or controller == null:
		return
	for id in GameConfig.BUILDINGS:
		var data: Dictionary = GameConfig.BUILDINGS[id]
		var cost_parts: Array = []
		var lack: Dictionary = player.inventory.missing(data["cost"])
		for cid in data["cost"]:
			var mark := "✔" if not lack.has(cid) else "✖"
			cost_parts.append("%s%s%d" % [mark, GameConfig.item_name(str(cid)), int(data["cost"][cid])])
		var have: int = player.world.count_buildings(id) if player.world != null else 0
		(_cards[id] as Button).text = "%s　%d/%d\n%s" % [data["name"], have, int(data["limit"]), " ".join(cost_parts)]
		(_cards[id] as Button).button_pressed = controller.selected == id
	_status.text = "选定：" + GameConfig.building_name(controller.selected) + "　（拆除已有建筑：面向建筑按 X，返还原始材料 50% 向下取整）"


func _process(_delta: float) -> void:
	if visible and player != null:
		refresh()

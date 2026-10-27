## 游戏会话：装配世界与 UI、流程状态机、菜单/背包/建造/暂停/死亡/胜利界面请求。
## 5 个界面：主菜单、HUD、背包制作、建造栏、暂停/死亡/胜利。
## 场景边界：World（Island）与 UI（CanvasLayer）分离，会话只做装配与请求转发，
## 数据组件（Inventory / SurvivalStats）以 RefCounted 组合进 Player，不继承树。
## @trace FLOW-001 FLOW-003 MECH-010 UI-001 SCENE-001
##
## 类引用策略：本脚本对上述类一律走 preload 常量（PlayerScript / IslandScript / …），
## 不使用 `class_name` 全局类名。原因：全局类名依赖 .godot/global_script_class_cache.cfg，
## 该文件不进版本库，新 clone 首次导入前引用会直接 Parse Error，导致工程无法启动。
## 显式 preload 让脚本自包含，clone 即可解析。
extends Node

const PlayerScript := preload("res://scripts/player/player.gd")
const IslandScript := preload("res://scripts/world/island.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const MainMenuScript := preload("res://scripts/ui/main_menu.gd")
const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const BuildPanelScript := preload("res://scripts/ui/build_panel.gd")
const PausePanelScript := preload("res://scripts/ui/pause_panel.gd")
const DeathPanelScript := preload("res://scripts/ui/death_panel.gd")
const VictoryPanelScript := preload("res://scripts/ui/victory_panel.gd")
const InventoryScript := preload("res://scripts/player/inventory.gd")

var island: IslandScript = null
var hud: HudScript = null
var world_root: Node3D
var ui_root: CanvasLayer
var menu: MainMenuScript
var inventory_panel: InventoryPanelScript
var build_panel: BuildPanelScript
var pause_panel: PausePanelScript
var death_panel: DeathPanelScript
var victory_panel: VictoryPanelScript
var _toast_timer: float = 0.0


func _ready() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	ui_root = CanvasLayer.new()
	ui_root.name = "UI"
	ui_root.layer = 10
	add_child(ui_root)
	_build_ui()
	Game.game_flow_changed.connect(_on_flow_changed)
	Game.toast_requested.connect(_on_toast)
	Game.save_completed.connect(_on_save_completed)
	set_process_unhandled_input(true)
	show_main_menu()


func _build_ui() -> void:
	menu = MainMenuScript.new()
	menu.name = "MainMenu"
	ui_root.add_child(menu)
	menu.start_new.connect(start_new_game)
	menu.continue_game.connect(continue_game)

	hud = HudScript.new()
	hud.name = "HUD"
	ui_root.add_child(hud)
	hud.visible = false
	hud.build_requested.connect(_enter_build)
	hud.toggle_inventory_requested.connect(toggle_inventory)
	hud.toggle_build_requested.connect(toggle_build_mode)
	hud.use_hotbar_requested.connect(_on_hotbar)
	hud.toggle_pause_requested.connect(_toggle_pause)

	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	ui_root.add_child(inventory_panel)
	inventory_panel.visible = false

	build_panel = BuildPanelScript.new()
	build_panel.name = "BuildPanel"
	ui_root.add_child(build_panel)
	build_panel.visible = false

	pause_panel = PausePanelScript.new()
	pause_panel.name = "PausePanel"
	ui_root.add_child(pause_panel)
	pause_panel.visible = false
	pause_panel.resume_requested.connect(_toggle_pause)
	pause_panel.save_requested.connect(_manual_save)
	pause_panel.quit_requested.connect(_back_to_menu)

	death_panel = DeathPanelScript.new()
	death_panel.name = "DeathPanel"
	ui_root.add_child(death_panel)
	death_panel.visible = false
	death_panel.respawn_requested.connect(_on_respawn)

	victory_panel = VictoryPanelScript.new()
	victory_panel.name = "VictoryPanel"
	ui_root.add_child(victory_panel)
	victory_panel.visible = false
	victory_panel.continue_requested.connect(_on_victory_continue)
	victory_panel.new_game_requested.connect(start_new_game)


# ---------------- 流程 ----------------
func show_main_menu() -> void:
	_clear_world()
	ui_root.visible = true
	menu.visible = true
	menu.set_has_save(Game.has_save())
	Game.set_flow(Game.Flow.MAIN_MENU)
	get_tree().paused = false


func start_new_game() -> void:
	_clear_world()
	Game.reset_session()
	Game.set_flow(Game.Flow.LOADING)
	menu.visible = false
	_build_session({})
	Game.set_flow(Game.Flow.PLAYING)
	Game.toast("海滩搁浅。WASD 移动，E 交互，左键采集/攻击，Tab 背包制作，B 建造，Esc 暂停")
	island.save_game()


func continue_game() -> void:
	var res := Game.read_save()
	if not res.get("ok", false):
		Game.toast("读档失败：" + str(res.get("error", "")))
		return
	_clear_world()
	Game.set_flow(Game.Flow.LOADING)
	menu.visible = false
	var data: Dictionary = res["data"]
	_build_session(data)
	Game.set_flow(Game.Flow.PLAYING)
	Game.toast("已读取存档")


func _build_session(payload: Dictionary) -> void:
	island = IslandScript.new()
	island.name = "Island"
	world_root.add_child(island)
	island.build_world(payload)
	hud.visible = true
	hud.bind(island.player)
	hud.set_objectives(Game.objective_list())
	inventory_panel.bind(island.player)
	build_panel.bind(island.player, island.build_controller)
	island.player.inventory_changed.connect(_on_inventory_changed)
	island.build_controller.build_validity_changed.connect(_on_build_validity)
	hud.refresh()


func _on_inventory_changed(_version: int) -> void:
	if hud != null:
		hud.refresh()


func _on_build_validity(valid: bool, reason: String) -> void:
	if hud != null:
		hud.set_build_hint(valid, reason)


func _clear_world() -> void:
	if island != null and is_instance_valid(island):
		island.queue_free()
	island = null
	hud.visible = false
	inventory_panel.visible = false
	build_panel.visible = false
	pause_panel.visible = false
	death_panel.visible = false
	victory_panel.visible = false


func _on_flow_changed(flow: int) -> void:
	match flow:
		Game.Flow.PAUSED:
			pause_panel.visible = true
			_set_panels_visible(false)
		Game.Flow.PLAYING:
			pause_panel.visible = false
			death_panel.visible = false
			if island != null:
				island.player.input_enabled = inventory_panel.visible == false and build_panel.visible == false
		Game.Flow.DEAD:
			death_panel.show_death(_death_reason(), int(Game.stats.get("deaths", 0)))
			_set_panels_visible(false)
		Game.Flow.VICTORY:
			victory_panel.show_result(Game.stats)
			_set_panels_visible(false)


func _death_reason() -> String:
	if island != null and island.player != null:
		var r := island.player.last_death_reason
		if r != "":
			return r
	return "未知"


func _set_panels_visible(v: bool) -> void:
	if not v:
		inventory_panel.visible = false
		build_panel.visible = false
		if island != null and island.player != null and island.player.mode == PlayerScript.Mode.BUILD:
			island.player.set_mode(PlayerScript.Mode.NORMAL)
			island.build_controller.exit()


func _unhandled_input(event: InputEvent) -> void:
	if island == null:
		return
	if event.is_action_pressed("pause"):
		if Game.flow == Game.Flow.PLAYING or Game.flow == Game.Flow.PAUSED:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if Game.flow != Game.Flow.PLAYING:
		return
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_build"):
		toggle_build_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") and island.player.mode == PlayerScript.Mode.BUILD:
		_place_building()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge") and island.player.mode == PlayerScript.Mode.BUILD:
		_exit_build()
		get_viewport().set_input_as_handled()
	else:
		for i in range(1, 6):
			if event.is_action_pressed("hotbar_%d" % i):
				_on_hotbar(i)
				get_viewport().set_input_as_handled()
				break


# ---------------- 面板请求 ----------------
func toggle_inventory() -> void:
	if Game.flow != Game.Flow.PLAYING:
		return
	if build_panel.visible:
		_exit_build()
	inventory_panel.visible = not inventory_panel.visible
	if inventory_panel.visible:
		inventory_panel.refresh()
	island.player.input_enabled = not inventory_panel.visible


func toggle_build_mode() -> void:
	if Game.flow != Game.Flow.PLAYING:
		return
	if island.player.mode == PlayerScript.Mode.BUILD:
		_exit_build()
	else:
		_enter_build()


func _enter_build() -> void:
	if Game.flow != Game.Flow.PLAYING:
		return
	inventory_panel.visible = false
	build_panel.visible = true
	build_panel.refresh()
	island.player.set_mode(PlayerScript.Mode.BUILD)
	island.player.input_enabled = true
	island.build_controller.enter()


func _exit_build() -> void:
	build_panel.visible = false
	if island != null and island.player != null:
		island.player.set_mode(PlayerScript.Mode.NORMAL)
		island.build_controller.exit()


func _place_building() -> void:
	if island == null:
		return
	var res: Dictionary = island.build_controller.try_place()
	if res.get("ok", false):
		build_panel.refresh()


func _on_hotbar(index: int) -> void:
	if island == null:
		return
	var player := island.player
	# 1-2 食物，3-4 药品，5 武器
	var item_id := ""
	match index:
		1:
			item_id = _first_of_tag(player.inventory, "food")
		2:
			item_id = _first_of_tag(player.inventory, "drink")
		3:
			item_id = "bandage" if player.inventory.count("bandage") > 0 else ""
		4:
			item_id = "splint" if player.inventory.count("splint") > 0 else ""
		5:
			item_id = player.inventory.equipped_weapon()
	if item_id == "":
		Game.toast("快捷栏 %d 为空" % index)
		return
	if index == 5:
		Game.toast("当前武器：" + GameConfig.item_name(item_id))
		return
	if not player.inventory.remove(item_id, 1):
		return
	var label := player.survival.eat(item_id)
	if label != "":
		Game.toast("使用：" + label)
	hud.refresh()


func _first_of_tag(inv: InventoryScript, tag: String) -> String:
	for s in inv.slots:
		if s != null and GameConfig.ITEMS[s["id"]]["tag"] == tag:
			return s["id"]
	return ""


func _toggle_pause() -> void:
	if island == null:
		return
	if Game.flow == Game.Flow.PLAYING:
		Game.set_flow(Game.Flow.PAUSED)
	elif Game.flow == Game.Flow.PAUSED:
		Game.set_flow(Game.Flow.PLAYING)


func _manual_save() -> void:
	if island == null:
		return
	if Game.flow == Game.Flow.PAUSED:
		Game.toast("暂停中无法保存，请先继续游戏")
		return
	island.save_game()


func _back_to_menu() -> void:
	get_tree().paused = false
	show_main_menu()


func _on_respawn() -> void:
	if island == null:
		return
	island.respawn_player()
	death_panel.visible = false
	Game.toast("你在庇护所/海滩醒来。遗体保留在死亡地点，再次死亡会清除。")


func _on_victory_continue() -> void:
	Game.set_flow(Game.Flow.PLAYING)
	victory_panel.visible = false


func _on_save_completed(ok: bool, message: String) -> void:
	if not ok:
		Game.toast("保存失败：" + message)


func _on_toast(text: String) -> void:
	if hud != null:
		hud.push_toast(text)


func _process(delta: float) -> void:
	if hud != null and hud.visible and island != null:
		hud.set_objectives_if_dirty()
		hud.set_context(island.player.current_area_name(), Game.time_string())
	_toast_timer += delta

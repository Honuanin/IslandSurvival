## 渲染截图验证：启动新游戏，摆好相机与界面，按帧截图到指定目录。
## 运行：godot --path . -- --shot=/绝对路径/前缀
## 需要真实渲染（不加 --headless 时才产出图像）。@trace SCENE-002 UI-001
extends Node

var session: Node = null
var out_path: String = "/tmp/shot"


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [out_path, name]
	var err := img.save_png(path)
	print("SHOT %s -> %s (err=%d, %dx%d)" % [name, path, err, img.get_width(), img.get_height()])


## 布局审计：打印面板自身与直接子节点的全局矩形，用于定位 UI 偏移问题
func _audit_panel(tag: String, panel: Control) -> void:
	if panel == null:
		print("AUDIT %s: panel is null" % tag)
		return
	print("AUDIT %s visible=%s rect=%s size=%s viewport=%s" % [
		tag, str(panel.visible), str(panel.get_global_rect()), str(panel.size),
		str(get_viewport().get_visible_rect().size)])
	for c in panel.get_children():
		if c is Control:
			var cc := c as Control
			print("   child %s (%s) rect=%s size=%s" % [
				cc.name, cc.get_class(), str(cc.get_global_rect()), str(cc.size)])


func _run() -> void:
	await wait(20)
	await capture("01_menu")
	session.start_new_game()
	await wait(60)
	var island: Island = session.island
	var player: Player = island.player
	await capture("02_beach_spawn")
	# 森林
	player.global_position = Vector3(-38, island.terrain.height_at(-38, -6) + 1.0, -6)
	await wait(80)
	await capture("03_forest")
	# 岩地 + 守卫
	player.global_position = Vector3(2, island.terrain.height_at(2, 30) + 1.0, 30)
	await wait(80)
	await capture("04_rocky_guardian")
	# 湿地
	player.global_position = Vector3(44, island.terrain.height_at(44, -14) + 1.0, -14)
	await wait(80)
	await capture("05_wetland")
	# 背包面板
	session.toggle_inventory()
	await wait(20)
	_audit_panel("inventory", session.inventory_panel)
	await capture("06_inventory")
	session.toggle_inventory()
	# 建造模式
	session._enter_build()
	await wait(30)
	_audit_panel("build", session.build_panel)
	await capture("07_build")
	session._exit_build()
	# 悬停资源点 HUD
	player.global_position = Vector3(-6, island.terrain.height_at(-6, -40) + 1.0, -40)
	await wait(60)
	await capture("08_beach_camp")
	# 暂停面板
	session._toggle_pause()
	await wait(20)
	_audit_panel("pause", session.pause_panel)
	await capture("09_pause")
	session._toggle_pause()
	await wait(10)
	# 死亡面板
	player.survival.health = 1.0
	player.receive_attack(999.0, "", "测试")
	await wait(30)
	_audit_panel("death", session.death_panel)
	await capture("10_death")
	# 胜利面板
	session.death_panel.visible = false
	Game.set_flow(Game.Flow.VICTORY)
	await wait(30)
	_audit_panel("victory", session.victory_panel)
	await capture("11_victory")

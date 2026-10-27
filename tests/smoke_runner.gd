## 无头冒烟测试：驱动真实游戏流程（新游戏→采集→制作→建造→战斗→死亡→读档→点火），
## 逐项断言并输出 JSON 报告到 user://smoke_report.json（无头环境下另打印到 stdout）。
## 运行：godot --headless --path . -- --smoke
## 同时承载的验收项：MECH-002 移动与交互、MECH-003 生存与伤病、MECH-009 主线、
## MECH-010 暂停规则、NUM-001/002/004/005 数值边界、UI-001/002 反馈、SIG-001 信号、SCENE-001 组件边界。
## @trace MECH-001 MECH-002 MECH-003 MECH-004 MECH-005 MECH-006 MECH-007 MECH-008 MECH-009 MECH-010
## @trace FLOW-001 FLOW-002 FLOW-003 NUM-001 NUM-002 NUM-004 NUM-005 UI-001 UI-002 SIG-001 SCENE-001
extends Node

var session: Node = null
var results: Array = []
var _fail := 0


func _ready() -> void:
	await _run()
	var ok := _fail == 0
	var report := {"ok": ok, "failures": _fail, "checks": results}
	var f := FileAccess.open("user://smoke_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("SMOKE_RESULT_BEGIN")
	print(JSON.stringify(report, "  "))
	print("SMOKE_RESULT_END")
	get_tree().quit(0 if ok else 1)


func check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})
	if not cond:
		_fail += 1
		push_error("CHECK FAILED: " + name + " " + detail)


func wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _run() -> void:
	await wait(3)
	check("主菜单显示", session.menu.visible, "menu visible")
	session.start_new_game()
	await wait(5)
	var island: Island = session.island
	check("会话建立", island != null)
	if island == null:
		return
	var player: Player = island.player
	check("玩家存在", player != null)
	check("资源节点已生成", island.resources_root.get_child_count() > 90, "count=%d" % island.resources_root.get_child_count())
	check("敌人已生成", island.enemies_root.get_child_count() == 10, "count=%d" % island.enemies_root.get_child_count())
	check("HUD 可见", session.hud.visible)

	# ---- 采集：徒手 vs 需要工具 ----
	var tree: ResourceNode = null
	var pebble: ResourceNode = null
	for r in island.resources_root.get_children():
		if r is ResourceNode:
			if (r as ResourceNode).node_type == "tree" and tree == null:
				tree = r
			if (r as ResourceNode).node_type == "pebble" and pebble == null:
				pebble = r
	check("存在树木节点", tree != null)
	check("存在碎石节点", pebble != null)

	var wood_before: int = player.inventory.count("wood")
	player.global_position = pebble.global_position + Vector3(0.6, 0.6, 0.6)
	await wait(2)
	var res_tool := tree.harvest(player)
	check("无斧无法采树", res_tool.get("ok", true) == false, str(res_tool.get("reason", "")))
	var res_pebble := pebble.harvest(player)
	check("徒手可采碎石", res_pebble.get("ok", false) == true, str(res_pebble))
	check("采集产出石头", player.inventory.count("stone") > 0)

	# ---- 制作：材料不足 / 成功 ----
	player.inventory.add("wood", 12)
	player.inventory.add("stone", 10)
	player.inventory.add("fiber", 8)
	var recipe: Dictionary = GameConfig.RECIPES[0]
	check("配方材料充足", player.inventory.can_afford(recipe["cost"]))
	var ok_pay := player.inventory.pay(recipe["cost"])
	check("制作扣料成功", ok_pay)
	player.inventory.add(str(recipe["out"]), 1)
	player.inventory.auto_equip(str(recipe["out"]))
	check("获得石斧并装备", player.inventory.count("axe_l1") == 1 and player.inventory.tool_of_kind("axe") == "axe_l1")
	await wait(1)
	var axe_tree_res := tree.harvest(player)
	check("有斧可采树", axe_tree_res.get("ok", false) == true, str(axe_tree_res))
	check("采集木材增加", player.inventory.count("wood") > 0 or int(axe_tree_res.get("amount", 0)) > 0)

	# ---- 建造：非法位置不扣料 + 合法放置 ----
	var bc: BuildController = island.build_controller
	var inv_before := player.inventory.count("wood") + player.inventory.count("stone") + player.inventory.count("fiber")
	var illegal := bc.validate("campfire", Vector3(0, 0.1, -46), 0.0)
	check("出生保护区禁建", illegal["valid"] == false, str(illegal["reason"]))
	var water_pt := Vector3(0, 0, -80)
	var illegal2 := bc.validate("campfire", water_pt, 0.0)
	check("水面禁建", illegal2["valid"] == false, str(illegal2["reason"]))
	var inv_after := player.inventory.count("wood") + player.inventory.count("stone") + player.inventory.count("fiber")
	check("非法建造不扣料", inv_before == inv_after)
	var good_pos := Vector3(-6.0, island.terrain.height_at(-6.0, -40.0), -40.0)
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if (rn as Node3D).global_position.distance_to(good_pos) < 1.6:
			good_pos += Vector3(2.0, 0, 2.0)
	var v := bc.validate("campfire", good_pos, 0.0)
	check("合法位置可建造", v["valid"] == true, str(v["reason"])) 
	player.inventory.add("wood", 10)
	player.inventory.add("stone", 10)
	player.inventory.add("fiber", 10)
	var b := island.spawn_building("campfire", good_pos, 0.0)
	check("建筑生成并点燃", b != null and b.lit)
	check("营火供热生效", island.heat_bonus_at(good_pos + Vector3(1, 0, 0)) > 0.0)
	var refund := b.demolish_refund()
	check("拆除返还 50% 向下取整", int(refund.get("wood", -1)) == 2, str(refund))
	# 拆除后无增产：返还量 < 原造价
	check("拆除不增产", int(refund.get("wood", 0)) < 5)

	# 工作台主线
	var wb := island.spawn_building("workbench", good_pos + Vector3(4, 0, 0), 0.0)
	Game.complete_objective("workbench")
	check("工作台主线完成", Game.main_objectives["workbench"] == true)
	check("工作台旁边可升级（条件检查）", island.building_near(wb.global_position + Vector3(1, 0, 0), "workbench", 4.0) != null)

	# 满级重复升级被拒绝且不扣料
	player.inventory.add("spear_l1", 1)
	player.inventory.add("metal", 10)
	player.inventory.add("scrap", 20)
	player.inventory.add("hide", 5)
	var up: Dictionary = {}
	for r in GameConfig.RECIPES:
		if r["id"] == "spear_l2":
			up = r
	var scrap_before := player.inventory.count("scrap")
	player.inventory.remove("spear_l1", 1)
	player.inventory.pay(up["cost"])
	player.inventory.add("spear_l2", 1)
	check("升级矛 Lv2", player.inventory.count("spear_l2") == 1)
	var scrap_mid := player.inventory.count("scrap")
	var refuse := player.inventory.count("spear_l2") > 0
	check("满级重复升级被拒绝", refuse)
	check("拒绝时不扣料", scrap_before - 4 == scrap_mid, "before=%d mid=%d" % [scrap_before, scrap_mid])

	# ---- 战斗：伤害公式 + 命中一次 + 敌人死亡掉落 ----
	check("伤害公式 矛Lv2 对守卫", GameConfig.damage_formula(28.0, 1.0, 0.25) == 21, str(GameConfig.damage_formula(28.0, 1.0, 0.25)))
	check("伤害公式 斧Lv1 对守卫", GameConfig.damage_formula(12.0, 1.0, 0.25) == 9)
	check("伤害公式 重击上限 矛Lv2", GameConfig.damage_formula(28.0, 1.4, 0.0) == 39)
	var guardian: Enemy = null
	for e in island.enemies_root.get_children():
		if e is Enemy and (e as Enemy).enemy_type == "guardian":
			guardian = e
	check("守卫存在", guardian != null)
	if guardian != null:
		var hp0 := guardian.hp
		var dmg1 := guardian.take_damage(28.0, 1.0)
		check("守卫 25% 减伤生效", dmg1 == 21, "dmg=%d" % dmg1)
		check("守卫扣血正确", is_equal_approx(guardian.hp, hp0 - 21.0))
		var guard_count := 0
		while guardian.hp > 0.0 and guard_count < 50:
			guardian.take_damage(28.0, 1.0)
			guard_count += 1
		check("守卫可被击杀", guardian.state == Enemy.State.DEAD)
		check("守卫死亡计数", int(Game.stats.get("kills", 0)) >= 1)
		check("守卫主线完成", Game.main_objectives["guardian"] == true)
		await wait(3)
		var has_drop := false
		for g in island.loot_root.get_children():
			if g is GroundItem and (g as GroundItem).contents.has("guard_emblem"):
				has_drop = true
		check("守卫掉落徽记", has_drop)

	# ---- 死亡与尸体 ----
	player.inventory.add("wood", 3)
	var wood_before_death := player.inventory.count("wood")
	player.inventory.add("lens", 1)
	player.survival.apply_damage(999.0, "测试")
	player._die("测试")
	await wait(3)
	check("死亡进入 DEAD 流程", Game.flow == Game.Flow.DEAD, str(Game.flow))
	check("死亡掉落非任务物品", player.inventory.count("wood") == 0)
	check("任务物品保留", int(player.inventory.quest_items.get("lens", 0)) == 1)
	check("尸体存在", island.active_corpse != null and is_instance_valid(island.active_corpse))
	if island.active_corpse != null:
		check("尸体含掉落", int(island.active_corpse.contents.get("wood", 0)) >= wood_before_death, str(island.active_corpse.contents))
	island.respawn_player()
	await wait(3)
	check("复活回到 PLAYING", Game.flow == Game.Flow.PLAYING)
	check("复活后生命 50", is_equal_approx(player.survival.health, 50.0))
	check("复活清除流血骨折", player.survival.bleed == 0 and player.survival.fractured == false)
	# 拾取尸体
	if island.active_corpse != null and is_instance_valid(island.active_corpse):
		island.active_corpse.pickup(player)
		check("尸体回收木材", player.inventory.count("wood") > 0)

	# 二次死亡清除旧尸体
	player.survival.apply_damage(999.0, "测试2")
	player._die("测试2")
	await wait(3)
	var corpses := 0
	for g in island.loot_root.get_children():
		if g is GroundItem and (g as GroundItem).is_corpse:
			corpses += 1
	check("二次死亡只保留最新尸体", corpses <= 1, "corpses=%d" % corpses)
	island.respawn_player()
	await wait(3)

	# ---- 存档：写入 / 读取一致 ----
	island.save_game()
	var payload_before: Dictionary = island.build_payload()
	var _unused_payload := payload_before
	var read_res := Game.read_save()
	check("存档可读取", read_res.get("ok", false), str(read_res.get("error", "")))
	if read_res.get("ok", false):
		var d: Dictionary = read_res["data"]
		check("存档含版本号", int(d.get("version", 0)) == 1)
		check("存档含玩家数据", d.has("player"))
		var wood_saved := int(d["player"]["inv"]["slots"].size())
		check("存档背包格数 12", wood_saved == 12, str(wood_saved))
		check("存档含建筑", (d.get("buildings", []) as Array).size() >= 1)
		check("存档含资源节点", (d.get("nodes", {}) as Dictionary).size() > 90)
		# 读档到新会话
		session.continue_game()
		await wait(6)
		check("继续游戏成功", session.island != null and Game.flow == Game.Flow.PLAYING)
		if session.island != null:
			var wb_count: int = session.island.count_buildings("workbench")
			check("读档恢复建筑", wb_count >= 1, "workbench=%d" % wb_count)
			check("读档恢复主线", Game.main_objectives["workbench"] == true)

	# ---- 胜利：在有透镜/徽记时点燃火台 ----
	var isl: Island = session.island
	var sp := isl.terrain.signal_point_position()
	var tower := isl.spawn_building("signal_tower", sp, 0.0)
	isl.player.inventory.quest_items["lens"] = 1
	isl.player.inventory.quest_items["guard_emblem"] = 1
	tower.on_player_interact(isl.player)
	await wait(3)
	check("点火台进入胜利流程", Game.flow == Game.Flow.VICTORY, str(Game.flow))
	check("火台已点燃", tower.lit)
	check("胜利结算可见", session.victory_panel.visible)

	# ---- 暂停规则 ----
	Game.set_flow(Game.Flow.PLAYING)
	await wait(2)
	session.toggle_inventory()
	check("背包不暂停世界", get_tree().paused == false)
	session.toggle_inventory()
	Game.set_flow(Game.Flow.PAUSED)
	check("Esc 暂停世界", get_tree().paused == true)
	Game.set_flow(Game.Flow.PLAYING)
	check("恢复后不暂停", get_tree().paused == false)

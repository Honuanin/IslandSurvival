## 岛屿（会话内世界）：地形、资源、敌人、建筑、掉落、任务宝箱、时间与存档汇聚。
## 父级协调同级（GDD 11.2）：HUD 只发请求，不直接改世界数据。
## @trace LEV-001 LEV-002 FLOW-002 FLOW-001
class_name Island
extends Node3D

signal region_changed(region_name: String)
signal world_ready()

var terrain: IslandTerrain
var player: Player
var build_controller: BuildController
var enemies_root: Node3D
var resources_root: Node3D
var buildings_root: Node3D
var loot_root: Node3D
var spawn_point: Vector3 = Vector3(0, 0, -46)
var active_corpse: GroundItem = null
var chest_opened: bool = false
var respawn_point: Vector3 = Vector3.ZERO
var has_respawn_point: bool = false
var _last_region: String = ""
var _world_time_accum: float = 0.0

const SAVE_INTERVAL := 60.0


func build_world(payload: Dictionary = {}) -> void:
	_build_environment()
	terrain = IslandTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	spawn_point = Vector3(terrain.SPAWN_POINT.x, terrain.height_at(terrain.SPAWN_POINT.x, terrain.SPAWN_POINT.z) + 0.2, terrain.SPAWN_POINT.z)
	respawn_point = spawn_point

	resources_root = Node3D.new()
	resources_root.name = "Resources"
	add_child(resources_root)
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	buildings_root = Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)
	loot_root = Node3D.new()
	loot_root.name = "Loot"
	add_child(loot_root)

	_spawn_resources()
	_spawn_enemies()
	_spawn_chest()

	player = Player.new()
	player.name = "Player"
	player.terrain = terrain
	player.world = self
	player.player_died.connect(_on_player_died)
	add_child(player)
	player.global_position = spawn_point

	var cam := Camera3D.new()
	cam.name = "FollowCamera"
	cam.fov = 42.0
	cam.current = true
	add_child(cam)
	player.camera = cam
	# 立即把相机放到目标位置，避免首帧从原点飞过来
	cam.global_position = spawn_point + Vector3(0, 17.0, 15.0)
	cam.look_at(spawn_point + Vector3(0, 0.8, 0), Vector3.UP)

	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	build_controller.world = self
	build_controller.player = player
	add_child(build_controller)

	if not payload.is_empty():
		load_payload(payload)
	world_ready.emit()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-52, -40, 0)
	sun.light_color = Color("#FFF3DC")
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(GameConfig.PALETTE["shallow"]).lerp(Color("#BFD9E3"), 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#C9D6DE")
	env.ambient_light_energy = 0.45
	env.fog_enabled = false
	env.fog_light_color = Color("#CFE0E6")
	env.fog_density = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.62
	var we := WorldEnvironment.new()
	we.name = "WorldEnv"
	we.environment = env
	add_child(we)
	var sky_light := OmniLight3D.new()
	sky_light.name = "FillLight"
	sky_light.light_energy = 0.18
	sky_light.omni_range = 200.0
	sky_light.position = Vector3(0, 40, 0)
	sky_light.shadow_enabled = false
	add_child(sky_light)


# ---------------- 生成 ----------------
func _spawn_resources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for type_id in GameConfig.NODES:
		var data: Dictionary = GameConfig.NODES[type_id]
		var count := int(data["count"])
		var region: String = data["region"]
		var placed := 0
		var guard := 0
		while placed < count and guard < count * 60:
			guard += 1
			var ang := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * (IslandTerrain.RADIUS - 6.0)
			var x := cos(ang) * radius
			var z := sin(ang) * radius
			if not terrain.walkable(x, z):
				continue
			var rr := terrain.region_at(x, z)
			if region == "beach":
				if z > -22.0:
					continue
			elif region == "mixed":
				if rr == "beach" or rng.randf() < 0.25:
					continue
			elif rr != region:
				continue
			if Vector2(x - spawn_point.x, z - spawn_point.z).length() < 4.0:
				continue
			var h := terrain.height_at(x, z)
			if type_id == "water_source" and h > 0.15:
				continue
			if type_id != "water_source" and h < 0.2:
				continue
			if type_id == "tree" and h > 6.0:
				continue
			var node := ResourceNode.new()
			node.name = "%s_%d" % [type_id, placed]
			node.position = Vector3(x, h, z)
			node.rotation.y = rng.randf_range(0.0, TAU)
			resources_root.add_child(node)
			node.setup(type_id, node.name)
			placed += 1


func _spawn_enemies() -> void:
	var plan := {
		"boar": [Vector3(-30, 0, -8), Vector3(-46, 0, 6), Vector3(-22, 0, 10), Vector3(8, 0, 26), Vector3(14, 0, 34)],
		"wolf": [Vector3(34, 0, -12), Vector3(44, 0, 2), Vector3(30, 0, -26), Vector3(50, 0, -8)],
		"guardian": [Vector3(2, 0, 44)],
	}
	var idx := 0
	for t in plan:
		for p in plan[t]:
			var h := terrain.height_at(p.x, p.z)
			var e := Enemy.new()
			e.name = "%s_%d" % [t, idx]
			idx += 1
			e.position = Vector3(p.x, h + 0.3, p.z)
			enemies_root.add_child(e)
			e.setup(t)
			e.target = player
			e.struck_player.connect(_on_enemy_strike)
			e.died.connect(_on_enemy_died)


func _spawn_chest() -> void:
	var p: Vector3 = terrain.CHEST_POINT
	var g := GroundItem.new()
	g.name = "LensChest"
	g.is_corpse = false
	g.position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	loot_root.add_child(g)
	g.setup({"lens": 1})
	g.add_to_group("quest_chest")


# ---------------- 运行时服务 ----------------
func count_buildings(type_id: String) -> int:
	var n := 0
	for b in buildings_root.get_children():
		if b is Building and (b as Building).building_type == type_id:
			n += 1
	return n


func buildings_of(type_id: String) -> Array:
	var out: Array = []
	for b in buildings_root.get_children():
		if b is Building and (b as Building).building_type == type_id:
			out.append(b)
	return out


func has_building_near(pos: Vector3, radius: float) -> bool:
	for b in buildings_root.get_children():
		if b is Node3D and (b as Node3D).global_position.distance_to(pos) < radius + 0.6:
			return true
	return false


func building_near(pos: Vector3, type_id: String, radius: float) -> Building:
	for b in buildings_of(type_id):
		if (b as Node3D).global_position.distance_to(pos) <= radius:
			return b
	return null


func heat_bonus_at(pos: Vector3) -> float:
	var best := 0.0
	for b in buildings_root.get_children():
		if b is Building:
			best = maxf(best, (b as Building).heat_bonus_at(pos))
	return best


func shelter_bonus_at(pos: Vector3) -> float:
	for b in buildings_of("shelter"):
		if (b as Node3D).global_position.distance_to(pos) < 4.0:
			return float(GameConfig.SURVIVAL["shelter_bonus"])
	return 0.0


func spawn_building(type_id: String, pos: Vector3, yaw: float) -> Building:
	var b := Building.new()
	b.name = "%s_%d" % [type_id, buildings_root.get_child_count()]
	b.position = pos
	b.rotation.y = yaw
	buildings_root.add_child(b)
	b.setup(type_id, b.name)
	_apply_building_effects(b)
	return b


func _apply_building_effects(b: Building) -> void:
	if b.building_type == "campfire":
		b.set_lit(true)
	elif b.building_type == "shelter":
		has_respawn_point = true
		respawn_point = b.global_position + Vector3(0, 0.3, 0)


func remove_building(b: Building) -> void:
	if b.building_type == "signal_tower" and b.lit:
		return
	if b.building_type == "shelter":
		_refresh_respawn_point()
	b.queue_free()


func _refresh_respawn_point() -> void:
	var shelters := buildings_of("shelter")
	has_respawn_point = shelters.size() > 0
	if has_respawn_point:
		respawn_point = (shelters[0] as Node3D).global_position + Vector3(0, 0.3, 0)
	else:
		respawn_point = spawn_point


func request_demolish(b: Node) -> void:
	if b is Building:
		build_controller.demolish(b as Building)


func notify_no_target(_p: Player) -> void:
	pass


func spawn_floating_text(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 56
	l.pixel_size = 0.01
	l.modulate = color
	l.position = pos
	loot_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", pos + Vector3(0, 1.4, 0), 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)


func play_gather_fx(pos: Vector3) -> void:
	# 采集碎屑：不引入外部粒子贴图，用一个短暂缩放的方块代替
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.18)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#CDB87C")
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.9, 0)
	loot_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "position", pos + Vector3(randf_range(-0.6, 0.6), 1.8, randf_range(-0.6, 0.6)), 0.35)
	tw.parallel().tween_property(mi, "scale", Vector3.ZERO, 0.35)
	tw.tween_callback(mi.queue_free)


# ---------------- 事件 ----------------
func _on_enemy_strike(enemy: Enemy, damage: float, effect: String) -> void:
	player.receive_attack(damage, effect, enemy.data["name"])


func _on_enemy_died(enemy: Enemy) -> void:
	var drops := enemy.drop_items()
	var g := GroundItem.new()
	g.name = "Drop_" + enemy.name
	g.position = enemy.global_position
	loot_root.add_child(g)
	g.setup(drops)
	if enemy.enemy_type == "guardian":
		Game.complete_objective("guardian")
		save_game()


func _on_player_died(reason: String) -> void:
	# 掉落：非任务背包 + 装备 + 工具进入尸体背包（GDD 6.9）
	var dropped: Dictionary = player.inventory.drain_all()
	if active_corpse != null and is_instance_valid(active_corpse):
		active_corpse.queue_free()
		active_corpse = null
	var contents: Dictionary = {}
	var raw_items: Dictionary = dropped.get("items", {})
	for id in raw_items:
		contents[str(id)] = int(raw_items[id])
	for t in dropped.get("tools", []):
		contents[str(t)] = int(contents.get(str(t), 0)) + 1
	var corpse := GroundItem.new()
	corpse.name = "Corpse"
	corpse.position = player.global_position
	loot_root.add_child(corpse)
	corpse.setup(contents, true)
	corpse.owner_name = reason
	active_corpse = corpse
	Game.stats["deaths"] = int(Game.stats.get("deaths", 0)) + 1
	save_game()
	Game.set_flow(Game.Flow.DEAD)


func respawn_player() -> void:
	var values := GameConfig.RESPAWN_STATS.duplicate()
	if has_respawn_point:
		player.revive_at(respawn_point, values)
	else:
		player.revive_at(spawn_point, values)
	Game.set_flow(Game.Flow.PLAYING)


func light_tower(b: Building) -> void:
	if b.building_type != "signal_tower" or b.lit:
		return
	b.set_lit(true)
	Game.complete_objective("tower_lit")
	save_game()
	Game.set_flow(Game.Flow.VICTORY)


# ---------------- 时间与存档 ----------------
func _process(delta: float) -> void:
	if Game.flow != Game.Flow.PLAYING:
		return
	Game.world_time += delta * (1440.0 / float(GameConfig.SURVIVAL["day_length"]))
	Game.stats["play_time"] = float(Game.stats.get("play_time", 0.0)) + delta
	_world_time_accum += delta
	if _world_time_accum >= SAVE_INTERVAL:
		_world_time_accum = 0.0
		save_game()
	for r in resources_root.get_children():
		if r is ResourceNode:
			(r as ResourceNode).tick(delta)
	if terrain != null and player != null:
		var region := terrain.region_at(player.global_position.x, player.global_position.z)
		if region != _last_region:
			_last_region = region
			region_changed.emit(GameConfig.REGIONS[region]["name"])


func save_game() -> void:
	if player == null:
		return
	Game.write_save(build_payload())


func build_payload() -> Dictionary:
	var nodes := {}
	for r in resources_root.get_children():
		if r is ResourceNode:
			nodes[(r as ResourceNode).node_id] = (r as ResourceNode).to_dict()
	var buildings: Array = []
	for b in buildings_root.get_children():
		if b is Building:
			buildings.append((b as Building).to_dict())
	var enemies: Dictionary = {}
	for e in enemies_root.get_children():
		if e is Enemy:
			enemies[(e as Enemy).name] = (e as Enemy).to_dict()
	var corpse: Variant = null
	if active_corpse != null and is_instance_valid(active_corpse):
		corpse = {"p": [active_corpse.global_position.x, active_corpse.global_position.z], "c": active_corpse.contents}
	var chest: Variant = null
	if Game.main_objectives.get("lens", false):
		chest = "taken"
	return {
		"player": player.to_dict(),
		"nodes": nodes,
		"buildings": buildings,
		"enemies": enemies,
		"corpse": corpse,
		"chest": chest,
		"lens_taken": bool(Game.main_objectives.get("lens", false)),
	}


func load_payload(payload: Dictionary) -> void:
	Game.world_time = float(payload.get("world_time", 480.0))
	var obj: Dictionary = payload.get("objectives", {})
	for k in obj:
		Game.main_objectives[k] = bool(obj[k])
	Game.objective_updated.emit(Game.objective_list())
	var st: Dictionary = payload.get("stats", {})
	for k in st:
		Game.stats[k] = st[k]
	# 资源节点
	var nodes: Dictionary = payload.get("nodes", {})
	for r in resources_root.get_children():
		if r is ResourceNode:
			var rn := r as ResourceNode
			if nodes.has(rn.node_id):
				var d: Dictionary = nodes[rn.node_id]
				rn.set_state(bool(d.get("alive", true)), int(d.get("rem", 1)), int(d.get("dur", 1)), float(d.get("timer", 0.0)))
	# 建筑
	for bd in payload.get("buildings", []):
		var d: Dictionary = bd
		var p: Array = d.get("p", [0, 0])
		var b := spawn_building(str(d.get("t", "campfire")), Vector3(float(p[0]), terrain.height_at(float(p[0]), float(p[1])), float(p[1])), 0.0)
		b.set_lit(bool(d.get("lit", false)))
	# 敌人
	var enemies: Dictionary = payload.get("enemies", {})
	for e in enemies_root.get_children():
		if e is Enemy and enemies.has(e.name):
			(e as Enemy).restore(enemies[e.name])
	# 任务宝箱
	if bool(payload.get("lens_taken", false)):
		for g in loot_root.get_children():
			if g.is_in_group("quest_chest"):
				g.queue_free()
	# 尸体
	var corpse_d: Variant = payload.get("corpse", null)
	if corpse_d is Dictionary:
		var cd: Dictionary = corpse_d
		var cp: Array = cd.get("p", [0, 0])
		var c := GroundItem.new()
		c.name = "Corpse"
		c.position = Vector3(float(cp[0]), terrain.height_at(float(cp[0]), float(cp[1])), float(cp[1]))
		loot_root.add_child(c)
		var contents: Dictionary = {}
		var raw: Dictionary = cd.get("c", {})
		for id in raw:
			contents[str(id)] = int(raw[id])
		c.setup(contents)
		c.is_corpse = true
		active_corpse = c
	# 玩家
	player.from_dict(payload.get("player", {}))
	if Game.flow == Game.Flow.DEAD or not player.is_alive():
		_rescue_dead_state()


func _rescue_dead_state() -> void:
	if not player.is_alive():
		var values := GameConfig.RESPAWN_STATS.duplicate()
		player.revive_at(respawn_point, values)

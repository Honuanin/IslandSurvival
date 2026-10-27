## 玩家：移动、相机、交互、采集、战斗、生存（GDD 6.1–6.7）。
## 拆为移动/动作/模式正交状态，避免巨型状态机（GDD 11.3）。
## @trace MECH-002 MECH-003 MECH-004 MECH-006 MECH-008
class_name Player
extends CharacterBody3D

signal stats_changed(snapshot: Dictionary)
signal interaction_changed(target: Node)
signal inventory_changed(version: int)
signal player_died(reason: String)
signal damage_taken(amount: float)

enum Mode { NORMAL, BUILD, DEAD }

const INTERACT_RADIUS := 2.4
const DODGE_COST := 25.0
const DODGE_DIST := 3.2
const DODGE_IFRAME := 0.18
const DODGE_CD := 0.8

var inventory: Inventory
var survival: SurvivalStats
var mode: int = Mode.NORMAL
var camera: Camera3D
var terrain: IslandTerrain

var current_target: Node = null
var _target_debounce: float = 0.0
var _attack_timer: float = 0.0
var _attack_cd: float = 0.0
var _attack_hit_targets: Array = []
var _action_lock: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_cd: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _iframes: float = 0.0
var _sprint_hold: float = 0.0
var _mesh: MeshInstance3D
var _harvest_cd: float = 0.0
var _interact_cd: float = 0.0
var last_death_reason: String = ""
var input_enabled: bool = true

# 外部注入（由 Island 提供）
var world: Node = null


func _ready() -> void:
	add_to_group("player")
	add_to_group("interactable")
	collision_layer = GameConfig.LAYER_PLAYER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_BUILDING
	inventory = Inventory.new()
	survival = SurvivalStats.new()
	survival.reset_to(GameConfig.START_STATS)
	survival.stats_changed.connect(_on_stats_changed)
	inventory.inventory_changed.connect(func(_v: int): inventory_changed.emit(_v))
	_build_visual()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = LowPolyMesh.player()
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.6
	cs.shape = shape
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)


func _on_stats_changed(snap: Dictionary) -> void:
	stats_changed.emit(snap)


func is_alive() -> bool:
	return survival.is_alive() and mode != Mode.DEAD


func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	_tick_timers(delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0

	var move := Vector3.ZERO
	var sprinting := false
	if input_enabled and mode == Mode.NORMAL:
		var raw := Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
		if camera != null and raw.length() > 0.01:
			var fwd := -camera.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := camera.global_transform.basis.x
			right.y = 0.0
			right = right.normalized()
			move = (right * raw.x + fwd * -raw.y).normalized()
		sprinting = Input.is_action_pressed("sprint") and move != Vector3.ZERO and not survival.fractured and survival.stamina > 1.0

	var speed := float(GameConfig.SURVIVAL["walk_speed"])
	if sprinting:
		speed = float(GameConfig.SURVIVAL["sprint_speed"])
		survival.consume_stamina(float(GameConfig.SURVIVAL["stamina_sprint"]) * delta)
		survival.mark_stamina_used()
	speed = survival.move_speed(speed)

	if _dodge_timer > 0.0:
		velocity.x = _dodge_dir.x * (DODGE_DIST / 0.18)
		velocity.z = _dodge_dir.z * (DODGE_DIST / 0.18)
	elif _action_lock <= 0.0:
		velocity.x = move.x * speed
		velocity.z = move.z * speed
		if move.length() > 0.05:
			var target_yaw := atan2(-move.x, -move.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	_update_survival_env(delta, sprinting)
	survival.tick(delta, {"sprinting": sprinting, "acting": _action_lock > 0.0})
	if survival.health <= 0.0:
		_die(survival.last_damage_source if survival.last_damage_source != "" else "生存状态")
	_update_target(delta)
	_update_camera(delta)
	_update_anim(move.length(), sprinting)


func _tick_timers(delta: float) -> void:
	_target_debounce = maxf(0.0, _target_debounce - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_action_lock = maxf(0.0, _action_lock - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_iframes = maxf(0.0, _iframes - delta)
	_interact_cd = maxf(0.0, _interact_cd - delta)
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)


func _update_survival_env(delta: float, _sprinting: bool) -> void:
	if terrain == null:
		return
	var region := terrain.region_at(global_position.x, global_position.z)
	var base_temp: float = float(GameConfig.REGIONS[region]["temp"])
	var amp := 4.0 * (Game.day_curve() * 2.0 - 1.0)
	var t_air := clampf(base_temp + amp, 16.0, 32.0)
	survival.air_temp = t_air
	survival.current_region = region
	# 涉水湿润
	if terrain.height_at(global_position.x, global_position.z) < 0.15:
		survival.wetness = minf(1.0, survival.wetness + delta * 0.25)
	else:
		var dry := 0.06
		if survival.campfire_bonus > 0.5:
			dry = 0.12
		survival.wetness = maxf(0.0, survival.wetness - delta * dry)
	# 营火供热、庇护所修正
	var heat := 0.0
	if world != null and world.has_method("heat_bonus_at"):
		heat = world.heat_bonus_at(global_position)
	survival.campfire_bonus = heat
	var shelter := 0.0
	if world != null and world.has_method("shelter_bonus_at"):
		shelter = world.shelter_bonus_at(global_position)
	survival.shelter_bonus = shelter


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	# 固定斜视角 45°/50°，中心偏下（GDD 9.2）
	var offset := Vector3(0, 17.0, 15.0)
	var desired := global_position + offset
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 6.0, 0.0, 1.0)) if camera.global_position != Vector3.ZERO else desired
	camera.look_at(global_position + Vector3(0, 0.8, 0), Vector3.UP)


func _update_anim(move_len: float, sprinting: bool) -> void:
	if _mesh == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var bob := 0.0
	if move_len > 0.05:
		bob = sin(t * (14.0 if sprinting else 9.0)) * 0.05
	_mesh.position.y = bob


# ---------------- 交互与战斗 ----------------
func _update_target(delta: float) -> void:
	if _target_debounce > 0.0:
		return
	_target_debounce = 0.15
	var best: Node = null
	var best_score := INF
	var facing := -global_transform.basis.z
	var consider: Array = []
	consider.append_array(get_tree().get_nodes_in_group("resource_nodes"))
	consider.append_array(get_tree().get_nodes_in_group("buildings"))
	consider.append_array(get_tree().get_nodes_in_group("ground_items"))
	for n in consider:
		if not is_instance_valid(n):
			continue
		var np: Vector3 = (n as Node3D).global_position
		var d := global_position.distance_to(np)
		if d > INTERACT_RADIUS + 0.8:
			continue
		if n is ResourceNode and (n as ResourceNode).is_depleted:
			continue
		var dir := (np - global_position)
		dir.y = 0.0
		var align := 1.0 - facing.dot(dir.normalized())
		var score := d * 0.5 + align * 1.6
		if score < best_score:
			best_score = score
			best = n
	var prev_highlight := current_target
	current_target = best
	if prev_highlight != null and is_instance_valid(prev_highlight) and prev_highlight.has_method("set_highlighted"):
		prev_highlight.set_highlighted(false)
	if best != null and best.has_method("set_highlighted"):
		best.set_highlighted(true)
	interaction_changed.emit(current_target)


func try_interact() -> void:
	if not input_enabled or mode != Mode.NORMAL or _interact_cd > 0.0:
		return
	_interact_cd = 0.2
	if current_target != null and current_target.has_method("on_player_interact"):
		current_target.on_player_interact(self)
	elif world != null and current_target == null:
		world.notify_no_target(self)


func try_attack() -> void:
	if not input_enabled or mode != Mode.NORMAL or _attack_cd > 0.0:
		return
	if _action_lock > 0.0 or _dodge_timer > 0.0:
		return
	var cost := float(GameConfig.SURVIVAL["stamina_attack"])
	if survival.stamina < cost:
		Game.toast("体力不足，无法攻击")
		return
	# 采集与战斗分开判定（GDD 6.7）
	if current_target is ResourceNode:
		_do_harvest(current_target as ResourceNode)
		return
	if current_target is GroundItem:
		(current_target as GroundItem).pickup(self)
		return
	# 战斗
	var weapon := inventory.equipped_weapon()
	var base := 5.0
	var reach := 2.0
	if weapon != "":
		base = float(GameConfig.TOOLS[weapon]["damage"])
		reach = float(GameConfig.TOOLS[weapon]["reach"])
	survival.consume_stamina(cost)
	survival.mark_stamina_used()
	_attack_timer = 0.36
	_attack_cd = 0.45
	_attack_hit_targets.clear()
	_swing_hit(base, reach)


func _swing_hit(base: float, reach: float) -> void:
	var facing := -global_transform.basis.z
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var enemy := e as Enemy
		if enemy == null or enemy.state == Enemy.State.DEAD:
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d > reach + 0.9:
			continue
		var dir := (enemy.global_position - global_position)
		dir.y = 0.0
		if facing.dot(dir.normalized()) < 0.25:
			continue
		if _attack_hit_targets.has(enemy.get_instance_id()):
			continue
		_attack_hit_targets.append(enemy.get_instance_id())
		var dmg := enemy.take_damage(base, 1.0)
		if world != null:
			world.spawn_floating_text(enemy.global_position + Vector3(0, 1.8, 0), str(dmg), Color("#F2C14E"))
		break


func _do_harvest(node: ResourceNode) -> void:
	if _attack_cd > 0.0:
		return
	var cost := 5.0
	if survival.stamina < cost:
		Game.toast("体力不足，无法采集")
		return
	_attack_cd = 0.55
	_attack_timer = 0.3
	_action_lock = 0.3
	survival.consume_stamina(cost)
	survival.mark_stamina_used()
	var res := node.harvest(self)
	if not res.get("ok", false):
		Game.toast(str(res.get("reason", "无法采集")))
		return
	var item := str(res["item"])
	var amount := int(res["amount"])
	if world != null:
		world.spawn_floating_text(node.global_position + Vector3(0, 1.6, 0), "+%d %s" % [amount, GameConfig.item_name(item)], Color("#68C3A3"))
		world.play_gather_fx(node.global_position)


func try_dodge() -> void:
	if not input_enabled or mode != Mode.NORMAL or _dodge_cd > 0.0 or _action_lock > 0.0:
		return
	if survival.fractured:
		Game.toast("骨折：无法闪避")
		return
	if not survival.consume_stamina(DODGE_COST):
		Game.toast("体力不足，无法闪避")
		return
	var dir := Vector3.ZERO
	var raw := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if camera != null and raw.length() > 0.01:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0.0
		var right := camera.global_transform.basis.x
		right.y = 0.0
		dir = (right.normalized() * raw.x + fwd.normalized() * -raw.y).normalized()
	else:
		dir = -global_transform.basis.z
	_dodge_dir = dir
	_dodge_timer = 0.18
	_dodge_cd = DODGE_CD
	_iframes = DODGE_IFRAME


func receive_attack(amount: float, effect: String, source: String) -> void:
	if mode == Mode.DEAD:
		return
	if _iframes > 0.0:
		return
	survival.apply_damage(amount, source)
	survival.mark_stamina_used()
	damage_taken.emit(amount)
	_action_lock = 0.25
	if effect == "bleed":
		survival.add_bleed(1)
	elif effect == "fracture":
		survival.apply_fracture()
		Game.toast("骨折！需要夹板")
	if survival.health <= 0.0:
		_die(source)


func _die(reason: String) -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.DEAD
	last_death_reason = reason
	velocity = Vector3.ZERO
	if _mesh != null:
		_mesh.rotation.z = PI * 0.5
	player_died.emit(reason)


func revive_at(pos: Vector3, values: Dictionary) -> void:
	global_position = pos
	survival.reset_to(values)
	survival.bleed = 0
	survival.fractured = false
	mode = Mode.NORMAL
	if _mesh != null:
		_mesh.rotation.z = 0.0
	_set_target(null)


func _set_target(t: Node) -> void:
	current_target = t


func set_mode(m: int) -> void:
	mode = m


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if mode == Mode.BUILD:
		return
	if event.is_action_pressed("attack") and mode == Mode.NORMAL:
		try_attack()
	elif event.is_action_pressed("dodge") and mode == Mode.NORMAL:
		try_dodge()
	elif event.is_action_pressed("interact") and mode == Mode.NORMAL:
		try_interact()
	elif event.is_action_pressed("demolish") and mode == Mode.NORMAL and current_target is Building:
		if input_enabled:
			world.request_demolish(current_target)


func current_area_name() -> String:
	if survival.current_region != "":
		return GameConfig.REGIONS[survival.current_region]["name"]
	return ""


func to_dict() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "stats": survival.to_dict(), "inv": inventory.to_dict(), "yaw": rotation.y}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, -46])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(d.get("yaw", 0.0))
	survival.from_dict(d.get("stats", {}))
	inventory.from_dict(d.get("inv", {}))

## 敌人：数据驱动状态机 巡逻→警觉→追击→前摇→攻击→恢复，辅以受击/死亡（GDD 6.8）。
## 野猪=短距冲撞、狼=环绕突袭、守卫=横扫/范围重击交替。
## @trace MECH-007 MECH-006 NUM-003
class_name Enemy
extends CharacterBody3D

signal died(enemy: Enemy)
signal struck_player(enemy: Enemy, damage: float, effect: String)

enum State { PATROL, ALERT, CHASE, WINDUP, ATTACK, RECOVER, DEAD }

var enemy_type: String = "boar"
var data: Dictionary = {}
var state: int = State.PATROL
var hp: float = 60.0
var max_hp: float = 60.0
var home: Vector3
var target: Node3D = null
var _timer: float = 0.0
var _patrol_dir: Vector3 = Vector3.ZERO
var _attack_variant: int = 0
var _hit_done: bool = false
var _away_timer: float = 0.0
var _mesh: MeshInstance3D
var _telegraph: MeshInstance3D
var _health_bar: MeshInstance3D
var _health_fill: MeshInstance3D
var _flash_t: float = 0.0
var _last_attack_type: String = ""
var _base_mat: StandardMaterial3D


func setup(type_id: String) -> void:
	enemy_type = type_id
	data = GameConfig.ENEMIES[type_id]
	max_hp = float(data["hp"])
	hp = max_hp
	home = global_position
	collision_layer = GameConfig.LAYER_ENEMY
	collision_mask = GameConfig.LAYER_WORLD
	add_to_group("enemies")
	add_to_group("interactable_enemy")
	_build_visual()
	# 受击闪红：为网格加一个共享材质（emission 叠加），避免改共享网格材质
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.3, 0.3, 0.0)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_base_mat = flash_mat


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	match enemy_type:
		"boar":
			_mesh.mesh = LowPolyMesh.boar()
		"wolf":
			_mesh.mesh = LowPolyMesh.wolf()
		_:
			_mesh.mesh = LowPolyMesh.guardian()
	add_child(_mesh)

	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	match enemy_type:
		"boar":
			shape.radius = 0.55
			shape.height = 1.3
			cs.position = Vector3(0, 0.65, 0)
		"wolf":
			shape.radius = 0.4
			shape.height = 1.2
			cs.position = Vector3(0, 0.6, 0)
		_:
			shape.radius = 0.75
			shape.height = 2.9
			cs.position = Vector3(0, 1.45, 0)
	cs.shape = shape
	add_child(cs)

	# 前摇提示：地面红圈
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.3
	cyl.bottom_radius = 1.3
	cyl.height = 0.05
	cyl.radial_segments = 20
	_telegraph.mesh = cyl
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(GameConfig.PALETTE["danger"])
	tm.albedo_color.a = 0.45
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph.material_override = tm
	_telegraph.position = Vector3(0, 0.06, 0)
	_telegraph.visible = false
	add_child(_telegraph)

	# 血量条
	_health_bar = MeshInstance3D.new()
	var bg := QuadMesh.new()
	bg.size = Vector2(1.2, 0.14)
	_health_bar.mesh = bg
	var bgm := StandardMaterial3D.new()
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgm.albedo_color = Color(0.1, 0.1, 0.1, 0.7)
	bgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.material_override = bgm
	_health_bar.position = Vector3(0, 3.3 if enemy_type == "guardian" else 1.8, 0)
	add_child(_health_bar)
	_health_fill = MeshInstance3D.new()
	var fill := QuadMesh.new()
	fill.size = Vector2(1.16, 0.1)
	_health_fill.mesh = fill
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color("#D95555")
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_health_fill.material_override = fm
	_health_fill.position = Vector3(0, 0, 0.01)
	_health_fill.top_level = true
	_health_bar.visible = false


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	_timer -= delta
	_flash_t = maxf(0.0, _flash_t - delta)
	if _base_mat != null:
		_base_mat.emission_enabled = _flash_t > 0.0
		_base_mat.emission = Color(1.0, 0.35, 0.35) if _flash_t > 0.0 else Color.BLACK
	var to_target := 0.0
	if is_instance_valid(target):
		to_target = global_position.distance_to(target.global_position)
	match state:
		State.PATROL:
			_do_patrol(delta)
			if is_instance_valid(target) and to_target < float(data["aggro"]):
				_set_state(State.ALERT)
		State.ALERT:
			_timer -= delta
			_face(target.global_position if is_instance_valid(target) else global_position)
			if _timer <= 0.0:
				_set_state(State.CHASE)
		State.CHASE:
			_do_chase(delta, to_target)
		State.WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			if _timer <= 0.0:
				_do_attack_start()
		State.ATTACK:
			_do_attack(delta)
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _timer <= 0.0:
				_set_state(State.CHASE if is_instance_valid(target) else State.PATROL)
	move_and_slide()
	_update_health_bar()


func _set_state(s: int) -> void:
	state = s
	match s:
		State.ALERT:
			_timer = 0.35
		State.WINDUP:
			var wind: float = float(data["windup"])
			if _last_attack_type == "heavy":
				wind *= 1.25
			_timer = wind
			_telegraph.visible = true
			_hit_done = false
		State.ATTACK:
			_telegraph.visible = false
		State.RECOVER:
			_timer = float(data["recover"])
			if enemy_type == "guardian":
				_timer = 1.2 if _last_attack_type == "sweep" else 1.8
		State.DEAD:
			_telegraph.visible = false
			if _health_bar != null:
				_health_bar.visible = false


func _do_patrol(delta: float) -> void:
	if _patrol_dir == Vector3.ZERO or global_position.distance_to(home) > 8.0:
		var ang := randf() * TAU
		_patrol_dir = Vector3(cos(ang), 0, sin(ang))
	var speed := float(data["speed"]) * 0.35
	velocity.x = _patrol_dir.x * speed
	velocity.z = _patrol_dir.z * speed
	_face(global_position + _patrol_dir)
	if global_position.distance_to(home) > 9.0:
		_patrol_dir = (home - global_position).normalized()
	if _timer <= 0.0:
		_timer = randf_range(2.0, 4.0)
		_patrol_dir = Vector3.ZERO


func _do_chase(delta: float, dist: float) -> void:
	if not is_instance_valid(target):
		_set_state(State.PATROL)
		return
	if global_position.distance_to(home) > float(data["leash"]):
		_lose_target()
		return
	_face(target.global_position)
	var speed := float(data["speed"])
	if enemy_type == "wolf":
		# 环绕后突袭
		var to := (target.global_position - global_position)
		to.y = 0.0
		if dist > 3.5:
			velocity.x = to.normalized().x * speed
			velocity.z = to.normalized().z * speed
		else:
			var side := to.normalized().cross(Vector3.UP)
			velocity.x = side.x * speed * 0.8 + to.normalized().x * speed * 0.3
			velocity.z = side.z * speed * 0.8 + to.normalized().z * speed * 0.3
	elif dist > _attack_range():
		var to := (target.global_position - global_position)
		to.y = 0.0
		velocity.x = to.normalized().x * speed
		velocity.z = to.normalized().z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if dist <= _attack_range():
		_pick_attack()


func _pick_attack() -> void:
	if not is_instance_valid(target):
		return
	_last_attack_type = "sweep"
	if enemy_type == "guardian":
		_attack_variant = 1 - _attack_variant
		_last_attack_type = "sweep" if _attack_variant == 0 else "heavy"
	_set_state(State.WINDUP)


func _attack_range() -> float:
	match enemy_type:
		"boar":
			return 2.2
		"wolf":
			return 2.0
		_:
			return 2.6


func _do_attack_start() -> void:
	_set_state(State.ATTACK)
	if enemy_type == "boar":
		var dir := (target.global_position - global_position) if is_instance_valid(target) else -global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
		_charge_dir = dir
		_charge_left = 0.45
		_timer = 0.45
	else:
		_timer = 0.32
		_try_hit()


var _charge_dir: Vector3 = Vector3.ZERO
var _charge_left: float = 0.0


func _do_attack(delta: float) -> void:
	if enemy_type == "boar":
		velocity.x = _charge_dir.x * float(data["speed"]) * 2.0
		velocity.z = _charge_dir.z * float(data["speed"]) * 2.0
		_try_hit()
		if _timer <= 0.0:
			_set_state(State.RECOVER)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_try_hit()
		if _timer <= 0.0:
			_set_state(State.RECOVER)


func _try_hit() -> void:
	if _hit_done or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	var reach := _attack_range()
	if enemy_type == "guardian" and _last_attack_type == "heavy":
		reach = 3.6
	if dist > reach:
		return
	_hit_done = true
	var dmg := float(data["damage"])
	var effect := ""
	if enemy_type == "guardian" and _last_attack_type == "heavy":
		dmg = float(data["heavy_damage"])
		effect = "fracture"
	if enemy_type == "wolf" and randf() < float(data["bleed"]):
		effect = "bleed"
	if enemy_type == "boar" and randf() < float(data["fracture"]):
		effect = "fracture"
	var fwd := -global_transform.basis.z
	var to_t := (target.global_position - global_position)
	to_t.y = 0.0
	if fwd.normalized().dot(to_t.normalized()) < -0.2 and dist > 1.2:
		return
	struck_player.emit(self, dmg, effect)


func _lose_target() -> void:
	target = null
	velocity = Vector3.ZERO
	_set_state(State.PATROL)
	# 脱战回血（GDD 6.8）
	hp = minf(max_hp, hp + max_hp * 0.25)


func _face(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	rotation.y = atan2(-d.x, -d.z)


## 返回实际伤害；同一动作对同一目标只命中一次由调用方保证
func take_damage(base: float, move_mult: float = 1.0) -> int:
	if state == State.DEAD:
		return 0
	var dmg := GameConfig.damage_formula(base, move_mult, float(data["resistance"]))
	hp = maxf(0.0, hp - float(dmg))
	_flash_t = 0.12
	_health_bar.visible = true
	if is_instance_valid(target) == false and is_inside_tree():
		target = _find_player()
		if state == State.PATROL:
			_set_state(State.CHASE)
	if hp <= 0.0:
		_die()
	return dmg


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	remove_from_group("enemies")
	remove_from_group("interactable_enemy")
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.0, 0.2, 1.0), 0.35)
	Game.stats["kills"] = int(Game.stats.get("kills", 0)) + 1
	died.emit(self)


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func _update_health_bar() -> void:
	if _health_bar == null:
		return
	if _health_bar.visible:
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		_health_bar.global_position = global_position + Vector3(0, 3.3 if enemy_type == "guardian" else 1.8, 0)
		if ratio <= 0.0:
			_health_bar.visible = false


func _ready() -> void:
	add_to_group("interactable")


func drop_items() -> Dictionary:
	return data["drop"].duplicate()


func to_dict() -> Dictionary:
	return {"t": enemy_type, "hp": hp, "p": [home.x, home.z], "dead": state == State.DEAD}


func restore(state_dict: Dictionary) -> void:
	hp = float(state_dict.get("hp", max_hp))
	if bool(state_dict.get("dead", false)):
		queue_free()

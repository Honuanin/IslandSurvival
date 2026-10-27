## 建造控制器：预览、合法性检查、放置事务、拆除返还（GDD 6.5）。
## @trace MECH-005 UI-002
class_name BuildController
extends Node3D

signal build_validity_changed(valid: bool, reason: String)
signal building_placed(building: Building)
signal building_removed(building: Building)

const MAX_SLOPE_DEG := 25.0
const MIN_SPACING := 0.2

var world: Node = null
var player: Player = null
var active: bool = false
var selected: String = ""
var preview: MeshInstance3D
var _preview_mat_ok: StandardMaterial3D
var _preview_mat_bad: StandardMaterial3D
var _last_reason: String = ""
var _last_valid: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_mat_ok = StandardMaterial3D.new()
	_preview_mat_ok.albedo_color = Color(GameConfig.PALETTE["build_ok"])
	_preview_mat_ok.albedo_color.a = 0.55
	_preview_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat_bad = StandardMaterial3D.new()
	_preview_mat_bad.albedo_color = Color(GameConfig.PALETTE["danger"])
	_preview_mat_bad.albedo_color.a = 0.55
	_preview_mat_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat_bad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview = MeshInstance3D.new()
	preview.name = "Preview"
	preview.visible = false
	add_child(preview)


func enter() -> void:
	active = true
	if selected == "":
		selected = "campfire"
	preview.visible = true
	_set_preview_mesh()


func exit() -> void:
	active = false
	preview.visible = false


func select(type_id: String) -> void:
	if not GameConfig.BUILDINGS.has(type_id):
		return
	selected = type_id
	_set_preview_mesh()


func _set_preview_mesh() -> void:
	if selected == "":
		return
	var tmp: ArrayMesh
	match selected:
		"campfire":
			tmp = LowPolyMesh.campfire()
		"workbench":
			tmp = LowPolyMesh.workbench()
		"shelter":
			tmp = LowPolyMesh.shelter()
		_:
			tmp = LowPolyMesh.signal_tower()
	preview.mesh = tmp
	preview.material_override = _preview_mat_ok


func _process(_delta: float) -> void:
	if not active or player == null:
		return
	var pos := _pointer_ground()
	preview.global_position = pos
	preview.rotation.y += 4.0 * _delta if Input.is_action_pressed("rotate_build") else 0.0
	var check := validate(selected, pos, preview.rotation.y)
	preview.material_override = _preview_mat_ok if check["valid"] else _preview_mat_bad
	if check["valid"] != _last_valid or check["reason"] != _last_reason:
		_last_valid = check["valid"]
		_last_reason = check["reason"]
		build_validity_changed.emit(check["valid"], check["reason"])


func _pointer_ground() -> Vector3:
	var cam: Camera3D = player.camera
	var p := player.global_position
	if cam != null:
		var screen_pos := get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(screen_pos)
		var dir := cam.project_ray_normal(screen_pos)
		if absf(dir.y) > 0.001:
			var t := (0.0 - from.y) / dir.y
			if t > 0.0:
				var hit := from + dir * t
				var terrain: IslandTerrain = player.terrain
				if terrain != null:
					hit.y = terrain.height_at(hit.x, hit.z)
				# 限制在玩家 8 米内（GDD 4.3 建造半径）
				var flat := Vector3(hit.x, 0, hit.z)
				var pp := Vector3(p.x, 0, p.z)
				if flat.distance_to(pp) > 8.0:
					hit = pp + (flat - pp).normalized() * 8.0
					if terrain != null:
						hit.y = terrain.height_at(hit.x, hit.z)
				return hit
	p.y = player.terrain.height_at(p.x, p.z) if player.terrain != null else 0.0
	return p


## 返回 {"valid":bool, "reason":String}
func validate(type_id: String, pos: Vector3, _yaw: float = 0.0) -> Dictionary:
	if not GameConfig.BUILDINGS.has(type_id):
		return {"valid": false, "reason": "未知建筑"}
	var data: Dictionary = GameConfig.BUILDINGS[type_id]
	if world == null or player == null:
		return {"valid": false, "reason": "世界未就绪"}
	var terrain: IslandTerrain = player.terrain
	# 地表/水域
	if terrain != null:
		if not terrain.walkable(pos.x, pos.z):
			return {"valid": false, "reason": "超出可建范围"}
		if terrain.height_at(pos.x, pos.z) < 0.05:
			return {"valid": false, "reason": "不能建在水下"}
		if _slope_deg(terrain, pos) > MAX_SLOPE_DEG:
			return {"valid": false, "reason": "坡度过陡（>25°）"}
	# 出生保护区 / 遗迹内部
	if terrain != null:
		if Vector2(pos.x - terrain.SPAWN_POINT.x, pos.z - terrain.SPAWN_POINT.z).length() < 5.0:
			return {"valid": false, "reason": "出生保护区禁建"}
		if Vector2(pos.x - terrain.RITUAL_POINT.x, pos.z - terrain.RITUAL_POINT.z).length() < 6.0:
			return {"valid": false, "reason": "遗迹内部禁建"}
	# 信号火台只能在信号点
	if type_id == "signal_tower":
		var sp: Vector3 = terrain.signal_point_position()
		if Vector2(pos.x - sp.x, pos.z - sp.z).length() > 3.5:
			return {"valid": false, "reason": "信号火台只能建在信号点"}
		for qi in data["quest_items"]:
			if int(player.inventory.quest_items.get(qi, 0)) <= 0:
				return {"valid": false, "reason": "缺少" + GameConfig.item_name(str(qi))}
	# 数量上限
	var existing: int = world.count_buildings(type_id)
	if existing >= int(data["limit"]):
		return {"valid": false, "reason": "已达数量上限（%d）" % int(data["limit"])}
	# 材料
	if not player.inventory.can_afford(data["cost"]):
		var mis: Dictionary = player.inventory.missing(data["cost"])
		var parts: Array = []
		for id in mis:
			parts.append("%s 差%d" % [GameConfig.item_name(str(id)), int(mis[id])])
		return {"valid": false, "reason": "材料不足：" + "，".join(parts)}
	# 重叠
	if world.has_building_near(pos, float(data["size"]) + MIN_SPACING):
		return {"valid": false, "reason": "与已有建筑重叠"}
	# 资源节点重叠
	for rn in get_tree().get_nodes_in_group("resource_nodes"):
		if (rn as Node3D).global_position.distance_to(pos) < float(data["size"]) + 0.6:
			return {"valid": false, "reason": "与资源点重叠"}
	return {"valid": true, "reason": "可建造"}


func _slope_deg(terrain: IslandTerrain, pos: Vector3) -> float:
	var e := 1.0
	var hx := terrain.height_at(pos.x + e, pos.z) - terrain.height_at(pos.x - e, pos.z)
	var hz := terrain.height_at(pos.x, pos.z + e) - terrain.height_at(pos.x, pos.z - e)
	var grad := Vector2(hx / (2.0 * e), hz / (2.0 * e)).length()
	return rad_to_deg(atan(grad))


## 放置事务：校验通过才扣料并生成
func try_place() -> Dictionary:
	if not active:
		return {"ok": false, "reason": "未进入建造模式"}
	var pos := _pointer_ground()
	var check := validate(selected, pos, preview.rotation.y)
	if not check["valid"]:
		Game.toast("无法建造：" + str(check["reason"]))
		return {"ok": false, "reason": check["reason"]}
	var data: Dictionary = GameConfig.BUILDINGS[selected]
	if not player.inventory.pay(data["cost"]):
		return {"ok": false, "reason": "材料不足"}
	var b: Building = world.spawn_building(selected, pos, preview.rotation.y)
	building_placed.emit(b)
	Game.stats["buildings"] = int(Game.stats.get("buildings", 0)) + 1
	Game.toast("已建造：" + GameConfig.building_name(selected))
	if selected == "workbench":
		Game.complete_objective("workbench")
		world.save_game()
	elif selected == "signal_tower":
		Game.complete_objective("tower_built")
		world.save_game()
	return {"ok": true, "building": b}


func demolish(b: Building) -> void:
	if b == null or not is_instance_valid(b):
		return
	if b.building_type == "signal_tower" and b.lit:
		Game.toast("已点燃的火台无法拆除")
		return
	var refund := b.demolish_refund()
	for id in refund:
		player.inventory.add(str(id), int(refund[id]))
	building_removed.emit(b)
	var parts: Array = []
	for id in refund:
		parts.append("%s×%d" % [GameConfig.item_name(str(id)), int(refund[id])])
	Game.toast("已拆除，返还（50%%向下取整）：" + ("无" if parts.is_empty() else "、".join(parts)))
	world.remove_building(b)

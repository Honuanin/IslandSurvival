## 建筑：统一接口 + 功能组件（营火供热/工作台/庇护所/信号火台）。
## @trace MECH-005 MECH-009 FLOW-003
class_name Building
extends StaticBody3D

signal lit_changed(building: Building, lit: bool)

var building_type: String = "campfire"
var data: Dictionary = {}
var building_id: String = ""
var lit: bool = false
var _mesh_inst: MeshInstance3D
var _fire_light: OmniLight3D
var _gk: Node3D


func setup(type_id: String, id: String, authored_state: Dictionary = {}) -> void:
	building_type = type_id
	building_id = id
	data = GameConfig.BUILDINGS[type_id]
	collision_layer = GameConfig.LAYER_BUILDING | GameConfig.LAYER_INTERACT
	collision_mask = 0
	add_to_group("buildings")
	add_to_group("interactable")
	if type_id != "signal_tower":
		add_to_group("buildings_" + type_id)
	_build()
	if authored_state.has("lit"):
		set_lit(bool(authored_state["lit"]))


func _build() -> void:
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "Mesh"
	match building_type:
		"campfire":
			_mesh_inst.mesh = LowPolyMesh.campfire()
		"workbench":
			_mesh_inst.mesh = LowPolyMesh.workbench()
		"shelter":
			_mesh_inst.mesh = LowPolyMesh.shelter()
		_:
			_mesh_inst.mesh = LowPolyMesh.signal_tower()
	add_child(_mesh_inst)
	var size: float = data["size"]
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = size
	shape.height = 2.0
	cs.shape = shape
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)
	_gk = Node3D.new()
	_gk.name = "Gizmo"
	add_child(_gk)
	if building_type == "campfire":
		_fire_light = OmniLight3D.new()
		_fire_light.light_color = Color("#FFA24E")
		_fire_light.light_energy = 1.6
		_fire_light.omni_range = float(data["range"])
		_fire_light.position = Vector3(0, 0.9, 0)
		_fire_light.visible = false
		add_child(_fire_light)
		lit = false
	elif building_type == "signal_tower":
		_fire_light = OmniLight3D.new()
		_fire_light.light_color = Color("#FFB347")
		_fire_light.light_energy = 0.0
		_fire_light.omni_range = 16.0
		_fire_light.position = Vector3(0, 3.2, 0)
		_fire_light.visible = false
		add_child(_fire_light)


func set_lit(value: bool) -> void:
	lit = value
	if _fire_light != null:
		_fire_light.visible = value
		_fire_light.light_energy = 1.6 if building_type == "campfire" else 4.0
	if building_type == "campfire":
		_mesh_inst.scale = Vector3.ONE


## 营火：6 米内线性衰减供热 0..2℃；点燃后才有热
func heat_bonus_at(pos: Vector3) -> float:
	if building_type == "signal_tower" and lit:
		return 0.0
	if not lit:
		return 0.0
	var dist := global_position.distance_to(pos)
	var r: float = float(data["range"])
	if dist > r:
		return 0.0
	return float(GameConfig.SURVIVAL["campfire_bonus"]) * (1.0 - dist / r)


func on_player_interact(player_node: Node) -> void:
	match building_type:
		"campfire":
			if not lit:
				set_lit(true)
				Game.toast("营火已点燃：6 米内供热")
			else:
				Game.toast("营火可烹饪，按 Tab 打开制作")
		"shelter":
			var host: Node = get_parent().get_parent()
			if host != null and host.has_method("try_sleep"):
				host.try_sleep(self, player_node)
		"signal_tower":
			if lit:
				Game.toast("火台已点燃")
				return
			if int(player_node.inventory.quest_items.get("lens", 0)) <= 0:
				Game.toast("缺少火台透镜")
				return
			if int(player_node.inventory.quest_items.get("guard_emblem", 0)) <= 0:
				Game.toast("缺少守卫徽记")
				return
			var host2: Node = get_parent().get_parent()
			if host2 != null and host2.has_method("light_tower"):
				host2.light_tower(self)


func interact_prompt() -> String:
	match building_type:
		"campfire":
			return "营火（E 点燃）" if not lit else "营火（E 添加燃料 / Tab 烹饪）"
		"workbench":
			return "工作台（Tab 制作升级）"
		"shelter":
			return "庇护所（E 休息到清晨）"
		"signal_tower":
			return "信号火台（E 点燃）" if not lit else "信号火台（已点燃）"
	return GameConfig.building_name(building_type)


func to_dict() -> Dictionary:
	return {"t": building_type, "id": building_id, "p": [global_position.x, global_position.z], "lit": lit}


func demolish_refund() -> Dictionary:
	var out := {}
	var cost: Dictionary = data["cost"]
	for id in cost:
		var half := int(floor(float(cost[id]) * 0.5))
		if half > 0:
			out[id] = half
	return out

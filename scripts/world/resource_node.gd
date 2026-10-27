## 资源节点：工具校验、产出、耗尽与个人复活计时（GDD 6.2 / 5.4）。
## @trace MECH-004 NUM-005
class_name ResourceNode
extends StaticBody3D

signal depleted(node: ResourceNode)

var node_type: String = "driftwood"
var node_id: String = ""
var data: Dictionary = {}
var durability: int = 2
var remaining: int = 1
var respawn_timer: float = 0.0
var is_depleted: bool = false

var _mesh_inst: MeshInstance3D
var _highlight: MeshInstance3D
var _label: Label3D


func setup(type_id: String, id: String) -> void:
	node_type = type_id
	node_id = id
	data = GameConfig.NODES[type_id]
	durability = int(data["durability"])
	remaining = int(data["amount"])
	collision_layer = GameConfig.LAYER_INTERACT
	collision_mask = 0
	add_to_group("resource_nodes")
	add_to_group("interactable")
	_build_visual()


func _build_visual() -> void:
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "Mesh"
	var mesh: ArrayMesh
	match node_type:
		"tree":
			mesh = LowPolyMesh.tree()
		"driftwood":
			mesh = LowPolyMesh.driftwood()
		"rock":
			mesh = LowPolyMesh.rock()
		"pebble":
			mesh = LowPolyMesh.pebble()
		"fiber_bush":
			mesh = LowPolyMesh.fiber_bush()
		"berry_bush":
			mesh = LowPolyMesh.berry_bush()
		"herb":
			mesh = LowPolyMesh.herb()
		"metal_ore":
			mesh = LowPolyMesh.metal_ore()
		"scrap_box":
			mesh = LowPolyMesh.scrap_box()
		_:
			mesh = LowPolyMesh.water_source()
	_mesh_inst.mesh = mesh
	add_child(_mesh_inst)

	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.85 if node_type != "tree" else 0.55
	shape.height = 2.6 if node_type == "tree" else 1.2
	cs.shape = shape
	cs.position = Vector3(0, shape.height * 0.5, 0)
	add_child(cs)

	_highlight = MeshInstance3D.new()
	_highlight.name = "Highlight"
	_highlight.mesh = mesh
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(GameConfig.PALETTE["interactable"])
	hm.albedo_color.a = 0.35
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.grow = 0.03
	hm.cull_mode = BaseMaterial3D.CULL_FRONT
	_highlight.material_override = hm
	_highlight.visible = false
	_highlight.scale = Vector3(1.04, 1.03, 1.04)
	add_child(_highlight)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.008
	_label.position = Vector3(0, 2.3 if node_type == "tree" else 1.5, 0)
	_label.modulate = Color("#F2C14E")
	_label.visible = false
	add_child(_label)


func on_player_interact(player_node: Node) -> void:
	if player_node.has_method("_do_harvest"):
		player_node._do_harvest(self)


func set_highlighted(on: bool) -> void:
	if _highlight != null:
		_highlight.visible = on and not is_depleted


func interact_prompt() -> String:
	if is_depleted:
		return ""
	var need: String = str(data["tool"])
	if need != "":
		return "%s（需%s）" % [data["name"], "石斧" if need == "axe" else "石镐"]
	return str(data["name"])


## 返回 {"ok":bool, "reason":String, "item":String, "amount":int}
func harvest(player: Node) -> Dictionary:
	if is_depleted:
		return {"ok": false, "reason": "已耗尽"}
	var need: String = str(data["tool"])
	var has_tool := false
	if need != "":
		var inv: Inventory = player.inventory
		has_tool = inv.tool_of_kind(need) != ""
	if need != "" and not has_tool:
		return {"ok": false, "reason": "需要%s" % ("石斧" if need == "axe" else "石镐")}
	durability -= 1
	remaining -= 1
	var item: String = str(data["item"])
	var amount := 1
	if need != "":
		var tool_id: String = player.inventory.tool_of_kind(need)
		amount = int(GameConfig.TOOLS[tool_id]["gather"])
	amount = maxi(1, amount)
	var placed: int = player.inventory.add(item, amount)
	if placed <= 0:
		return {"ok": false, "reason": "背包已满"}
	if remaining <= 0 or durability <= 0:
		_deplete()
	return {"ok": true, "item": item, "amount": placed, "depleted": is_depleted}


func _deplete() -> void:
	is_depleted = true
	remaining = 0
	durability = 0
	respawn_timer = float(data["respawn"])
	_mesh_inst.visible = false
	_highlight.visible = false
	_label.visible = false
	collision_layer = 0
	depleted.emit(self)


func set_state(alive: bool, rem: int, dur: int, timer: float) -> void:
	is_depleted = not alive
	remaining = rem
	durability = dur
	respawn_timer = timer
	if alive:
		_mesh_inst.visible = true
		collision_layer = GameConfig.LAYER_INTERACT
	else:
		_mesh_inst.visible = false
		collision_layer = 0


func tick(delta: float) -> void:
	if not is_depleted:
		return
	if respawn_timer <= 0.0:
		return
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		_respawn()


func _respawn() -> void:
	is_depleted = false
	remaining = int(data["amount"])
	durability = int(data["durability"])
	respawn_timer = 0.0
	_mesh_inst.visible = true
	collision_layer = GameConfig.LAYER_INTERACT


func to_dict() -> Dictionary:
	return {"t": node_type, "alive": not is_depleted, "rem": remaining, "dur": durability, "timer": respawn_timer}

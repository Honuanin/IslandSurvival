## 掉落物（资源满包落地、死亡尸体、战利品箱）。
## @trace MECH-004 MECH-008
class_name GroundItem
extends Area3D

var contents: Dictionary = {}     # {item_id: count}
var is_corpse: bool = false
var owner_name: String = ""
var _mesh: MeshInstance3D
var _label: Label3D


func setup(items: Dictionary, corpse: bool = false) -> void:
	contents = items.duplicate()
	is_corpse = corpse
	collision_layer = GameConfig.LAYER_INTERACT
	collision_mask = 0
	add_to_group("ground_items")
	add_to_group("interactable")
	_build_visual()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	if is_corpse:
		_mesh.mesh = LowPolyMesh.corpse()
	else:
		_mesh.mesh = LowPolyMesh.scrap_box()
		_mesh.scale = Vector3(0.45, 0.45, 0.45)
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	cs.shape = sphere
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.008
	_label.position = Vector3(0, 1.4, 0)
	_label.modulate = Color("#F2C14E")
	add_child(_label)
	_refresh_label()


func _refresh_label() -> void:
	if is_corpse:
		_label.text = "遗体：%s\n(E 拾取，再次死亡会清除)" % _summary()
	else:
		_label.text = "掉落：%s" % _summary()


func _summary() -> String:
	var parts: Array = []
	for id in contents:
		parts.append("%s×%d" % [GameConfig.item_name(str(id)), int(contents[id])])
	return "、".join(parts) if parts.size() > 0 else "空"


func set_highlighted(on: bool) -> void:
	if _mesh != null:
		_mesh.scale = Vector3(0.5, 0.5, 0.5) if (on and not is_corpse) else (Vector3(0.45, 0.45, 0.45) if not is_corpse else Vector3.ONE)


func on_player_interact(player: Node) -> void:
	pickup(player)


func pickup(player: Node) -> bool:
	var inv: Inventory = player.inventory
	var remaining := {}
	var got: Array = []
	for id in contents:
		var want := int(contents[id])
		var placed := inv.add(str(id), want)
		if placed > 0:
			got.append("%s×%d" % [GameConfig.item_name(str(id)), placed])
		if placed < want:
			remaining[id] = want - placed
	if got.size() > 0:
		Game.toast("拾取：" + "、".join(got))
		if player.world != null:
			player.world.spawn_floating_text(global_position + Vector3(0, 1.4, 0), "拾取", Color("#68C3A3"))
		# 任务物品自动推进主线
		var inv_q: Dictionary = inv.quest_items
		if int(inv_q.get("lens", 0)) > 0:
			Game.complete_objective("lens")
		if int(inv_q.get("guard_emblem", 0)) > 0:
			Game.complete_objective("guardian")
	contents = remaining
	if contents.is_empty():
		queue_free()
	else:
		_refresh_label()
	return contents.is_empty()

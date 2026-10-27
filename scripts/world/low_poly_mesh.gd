## 低多边形程序模型库：全部由原始几何体组装，不使用外部美术资产（GDD 9.1）。
## 为降低绘制调用，每类角色/物件合并为一个 ArrayMesh，按材质分为多个 surface。
## @trace SCENE-002
class_name LowPolyMesh
extends RefCounted


static func _box(size: Vector3, center: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Array:
	var st := SurfaceTool.new()
	var h := size * 0.5
	var b := Basis.from_euler(rot_deg * (PI / 180.0))
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var half_n := n * h
		var half_u := u * h
		var half_v := v * h
		var pts := [
			half_n - half_u - half_v, half_n + half_u - half_v,
			half_n + half_u + half_v, half_n - half_u + half_v,
		]
		var wn := (b * n).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(wn)
			st.add_vertex(b * (pts[idx] as Vector3) + center)
	var arr := st.commit_to_arrays()
	return [arr]


static func _cyl(radius: float, height: float, center: Vector3, segments: int = 8, top_radius: float = -1.0) -> Array:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	var arr := m.get_mesh_arrays()
	_apply_transform(arr, Transform3D(Basis(), center))
	return [arr]


static func _sphere(radius: float, center: Vector3, height: float = -1.0, segments: int = 8, rings: int = 4) -> Array:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 if height < 0.0 else height
	m.radial_segments = segments
	m.rings = rings
	var arr := m.get_mesh_arrays()
	_apply_transform(arr, Transform3D(Basis(), center))
	return [arr]


static func _prism(size: Vector3, center: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Array:
	var m := PrismMesh.new()
	m.size = size
	var arr := m.get_mesh_arrays()
	var b := Basis.from_euler(rot_deg * (PI / 180.0))
	_apply_transform(arr, Transform3D(b, center))
	return [arr]


static func _apply_transform(arr: Array, xf: Transform3D) -> void:
	var verts: PackedVector3Array = arr[ArrayMesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[ArrayMesh.ARRAY_NORMAL]
	var b := xf.basis
	for i in range(verts.size()):
		verts[i] = xf * verts[i]
		normals[i] = (b * normals[i]).normalized()
	arr[ArrayMesh.ARRAY_VERTEX] = verts
	arr[ArrayMesh.ARRAY_NORMAL] = normals


## parts: Array of {geo: Array[ArrayMesh arrays], color: Color}
static func build(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for p in parts:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p["color"]
		mat.roughness = 0.95
		mat.metallic = 0.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		var geo: Array = p["geo"]
		for arr in geo:
			var a := (arr as Array).duplicate()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func color(hex: String) -> Color:
	return Color(hex)


# ---------------- 玩家 ----------------
static func player() -> ArrayMesh:
	var skin := Color("#E0B08A")
	var cloth := Color("#5C7D8A")
	var pants := Color("#3F4A55")
	return build([
		{"geo": _box(Vector3(0.52, 0.62, 0.34), Vector3(0, 0.95, 0)), "color": cloth},
		{"geo": _box(Vector3(0.44, 0.5, 0.3), Vector3(0, 0.42, 0)), "color": pants},
		{"geo": _sphere(0.19, Vector3(0, 1.42, 0), 0.38, 8, 4), "color": skin},
		{"geo": _cyl(0.07, 0.5, Vector3(-0.32, 0.95, 0), 6), "color": skin},
		{"geo": _cyl(0.07, 0.5, Vector3(0.32, 0.95, 0), 6), "color": skin},
		{"geo": _box(Vector3(0.16, 0.42, 0.16), Vector3(-0.13, 0.18, 0)), "color": pants},
		{"geo": _box(Vector3(0.16, 0.42, 0.16), Vector3(0.13, 0.18, 0)), "color": pants},
	])


# ---------------- 敌人 ----------------
static func boar() -> ArrayMesh:
	var fur := Color("#6B5546")
	var dark := Color("#3E3028")
	return build([
		{"geo": _box(Vector3(0.85, 0.72, 1.35), Vector3(0, 0.62, 0)), "color": fur},
		{"geo": _box(Vector3(0.6, 0.55, 0.5), Vector3(0, 0.62, 0.78)), "color": dark},
		{"geo": _box(Vector3(0.1, 0.1, 0.26), Vector3(-0.22, 0.5, 1.02)), "color": Color("#E8DCC0")},
		{"geo": _box(Vector3(0.1, 0.1, 0.26), Vector3(0.22, 0.5, 1.02)), "color": Color("#E8DCC0")},
		{"geo": _box(Vector3(0.2, 0.28, 0.2), Vector3(-0.28, 0.14, 0.42)), "color": dark},
		{"geo": _box(Vector3(0.2, 0.28, 0.2), Vector3(0.28, 0.14, 0.42)), "color": dark},
		{"geo": _box(Vector3(0.2, 0.28, 0.2), Vector3(-0.28, 0.14, -0.42)), "color": dark},
		{"geo": _box(Vector3(0.2, 0.28, 0.2), Vector3(0.28, 0.14, -0.42)), "color": dark},
	])


static func wolf() -> ArrayMesh:
	var fur := Color("#5A5F66")
	var dark := Color("#34383D")
	return build([
		{"geo": _box(Vector3(0.48, 0.5, 1.25), Vector3(0, 0.58, 0)), "color": fur},
		{"geo": _box(Vector3(0.38, 0.38, 0.45), Vector3(0, 0.72, 0.72)), "color": fur},
		{"geo": _box(Vector3(0.2, 0.16, 0.24), Vector3(0, 0.64, 0.98)), "color": dark},
		{"geo": _prism(Vector3(0.14, 0.18, 0.1), Vector3(-0.12, 0.92, 0.68), Vector3(0, 0, 20)), "color": dark},
		{"geo": _prism(Vector3(0.14, 0.18, 0.1), Vector3(0.12, 0.92, 0.68), Vector3(0, 0, -20)), "color": dark},
		{"geo": _box(Vector3(0.12, 0.42, 0.12), Vector3(-0.16, 0.2, 0.42)), "color": dark},
		{"geo": _box(Vector3(0.12, 0.42, 0.12), Vector3(0.16, 0.2, 0.42)), "color": dark},
		{"geo": _box(Vector3(0.12, 0.42, 0.12), Vector3(-0.16, 0.2, -0.42)), "color": dark},
		{"geo": _box(Vector3(0.12, 0.42, 0.12), Vector3(0.16, 0.2, -0.42)), "color": dark},
		{"geo": _box(Vector3(0.1, 0.1, 0.5), Vector3(0, 0.7, -0.75)), "color": fur},
	])


static func guardian() -> ArrayMesh:
	var stone := Color("#8A8F96")
	var moss := Color("#5F7A5A")
	var glow := Color("#E2A23A")
	return build([
		{"geo": _box(Vector3(1.25, 1.5, 0.85), Vector3(0, 1.55, 0)), "color": stone},
		{"geo": _box(Vector3(0.75, 0.6, 0.7), Vector3(0, 2.55, 0.05)), "color": stone},
		{"geo": _box(Vector3(0.5, 0.12, 0.12), Vector3(0, 2.6, 0.4)), "color": glow},
		{"geo": _box(Vector3(0.3, 1.1, 0.3), Vector3(-0.85, 1.5, 0)), "color": stone},
		{"geo": _box(Vector3(0.3, 1.1, 0.3), Vector3(0.85, 1.5, 0)), "color": stone},
		{"geo": _box(Vector3(0.4, 0.7, 0.4), Vector3(-0.35, 0.35, 0)), "color": moss},
		{"geo": _box(Vector3(0.4, 0.7, 0.4), Vector3(0.35, 0.35, 0)), "color": moss},
		{"geo": _box(Vector3(0.5, 0.5, 0.5), Vector3(1.2, 1.05, 0.3)), "color": moss},
	])


# ---------------- 资源节点 ----------------
static func tree() -> ArrayMesh:
	var trunk := Color("#6B4F36")
	var leaf := Color("#3F6B3F")
	var leaf2 := Color("#4E7C46")
	return build([
		{"geo": _cyl(0.32, 2.4, Vector3(0, 1.2, 0), 7), "color": trunk},
		{"geo": _sphere(1.5, Vector3(0, 3.0, 0), 2.0, 7, 4), "color": leaf},
		{"geo": _sphere(1.0, Vector3(0.7, 3.7, 0.3), 1.4, 7, 3), "color": leaf2},
	])


static func driftwood() -> ArrayMesh:
	var wood := Color("#A08C6E")
	return build([
		{"geo": _cyl(0.18, 2.2, Vector3(0, 0.18, 0), 6), "color": wood},
		{"geo": _cyl(0.14, 1.4, Vector3(0.3, 0.3, 0.5), 6), "color": Color("#8B7757")},
	])


static func rock() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.9, Vector3(0, 0.55, 0), 1.1, 6, 3), "color": Color("#8A8F94")},
		{"geo": _sphere(0.55, Vector3(0.8, 0.3, 0.3), 0.7, 6, 3), "color": Color("#767B80")},
	])


static func pebble() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.5, Vector3(0, 0.25, 0), 0.6, 6, 3), "color": Color("#9A9F9F")},
		{"geo": _sphere(0.3, Vector3(0.5, 0.15, 0.2), 0.4, 6, 3), "color": Color("#8A8F8F")},
	])


static func fiber_bush() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.7, Vector3(0, 0.45, 0), 0.9, 6, 3), "color": Color("#7C9A55")},
		{"geo": _box(Vector3(0.12, 0.7, 0.12), Vector3(0.3, 0.55, 0.2)), "color": Color("#9BB36A")},
		{"geo": _box(Vector3(0.12, 0.6, 0.12), Vector3(-0.3, 0.5, -0.1)), "color": Color("#9BB36A")},
	])


static func berry_bush() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.7, Vector3(0, 0.45, 0), 0.9, 6, 3), "color": Color("#5C8A4A")},
		{"geo": _sphere(0.1, Vector3(0.25, 0.7, 0.35), -1, 5, 3), "color": Color("#C0392B")},
		{"geo": _sphere(0.1, Vector3(-0.3, 0.6, 0.2), -1, 5, 3), "color": Color("#C0392B")},
	])


static func herb() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.5, Vector3(0, 0.3, 0), 0.7, 6, 3), "color": Color("#7FA96B")},
		{"geo": _box(Vector3(0.1, 0.6, 0.1), Vector3(0, 0.6, 0)), "color": Color("#C9D98A")},
	])


static func metal_ore() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.85, Vector3(0, 0.5, 0), 1.0, 6, 3), "color": Color("#6E7378")},
		{"geo": _box(Vector3(0.3, 0.3, 0.3), Vector3(0.35, 0.9, 0.2), Vector3(25, 35, 10)), "color": Color("#B9A46B")},
		{"geo": _box(Vector3(0.24, 0.24, 0.24), Vector3(-0.3, 0.75, -0.2), Vector3(15, 55, 20)), "color": Color("#C9B47B")},
	])


static func scrap_box() -> ArrayMesh:
	var crate := Color("#8E6E4A")
	return build([
		{"geo": _box(Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0)), "color": crate},
		{"geo": _box(Vector3(0.95, 0.12, 0.95), Vector3(0, 0.85, 0), Vector3(0, 0, 5)), "color": Color("#6E5335")},
		{"geo": _box(Vector3(0.3, 0.1, 0.3), Vector3(0.2, 0.95, 0.1), Vector3(10, 20, 0)), "color": Color("#57A7B8")},
	])


static func water_source() -> ArrayMesh:
	return build([
		{"geo": _cyl(0.9, 0.08, Vector3(0, 0.04, 0), 10), "color": Color("#3E8AA8")},
	])


static func chest() -> ArrayMesh:
	return build([
		{"geo": _box(Vector3(1.0, 0.6, 0.7), Vector3(0, 0.3, 0)), "color": Color("#8C6239")},
		{"geo": _box(Vector3(1.05, 0.22, 0.75), Vector3(0, 0.7, 0)), "color": Color("#6E4B2A")},
		{"geo": _box(Vector3(0.2, 0.2, 0.1), Vector3(0, 0.55, 0.38)), "color": Color("#E2A23A")},
	])


static func corpse() -> ArrayMesh:
	return build([
		{"geo": _sphere(0.55, Vector3(0, 0.2, 0), 0.5, 6, 3), "color": Color("#6E5B4E")},
		{"geo": _box(Vector3(0.3, 0.3, 0.3), Vector3(0.4, 0.2, 0.3), Vector3(0, 30, 0)), "color": Color("#8A7A66")},
	])


# ---------------- 建筑 ----------------
static func campfire() -> ArrayMesh:
	return build([
		{"geo": _cyl(0.9, 0.12, Vector3(0, 0.06, 0), 8), "color": Color("#5A5A5A")},
		{"geo": _box(Vector3(0.16, 0.16, 0.9), Vector3(0.15, 0.2, 0), Vector3(0, 35, 12)), "color": Color("#6B4F36")},
		{"geo": _box(Vector3(0.16, 0.16, 0.9), Vector3(-0.15, 0.2, 0), Vector3(0, -35, 12)), "color": Color("#5C4430")},
		{"geo": _prism(Vector3(0.6, 0.9, 0.6), Vector3(0, 0.5, 0)), "color": Color("#E8703A")},
	])


static func workbench() -> ArrayMesh:
	return build([
		{"geo": _box(Vector3(1.6, 0.12, 0.9), Vector3(0, 0.85, 0)), "color": Color("#A5834F")},
		{"geo": _box(Vector3(0.14, 0.85, 0.14), Vector3(-0.7, 0.42, -0.35)), "color": Color("#7A5A36")},
		{"geo": _box(Vector3(0.14, 0.85, 0.14), Vector3(0.7, 0.42, -0.35)), "color": Color("#7A5A36")},
		{"geo": _box(Vector3(0.14, 0.85, 0.14), Vector3(-0.7, 0.42, 0.35)), "color": Color("#7A5A36")},
		{"geo": _box(Vector3(0.14, 0.85, 0.14), Vector3(0.7, 0.42, 0.35)), "color": Color("#7A5A36")},
		{"geo": _box(Vector3(0.5, 0.2, 0.35), Vector3(0.35, 1.0, 0)), "color": Color("#8A8F94")},
	])


static func shelter() -> ArrayMesh:
	var wood := Color("#8A6B45")
	var leaf := Color("#4F7A4A")
	return build([
		{"geo": _box(Vector3(2.6, 0.2, 2.6), Vector3(0, 0.1, 0)), "color": wood},
		{"geo": _prism(Vector3(2.8, 1.6, 2.8), Vector3(0, 1.0, 0), Vector3(0, 45, 0)), "color": leaf},
		{"geo": _box(Vector3(0.16, 1.2, 0.16), Vector3(-1.2, 0.7, -1.2)), "color": wood},
		{"geo": _box(Vector3(0.16, 1.2, 0.16), Vector3(1.2, 0.7, 1.2)), "color": wood},
	])


static func signal_tower() -> ArrayMesh:
	return build([
		{"geo": _cyl(1.3, 0.4, Vector3(0, 0.2, 0), 8), "color": Color("#7A7A7A")},
		{"geo": _box(Vector3(0.25, 2.6, 0.25), Vector3(-0.8, 1.4, -0.8), Vector3(0, 0, 8)), "color": Color("#8A6B45")},
		{"geo": _box(Vector3(0.25, 2.6, 0.25), Vector3(0.8, 1.4, -0.8), Vector3(0, 0, -8)), "color": Color("#8A6B45")},
		{"geo": _box(Vector3(0.25, 2.6, 0.25), Vector3(-0.8, 1.4, 0.8), Vector3(0, 0, 8)), "color": Color("#8A6B45")},
		{"geo": _box(Vector3(0.25, 2.6, 0.25), Vector3(0.8, 1.4, 0.8), Vector3(0, 0, -8)), "color": Color("#8A6B45")},
		{"geo": _cyl(0.9, 0.2, Vector3(0, 2.6, 0), 8), "color": Color("#5C5C5C")},
	])

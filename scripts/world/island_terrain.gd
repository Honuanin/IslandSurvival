## 岛屿地形与区域：手工布局的连续开放岛（GDD 5.1），无区域加载。
## 岛半径 68 米，北岩地/西森林/东湿地/南海滩，中央高地。
## @trace LEV-001 LEV-002
class_name IslandTerrain
extends Node3D

const RADIUS := 68.0

var _heightmap: FastNoiseLite
var _region_noise: FastNoiseLite

# 区域中心（米）与半径，用于判断所在区域和气温基准
const REGION_CENTERS := {
	"beach": Vector2(0, -46),
	"forest": Vector2(-40, -6),
	"rocky": Vector2(2, 42),
	"wetland": Vector2(42, -10),
}


func _ready() -> void:
	_heightmap = FastNoiseLite.new()
	_heightmap.seed = 20261026
	_heightmap.frequency = 0.03
	_heightmap.fractal_octaves = 3
	_region_noise = FastNoiseLite.new()
	_region_noise.seed = 7
	_region_noise.frequency = 0.02
	_build_ground()
	_build_water()
	_build_landmarks()


## 地形高度函数：中心高地 + 海岸下沉 + 噪声起伏
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var land := clampf(1.0 - pow(d / RADIUS, 3.0), 0.0, 1.0)
	var h := land * 2.2 - 0.6
	h += _heightmap.get_noise_2d(x, z) * 0.9 * land
	# 北侧岩地抬升
	if z > 10.0:
		h += clampf((z - 10.0) / 40.0, 0.0, 1.0) * 2.4 * land
	# 东侧湿地压低
	if x > 18.0:
		h -= clampf((x - 18.0) / 35.0, 0.0, 1.0) * 0.8 * land
	# 出生点平台
	var beach_d := Vector2(x, z + 46.0).length()
	if beach_d < 10.0:
		h = maxf(h, 0.35)
	return h


func region_at(x: float, z: float) -> String:
	var best := "beach"
	var best_d := INF
	for id in REGION_CENTERS:
		var c: Vector2 = REGION_CENTERS[id]
		var d := Vector2(x, z).distance_to(c)
		if d < best_d:
			best_d = d
			best = id
	return best


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < -0.15


func walkable(x: float, z: float) -> bool:
	return Vector2(x, z).length() < RADIUS and height_at(x, z) > -0.15


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var n := int(RADIUS * 2.0 / step)
	var verts: Array = []
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -RADIUS + ix * step
			var z := -RADIUS + iz * step
			verts.append(Vector3(x, height_at(x, z), z))
	for iz in range(n):
		for ix in range(n):
			var i0: int = iz * (n + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + (n + 1)
			var i3 := i2 + 1
			_add_tri(st, verts[i0], verts[i2], verts[i1])
			_add_tri(st, verts[i1], verts[i2], verts[i3])
	var mesh := st.commit()
	_apply_ground_colors(mesh, verts)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


## 地形按顶点着色（每个顶点按其 xz 决定区域色），避免整面同色的斑块感。
## 直接写 ARRAY_COLOR，不使用 SurfaceTool.set_color（4.3 中按材质格式可能被丢弃）。
func _apply_ground_colors(mesh: ArrayMesh, verts: Array) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(v.size())
	for i in range(v.size()):
		colors[i] = _ground_color(v[i].x, v[i].z)
	arrays[ArrayMesh.ARRAY_COLOR] = colors
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot 以顺时针为正面：正面法线 = (c-a).cross(b-a)
	var nrm := (c - a).cross(b - a).normalized()
	if nrm.y < 0.0:
		var tmp := b
		b = c
		c = tmp
		nrm = (c - a).cross(b - a).normalized()
	var center := (a + b + c) / 3.0
	st.set_normal(nrm)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.add_vertex(b)
	st.set_normal(nrm)
	st.add_vertex(c)


func _ground_color(x: float, z: float) -> Color:
	var h := height_at(x, z)
	if h < 0.0:
		return Color("#8FA88F").lerp(Color(GameConfig.PALETTE["sea"]), clampf(-h / 1.5, 0.2, 1.0))
	if h < 0.45:
		return Color(GameConfig.PALETTE["sand"]).lerp(Color("#C7B27C"), 0.35)
	var region := region_at(x, z)
	var base: Color = Color(GameConfig.REGIONS[region]["color"])
	var n := _region_noise.get_noise_2d(x * 3.0, z * 3.0)
	base = base.lightened(0.06 * n) if n > 0.0 else base.darkened(-0.08 * n)
	if region == "beach":
		base = Color("#D8C58F")
	elif region == "wetland":
		base = base.lerp(Color("#3E5A4E"), clampf(0.35 + n * 0.3, 0.0, 0.6))
	return base


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(RADIUS * 3.0, RADIUS * 3.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(GameConfig.PALETTE["sea"])
	mat.albedo_color.a = 0.82
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.25
	mat.metallic = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, -0.05, 0)
	add_child(mi)


## 地标：出生海滩、信号点、遗迹、湿地宝箱点。提供方向参照（GDD 5.1）
const SIGNAL_POINT := Vector3(8, 0, -50)
const RITUAL_POINT := Vector3(2, 0, 40)
const CHEST_POINT := Vector3(50, 0, -22)
const SPAWN_POINT := Vector3(0, 0, -46)


func _build_landmarks() -> void:
	_add_monument(SIGNAL_POINT + Vector3(0, 0, -3), Color("#8A8F94"), "信号点", true)
	for i in range(4):
		var ang := TAU * float(i) / 4.0 + 0.4
		var p := RITUAL_POINT + Vector3(cos(ang) * 5.0, 0, sin(ang) * 5.0)
		_add_monument(Vector3(p.x, height_at(p.x, p.z), p.z), Color("#9AA0A6"), "", false)
	_add_glow_marker(SIGNAL_POINT, Color("#F2C14E"))
	_add_glow_marker(CHEST_POINT, Color("#C0392B"))


func _add_monument(p: Vector3, col: Color, label: String, is_signal: bool) -> void:
	var h := 3.2 if is_signal else 2.2
	var mi := MeshInstance3D.new()
	var mesh := LowPolyMesh.build([
		{"geo": LowPolyMesh._box(Vector3(0.7, h, 0.7), Vector3(0, h * 0.5, 0)), "color": col},
	])
	mi.mesh = mesh
	mi.position = p
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, h, 0.9)
	cs.shape = shape
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	mi.add_child(body)
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(0, h + 0.9, 0)
		l.font_size = 64
		l.pixel_size = 0.012
		l.modulate = Color("#F2C14E")
		mi.add_child(l)


func _add_glow_marker(p: Vector3, col: Color) -> void:
	var om := OmniLight3D.new()
	om.light_color = col
	om.light_energy = 1.2
	om.omni_range = 8.0
	om.position = Vector3(p.x, height_at(p.x, p.z) + 2.0, p.z)
	add_child(om)


func signal_point_position() -> Vector3:
	return Vector3(SIGNAL_POINT.x, 0.0, SIGNAL_POINT.z)

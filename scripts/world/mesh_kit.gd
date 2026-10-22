## Low-level procedural mesh helpers.
##
## NOTE ON WINDING: faces are emitted with outward vertex normals but the shared
## materials disable back-face culling, so the result is correct regardless of
## the renderer's front-face convention (Godot uses clockwise for meshes, which
## is the opposite of the math convention used to derive the normals here).
## Double-sided opaque geometry costs almost nothing: hidden back faces are
## rejected by the early depth test.
##
## The whole game ships without a single imported 3D model: geometry is built
## from boxes, prisms and cylinders at boot. That keeps the APK tiny (no glTF
## importer data, no lightmaps) and gives us exact control over triangle counts
## per quality tier.
##
## Meshes are built with SurfaceTool and baked vertex colours, so one material
## can render a whole prop or a whole street segment in a single draw call.
class_name MeshKit
extends RefCounted

## Cache so a 60-prop street segment re-uses four materials instead of 60.
static var _mat_vertex: StandardMaterial3D
static var _mat_vertex_cheap: StandardMaterial3D
static var _mat_road: StandardMaterial3D
static var _mat_sand: StandardMaterial3D
static var _mat_glass: StandardMaterial3D
static var _mat_emissive: Dictionary = {}


# ---------------------------------------------------------------------------
# Builder helpers
# ---------------------------------------------------------------------------
static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color, uv_scale: float = 0.0) -> void:
	# Winding: a-b-c / a-c-d must be counter-clockwise seen from the front.
	var normal := (b - a).cross(c - a).normalized()
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	if uv_scale > 0.0:
		uvs = [Vector2(0, 0), Vector2(uv_scale, 0), Vector2(uv_scale, uv_scale),
				Vector2(0, uv_scale)]
	for i in 2:
		var tri := [a, b, c] if i == 0 else [a, c, d]
		var tri_uv := [uvs[0], uvs[1], uvs[2]] if i == 0 else [uvs[0], uvs[2], uvs[3]]
		for k in 3:
			st.set_color(color)
			st.set_normal(normal)
			st.set_uv(tri_uv[k])
			st.add_vertex(tri[k])


static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(v)


## Axis aligned box. `center` is the middle of the box.
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color,
		uv_scale: float = 0.0) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	# -Z, +Z, -X, +X, +Y, -Y
	add_quad(st, p[0], p[1], p[2], p[3], color, uv_scale)
	add_quad(st, p[5], p[4], p[7], p[6], color, uv_scale)
	add_quad(st, p[4], p[0], p[3], p[7], color, uv_scale)
	add_quad(st, p[1], p[5], p[6], p[2], color, uv_scale)
	add_quad(st, p[3], p[2], p[6], p[7], color.darkened(0.12), uv_scale)
	add_quad(st, p[4], p[5], p[1], p[0], color.darkened(0.3), uv_scale)


## Vertical cylinder with optional top radius (cones / tapered cups).
static func add_cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float,
		color: Color, sides: int = 8, top_radius: float = -1.0) -> void:
	if top_radius < 0.0:
		top_radius = radius
	var top := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := top + Vector3(cos(a0) * top_radius, 0, sin(a0) * top_radius)
		var t1 := top + Vector3(cos(a1) * top_radius, 0, sin(a1) * top_radius)
		add_quad(st, b0, b1, t1, t0, color)
		add_tri(st, top, t0, t1, color.lightened(0.08))


## Wheel: a short cylinder lying on the X axis, handy for carts and buses.
static func add_wheel(st: SurfaceTool, center: Vector3, radius: float, width: float,
		color: Color, sides: int = 10) -> void:
	var half := width * 0.5
	for side in [-1.0, 1.0]:
		var cx: float = center.x + half * side
		var ring_prev := Vector3.ZERO
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var p := Vector3(cx, center.y + cos(a) * radius, center.z + sin(a) * radius)
			if i > 0:
				add_tri(st, center, ring_prev, p, color.darkened(0.25))
			ring_prev = p
	# Tread band.
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		var p0 := Vector3(center.x - half, center.y + cos(a0) * radius, center.z + sin(a0) * radius)
		var p1 := Vector3(center.x - half, center.y + cos(a1) * radius, center.z + sin(a1) * radius)
		var p2 := Vector3(center.x + half, center.y + cos(a1) * radius, center.z + sin(a1) * radius)
		var p3 := Vector3(center.x + half, center.y + cos(a0) * radius, center.z + sin(a0) * radius)
		add_quad(st, p0, p1, p2, p3, color)


## Flat decal lying on the ground (potholes, road paint, shadows).
static func add_ground_patch(st: SurfaceTool, center: Vector3, radius_x: float, radius_z: float,
		color: Color, segments: int = 12) -> void:
	var prev := Vector3.ZERO
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var p := center + Vector3(cos(a) * radius_x, 0, sin(a) * radius_z)
		if i > 0:
			add_tri(st, center, prev, p, color)
		prev = p


## The Sudanese flag as three bands + hoist triangle, on a plane facing -Z.
static func add_flag_panel(st: SurfaceTool, origin: Vector3, width: float, height: float,
		facing: int = 1) -> void:
	var f := float(facing)
	var z := origin.z
	var red := Color("#d21034")
	var white := Color("#ffffff")
	var black := Color("#101010")
	var green := Color("#009a00")
	var band := height / 3.0
	# Keep winding consistent for both facings.
	var x0 := origin.x
	var x1 := origin.x + width * f
	for i in 3:
		var y0 := origin.y + band * float(i)
		var y1 := y0 + band
		var col := [red, white, black][i]
		if f > 0:
			add_quad(st, Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z),
					Vector3(x0, y1, z), col)
		else:
			add_quad(st, Vector3(x1, y0, z), Vector3(x0, y0, z), Vector3(x0, y1, z),
					Vector3(x1, y1, z), col)
	# Green triangle, apex at one third of the fly.
	var apex_x := origin.x + width * f / 3.0
	if f > 0:
		add_tri(st, Vector3(x0, origin.y, z), Vector3(x0, origin.y + height, z),
				Vector3(apex_x, origin.y + height * 0.5, z), green)
	else:
		add_tri(st, Vector3(x0, origin.y + height, z), Vector3(x0, origin.y, z),
				Vector3(apex_x, origin.y + height * 0.5, z), green)


# ---------------------------------------------------------------------------
# Materials (cached)
# ---------------------------------------------------------------------------
static func vertex_material() -> StandardMaterial3D:
	if _mat_vertex == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.92
		m.metallic = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_vertex = m
	return _mat_vertex


static func vertex_material_cheap() -> StandardMaterial3D:
	if _mat_vertex_cheap == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_vertex_cheap = m
	return _mat_vertex_cheap


static func road_material() -> StandardMaterial3D:
	if _mat_road == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/asphalt.png")
		m.uv1_scale = Vector3(4.0, 26.0, 1.0)
		m.roughness = 1.0
		m.metallic = 0.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_road = m
	return _mat_road


static func sand_material() -> StandardMaterial3D:
	if _mat_sand == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/sand.png")
		m.uv1_scale = Vector3(30.0, 30.0, 1.0)
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mat_sand = m
	return _mat_sand


static func glass_material() -> StandardMaterial3D:
	if _mat_glass == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.55, 0.72, 0.78, 0.45)
		m.roughness = 0.1
		m.metallic = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_glass = m
	return _mat_glass


static func emissive_material(color: Color, energy: float = 1.4) -> StandardMaterial3D:
	var key := "%s_%.2f" % [color.to_html(), energy]
	if _mat_emissive.has(key):
		return _mat_emissive[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_emissive[key] = m
	return m

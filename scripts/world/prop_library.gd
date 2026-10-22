## Catalogue of obstacles + collectibles, with their gameplay data.
##
## Everything is generated once into shared ArrayMeshes (cached in a static
## dictionary). A hundred pooled props therefore reference seven meshes instead
## of holding a hundred copies of geometry.
class_name PropLibrary
extends RefCounted

# --- obstacle kinds --------------------------------------------------------
const BARRIER := 0      # striped road barrier  -> jump
const POTHOLE := 1      # pothole               -> jump
const CRATES := 2       # cargo crates          -> jump
const BUS := 3          # parked amjad minibus  -> change lane
const CART := 4         # karu wooden cart      -> change lane
const TABLE := 5        # vendor table          -> change lane
const LOW_BAR := 6      # low steel banner bar  -> slide
const KIND_COUNT := 7

# --- pass rules ------------------------------------------------------------
const PASS_DODGE := 0
const PASS_JUMP := 1
const PASS_SLIDE := 2

# --- cup kinds -------------------------------------------------------------
const CUP_ARADAIB := 0
const CUP_KARKADEH := 1
const CUP_GONGOLEZ := 2

const CUP_COLORS := [
	Color("#c9812f"),  # aradaib  (tamarind)
	Color("#a01834"),  # karkadeh (hibiscus)
	Color("#e6d2a8"),  # gongolez (baobab)
]

const CUP_TEXTURES := [
	"res://assets/art/cup_aradaib.png",
	"res://assets/art/cup_karkadeh.png",
	"res://assets/art/cup_gongolez.png",
]

## Gameplay metadata. `clear` is the lowest body point the player must reach to
## pass a JUMP obstacle, or the maximum height they may occupy for SLIDE.
const DATA := {
	BARRIER: {
		"pass": PASS_JUMP, "clear": 1.0, "half_width": 1.05, "depth_half": 0.35,
		"reason": "crash.barrier", "low_end": true,
	},
	POTHOLE: {
		"pass": PASS_JUMP, "clear": 0.35, "half_width": 1.15, "depth_half": 1.0,
		"reason": "crash.pothole", "low_end": true,
	},
	CRATES: {
		"pass": PASS_JUMP, "clear": 1.15, "half_width": 0.95, "depth_half": 0.6,
		"reason": "crash.crates", "low_end": false,
	},
	BUS: {
		"pass": PASS_DODGE, "clear": 0.0, "half_width": 1.2, "depth_half": 2.7,
		"reason": "crash.bus", "low_end": false,
	},
	CART: {
		"pass": PASS_DODGE, "clear": 0.0, "half_width": 1.05, "depth_half": 1.15,
		"reason": "crash.cart", "low_end": false,
	},
	TABLE: {
		"pass": PASS_DODGE, "clear": 0.0, "half_width": 1.0, "depth_half": 0.85,
		"reason": "crash.table", "low_end": false,
	},
	LOW_BAR: {
		"pass": PASS_SLIDE, "clear": 1.25, "half_width": 1.15, "depth_half": 0.3,
		"reason": "crash.bar", "low_end": false,
	},
}

static var _mesh_cache: Dictionary = {}
static var _cup_mesh_cache: Dictionary = {}
static var _cup_material_cache: Dictionary = {}

# Palette (dusk in Khartoum: warm sand, teal shutters, terracotta, flag accents).
const C := {
	"metal": Color("#8d949b"),
	"dark_metal": Color("#4a5058"),
	"red": Color("#d21034"),
	"white": Color("#f3f1ea"),
	"black": Color("#14161a"),
	"green": Color("#009a00"),
	"wood": Color("#9a6234"),
	"wood_dark": Color("#6d4324"),
	"wood_light": Color("#c08a52"),
	"sand": Color("#d8b585"),
	"sack": Color("#c9b48b"),
	"asphalt": Color("#23262a"),
	"asphalt_dark": Color("#141619"),
	"cream": Color("#efe6d4"),
	"blue": Color("#2b6fa8"),
	"teal": Color("#2c8b8b"),
	"glass": Color("#233240"),
	"orange": Color("#e08a3c"),
	"purple": Color("#6d3f83"),
}


static func info(kind: int) -> Dictionary:
	return DATA.get(kind, DATA[BARRIER])


# ---------------------------------------------------------------------------
# Obstacles
# ---------------------------------------------------------------------------
static func obstacle_mesh(kind: int) -> ArrayMesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var st := MeshKit.begin()
	match kind:
		BARRIER:
			_build_barrier(st)
		POTHOLE:
			_build_pothole(st)
		CRATES:
			_build_crates(st)
		BUS:
			_build_bus(st)
		CART:
			_build_cart(st)
		TABLE:
			_build_table(st)
		LOW_BAR:
			_build_low_bar(st)
	var mesh := st.commit()
	_mesh_cache[kind] = mesh
	return mesh


static func _build_barrier(st: SurfaceTool) -> void:
	# A-frame legs.
	for sx in [-0.92, 0.92]:
		MeshKit.add_box(st, Vector3(sx, 0.42, 0), Vector3(0.12, 0.84, 0.5), C["dark_metal"])
		MeshKit.add_box(st, Vector3(sx, 0.07, 0.02), Vector3(0.34, 0.14, 0.62), C["metal"])
	# Striped plank (red / white, the classic Khartoum road works barrier).
	var stripes := 7
	var w := 2.1 / float(stripes)
	for i in stripes:
		var x := -1.05 + w * (float(i) + 0.5)
		var col: Color = C["red"] if i % 2 == 0 else C["white"]
		MeshKit.add_box(st, Vector3(x, 0.78, 0), Vector3(w + 0.005, 0.34, 0.1), col)
	MeshKit.add_box(st, Vector3(0, 0.96, 0), Vector3(2.16, 0.06, 0.16), C["dark_metal"])
	# Little solar lamp, so the prop reads at night.
	MeshKit.add_box(st, Vector3(0, 1.08, 0), Vector3(0.26, 0.16, 0.2), C["black"])


static func _build_pothole(st: SurfaceTool) -> void:
	MeshKit.add_ground_patch(st, Vector3(0, 0.02, 0), 1.16, 1.05, C["asphalt_dark"], 14)
	MeshKit.add_ground_patch(st, Vector3(0, 0.01, 0), 1.28, 1.16, Color("#3b3d40"), 14)
	# Broken asphalt chunks around the rim.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		var p := Vector3(cos(a) * 1.15, 0.045, sin(a) * 1.0)
		MeshKit.add_box(st, p, Vector3(0.3, 0.07, 0.22), Color("#4a4c4f"))


static func _build_crates(st: SurfaceTool) -> void:
	MeshKit.add_box(st, Vector3(-0.42, 0.35, 0), Vector3(0.68, 0.7, 0.68), C["wood"])
	MeshKit.add_box(st, Vector3(0.38, 0.35, 0.05), Vector3(0.66, 0.7, 0.66), C["wood_light"])
	MeshKit.add_box(st, Vector3(-0.02, 0.92, 0.02), Vector3(0.62, 0.44, 0.6), C["wood_dark"])
	for sx in [-0.42, 0.38]:
		MeshKit.add_box(st, Vector3(sx, 0.35, 0.36), Vector3(0.7, 0.08, 0.03), C["wood_dark"])
	MeshKit.add_box(st, Vector3(0, 1.16, 0.02), Vector3(0.5, 0.05, 0.5), C["wood"])


static func _build_bus(st: SurfaceTool) -> void:
	# Khartoum "amjad": cream minibus, blue skirt, flag livery on the flanks.
	MeshKit.add_box(st, Vector3(0, 1.05, 0), Vector3(2.16, 1.5, 5.2), C["cream"])
	MeshKit.add_box(st, Vector3(0, 0.42, 0), Vector3(2.18, 0.5, 5.22), C["blue"])
	MeshKit.add_box(st, Vector3(0, 1.92, 0), Vector3(2.0, 0.28, 4.9), C["white"])
	# Windows.
	for sx in [-1.09, 1.09]:
		for i in 3:
			MeshKit.add_box(st, Vector3(sx, 1.55, -1.5 + float(i) * 1.5),
					Vector3(0.03, 0.62, 1.12), C["glass"])
	MeshKit.add_box(st, Vector3(0, 1.55, -2.61), Vector3(1.82, 0.66, 0.04), C["glass"])
	MeshKit.add_box(st, Vector3(0, 1.5, 2.62), Vector3(1.7, 0.5, 0.04), C["glass"])
	# Flag bands along both sides (red / white / black) + green hoist triangle.
	for sx in [-1.1, 1.1]:
		var facing := 1.0 if sx > 0.0 else -1.0
		var x := sx
		var z0 := 2.4
		var length := 4.4
		_side_band(st, x, 0.95, z0, length, 0.13, C["red"], facing)
		_side_band(st, x, 1.08, z0, length, 0.13, C["white"], facing)
		_side_band(st, x, 1.21, z0, length, 0.13, C["black"], facing)
		_side_tri(st, x, 0.95, z0, 1.5, 0.39, C["green"], facing)
	# Wheels, bumpers, lights.
	for wz in [-1.75, 1.75]:
		for wx in [-1.0, 1.0]:
			MeshKit.add_wheel(st, Vector3(wx, 0.46, wz), 0.46, 0.28, C["black"], 10)
	MeshKit.add_box(st, Vector3(0, 0.35, 2.66), Vector3(2.1, 0.22, 0.14), C["dark_metal"])
	MeshKit.add_box(st, Vector3(0, 0.35, -2.66), Vector3(2.1, 0.22, 0.14), C["dark_metal"])
	for lx in [-0.78, 0.78]:
		MeshKit.add_box(st, Vector3(lx, 0.72, -2.66), Vector3(0.3, 0.18, 0.06), Color("#ffe9b0"))
	# Roof rack with luggage.
	MeshKit.add_box(st, Vector3(0, 2.09, 0.4), Vector3(1.7, 0.12, 2.6), C["wood"])
	MeshKit.add_box(st, Vector3(-0.35, 2.3, 0.2), Vector3(0.7, 0.34, 0.9), C["teal"])
	MeshKit.add_box(st, Vector3(0.45, 2.26, 1.0), Vector3(0.6, 0.26, 0.7), C["orange"])


static func _build_cart(st: SurfaceTool) -> void:
	# Karu: hand cart with two big wooden wheels, piled with sacks.
	MeshKit.add_box(st, Vector3(0, 0.62, 0), Vector3(1.7, 0.14, 2.1), C["wood"])
	for sx in [-0.8, 0.8]:
		MeshKit.add_box(st, Vector3(sx, 0.78, 0), Vector3(0.08, 0.32, 2.1), C["wood_dark"])
	MeshKit.add_box(st, Vector3(0, 0.86, -1.12), Vector3(1.6, 0.36, 0.08), C["wood_light"])
	MeshKit.add_wheel(st, Vector3(-0.92, 0.58, 0.1), 0.58, 0.14, C["wood_dark"], 12)
	MeshKit.add_wheel(st, Vector3(0.92, 0.58, 0.1), 0.58, 0.14, C["wood_dark"], 12)
	# Handles.
	MeshKit.add_box(st, Vector3(0, 0.86, 1.35), Vector3(1.3, 0.08, 0.1), C["wood"])
	MeshKit.add_box(st, Vector3(0, 0.8, 1.75), Vector3(0.1, 0.1, 0.9), C["wood"])
	# Cargo: sacks of onions + a watermelon pyramid.
	for i in 3:
		MeshKit.add_box(st, Vector3(-0.4 + float(i) * 0.4, 0.95, -0.3 + float(i % 2) * 0.35),
				Vector3(0.36, 0.34, 0.34), C["sack"])
	MeshKit.add_box(st, Vector3(0.0, 1.2, -0.2), Vector3(0.34, 0.3, 0.34), C["sack"])
	for i in 3:
		MeshKit.add_box(st, Vector3(-0.35 + float(i) * 0.35, 0.82, 0.6),
				Vector3(0.3, 0.28, 0.3), Color("#2f6b34"))


static func _build_table(st: SurfaceTool) -> void:
	# Street vendor stall: table, goods and a striped canopy.
	MeshKit.add_box(st, Vector3(0, 0.78, 0), Vector3(1.9, 0.1, 1.2), C["wood_light"])
	for sx in [-0.85, 0.85]:
		for sz in [-0.5, 0.5]:
			MeshKit.add_box(st, Vector3(sx, 0.38, sz), Vector3(0.08, 0.76, 0.08), C["wood_dark"])
	# Goods: stacked cups and fruit.
	for i in 4:
		MeshKit.add_box(st, Vector3(-0.7 + float(i) * 0.45, 0.9, -0.2),
				Vector3(0.24, 0.16, 0.24), C["orange"] if i % 2 == 0 else C["red"])
	MeshKit.add_box(st, Vector3(0.55, 0.92, 0.28), Vector3(0.5, 0.18, 0.4), C["teal"])
	# Poles + canopy.
	for sx in [-0.95, 0.95]:
		for sz in [-0.6, 0.6]:
			MeshKit.add_box(st, Vector3(sx, 1.3, sz), Vector3(0.06, 1.8, 0.06), C["metal"])
	MeshKit.add_box(st, Vector3(0, 2.18, 0), Vector3(2.3, 0.08, 1.6), C["white"])
	for i in 5:
		MeshKit.add_box(st, Vector3(-1.0 + float(i) * 0.5, 2.13, 0.0),
				Vector3(0.25, 0.02, 1.62), C["green"] if i % 2 == 0 else C["red"])
	MeshKit.add_box(st, Vector3(0, 2.02, 0.8), Vector3(2.3, 0.3, 0.05), C["red"])


static func _build_low_bar(st: SurfaceTool) -> void:
	# Steel posts either side + a low banner you have to slide under.
	for sx in [-1.12, 1.12]:
		MeshKit.add_box(st, Vector3(sx, 0.95, 0), Vector3(0.11, 1.9, 0.11), C["metal"])
		MeshKit.add_box(st, Vector3(sx, 0.05, 0), Vector3(0.3, 0.1, 0.3), C["dark_metal"])
	MeshKit.add_box(st, Vector3(0, 1.62, 0), Vector3(2.3, 0.1, 0.1), C["dark_metal"])
	# Flag coloured banner hanging from the bar, clearance ~1.25 m.
	for i in 3:
		var col: Color = [C["red"], C["white"], C["black"]][i]
		MeshKit.add_box(st, Vector3(0, 1.42 - float(i) * 0.1, 0.0),
				Vector3(2.16, 0.1, 0.03), col)
	MeshKit.add_box(st, Vector3(-0.72, 1.34, 0.0), Vector3(0.7, 0.32, 0.03), C["green"])


# --- small helpers ---------------------------------------------------------
## Horizontal band on the side of a vehicle; `z0` is the +Z end, extends to -Z.
static func _side_band(st: SurfaceTool, x: float, y: float, z0: float, length: float,
		height: float, color: Color, facing: float) -> void:
	var z1 := z0 - length
	var y1 := y + height * 0.5
	var y0 := y - height * 0.5
	if facing > 0.0:
		MeshKit.add_quad(st, Vector3(x, y0, z1), Vector3(x, y0, z0), Vector3(x, y1, z0),
				Vector3(x, y1, z1), color)
	else:
		MeshKit.add_quad(st, Vector3(x, y0, z0), Vector3(x, y0, z1), Vector3(x, y1, z1),
				Vector3(x, y1, z0), color)


static func _side_tri(st: SurfaceTool, x: float, y: float, z0: float, length: float,
		height: float, color: Color, facing: float) -> void:
	var z1 := z0 - length
	if facing > 0.0:
		MeshKit.add_tri(st, Vector3(x, y, z0), Vector3(x, y, z1),
				Vector3(x, y + height * 0.5, z0 - length * 0.5), color)
	else:
		MeshKit.add_tri(st, Vector3(x, y, z1), Vector3(x, y, z0),
				Vector3(x, y + height * 0.5, z0 - length * 0.5), color)


# ---------------------------------------------------------------------------
# Collectibles (traditional Sudanese drink cups)
# ---------------------------------------------------------------------------
static func cup_mesh(kind: int) -> ArrayMesh:
	if _cup_mesh_cache.has(kind):
		return _cup_mesh_cache[kind]
	var st := MeshKit.begin()
	var liquid: Color = CUP_COLORS[kind % CUP_COLORS.size()]
	# Glass.
	MeshKit.add_cylinder(st, Vector3.ZERO, 0.17, 0.42, Color("#dceef2"), 10, 0.2)
	# Liquid.
	MeshKit.add_cylinder(st, Vector3(0, 0.04, 0), 0.155, 0.32, liquid, 10, 0.18)
	# Rim + straw.
	MeshKit.add_cylinder(st, Vector3(0, 0.42, 0), 0.2, 0.03, Color("#f2fbff"), 10)

	var mesh := st.commit()
	_cup_mesh_cache[kind] = mesh
	return mesh


static func cup_sprite_material(kind: int) -> StandardMaterial3D:
	var key := kind % CUP_TEXTURES.size()
	if _cup_material_cache.has(key):
		return _cup_material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(CUP_TEXTURES[key])
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.no_depth_test = false
	_cup_material_cache[key] = m
	return m

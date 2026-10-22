## Procedural street segments.
##
## Each segment is a single MeshInstance3D with three surfaces (road, scenery,
## ground). Rebuilding a 40 m chunk costs ~2 ms, and it only happens when a
## chunk is recycled, i.e. once every ~2 seconds per chunk - never during a
## frame that also runs gameplay logic.
##
## Variants:
##   0 KHARTOUM STREET  - shopfronts, acacias, lamps, parked cars
##   1 MARKET LANE      - vendor stalls, crates, canopies, hanging bulbs
##   2 NILE CORNICHE    - river on one side, railing, palms
##   3 NEIGHBOURHOOD    - mud brick walls, gates, water tanks, laundry
##   4 BLUE NILE BRIDGE - water on both sides, steel railings, flag banners
class_name SegmentBuilder
extends RefCounted

const LENGTH := 40.0
const ROAD_HALF := 4.2          # asphalt half width (3 lanes * 2.4 m + shoulders)
const WALK := 1.7               # sidewalk width
const INNER := ROAD_HALF + WALK # where buildings start

const VARIANT_COUNT := 5
const CACHE_SLOTS := 3          # three mesh variants per layout for variety

const PALETTE := {
	"wall_a": Color("#d9b98c"),
	"wall_b": Color("#cdc3ae"),
	"wall_c": Color("#b98663"),
	"wall_d": Color("#9daf9b"),
	"wall_mud": Color("#b48a5e"),
	"roof": Color("#8e7b63"),
	"shutter": Color("#2c8b8b"),
	"wood": Color("#9a6234"),
	"wood_dark": Color("#6d4324"),
	"metal": Color("#8d949b"),
	"dark": Color("#2a2d31"),
	"white": Color("#f1ece1"),
	"red": Color("#d21034"),
	"green": Color("#009a00"),
	"black": Color("#14161a"),
	"gold": Color("#f2b705"),
	"leaf": Color("#3f6b3a"),
	"leaf_dark": Color("#2c5129"),
	"palm": Color("#4f7a3f"),
	"water": Color("#2c5566"),
	"stone": Color("#a89b86"),
	"cloth_a": Color("#e08a3c"),
	"cloth_b": Color("#6d3f83"),
	"cloth_c": Color("#2b6fa8"),
	"sand": Color("#cba978"),
	"sack": Color("#c9b48b"),
	"clay": Color("#c0522c"),
}

static var _cache: Dictionary = {}


## Returns a mesh with surface 0 = road, 1 = scenery, 2 = sand ground.
static func build(variant: int, slot: int, density: float) -> ArrayMesh:
	var key := "%d_%d_%.2f" % [variant, slot, density]
	if _cache.has(key):
		return _cache[key]

	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (slot + 1) + 104729 * variant

	var road := MeshKit.begin()
	var art := MeshKit.begin()
	var ground := MeshKit.begin()

	_build_ground(ground)
	_build_road(road, rng)
	_build_walkways(art)

	match variant % VARIANT_COUNT:
		0:
			_build_street(art, rng, density)
		1:
			_build_market(art, rng, density)
		2:
			_build_corniche(art, rng, density)
		3:
			_build_neighbourhood(art, rng, density)
		_:
			_build_bridge(art, rng, density)

	_build_flags(art, rng, density)

	var mesh := road.commit()
	art.commit(mesh)
	ground.commit(mesh)
	_cache[key] = mesh
	return mesh


static func clear_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------------------
# Ground / road
# ---------------------------------------------------------------------------
static func _build_ground(st: SurfaceTool) -> void:
	var h := LENGTH * 0.5
	MeshKit.add_quad(st, Vector3(-160, -0.06, h), Vector3(160, -0.06, h),
			Vector3(160, -0.06, -h), Vector3(-160, -0.06, -h), Color.WHITE, 14.0)


static func _build_road(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var h := LENGTH * 0.5
	# Main asphalt slab.
	MeshKit.add_quad(st, Vector3(-ROAD_HALF, 0, h), Vector3(ROAD_HALF, 0, h),
			Vector3(ROAD_HALF, 0, -h), Vector3(-ROAD_HALF, 0, -h), Color.WHITE, 1.0)
	# Dashed lane dividers between the three lanes (x = +-1.2).
	var paint := Color("#e8e3d3")
	var z := -h
	while z < h:
		for lane_edge: float in [-1.2, 1.2]:
			_add_flat_box(st, Vector3(lane_edge, 0.03, z + 1.5), Vector3(0.16, 0.012, 2.6),
					paint)
		z += 5.6
	# Occasional crosswalk / speed bump paint for rhythm.
	if rng.randf() < 0.5:
		var cz := rng.randf_range(-h + 6.0, h - 6.0)
		for i in 7:
			_add_flat_box(st, Vector3(-3.6 + float(i) * 1.2, 0.013, cz),
					Vector3(0.55, 0.01, 1.8), paint)
	# Sand drifts on the shoulder (Khartoum streets are never fully clean).
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var px := side * rng.randf_range(3.4, ROAD_HALF - 0.3)
		var pz := rng.randf_range(-h, h)
		_add_flat_box(st, Vector3(px, 0.008, pz),
				Vector3(rng.randf_range(0.6, 1.6), 0.006, rng.randf_range(0.8, 2.4)),
				PALETTE["sand"])


static func _build_walkways(st: SurfaceTool) -> void:
	var h := LENGTH * 0.5
	var concrete := Color("#b9b3a6")
	var curb := Color("#e4ded0")
	for side: float in [-1.0, 1.0]:
		var x_in := side * ROAD_HALF
		var x_out := side * INNER
		MeshKit.add_quad(st, Vector3(x_in, 0.16, h), Vector3(x_out, 0.16, h),
				Vector3(x_out, 0.16, -h), Vector3(x_in, 0.16, -h), concrete)
		# Curb face toward the road.
		MeshKit.add_quad(st, Vector3(x_in, 0.0, h), Vector3(x_in, 0.16, h),
				Vector3(x_in, 0.16, -h), Vector3(x_in, 0.0, -h), curb)
		# Sidewalk edge strip.
		_add_flat_box(st, Vector3(x_out - side * 0.18, 0.17, 0), Vector3(0.34, 0.02, LENGTH),
				Color("#9c968a"))


# ---------------------------------------------------------------------------
# Variant 0: Khartoum street
# ---------------------------------------------------------------------------
static func _build_street(st: SurfaceTool, rng: RandomNumberGenerator, density: float) -> void:
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5 - 3.0:
			var span := rng.randf_range(7.0, 12.0)
			var skip := density < 0.75 and rng.randf() < 0.35
			if not skip:
				_building(st, rng, side, z + span * 0.5, span)
			z += span + rng.randf_range(0.5, 2.5)
		# Street furniture along the curb.
		for i in 3:
			var fz := -LENGTH * 0.5 + 6.0 + float(i) * 12.0 + rng.randf_range(-2.0, 2.0)
			_lamp(st, side, fz)
			if rng.randf() < 0.7:
				_acacia(st, side * (INNER + 1.4), fz + 4.0, rng)
			if rng.randf() < 0.5 * density:
				_parked_car(st, side, fz + 6.5, rng)
		if rng.randf() < 0.5:
			_shop_awning(st, side, rng.randf_range(-14.0, 14.0), rng)


static func _building(st: SurfaceTool, rng: RandomNumberGenerator, side: float,
		z_center: float, z_span: float) -> void:
	var depth := rng.randf_range(5.0, 9.0)
	var height := rng.randf_range(4.0, 12.0)
	var colors := [PALETTE["wall_a"], PALETTE["wall_b"], PALETTE["wall_c"], PALETTE["wall_d"]]
	var wall: Color = colors[rng.randi_range(0, colors.size() - 1)]
	var x_inner: float = side * INNER
	var x_center: float = x_inner + side * depth * 0.5
	var body := Vector3(x_center, height * 0.5 + 0.16, z_center)

	MeshKit.add_box(st, body, Vector3(depth, height, z_span), wall)
	# Parapet + roof furniture.
	MeshKit.add_box(st, Vector3(x_center, height + 0.16 + 0.18, z_center),
			Vector3(depth + 0.2, 0.36, z_span + 0.2), wall.darkened(0.12))
	MeshKit.add_box(st, Vector3(x_center + side * 1.2, height + 0.7, z_center + 1.0),
			Vector3(1.1, 0.9, 1.1), PALETTE["roof"])
	MeshKit.add_cylinder(st, Vector3(x_center - side * 1.6, height + 0.34, z_center - 1.4),
			0.45, 1.0, Color("#5f5f5f"), 8)

	# Facade: windows + shutters on the inner face.
	var face_x: float = x_inner + side * 0.03
	var rows := int(maxf(1.0, floor((height - 2.6) / 2.6)))
	for row in rows:
		var wy := 2.6 + float(row) * 2.6
		if wy > height - 1.2:
			break
		var cols := int(maxf(1.0, floor(z_span / 2.6)))
		for col in cols:
			var wz := z_center - z_span * 0.5 + 1.5 + float(col) * 2.6
			if wz > z_center + z_span * 0.5 - 0.8:
				break
			MeshKit.add_box(st, Vector3(face_x, wy, wz), Vector3(0.1, 1.25, 1.15),
					PALETTE["dark"])
			if rng.randf() < 0.5:
				MeshKit.add_box(st, Vector3(face_x + side * 0.06, wy, wz),
						Vector3(0.06, 1.35, 0.2), PALETTE["shutter"])
	# Ground floor shop: dark opening + awning bars.
	MeshKit.add_box(st, Vector3(face_x, 1.35, z_center), Vector3(0.12, 2.3, z_span * 0.6),
			Color("#1b1e22"))


static func _shop_awning(st: SurfaceTool, side: float, z: float,
		rng: RandomNumberGenerator) -> void:
	var col: Color = [PALETTE["cloth_a"], PALETTE["cloth_c"], PALETTE["green"]][
			rng.randi_range(0, 2)]
	var x := side * (INNER + 0.9)
	for i in 4:
		MeshKit.add_box(st, Vector3(x - side * float(i) * 0.55, 3.2 - float(i) * 0.12, z),
				Vector3(0.55, 0.06, 3.4), col if i % 2 == 0 else PALETTE["white"])


static func _lamp(st: SurfaceTool, side: float, z: float) -> void:
	var x: float = side * (ROAD_HALF + 1.1)
	MeshKit.add_cylinder(st, Vector3(x, 0.16, z), 0.11, 5.4, PALETTE["metal"], 6)
	MeshKit.add_box(st, Vector3(x - side * 0.8, 5.5, z), Vector3(1.7, 0.12, 0.12),
			PALETTE["metal"])
	MeshKit.add_box(st, Vector3(x - side * 1.5, 5.36, z), Vector3(0.55, 0.18, 0.34),
			Color("#ffe6a8"))
	MeshKit.add_box(st, Vector3(x, 0.2, z), Vector3(0.36, 0.3, 0.36), PALETTE["dark"])


static func _acacia(st: SurfaceTool, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(2.6, 3.8)
	MeshKit.add_cylinder(st, Vector3(x, 0.16, z), 0.16, h, Color("#5a4530"), 5, 0.11)
	var canopy_w := rng.randf_range(3.2, 5.0)
	MeshKit.add_box(st, Vector3(x, h + 0.55, z), Vector3(canopy_w, 0.55, canopy_w * 0.9),
			PALETTE["leaf"])
	MeshKit.add_box(st, Vector3(x + 0.5, h + 1.0, z - 0.4),
			Vector3(canopy_w * 0.6, 0.4, canopy_w * 0.55), PALETTE["leaf_dark"])


static func _parked_car(st: SurfaceTool, side: float, z: float,
		rng: RandomNumberGenerator) -> void:
	var x: float = side * (ROAD_HALF - 0.9)
	var body: Color = [Color("#c8c9c2"), Color("#8fa7b8"), Color("#c07a52")][
			rng.randi_range(0, 2)]
	MeshKit.add_box(st, Vector3(x, 0.55, z), Vector3(1.8, 0.62, 4.0), body)
	MeshKit.add_box(st, Vector3(x, 1.02, z + 0.2), Vector3(1.6, 0.5, 2.1), body.darkened(0.08))
	MeshKit.add_box(st, Vector3(x, 1.02, z + 0.2), Vector3(1.64, 0.34, 1.9), PALETTE["dark"])
	for wz: float in [-1.3, 1.3]:
		for wx: float in [-0.82, 0.82]:
			MeshKit.add_wheel(st, Vector3(x + wx, 0.36, z + wz), 0.36, 0.22, PALETTE["black"], 8)


# ---------------------------------------------------------------------------
# Variant 1: market lane
# ---------------------------------------------------------------------------
static func _build_market(st: SurfaceTool, rng: RandomNumberGenerator, density: float) -> void:
	for side: float in [-1.0, 1.0]:
		# A low back wall so stalls read against something solid.
		MeshKit.add_box(st, Vector3(side * (INNER + 3.2), 2.2, 0),
				Vector3(6.0, 4.4, LENGTH), PALETTE["wall_b"].darkened(0.05))
		var z := -LENGTH * 0.5 + 3.0
		while z < LENGTH * 0.5 - 3.0:
			if rng.randf() < density:
				_stall(st, side, z, rng)
			z += rng.randf_range(7.0, 10.0)
		for i in 4:
			_acacia(st, side * (INNER + 0.6), -LENGTH * 0.5 + 5.0 + float(i) * 10.0, rng)
	# Hanging bulb strings across the lane (very Khartoum souq). They sit at
	# 7 m - above the 4.5 m chase camera - so bulbs never fill the lens.
	for i in 5:
		var z := -LENGTH * 0.5 + 4.0 + float(i) * 8.0
		MeshKit.add_box(st, Vector3(0, 7.4, z), Vector3(9.0, 0.05, 0.05), PALETTE["dark"])
		for k in 5:
			var lx := -3.6 + float(k) * 1.8
			MeshKit.add_box(st, Vector3(lx, 7.2, z), Vector3(0.16, 0.24, 0.16),
					Color("#ffd88a"))


static func _stall(st: SurfaceTool, side: float, z: float,
		rng: RandomNumberGenerator) -> void:
	var x: float = side * (INNER - 0.6)
	var cloth: Color = [PALETTE["cloth_a"], PALETTE["cloth_b"], PALETTE["cloth_c"],
			PALETTE["green"], PALETTE["red"]][rng.randi_range(0, 4)]
	# Counter + legs.
	MeshKit.add_box(st, Vector3(x, 0.82, z), Vector3(1.9, 0.12, 2.6), PALETTE["wood"])
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-1.1, 1.1]:
			MeshKit.add_box(st, Vector3(x + sx, 0.45, z + sz), Vector3(0.1, 0.78, 0.1),
					PALETTE["wood_dark"])
	# Canopy on poles.
	for sx: float in [-0.95, 0.95]:
		for sz: float in [-1.25, 1.25]:
			MeshKit.add_box(st, Vector3(x + sx, 1.4, z + sz), Vector3(0.07, 2.2, 0.07),
					PALETTE["metal"])
	MeshKit.add_box(st, Vector3(x, 2.5, z), Vector3(2.4, 0.1, 3.0), cloth)
	MeshKit.add_box(st, Vector3(x - side * 0.9, 2.32, z), Vector3(0.9, 0.06, 3.0),
			cloth.darkened(0.18))
	# Goods: crates, sacks, spice bowls.
	for i in 3:
		MeshKit.add_box(st, Vector3(x - 0.4 + float(i) * 0.45, 0.98, z + 0.9),
				Vector3(0.36, 0.24, 0.36), PALETTE["wood"])
	MeshKit.add_box(st, Vector3(x + 0.1, 0.95, z - 0.7), Vector3(0.7, 0.26, 0.5),
			PALETTE["sack"])
	MeshKit.add_cylinder(st, Vector3(x - 0.7, 0.9, z - 0.5), 0.22, 0.16,
			PALETTE["clay"], 8)


# ---------------------------------------------------------------------------
# Variant 2: Nile corniche
# ---------------------------------------------------------------------------
static func _build_corniche(st: SurfaceTool, rng: RandomNumberGenerator,
		density: float) -> void:
	# River to the left, city to the right.
	_water(st, -1.0)
	for side: float in [1.0]:
		_wall_row(st, side, rng, density)
	# Corniche railing + palms on the river side.
	var z := -LENGTH * 0.5 + 2.0
	while z < LENGTH * 0.5:
		_railing(st, -1.0, z, 2.0, 1.05)
		if rng.randf() < density:
			_palm(st, Vector3(-(INNER + 0.4), 0.16, z + 1.0), rng)
		z += 3.0
	for i in 2:
		_lamp(st, 1.0, -LENGTH * 0.5 + 10.0 + float(i) * 18.0)
	# Small moored boat silhouette in the water for storytelling.
	if rng.randf() < 0.6:
		var bz := rng.randf_range(-12.0, 12.0)
		MeshKit.add_box(st, Vector3(-14.0, 0.2, bz), Vector3(3.4, 0.35, 1.2),
				Color("#5c4a36"))
		MeshKit.add_box(st, Vector3(-14.0, 0.6, bz), Vector3(1.2, 0.6, 0.8),
				Color("#8d949b"))


static func _wall_row(st: SurfaceTool, side: float, rng: RandomNumberGenerator,
		density: float) -> void:
	var z := -LENGTH * 0.5
	while z < LENGTH * 0.5 - 4.0:
		var span := rng.randf_range(9.0, 14.0)
		if rng.randf() < 0.85 * maxf(density, 0.6):
			_building(st, rng, side, z + span * 0.5, span)
		z += span + rng.randf_range(2.0, 4.0)


static func _water(st: SurfaceTool, side: float) -> void:
	var h := LENGTH * 0.5
	var x0: float = side * (INNER + 0.1)
	var x1: float = side * 80.0
	MeshKit.add_quad(st, Vector3(x0, -1.55, h), Vector3(x1, -1.55, h),
			Vector3(x1, -1.55, -h), Vector3(x0, -1.55, -h), PALETTE["water"])
	# Embankment wall.
	var wx: float = side * (INNER + 0.05)
	MeshKit.add_quad(st, Vector3(wx, -1.6, h), Vector3(wx, 0.1, h), Vector3(wx, 0.1, -h),
			Vector3(wx, -1.6, -h), PALETTE["stone"])


static func _railing(st: SurfaceTool, side: float, z: float, span: float, height: float) -> void:
	var x: float = side * (INNER - 0.25)
	MeshKit.add_box(st, Vector3(x, 0.16 + height, z), Vector3(0.08, 0.08, span),
			PALETTE["white"])
	MeshKit.add_box(st, Vector3(x, 0.16 + height * 0.55, z), Vector3(0.06, 0.06, span),
			PALETTE["metal"])
	for i in 3:
		MeshKit.add_box(st, Vector3(x, 0.16 + height * 0.5, z - span * 0.5 + float(i) * span * 0.5),
				Vector3(0.07, height, 0.07), PALETTE["white"])


static func _palm(st: SurfaceTool, base: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(5.0, 7.5)
	MeshKit.add_cylinder(st, base, 0.22, h, Color("#7a6142"), 6, 0.14)
	for i in 7:
		var a := TAU * float(i) / 7.0
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := base + Vector3(0, h, 0) + dir * 1.1 + Vector3(0, 0.35, 0)
		var tip := base + Vector3(0, h, 0) + dir * 2.4 + Vector3(0, -0.5, 0)
		var perp := Vector3(-dir.z, 0.35, dir.x) * 0.45
		MeshKit.add_quad(st, mid - perp, mid + perp, tip + perp * 0.25, tip - perp * 0.25,
				PALETTE["palm"])
	MeshKit.add_box(st, base + Vector3(0, h - 0.2, 0), Vector3(0.5, 0.5, 0.5),
			PALETTE["leaf_dark"])


# ---------------------------------------------------------------------------
# Variant 3: dusty neighbourhood
# ---------------------------------------------------------------------------
static func _build_neighbourhood(st: SurfaceTool, rng: RandomNumberGenerator,
		density: float) -> void:
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5 - 6.0:
			var span := rng.randf_range(8.0, 13.0)
			_compound_wall(st, side, z + span * 0.5, span, rng)
			z += span + rng.randf_range(1.5, 4.0)
		for i in 3:
			var fz := -LENGTH * 0.5 + 5.0 + float(i) * 12.0 + rng.randf_range(-2.0, 2.0)
			_acacia(st, side * (ROAD_HALF + 1.0), fz, rng)
			if rng.randf() < density:
				_lamp(st, side, fz + 5.0)
		# Laundry lines between the walls.
		for i in 2:
			var lz := -LENGTH * 0.5 + 8.0 + float(i) * 16.0
			var x: float = side * (INNER + 0.6)
			MeshKit.add_box(st, Vector3(x, 2.9, lz), Vector3(0.05, 0.05, 6.0), PALETTE["dark"])
			for k in 4:
				var col: Color = [PALETTE["red"], PALETTE["white"], PALETTE["green"],
						PALETTE["cloth_c"]][k % 4]
				MeshKit.add_box(st, Vector3(x, 2.5, lz - 2.2 + float(k) * 1.5),
						Vector3(0.04, 0.8, 0.7), col)


static func _compound_wall(st: SurfaceTool, side: float, z_center: float, z_span: float,
		rng: RandomNumberGenerator) -> void:
	var x: float = side * (INNER + 0.35)
	var h := rng.randf_range(2.0, 2.8)
	MeshKit.add_box(st, Vector3(x, h * 0.5 + 0.16, z_center), Vector3(0.45, h, z_span),
			PALETTE["wall_mud"])
	# Gate + painted trim - the visual signature of a Sudanese house.
	MeshKit.add_box(st, Vector3(x, 1.2, z_center), Vector3(0.52, 2.2, 2.4),
			Color("#3c2f26"))
	MeshKit.add_box(st, Vector3(x, 1.55, z_center), Vector3(0.56, 0.14, 2.5),
			PALETTE["gold"])
	MeshKit.add_box(st, Vector3(x, h + 0.28, z_center), Vector3(0.55, 0.2, z_span),
			PALETTE["wall_mud"].darkened(0.15))
	# House behind the wall.
	var house_h := rng.randf_range(3.0, 5.5)
	var house_x: float = x + side * 3.5
	MeshKit.add_box(st, Vector3(house_x, house_h * 0.5 + 0.16, z_center),
			Vector3(6.0, house_h, z_span * 0.8), PALETTE["wall_a"])
	MeshKit.add_box(st, Vector3(house_x, house_h + 0.3, z_center),
			Vector3(6.2, 0.3, z_span * 0.8), PALETTE["roof"])
	for i in 3:
		MeshKit.add_box(st, Vector3(house_x + side * 3.05, 1.9 + float(i % 2) * 1.6,
				z_center - z_span * 0.25 + float(i) * 1.4), Vector3(0.1, 0.9, 0.8),
				PALETTE["dark"])
	# Water tank on the roof.
	MeshKit.add_cylinder(st, Vector3(house_x - side * 1.5, house_h + 0.4, z_center + 1.0),
			0.7, 1.2, Color("#2f2f33"), 8)


# ---------------------------------------------------------------------------
# Variant 4: Blue Nile bridge
# ---------------------------------------------------------------------------
static func _build_bridge(st: SurfaceTool, rng: RandomNumberGenerator,
		density: float) -> void:
	for side: float in [-1.0, 1.0]:
		_water(st, side)
		var x: float = side * (INNER - 0.2)
		# Stone parapet + steel railing.
		MeshKit.add_box(st, Vector3(x, 0.45, 0), Vector3(0.6, 0.6, LENGTH), PALETTE["stone"])
		MeshKit.add_box(st, Vector3(x, 0.95, 0), Vector3(0.5, 0.06, LENGTH), PALETTE["white"])
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5:
			_railing(st, side, z + 1.5, 3.0, 1.0)
			z += 3.0
	# Overhead flag banners - signature shot for the trailer.
	for i in 3:
		var bz := -LENGTH * 0.5 + 6.0 + float(i) * 13.0
		for side: float in [-1.0, 1.0]:
			MeshKit.add_box(st, Vector3(side * (INNER - 0.3), 3.2, bz),
					Vector3(0.18, 6.0, 0.18), PALETTE["metal"])
		MeshKit.add_box(st, Vector3(0, 6.0, bz), Vector3((INNER - 0.3) * 2.0, 0.1, 0.1),
				PALETTE["metal"])
		var flag_w := 2.6
		for k in 3:
			var fx := -2.6 + float(k) * 2.6
			MeshKit.add_flag_panel(st, Vector3(fx - flag_w * 0.5, 4.0, bz), flag_w, 1.7)


# ---------------------------------------------------------------------------
# Shared flourishes
# ---------------------------------------------------------------------------
static func _build_flags(st: SurfaceTool, rng: RandomNumberGenerator, density: float) -> void:
	# Sudanese flags on the sidewalk make the theme unmistakable.
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5 + 4.0 + rng.randf_range(0.0, 6.0)
		while z < LENGTH * 0.5 - 2.0:
			if rng.randf() < 0.55 * maxf(density, 0.4):
				var x: float = side * (INNER - 0.6)
				MeshKit.add_cylinder(st, Vector3(x, 0.16, z), 0.07, 3.4,
						PALETTE["metal"], 5)
				MeshKit.add_flag_panel(st, Vector3(x, 2.2, z + 0.05), 1.4, 0.95)
			z += rng.randf_range(9.0, 16.0)


static func _add_flat_box(st: SurfaceTool, center: Vector3, size: Vector3,
		color: Color) -> void:
	MeshKit.add_box(st, center, size, color)

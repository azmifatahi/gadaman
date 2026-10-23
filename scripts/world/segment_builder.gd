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
##   4 MAC NIMIR BRIDGE - riveted steel truss, concrete piers, open Nile
##   5 SHAMBAT BRIDGE   - concrete beam deck, tall piers, river haze
##   6 OLD BAHRI        - two-storey colonial shopfronts, balconies, laundry
##
## Surfaces (v1.3.0): every segment is a mesh whose surfaces are described by
## the meta key "surfaces", so TrackSegment can bind the right material to the
## right index without hard-coding numbers. Photographic surfaces (road,
## pavement, facades, water, steel, concrete) carry world-space UVs; the
## remaining "art" surface still uses cheap vertex colours for small props.
class_name SegmentBuilder
extends RefCounted

const LENGTH := 40.0
const ROAD_HALF := 4.2          # asphalt half width (3 lanes * 2.4 m + shoulders)
const WALK := 1.7               # sidewalk width
const INNER := ROAD_HALF + WALK # where buildings start

const VARIANT_COUNT := 7
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

## --- Warm-up / stall guard --------------------------------------------------
## Building one district means ten SurfaceTool passes, ten `commit()` calls and
## a surface copy each: 5-30 ms on a desktop, and a *visible freeze* on a cheap
## phone. It used to run the first time a layout appeared, which for the
## landmark districts is 250 m (Bahri), 400 m (Mac Nimir) and 650 m (Shambat)
## into the run - the exact "the game hangs after a distance" report. Everything
## is therefore built up-front at boot (`warm_all`) and `run_guard` turns any
## build that still happens mid-run into a countable bug instead of a hitch.
static var build_count: int = 0
static var builds_in_run: int = 0
static var build_ms_total: float = 0.0
static var run_guard: bool = false

## Surface order used by every segment mesh. TrackSegment maps these names to
## materials; adding a surface here is all it takes to give the street a new
## photographic material.
const SURFACES := ["road", "walk", "art", "ground", "facade", "facade_b",
	"facade_c", "water", "steel", "concrete", "leaf", "leaves"]


## Cache identity of one built district. The variant is normalised first so a
## caller can pass any integer (a district id, an rng roll) without growing the
## cache with duplicates.
static func cache_key(variant: int, slot: int, density: float) -> String:
	variant = posmod(variant, VARIANT_COUNT)
	slot = posmod(slot, CACHE_SLOTS)
	return "%d_%d_%.2f" % [variant, slot, density]


static func has(variant: int, slot: int, density: float) -> bool:
	return _cache.has(cache_key(posmod(variant, VARIANT_COUNT),
			posmod(slot, CACHE_SLOTS), density))


## Builds every (layout, cache slot) pair for one density and returns how many
## meshes were actually created. Call it once the hardware tier is known: after
## this, `build()` is a dictionary lookup for the rest of the session.
static func warm_all(density: float) -> int:
	var built := 0
	for variant in range(VARIANT_COUNT):
		for slot in range(CACHE_SLOTS):
			if _cache.has(cache_key(variant, slot, density)):
				continue
			build(variant, slot, density)
			built += 1
	return built


static func stats() -> String:
	return "meshes=%d builds=%d in_run=%d build_ms=%.0f guard=%s" % [
		_cache.size(), build_count, builds_in_run, build_ms_total, run_guard]


## Returns an ArrayMesh whose surfaces follow `SURFACES` (empty surfaces are
## omitted, and `mesh.set_meta("surfaces", [...])` records what is present).
static func build(variant: int, slot: int, density: float) -> ArrayMesh:
	variant = posmod(variant, VARIANT_COUNT)
	slot = posmod(slot, CACHE_SLOTS)
	var key := cache_key(variant, slot, density)
	if _cache.has(key):
		return _cache[key]
	var started := Time.get_ticks_usec()
	if run_guard:
		builds_in_run += 1
		push_warning("[SegmentBuilder] building '%s' while a run is active" % key)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (slot + 1) + 104729 * variant

	var tools := {
		"road": MeshKit.begin(),
		"walk": MeshKit.begin(),
		"art": MeshKit.begin(),
		"ground": MeshKit.begin(),
		"facade": MeshKit.begin(),
		"facade_b": MeshKit.begin(),
		"facade_c": MeshKit.begin(),
		"water": MeshKit.begin(),
		"steel": MeshKit.begin(),
		"concrete": MeshKit.begin(),
		"leaf": MeshKit.begin(),
		"leaves": MeshKit.begin(),
	}

	_build_ground(tools["ground"], variant % VARIANT_COUNT)
	_build_road(tools["road"], tools["art"], rng)
	_build_walkways(tools["walk"], tools["art"])

	match variant % VARIANT_COUNT:
		0:
			_build_street(tools, rng, density)
		1:
			_build_market(tools, rng, density)
		2:
			_build_corniche(tools, rng, density)
		3:
			_build_neighbourhood(tools, rng, density)
		4:
			_build_mac_nimir(tools, rng, density)
		5:
			_build_shambat(tools, rng, density)
		_:
			_build_bahri(tools, rng, density)

	_build_flags(tools["art"], rng, density)

	var mesh := ArrayMesh.new()
	var present := PackedStringArray()
	for name in SURFACES:
		var st: SurfaceTool = tools[name]
		var built: ArrayMesh = st.commit()
		if built == null or built.get_surface_count() == 0:
			continue
		# ArrayMesh has no append_from(): copy the surface's arrays across.
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				built.surface_get_arrays(0))
		present.append(name)
	mesh.set_meta("surfaces", present)
	_cache[key] = mesh
	build_count += 1
	build_ms_total += float(Time.get_ticks_usec() - started) / 1000.0
	return mesh


static func clear_cache() -> void:
	_cache.clear()


## Drops every cached mesh built for a *different* quality density. A preset
## change would otherwise leave 21 unused meshes of the old density alive for
## the rest of the session, which is real GPU memory on a 2 GB phone.
static func prune_density(keep: float) -> int:
	var suffix := "_%.2f" % keep
	var dropped := 0
	for key in _cache.keys():
		if not String(key).ends_with(suffix):
			_cache.erase(key)
			dropped += 1
	return dropped


## Pick one of the three photographed shopfronts, so a street is not wallpapered
## with the same building 40 times in a row.
static func _facade_tool(tools: Dictionary, pick: int) -> SurfaceTool:
	match posmod(pick, 3):
		1:
			return tools["facade_b"]
		2:
			return tools["facade_c"]
		_:
			return tools["facade"]


# ---------------------------------------------------------------------------
# Ground / road
# ---------------------------------------------------------------------------
## Sand ground around the street.
##
## The river variants must NOT get one full-width slab: it sits at y = -0.06 and
## would cover the water at y = -1.55, which is why the corniche used to look
## like a wall of sand instead of the Nile. Each variant therefore lists the
## spans that are actually dry land.
static func _build_ground(st: SurfaceTool, variant: int) -> void:
	match variant:
		2:
			# Corniche: the Nile is on the left, so the city keeps its ground on
			# the right and the far shore is a separate bank across the water.
			_ground_span(st, INNER, 170.0, -0.06)
			_ground_span(st, -170.0, -80.0, -1.4)
		4, 5:
			# Bridges: water on both sides, banks beyond the 80 m channel.
			_ground_span(st, 80.0, 170.0, -1.4)
			_ground_span(st, -170.0, -80.0, -1.4)
		_:
			_ground_span(st, -170.0, 170.0, -0.06)


static func _ground_span(st: SurfaceTool, x0: float, x1: float, y: float) -> void:
	if is_equal_approx(x0, x1):
		return
	var h := LENGTH * 0.5
	MeshKit.add_uv_ground(st, Vector3(x0, y, h), Vector3(x1, y, h),
			Vector3(x1, y, -h), Vector3(x0, y, -h), 9.0)


## `st` paints the photographic asphalt; `paint_st` carries the flat, vertex
## coloured markings (lane dashes, crosswalks, sand drifts) which must not be
## textured with the asphalt photo.
static func _build_road(st: SurfaceTool, paint_st: SurfaceTool,
		rng: RandomNumberGenerator) -> void:
	var h := LENGTH * 0.5
	# Main asphalt slab: world-space UVs so the photo grain keeps a real 2.4 m
	# per tile scale instead of stretching with the segment.
	MeshKit.add_uv_ground(st, Vector3(-ROAD_HALF, 0, h), Vector3(ROAD_HALF, 0, h),
			Vector3(ROAD_HALF, 0, -h), Vector3(-ROAD_HALF, 0, -h), 2.4)
	# Dashed lane dividers between the three lanes (x = +-1.2).
	# Worn thermoplastic, not studio white: real Khartoum paint is grey-yellow
	# after a season of dust and tyres.
	var paint := Color("#cfc7b4")
	var z := -h
	while z < h:
		for lane_edge: float in [-1.2, 1.2]:
			_add_flat_box(paint_st, Vector3(lane_edge, 0.03, z + 1.5),
					Vector3(0.15, 0.012, 2.6), paint)
		z += 5.6
	# Occasional crosswalk / speed bump paint for rhythm.
	if rng.randf() < 0.5:
		var cz := rng.randf_range(-h + 6.0, h - 6.0)
		for i in 7:
			_add_flat_box(paint_st, Vector3(-3.6 + float(i) * 1.2, 0.013, cz),
					Vector3(0.55, 0.01, 1.8), paint)
	# Sand drifts on the shoulder (Khartoum streets are never fully clean).
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var px := side * rng.randf_range(3.4, ROAD_HALF - 0.3)
		var pz := rng.randf_range(-h, h)
		_add_flat_box(paint_st, Vector3(px, 0.008, pz),
				Vector3(rng.randf_range(0.6, 1.6), 0.006, rng.randf_range(0.8, 2.4)),
				PALETTE["sand"])


static func _build_walkways(st: SurfaceTool, curb_st: SurfaceTool) -> void:
	var h := LENGTH * 0.5
	var concrete := Color("#b8ac97")
	var curb := Color("#b6ac9a")
	for side: float in [-1.0, 1.0]:
		var x_in := side * ROAD_HALF
		var x_out := side * INNER
		MeshKit.add_uv_ground(st, Vector3(x_in, 0.16, h), Vector3(x_out, 0.16, h),
				Vector3(x_out, 0.16, -h), Vector3(x_in, 0.16, -h), 2.0)
		# Curb face toward the road (vertex-coloured: it is a 16 cm strip, and a
		# stretched photo there would smear).
		MeshKit.add_quad(curb_st, Vector3(x_in, 0.0, h), Vector3(x_in, 0.16, h),
				Vector3(x_in, 0.16, -h), Vector3(x_in, 0.0, -h), curb)
		# Outer skirt down to the sand, otherwise the raised walkway edge shows
		# a 22 cm slit of sky between the pavement and the ground plane.
		MeshKit.add_quad(curb_st, Vector3(x_out, 0.16, h), Vector3(x_out, -0.06, h),
				Vector3(x_out, -0.06, -h), Vector3(x_out, 0.16, -h), concrete)



# ---------------------------------------------------------------------------
# Variant 0: Khartoum street
# ---------------------------------------------------------------------------
static func _build_street(tools: Dictionary, rng: RandomNumberGenerator, density: float) -> void:
	var st: SurfaceTool = tools["art"]
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5 - 3.0:
			var span := rng.randf_range(7.0, 12.0)
			var skip := density < 0.75 and rng.randf() < 0.35
			if not skip:
				_building_into(st, tools, rng, side, z + span * 0.5, span,
						rng.randi_range(0, 2), 1.0)
			z += span + rng.randf_range(0.5, 2.5)
		# Street furniture along the curb.
		for i in 3:
			var fz := -LENGTH * 0.5 + 6.0 + float(i) * 12.0 + rng.randf_range(-2.0, 2.0)
			_lamp(st, side, fz)
			if rng.randf() < 0.7:
				_acacia(st, tools["leaves"], side * (INNER + 1.4), fz + 4.0, rng)
			if rng.randf() < 0.5 * density:
				_parked_car(st, side, fz + 6.5, rng)
		if rng.randf() < 0.5:
			_shop_awning(st, side, rng.randf_range(-14.0, 14.0), rng)


static func _building(st: SurfaceTool, rng: RandomNumberGenerator, side: float,
		z_center: float, z_span: float) -> void:
	_building_into(st, {}, rng, side, z_center, z_span, 0, 0.0)


## Textured building. `tools` may be empty (pure vertex-colour body).
static func _building_into(st: SurfaceTool, tools: Dictionary,
		rng: RandomNumberGenerator, side: float, z_center: float, z_span: float,
		facade_tile: int, texture_scale: float) -> void:
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

	# Facade: a photographic panel when the caller supplied a facade surface,
	# otherwise the old flat window grid (low tier without photo textures).
	var face_x: float = x_inner + side * 0.03
	var facade: SurfaceTool = _facade_tool(tools, facade_tile) if not tools.is_empty() else null
	if facade != null:
		# One photographic panel per building, mapped exactly once across the
		# span. Culling is disabled on the facade material, so the same winding
		# is correct on both sides of the street (Godot flips the normal on back
		# faces automatically).
		MeshKit.add_facade_panel(facade,
				Vector3(face_x, 0.16, z_center - z_span * 0.5),
				Vector3(0, 0, 1), z_span, height - 0.2, facade_tile)
		# A shaded ground-floor recess sells the depth of the photo.
		MeshKit.add_box(st, Vector3(face_x + side * 0.05, 1.3, z_center),
				Vector3(0.14, 1.4, z_span * 0.42), Color("#16181c"))
	else:
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
		MeshKit.add_box(st, Vector3(face_x, 1.35, z_center),
				Vector3(0.12, 2.3, z_span * 0.6), Color("#1b1e22"))


static func _shop_awning(st: SurfaceTool, side: float, z: float,
		rng: RandomNumberGenerator) -> void:
	# Faded cotton, sun-bleached: saturated primaries are what made the street
	# look like a cartoon market.
	var col: Color = [Color("#c98a4b"), Color("#7e9bb0"), Color("#6f7f5a"),
			Color("#b4695a")][rng.randi_range(0, 3)]
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


## Umbrella-thorn acacia: the tree that lines every Khartoum street.
##
## It used to be two big flat boxes, which read as green hedges floating over the
## road - the single most cartoonish thing left in the frame. The canopy is now a
## fan of narrow, slightly drooping leaf clusters around a dark core, in muted
## olive tones, so it reads as a tree at chase-camera distance and costs 12 quads.
static func _acacia(st: SurfaceTool, leaves_st: SurfaceTool, x: float, z: float,
		rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(2.6, 3.8)
	var base := Vector3(x, 0.16, z)
	MeshKit.add_cylinder(st, base, 0.17, h, Color("#54402e"), 5, 0.12)
	# Two forked limbs, so the crown does not look glued to a stick.
	for k in 2:
		var a := rng.randf_range(0.0, TAU)
		var tip := base + Vector3(cos(a) * 0.9, h * 0.95, sin(a) * 0.9)
		MeshKit.add_quad(st, base + Vector3(0, h * 0.55, 0),
				base + Vector3(0.13, h * 0.55, 0.13), tip + Vector3(0.13, 0, 0.13), tip,
				Color("#6b5238"))
	var crown := h + 0.55
	var spread := rng.randf_range(1.6, 2.4)
	var core := base + Vector3(0, crown, 0)
	# Dome of alpha cluster cards. Each card faces a different way, so from any
	# camera angle several overlap and the crown reads as foliage with sky
	# showing through it - instead of the old fan of solid green blades.
	var cards := 13
	for i in cards:
		var a := TAU * float(i) / float(cards) + rng.randf_range(-0.18, 0.18)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var arm := spread * rng.randf_range(0.70, 1.15)
		var card := rng.randf_range(1.15, 1.75)
		var centre: Vector3 = core + dir * (arm * 0.55) + Vector3(0, rng.randf_range(-0.10, 0.45), 0)
		var shade := rng.randf_range(0.70, 1.0)
		var tint := Color(shade, shade * 1.03, shade * 0.9)
		MeshKit.add_quad(leaves_st,
				centre - dir * card * 0.5 - Vector3(0, card * 0.42, 0),
				centre + dir * card * 0.5 - Vector3(0, card * 0.42, 0),
				centre + dir * card * 0.5 + Vector3(0, card * 0.42, 0),
				centre - dir * card * 0.5 + Vector3(0, card * 0.42, 0),
				tint)
	# Dark core under the leaves fills the gap when seen from below.
	MeshKit.add_cylinder(st, base + Vector3(0, crown - 0.25, 0), spread * 0.34, 0.35,
			PALETTE["leaf_dark"].darkened(0.15), 7)


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
static func _build_market(tools: Dictionary, rng: RandomNumberGenerator, density: float) -> void:
	var st: SurfaceTool = tools["art"]
	for side: float in [-1.0, 1.0]:
		var facade: SurfaceTool = _facade_tool(tools, rng.randi_range(0, 2))
		# A low back wall so stalls read against something solid, with a
		# photographic shopfront strip above it.
		MeshKit.add_box(st, Vector3(side * (INNER + 3.2), 2.2, 0),
				Vector3(6.0, 4.4, LENGTH), PALETTE["wall_b"].darkened(0.05))
		# The photographic shopfronts cover the road-facing side of that wall. A
		# floating strip above the wall (the old layout) read as a billboard.
		MeshKit.add_facade_panel(facade,
				Vector3(side * (INNER + 0.17), 0.16, -LENGTH * 0.5),
				Vector3(0, 0, 1), LENGTH, 4.1)
		var z := -LENGTH * 0.5 + 3.0
		while z < LENGTH * 0.5 - 3.0:
			if rng.randf() < density:
				_stall(st, side, z, rng)
			z += rng.randf_range(7.0, 10.0)
		for i in 4:
			_acacia(st, tools["leaves"], side * (INNER + 0.6),
					-LENGTH * 0.5 + 5.0 + float(i) * 10.0, rng)
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
	# Dust-faded canvas: even "bright" market cloth in Khartoum is sun-bleached
	# within a season, and saturated primaries are what read as cartoon.
	var cloth: Color = [Color("#b98553"), Color("#7d7186"), Color("#6d8095"),
			Color("#77835f"), Color("#a86d5c")][rng.randi_range(0, 4)]
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
	# Striped canvas: six slats across the 2.4 m span, alternating the stall
	# colour with sun-bleached cotton. A single flat slab reads as a plastic
	# sheet; the slats catch the low sun one at a time.
	for i in 6:
		var sw := 0.4
		var sx := x - 1.2 + sw * 0.5 + float(i) * sw
		var slat: Color = cloth if i % 2 == 0 else cloth.lightened(0.24)
		MeshKit.add_box(st, Vector3(sx, 2.5 - float(i % 2) * 0.012, z),
				Vector3(sw - 0.015, 0.1, 3.0), slat)
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
static func _build_corniche(tools: Dictionary, rng: RandomNumberGenerator,
		density: float) -> void:
	var st: SurfaceTool = tools["art"]
	# River to the left, city to the right.
	_water(tools["water"], tools["concrete"], -1.0)
	for side: float in [1.0]:
		_wall_row(st, tools, side, rng, density)
	# Corniche railing + palms on the river side.
	var z := -LENGTH * 0.5 + 2.0
	while z < LENGTH * 0.5:
		_railing(st, -1.0, z, 2.0, 1.05)
		if rng.randf() < density:
			_palm(st, tools["leaf"], Vector3(-(INNER + 0.4), 0.16, z + 1.0), rng)
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


static func _wall_row(st: SurfaceTool, tools: Dictionary, side: float,
		rng: RandomNumberGenerator, density: float) -> void:
	var z := -LENGTH * 0.5
	while z < LENGTH * 0.5 - 4.0:
		var span := rng.randf_range(9.0, 14.0)
		if rng.randf() < 0.85 * maxf(density, 0.6):
			_building_into(st, tools, rng, side, z + span * 0.5, span,
					rng.randi_range(0, 2), 1.0)
		z += span + rng.randf_range(2.0, 4.0)


static func _water(st: SurfaceTool, embankment: SurfaceTool, side: float) -> void:
	var h := LENGTH * 0.5
	var x0: float = side * (INNER + 0.1)
	var x1: float = side * 80.0
	# Photographic Nile surface, UVs in world metres so the ripples do not
	# stretch along a 40 m chunk.
	MeshKit.add_uv_ground(st, Vector3(x0, -1.55, h), Vector3(x1, -1.55, h),
			Vector3(x1, -1.55, -h), Vector3(x0, -1.55, -h), 18.0)
	# Embankment wall (concrete photo).
	var wx: float = side * (INNER + 0.05)
	MeshKit.add_uv_quad(embankment, Vector3(wx, -1.6, h), Vector3(wx, 0.1, h),
			Vector3(wx, 0.1, -h), Vector3(wx, -1.6, -h),
			Vector2(0, 0), Vector2(0, 1.6 / 6.0), Vector2(LENGTH / 6.0, 1.6 / 6.0),
			Vector2(LENGTH / 6.0, 0), Color.WHITE)


static func _railing(st: SurfaceTool, side: float, z: float, span: float, height: float) -> void:
	var x: float = side * (INNER - 0.25)
	MeshKit.add_box(st, Vector3(x, 0.16 + height, z), Vector3(0.08, 0.08, span),
			PALETTE["white"])
	MeshKit.add_box(st, Vector3(x, 0.16 + height * 0.55, z), Vector3(0.06, 0.06, span),
			PALETTE["metal"])
	for i in 3:
		MeshKit.add_box(st, Vector3(x, 0.16 + height * 0.5, z - span * 0.5 + float(i) * span * 0.5),
				Vector3(0.07, height, 0.07), PALETTE["white"])


## Nile palm. The fronds are long and *narrow*: a 0.9 m wide blade seen from
## 3 m away is a green sheet, which is exactly what the old version looked like.
## Nine 0.2 m fronds per crown read as a palm at chase-camera distance.
static func _palm(st: SurfaceTool, leaf_st: SurfaceTool, base: Vector3,
		rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(5.2, 7.8)
	# Slight lean, so a row of palms is not a picket fence.
	var lean := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.25, 0.25))
	var top := base + Vector3(0, h, 0) + lean
	MeshKit.add_cylinder(st, base, 0.2, h, Color("#6f5940"), 6, 0.13)
	MeshKit.add_cylinder(st, top - Vector3(0, 0.5, 0), 0.42, 0.55,
			Color("#4a3a28"), 6)
	# 13 textured fronds per crown. Each one is a single quad running from the
	# crown to the tip, mapped 0..1 across `palm_frond.png` - the texture carries
	# the leaflets, so the silhouette is a palm instead of a green shard.
	for i in 13:
		var a := TAU * float(i) / 13.0 + rng.randf_range(-0.16, 0.16)
		var dir := Vector3(cos(a), 0, sin(a))
		var reach := rng.randf_range(2.1, 2.9)
		# Younger fronds stand up, older ones droop: the crown has a profile.
		var lift := rng.randf_range(0.35, 0.8)
		var droop := rng.randf_range(0.6, 1.5)
		var root: Vector3 = top + dir * 0.18 + Vector3(0, lift, 0)
		var tip: Vector3 = top + dir * reach + Vector3(0, lift - droop, 0)
		var perp := Vector3(-dir.z, 0.0, dir.x) * rng.randf_range(0.30, 0.42)
		var shade := rng.randf_range(0.72, 1.0)
		var tint := Color(shade, shade * 1.04, shade * 0.88)
		MeshKit.add_quad(leaf_st, root - perp, tip - perp * 0.55,
				tip + perp * 0.55, root + perp, tint)
	# Dead fronds hanging under the crown - every Khartoum palm has them. Same
	# texture, sun-bleached brown: five extra quads, no extra asset.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var tip: Vector3 = top + dir * 1.05 + Vector3(0, -1.7, 0)
		var perp := Vector3(-dir.z, 0.0, dir.x) * 0.26
		MeshKit.add_quad(leaf_st, top - perp, tip - perp * 0.7, tip + perp * 0.7,
				top + perp, Color("#9c8352"))


# ---------------------------------------------------------------------------
# Variant 3: dusty neighbourhood
# ---------------------------------------------------------------------------
static func _build_neighbourhood(tools: Dictionary, rng: RandomNumberGenerator,
		density: float) -> void:
	var st: SurfaceTool = tools["art"]
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5 - 6.0:
			var span := rng.randf_range(8.0, 13.0)
			_compound_wall(st, tools, side, z + span * 0.5, span, rng)
			z += span + rng.randf_range(1.5, 4.0)
		for i in 3:
			var fz := -LENGTH * 0.5 + 5.0 + float(i) * 12.0 + rng.randf_range(-2.0, 2.0)
			_acacia(st, tools["leaves"], side * (ROAD_HALF + 1.0), fz, rng)
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


static func _compound_wall(st: SurfaceTool, tools: Dictionary, side: float,
		z_center: float, z_span: float, rng: RandomNumberGenerator) -> void:
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
	# Photographic plaster panel on the road-facing wall of the house.
	MeshKit.add_facade_panel(_facade_tool(tools, 2),
			Vector3(house_x - side * 3.02, 0.16, z_center - z_span * 0.4),
			Vector3(0, 0, 1), z_span * 0.8, house_h - 0.2, 2)
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
# Variant 4: Mac Nimir bridge (the riveted steel truss over the Blue Nile)
# ---------------------------------------------------------------------------
## Built from the reference photograph in `art_src/bridge_mac_nimir.jpg`:
## deep steel truss girders on both sides, riveted cross-bracing overhead,
## weathered concrete piers standing in the river.
static func _build_mac_nimir(tools: Dictionary, rng: RandomNumberGenerator,
		density: float) -> void:
	var steel: SurfaceTool = tools["steel"]
	var concrete: SurfaceTool = tools["concrete"]
	var art: SurfaceTool = tools["art"]
	_water(tools["water"], concrete, -1.0)
	_water(tools["water"], concrete, 1.0)

	var h := LENGTH * 0.5
	for side: float in [-1.0, 1.0]:
		var x: float = side * (INNER - 0.15)
		# Deck edge beam + parapet (concrete).
		MeshKit.add_uv_quad(concrete, Vector3(x, 0.0, h), Vector3(x, 0.6, h),
				Vector3(x, 0.6, -h), Vector3(x, 0.0, -h),
				Vector2(0, 0), Vector2(LENGTH / 6.0, 0), Vector2(LENGTH / 6.0, 0.1),
				Vector2(0, 0.1), Color.WHITE)
		# Truss: top chord, bottom chord, verticals and diagonals.
		_truss_span(steel, side, -h, h)
		# Stone parapet cap above the deck.
		MeshKit.add_box(art, Vector3(x + side * 0.1, 0.78, 0), Vector3(0.34, 0.18, LENGTH),
				PALETTE["stone"])

	# Concrete piers standing in the river (outside the drivable lanes).
	var pier_x := INNER + 6.0
	for pz: float in [-h + 8.0, 0.0, h - 8.0]:
		for side: float in [-1.0, 1.0]:
			MeshKit.add_uv_quad(concrete,
					Vector3(side * pier_x, -2.2, pz + 2.4),
					Vector3(side * pier_x, 0.0, pz + 2.4),
					Vector3(side * pier_x, 0.0, pz - 2.4),
					Vector3(side * pier_x, -2.2, pz - 2.4),
					Vector2(0, 0), Vector2(4.8 / 6.0, 0), Vector2(4.8 / 6.0, 2.2 / 6.0),
					Vector2(0, 2.2 / 6.0), Color.WHITE)

	# Overhead banner gantries. They hang ABOVE the truss (7.4 m): at 4.2 m the
	# banners sat exactly at the chase camera's height and filled the screen with
	# giant geometry-coloured flags.
	if density > 0.6:
		for i in 2:
			var bz := -h + 10.0 + float(i) * 18.0
			for side: float in [-1.0, 1.0]:
				MeshKit.add_box(art, Vector3(side * (INNER - 0.3), 3.9, bz),
						Vector3(0.14, 7.8, 0.14), PALETTE["metal"])
			MeshKit.add_box(art, Vector3(0, 7.75, bz), Vector3((INNER - 0.3) * 2.0, 0.08, 0.08),
					PALETTE["metal"])
			for k in 4:
				MeshKit.add_flag_panel(art,
						Vector3(-2.7 + float(k) * 1.8 - 0.75, 7.55, bz), 1.5, 1.0)


## One side of a riveted steel truss, 6.5 m tall, made of textured box chords.
static func _truss_span(st: SurfaceTool, side: float, z_start: float, z_end: float) -> void:
	var x: float = side * (INNER - 0.45)
	var top := 6.4
	var bottom := 1.15
	# Chords: long textured strips so the rivet pattern from the photo shows.
	for chord_y: float in [top, bottom]:
		MeshKit.add_uv_quad(st, Vector3(x, chord_y - 0.28, z_start),
				Vector3(x, chord_y + 0.28, z_start),
				Vector3(x, chord_y + 0.28, z_end),
				Vector3(x, chord_y - 0.28, z_end),
				Vector2(0, 0), Vector2(0, 0.56 / 2.0),
				Vector2(absf(z_end - z_start) / 2.0, 0.56 / 2.0),
				Vector2(absf(z_end - z_start) / 2.0, 0), Color.WHITE)
	# Verticals + diagonals every 4 m (matches the 4 m panel of the texture).
	var z := z_start
	var i := 0
	while z < z_end:
		MeshKit.add_uv_quad(st, Vector3(x, bottom, z), Vector3(x, top, z),
				Vector3(x, top, z + 0.34), Vector3(x, bottom, z + 0.34),
				Vector2(0, 0), Vector2(0, 1), Vector2(0.17, 1), Vector2(0.17, 0),
				Color.WHITE)
		# Diagonal brace.
		var z2 := minf(z + 4.0, z_end)
		MeshKit.add_uv_quad(st, Vector3(x, bottom, z), Vector3(x, top, z2),
				Vector3(x, top, z2 + 0.28), Vector3(x, bottom, z + 0.28),
				Vector2(0, 0), Vector2(1, 1), Vector2(1.14, 1), Vector2(0.14, 0),
				Color.WHITE)
		z += 4.0
		i += 1


# ---------------------------------------------------------------------------
# Variant 5: Shambat bridge (concrete beam deck, tall weathered piers)
# ---------------------------------------------------------------------------
static func _build_shambat(tools: Dictionary, rng: RandomNumberGenerator,
		density: float) -> void:
	var concrete: SurfaceTool = tools["concrete"]
	var art: SurfaceTool = tools["art"]
	_water(tools["water"], concrete, -1.0)
	_water(tools["water"], concrete, 1.0)
	var h := LENGTH * 0.5

	for side: float in [-1.0, 1.0]:
		var x: float = side * (INNER - 0.1)
		# Solid concrete parapet, 1.1 m high: exactly the Shambat profile.
		MeshKit.add_uv_quad(concrete, Vector3(x, 0.0, h), Vector3(x, 1.06, h),
				Vector3(x, 1.06, -h), Vector3(x, 0.0, -h),
				Vector2(0, 0), Vector2(0, 1.06 / 6.0), Vector2(LENGTH / 6.0, 1.06 / 6.0),
				Vector2(LENGTH / 6.0, 0), Color.WHITE)
		MeshKit.add_box(art, Vector3(x - side * 0.03, 1.12, 0), Vector3(0.3, 0.12, LENGTH),
				PALETTE["white"])
		# Simple steel handrail on top.
		MeshKit.add_box(art, Vector3(x, 1.55, 0), Vector3(0.06, 0.06, LENGTH),
				PALETTE["metal"])
		var z := -h
		while z < h:
			MeshKit.add_box(art, Vector3(x, 1.32, z + 1.5), Vector3(0.05, 0.5, 0.05),
					PALETTE["metal"])
			z += 3.0

	# Lamp masts every 20 m - the bridge has them, and they catch the sunset.
	for i in 3:
		var lz := -h + 7.0 + float(i) * 14.0
		for side: float in [-1.0, 1.0]:
			MeshKit.add_cylinder(art, Vector3(side * (INNER - 0.6), 1.1, lz), 0.1, 6.2,
					PALETTE["metal"], 6)
			MeshKit.add_box(art, Vector3(side * (INNER - 1.1), 7.2, lz),
					Vector3(1.0, 0.1, 0.1), PALETTE["metal"])
			MeshKit.add_box(art, Vector3(side * (INNER - 1.5), 7.05, lz),
					Vector3(0.4, 0.16, 0.3), Color("#ffe9b8"))


# ---------------------------------------------------------------------------
# Variant 6: old Bahri (colonial two-storey shopfronts)
# ---------------------------------------------------------------------------
static func _build_bahri(tools: Dictionary, rng: RandomNumberGenerator,
		density: float) -> void:
	var art: SurfaceTool = tools["art"]
	for side: float in [-1.0, 1.0]:
		var z := -LENGTH * 0.5
		while z < LENGTH * 0.5 - 4.0:
			var span := rng.randf_range(8.0, 13.0)
			var two_storey := rng.randf() < 0.85
			var height := rng.randf_range(7.0, 9.2) if two_storey else rng.randf_range(3.6, 4.6)
			var x_inner: float = side * INNER
			var depth := rng.randf_range(7.0, 10.0)
			var x_center: float = x_inner + side * depth * 0.5
			var tone: Color = [PALETTE["wall_a"], PALETTE["wall_c"],
					PALETTE["wall_b"]][rng.randi_range(0, 2)]
			MeshKit.add_box(art, Vector3(x_center, height * 0.5 + 0.16, z + span * 0.5),
					Vector3(depth, height, span), tone.darkened(0.1))
			# Deep cornice - the signature of the 1900s Bahri houses.
			MeshKit.add_box(art, Vector3(x_inner + side * 0.35, height + 0.16, z + span * 0.5),
					Vector3(0.9, 0.42, span + 0.2), tone.darkened(0.25))
			# Photographic facade on the street side.
			MeshKit.add_facade_panel(_facade_tool(tools, rng.randi_range(0, 2)),
					Vector3(x_inner + side * 0.05, 0.16, z),
					Vector3(0, 0, 1), span, height - 0.2)
			# Corrugated awning over the shop.
			MeshKit.add_box(art, Vector3(x_inner - side * 0.85, 3.0, z + span * 0.5),
					Vector3(1.8, 0.08, span * 0.9), PALETTE["metal"].darkened(0.2))
			for k in 2:
				MeshKit.add_box(art, Vector3(x_inner - side * 1.6, 1.5,
						z + span * 0.5 - span * 0.3 + float(k) * span * 0.55),
						Vector3(0.08, 3.0, 0.08), PALETTE["metal"].darkened(0.3))
			z += span + rng.randf_range(2.0, 4.0)
		# Acacias + a lamp, same rhythm as the reference photo.
		for i in 2:
			_acacia(art, tools["leaves"], side * (ROAD_HALF + 0.9),
					-LENGTH * 0.5 + 10.0 + float(i) * 16.0, rng)
		_lamp(art, side, -LENGTH * 0.5 + 6.0)


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

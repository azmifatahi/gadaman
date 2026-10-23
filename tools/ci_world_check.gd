extends SceneTree
## =============================================================================
##  ci_world_check.gd — proves the photographic street art is actually built.
## -----------------------------------------------------------------------------
##  The procedural world is the one part of the game that cannot be reviewed by
##  reading the diff: a single bad UV or a missing tool entry produces an empty
##  surface and the street silently turns invisible. This script builds every
##  district at every cache slot, checks the geometry and the materials, and
##  exercises the new settings round-trip.
##
##  Usage:  godot --headless --script tools/ci_world_check.gd -- --strict
## =============================================================================

const SEGMENTS := preload("res://scripts/world/segment_builder.gd")
const KIT := preload("res://scripts/world/mesh_kit.gd")

## Surfaces every slot of a district must contain. A surface missing entirely
## means its texture never shows up in game.
##
## "facade*" is a wildcard: each building picks one of the three photographed
## shopfronts, so which of facade/facade_b/facade_c a slot contains depends on
## its RNG seed. Requiring one specific name fails a perfectly good street.
const EXPECTED := {
	0: ["road", "walk", "art", "ground", "facade*"],
	1: ["road", "walk", "art", "ground", "facade*", "leaves"],
	2: ["road", "walk", "art", "ground", "facade*", "water", "concrete", "leaf"],
	3: ["road", "walk", "art", "ground", "facade*", "leaves"],
	4: ["road", "walk", "art", "ground", "water", "steel", "concrete"],
	5: ["road", "walk", "art", "ground", "water", "concrete"],
	6: ["road", "walk", "art", "ground", "facade*"],
}


static func _surface_matches(present: PackedStringArray, wanted: String) -> bool:
	if wanted.ends_with("*"):
		var prefix := wanted.substr(0, wanted.length() - 1)
		for name in present:
			if String(name).begins_with(prefix):
				return true
		return false
	return present.has(wanted)

var _problems: Array[String] = []
var _summary: Dictionary = {}


func _initialize() -> void:
	print("[CIWorld] godot %s" % Engine.get_version_info().string)
	var autoloads := PackedStringArray()
	for child in root.get_children():
		autoloads.append(String(child.name))
	print("[CIWorld] root children: %s" % ", ".join(autoloads))
	_check_textures()
	_check_segments()
	_check_warm_up()
	_check_settings()
	# Always echo what was actually built: when this job fails in CI the log is
	# often unreachable, but annotations are not.
	print("[CIWorld] summary %s" % JSON.stringify(_summary))
	if _problems.is_empty():
		print("[CIWorld] OK: every district builds with its photographic surfaces.")
		quit(0)
		return
	for problem in _problems:
		printerr("[CIWorld] PROBLEM: %s" % problem)
	printerr("[CIWorld] FAILED with %d problem(s)." % _problems.size())
	quit(1)


# ---------------------------------------------------------------------------
func _check_textures() -> void:
	var required := [
		"sky_khartoum.jpg", "skyline_khartoum.png", "menu_bg.jpg",
		"asphalt_photo.jpg", "asphalt_photo_normal.png", "asphalt_photo_rough.png",
		"pavement_photo.jpg", "pavement_photo_normal.png", "water_photo.jpg",
		"facade_atlas.jpg", "truss_steel.jpg", "truss_steel_normal.png",
		"concrete_photo.jpg", "asphalt_grain.jpg", "palm_frond.png",
		"leaf_cluster.png",
	]
	for name in required:
		var path: String = "res://assets/textures/" + String(name)
		if not ResourceLoader.exists(path):
			_problems.append("missing texture %s" % path)
			continue
		var tex := load(path)
		if tex == null:
			_problems.append("texture does not load: %s" % path)
	print("[CIWorld] textures: %d checked" % required.size())


func _check_segments() -> void:
	for variant in range(SEGMENTS.VARIANT_COUNT):
		var want: Array = EXPECTED.get(variant, [])
		for slot in range(SEGMENTS.CACHE_SLOTS):
			var mesh: ArrayMesh = SEGMENTS.build(variant, slot, 1.0)
			if mesh == null:
				_problems.append("variant %d slot %d returned null" % [variant, slot])
				continue
			var names: PackedStringArray = []
			if mesh.has_meta("surfaces"):
				names = mesh.get_meta("surfaces")
			if mesh.get_surface_count() != names.size():
				_problems.append("variant %d slot %d: %d surfaces but %d names" % [
					variant, slot, mesh.get_surface_count(), names.size()])
			for surface_name in want:
				if not _surface_matches(names, String(surface_name)):
					_problems.append("variant %d slot %d is missing the '%s' surface" % [
						variant, slot, surface_name])
			var tris := 0
			for i in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(i)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					_problems.append("variant %d surface %d has no vertex array" % [variant, i])
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if verts.size() < 3:
					_problems.append("variant %d surface %d is empty" % [variant, i])
				tris += verts.size() / 3
				# A surface with a texture needs UVs, or the photo collapses to
				# one pixel.
				if String(names[i]) in ["road", "walk", "facade", "facade_b", "facade_c",
						"water", "steel", "concrete", "leaf", "leaves"]:
					if arrays.size() <= Mesh.ARRAY_TEX_UV or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
						_problems.append("variant %d surface '%s' has no UVs" % [variant, names[i]])
			if tris < 200:
				_problems.append("variant %d slot %d has only %d triangles" % [variant, slot, tris])
			_summary["v%d_s%d" % [variant, slot]] = {
				"surfaces": names, "tris": tris, "mesh_surfaces": mesh.get_surface_count(),
			}
	print("[CIWorld] districts: %d variants x %d slots built" % [
		SEGMENTS.VARIANT_COUNT, SEGMENTS.CACHE_SLOTS])


## The freeze "after a distance" was a district mesh being generated on the
## frame it first appeared. `warm_all()` must therefore cover the entire cache
## matrix, and recycling must never build again.
func _check_warm_up() -> void:
	var started := Time.get_ticks_msec()
	var built := SEGMENTS.warm_all(1.0)
	var warm_ms := Time.get_ticks_msec() - started
	# Everything is already in the cache from _check_segments(), so this call is
	# the pure lookup path the game uses at runtime.
	if built != 0:
		_problems.append("warm_all rebuilt %d meshes that were already cached" % built)
	SEGMENTS.run_guard = true
	var before := SEGMENTS.build_count
	for i in 600:
		SEGMENTS.build(i % SEGMENTS.VARIANT_COUNT, i % SEGMENTS.CACHE_SLOTS, 1.0)
	if SEGMENTS.build_count != before:
		_problems.append("%d district meshes were rebuilt during the recycle loop" % [
			SEGMENTS.build_count - before])
	if SEGMENTS.builds_in_run != 0:
		_problems.append("%d builds were counted while the run guard was on" % [
			SEGMENTS.builds_in_run])
	SEGMENTS.run_guard = false
	# A cold build is what used to happen mid-run; keep its cost visible in CI.
	SEGMENTS.clear_cache()
	var cold := Time.get_ticks_msec()
	var cold_built := SEGMENTS.warm_all(1.0)
	var cold_ms := Time.get_ticks_msec() - cold
	_summary["warm_up"] = {
		"meshes": cold_built, "cold_ms": cold_ms, "cached_lookup_ms": warm_ms,
		"cache_after": SEGMENTS.build_count,
	}
	print("[CIWorld] warm-up: %d meshes built in %d ms (cold); cache hits afterwards" % [
		cold_built, cold_ms])
	if cold_built != SEGMENTS.VARIANT_COUNT * SEGMENTS.CACHE_SLOTS:
		_problems.append("warm_all built %d meshes, expected %d" % [
			cold_built, SEGMENTS.VARIANT_COUNT * SEGMENTS.CACHE_SLOTS])
	# Refill the cache so the rest of the checks see warm data.
	SEGMENTS.warm_all(1.0)


func _check_settings() -> void:
	# `--script` may run before the autoloads are attached to the root, so fall
	# back to instantiating the very same script rather than skipping the check
	# (a skipped check is how the settings regressions shipped before).
	# Deliberately untyped: the setters below are dynamic property lookups.
	var s = root.get_node_or_null("Settings")
	if s == null:
		var settings_script: GDScript = load("res://scripts/core/settings.gd")
		if settings_script == null:
			_problems.append("settings.gd does not load")
			return
		s = settings_script.new()
		s.name = "Settings"
		root.add_child(s)
	# Lane control <-> legacy tilt flag must stay consistent, because the player
	# controller still reads tilt_enabled.
	var original: int = s.lane_control
	for mode in [0, 1, 2]:
		s.set_lane_control(mode)
		var want_tilt: bool = int(mode) == 2
		if bool(s.tilt_enabled) != want_tilt:
			_problems.append("lane_control %d left tilt_enabled=%s" % [mode, s.tilt_enabled])
		if mode == 1 and not bool(s.show_buttons):
			_problems.append("button mode did not enable the on-screen pads")
	s.set_lane_control(original)
	for district in range(-1, 7):
		s.set_district(district)
		if int(s.district) != district:
			_problems.append("district %d did not round-trip" % district)
	print("[CIWorld] settings: lane control + district round-trip OK")

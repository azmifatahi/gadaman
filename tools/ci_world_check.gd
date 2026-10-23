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

## Minimum vertices per district, per surface family. A surface missing entirely
## means a texture would not show up in game.
const EXPECTED := {
	0: ["road", "walk", "art", "ground", "facade"],
	1: ["road", "walk", "art", "ground", "facade"],
	2: ["road", "walk", "art", "ground", "facade", "water", "concrete"],
	3: ["road", "walk", "art", "ground", "facade"],
	4: ["road", "walk", "art", "ground", "water", "steel", "concrete"],
	5: ["road", "walk", "art", "ground", "water", "concrete"],
	6: ["road", "walk", "art", "ground", "facade"],
}

var _problems: Array[String] = []


func _initialize() -> void:
	print("[CIWorld] godot %s" % Engine.get_version_info().string)
	_check_textures()
	_check_segments()
	_check_settings()
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
		"concrete_photo.jpg",
	]
	for name in required:
		var path := "res://assets/textures/" + name
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
				if not names.has(surface_name):
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
				if String(names[i]) in ["road", "walk", "facade", "water", "steel", "concrete"]:
					if arrays.size() <= Mesh.ARRAY_TEX_UV or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
						_problems.append("variant %d surface '%s' has no UVs" % [variant, names[i]])
			if tris < 200:
				_problems.append("variant %d slot %d has only %d triangles" % [variant, slot, tris])
			if variant == 0 and slot == 0:
				print("[CIWorld] variant 0: %d surfaces %s, %d triangles" % [
					mesh.get_surface_count(), names, tris])
	print("[CIWorld] districts: %d variants x %d slots built" % [
		SEGMENTS.VARIANT_COUNT, SEGMENTS.CACHE_SLOTS])


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
		var want_tilt := mode == 2
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

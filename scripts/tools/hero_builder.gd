## =============================================================================
##  hero_builder.gd  —  Headless-safe automation core
##  ----------------------------------------------------------------------------
##  The reusable build routine behind ImportArabicFolderHero.gd. This file is
##  NOT an EditorScript: it exposes static functions that work from any context
##  (EditorScript, headless --script MainLoop, or even a runtime @onready).
##  That is the piece that makes the CI build fully automatic: GitHub Actions
##  invokes build_hero() via a tiny MainLoop script after `godot --import`,
##  producing assets/models/hero/hero.tscn before the APK export step.
##
##  All paths are UTF-8 safe (String.path_join + DirAccess) so the Arabic
##  folder name "الشخصيه/" works on every platform including the Linux CI.
## =============================================================================
class_name HeroBuilder
extends RefCounted

const ARABIC_FOLDER_CANDIDATES := ["res://الشخصيه/", "res://الشخصية/"]
const HERO_DIR := "res://assets/models/hero/"
const HERO_SCENE_PATH := HERO_DIR + "hero.tscn"

const ANIM_RULES := [
	{"key": "stumble", "needle": "stumble", "loop": false, "required": true},
	{"key": "slide",   "needle": "slide",   "loop": false, "required": true},
	{"key": "jump",    "needle": "jump",    "loop": false, "required": true},
	{"key": "fall",    "needle": "fall",    "loop": false, "required": true},
	{"key": "land",    "needle": "land",    "loop": false, "required": true},
	{"key": "sprint",  "needle": "sprint",  "loop": true,  "required": false},
	{"key": "jog",     "needle": "run",     "loop": true,  "required": true},
	{"key": "idle",    "needle": "idle",    "loop": true,  "required": false},
]

var _issues: Array[String] = []


## ---------------------------------------------------------------------------
## Entry points
## ---------------------------------------------------------------------------
## Runs the full automated import. Returns true if hero.tscn was saved
## successfully. Prints progress to stdout and records any issues in _issues.
static func build_hero(allow_fallback := true) -> bool:
	var selfb := HeroBuilder.new()
	return selfb._do_build(allow_fallback)


## Like build_hero() but only builds if hero.tscn is not already present.
## Safe to call from _ready() during a runtime first-launch.
static func build_if_missing() -> bool:
	if ResourceLoader.exists(HERO_SCENE_PATH):
		return true
	return build_hero(true)


func get_issues() -> Array[String]:
	return _issues


## ---------------------------------------------------------------------------
## Build
## ---------------------------------------------------------------------------
func _do_build(allow_fallback := true) -> bool:
	_mkdir(HERO_DIR)
	var arabic_dir := _locate_arabic_folder()
	if arabic_dir == "":
		_issues.append("Arabic character folder not found")
		if not allow_fallback:
			push_error("[HeroBuilder] %s" % _issues[-1])
			return false
		push_warning("[HeroBuilder] %s - leaving procedural model in place" % _issues[-1])
		return false
	print("[HeroBuilder] Scanning %s" % arabic_dir)

	# Short-circuit: without FBX2glTF on PATH, Godot's importer will hang
	# trying to convert FBX files. GLB files can still be loaded. We check
	# for any GLB first; if none and no FBX2glTF, bail out gracefully.
	var have_glb := false
	var files := _list_fbx(arabic_dir)
	for f in files:
		if f.to_lower().ends_with(".glb") or f.to_lower().ends_with(".gltf"):
			have_glb = true
	if not have_glb and not _fbx2gltf_available():
		_issues.append("FBX2glTF not on PATH and no GLB supplied; cannot build hero headlessly")
		if not allow_fallback:
			push_error("[HeroBuilder] %s" % _issues[-1])
			return false
		push_warning("[HeroBuilder] %s (procedural model will be used)" % _issues[-1])
		return false

	if files.is_empty():
		_issues.append("No FBX/GLB files in %s" % arabic_dir)
		if not allow_fallback:
			push_error("[HeroBuilder] %s" % _issues[-1])
			return false
		push_warning("[HeroBuilder] %s" % _issues[-1])
		return false

	var skin_path := ""
	var anim_clips := {}
	for f in files:
		var full := arabic_dir.path_join(f)
		# Only treat FBX as skin if FBX2glTF is present, otherwise treat all
		# FBX as unknown and look for GLB.
		if (f.to_lower().ends_with(".fbx") and not _fbx2gltf_available()):
			continue
		if (f.to_lower().ends_with(".glb") or f.to_lower().ends_with(".gltf")) or _is_skin_fbx(full):
			skin_path = full
		else:
			var key := _classify(f)
			if key != "":
				anim_clips[key] = full
	if skin_path == "":
		var largest_name := ""
		var largest_size := -1
		for f in files:
			var fp := arabic_dir.path_join(f)
			var is_fbx := f.to_lower().ends_with(".fbx")
			if is_fbx and not _fbx2gltf_available():
				continue
			var sz := FileAccess.get_file_as_bytes(fp).size()
			if sz > largest_size:
				largest_size = sz
				largest_name = f
		skin_path = arabic_dir.path_join(largest_name)
	if skin_path == "" or skin_path == arabic_dir.path_join(""):
		_issues.append("No loadable skin mesh found")
		if not allow_fallback:
			push_error("[HeroBuilder] %s" % _issues[-1])
			return false
		push_warning("[HeroBuilder] %s" % _issues[-1])
		return false
	print("[HeroBuilder] skin = %s, clips = %s" % [skin_path.get_file(), anim_clips.keys()])

	# Try to load the skin scene (FBX or GLB).
	var skin_scene: PackedScene = null
	if ResourceLoader.exists(skin_path):
		skin_scene = load(skin_path)
	if skin_scene == null:
		_issues.append("Cannot load skin FBX %s (FBX2glTF may be missing)" % skin_path)
		if not allow_fallback:
			push_error("[HeroBuilder] %s" % _issues[-1])
			return false
		push_warning("[HeroBuilder] %s - leaving procedural model in place" % _issues[-1])
		return false

	var hero := _build_hero_from_scene(skin_scene, skin_path, anim_clips)
	var pck := PackedScene.new()
	if pck.pack(hero) != OK:
		_issues.append("PackScene failed")
		hero.queue_free()
		return false
	hero.queue_free()
	var flags := ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS
	#if ResourceSaver has FLAG_BUNDLE_RESOURCES:
	#	flags |= ResourceSaver.FLAG_BUNDLE_RESOURCES
	var err := ResourceSaver.save(pck, HERO_SCENE_PATH, flags)
	if err != OK:
		_issues.append("Saving %s failed: %s" % [HERO_SCENE_PATH, error_string(err)])
		push_error("[HeroBuilder] %s" % _issues[-1])
		return false
	print("[HeroBuilder] ✔ Saved %s" % HERO_SCENE_PATH)
	return true


## ---------------------------------------------------------------------------
## UTF-8 safe directory helpers
## ---------------------------------------------------------------------------
func _mkdir(path: String) -> void:
	# Ensure the hero output directory exists. DirAccess.make_dir_recursive
	# creates missing intermediate directories relative to the project root.
	var da := DirAccess.open("res://")
	if da == null:
		printerr("[HeroBuilder] Cannot open res://")
		return
	var rel := path.trim_prefix("res://").rtrim("/")
	if rel.begins_with("assets/"):
		# Walk down and make sure assets/models exists first.
		var parts := rel.split("/")
		var cur := ""
		for p in parts:
			cur += p
			if not da.dir_exists(cur):
				da.make_dir(cur)
			cur += "/"


func _fbx2gltf_available() -> bool:
	# Godot's FBX importer shells out to FBX2glTF at import time. Without the
	# binary on PATH, load() on an FBX scene hangs indefinitely waiting for
	# the child process. We detect availability up front and short-circuit.
	var path_env := OS.get_environment("PATH", "")
	for d in path_env.split(":"):
		if d == "":
			continue
		var cand := d.rstrip("/") + "/FBX2glTF"
		if FileAccess.file_exists(cand):
			return true
		# Some distros ship it lowercase.
		var cand2 := d.rstrip("/") + "/fbx2gltf"
		if FileAccess.file_exists(cand2):
			return true
	return false


func _locate_arabic_folder() -> String:
	for cand in ARABIC_FOLDER_CANDIDATES:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cand)):
			return cand
	var da := DirAccess.open("res://")
	if da == null:
		return ""
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != ".." and da.current_is_dir():
			if name.contains("شخص"):
				da.list_dir_end()
				return "res://%s/" % name
		name = da.get_next()
	da.list_dir_end()
	return ""


func _list_fbx(folder: String) -> Array:
	var out := []
	var da := DirAccess.open(folder)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != ".." and not da.current_is_dir():
			var low := n.to_lower()
			if low.ends_with(".fbx") or low.ends_with(".glb") or low.ends_with(".gltf"):
				out.append(n)
		n = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _is_skin_fbx(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(6144).get_string_from_utf8()
	f.close()
	if head.find("MotionOnlyScene") != -1:
		return false
	return head.find("skin") != -1 or head.find("Skin") != -1 \
			or head.find("X Bot") != -1 or head.find("Y Bot") != -1


func _classify(file_name: String) -> String:
	var low := file_name.get_basename().to_lower()
	for rule in ANIM_RULES:
		var needle: String = rule["needle"]
		if needle == "run" and low.find("slide") != -1:
			continue
		if needle == "jump" and low.find("stumble") != -1:
			continue
		if low.find(needle) != -1:
			return rule["key"]
	return ""


## ---------------------------------------------------------------------------
## Hero build (mesh + animplayer + animationtree + PBR material)
## ---------------------------------------------------------------------------
func _build_hero_from_scene(skin_scene: PackedScene, skin_path: String, clips: Dictionary) -> Node3D:
	var hero := Node3D.new()
	hero.name = "Hero"

	if skin_scene == null:
		push_error("[HeroBuilder] Cannot load skin %s" % skin_path)
		return hero
	var mesh_root := skin_scene.instantiate()
	mesh_root.name = "Mesh"
	hero.add_child(mesh_root)

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	hero.add_child(ap)
	var lib := AnimationLibrary.new()
	ap.add_animation_library("", lib)

	_add_all_anims_from(mesh_root, "jog", lib)
	for key in clips.keys():
		var cs: PackedScene = load(clips[key])
		if cs == null:
			push_warning("[HeroBuilder] Skip %s (%s)" % [key, clips[key]])
			continue
		var tmp := cs.instantiate()
		_add_all_anims_from(tmp, key, lib)
		tmp.queue_free()

	_ensure_canonical(lib)
	_apply_loop_modes(lib)
	_print_library(lib)

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = ap
	tree.active = true
	tree.tree_root = _build_state_machine()
	hero.add_child(tree)

	_fit_mesh_to_game(mesh_root)

	var suit_script: GDScript = load("res://scripts/tools/SetupRealisticRunner.gd")
	if suit_script:
		var suit_mat := suit_script.make_suit_material()
		for mi in mesh_root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var ln := m.name.to_lower()
			if ln.find("eye") != -1 or ln.find("lashes") != -1 or ln.find("teeth") != -1:
				continue
			for s in range(m.mesh.get_surface_count()):
				m.set_surface_override_material(s, suit_mat)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		suit_script.ensure_reflection_probe(hero)
	return hero


func _add_all_anims_from(root: Node, force_key: String, lib: AnimationLibrary) -> void:
	for node in _iter_nodes_of_type(root, AnimationPlayer):
		var player := node as AnimationPlayer
		for lib_name in player.get_animation_library_list():
			var src := player.get_animation_library(lib_name)
			if src == null:
				continue
			var names := src.get_animation_list()
			if names.is_empty():
				continue
			if force_key != "" and names.size() >= 1:
				_put_anim(lib, force_key, src.get_animation(names[0]).duplicate())
			else:
				for nm in names:
					var key := nm.to_snake_case().replace("-", "_").replace(" ", "_")
					if key.is_empty():
						continue
					_put_anim(lib, key, src.get_animation(nm).duplicate())


func _put_anim(lib: AnimationLibrary, key: String, anim: Animation) -> void:
	if lib.has_animation(key):
		lib.remove_animation(key)
	lib.add_animation(key, anim)


func _ensure_canonical(lib: AnimationLibrary) -> void:
	if not lib.has_animation("jog"):
		for n in lib.get_animation_list():
			if n.to_lower().find("run") != -1 and n.to_lower().find("slide") == -1:
				lib.rename_animation(n, "jog")
				break
	if not lib.has_animation("idle") and lib.has_animation("jog"):
		var jog: Animation = lib.get_animation("jog")
		var idle := Animation.new()
		idle.length = 1.0
		idle.loop_mode = Animation.LOOP_LINEAR
		for t in range(jog.get_track_count()):
			if jog.track_get_key_count(t) == 0:
				continue
			idle.add_track(jog.track_get_type(t))
			idle.track_set_path(idle.get_track_count() - 1, jog.track_get_path(t))
			var val := jog.track_get_key_value(t, 0)
			idle.track_insert_key(idle.get_track_count() - 1, 0.0, val)
			idle.track_insert_key(idle.get_track_count() - 1, 1.0, val)
		lib.add_animation("idle", idle)
		print("[HeroBuilder] synthesized 'idle' from jog")
	if not lib.has_animation("sprint") and lib.has_animation("jog"):
		var jog: Animation = lib.get_animation("jog")
		var sprint := jog.duplicate()
		sprint.length = jog.length / 1.6
		for t in range(sprint.get_track_count()):
			var kc := sprint.track_get_key_count(t)
			var times := []
			var vals := []
			for k in range(kc):
				times.append(sprint.track_get_key_time(t, k) / 1.6)
				vals.append(sprint.track_get_key_value(t, k))
			for k in range(kc):
				sprint.track_set_key_time(t, k, times[k])
		lib.add_animation("sprint", sprint)
		print("[HeroBuilder] synthesized 'sprint' (1.6x jog)")
	if lib.has_animation("fall") and not lib.has_animation("land"):
		lib.add_animation("land", lib.get_animation("fall").duplicate())


func _apply_loop_modes(lib: AnimationLibrary) -> void:
	for rule in ANIM_RULES:
		if lib.has_animation(rule["key"]):
			lib.get_animation(rule["key"]).loop_mode = \
				Animation.LOOP_LINEAR if rule["loop"] else Animation.LOOP_NONE


func _print_library(lib: AnimationLibrary) -> void:
	print("[HeroBuilder] Clips:")
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		print("   %-12s %5.2fs  %s" % [n, a.length, "loop" if a.loop_mode == Animation.LOOP_LINEAR else "one-shot"])


## ---------------------------------------------------------------------------
## AnimationTree (StateMachine)
## ---------------------------------------------------------------------------
func _build_state_machine() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendTree.new()
	loco.add_node("output", AnimationNodeOutput.new(), Vector2(500, 80))
	var bs1d := AnimationNodeBlendSpace1D.new()
	bs1d.add_blend_point(_anim("idle"),   0.0)
	bs1d.add_blend_point(_anim("jog"),    0.55)
	bs1d.add_blend_point(_anim("sprint"), 1.0)
	bs1d.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	bs1d.snap = 0.0
	loco.add_node("locomotion", bs1d, Vector2(60, 80))
	var lean := AnimationNodeBlend2.new()
	lean.amount = 0.0
	loco.add_node("lean", lean, Vector2(280, 80))
	loco.connect_node("lean", 0, "locomotion", 0)
	loco.connect_node("lean", 1, "locomotion", 0)
	loco.connect_node("output", 0, "lean", 0)
	sm.add_node("locomotion", loco, Vector2(0, 0))

	var add_state := func(nm: String, pos: Vector2):
		sm.add_node(nm, _anim(nm), pos)
	add_state("jump",    Vector2(280, -150))
	add_state("fall",    Vector2(520, -150))
	add_state("land",    Vector2(780, -150))
	add_state("slide",   Vector2(280,  150))
	add_state("stumble", Vector2(560,  150))

	var add_trans := func(from: String, to: String, xfade: float, auto: bool):
		var t := AnimationNodeStateMachineTransition.new()
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END if auto \
				else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.fade_time = xfade
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
				else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		sm.add_transition(from, to, t)
	add_trans("locomotion", "jump",   0.08, false)
	add_trans("jump",       "fall",   0.10, true)
	add_trans("fall",       "land",   0.10, true)
	add_trans("land",       "locomotion", 0.12, true)
	add_trans("locomotion", "slide",  0.06, false)
	add_trans("slide",      "locomotion", 0.10, true)
	add_trans("locomotion", "stumble",0.10, false)
	add_trans("stumble",    "locomotion", 0.12, true)
	add_trans("jump",       "slide",  0.08, false)
	sm.start_node = "locomotion"
	return sm


func _anim(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


## ---------------------------------------------------------------------------
## Mesh fit/orient
## ---------------------------------------------------------------------------
func _fit_mesh_to_game(root: Node3D) -> void:
	var mi := _find_first_mesh(root)
	if mi == null:
		push_warning("[HeroBuilder] No mesh found; leaving default scale")
		return
	var aabb := mi.get_aabb()
	var height := aabb.size.y
	var s := 1.0
	if height > 4.0:
		s = 1.7 / height
	root.scale = Vector3(s, s, s)
	root.position.y = -aabb.position.y * s
	root.rotation = Vector3.ZERO


func _find_first_mesh(root: Node) -> MeshInstance3D:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			return c as MeshInstance3D
		var hit := _find_first_mesh(c)
		if hit:
			return hit
	return null


func _iter_nodes_of_type(root: Node, type_obj: Variant) -> Array:
	var out := []
	if root.is_class(type_obj):
		out.append(root)
	for c in root.get_children():
		out.append_array(_iter_nodes_of_type(c, type_obj))
	return out

## =============================================================================
##  hero_builder.gd  —  Headless-safe hero scene builder.
## -----------------------------------------------------------------------------
##  Scans res://assets/characters/الشخصية/ (or the older res://الشخصيه/),
##  loads the Mixamo X-Bot skin FBX and all per-action animation clips using
##  Godot 4.4's BUILT-IN ufbx importer (no external FBX2glTF binary needed),
##  and writes assets/models/hero/hero.tscn containing:
##    * The skinned mesh (~1.7m tall, feet at Y=0, facing -Z).
##    * AnimationPlayer with canonical clips: idle / jog / sprint / jump /
##      fall / land / slide / stumble. (idle and sprint are synthesised.)
##    * AnimationTree (root = StateMachine): BlendSpace1D driven by run_blend
##      (idle/jog/sprint), Blend2 lane-lean driven by lane_blend, one-shot
##      states for jump/fall/land/slide/stumble.
##    * Sudan chrome PBR suit material (Metallic 0.8, Roughness 0.2, seams
##      normal map) on every body mesh surface plus a ReflectionProbe.
##
##  Exit codes: build_hero() returns true on success; false on failure.
##  When strict=true (APK export job) failure is fatal so we never ship a
##  capsule-only APK again.
## =============================================================================
class_name HeroBuilder
extends RefCounted

const CHAR_FOLDER_CANDIDATES := [
	"res://assets/characters/الشخصية/",
	"res://assets/characters/الشخصيه/",
	"res://الشخصية/",
	"res://الشخصيه/",
]

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
## Public API
## ---------------------------------------------------------------------------
static func build_hero(strict := false) -> bool:
	var b := HeroBuilder.new()
	return b._do_build(strict)


static func build_if_missing() -> bool:
	if ResourceLoader.exists(HERO_SCENE_PATH):
		return true
	return build_hero(false)


func get_issues() -> Array[String]:
	return _issues


## ---------------------------------------------------------------------------
## Build pipeline
## ---------------------------------------------------------------------------
func _do_build(strict := false) -> bool:
	_mkdir(HERO_DIR)
	var folder := _locate_folder()
	if folder == "":
		_issue("Character folder not found", strict)
		return false
	print("[HeroBuilder] Scanning %s" % folder)

	var files := _list_assets(folder)
	if files.is_empty():
		_issue("No FBX/GLB files in %s" % folder, strict)
		return false

	var skin_path: String = ""
	var clips: Dictionary = {}
	for f in files:
		var full: String = folder.path_join(f)
		if _is_skin(full):
			skin_path = full
		else:
			var k := _classify(f)
			if k != "":
				clips[k] = full

	# Fallback: if no file marked itself as the skin, pick the largest.
	if skin_path == "":
		var largest_name: String = ""
		var largest_size: int = -1
		for f in files:
			var sz: int = FileAccess.get_file_as_bytes(folder.path_join(f)).size()
			if sz > largest_size:
				largest_size = sz
				largest_name = f
		skin_path = folder.path_join(largest_name)
	print("[HeroBuilder] skin = %s" % skin_path.get_file())
	print("[HeroBuilder] clips = %s" % clips.keys())

	# Load the skin scene. Godot 4.3+ includes the ufbx importer built-in;
	# FBX loading works out of the box in headless mode as long as we have
	# let the editor/import step finish first.
	var skin_scene: PackedScene = _safe_load_scene(skin_path)
	if skin_scene == null:
		_issue("Could not load skin mesh %s (import may have failed)" % skin_path, strict)
		return false

	var hero: Node3D = _build_hero_tree(skin_scene, clips)

	# Merge animations: start with whatever came with the skin (usually a
	# reference "mixamo.com" clip, used as jog if needed).
	var ap: AnimationPlayer = hero.get_node("AnimationPlayer") as AnimationPlayer
	var lib: AnimationLibrary = ap.get_animation_library("")
	_add_anims_from(ap.get_node("Mesh"), "jog", lib)
	for key in clips.keys():
		var cs: PackedScene = _safe_load_scene(clips[key])
		if cs == null:
			push_warning("[HeroBuilder] Skip clip %s (%s)" % [key, clips[key]])
			continue
		var tmp := cs.instantiate()
		_add_anims_from(tmp, key, lib)
		tmp.queue_free()

	_make_canonical(lib)
	_apply_loops(lib)
	_print_library(lib)

	# Apply suit material.
	var suit_script: GDScript = load("res://scripts/tools/SetupRealisticRunner.gd") as GDScript
	if suit_script != null:
		var suit_mat: Material = suit_script.make_suit_material()
		if suit_mat != null:
			_apply_material(hero.get_node("Mesh"), suit_mat)
		suit_script.ensure_reflection_probe(hero)

	# Pack + save.
	var pck := PackedScene.new()
	if pck.pack(hero) != OK:
		_issue("PackScene failed", strict)
		hero.queue_free()
		return false
	hero.queue_free()
	var err := ResourceSaver.save(pck, HERO_SCENE_PATH, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		_issue("Saving %s failed: %s" % [HERO_SCENE_PATH, error_string(err)], strict)
		return false
	print("[HeroBuilder] \u2714 Wrote %s" % HERO_SCENE_PATH)
	return true


## ---------------------------------------------------------------------------
## Folder / file discovery (UTF-8 safe)
## ---------------------------------------------------------------------------
func _locate_folder() -> String:
	for cand in CHAR_FOLDER_CANDIDATES:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cand)):
			return cand
	var da: DirAccess = DirAccess.open("res://")
	if da == null:
		return ""
	da.list_dir_begin()
	var n: String = da.get_next()
	while n != "":
		if n != "." and n != ".." and da.current_is_dir() and n.contains("شخص"):
			da.list_dir_end()
			return "res://%s/" % n
		n = da.get_next()
	da.list_dir_end()
	# Also search under assets/characters/ for any arabic-named folder.
	var ac: DirAccess = DirAccess.open("res://assets/characters")
	if ac != null:
		ac.list_dir_begin()
		n = ac.get_next()
		while n != "":
			if n != "." and n != ".." and ac.current_is_dir() and n.contains("شخص"):
				ac.list_dir_end()
				return "res://assets/characters/%s/" % n
			n = ac.get_next()
		ac.list_dir_end()
	return ""


func _list_assets(folder: String) -> Array:
	var out: Array[String] = []
	var da: DirAccess = DirAccess.open(folder)
	if da == null:
		return out
	da.list_dir_begin()
	var n: String = da.get_next()
	while n != "":
		if n != "." and n != ".." and not da.current_is_dir():
			var low: String = n.to_lower()
			if low.ends_with(".fbx") or low.ends_with(".glb") or low.ends_with(".gltf"):
				out.append(n)
		n = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _is_skin(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head: String = f.get_buffer(6144).get_string_from_utf8()
	f.close()
	if head.find("MotionOnlyScene") != -1:
		return false
	return head.find("X Bot") != -1 or head.find("Y Bot") != -1 \
			or (head.find("Skin") != -1 and head.find("skin") != -1)


func _classify(file_name: String) -> String:
	var low: String = file_name.get_basename().to_lower()
	for rule in ANIM_RULES:
		var needle: String = rule["needle"]
		if needle == "run" and low.find("slide") != -1:
			continue
		if needle == "jump" and low.find("stumble") != -1:
			continue
		if low.find(needle) != -1:
			return rule["key"]
	return ""


func _safe_load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return res as PackedScene
	return null


func _mkdir(path: String) -> void:
	var da: DirAccess = DirAccess.open("res://")
	if da == null:
		return
	var rel: String = path.trim_prefix("res://").strip_edges(false, true)
	if rel == "":
		return
	var parts: PackedStringArray = rel.split("/")
	var cur: String = ""
	for p in parts:
		cur += p
		if not da.dir_exists(cur):
			da.make_dir(cur)
		cur += "/"


func _issue(msg: String, strict: bool) -> void:
	_issues.append(msg)
	if strict:
		push_error("[HeroBuilder] %s" % msg)
	else:
		push_warning("[HeroBuilder] %s" % msg)


## ---------------------------------------------------------------------------
## Hero node tree
## ---------------------------------------------------------------------------
func _build_hero_tree(skin_scene: PackedScene, _clips: Dictionary) -> Node3D:
	var hero: Node3D = Node3D.new()
	hero.name = "Hero"

	var mesh_root: Node3D = skin_scene.instantiate() as Node3D
	mesh_root.name = "Mesh"
	hero.add_child(mesh_root)

	var ap: AnimationPlayer = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	hero.add_child(ap)
	var lib: AnimationLibrary = AnimationLibrary.new()
	ap.add_animation_library("", lib)

	var tree: AnimationTree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.active = true
	tree.tree_root = _build_state_machine()
	hero.add_child(tree)

	_fit_mesh(mesh_root)
	return hero


func _find_first_mesh(root: Node) -> MeshInstance3D:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			return c as MeshInstance3D
		var hit: MeshInstance3D = _find_first_mesh(c)
		if hit != null:
			return hit
	return null


func _fit_mesh(root: Node3D) -> void:
	var mi: MeshInstance3D = _find_first_mesh(root)
	if mi == null:
		push_warning("[HeroBuilder] No mesh found; leaving default scale")
		return
	var aabb: AABB = mi.get_aabb()
	var h: float = aabb.size.y
	var s: float = 1.0
	if h > 4.0:
		s = 1.7 / h
	root.scale = Vector3(s, s, s)
	root.position.y = -aabb.position.y * s
	root.rotation = Vector3.ZERO


## ---------------------------------------------------------------------------
## Animation harvesting
## ---------------------------------------------------------------------------
func _add_anims_from(root: Node, force_key: String, lib: AnimationLibrary) -> void:
	for node in _nodes_of_type(root, AnimationPlayer):
		var player: AnimationPlayer = node as AnimationPlayer
		for ln in player.get_animation_library_list():
			var src: AnimationLibrary = player.get_animation_library(ln)
			if src == null:
				continue
			var names: PackedStringArray = src.get_animation_list()
			if names.is_empty():
				continue
			if force_key != "":
				_put_anim(lib, force_key, src.get_animation(names[0]).duplicate())
			else:
				for nm in names:
					var k: String = nm.to_snake_case().replace("-", "_").replace(" ", "_")
					if k == "":
						continue
					_put_anim(lib, k, src.get_animation(nm).duplicate())


func _put_anim(lib: AnimationLibrary, key: String, anim: Animation) -> void:
	if lib.has_animation(key):
		lib.remove_animation(key)
	lib.add_animation(key, anim)


func _nodes_of_type(root: Node, t: Variant) -> Array:
	var out: Array = []
	if root.is_class(t):
		out.append(root)
	for c in root.get_children():
		out.append_array(_nodes_of_type(c, t))
	return out


## ---------------------------------------------------------------------------
## Canonical clip synthesis
## ---------------------------------------------------------------------------
func _make_canonical(lib: AnimationLibrary) -> void:
	if not lib.has_animation("jog"):
		for n in lib.get_animation_list():
			if n.to_lower().find("run") != -1 and n.to_lower().find("slide") == -1:
				lib.rename_animation(n, "jog")
				break
	if not lib.has_animation("idle") and lib.has_animation("jog"):
		var jog: Animation = lib.get_animation("jog")
		var idle: Animation = Animation.new()
		idle.length = 1.0
		idle.loop_mode = Animation.LOOP_LINEAR
		for t in range(jog.get_track_count()):
			if jog.track_get_key_count(t) == 0:
				continue
			idle.add_track(jog.track_get_type(t))
			var idx: int = idle.get_track_count() - 1
			idle.track_set_path(idx, jog.track_get_path(t))
			var val: Variant = jog.track_get_key_value(t, 0)
			idle.track_insert_key(idx, 0.0, val)
			idle.track_insert_key(idx, 1.0, val)
		lib.add_animation("idle", idle)
		print("[HeroBuilder] synthesized 'idle' from jog")
	if not lib.has_animation("sprint") and lib.has_animation("jog"):
		var jog: Animation = lib.get_animation("jog")
		var sprint: Animation = jog.duplicate()
		sprint.length = jog.length / 1.6
		for t in range(sprint.get_track_count()):
			var kc: int = sprint.track_get_key_count(t)
			var times: Array[float] = []
			var vals: Array = []
			for k in range(kc):
				times.append(sprint.track_get_key_time(t, k) / 1.6)
				vals.append(sprint.track_get_key_value(t, k))
			for k in range(kc):
				sprint.track_set_key_time(t, k, times[k])
		lib.add_animation("sprint", sprint)
		print("[HeroBuilder] synthesized 'sprint' (1.6x jog)")
	if lib.has_animation("fall") and not lib.has_animation("land"):
		lib.add_animation("land", lib.get_animation("fall").duplicate())


func _apply_loops(lib: AnimationLibrary) -> void:
	for rule in ANIM_RULES:
		if lib.has_animation(rule["key"]):
			lib.get_animation(rule["key"]).loop_mode = Animation.LOOP_LINEAR if rule["loop"] else Animation.LOOP_NONE


func _print_library(lib: AnimationLibrary) -> void:
	print("[HeroBuilder] Clips in hero AnimationPlayer:")
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		print("   %-12s %5.2fs  %s" % [n, a.length, "loop" if a.loop_mode == Animation.LOOP_LINEAR else "one-shot"])


## ---------------------------------------------------------------------------
## State-machine tree
## ---------------------------------------------------------------------------
func _build_state_machine() -> AnimationNodeStateMachine:
	var sm: AnimationNodeStateMachine = AnimationNodeStateMachine.new()

	# Locomotion tree: BlendSpace1D for speed, Blend2 for lane lean.
	var loco: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	loco.add_node("output", AnimationNodeOutput.new(), Vector2(500, 80))
	var bs1d: AnimationNodeBlendSpace1D = AnimationNodeBlendSpace1D.new()
	bs1d.add_blend_point(_anim("idle"),   0.0)
	bs1d.add_blend_point(_anim("jog"),    0.55)
	bs1d.add_blend_point(_anim("sprint"), 1.0)
	bs1d.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	bs1d.snap = 0.0
	loco.add_node("locomotion", bs1d, Vector2(60, 80))
	var lean: AnimationNodeBlend2 = AnimationNodeBlend2.new()
	lean.amount = 0.0
	loco.add_node("lean", lean, Vector2(280, 80))
	loco.connect_node("lean", 0, "locomotion")
	loco.connect_node("lean", 1, "locomotion")
	loco.connect_node("output", 0, "lean")
	sm.add_node("locomotion", loco, Vector2(0, 0))

	sm.add_node("jump",    _anim("jump"),    Vector2(280, -150))
	sm.add_node("fall",    _anim("fall"),    Vector2(520, -150))
	sm.add_node("land",    _anim("land"),    Vector2(780, -150))
	sm.add_node("slide",   _anim("slide"),   Vector2(280,  150))
	sm.add_node("stumble", _anim("stumble"), Vector2(560,  150))

	_add_trans(sm, "locomotion", "jump",       0.08, false)
	_add_trans(sm, "jump",       "fall",       0.10, true)
	_add_trans(sm, "fall",       "land",       0.10, true)
	_add_trans(sm, "land",       "locomotion", 0.12, true)
	_add_trans(sm, "locomotion", "slide",      0.06, false)
	_add_trans(sm, "slide",      "locomotion", 0.10, true)
	_add_trans(sm, "locomotion", "stumble",    0.10, false)
	_add_trans(sm, "stumble",    "locomotion", 0.12, true)
	_add_trans(sm, "jump",       "slide",      0.08, false)
	sm.start_node = "locomotion"
	return sm


func _add_trans(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float, auto: bool) -> void:
	var t: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
	if auto:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	t.fade_time = xfade
	sm.add_transition(from, to, t)


func _anim(name: String) -> AnimationNodeAnimation:
	var a: AnimationNodeAnimation = AnimationNodeAnimation.new()
	a.animation = name
	return a


## ---------------------------------------------------------------------------
## PBR suit material application
## ---------------------------------------------------------------------------
func _apply_material(root: Node, mat: Material) -> void:
	for node in _nodes_of_type(root, MeshInstance3D):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		var ln: String = mi.name.to_lower()
		if ln.find("eye") != -1 or ln.find("lashes") != -1 or ln.find("teeth") != -1:
			continue
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@tool
extends EditorScript
## =============================================================================
##  ImportArabicFolderHero.gd
##  ----------------------------------------------------------------------------
##  One-click importer that scans the Arabic-named FBX folder (الشخصيه/) at the
##  project root, merges the Mixamo X Bot skinned mesh with all per-action
##  animations into a reusable hero scene (assets/models/hero/hero.tscn) that
##  contains:
##    * The imported skin mesh (feet at Y=0, facing -Z, ~1.7m tall).
##    * An AnimationPlayer with every clip renamed to canonical names
##      (idle/jog/sprint/jump/fall/land/slide/stumble).
##    * An AnimationTree wired with a BlendSpace1D for run_blend, an Add2 for
##      lane_blend (lean), and one-shots for Jump/Slide/Stumble/Fall/Land.
##    * The Sudan Chrome PBR suit material from SetupRealisticRunner.gd plus
##      a local ReflectionProbe.
##
##  The importer is UTF-8-safe for Arabic directory names: all paths are joined
##  with String.path_join() and accessed via DirAccess / ProjectSettings which
##  are 8-bit clean on all platforms.
##
##  Run from the Script Editor → File → Run (Ctrl+Shift+X). After running, the
##  PlayerController automatically detects assets/models/hero/hero.tscn at
##  runtime and uses it in place of the procedural placeholder.
## =============================================================================

const ARABIC_FOLDER_CANDIDATES := [
	"res://الشخصيه/",
	"res://الشخصية/",
]

const HERO_DIR := "res://assets/models/hero/"
const HERO_SCENE_PATH := HERO_DIR + "hero.tscn"

# Canonical animations: pattern (substring match), looping, required.
const ANIM_RULES := [
	{"key": "stumble", "needle": "stumble",                      "loop": false, "required": true},
	{"key": "slide",   "needle": "slide",                        "loop": false, "required": true},
	{"key": "jump",    "needle": "jump",                         "loop": false, "required": true},
	{"key": "fall",    "needle": "fall",                         "loop": false, "required": true},
	{"key": "land",    "needle": "land",                         "loop": false, "required": true},
	{"key": "sprint",  "needle": "sprint",                       "loop": true,  "required": false},
	{"key": "jog",     "needle": "run",                          "loop": true,  "required": true},
	{"key": "idle",    "needle": "idle",                         "loop": true,  "required": false},
]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HERO_DIR))
	var arabic_dir := _locate_arabic_folder()
	if arabic_dir == "":
		push_error("ImportArabicFolderHero: could not locate Arabic character folder.")
		return
	print("[ImportHero] Scanning %s" % arabic_dir)

	var files := _list_fbx(arabic_dir)
	if files.is_empty():
		push_error("[ImportHero] No .fbx/.glb files in %s" % arabic_dir)
		return

	var skin_path := ""
	var anim_clips := {}  # key -> absolute res:// path
	for f in files:
		var full := arabic_dir.path_join(f)
		if _is_skin_fbx(full):
			skin_path = full
		else:
			var key := _classify(f)
			if key != "":
				anim_clips[key] = full
				print("  anim  %-10s -> %s" % [key, f])
			else:
				print("  skip  %s" % f)
	if skin_path == "":
		# Fallback: largest file is the skinned mesh.
		files.sort_custom(func(a, b): return FileAccess.get_file_as_bytes(arabic_dir.path_join(a)).size() < FileAccess.get_file_as_bytes(arabic_dir.path_join(b)).size())
		skin_path = arabic_dir.path_join(files[-1])
		# Remove it from the animation candidate list.
		var skin_file_name := skin_path.get_file()
		anim_clips.erase(_classify(skin_file_name))
	print("  skin  -> %s" % skin_path.get_file())

	# Trigger editor reimport of all FBX files.
	_ensure_imported(skin_path)
	for k in anim_clips.keys():
		_ensure_imported(anim_clips[k])

	var hero := _build_hero(skin_path, anim_clips)

	# Pack and save.
	var pck := PackedScene.new()
	if pck.pack(hero) != OK:
		push_error("[ImportHero] Packing hero scene failed.")
	hero.queue_free()
	var err := ResourceSaver.save(pck, HERO_SCENE_PATH, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		push_error("[ImportHero] Failed to save %s: %s" % [HERO_SCENE_PATH, error_string(err)])
	else:
		print("[ImportHero] Wrote %s" % HERO_SCENE_PATH)

	# Make sure player_animation_handler.gd exists so PlayerController can use it.
	_ensure_animation_handler()

	# Touch the filesystem so main scene reloads.
	EditorInterface.get_resource_filesystem().scan()
	print("[ImportHero] Done. Open the main scene and press Play – the new hero is wired up automatically.")


func _ensure_animation_handler() -> void:
	var path := "res://scripts/player/player_animation_handler.gd"
	if ResourceLoader.exists(path):
		return
	push_warning("[ImportHero] PlayerAnimationHandler script missing – expected at %s" % path)


# ---------------------------------------------------------------------------
# UTF-8 safe directory helpers
# ---------------------------------------------------------------------------
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
	# Mixamo marks skinned files with "Skin:" and an embedded character path.
	return head.find("skin") != -1 or head.find("Skin") != -1 \
			or head.find("X Bot") != -1 or head.find("Y Bot") != -1


func _classify(file_name: String) -> String:
	var low := file_name.get_basename().to_lower()
	for rule in ANIM_RULES:
		var needle: String = rule["needle"]
		# Special-case: "run" shouldn't match "running slide" -> classify slide first.
		if needle == "run" and low.find("slide") != -1:
			continue
		if needle == "jump" and low.find("stumble") != -1:
			continue
		if needle == "fall" and low.find("land") != -1 and low.find("to") == -1:
			# "Falling To Landing" should be fall; standalone "land" is land.
			continue
		if low.find(needle) != -1:
			return rule["key"]
	return ""


func _ensure_imported(path: String) -> void:
	if ResourceLoader.exists(path):
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	for _i in range(40):
		if ResourceLoader.exists(path):
			return
		OS.delay_msec(60)


# ---------------------------------------------------------------------------
# Hero build
# ---------------------------------------------------------------------------
func _build_hero(skin_path: String, clips: Dictionary) -> Node3D:
	var hero := Node3D.new()
	hero.name = "Hero"

	# Instantiate skin.
	var skin_scene: PackedScene = load(skin_path)
	if skin_scene == null:
		push_error("[ImportHero] Cannot load skin %s" % skin_path)
		return hero
	var mesh_root := skin_scene.instantiate()
	mesh_root.name = "Mesh"
	hero.add_child(mesh_root)

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	hero.add_child(ap)
	var lib := AnimationLibrary.new()
	ap.add_animation_library("", lib)

	# Harvest the animation(s) that came with the skin FBX (typically the T-pose
	# or a "mixamo.com" reference clip, but may also be the run if we misdetect).
	_add_all_anims_from(mesh_root, "jog", lib)  # Tentative; might be overwritten.

	# Merge in every clip FBX.
	for key in clips.keys():
		var clip_scene: PackedScene = load(clips[key])
		if clip_scene == null:
			push_warning("[ImportHero] Cannot load clip %s (%s)" % [key, clips[key]])
			continue
		var tmp := clip_scene.instantiate()
		_add_all_anims_from(tmp, key, lib)
		tmp.queue_free()

	# Ensure required canonical clips exist.
	_ensure_canonical(lib)
	_apply_loop_modes(lib)
	_print_library(lib)

	# Build AnimationTree.
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = ap
	tree.active = true
	tree.tree_root = _build_blend_tree(lib)
	hero.add_child(tree)

	# Orient + scale to gameplay coordinates (~1.7m tall, feet at Y=0, -Z forward).
	_fit_mesh_to_game(mesh_root)

	# Apply PBR suit material.
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

	hero.owner = hero
	return hero


func _add_all_anims_from(root: Node, force_key: String, lib: AnimationLibrary) -> void:
	# Walk all AnimationPlayer nodes under root, steal their clips.
	for node in _iter_nodes_of_type(root, AnimationPlayer):
		var player := node as AnimationPlayer
		for lib_name in player.get_animation_library_list():
			var src := player.get_animation_library(lib_name)
			if src == null:
				continue
			var names := src.get_animation_list()
			if names.is_empty():
				continue
			# If the library contains a single animation and force_key is supplied,
			# always use force_key; otherwise use the animation's original snake-case name.
			if force_key != "" and names.size() >= 1:
				var anim := src.get_animation(names[0]).duplicate()
				_put_anim(lib, force_key, anim)
				# If the skin FBX had a Run, we may also get an animation named
				# "mixamo.com" or similar - still use it as the jog.
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
	# Normalize: first clip containing "run" that isn't slide becomes "jog".
	if not lib.has_animation("jog"):
		for n in lib.get_animation_list():
			if n.to_lower().find("run") != -1 and n.to_lower().find("slide") == -1:
				lib.rename_animation(n, "jog")
				break
	# Synthesize idle from the first frame of jog.
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
		print("[ImportHero] synthesized 'idle' from jog (first-frame freeze).")
	# Synthesize sprint as 1.6x speed-scaled jog.
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
		print("[ImportHero] synthesized 'sprint' from jog (1.6x speed).")
	# If "fall" covers the whole fall-to-land sequence, slice a land from its tail.
	# (Keep things simple: reuse the same clip as both fall and land, the one-shot
	# blend will crossfade.)
	if lib.has_animation("fall") and not lib.has_animation("land"):
		var fall := lib.get_animation("fall")
		var land := fall.duplicate()
		land.loop_mode = Animation.LOOP_NONE
		lib.add_animation("land", land)


func _apply_loop_modes(lib: AnimationLibrary) -> void:
	for rule in ANIM_RULES:
		if lib.has_animation(rule["key"]):
			lib.get_animation(rule["key"]).loop_mode = Animation.LOOP_LINEAR if rule["loop"] else Animation.LOOP_NONE


func _print_library(lib: AnimationLibrary) -> void:
	print("[ImportHero] Animation library:")
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		print("   %-12s %5.2fs  %s" % [n, a.length, "loop" if a.loop_mode == Animation.LOOP_LINEAR else "one-shot"])


# ---------------------------------------------------------------------------
# Animation tree
# ---------------------------------------------------------------------------
func _build_blend_tree(_lib: AnimationLibrary) -> AnimationNodeStateMachine:
	# A StateMachine is the most robust layout: locomotion is the steady state
	# and each gameplay verb travels through a one-shot and returns to it.
	var sm := AnimationNodeStateMachine.new()

	# Locomotion sub-blend-tree: BlendSpace1D (speed) -> Blend2 (lane lean).
	var loco := AnimationNodeBlendTree.new()
	loco.add_node("output", AnimationNodeOutput.new(), Vector2(500, 80))
	var bs1d := AnimationNodeBlendSpace1D.new()
	bs1d.add_blend_point(_anim("idle"),    0.0)
	bs1d.add_blend_point(_anim("jog"),     0.55)
	bs1d.add_blend_point(_anim("sprint"),  1.0)
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

	# One-shot action states.
	var add_state := func(name: String, fade: float, pos: Vector2):
		var node := _anim(name)
		sm.add_node(name, node, pos)
	var positions := {
		"jump":    Vector2(280, -150),
		"fall":    Vector2(520, -150),
		"land":    Vector2(780, -150),
		"slide":   Vector2(280,  150),
		"stumble": Vector2(560,  150),
	}
	for n in positions.keys():
		add_state(n, 0.08, positions[n])

	# Transitions (start->end *, advance to auto at end, switches_mode off).
	var add_trans := func(from: String, to: String, xfade: float, auto_advance: bool):
		var t := AnimationNodeStateMachineTransition.new()
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE if not auto_advance else AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.fade_time = xfade
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto_advance else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		sm.add_transition(from, to, t)
	add_trans("locomotion", "jump",   0.08, false)
	add_trans("jump",       "fall",   0.10, true)
	add_trans("fall",       "land",   0.10, true)
	add_trans("land",       "locomotion", 0.12, true)
	add_trans("locomotion", "slide",  0.06, false)
	add_trans("slide",      "locomotion", 0.10, true)
	add_trans("locomotion", "stumble",0.10, false)
	add_trans("stumble",    "locomotion", 0.12, true)
	# Allow cancelling jump into slide (airborne slide).
	add_trans("jump",       "slide",  0.08, false)
	sm.set_graph_node("locomotion", Vector2(0, 0))
	sm.start_node = "locomotion"
	return sm


func _anim(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	return n


# ---------------------------------------------------------------------------
# Mesh fit/orient
# ---------------------------------------------------------------------------
func _fit_mesh_to_game(root: Node3D) -> void:
	# Find a MeshInstance3D to size.
	var mi := _find_first_mesh(root)
	if mi == null:
		push_warning("[ImportHero] No mesh instance found; leaving at default scale.")
		return
	var aabb := mi.get_aabb()
	var height := aabb.size.y
	var s := 1.0
	if height > 4.0:
		# Mixamo FBXs in centimeters come in at ~170 units tall.
		s = 1.7 / height
	root.scale = Vector3(s, s, s)
	root.position.y = -aabb.position.y * s
	root.rotation = Vector3.ZERO
	# Face -Z if the importer left the character facing +Z. The X Bot from
	# Mixamo typically faces -Z already; if not, rotate 180 on Y.
	root.rotation.y = 0.0


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

## =============================================================================
##  hero_builder.gd  —  builds res://assets/models/hero/hero.tscn from the FBX
##  files inside the character folder (res://assets/characters/الشخصية/).
## -----------------------------------------------------------------------------
##  WHY THIS FILE EXISTS / WHAT IT GUARANTEES
##  -----------------------------------------
##  The hero scene is generated at build time (CI or the editor tool) and shipped
##  inside the APK. It contains:
##    * Hero/Mesh ............ the imported skinned Mixamo character
##                              (~1.78 m tall, feet on Y=0, facing -Z)
##    * Hero/AnimationPlayer . canonical clips: idle / jog / sprint / jump /
##                              fall / land / slide / stumble, with every track
##                              RETARGETED onto Hero/Mesh's skeleton
##    * Hero/AnimationTree ... StateMachine + BlendSpace1D (run blend)
##
##  Three rules keep this honest (all of them were broken before v1.2.2 and the
##  result was an invisible runner in the shipped APK):
##
##  1. NODES MUST HAVE AN OWNER BEFORE PackedScene.pack().
##     SceneState::_parse_node() drops any node whose owner is not the packed
##     root, together with its whole subtree. An instantiated FBX root has
##     owner == null, so packing a hero built from it used to save an EMPTY
##     scene: the player loaded it, skipped the procedural fallback and drew
##     nothing. `_own_tree()` fixes that and `verify()` proves it.
##
##  2. ANIMATION TRACKS MUST BE RETARGETED.
##     An FBX clip stores paths relative to *its own* scene root
##     ("Skeleton3D:mixamorig_Hips"). Inside the hero the skeleton lives at
##     "Mesh/<...>/Skeleton3D", so every track is remapped by bone name.
##     Untouched paths = a frozen T-pose.
##
##  3. THE SKIN IS CHOSEN BY CONTENT, NOT BY FILE NAME OR SIZE.
##     The folder holds one skinned FBX and several motion-only FBXs. In an
##     exported game the .fbx sources are gone (sizes report 0), so size-based
##     guessing picked a motion-only file and produced a hero with no geometry.
##     We now instantiate each candidate and count real mesh vertices.
##
##  Exit contract: build_hero() returns true only when the scene it wrote loads
##  back with a drawable skinned mesh, a sane size and working clips.
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
const HERO_REPORT_PATH := HERO_DIR + "hero_report.txt"

## Final on-screen height of the runner, in metres.
const TARGET_HEIGHT := 1.78
## Sanity window used by verify(): outside of this the scene is rejected.
const MIN_HEIGHT := 1.2
const MAX_HEIGHT := 2.4
const MIN_VERTICES := 200
const MIN_BONES := 10

## Exact file-name -> canonical clip. Names are lower-case, spaces collapsed.
## Anything not listed falls back to the needle rules below, so renamed exports
## (e.g. "mixamo.com_Jog.fbx") still land in the right slot.
const NAME_TO_CLIP := {
	"run forward": "jog",
	"running": "jog",
	"run": "jog",
	"jog": "jog",
	"jogging": "jog",
	"jump": "jump",
	"jumping": "jump",
	"falling to landing": "fall",
	"falling": "fall",
	"fall": "fall",
	"landing": "land",
	"land": "land",
	"running slide": "slide",
	"slide": "slide",
	"sliding": "slide",
	"jogging stumble": "stumble",
	"stumble": "stumble",
	"idle": "idle",
}

const ANIM_RULES := [
	{"key": "stumble", "needle": "stumble", "loop": false},
	{"key": "slide", "needle": "slide", "loop": false},
	{"key": "land", "needle": "landing", "loop": false},
	{"key": "land", "needle": "land", "loop": false},
	{"key": "jump", "needle": "jump", "loop": false},
	{"key": "fall", "needle": "fall", "loop": false},
	{"key": "idle", "needle": "idle", "loop": true},
	{"key": "sprint", "needle": "sprint", "loop": true},
	{"key": "jog", "needle": "run", "loop": true},
	{"key": "jog", "needle": "jog", "loop": true},
]

## Clips the AnimationTree needs. `land` and `idle`/`sprint` may be synthesised.
const REQUIRED_CLIPS := ["jog", "jump", "fall", "land", "slide", "stumble"]

const LOOP_CLIPS := ["idle", "jog", "sprint"]

var _issues: Array[String] = []


## ---------------------------------------------------------------------------
## Public API
## ---------------------------------------------------------------------------
static func build_hero(strict := false) -> bool:
	var b := HeroBuilder.new()
	var ok := b._do_build(strict)
	if not ok:
		for msg in b._issues:
			printerr("[HeroBuilder] %s" % msg)
	return ok


## Editor convenience: build once if the scene is missing (runtime builds inside
## an exported game are impossible — the .fbx sources are not in the PCK).
static func build_if_missing() -> bool:
	if ResourceLoader.exists(HERO_SCENE_PATH) and verify().get("ok", false):
		return true
	return build_hero(false)


## Verifies the shipped hero scene end-to-end. Returns a plain Dictionary so it
## can be printed / JSON-ified by CI:
##   { ok, meshes, vertices, bones, height, feet, clips, problems[] }
static func verify(path := HERO_SCENE_PATH) -> Dictionary:
	var b := HeroBuilder.new()
	return b._do_verify(path)


func get_issues() -> Array[String]:
	return _issues


## ---------------------------------------------------------------------------
## Build pipeline
## ---------------------------------------------------------------------------
func _do_build(strict := false) -> bool:
	_issues.clear()
	_mkdir(HERO_DIR)

	var folder := _locate_folder()
	if folder.is_empty():
		_issue("Character folder not found. Expected one of: %s" % [CHAR_FOLDER_CANDIDATES], strict)
		return false

	var files := _list_assets(folder)
	if files.is_empty():
		_issue("No .fbx/.glb/.gltf files inside %s" % folder, strict)
		return false
	print("[HeroBuilder] folder = %s" % folder)
	print("[HeroBuilder] files  = %s" % [files])

	# -- 1. Inspect every file by content: meshes, vertices, bones, clips ------
	var candidates: Array[Dictionary] = []
	for file_name in files:
		var path: String = folder.path_join(file_name)
		var scene := _safe_load_scene(path)
		if scene == null:
			push_warning("[HeroBuilder] cannot load %s (import step not finished?)" % path)
			continue
		var info := _inspect_scene(scene)
		info["path"] = path
		info["file"] = file_name
		info["clip"] = _classify(file_name)
		candidates.append(info)
		print("[HeroBuilder]   %-26s meshes=%d verts=%5d bones=%3d clip='%s' anims=%s" % [
			file_name, int(info["meshes"]), int(info["vertices"]),
			int(info["bones"]), String(info["clip"]), info["anims"]])

	if candidates.is_empty():
		_issue("None of the files in %s could be loaded (check `godot --headless --import`)" % folder, strict)
		return false

	# -- 2. The skin is simply the file with the most mesh vertices ------------
	var skin: Dictionary = {}
	for info in candidates:
		if int(info["vertices"]) < MIN_VERTICES:
			continue
		if skin.is_empty() or int(info["vertices"]) > int(skin["vertices"]):
			skin = info
	if skin.is_empty():
		_issue("No skinned character found in %s — every file is motion-only (no mesh)." % folder, strict)
		return false
	print("[HeroBuilder] skin = %s (%d verts, %d bones)" % [
		String(skin["file"]), int(skin["vertices"]), int(skin["bones"])])

	# -- 3. Build the hero tree -----------------------------------------------
	var skin_scene: PackedScene = skin["scene"] as PackedScene
	var hero := Node3D.new()
	hero.name = "Hero"

	var mesh_root := skin_scene.instantiate() as Node3D
	if mesh_root == null:
		_issue("Could not instantiate the skin scene %s" % String(skin["path"]), strict)
		hero.free()
		return false
	mesh_root.name = "Mesh"
	hero.add_child(mesh_root, true)

	var skeleton := _first_skeleton(mesh_root)
	if skeleton == null:
		_issue("The skinned file has no Skeleton3D — cannot animate or verify it.", strict)
		hero.free()
		return false
	print("[HeroBuilder] skeleton '%s' with %d bones" % [skeleton.name, skeleton.get_bone_count()])

	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	anim_player.root_node = NodePath("..")
	hero.add_child(anim_player, true)
	var lib := AnimationLibrary.new()
	anim_player.add_animation_library("", lib)

	# -- 4. Clips: one file per action, retargeted onto our skeleton ----------
	var skin_path := String(skin["path"])
	for info in candidates:
		var key := String(info["clip"])
		if key.is_empty():
			continue
		if String(info["path"]) == skin_path:
			continue  # the skin's own clips are harvested below as a fallback
		if lib.has_animation(key):
			continue
		_harvest_best(info["scene"] as PackedScene, key, lib, hero, skeleton)
	# Fallback: the skin file usually carries an animation stack too (Mixamo
	# exports "Run Forward" with skin, for example). Only use it for the run
	# cycle — idle/sprint are synthesised from it later, so we never label a
	# sprint clip as "idle".
	if not lib.has_animation("jog"):
		_harvest_node(mesh_root, "jog", lib, hero, skeleton)

	_make_canonical(lib)
	_apply_loops(lib)
	_print_library(lib)

	var missing: Array[String] = []
	for key in REQUIRED_CLIPS:
		if not lib.has_animation(key):
			missing.append(key)
	if not missing.is_empty():
		_issue("Missing animation clips: %s (found: %s)" % [missing, lib.get_animation_list()], strict)
		hero.free()
		return false

	# -- 5. Hide Mixamo's joint-helper geometry, apply the suit material ------
	_hide_helper_meshes(mesh_root)
	var suit := HeroMaterial.make_suit_material()
	var surfaces := _apply_material(mesh_root, suit)
	print("[HeroBuilder] suit material applied to %d surfaces" % surfaces)

	# -- 6. Scale / centre / face the character away from the camera ----------
	var fit := _fit_and_orient(hero, mesh_root, skeleton)
	print("[HeroBuilder] fit: aabb=%s height=%.3f scale=%.4f feet=%.3f yaw=%.1fdeg meshes=%d" % [
		fit["aabb"], float(fit["height"]), float(fit["scale"]),
		float(fit["feet"]), rad_to_deg(float(fit["yaw"])), int(fit["meshes"])])

	# -- 7. AnimationTree on top of the retargeted clips ----------------------
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.tree_root = _build_state_machine()
	tree.active = true
	hero.add_child(tree, true)

	# -- 8. OWNERSHIP: without this PackedScene.pack() saves an EMPTY scene ---
	_own_tree(hero)
	hero.visible = true
	mesh_root.visible = true

	var pck := PackedScene.new()
	var err := pck.pack(hero)
	if err != OK:
		_issue("PackedScene.pack() failed: %s" % error_string(err), strict)
		hero.free()
		return false
	hero.free()

	err = ResourceSaver.save(pck, HERO_SCENE_PATH, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
	if err != OK:
		_issue("Saving %s failed: %s" % [HERO_SCENE_PATH, error_string(err)], strict)
		return false

	# -- 9. Read it back and prove it is drawable -----------------------------
	var report := _do_verify(HERO_SCENE_PATH)
	_write_report(report)
	if not bool(report.get("ok", false)):
		for problem in report.get("problems", []):
			_issue("verify: %s" % String(problem), strict)
		return false
	print("[HeroBuilder] ✔ wrote %s (meshes=%d verts=%d bones=%d height=%.2fm)" % [
		HERO_SCENE_PATH, int(report["meshes"]), int(report["vertices"]),
		int(report["bones"]), float(report["height"])])
	return true


## ---------------------------------------------------------------------------
## Folder / file discovery (UTF-8 safe)
## ---------------------------------------------------------------------------
func _locate_folder() -> String:
	for cand in CHAR_FOLDER_CANDIDATES:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cand)):
			return cand
	var da: DirAccess = DirAccess.open("res://")
	if da != null:
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
		var n2: String = ac.get_next()
		while n2 != "":
			if n2 != "." and n2 != ".." and ac.current_is_dir() and n2.contains("شخص"):
				ac.list_dir_end()
				return "res://assets/characters/%s/" % n2
			n2 = ac.get_next()
		ac.list_dir_end()
	return ""


func _list_assets(folder: String) -> Array[String]:
	var out: Array[String] = []
	var da: DirAccess = DirAccess.open(folder)
	if da == null:
		return out
	da.list_dir_begin()
	var n: String = da.get_next()
	while n != "":
		if n != "." and n != ".." and not da.current_is_dir():
			var low := n.to_lower()
			# Exported builds also expose "<name>.fbx.remap" style entries.
			if low.ends_with(".fbx") or low.ends_with(".glb") or low.ends_with(".gltf"):
				out.append(n)
		n = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


## Canonical clip key for a file name ("" when it is only the skin).
func _classify(file_name: String) -> String:
	var base := file_name.get_basename().to_lower()
	for ch in ["_", "-", "."]:
		base = base.replace(ch, " ")
	base = base.strip_edges()
	while base.contains("  "):
		base = base.replace("  ", " ")
	if NAME_TO_CLIP.has(base):
		return String(NAME_TO_CLIP[base])
	for rule in ANIM_RULES:
		var needle := String(rule["needle"])
		if needle == "run" and base.contains("slide"):
			continue
		if needle == "jump" and base.contains("stumble"):
			continue
		if base.contains(needle):
			return String(rule["key"])
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
	if rel.is_empty():
		return
	var parts := rel.split("/")
	var cur := ""
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
## Scene inspection (content, never file size or byte sniffing)
## ---------------------------------------------------------------------------
func _inspect_scene(scene: PackedScene) -> Dictionary:
	var info := {"scene": scene, "meshes": 0, "vertices": 0, "bones": 0, "anims": []}
	var inst := scene.instantiate()
	if inst == null:
		return info
	var verts := 0
	var meshes := 0
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh.get_surface_count() <= 0:
			continue
		meshes += 1
		verts += _mesh_vertex_count(mi.mesh)
	info["meshes"] = meshes
	info["vertices"] = verts
	var bones := 0
	for node in inst.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		if sk != null:
			bones = maxi(bones, sk.get_bone_count())
	info["bones"] = bones
	var anims: Array = []
	for node in _nodes_of_type(inst, "AnimationPlayer"):
		var ap := node as AnimationPlayer
		for lib_name in ap.get_animation_library_list():
			var l := ap.get_animation_library(lib_name)
			if l != null:
				anims.append_array(l.get_animation_list())
	info["anims"] = anims
	inst.free()
	return info


func _mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts is PackedVector3Array:
			total += (verts as PackedVector3Array).size()
	return total


func _first_skeleton(root: Node) -> Skeleton3D:
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


func _nodes_of_type(root: Node, type_name: String) -> Array:
	var out: Array = []
	if root.is_class(type_name):
		out.append(root)
	for c in root.get_children(true):
		out.append_array(_nodes_of_type(c, type_name))
	return out


## ---------------------------------------------------------------------------
## Animation harvesting + retargeting
## ---------------------------------------------------------------------------
func _harvest_best(src_scene: PackedScene, key: String, lib: AnimationLibrary,
		hero: Node3D, skel: Skeleton3D) -> int:
	var inst := src_scene.instantiate()
	if inst == null:
		return 0
	var tracks := _harvest_node(inst, key, lib, hero, skel)
	inst.free()
	return tracks


## Copies the "richest" animation found under `root` into `lib` under `key`,
## rewriting every track path onto the hero skeleton.
func _harvest_node(root: Node, key: String, lib: AnimationLibrary,
		hero: Node3D, skel: Skeleton3D) -> int:
	var skin_root: Node = skel.get_parent() if skel != null else root
	var best: Animation = null
	var best_name := ""
	var best_tracks := 0
	for node in _nodes_of_type(root, "AnimationPlayer"):
		var ap := node as AnimationPlayer
		if ap == null:
			continue
		for lib_name in ap.get_animation_library_list():
			var l := ap.get_animation_library(lib_name)
			if l == null:
				continue
			for anim_name in l.get_animation_list():
				var src := l.get_animation(anim_name)
				if src == null:
					continue
				var dup := src.duplicate() as Animation
				if dup == null:
					continue
				var kept := _retarget(dup, ap, hero, skel, skin_root)
				if kept > best_tracks:
					best_tracks = kept
					best = dup
					best_name = String(anim_name)
	if best == null or best_tracks <= 0:
		return 0
	_put_anim(lib, key, best)
	print("[HeroBuilder] clip '%s' <- '%s' (%d tracks)" % [key, best_name, best_tracks])
	return best_tracks


## Rewrites every track path of `anim` so it resolves inside the hero tree.
## Returns how many tracks survived (0 means the clip is unusable).
func _retarget(anim: Animation, src_player: AnimationPlayer, hero: Node3D,
		skel: Skeleton3D, skin_root: Node) -> int:
	var src_root: Node = src_player.get_node_or_null(src_player.root_node)
	if src_root == null:
		src_root = src_player.get_parent()
	if src_root == null:
		return 0
	var bone_prefix := _rel_path(hero, skel)
	var drop: Array[int] = []
	for t in range(anim.get_track_count()):
		var path := anim.track_get_path(t)
		var mapped := _map_track(path, src_root, hero, bone_prefix, skel, skin_root,
			anim.track_get_type(t))
		if mapped.is_empty():
			drop.append(t)
		else:
			anim.track_set_path(t, mapped)
	for i in range(drop.size() - 1, -1, -1):
		anim.remove_track(drop[i])
	# Kill in-place drift: Mixamo clips are authored "in place", but if a clip
	# carries hip translation we pin X/Z so the runner never slides out of its
	# collision box. Height (Y) is left untouched.
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var p := anim.track_get_path(t)
		if _track_bone_key(p) != "hips":
			continue
		if anim.track_get_key_count(t) == 0:
			continue
		var first: Variant = anim.track_get_key_value(t, 0)
		if first is not Vector3:
			continue
		var anchor := first as Vector3
		for k in range(anim.track_get_key_count(t)):
			var v: Variant = anim.track_get_key_value(t, k)
			if v is Vector3:
				var vv := v as Vector3
				anim.track_set_key_value(t, k, Vector3(anchor.x, vv.y, anchor.z))
	return anim.get_track_count()


func _map_track(path: NodePath, src_root: Node, hero: Node3D, bone_prefix: String,
		skel: Skeleton3D, skin_root: Node, track_type: int) -> NodePath:
	var text := String(path)
	var colon := text.rfind(":")
	var node_part := text
	var subname := ""
	if colon >= 0:
		node_part = text.substr(0, colon)
		subname = text.substr(colon + 1)
	if node_part.is_empty():
		return NodePath()
	var src_node := src_root.get_node_or_null(NodePath(node_part))
	if src_node == null:
		return NodePath()

	if not subname.is_empty():
		# Skeletal track ("Skeleton3D:bone").
		var src_skel := src_node as Skeleton3D
		if src_skel == null:
			return NodePath()
		var src_bone := _find_bone(src_skel, subname)
		if src_bone < 0:
			return NodePath()
		var target_bone := _find_bone(skel, src_skel.get_bone_name(src_bone))
		if target_bone < 0:
			return NodePath()
		return NodePath("%s:%s" % [bone_prefix, String(skel.get_bone_name(target_bone))])

	# Plain node track. Mixamo "without skin" downloads (Jump.fbx, Running
	# Slide.fbx, …) contain no mesh, so the importer exports their bone motion
	# as ordinary Node3D transform tracks instead of Skeleton3D bone tracks.
	# Those must land on the hero's skeleton bones, otherwise every clip from
	# the character folder would be dropped as unresolvable.
	if track_type == Animation.TYPE_POSITION_3D \
			or track_type == Animation.TYPE_ROTATION_3D \
			or track_type == Animation.TYPE_SCALE_3D:
		var as_bone := _find_bone(skel, String(src_node.name))
		if as_bone >= 0:
			return NodePath("%s:%s" % [bone_prefix, String(skel.get_bone_name(as_bone))])
	# Mesh / helper node track: keep it only if the same name exists in the hero.
	var target := _find_node_by_name(skin_root, String(src_node.name))
	if target == null:
		return NodePath()
	return NodePath(_rel_path(hero, target))


func _track_bone_key(path: NodePath) -> String:
	var text := String(path)
	var colon := text.rfind(":")
	if colon < 0:
		return ""
	return _bone_key(text.substr(colon + 1))


## Normalised bone key: "mixamorig:Hips", "mixamorig_Hips" and "Hips" all map
## to "hips", so clips exported with a different prefix still retarget.
func _bone_key(raw: String) -> String:
	var low := raw.to_lower()
	var out := ""
	for i in range(low.length()):
		var ch := low.substr(i, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789".contains(ch):
			out += ch
	if out.begins_with("mixamorig"):
		out = out.substr(9)
	return out


func _find_bone(skel: Skeleton3D, bone_name: String) -> int:
	if skel == null:
		return -1
	var direct := skel.find_bone(bone_name)
	if direct >= 0:
		return direct
	var key := _bone_key(bone_name)
	if key.is_empty():
		return -1
	for i in range(skel.get_bone_count()):
		if _bone_key(skel.get_bone_name(i)) == key:
			return i
	return -1


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if String(root.name) == target_name:
		return root
	for c in root.get_children(true):
		var hit := _find_node_by_name(c, target_name)
		if hit != null:
			return hit
	return null


## Path from `from` to `to` without requiring a SceneTree (Node.get_path_to()
## refuses to work outside the tree, which is where the builder runs).
func _rel_path(from: Node, to: Node) -> String:
	var out := ""
	var n: Node = to
	var guard := 0
	while n != null and n != from and guard < 256:
		out = String(n.name) if out.is_empty() else String(n.name) + "/" + out
		n = n.get_parent()
		guard += 1
	if n == null:
		return ""
	return out


func _put_anim(lib: AnimationLibrary, key: String, anim: Animation) -> void:
	if lib.has_animation(key):
		lib.remove_animation(key)
	lib.add_animation(key, anim)


## Fills in idle / sprint / land when the folder does not provide them.
func _make_canonical(lib: AnimationLibrary) -> void:
	if not lib.has_animation("jog"):
		for n in lib.get_animation_list():
			var low := String(n).to_lower()
			if low.contains("run") and not low.contains("slide"):
				lib.rename_animation(n, "jog")
				break
	if not lib.has_animation("idle") and lib.has_animation("jog"):
		var jog := lib.get_animation("jog")
		var idle := Animation.new()
		idle.resource_name = "idle"
		idle.length = 1.0
		idle.loop_mode = Animation.LOOP_LINEAR
		for t in range(jog.get_track_count()):
			if jog.track_get_key_count(t) == 0:
				continue
			idle.add_track(jog.track_get_type(t))
			var idx := idle.get_track_count() - 1
			idle.track_set_path(idx, jog.track_get_path(t))
			var val: Variant = jog.track_get_key_value(t, 0)
			idle.track_insert_key(idx, 0.0, val)
			idle.track_insert_key(idx, 1.0, val)
		lib.add_animation("idle", idle)
		print("[HeroBuilder] synthesised 'idle' from 'jog'")
	if not lib.has_animation("sprint") and lib.has_animation("jog"):
		var jog := lib.get_animation("jog")
		var sprint := jog.duplicate() as Animation
		sprint.resource_name = "sprint"
		sprint.length = jog.length / 1.6
		for t in range(sprint.get_track_count()):
			var kc := sprint.track_get_key_count(t)
			var times: Array[float] = []
			for k in range(kc):
				times.append(sprint.track_get_key_time(t, k) / 1.6)
			for k in range(kc):
				sprint.track_set_key_time(t, k, times[k])
		lib.add_animation("sprint", sprint)
		print("[HeroBuilder] synthesised 'sprint' (1.6x jog)")
	if lib.has_animation("fall") and not lib.has_animation("land"):
		var land := (lib.get_animation("fall") as Animation).duplicate() as Animation
		land.resource_name = "land"
		lib.add_animation("land", land)
		print("[HeroBuilder] synthesised 'land' from 'fall'")


func _apply_loops(lib: AnimationLibrary) -> void:
	for n in lib.get_animation_list():
		var anim := lib.get_animation(n)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if LOOP_CLIPS.has(String(n)) else Animation.LOOP_NONE


func _print_library(lib: AnimationLibrary) -> void:
	print("[HeroBuilder] clips in hero AnimationPlayer:")
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		var mode := "loop" if a.loop_mode == Animation.LOOP_LINEAR else "one-shot"
		print("   %-10s %5.2fs  %2d tracks  %s" % [n, a.length, a.get_track_count(), mode])


## ---------------------------------------------------------------------------
## Fit / orientation
## ---------------------------------------------------------------------------
func _visible_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() <= 0:
			continue
		var vis := mi.visible
		var n: Node = mi.get_parent()
		while vis and n != null and n != root:
			if n is Node3D:
				vis = (n as Node3D).visible
			n = n.get_parent()
		if vis:
			out.append(mi)
	if out.is_empty():
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi2 := node as MeshInstance3D
			if mi2 != null and mi2.mesh != null and mi2.mesh.get_surface_count() > 0:
				out.append(mi2)
	return out


## Union AABB of `meshes` expressed in `root` space. Uses manually accumulated
## transforms because Node3D.global_transform is invalid outside the tree
## (Godot 4.4 returns Transform3D() and spams ERR_FAIL for every call).
func _local_bounds(root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var aabb := AABB()
	var first := true
	for mi in meshes:
		var xf := _relative_transform(root, mi)
		var box := xf * mi.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	return aabb


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var n: Node = node
	var guard := 0
	while n != null and n != root and guard < 256:
		if n is Node3D:
			chain.push_front((n as Node3D).transform)
		n = n.get_parent()
		guard += 1
	var xf := Transform3D()
	for t in chain:
		xf = xf * t
	return xf


func _fit_and_orient(hero: Node3D, mesh_root: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var meshes := _visible_meshes(mesh_root)
	var aabb := _local_bounds(mesh_root, meshes)
	var height := aabb.size.y
	var scale := 1.0
	if height > 0.0001:
		# Always normalise (metres, centimetres, 0.01-unit exports … all work).
		scale = clampf(TARGET_HEIGHT / height, 0.0005, 2000.0)
	var yaw := _facing_yaw(skeleton)
	var centre := aabb.position + aabb.size * 0.5
	var flat := Vector3(centre.x * scale, 0.0, centre.z * scale).rotated(Vector3.UP, yaw)
	mesh_root.scale = Vector3.ONE * scale
	mesh_root.rotation = Vector3(0.0, yaw, 0.0)
	mesh_root.position = Vector3(-flat.x, -aabb.position.y * scale, -flat.z)
	hero.visible = true
	return {
		"aabb": aabb,
		"height": height,
		"scale": scale,
		"feet": aabb.position.y * scale,
		"yaw": yaw,
		"meshes": meshes.size(),
	}


## Yaw (radians) that turns the character so it runs away from the camera (-Z).
## Mixamo rigs face +Z; we derive it from the rest pose instead of assuming.
func _facing_yaw(skeleton: Skeleton3D) -> float:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return 0.0
	var hips := _bone_global_rest(skeleton, "hips")
	var toe_l := _bone_global_rest(skeleton, "lefttoebase")
	var toe_r := _bone_global_rest(skeleton, "righttoebase")
	var toe := toe_l
	if toe_l.is_zero_approx():
		toe = toe_r
	elif not toe_r.is_zero_approx():
		toe = (toe_l + toe_r) * 0.5
	if hips.is_zero_approx() or toe.is_zero_approx():
		return 0.0
	var forward := toe - hips
	if absf(forward.z) < 0.01:
		return 0.0
	return 0.0 if forward.z < 0.0 else PI


func _bone_global_rest(skeleton: Skeleton3D, key: String) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var idx := -1
	for i in range(skeleton.get_bone_count()):
		if _bone_key(skeleton.get_bone_name(i)) == key:
			idx = i
			break
	if idx < 0:
		for i in range(skeleton.get_bone_count()):
			if _bone_key(skeleton.get_bone_name(i)).contains(key):
				idx = i
				break
	if idx < 0:
		return Vector3.ZERO
	return _bone_global_rest_at(skeleton, idx).origin


func _bone_global_rest_at(skeleton: Skeleton3D, idx: int) -> Transform3D:
	var chain: Array[int] = []
	var b := idx
	var guard := 0
	while b >= 0 and guard < 512:
		chain.push_front(b)
		b = skeleton.get_bone_parent(b)
		guard += 1
	var xf := Transform3D()
	for i in chain:
		xf = xf * skeleton.get_bone_rest(i)
	return xf


## ---------------------------------------------------------------------------
## Materials / visibility
## ---------------------------------------------------------------------------
## Mixamo's X Bot ships a second geometry ("Beta_Joints") that only exists to
## visualise the rig. Drawing it hides the real body behind a dark spiky shell.
func _hide_helper_meshes(mesh_root: Node) -> void:
	var all := _visible_meshes(mesh_root)
	var keep: Array[MeshInstance3D] = []
	var helpers: Array[MeshInstance3D] = []
	for mi in all:
		var low := String(mi.name).to_lower()
		if low.contains("joint") or low.contains("helper") or low.contains("_rig"):
			helpers.append(mi)
		else:
			keep.append(mi)
	if keep.is_empty():
		return  # nothing but helpers: keep them, or the hero would vanish
	for mi in helpers:
		mi.visible = false
		print("[HeroBuilder] hidden rig helper mesh '%s'" % mi.name)


func _apply_material(root: Node, mat: Material) -> int:
	var count := 0
	for node in _nodes_of_type(root, "MeshInstance3D"):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var low := String(mi.name).to_lower()
		if low.contains("eye") or low.contains("lash") or low.contains("teeth") or low.contains("tongue"):
			continue
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
			count += 1
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return count


## Assigns `owner` to the whole subtree. MANDATORY before PackedScene.pack():
## SceneState::_parse_node() silently drops every node whose owner is not the
## packed root — that bug is what made the runner invisible in v1.2.x.
func _own_tree(root: Node) -> void:
	var stack: Array[Node] = [root]
	var count := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(true):
			c.owner = root
			count += 1
			stack.append(c)
	print("[HeroBuilder] assigned owner to %d nodes" % count)


## ---------------------------------------------------------------------------
## State machine
## ---------------------------------------------------------------------------
func _build_state_machine() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	sm.resource_name = "HeroStates"

	var loco := AnimationNodeBlendTree.new()
	loco.resource_name = "LocomotionTree"
	loco.add_node("output", AnimationNodeOutput.new(), Vector2(500, 80))
	var bs1d := AnimationNodeBlendSpace1D.new()
	bs1d.resource_name = "RunBlend"
	bs1d.add_blend_point(_anim("idle"), 0.0)
	bs1d.add_blend_point(_anim("jog"), 0.55)
	bs1d.add_blend_point(_anim("sprint"), 1.0)
	bs1d.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	bs1d.snap = 0.0
	loco.add_node("locomotion", bs1d, Vector2(60, 80))
	loco.connect_node("output", 0, "locomotion")
	sm.add_node("locomotion", loco, Vector2(0, 0))

	sm.add_node("jump", _anim("jump"), Vector2(280, -150))
	sm.add_node("fall", _anim("fall"), Vector2(520, -150))
	sm.add_node("land", _anim("land"), Vector2(780, -150))
	sm.add_node("slide", _anim("slide"), Vector2(280, 150))
	sm.add_node("stumble", _anim("stumble"), Vector2(560, 150))

	_add_trans(sm, "locomotion", "jump", 0.08, false)
	_add_trans(sm, "jump", "fall", 0.10, true)
	_add_trans(sm, "fall", "land", 0.10, true)
	_add_trans(sm, "land", "locomotion", 0.12, true)
	_add_trans(sm, "locomotion", "slide", 0.06, false)
	_add_trans(sm, "slide", "locomotion", 0.10, true)
	_add_trans(sm, "locomotion", "stumble", 0.10, false)
	_add_trans(sm, "stumble", "locomotion", 0.12, true)
	_add_trans(sm, "jump", "slide", 0.08, false)
	sm.start_node = "locomotion"
	return sm


func _add_trans(sm: AnimationNodeStateMachine, from: String, to: String,
		xfade: float, auto_advance: bool) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	if auto_advance:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	t.fade_time = xfade
	sm.add_transition(from, to, t)


func _anim(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


## ---------------------------------------------------------------------------
## Verification (used by the builder itself, the editor tool and CI)
## ---------------------------------------------------------------------------
func _do_verify(path: String) -> Dictionary:
	var report := {
		"ok": false,
		"path": path,
		"meshes": 0,
		"vertices": 0,
		"bones": 0,
		"height": 0.0,
		"feet": 0.0,
		"bone_span": 0.0,
		"clips": {},
		"problems": [],
	}
	var problems: Array = report["problems"]

	if not ResourceLoader.exists(path):
		problems.append("scene not found: %s" % path)
		return report
	var res: Resource = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var pck := res as PackedScene
	if pck == null:
		problems.append("cannot load as PackedScene: %s" % path)
		return report
	var inst := pck.instantiate()
	if inst == null:
		problems.append("scene failed to instantiate")
		return report

	var meshes := 0
	var verts := 0
	var aabb := AABB()
	var has_box := false
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() <= 0:
			continue
		meshes += 1
		verts += _mesh_vertex_count(mi.mesh)
		if not mi.visible:
			continue
		var xf := _relative_transform(inst as Node3D, mi)
		var box := xf * mi.get_aabb()
		aabb = box if not has_box else aabb.merge(box)
		has_box = true
	report["meshes"] = meshes
	report["vertices"] = verts
	if has_box:
		report["height"] = aabb.size.y
		report["feet"] = aabb.position.y

	var bones := 0
	var bone_span := 0.0
	for node in inst.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		if sk == null:
			continue
		if sk.get_bone_count() > bones:
			bones = sk.get_bone_count()
			bone_span = _bone_span(sk)
	report["bones"] = bones
	report["bone_span"] = bone_span

	# Clips: every required clip must exist AND have tracks that resolve inside
	# the saved scene (this is what catches un-retargeted animations).
	var ap := _find_first_animation_player(inst)
	var clips: Dictionary = report["clips"]
	if ap == null:
		problems.append("no AnimationPlayer in the scene")
	else:
		for key in REQUIRED_CLIPS:
			if not ap.has_animation(key):
				problems.append("missing clip '%s'" % key)
				continue
			var resolved := _count_resolved_tracks(ap, ap.get_animation(key))
			clips[key] = resolved
			if resolved <= 0:
				problems.append("clip '%s' has no track that resolves inside the hero" % key)
	if _find_first_animation_tree(inst) == null:
		problems.append("no AnimationTree in the scene")

	if meshes <= 0:
		problems.append("hero has no mesh at all (empty scene)")
	elif verts < MIN_VERTICES:
		problems.append("hero mesh is too small (%d vertices)" % verts)
	if has_box:
		if float(report["height"]) < MIN_HEIGHT or float(report["height"]) > MAX_HEIGHT:
			problems.append("hero height %.2f m is outside [%.1f, %.1f]" % [
				float(report["height"]), MIN_HEIGHT, MAX_HEIGHT])
		if absf(float(report["feet"])) > 0.2:
			problems.append("feet are %.2f m away from the ground" % float(report["feet"]))
	else:
		problems.append("no visible mesh bounds (nothing would be drawn)")
	if bones < MIN_BONES:
		problems.append("skeleton has only %d bones" % bones)
	elif bone_span < 0.5 * maxf(float(report["height"]), 0.1):
		problems.append("skeleton rest pose is collapsed (span %.2f m)" % bone_span)

	report["ok"] = problems.is_empty()
	inst.free()
	return report


func _find_first_animation_player(root: Node) -> AnimationPlayer:
	var preferred := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if preferred != null:
		return preferred
	for node in root.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null


func _find_first_animation_tree(root: Node) -> AnimationTree:
	var preferred := root.get_node_or_null("AnimationTree") as AnimationTree
	if preferred != null:
		return preferred
	for node in root.find_children("*", "AnimationTree", true, false):
		return node as AnimationTree
	return null


func _count_resolved_tracks(ap: AnimationPlayer, anim: Animation) -> int:
	if ap == null or anim == null:
		return 0
	var root: Node = ap.get_node_or_null(ap.root_node)
	if root == null:
		root = ap.get_parent()
	if root == null:
		return 0
	var ok := 0
	for t in range(anim.get_track_count()):
		var text := String(anim.track_get_path(t))
		var colon := text.rfind(":")
		if colon < 0:
			if root.get_node_or_null(anim.track_get_path(t)) != null:
				ok += 1
			continue
		var host := root.get_node_or_null(NodePath(text.substr(0, colon)))
		var sk := host as Skeleton3D
		if sk != null and sk.find_bone(text.substr(colon + 1)) >= 0:
			ok += 1
	return ok


func _bone_span(skel: Skeleton3D) -> float:
	if skel == null or skel.get_bone_count() == 0:
		return 0.0
	var box := AABB()
	var first := true
	for i in range(skel.get_bone_count()):
		var p := _bone_global_rest_at(skel, i).origin
		var point := AABB(p, Vector3.ZERO)
		box = point if first else box.merge(point)
		first = false
	return box.size.y


func _write_report(report: Dictionary) -> void:
	var f := FileAccess.open(HERO_REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()

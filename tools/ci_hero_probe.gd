extends SceneTree
## =============================================================================
##  ci_hero_probe.gd — headless proof that the hero really ANIMATES in-game.
## -----------------------------------------------------------------------------
##  tools/ci_verify_hero.gd proves the generated scene has geometry, bones and
##  resolvable animation tracks. It cannot prove that something *drives* those
##  tracks at runtime — v1.2.2 shipped a scene that passed every data check and
##  still stood in a T-pose (the run cycle had been taken from Mixamo's static
##  "Take 001" stack, and the saved AnimationTree had no root).
##
##  This probe therefore reproduces the real runtime wiring:
##     Player(Node3D) ── "Model" (hero.tscn) ── AnimationPlayer
##                     └─ AnimationHandler (scripts/player/player_animation_handler.gd)
##  then lets the handler run for a few frames and compares skeleton poses.
##  A frozen skeleton means the character is not animated, and this exits 1.
##
##  Usage:  godot --headless --script tools/ci_hero_probe.gd [-- --strict]
## =============================================================================

const HERO_PATH := "res://assets/models/hero/hero.tscn"
const HANDLER_PATH := "res://scripts/player/player_animation_handler.gd"

var _player: Node3D        # stand-in for the player CharacterBody3D
var _hero: Node3D
var _handler: Node
var _skeleton: Skeleton3D
var _ap: AnimationPlayer
var _frame := 0
var _before: Array = []
var _strict := false


func _initialize() -> void:
	_strict = "--strict" in OS.get_cmdline_args() or "--strict" in OS.get_cmdline_user_args()
	print("[HeroProbe] Godot %s" % Engine.get_version_info().string)
	_test_raw_import()

	if not ResourceLoader.exists(HERO_PATH):
		_fail("%s not found" % HERO_PATH)
		return
	var pck := load(HERO_PATH) as PackedScene
	if pck == null:
		_fail("cannot load hero scene")
		return
	_hero = pck.instantiate() as Node3D
	if _hero == null:
		_fail("hero scene is not a Node3D")
		return

	# Mirror PlayerController: hero lives under the player as "Model".
	_player = Node3D.new()
	_player.name = "ProbePlayer"
	root.add_child(_player)
	_hero.name = "Model"
	_player.add_child(_hero)

	_skeleton = _find_skeleton(_hero)
	_ap = _hero.get_node_or_null("AnimationPlayer") as AnimationPlayer

	print("[HeroProbe] hero children: %s" % _names(_hero.get_children()))
	print("[HeroProbe] skeleton=%s bones=%d" % [
		_skeleton.name if _skeleton != null else "<none>",
		_skeleton.get_bone_count() if _skeleton != null else 0])
	print("[HeroProbe] clips=%s" % [
		_ap.get_animation_list() if _ap != null else PackedStringArray()])

	if _skeleton == null or _ap == null:
		_fail("missing skeleton / AnimationPlayer")
		return

	# Attach the REAL runtime handler (its _ready() binds and connects).
	var handler_script := load(HANDLER_PATH)
	if handler_script == null:
		_fail("cannot load %s" % HANDLER_PATH)
		return
	_handler = Node.new()
	_handler.name = "AnimationHandler"
	_handler.set_script(handler_script)
	_player.add_child(_handler)
	_handler.call("bind_player", _player)

	var clip: String = String(_handler.get("_clip"))
	print("[HeroProbe] handler clip='%s'" % clip)
	if clip.is_empty():
		_fail("handler could not start any clip")
		return

	# Ask for a jog cycle so a real run clip is sampled.
	_handler.call("set_run_blend", 0.6)
	_handler.call("tick", 0.016, false, false, false)
	print("[HeroProbe] requested jog (blend 0.6)")

	# Deep diagnostics: does the clip data actually address this skeleton?
	for clip_name in ["jog", "jump"]:
		if not _ap.has_animation(clip_name):
			continue
		var anim := _ap.get_animation(clip_name)
		print("[HeroProbe] clip '%s': length=%.3f loop=%d tracks=%d" % [
			clip_name, anim.length, anim.loop_mode, anim.get_track_count()])
		for t in range(mini(4, anim.get_track_count())):
			var path := anim.track_get_path(t)
			var node := _hero.get_node_or_null(NodePath(path.get_concatenated_names()))
			var bone := -1
			if node is Skeleton3D:
				bone = (node as Skeleton3D).find_bone(path.get_concatenated_subnames())
			print("[HeroProbe]   track%d type=%d path='%s' node=%s bone=%d" % [
				t, anim.track_get_type(t), String(path),
				"<missing>" if node == null else String(node.name), bone])


func _process(_delta: float) -> bool:
	_frame += 1
	if _skeleton == null:
		return true
	if _frame == 10:
		_before = _pose_snapshot()
		print("[HeroProbe] frame 10 pose captured (clip='%s' playing=%s t=%.3f bone1=%s)" % [
			String(_ap.current_animation), _ap.is_playing(),
			_ap.get_current_animation_position(), _skeleton.get_bone_pose_rotation(1)])
	elif _frame == 45:
		var moved := _count_moved(_before, _pose_snapshot())
		var bones := _skeleton.get_bone_count()
		print("[HeroProbe] frame 45 pose compare: %d/%d bones moved (clip='%s' t=%.3f bone1=%s)" % [
			moved, bones, String(_ap.current_animation),
			_ap.get_current_animation_position(), _skeleton.get_bone_pose_rotation(1)])
		if moved < 3:
			_fail("skeleton is frozen: %d/%d bones moved (T-pose)" % [moved, bones])
			return true
		print("[HeroProbe] OK: the hero animates (%d/%d bones moved)." % [moved, bones])
		quit(0)
		return true
	elif _frame > 90:
		_fail("probe timed out")
		return true
	return false


## A/B control: does the *raw* imported FBX animate at all? If the source
## scene already stands still, the problem is upstream of our retargeting.
func _test_raw_import() -> void:
	var path := "res://assets/characters/الشخصية/Run Forward.fbx"
	if not ResourceLoader.exists(path):
		print("[HeroProbe] raw FBX not available (exported build?) — skipping A/B test")
		return
	var pck := load(path) as PackedScene
	if pck == null:
		print("[HeroProbe] raw FBX could not be loaded")
		return
	var holder := Node3D.new()
	holder.name = "RawHolder"
	root.add_child(holder)
	holder.add_child(pck.instantiate())
	var ap: AnimationPlayer = null
	var skel: Skeleton3D = null
	for node in holder.find_children("*", "AnimationPlayer", true, false):
		ap = node as AnimationPlayer
		break
	skel = _find_skeleton(holder)
	if ap == null or skel == null:
		print("[HeroProbe] raw FBX has no AnimationPlayer/Skeleton3D")
		holder.queue_free()
		return
	var names := ap.get_animation_list()
	print("[HeroProbe] RAW import: clips=%s bones=%d root_node='%s'" % [
		names, skel.get_bone_count(), String(ap.root_node)])
	var clip := StringName("")
	for candidate in names:
		if String(candidate).to_lower().contains("mixamo"):
			clip = candidate
	if clip.is_empty() and names.size() > 0:
		clip = names[0]
	if not clip.is_empty():
		var anim := ap.get_animation(clip)
		var before := _pose_snapshot_of(skel)
		ap.play(clip)
		ap.seek(minf(anim.length * 0.5, 0.3), true)
		var moved := _count_moved(before, _pose_snapshot_of(skel))
		print("[HeroProbe] RAW import: clip='%s' len=%.3f tracks=%d playing=%s moved=%d/%d bones" % [
			String(clip), anim.length, anim.get_track_count(), ap.is_playing(),
			moved, skel.get_bone_count()])
	holder.queue_free()


func _find_skeleton(node: Node) -> Skeleton3D:
	for child in node.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


func _pose_snapshot() -> Array:
	return _pose_snapshot_of(_skeleton)


func _pose_snapshot_of(skel: Skeleton3D) -> Array:
	var out: Array = []
	if skel == null:
		return out
	for i in range(skel.get_bone_count()):
		out.append(skel.get_bone_pose_rotation(i))
	return out


func _count_moved(before: Array, after: Array) -> int:
	var moved := 0
	for i in range(mini(before.size(), after.size())):
		var a: Quaternion = before[i]
		var b: Quaternion = after[i]
		if absf(a.dot(b)) < 0.9999:
			moved += 1
	return moved


func _names(nodes: Array) -> String:
	var parts := PackedStringArray()
	for n in nodes:
		parts.append(String(n.name))
	return ", ".join(parts)


func _fail(message: String) -> void:
	printerr("[HeroProbe] FAILED: %s" % message)
	quit(1)

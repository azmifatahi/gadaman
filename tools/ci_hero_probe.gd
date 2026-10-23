#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_hero_probe.gd — headless proof that the generated hero actually ANIMATES.
## -----------------------------------------------------------------------------
##  tools/ci_verify_hero.gd checks the data (mesh, bones, resolvable tracks).
##  This probe goes one step further: it instantiates hero.tscn inside a real
##  SceneTree, lets the AnimationTree/AnimationPlayer run for a few dozen frames
##  and compares the skeleton pose before/after. If the pose does not change,
##  the "character" would be a frozen T-pose and this exits non-zero.
##
##  Usage:  godot --headless --script tools/ci_hero_probe.gd [-- --strict]
## =============================================================================
extends SceneTree

const HERO_PATH := "res://assets/models/hero/hero.tscn"

var _hero: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _player: AnimationPlayer
var _playback: AnimationNodeStateMachinePlayback
var _blend_path := ""
var _frame := 0
var _before: Array = []
var _strict := false


func _initialize() -> void:
	_strict = "--strict" in OS.get_cmdline_args() or "--strict" in OS.get_cmdline_user_args()
	if not ResourceLoader.exists(HERO_PATH):
		print("[HeroProbe] FAILED: %s not found" % HERO_PATH)
		quit(1)
		return
	var pck := load(HERO_PATH) as PackedScene
	if pck == null:
		print("[HeroProbe] FAILED: cannot load hero scene")
		quit(1)
		return
	_hero = pck.instantiate() as Node3D
	if _hero == null:
		print("[HeroProbe] FAILED: hero scene is not a Node3D")
		quit(1)
		return
	root.add_child(_hero)
	for node in _hero.find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	_player = _hero.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_tree = _hero.get_node_or_null("AnimationTree") as AnimationTree
	_dump_structure()
	if _skeleton == null or _tree == null or _player == null:
		print("[HeroProbe] FAILED: missing skeleton / AnimationTree / AnimationPlayer")
		quit(1)


func _dump_structure() -> void:
	print("[HeroProbe] hero children: %s" % _names(_hero.get_children()))
	print("[HeroProbe] skeleton=%s bones=%d" % [
		_skeleton.name if _skeleton != null else "<none>",
		_skeleton.get_bone_count() if _skeleton != null else 0])
	if _player == null:
		print("[HeroProbe] AnimationPlayer: MISSING")
		return
	print("[HeroProbe] AnimationPlayer root_node='%s' clips=%s" % [
		String(_player.root_node), _player.get_animation_list()])
	if _tree == null:
		print("[HeroProbe] AnimationTree: MISSING")
		return
	print("[HeroProbe] AnimationTree active=%s anim_player='%s' tree_root=%s" % [
		_tree.active, String(_tree.anim_player),
		_tree.tree_root.get_class() if _tree.tree_root != null else "<null>"])
	if _tree.tree_root is AnimationNodeStateMachine:
		var sm := _tree.tree_root as AnimationNodeStateMachine
		print("[HeroProbe] state machine start='%s' has_locomotion=%s transitions=%d" % [
			sm.start_node, sm.has_node("locomotion"), sm.get_transition_count()])
		for i in range(sm.get_transition_count()):
			print("[HeroProbe]   transition %s -> %s" % [
				sm.get_transition_from(i), sm.get_transition_to(i)])
		if sm.has_node("locomotion"):
			var loco := sm.get_node("locomotion")
			print("[HeroProbe] locomotion node=%s has_blendspace=%s" % [
				loco.get_class(),
				(loco is AnimationNodeBlendTree) and (loco as AnimationNodeBlendTree).has_node("locomotion")])
			if loco is AnimationNodeBlendTree and (loco as AnimationNodeBlendTree).has_node("locomotion"):
				_blend_path = "parameters/locomotion/locomotion/blend_position"
		_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		print("[HeroProbe] playback=%s current='%s'" % [
			_playback != null, _playback.get_current_node() if _playback != null else "-"])
	# Force the run cycle so we test a real clip, not the synthesised idle pose.
	_tree.active = true
	if not _blend_path.is_empty():
		_tree.set(_blend_path, 0.55)
		print("[HeroProbe] blend_position set to 0.55 (jog)")


func _process(_delta: float) -> bool:
	_frame += 1
	if _skeleton != null and _tree != null and _player != null:
		if _frame == 10:
			_before = _pose_snapshot()
			print("[HeroProbe] frame 10 pose captured (current_node='%s' clip='%s')" % [
				_playback.get_current_node() if _playback != null else "-",
				String(_player.current_animation)])
		elif _frame == 45:
			var moved := _count_moved(_before, _pose_snapshot())
			print("[HeroProbe] frame 45 pose compare: %d/%d bones moved (current_node='%s' clip='%s')" % [
				moved, _skeleton.get_bone_count(),
				_playback.get_current_node() if _playback != null else "-",
				String(_player.current_animation)])
			if moved < 3:
				printerr("[HeroProbe] FAILED: skeleton is frozen (T-pose) — AnimationTree is not driving it.")
				quit(1)
				return true
			print("[HeroProbe] OK: the hero animates.")
			quit(0)
			return true
	elif _frame > 60:
		print("[HeroProbe] FAILED: no skeleton/tree to probe")
		quit(1 if _strict else 0)
		return true
	return false


func _pose_snapshot() -> Array:
	var out: Array = []
	for i in range(_skeleton.get_bone_count()):
		out.append(_skeleton.get_bone_pose_rotation(i))
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
	var parts: PackedStringArray = []
	for n in nodes:
		parts.append(String(n.name))
	return ", ".join(parts)

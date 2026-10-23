## Bridges PlayerController signals to the generated hero's animation.
##
## Two back-ends, picked at runtime:
##   * TREE   — the AnimationTree saved inside hero.tscn (StateMachine >
##              BlendTree > BlendSpace1D "locomotion"). Preferred: it blends
##              idle/jog/sprint smoothly by speed.
##   * PLAYER — the plain AnimationPlayer. Used automatically when the
##              AnimationTree has no usable tree root, so a hero can never end up
##              frozen in its T-pose because of one bad resource.
##
## Parameter paths are discovered once from the actual tree layout; the handler
## never calls AnimationTree.set() with a guessed path (invalid paths print an
## engine error every frame).
class_name PlayerAnimationHandler
extends Node

enum Mode { NONE, TREE, PLAYER }

const HeroAnimationGraph := preload("res://scripts/player/hero_animation_graph.gd")
const LOCOMOTION_STATES := ["idle", "jog", "sprint"]
const ONE_SHOTS := ["jump", "fall", "land", "slide", "stumble"]

var _player_node: Node3D
var _tree: AnimationTree
var _ap: AnimationPlayer
var _state_machine: AnimationNodeStateMachinePlayback
var _blend_path: String = ""
var _mode: int = Mode.NONE
var _current: String = ""
var _blend: float = 0.0


func _ready() -> void:
	# PlayerController owns the player signals and calls fire(); binding here
	# only makes the handler usable stand-alone (e.g. in tools/ci_hero_probe.gd).
	bind_player(get_parent())


func bind_player(p: Node) -> void:
	_player_node = p as Node3D
	_refresh()


## Resolves the back-end and the run-blend parameter path from the real layout.
func _refresh() -> void:
	_state_machine = null
	_blend_path = ""
	_mode = Mode.NONE
	if _player_node == null:
		return
	_tree = _player_node.get_node_or_null("Model/AnimationTree") as AnimationTree
	_ap = _player_node.get_node_or_null("Model/AnimationPlayer") as AnimationPlayer
	# A saved scene can lose `tree_root` (nested resource graphs do not always
	# survive PackedScene.pack()); rebuild it from the clips on hand instead of
	# leaving the runner frozen in its T-pose.
	if _tree != null and not (_tree.tree_root is AnimationNodeStateMachine):
		if HeroAnimationGraph.can_build(_ap):
			_tree.tree_root = HeroAnimationGraph.build(_ap)
			print("[PlayerAnimationHandler] rebuilt AnimationTree root at runtime (%s)" % _tree.tree_root.resource_name)
	if _tree != null and _tree.tree_root is AnimationNodeStateMachine:
		_tree.active = true
		_state_machine = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if _state_machine != null:
			_mode = Mode.TREE
			_discover_blend_path()
	if _mode == Mode.NONE:
		# No usable tree (e.g. tree_root was lost when the scene was saved):
		# drive the AnimationPlayer directly instead of standing still.
		if _tree != null:
			_tree.active = false
		if _ap != null and _ap.has_animation("jog"):
			_mode = Mode.PLAYER
			_ap.play(_locomotion_clip(), 0.0)
			_current = _locomotion_clip()
	if _ap != null and not _ap.animation_finished.is_connected(_on_animation_finished):
		_ap.animation_finished.connect(_on_animation_finished)


func debug_state() -> String:
	return "handler mode=%d blend=%.2f blend_path='%s' current='%s' state='%s'" % [
		_mode, _blend, _blend_path, _current,
		_state_machine.get_current_node() if _state_machine != null else "-"]


func _discover_blend_path() -> void:
	var root := _tree.tree_root
	if not (root is AnimationNodeStateMachine):
		return
	var sm := root as AnimationNodeStateMachine
	if not sm.has_node("locomotion"):
		return
	var loco := sm.get_node("locomotion")
	if loco is AnimationNodeBlendTree and (loco as AnimationNodeBlendTree).has_node("locomotion"):
		_blend_path = HeroAnimationGraph.BLEND_PATH


## 0 = idle, 0.55 = jog, 1 = sprint.
func set_run_blend(value: float) -> void:
	_blend = clampf(value, 0.0, 1.0)
	match _mode:
		Mode.TREE:
			if not _blend_path.is_empty():
				_tree.set(_blend_path, _blend)
		Mode.PLAYER:
			if LOCOMOTION_STATES.has(_current):
				_play_player(_locomotion_clip(), 0.25)


func _locomotion_clip() -> String:
	if _blend < 0.12:
		return "idle"
	if _blend > 0.85:
		return "sprint"
	return "jog"


func _travel(state: String) -> void:
	match _mode:
		Mode.TREE:
			if _state_machine != null and _state_machine.get_current_node() != state:
				_state_machine.travel(state)
		Mode.PLAYER:
			if state == "locomotion":
				_play_player(_locomotion_clip(), 0.15)
			else:
				_play_player(state, 0.10, true)


func _play_player(clip: String, fade: float, restart: bool = false) -> void:
	if _ap == null or not _ap.has_animation(clip):
		return
	if not restart and _current == clip and _ap.is_playing():
		return
	_ap.play(clip, fade)
	_current = clip


func fire(action: String) -> void:
	match action:
		"jump", "fall", "land", "slide", "stumble":
			_travel(action)
		"recover", "idle", "run", "locomotion":
			_travel("locomotion")
		_:
			# Unknown one-shots (crash / smash) have no dedicated clip.
			pass


func tick(_delta: float, sliding: bool, airborne: bool, stumbling: bool) -> void:
	if _mode != Mode.PLAYER:
		return
	# One-shots win; otherwise keep the right locomotion clip for the speed.
	if airborne or sliding or stumbling:
		return
	if not LOCOMOTION_STATES.has(_current):
		return
	_play_player(_locomotion_clip(), 0.25)


func _on_animation_finished(anim_name: StringName) -> void:
	if _mode != Mode.PLAYER:
		return
	if ONE_SHOTS.has(String(anim_name)):
		_play_player(_locomotion_clip(), 0.2)

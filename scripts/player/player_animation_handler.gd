## Bridges PlayerController signals to the generated hero's AnimationTree state
## machine.
##
## The handler discovers the tree layout once, so it works with the current
## HeroBuilder output (StateMachine > BlendTree > BlendSpace1D "locomotion")
## and simply does nothing if the layout changes. It never calls
## AnimationTree.set() with a guessed path: an invalid parameter path prints an
## engine error every frame, which used to flood the log on device.
class_name PlayerAnimationHandler
extends Node

var _tree: AnimationTree
var _player_node: Node3D
var _state_machine: AnimationNodeStateMachinePlayback
var _blend_path: String = ""
var _last_fired: String = ""


func _ready() -> void:
	_player_node = get_parent() as Node3D
	if _player_node != null:
		_tree = _player_node.get_node_or_null("Model/AnimationTree") as AnimationTree
	_refresh()
	# Connect controller signals via callables so duplicates are harmless on
	# scene reload.
	if _player_node != null:
		if _player_node.has_signal("jumped") and not _player_node.jumped.is_connected(_on_jumped):
			_player_node.jumped.connect(_on_jumped)
		if _player_node.has_signal("landed") and not _player_node.landed.is_connected(_on_landed):
			_player_node.landed.connect(_on_landed)
		if _player_node.has_signal("slide_started") and not _player_node.slide_started.is_connected(_on_slide):
			_player_node.slide_started.connect(_on_slide)
		if _player_node.has_signal("stumbled") and not _player_node.stumbled.is_connected(_on_stumble):
			_player_node.stumbled.connect(_on_stumble)
		if _player_node.has_signal("recovered") and not _player_node.recovered.is_connected(_on_recover):
			_player_node.recovered.connect(_on_recover)
		if _player_node.has_signal("crashed") and not _player_node.crashed.is_connected(_on_crash):
			_player_node.crashed.connect(_on_crash)


func bind_player(p: Node) -> void:
	_player_node = p as Node3D
	if _player_node != null:
		_tree = _player_node.get_node_or_null("Model/AnimationTree") as AnimationTree
	_refresh()


## Caches the playback object and the run-blend parameter path.
func _refresh() -> void:
	_state_machine = null
	_blend_path = ""
	if _tree == null:
		return
	_tree.active = true
	var root := _tree.tree_root
	if root is AnimationNodeStateMachine:
		_state_machine = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		var sm := root as AnimationNodeStateMachine
		if sm.has_node("locomotion"):
			var loco := sm.get_node("locomotion")
			if loco is AnimationNodeBlendTree:
				var blend_tree := loco as AnimationNodeBlendTree
				if blend_tree.has_node("locomotion"):
					_blend_path = "parameters/locomotion/locomotion/blend_position"


## 0 = idle, 0.55 = jog, 1 = sprint (BlendSpace1D inside the "locomotion" state).
func set_run_blend(value: float) -> void:
	if _tree != null and not _blend_path.is_empty():
		_tree.set(_blend_path, clampf(value, 0.0, 1.0))


func _travel(state: String) -> void:
	if _state_machine == null:
		return
	if _state_machine.get_current_node() == state:
		return
	_state_machine.travel(state)
	_last_fired = state


func fire(action: String) -> void:
	match action:
		"jump":
			_travel("jump")
		"fall":
			_travel("fall")
		"land":
			_travel("land")
		"slide":
			_travel("slide")
		"stumble":
			_travel("stumble")
		"recover", "idle", "run":
			_travel("locomotion")
		_:
			# Ignore unknown one-shots (crash / smash have no dedicated clip).
			pass


func tick(_delta: float, sliding: bool, airborne: bool, stumbling: bool) -> void:
	if _state_machine == null:
		return
	var current := _state_machine.get_current_node()
	# fall -> land and land -> locomotion advance automatically (SWITCH_MODE_AT_END
	# transitions created by HeroBuilder); only the entry states need a nudge.
	if airborne and current == "locomotion":
		_travel("fall")
	elif not airborne and current == "fall":
		_travel("land")
	elif sliding and current == "locomotion":
		_travel("slide")
	elif stumbling and current == "locomotion":
		_travel("stumble")


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------
func _on_jumped() -> void:
	_travel("jump")


func _on_landed() -> void:
	if _state_machine != null and _state_machine.get_current_node() == "fall":
		_travel("land")


func _on_slide() -> void:
	_travel("slide")


func _on_stumble() -> void:
	_travel("stumble")


func _on_recover() -> void:
	_travel("locomotion")


func _on_crash() -> void:
	# No dedicated crash clip in the character folder: stay in the stumble pose.
	_travel("stumble")

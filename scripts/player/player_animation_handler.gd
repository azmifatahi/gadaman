## Bridges PlayerController signals to the imported hero's AnimationTree state
## machine. Keeps the controller free of node-path assumptions so it can be
## tested headless and keeps running if the hero scene isn't present yet.
class_name PlayerAnimationHandler
extends Node

var _player: Node3D
var _tree: AnimationTree
var _player_node: Node3D
var _state_machine: AnimationNodeStateMachinePlayback
var _last_fired: String = ""


func _ready() -> void:
	_player_node = get_parent() as Node3D
	_tree = _player_node.get_node_or_null("Model/AnimationTree") as AnimationTree
	if _tree:
		_tree.active = true
		# The AnimationNodeStateMachinePlayback is reachable at
		# "parameters/playback" when the tree root IS the state machine.
		_state_machine = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	# Connect controller signals via callables so duplicates are harmless on
	# scene reload.
	if _player_node.has_signal("jumped"):
		_player_node.jumped.connect(_on_jumped)
	if _player_node.has_signal("landed"):
		_player_node.landed.connect(_on_landed)
	if _player_node.has_signal("slide_started"):
		_player_node.slide_started.connect(_on_slide)
	if _player_node.has_signal("stumbled"):
		_player_node.stumbled.connect(_on_stumble)
	if _player_node.has_signal("recovered"):
		_player_node.recovered.connect(_on_recover)
	if _player_node.has_signal("crashed"):
		_player_node.crashed.connect(_on_crash)


func bind_player(p: Node) -> void:
	_player = p
	_tree = p.get_node_or_null("Model/AnimationTree") as AnimationTree
	if _tree:
		_tree.active = true
		_state_machine = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _travel(state: String) -> void:
	if _state_machine:
		_state_machine.travel(state)
		_last_fired = state


func fire(name: String) -> void:
	# Public API used by PlayerController._fire_anim.
	match name:
		"jump":    _travel("jump")
		"fall":    _travel("fall")
		"land":    _travel("land")
		"slide":   _travel("slide")
		"stumble": _travel("stumble")
		"recover", "idle", "run":
			_travel("locomotion")
		_:
			# Ignore unknown one-shots (e.g. "crash" / "smash" when we don't
			# have dedicated clips; the controller emits those too).
			pass


func tick(_delta: float, sliding: bool, airborne: bool, stumbling: bool) -> void:
	if _state_machine == null:
		return
	var current := _state_machine.get_current_node()
	# Automatic fall -> land chain: the state machine transitions are set to
	# advance at end so they do this on their own; nothing to do here.
	# If airborne and not already in a jump/fall/land chain, blend into fall.
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
	# The state machine advances automatically, but in case fall finished
	# without a land cue, ask for it.
	if _state_machine and _state_machine.get_current_node() == "fall":
		_travel("land")


func _on_slide() -> void:
	_travel("slide")


func _on_stumble() -> void:
	_travel("stumble")


func _on_recover() -> void:
	_travel("locomotion")


func _on_crash() -> void:
	# No dedicated crash clip in this pack; remain in stumble visually.
	_travel("stumble")

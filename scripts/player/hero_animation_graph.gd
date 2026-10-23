## Builds the animation graph for the imported Mixamo hero.
##
## The graph is created **in code** on purpose. `AnimationTree.tree_root` is a
## nested resource graph, and a graph created by a build script and then
## round-tripped through `PackedScene.pack()` can come back empty (that is
## exactly how v1.2.2 shipped a T-posed runner: the AnimationTree node existed
## but its `tree_root` was null, so nobody drove the skeleton).
##
## Both the offline builder (scripts/tools/hero_builder.gd) and the runtime
## handler (scripts/player/player_animation_handler.gd) call this, so the graph
## is always reconstructible from the clips that are actually present.
##
## Usage:
##     const HeroAnimationGraph := preload("res://scripts/player/hero_animation_graph.gd")
##     tree.tree_root = HeroAnimationGraph.build(animation_player)
extends RefCounted

## Locomotion states, blended by speed on a 1D blend space.
const LOCOMOTION := {
	"idle": 0.0,
	"jog": 0.55,
	"sprint": 1.0,
}

## One-shot / pose states and the xfade used when travelling into them.
const ONE_SHOTS := {
	"jump": 0.08,
	"fall": 0.10,
	"land": 0.12,
	"slide": 0.06,
	"stumble": 0.10,
}

const STATE_LOCOMOTION := "locomotion"
const NODE_LOCOMOTION := "locomotion"
## Parameter path used to set the blend value (relative to the AnimationTree).
const BLEND_PATH := "parameters/locomotion/locomotion/blend_position"


## Returns every clip the graph would like to have.
static func required_clips() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(PackedStringArray(LOCOMOTION.keys()))
	out.append_array(PackedStringArray(ONE_SHOTS.keys()))
	return out


## True when at least the jog cycle can be played, i.e. the graph is worth it.
static func can_build(animation_player: AnimationPlayer) -> bool:
	if animation_player == null:
		return false
	for clip in LOCOMOTION.keys():
		if animation_player.has_animation(clip):
			return true
	return false


## Builds the state machine for `animation_player`.
## Missing clips are skipped instead of producing invalid nodes, so a partial
## import still animates rather than freezing.
static func build(animation_player: AnimationPlayer) -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	sm.resource_name = "HeroStates"

	# -- locomotion: AnimationNodeBlendTree > BlendSpace1D ------------------
	var loco := AnimationNodeBlendTree.new()
	loco.resource_name = "LocomotionTree"
	loco.add_node("output", AnimationNodeOutput.new(), Vector2(500, 80))
	var space := AnimationNodeBlendSpace1D.new()
	space.resource_name = "RunBlend"
	space.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	space.snap = 0.0
	var points := 0
	for clip in LOCOMOTION.keys():
		if animation_player != null and animation_player.has_animation(clip):
			space.add_blend_point(_clip(clip), float(LOCOMOTION[clip]))
			points += 1
	# A BlendSpace1D with fewer than two points still plays its single clip.
	if points == 0:
		return sm
	loco.add_node(NODE_LOCOMOTION, space, Vector2(60, 80))
	loco.connect_node("output", 0, NODE_LOCOMOTION)
	sm.add_node(STATE_LOCOMOTION, loco, Vector2(0, 0))

	# -- one-shot states ----------------------------------------------------
	var x := 280.0
	for clip in ONE_SHOTS.keys():
		if animation_player == null or not animation_player.has_animation(clip):
			continue
		sm.add_node(clip, _clip(clip), Vector2(x, 150.0 if int(x) % 2 == 0 else -150.0))
		x += 240.0
		_add_transition(sm, STATE_LOCOMOTION, clip, float(ONE_SHOTS[clip]), false)
		_add_transition(sm, clip, STATE_LOCOMOTION, 0.12, true)

	# The airborne pair only makes sense when both halves exist.
	if sm.has_node("jump") and sm.has_node("fall"):
		_add_transition(sm, "jump", "fall", 0.10, true)

	sm.start_node = STATE_LOCOMOTION
	return sm


static func _clip(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


static func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String,
		xfade: float, auto_advance: bool) -> void:
	if not sm.has_node(from) or not sm.has_node(to):
		return
	var t := AnimationNodeStateMachineTransition.new()
	if auto_advance:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	# Godot 4 property name: `xfade_time` (there is no `fade_time`).
	t.xfade_time = xfade
	sm.add_transition(from, to, t)

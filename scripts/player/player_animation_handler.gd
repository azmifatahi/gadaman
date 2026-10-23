## Drives the imported Mixamo hero.
##
## Design rule: **the AnimationPlayer is the only animation back-end.** No
## `AnimationTree` is created at runtime or saved into the hero scene. That is
## deliberate — v1.2.2 crashed into a T-pose because the saved `AnimationTree` lost
## its `tree_root` (nested `AnimationNode*` graphs do not always survive
## `PackedScene.pack()`), and an empty tree silently outranks a perfectly good
## AnimationPlayer. The clips themselves were verified to animate (playing
## `mixamo_com` from `Run Forward.fbx` moves 51 of 65 bones), so the safest thing
## to ship is: play those clips, nothing in between.
##
## Locomotion is cross-faded between idle / jog / sprint on speed; one-shots
## (jump, fall, land, slide, stumble) play once and hand control back.
class_name PlayerAnimationHandler
extends Node

const HeroClips := preload("res://scripts/player/hero_clips.gd")

## Where the hero scene is mounted inside the player (PlayerController names it
## "Model").
const MODEL_PATH := ^"Model"

var _player_node: Node3D
var _ap: AnimationPlayer
var _blend: float = 0.0
var _clip: String = ""
var _locked: bool = false          # a one-shot owns the skeleton right now


func _ready() -> void:
	# PlayerController owns gameplay signals and calls fire(); binding here also
	# makes the handler usable stand-alone (tools/ci_hero_probe.gd does that).
	bind_player(get_parent())


func bind_player(p: Node) -> void:
	_player_node = p as Node3D
	_refresh()


func _refresh() -> void:
	_ap = null
	if _player_node == null:
		return
	var model := _player_node.get_node_or_null(MODEL_PATH)
	if model == null:
		return
	_ap = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _ap == null:
		# Tolerate a renamed/relocated player: take the first one in the hero.
		for node in model.find_children("*", "AnimationPlayer", true, false):
			_ap = node as AnimationPlayer
			break
	if _ap == null:
		push_warning("[PlayerAnimationHandler] the hero has no AnimationPlayer")
		return
	if not _ap.animation_finished.is_connected(_on_animation_finished):
		_ap.animation_finished.connect(_on_animation_finished)
	_clip = ""
	_locked = false
	_play(HeroClips.locomotion_clip(_blend), true)


## 0 = idle, 0.55 = jog, 1 = sprint.
func set_run_blend(value: float) -> void:
	_blend = clampf(value, 0.0, 1.0)
	if _ap == null or _locked:
		return
	var wanted := HeroClips.locomotion_clip(_blend)
	if wanted != _clip:
		_play(wanted)


## Called every physics frame by PlayerController. Keeps the locomotion clip in
## sync when playing it was skipped (e.g. the AnimationPlayer was re-bound).
func tick(_delta: float, sliding: bool, airborne: bool, stumbling: bool) -> void:
	if _ap == null or _locked:
		return
	if sliding or airborne or stumbling:
		return
	var wanted := HeroClips.locomotion_clip(_blend)
	if _clip != wanted or not _ap.is_playing():
		_play(wanted)


## Plays a one-shot action ("jump", "fall", "land", "slide", "stumble",
## "recover").
func fire(action: String) -> void:
	if _ap == null:
		return
	match action:
		"recover", "idle", "run", "locomotion":
			_locked = false
			_play(HeroClips.locomotion_clip(_blend))
		"crash":
			# No crash clip in the character folder: hold the stumble pose.
			_play_once("stumble")
		_:
			if HeroClips.ONE_SHOTS.has(action):
				_play_once(action)


func _play_once(clip: String) -> void:
	if not _has(clip):
		return
	_locked = true
	_play(clip)
	# A looping clip would never emit animation_finished: never lock on those.
	if _ap.get_animation(clip).loop_mode != Animation.LOOP_NONE:
		_locked = false


func _play(clip: String, restart: bool = false) -> void:
	if _ap == null or not _has(clip):
		return
	if not restart and _clip == clip and _ap.is_playing():
		return
	_ap.play(clip, HeroClips.fade_time(clip))
	_clip = clip


func _has(clip: String) -> bool:
	return _ap != null and not clip.is_empty() and _ap.has_animation(clip)


func _on_animation_finished(anim_name: StringName) -> void:
	if HeroClips.ONE_SHOTS.has(String(anim_name)):
		_locked = false
		_play(HeroClips.locomotion_clip(_blend), true)


## Compact state line published by the CI screenshot session.
func debug_state() -> String:
	return "handler clip='%s' blend=%.2f locked=%s playing=%s" % [
		_clip, _blend, _locked, _ap != null and _ap.is_playing()]

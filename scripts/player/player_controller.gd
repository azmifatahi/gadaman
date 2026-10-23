## Third-person endless runner controller.
##
## Movement model:
##   * Lanes are 3 virtual rails. A lane change is an exponential slide toward
##     the target x, which feels responsive but never teleports the body past an
##     obstacle hitbox.
##   * Jump is a classic ballistic arc tuned so a 1.0 m barrier clears at any
##     run speed (apex ~2.05 m, air time ~0.66 s).
##   * Slide is a timed duck (0.62 s) that lowers the head below the 1.25 m bar
##     clearance and can be cancelled into a jump.
##
## Input is deliberately engine-agnostic: swipes, mouse drags, keys and the
## optional accelerometer all funnel into the same three verbs.
##
## This controller supports two visual back-ends:
##   1. The imported Mixamo hero (res://assets/models/hero/hero.tscn) — uses an
##      AnimationTree with run_blend/lane_blend and one-shots driven by
##      PlayerAnimationHandler.
##   2. The legacy procedural RunnerModel — used as a graceful fallback if the
##      hero scene hasn't been imported yet (e.g. in CI headless runs).
class_name PlayerController
extends Node3D

signal jumped
signal landed
signal slide_started
signal crashed
signal stumbled
signal recovered
signal obstacle_smashed
signal action_intensity_changed(value: float)

const LANE_WIDTH := 2.4
const LANE_COUNT := 3
const LANE_CHANGE_TIME := 0.20
const LATERAL_ACCELERATION := 115.0
const LATERAL_DAMPING := 16.0
const STUMBLE_TIME := 0.85
const RECOVERY_INVULNERABILITY := 1.15
const SMASH_MIN_SPEED := 18.0
const JUMP_VELOCITY := 12.6
const GRAVITY := 38.0
const SLIDE_TIME := 0.62
const SWIPE_THRESHOLD := 46.0     # logical pixels
const TILT_THRESHOLD := 0.22
const TILT_COOLDOWN := 0.32

const HERO_SCENE_PATH := "res://assets/models/hero/hero.tscn"

var lane: int = 1
var target_x: float = 0.0
var velocity_y: float = 0.0
var is_sliding: bool = false
var is_airborne: bool = false
var alive: bool = true
var controlling: bool = false
var is_stumbling: bool = false
var lateral_velocity: float = 0.0
var run_blend: float = 0.0
var lane_blend: float = 0.0
var track: TrackManager

var _slide_timer := 0.0
var _jump_buffer := 0.0
var _touch_active := false
var _touch_start := Vector2.ZERO
var _touch_consumed := false
var _tilt_baseline := 0.0
var _tilt_cooldown := 0.0
var _stumble_timer := 0.0
var _invulnerability_timer := 0.0
var _last_intensity := -1.0

# Visual back-end references. Either _procedural (RunnerModel) is populated or
# _hero + _anim_player + _anim_tree + _anim_handler are; both paths work.
var _model: RunnerModel
var _hero: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _anim_handler: Node
var _blob: MeshInstance3D
var _using_imported_hero: bool = false


func _ready() -> void:
	position = Vector3(0, 0, 0)
	_attach_model()
	_build_blob_shadow()
	_attach_animation_handler()
	_connect_signals_to_animator()
	reset()


func _attach_model() -> void:
	# Editor convenience only: when the generated hero scene has never been
	# produced, build it once from the FBX folder. This is NOT done at runtime:
	# an exported game does not ship the raw .fbx files nor their import cache,
	# so a runtime rebuild cannot work (that is how v1.2.x ended up drawing an
	# empty armature).
	if Engine.is_editor_hint() and not ResourceLoader.exists(HERO_SCENE_PATH):
		HeroBuilder.build_if_missing()

	# Prefer the generated hero scene — but only if it is actually drawable.
	if ResourceLoader.exists(HERO_SCENE_PATH):
		var hero_scene: PackedScene = load(HERO_SCENE_PATH)
		if hero_scene:
			var inst: Node = hero_scene.instantiate()
			var hero_root := inst as Node3D
			if hero_root != null and _hero_is_drawable(hero_root):
				hero_root.name = "Model"
				add_child(hero_root)
				_hero = hero_root
				_anim_player = _hero.get_node_or_null("AnimationPlayer") as AnimationPlayer
				_anim_tree = _hero.get_node_or_null("AnimationTree") as AnimationTree
				_using_imported_hero = true
				if _anim_tree:
					_anim_tree.active = true
				print("[PlayerController] hero.tscn attached (meshes=%d, bones=%d, %.2f m tall)" % [
					_count_visible_meshes(_hero), _count_bones(_hero), _hero_height(_hero)])
				return
			push_warning("[PlayerController] hero.tscn is empty or not drawable - using the procedural runner instead.")
			if inst != null:
				inst.queue_free()
	push_warning("[PlayerController] No usable hero scene - falling back to the procedural runner.")
	# Fallback: procedural model (guaranteed to be visible on every GPU).
	_model = RunnerModel.new()
	_model.name = "Model"
	add_child(_model)
	_using_imported_hero = false


## A scene is only worth drawing if it contains at least one visible mesh with
## real surfaces, a skeleton and a plausible height. This check is the last line
## of defence: an empty/broken hero can never make the runner invisible again.
func _hero_is_drawable(root: Node3D) -> bool:
	return _count_visible_meshes(root) > 0 and _count_bones(root) > 0 and _hero_height(root) >= 0.4


func _count_visible_meshes(root: Node) -> int:
	var count := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.visible and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			count += 1
	return count


func _count_bones(root: Node) -> int:
	for n in root.find_children("*", "Skeleton3D", true, false):
		return (n as Skeleton3D).get_bone_count()
	return 0


## Height of the visible meshes in `root` space. Walks the parent chain manually
## because this runs before the node is added to the scene tree.
func _hero_height(root: Node3D) -> float:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null or mi.mesh.get_surface_count() <= 0:
			continue
		var chain: Array[Transform3D] = []
		var node: Node = mi
		var guard := 0
		while node != null and node != root and guard < 256:
			if node is Node3D:
				chain.push_front((node as Node3D).transform)
			node = node.get_parent()
			guard += 1
		var xf := Transform3D()
		for t in chain:
			xf = xf * t
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y if not first else 0.0


func _attach_animation_handler() -> void:
	if not _using_imported_hero:
		return
	if not ResourceLoader.exists("res://scripts/player/player_animation_handler.gd"):
		return
	if has_node("AnimationHandler"):
		_anim_handler = get_node("AnimationHandler")
	else:
		var script := load("res://scripts/player/player_animation_handler.gd")
		if script:
			_anim_handler = Node.new()
			_anim_handler.name = "AnimationHandler"
			_anim_handler.set_script(script)
			add_child(_anim_handler)
	if _anim_handler and _anim_handler.has_method("bind_player"):
		_anim_handler.bind_player(self)


func _connect_signals_to_animator() -> void:
	# Use callables so any signal wiring stays local to the controller and
	# both the procedural RunnerModel and the imported AnimationHandler work.
	jumped.connect(func(): _fire_anim("jump"))
	landed.connect(func(): _fire_anim("land"))
	slide_started.connect(func(): _fire_anim("slide"))
	stumbled.connect(func(): _fire_anim("stumble"))
	crashed.connect(func(): _fire_anim("crash"))
	recovered.connect(func(): _fire_anim("recover"))


func _build_blob_shadow() -> void:
	_blob = MeshInstance3D.new()
	_blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.1)
	_blob.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/blob_shadow.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blob.material_override = mat
	_blob.rotation = Vector3(-PI * 0.5, 0, 0)
	_blob.position = Vector3(0, 0.03, 0)
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func reset() -> void:
	lane = 1
	target_x = 0.0
	position = Vector3(0, 0, 0)
	velocity_y = 0.0
	lateral_velocity = 0.0
	is_sliding = false
	is_airborne = false
	is_stumbling = false
	alive = true
	controlling = true
	_slide_timer = 0.0
	_jump_buffer = 0.0
	_tilt_cooldown = 0.0
	_stumble_timer = 0.0
	_invulnerability_timer = 0.0
	rotation = Vector3.ZERO
	if _model:
		_model.set_state(RunnerModel.State.RUN)
		_model.reset_pose()
	if _using_imported_hero and _anim_player:
		if _anim_player.has_animation("idle"):
			_anim_player.play("idle")
		elif _anim_player.has_animation("jog"):
			_anim_player.play("jog")
	if _anim_tree:
		_reset_tree_oneshots()
	if _blob:
		_blob.visible = true
	if Settings.tilt_enabled:
		_calibrate_tilt()


func start_running() -> void:
	reset()


func die() -> void:
	alive = false
	controlling = false
	is_sliding = false
	if _model:
		_model.play_crash()
	crashed.emit()


func stop() -> void:
	controlling = false


func is_controllable() -> bool:
	return controlling and alive and not is_stumbling


func can_take_hit() -> bool:
	return alive and _invulnerability_timer <= 0.0


func can_smash_soft_obstacle() -> bool:
	return is_controllable() and not is_airborne and not is_sliding and track != null and track.speed >= SMASH_MIN_SPEED


## Minor impacts are recoverable, like classic cinematic action runners.
func stumble() -> void:
	if not can_take_hit():
		return
	is_stumbling = true
	is_sliding = false
	_stumble_timer = STUMBLE_TIME
	_invulnerability_timer = STUMBLE_TIME + RECOVERY_INVULNERABILITY
	lateral_velocity *= 0.25
	if _model:
		_model.set_state(RunnerModel.State.STUMBLE)
	stumbled.emit()
	Settings.vibrate(35)


func smash() -> void:
	obstacle_smashed.emit()
	_fire_anim("smash")
	Settings.vibrate(18)


func lane_x(index: int) -> float:
	return (float(clampi(index, 0, LANE_COUNT - 1)) - 1.0) * LANE_WIDTH


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not alive:
		return
	_invulnerability_timer = maxf(0.0, _invulnerability_timer - delta)
	if is_stumbling:
		_stumble_timer -= delta
		if _stumble_timer <= 0.0:
			is_stumbling = false
			if _model:
				_model.set_state(RunnerModel.State.RUN)
			recovered.emit()
	_update_lateral(delta)
	_update_vertical(delta)
	_update_tilt(delta)
	var spd: float = track.speed if track else 11.0
	run_blend = move_toward(run_blend, clampf((spd - 9.0) / 18.0, 0.0, 1.0), delta * 2.8)
	if _model:
		_model.animate(delta, spd, is_sliding, is_airborne)
	# Drive the imported AnimationTree.
	if _anim_tree:
		_drive_anim_tree(delta, spd)
	elif _anim_handler and _anim_handler.has_method("tick"):
		_anim_handler.tick(delta, is_sliding, is_airborne, is_stumbling)
	var intensity := clampf((spd - 11.0) / 16.0, 0.0, 1.0)
	if absf(intensity - _last_intensity) > 0.025:
		_last_intensity = intensity
		action_intensity_changed.emit(intensity)


func _drive_anim_tree(delta: float, _speed: float) -> void:
	if _anim_tree == null:
		return
	# The AnimationTree root is an AnimationNodeStateMachine whose "locomotion"
	# state embeds a BlendTree with a BlendSpace1D also named "locomotion".
	# PlayerAnimationHandler discovers that parameter path once and only sets it
	# when it really exists, so we never spam the console with invalid paths.
	if _anim_handler and _anim_handler.has_method("set_run_blend"):
		_anim_handler.set_run_blend(run_blend)
	if _anim_handler and _anim_handler.has_method("tick"):
		_anim_handler.tick(delta, is_sliding, is_airborne, is_stumbling)


func _reset_tree_oneshots() -> void:
	if _anim_handler and _anim_handler.has_method("fire"):
		_anim_handler.fire("recover")


func _fire_anim(name: String) -> void:
	if _anim_handler and _anim_handler.has_method("fire"):
		_anim_handler.fire(name)
	elif _anim_player and _anim_player.has_animation(name):
		_anim_player.play(name)


func _update_lateral(delta: float) -> void:
	target_x = lane_x(lane)
	var error := target_x - position.x
	lateral_velocity += error * LATERAL_ACCELERATION * delta
	lateral_velocity *= exp(-LATERAL_DAMPING * delta)
	position.x += lateral_velocity * delta
	if absf(error) < 0.008 and absf(lateral_velocity) < 0.04:
		position.x = target_x
		lateral_velocity = 0.0
	lane_blend = lerp(lane_blend, clampf(lateral_velocity / 8.0, -1.0, 1.0), 1.0 - exp(-delta * 12.0))
	if _model:
		_model.lean = lane_blend * 0.34


func _update_vertical(delta: float) -> void:
	if is_airborne:
		velocity_y -= GRAVITY * delta
		position.y += velocity_y * delta
		if position.y <= 0.0:
			position.y = 0.0
			velocity_y = 0.0
			is_airborne = false
			landed.emit()
			Settings.vibrate(12)
	if is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0:
			is_sliding = false
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
		if not is_airborne:
			_do_jump()


func _update_tilt(delta: float) -> void:
	_tilt_cooldown = maxf(0.0, _tilt_cooldown - delta)
	if not Settings.tilt_enabled or not controlling:
		return
	var accel := Input.get_accelerometer()
	if accel == Vector3.ZERO:
		return
	var tilt := accel.x - _tilt_baseline
	if _tilt_cooldown <= 0.0 and absf(tilt) > TILT_THRESHOLD:
		change_lane(1 if tilt > 0.0 else -1)
		_tilt_cooldown = TILT_COOLDOWN


func _calibrate_tilt() -> void:
	var accel := Input.get_accelerometer()
	_tilt_baseline = accel.x if accel != Vector3.ZERO else 0.0


# ---------------------------------------------------------------------------
# Verbs
# ---------------------------------------------------------------------------
func change_lane(direction: int) -> void:
	if not is_controllable() or direction == 0:
		return
	var new_lane := clampi(lane + signi(direction), 0, LANE_COUNT - 1)
	if new_lane == lane:
		return
	lane = new_lane
	Settings.vibrate(8)


func jump() -> void:
	if not is_controllable():
		return
	if is_airborne:
		_jump_buffer = 0.14
		return
	if is_sliding:
		is_sliding = false
		_slide_timer = 0.0
	_do_jump()


func _do_jump() -> void:
	_jump_buffer = 0.0
	is_airborne = true
	velocity_y = JUMP_VELOCITY
	is_sliding = false
	jumped.emit()
	Audio.play_sfx("jump", 0.05, 0.6)


func slide() -> void:
	if not is_controllable():
		return
	if is_airborne:
		velocity_y = minf(velocity_y, -18.0)
		_jump_buffer = 0.0
	_slide_timer = SLIDE_TIME
	if not is_sliding:
		is_sliding = true
		slide_started.emit()
		Audio.play_sfx("slide", 0.05, 0.55)


## Thin wrapper used by the UI's big touch pad: one entry point for gestures.
func handle_swipe(direction: String) -> void:
	match direction:
		"left":
			change_lane(-1)
		"right":
			change_lane(1)
		"up":
			jump()
		"down":
			slide()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not is_controllable():
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_active = true
			_touch_start = touch.position
			_touch_consumed = false
		elif _touch_active:
			_touch_active = false
			if not _touch_consumed:
				_resolve_swipe(touch.position - _touch_start)

	elif event is InputEventScreenDrag:
		if _touch_active and not _touch_consumed:
			var delta := (event as InputEventScreenDrag).position - _touch_start
			if delta.length() >= SWIPE_THRESHOLD:
				_touch_consumed = true
				_resolve_swipe(delta)


func _resolve_swipe(delta: Vector2) -> void:
	if delta.length() < SWIPE_THRESHOLD:
		return
	if absf(delta.x) > absf(delta.y):
		change_lane(1 if delta.x > 0.0 else -1)
	elif delta.y < 0.0:
		jump()
	else:
		slide()


func _process(_delta: float) -> void:
	if not is_controllable():
		return
	if Input.is_action_just_pressed("move_left"):
		change_lane(-1)
	elif Input.is_action_just_pressed("move_right"):
		change_lane(1)
	if Input.is_action_just_pressed("jump"):
		jump()
	elif Input.is_action_just_pressed("slide"):
		slide()


func head_world_y() -> float:
	# Slight difference depending on model.
	return global_position.y + (1.6 if _using_imported_hero else 1.6)

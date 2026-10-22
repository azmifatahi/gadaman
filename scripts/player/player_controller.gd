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
class_name PlayerController
extends Node3D

signal jumped
signal landed
signal slide_started
signal crashed

const LANE_WIDTH := 2.4
const LANE_COUNT := 3
const LANE_CHANGE_TIME := 0.16
const JUMP_VELOCITY := 12.6
const GRAVITY := 38.0
const SLIDE_TIME := 0.62
const SWIPE_THRESHOLD := 46.0     # logical pixels
const TILT_THRESHOLD := 0.22
const TILT_COOLDOWN := 0.32

var lane: int = 1
var target_x: float = 0.0
var velocity_y: float = 0.0
var is_sliding: bool = false
var is_airborne: bool = false
var alive: bool = true
var controlling: bool = false
var track: TrackManager

var _slide_timer := 0.0
var _jump_buffer := 0.0
var _touch_active := false
var _touch_start := Vector2.ZERO
var _touch_consumed := false
var _tilt_baseline := 0.0
var _tilt_cooldown := 0.0
var _model: RunnerModel
var _blob: MeshInstance3D


func _ready() -> void:
	position = Vector3(0, 0, 0)
	_model = RunnerModel.new()
	_model.name = "Model"
	add_child(_model)
	_build_blob_shadow()
	reset()


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
	is_sliding = false
	is_airborne = false
	alive = true
	controlling = true
	_slide_timer = 0.0
	_jump_buffer = 0.0
	_tilt_cooldown = 0.0
	rotation = Vector3.ZERO
	if _model:
		_model.set_state(RunnerModel.State.RUN)
		_model.reset_pose()
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
	return controlling and alive


func lane_x(index: int) -> float:
	return (float(clampi(index, 0, LANE_COUNT - 1)) - 1.0) * LANE_WIDTH


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not alive:
		return
	_update_lateral(delta)
	_update_vertical(delta)
	_update_tilt(delta)
	if _model:
		var spd: float = track.speed if track else 11.0
		_model.animate(delta, spd, is_sliding, is_airborne)


func _update_lateral(delta: float) -> void:
	target_x = lane_x(lane)
	# Exponential smoothing, frame-rate independent. tau = half the lane time.
	var t := 1.0 - exp(-delta / (LANE_CHANGE_TIME * 0.5))
	position.x = lerp(position.x, target_x, t)
	# Body lean sells the lane change (the model, not the collision point).
	if _model:
		_model.lean = clampf((target_x - position.x) * 0.55, -0.35, 0.35)


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

	# Slide timer.
	if is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0:
			is_sliding = false

	# Jump buffer: tapping jump slightly before landing still jumps.
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
		# Slide on landing: drop fast, then duck.
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

	# Note: mouse events are intentionally ignored. The project enables
	# input_devices/pointing/emulate_touch_from_mouse, so desktop mice already
	# arrive as InputEventScreenTouch/Drag and every platform shares one path.


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
	# Keyboard / gamepad / editor testing.
	if Input.is_action_just_pressed("move_left"):
		change_lane(-1)
	elif Input.is_action_just_pressed("move_right"):
		change_lane(1)
	if Input.is_action_just_pressed("jump"):
		jump()
	elif Input.is_action_just_pressed("slide"):
		slide()

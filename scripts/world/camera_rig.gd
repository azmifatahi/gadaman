## Third-person chase camera with speed-aware framing and screen shake.
##
## The camera is not parented to the player on purpose: it lags behind with
## exponential smoothing, which reads as "the runner is pulling away" and avoids
## the jitter you get from a rigid parent/child setup.
class_name CameraRig
extends Camera3D

const BASE_HEIGHT := 4.55
const BASE_DISTANCE := 7.4
const LOOK_HEIGHT := 1.25
const LOOK_AHEAD := -8.0

var target: Node3D
var track: TrackManager

var _shake := 0.0
var _shake_time := 0.0
var _base_fov := 62.0
var _current_x := 0.0


func _ready() -> void:
	fov = _base_fov
	near = 0.15
	far = Perf.draw_distance
	position = Vector3(0, BASE_HEIGHT, BASE_DISTANCE)
	Perf.apply_to_camera(self)


func setup(player: Node3D, track_manager: TrackManager) -> void:
	target = player
	track = track_manager


func shake(amount: float = 0.35, duration: float = 0.35) -> void:
	_shake = maxf(_shake, amount)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	var px := 0.0
	var py := 0.0
	var speed := 0.0
	if target:
		px = target.position.x
		py = clampf(target.position.y, 0.0, 2.2)
	if track:
		speed = track.speed

	# Lateral follow is softer than the player's own lane snap.
	_current_x = lerp(_current_x, px * 0.62, 1.0 - exp(-delta * 7.0))

	var distance := BASE_DISTANCE + clampf((speed - 11.0) * 0.055, 0.0, 1.1)
	var height := BASE_HEIGHT + py * 0.28
	position.x = _current_x
	position.y = lerp(position.y, height, 1.0 - exp(-delta * 9.0))
	position.z = lerp(position.z, distance, 1.0 - exp(-delta * 4.0))

	var look_point := Vector3(px * 0.55, LOOK_HEIGHT + py * 0.45, LOOK_AHEAD)
	look_at(look_point, Vector3.UP)

	# Speed widens the lens a touch; it is the cheapest "sense of speed" there is.
	var target_fov := _base_fov + clampf((speed - 11.0) * 0.55, 0.0, 6.0)
	fov = lerp(fov, target_fov, 1.0 - exp(-delta * 3.0))

	if _shake_time > 0.0:
		_shake_time -= delta
		var falloff := clampf(_shake_time / 0.35, 0.0, 1.0)
		h_offset = randf_range(-1.0, 1.0) * _shake * falloff * 0.25
		v_offset = randf_range(-1.0, 1.0) * _shake * falloff * 0.25
		if _shake_time <= 0.0:
			_shake = 0.0
			h_offset = 0.0
			v_offset = 0.0


func snap_to_player() -> void:
	if target:
		_current_x = target.position.x * 0.62
	position = Vector3(_current_x, BASE_HEIGHT, BASE_DISTANCE)

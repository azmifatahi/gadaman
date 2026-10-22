## Pooled obstacle. One MeshInstance3D whose mesh is swapped from the library.
class_name TrackProp
extends Node3D

var kind: int = PropLibrary.BARRIER
var lane: int = 1
var pass_type: int = PropLibrary.PASS_JUMP
var clear_height: float = 1.0
var half_width: float = 1.0
var depth_half: float = 0.5
var active: bool = false

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Obstacle"
		add_child(_mesh_instance)


func activate(new_kind: int, lane_index: int, x: float, z: float) -> void:
	if _mesh_instance == null:
		_ready()
	kind = new_kind
	lane = lane_index
	var data := PropLibrary.info(new_kind)
	pass_type = int(data.get("pass", PropLibrary.PASS_DODGE))
	clear_height = float(data.get("clear", 0.0))
	half_width = float(data.get("half_width", 1.0))
	depth_half = float(data.get("depth_half", 0.5))

	_mesh_instance.mesh = PropLibrary.obstacle_mesh(new_kind)
	if _mesh_instance.get_surface_override_material(0) == null:
		_mesh_instance.set_surface_override_material(0,
				MeshKit.vertex_material_cheap() if Perf.tier == Perf.Tier.LOW
				else MeshKit.vertex_material())
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if Perf.shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	position = Vector3(x, 0.0, z)
	# Random yaw keeps the street from looking stamped out of a mould.
	if new_kind in [PropLibrary.CART, PropLibrary.TABLE, PropLibrary.CRATES]:
		rotation.y = randf_range(-0.18, 0.18)
	else:
		rotation.y = 0.0
	scale = Vector3.ONE
	active = true
	visible = true


## Re-applies tier dependent material / shadow flags without touching gameplay.
func apply_quality() -> void:
	if _mesh_instance == null:
		return
	_mesh_instance.set_surface_override_material(0,
			MeshKit.vertex_material_cheap() if Perf.tier == Perf.Tier.LOW
			else MeshKit.vertex_material())
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if Perf.shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func deactivate() -> void:
	active = false
	visible = false


## True when the player's current pose passes this obstacle.
func is_passed_by(feet_y: float, is_sliding: bool) -> bool:
	match pass_type:
		PropLibrary.PASS_JUMP:
			return feet_y >= clear_height
		PropLibrary.PASS_SLIDE:
			return is_sliding
		_:
			return false


func reason_key() -> String:
	return String(PropLibrary.info(kind).get("reason", "crash.barrier"))

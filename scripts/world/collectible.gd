## Pooled collectible cup (aradaib / karkadeh / gongolez).
##
## Three small meshes: the cup itself, a spinning gold ring and a billboarded
## sprite of the hand-painted artwork. The ring is what makes cups readable at
## 60 m in fog.
class_name Collectible
extends Node3D

var kind: int = PropLibrary.CUP_KARKADEH
var active: bool = false

var _cup: MeshInstance3D
var _ring: MeshInstance3D
var _sprite: MeshInstance3D
var _phase: float = 0.0
var _base_y: float = 0.95

static var _ring_mesh: TorusMesh
static var _ring_material: StandardMaterial3D
static var _cup_materials: Dictionary = {}


func _ready() -> void:
	if _cup != null:
		return
	var cheap := Perf.tier == Perf.Tier.LOW
	_cup = MeshInstance3D.new()
	_cup.name = "Cup"
	_cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cup)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.mesh = _get_ring_mesh()
	_ring.set_surface_override_material(0, _get_ring_material())
	add_child(_ring)

	# The painted billboard is only used as a distant readability aid on low-end
	# devices, where it replaces the extra rim light of the 3D cup.
	if cheap:
		_sprite = MeshInstance3D.new()
		_sprite.name = "Sprite"
		_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		_sprite.mesh = quad
		add_child(_sprite)


static func _get_ring_mesh() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.32
		_ring_mesh.outer_radius = 0.4
		_ring_mesh.rings = 12
		_ring_mesh.ring_segments = 6
	return _ring_mesh


static func _get_ring_material() -> StandardMaterial3D:
	if _ring_material == null:
		_ring_material = StandardMaterial3D.new()
		_ring_material.albedo_color = Color("#f2b705")
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.emission_enabled = true
		_ring_material.emission = Color("#f2b705")
		_ring_material.emission_energy_multiplier = 0.8
	return _ring_material


func activate(new_kind: int, x: float, y: float, z: float) -> void:
	if _cup == null:
		_ready()
	kind = new_kind
	_base_y = y
	_phase = randf() * TAU
	position = Vector3(x, y, z)
	_cup.mesh = PropLibrary.cup_mesh(kind)
	if _cup.get_surface_override_material(0) == null:
		_cup.set_surface_override_material(0, _cup_material())
	# Vertical halo that spins around the cup: reads as "pick me up" from 60 m.
	_ring.rotation = Vector3(PI * 0.5, 0, 0)
	_ring.position = Vector3(0, 0.24, 0)
	if _sprite:
		_sprite.set_surface_override_material(0, PropLibrary.cup_sprite_material(kind))
		_sprite.position = Vector3(0, 0.22, 0)
	scale = Vector3.ONE
	visible = true
	active = true
	set_process(true)


func _cup_material() -> StandardMaterial3D:
	if _cup_materials.has("cup"):
		return _cup_materials["cup"]
	var mat := MeshKit.vertex_material().duplicate() as StandardMaterial3D
	# A glossy cone catches the low sun and turns cream on screen; matte keeps the
	# karkadeh red / aradaib amber readable, which is the whole point of the prop.
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.emission_enabled = false
	_cup_materials["cup"] = mat
	return mat


func deactivate() -> void:
	active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not active:
		return
	_phase += delta
	_cup.rotation.y += delta * 2.0
	_ring.rotation.y += delta * 2.6
	position.y = _base_y + sin(_phase * 2.6) * 0.07

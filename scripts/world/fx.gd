## Pooled particle effects: dust, pickups, crash and the "new best" confetti.
##
## Only three CPUParticles3D nodes exist for the whole game. They are moved and
## re-fired, never instantiated during a run. Amounts scale with the quality tier
## (Perf.particle_amount), so a low-end phone emits ~40% of the particles.
class_name Fx
extends Node3D

const DUST_COLOR := Color(0.82, 0.71, 0.55)
const CUP_COLOR := Color(1.0, 0.82, 0.28)
const CONFETTI := [Color("#d21034"), Color("#ffffff"), Color("#009a00"), Color("#f2b705")]

var _dust: CPUParticles3D
var _sparkle: CPUParticles3D
var _confetti: CPUParticles3D
var _puff_texture: Texture2D
var _materials: Dictionary = {}


func _ready() -> void:
	_puff_texture = load("res://assets/textures/puff.png")
	_dust = _make_particles(DUST_COLOR, 14, 0.55, 2.2, 1.1)
	_sparkle = _make_particles(CUP_COLOR, 10, 0.45, 2.8, 0.55)
	_confetti = _make_particles(Color.WHITE, 26, 1.4, 4.5, 0.75)
	_confetti.one_shot = true
	_confetti.emitting = false


func _make_particles(color: Color, base_amount: int, lifetime: float,
		velocity: float, scale: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(4, int(float(base_amount) * maxf(Perf.particle_amount, 0.35)))
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.randomness = 0.6
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.gravity = Vector3(0, -7.5, 0)
	p.initial_velocity_min = velocity * 0.55
	p.initial_velocity_max = velocity
	p.scale_amount_min = scale * 0.55
	p.scale_amount_max = scale
	p.damping_min = 0.4
	p.damping_max = 1.2

	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	p.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _puff_texture
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_materials[p] = mat
	add_child(p)
	return p


func _burst(node: CPUParticles3D, pos: Vector3) -> void:
	node.global_position = pos
	node.emitting = false
	node.restart()
	node.emitting = true


func land_dust(pos: Vector3) -> void:
	_burst(_dust, Vector3(pos.x, 0.1, pos.z))


func pickup_sparkle(pos: Vector3) -> void:
	_burst(_sparkle, pos)


func crash(pos: Vector3) -> void:
	_burst(_dust, Vector3(pos.x, 0.5, pos.z + 0.4))
	_burst(_sparkle, Vector3(pos.x, 0.9, pos.z + 0.4))


func celebrate(pos: Vector3) -> void:
	var mat: StandardMaterial3D = _materials.get(_confetti)
	if mat:
		mat.albedo_color = CONFETTI[randi() % CONFETTI.size()]
	_burst(_confetti, pos + Vector3(0, 1.6, 0))


func apply_quality() -> void:
	for p in [_dust, _sparkle, _confetti]:
		if p == null:
			continue
		var base := 14.0 if p == _dust else (10.0 if p == _sparkle else 26.0)
		p.amount = maxi(4, int(base * maxf(Perf.particle_amount, 0.35)))
	p.emitting = false

## Pooled GPU effects for action impacts. No emitter is allocated during a run.
class_name Fx
extends Node3D

const DUST_COLOR := Color(0.82, 0.71, 0.55, 0.72)
const CUP_COLOR := Color(1.0, 0.82, 0.28, 0.95)
const WOOD_COLOR := Color("#9a6234")
const CONFETTI := [Color("#d21034"), Color.WHITE, Color("#009a00"), Color("#f2b705")]

var _dust: GPUParticles3D
var _sparkle: GPUParticles3D
var _debris: GPUParticles3D
var _confetti: GPUParticles3D


func _ready() -> void:
	_dust = _make_billboard("Dust", DUST_COLOR, 20, 0.72, 3.0, 0.42)
	_sparkle = _make_billboard("DrinkSparkle", CUP_COLOR, 18, 0.6, 4.2, 0.20)
	_confetti = _make_billboard("Confetti", Color.WHITE, 34, 1.5, 5.8, 0.16)
	_debris = _make_debris()


func _base_process(color: Color, velocity: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.28
	process.direction = Vector3(0, 1, 0)
	process.spread = 62.0
	process.gravity = Vector3(0, -8.5, 0)
	process.initial_velocity_min = velocity * 0.55
	process.initial_velocity_max = velocity
	process.scale_min = 0.55
	process.scale_max = 1.25
	process.color = color
	return process


func _make_billboard(label: String, color: Color, amount: int, lifetime: float,
		velocity: float, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.amount = maxi(5, int(amount * Perf.particle_amount))
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.randomness = 0.72
	particles.emitting = false
	particles.process_material = _base_process(color, velocity)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/puff.png")
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


func _make_debris() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "CrateDebris"
	particles.amount = maxi(8, int(24.0 * Perf.particle_amount))
	particles.lifetime = 1.25
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.85
	particles.emitting = false
	var process := _base_process(WOOD_COLOR, 7.0)
	process.angular_velocity_min = -720.0
	process.angular_velocity_max = 720.0
	particles.process_material = process
	var chip := BoxMesh.new()
	chip.size = Vector3(0.08, 0.045, 0.24)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD_COLOR
	wood.roughness = 0.82
	chip.material = wood
	particles.draw_pass_1 = chip
	add_child(particles)
	return particles


func _burst(node: GPUParticles3D, pos: Vector3) -> void:
	node.global_position = pos
	node.emitting = false
	node.restart()
	node.emitting = true


func land_dust(pos: Vector3) -> void:
	_burst(_dust, Vector3(pos.x, 0.1, pos.z))


func slide_dust(pos: Vector3) -> void:
	_burst(_dust, Vector3(pos.x, 0.14, pos.z + 0.35))


func pickup_sparkle(pos: Vector3) -> void:
	_burst(_sparkle, pos)


func crash(pos: Vector3) -> void:
	_burst(_dust, Vector3(pos.x, 0.45, pos.z + 0.35))
	_burst(_sparkle, Vector3(pos.x, 0.9, pos.z + 0.35))


func crate_debris(pos: Vector3) -> void:
	_burst(_debris, pos + Vector3(0, 0.65, 0))
	_burst(_dust, pos + Vector3(0, 0.2, 0))


func celebrate(pos: Vector3) -> void:
	var process := _confetti.process_material as ParticleProcessMaterial
	if process:
		process.color = CONFETTI[randi() % CONFETTI.size()]
	_burst(_confetti, pos + Vector3(0, 1.6, 0))


func apply_quality() -> void:
	_dust.amount = maxi(5, int(20.0 * Perf.particle_amount))
	_sparkle.amount = maxi(5, int(18.0 * Perf.particle_amount))
	_debris.amount = maxi(8, int(24.0 * Perf.particle_amount))
	_confetti.amount = maxi(8, int(34.0 * Perf.particle_amount))
	for particles in [_dust, _sparkle, _debris, _confetti]:
		particles.emitting = false

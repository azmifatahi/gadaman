## The runner: a low-poly character wrapped in the Sudanese flag.
##
## 11 boxes and one cape plane - about 300 triangles in total, which is what
## lets the game hold 60/120 FPS on a 2 GB phone. All animation is procedural
## (sine-driven limb swing), so there is no skeleton, no skinning shader and no
## AnimationPlayer cost on the CPU.
class_name RunnerModel
extends Node3D

enum State { IDLE, RUN, CRASH }

const HIP_Y := 0.78
const SHOULDER_Y := 1.34

var lean: float = 0.0
var state: int = State.RUN

var _root: Node3D
var _torso: MeshInstance3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _cape: Node3D
var _cycle: float = 0.0
var _cape_swing: float = 0.0

static var _mat_flag: StandardMaterial3D
static var _mat_flag_double: StandardMaterial3D
static var _mat_skin: StandardMaterial3D
static var _mat_shoe: StandardMaterial3D
static var _mat_gold: StandardMaterial3D
static var _mat_dark: StandardMaterial3D
static var _mat_red: StandardMaterial3D
static var _mat_trousers: StandardMaterial3D


func _ready() -> void:
	if _root != null:
		return
	_build_materials()
	_build_body()
	reset_pose()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
static func _build_materials() -> void:
	var flag_tex: Texture2D = load("res://assets/textures/flag.png")
	if _mat_flag == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = flag_tex
		m.roughness = 0.72
		m.metallic = 0.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mat_flag = m
	if _mat_flag_double == null:
		var m2 := StandardMaterial3D.new()
		m2.albedo_texture = load("res://assets/textures/flag_stripes.png")
		m2.roughness = 0.8
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_flag_double = m2
	if _mat_skin == null:
		var s := StandardMaterial3D.new()
		s.albedo_color = Color("#6d4429")
		s.roughness = 0.85
		_mat_skin = s
	if _mat_shoe == null:
		var sh := StandardMaterial3D.new()
		sh.albedo_color = Color("#f0ece2")
		sh.roughness = 0.6
		_mat_shoe = sh
	if _mat_gold == null:
		var g := StandardMaterial3D.new()
		g.albedo_color = Color("#f2b705")
		g.roughness = 0.35
		g.metallic = 0.5
		_mat_gold = g
	if _mat_dark == null:
		var d := StandardMaterial3D.new()
		d.albedo_color = Color("#17191c")
		d.roughness = 0.9
		_mat_dark = d
	if _mat_red == null:
		var r := StandardMaterial3D.new()
		r.albedo_color = Color("#d21034")
		r.roughness = 0.8
		_mat_red = r
	if _mat_trousers == null:
		var t := StandardMaterial3D.new()
		t.albedo_color = Color("#efe9dc")
		t.roughness = 0.85
		_mat_trousers = t


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		name_hint: String = "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.name = name_hint
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _build_body() -> void:
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)

	# Torso wrapped in the flag: box UVs map the flag onto every face.
	_torso = _box(_root, Vector3(0.54, 0.62, 0.32), Vector3(0, 1.08, 0),
			_mat_flag, "Torso")
	# Hips / shorts.
	_box(_root, Vector3(0.5, 0.22, 0.3), Vector3(0, HIP_Y, 0), _mat_dark, "Hips")
	# Chest strap for a bit of tailoring.
	_box(_root, Vector3(0.58, 0.07, 0.36), Vector3(0, 1.2, 0), _mat_gold, "Strap")

	# Head group: skull, headband, eyes.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.44, 0)
	_root.add_child(_head)
	_box(_head, Vector3(0.32, 0.32, 0.3), Vector3(0, 0.16, 0), _mat_skin, "Skull")
	_box(_head, Vector3(0.34, 0.07, 0.32), Vector3(0, 0.29, 0), _mat_gold, "Band")
	_box(_head, Vector3(0.09, 0.05, 0.02), Vector3(-0.08, 0.18, -0.151), _mat_dark, "EyeL")
	_box(_head, Vector3(0.09, 0.05, 0.02), Vector3(0.08, 0.18, -0.151), _mat_dark, "EyeR")
	_box(_head, Vector3(0.2, 0.03, 0.02), Vector3(0, 0.09, -0.151), _mat_dark, "Mouth")
	# Neck.
	_box(_root, Vector3(0.14, 0.12, 0.14), Vector3(0, 1.32, 0), _mat_skin, "Neck")

	# Arms: pivot at the shoulder so rotation.x swings the whole limb.
	_arm_l = _limb(Vector3(-0.35, SHOULDER_Y, 0), Vector3(0.14, 0.46, 0.14),
			_mat_flag, _mat_skin, "ArmL")
	_arm_r = _limb(Vector3(0.35, SHOULDER_Y, 0), Vector3(0.14, 0.46, 0.14),
			_mat_flag, _mat_skin, "ArmR")
	# Legs.
	# Cream trousers with a flag-red side stripe: instantly readable against the
	# dark asphalt, and it ties the character to the flag palette.
	_leg_l = _limb(Vector3(-0.13, HIP_Y, 0), Vector3(0.18, 0.62, 0.2),
			_mat_trousers, _mat_shoe, "LegL")
	_leg_r = _limb(Vector3(0.13, HIP_Y, 0), Vector3(0.18, 0.62, 0.2),
			_mat_trousers, _mat_shoe, "LegR")
	_box(_leg_l, Vector3(0.05, 0.5, 0.02), Vector3(-0.07, -0.28, -0.1), _mat_red, "StripeL")
	_box(_leg_r, Vector3(0.05, 0.5, 0.02), Vector3(-0.07, -0.28, -0.1), _mat_red, "StripeR")

	# Cape: a flag panel hanging off the shoulders, animated by hand.
	_cape = Node3D.new()
	_cape.name = "Cape"
	_cape.position = Vector3(0, 1.30, 0.16)
	_root.add_child(_cape)
	var cape_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.52, 0.66)
	cape_mesh.mesh = quad
	cape_mesh.material_override = _mat_flag_double
	cape_mesh.position = Vector3(0, -0.33, 0)
	cape_mesh.rotation = Vector3(0, PI, 0)
	cape_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cape.add_child(cape_mesh)


func _limb(pivot: Vector3, size: Vector3, upper_mat: Material, end_mat: Material,
		name_hint: String) -> Node3D:
	var node := Node3D.new()
	node.name = name_hint
	node.position = pivot
	_root.add_child(node)
	var upper := _box(node, size, Vector3(0, -size.y * 0.5, 0), upper_mat, "Upper")
	upper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_box(node, size * Vector3(1.05, 0.35, 1.1), Vector3(0, -size.y - 0.02, -0.02),
			end_mat, "End")
	return node


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
func reset_pose() -> void:
	state = State.RUN
	_cycle = 0.0
	if _root:
		_root.rotation = Vector3.ZERO
		_root.position = Vector3.ZERO
	if _head:
		_head.rotation = Vector3.ZERO
	if _arm_l:
		_arm_l.rotation = Vector3.ZERO
		_arm_r.rotation = Vector3.ZERO
	if _leg_l:
		_leg_l.rotation = Vector3.ZERO
		_leg_r.rotation = Vector3.ZERO


func set_state(new_state: int) -> void:
	state = new_state


## Called every physics frame by PlayerController.
func animate(delta: float, speed: float, sliding: bool, airborne: bool) -> void:
	if _root == null:
		return
	if state == State.CRASH:
		_animate_crash(delta)
		return

	var target_pitch := 0.0
	var target_height := 0.0
	if sliding:
		target_pitch = -1.05
		target_height = 0.12
	var blend := 1.0 - exp(-delta * 18.0)
	_root.rotation.x = lerp(_root.rotation.x, target_pitch, blend)
	_root.position.y = lerp(_root.position.y, target_height, blend)
	_root.rotation.z = lerp(_root.rotation.z, -lean, blend)

	_cycle += delta * (3.4 + speed * 0.42)
	var swing := sin(_cycle)
	var swing2 := sin(_cycle + PI)

	if airborne:
		# Tuck the legs, throw the arms up: readable at 20 m.
		_leg_l.rotation.x = lerp(_leg_l.rotation.x, -0.75, blend)
		_leg_r.rotation.x = lerp(_leg_r.rotation.x, 0.55, blend)
		_arm_l.rotation.x = lerp(_arm_l.rotation.x, -2.1, blend)
		_arm_r.rotation.x = lerp(_arm_r.rotation.x, -2.1, blend)
	elif sliding:
		_leg_l.rotation.x = lerp(_leg_l.rotation.x, 0.95, blend)
		_leg_r.rotation.x = lerp(_leg_r.rotation.x, 0.75, blend)
		_arm_l.rotation.x = lerp(_arm_l.rotation.x, 0.7, blend)
		_arm_r.rotation.x = lerp(_arm_r.rotation.x, -0.4, blend)
	else:
		_leg_l.rotation.x = swing * 0.95
		_leg_r.rotation.x = swing2 * 0.95
		_arm_l.rotation.x = swing2 * 0.8
		_arm_r.rotation.x = swing * 0.8

	# Bob + head counter-rotation keeps the run from looking like a toy.
	_head.rotation.x = sin(_cycle * 2.0) * 0.05 - _root.rotation.x * 0.35
	# Cape trails behind (+Z) and flutters faster the quicker we run.
	_cape_swing = lerp(_cape_swing, 0.75 + speed * 0.028, blend)
	_cape.rotation.x = -_cape_swing + sin(_cycle * 2.3) * 0.12
	_cape.rotation.z = sin(_cycle * 1.7) * 0.06


func _animate_crash(delta: float) -> void:
	_root.rotation.x = lerp(_root.rotation.x, 1.35, 1.0 - exp(-delta * 6.0))
	_root.position.y = lerp(_root.position.y, -0.15, 1.0 - exp(-delta * 6.0))
	_arm_l.rotation.x = lerp(_arm_l.rotation.x, -2.4, 1.0 - exp(-delta * 8.0))
	_arm_r.rotation.x = lerp(_arm_r.rotation.x, -2.1, 1.0 - exp(-delta * 8.0))
	_leg_l.rotation.x = lerp(_leg_l.rotation.x, 0.7, 1.0 - exp(-delta * 8.0))
	_leg_r.rotation.x = lerp(_leg_r.rotation.x, -0.4, 1.0 - exp(-delta * 8.0))


func play_crash() -> void:
	state = State.CRASH


func head_world_y() -> float:
	return global_position.y + 1.6

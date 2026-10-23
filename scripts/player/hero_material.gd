@tool
class_name HeroMaterial
extends RefCounted
## Sudan-flag "suit" material shared by the imported hero and the procedural runner.
##
## IMPORTANT: keep it dielectric (metallic ~0). The project renders with the
## gl_compatibility backend and world.gd disables reflections on that backend,
## so a strongly metallic surface has nothing to reflect and collapses to
## near-black — on the dark asphalt at dusk that reads as "the character is
## not there". A bright albedo + high roughness stays readable on any GPU
## (including the 2 GB budget phones this game targets).

const FLAG: Texture2D = preload("res://assets/textures/flag.png")
const SEAMS: Texture2D = preload("res://assets/textures/suit_seams_normal.png")


static func make_suit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Sudan Flag Suit"
	m.albedo_texture = FLAG
	m.albedo_color = Color(1, 1, 1, 1)
	m.metallic = 0.05
	m.metallic_specular = 0.5
	m.roughness = 0.55
	m.normal_enabled = true
	m.normal_texture = SEAMS
	m.normal_scale = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m

## One pooled chunk of street visuals.
##
## Pooled by TrackManager: the node is never freed, only re-positioned and given
## a different (cached) mesh. The mesh itself is shared between chunks with the
## same layout + variant slot, so recycling allocates nothing.
##
## Materials are bound by NAME, not by index: `SegmentBuilder.build()` writes the
## list of surfaces it actually emitted into the mesh meta `"surfaces"`, so a
## variant that has no river (or no steel truss) never ends up painted with the
## wrong texture.
class_name TrackSegment
extends Node3D

## Surface name -> material factory. Photographic surfaces come from the
## reference photos in `art_src/` via `tools/build_textures.py`.
const MATERIALS := {
	"road": "asphalt_photo_material",
	"walk": "pavement_photo_material",
	"facade": "facade_material",
	"facade_b": "facade_material",
	"facade_c": "facade_material",
	"water": "water_photo_material",
	"steel": "steel_truss_material",
	"concrete": "concrete_photo_material",
	"ground": "sand_material",
	"leaf": "palm_frond_material",
	"leaves": "leaf_cluster_material",
}

var variant: int = 0
var mesh_slot: int = 0
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_mesh_instance)


func apply(new_variant: int, new_slot: int, density: float) -> void:
	variant = new_variant
	mesh_slot = new_slot
	if _mesh_instance == null:
		_ready()
	_mesh_instance.mesh = SegmentBuilder.build(variant, mesh_slot, density)
	_apply_materials()


func _apply_materials() -> void:
	var mesh := _mesh_instance.mesh
	if mesh == null:
		return
	var names: PackedStringArray = []
	if mesh.has_meta("surfaces"):
		names = mesh.get_meta("surfaces")
	for i in range(mesh.get_surface_count()):
		var surface_name := String(names[i]) if i < names.size() else "art"
		_mesh_instance.set_surface_override_material(i, _material_for(surface_name))


func _material_for(surface_name: String) -> Material:
	# Vertex-coloured props: the only surface that changes with the tier.
	if surface_name == "art" or not MATERIALS.has(surface_name):
		return MeshKit.vertex_material_cheap() if Perf.tier == Perf.Tier.LOW \
				else MeshKit.vertex_material()
	# Photo surfaces keep their albedo on every tier (a vertex-coloured road
	# would be flat white); the per-material cost is dropped instead — the
	# asphalt/pavement materials skip their normal map below HIGH, which is the
	# expensive part on a weak GPU.
	match surface_name:
		"road":
			return MeshKit.asphalt_photo_material()
		"walk":
			return MeshKit.pavement_photo_material()
		"facade":
			return MeshKit.facade_material(0)
		"facade_b":
			return MeshKit.facade_material(1)
		"facade_c":
			return MeshKit.facade_material(2)
		"water":
			return MeshKit.water_photo_material()
		"steel":
			return MeshKit.steel_truss_material()
		"concrete":
			return MeshKit.concrete_photo_material()
		"ground":
			return MeshKit.sand_material()
		"leaf":
			# Alpha-scissor foliage: cheap on every tier, and the only surface
			# where the photo cut-out matters more than the lighting cost.
			return MeshKit.palm_frond_material()
		"leaves":
			return MeshKit.leaf_cluster_material()
	return MeshKit.vertex_material()


func refresh_materials() -> void:
	_apply_materials()

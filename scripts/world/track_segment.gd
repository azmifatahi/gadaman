## One pooled chunk of street visuals.
##
## Pooled by TrackManager: the node is never freed, only re-positioned and given
## a different (cached) mesh. The mesh itself is shared between chunks with the
## same layout + variant slot, so recycling allocates nothing.
class_name TrackSegment
extends Node3D

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
	_mesh_instance.set_surface_override_material(0, MeshKit.road_material())
	var vertex_mat := MeshKit.vertex_material_cheap() if Perf.tier == Perf.Tier.LOW \
			else MeshKit.vertex_material()
	_mesh_instance.set_surface_override_material(1, vertex_mat)
	_mesh_instance.set_surface_override_material(2, MeshKit.sand_material())


func refresh_materials() -> void:
	_apply_materials()

@tool
extends EditorScript
## One-click visual upgrader for a selected runner/model node.
## Run from Script Editor > File > Run (Ctrl+Shift+X). It upgrades existing
## MeshInstance3D materials non-destructively and adds a local reflection probe.

const FLAG := preload("res://assets/textures/flag.png")
const SEAMS := preload("res://assets/textures/suit_seams_normal.png")


func _run() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	if selected.is_empty():
		push_error("Select Player, Model, or an imported hero root before running SetupRealisticRunner.")
		return
	var root := selected[0] as Node
	var upgraded := upgrade_runner(root)
	ensure_reflection_probe(root)
	get_editor_interface().mark_scene_as_unsaved()
	print("Realistic runner setup complete: %d mesh surfaces upgraded." % upgraded)


static func make_suit_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Sudan Chrome Suit PBR"
	material.albedo_texture = FLAG
	material.metallic = 0.8
	material.roughness = 0.2
	material.normal_enabled = true
	material.normal_texture = SEAMS
	material.normal_scale = 0.42
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


static func upgrade_runner(root: Node) -> int:
	var count := 0
	var suit := make_suit_material()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var lower := mesh_instance.name.to_lower()
		if lower.contains("eye") or lower.contains("shoe") or lower.contains("skin"):
			continue
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, suit)
			count += 1
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return count


static func ensure_reflection_probe(root: Node) -> ReflectionProbe:
	var existing := root.get_node_or_null("SudanSuitReflectionProbe") as ReflectionProbe
	if existing:
		return existing
	var probe := ReflectionProbe.new()
	probe.name = "SudanSuitReflectionProbe"
	probe.position = Vector3(0.0, 1.05, 0.0)
	probe.size = Vector3(7.0, 5.0, 9.0)
	probe.intensity = 1.15
	probe.max_distance = 18.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	root.add_child(probe)
	if Engine.is_editor_hint() and root.owner:
		probe.owner = root.owner
	return probe

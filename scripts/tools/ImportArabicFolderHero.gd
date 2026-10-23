@tool
extends EditorScript
## =============================================================================
##  ImportArabicFolderHero.gd  —  Editor one-click import.
##  ----------------------------------------------------------------------------
##  Thin wrapper around the shared HeroBuilder class. Press Ctrl+Shift+X in the
##  script editor to run it. All real logic lives in scripts/tools/hero_builder.gd
##  so the same code also runs headlessly in CI (see tools/ci_build_hero.gd).
## =============================================================================


func _run() -> void:
	var ok := HeroBuilder.build_hero()
	if ok:
		get_editor_interface().get_resource_filesystem().scan()
		get_editor_interface().mark_scene_as_unsaved()
		print("[ImportArabicFolderHero] Done – open scenes/main.tscn and press Play.")
	else:
		push_error("[ImportArabicFolderHero] Build failed – check the Output panel.")

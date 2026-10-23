@tool
extends EditorScript
## =============================================================================
##  ImportArabicFolderHero.gd  —  One-click editor import.
## -----------------------------------------------------------------------------
##  Opens in the script editor, press Ctrl+Shift+X to run. Thin wrapper over
##  HeroBuilder. The real pipeline lives in scripts/tools/hero_builder.gd and
##  runs headlessly from tools/ci_build_hero.gd in CI.
## =============================================================================


func _run() -> void:
	var ok: bool = HeroBuilder.build_hero(true)
	if ok:
		get_editor_interface().get_resource_filesystem().scan()
		get_editor_interface().mark_scene_as_unsaved()
		print("[ImportArabicFolderHero] Done. Hero scene at %s" % HeroBuilder.HERO_SCENE_PATH)
		print("[ImportArabicFolderHero] verify: %s" % JSON.stringify(HeroBuilder.verify(), "  "))
	else:
		push_error("[ImportArabicFolderHero] Build failed – check the Output panel.")
		push_error("[ImportArabicFolderHero] verify: %s" % JSON.stringify(HeroBuilder.verify(), "  "))

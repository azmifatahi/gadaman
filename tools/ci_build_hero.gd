#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero build for GitHub Actions.
##  ----------------------------------------------------------------------------
##  Invoked from the workflow AFTER `godot --headless --import` (so all FBX
##  clips in res://الشخصيه/ are already imported) and BEFORE
##  `godot --headless --export-release`. Calls HeroBuilder.build_hero() and
##  quits with exit code 0 on success / non-zero on failure, so the CI step
##  fails loudly if something is wrong with the assets instead of silently
##  shipping an APK that still uses the procedural fallback.
##
##  Usage:  godot --headless --script tools/ci_build_hero.gd
## =============================================================================
extends SceneTree


func _initialize() -> void:
	# Let the engine tick one frame so ResourceLoader finishes its post-import
	# scan before we try to instantiate PackedScenes from the Arabic FBX.
	await process_frame
	print("[CIBuildHero] Starting automated hero build")
	var ok := HeroBuilder.build_hero()
	if not ok:
		printerr("[CIBuildHero] Hero build FAILED")
		quit(1)
		# Force-quit even if Godot hangs.
		OS.crash("[CIBuildHero] aborting")
	print("[CIBuildHero] Hero build OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	quit(0)

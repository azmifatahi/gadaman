#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero build for GitHub Actions.
##  ----------------------------------------------------------------------------
##  Invoked after `godot --headless --import` and before the APK export. It
##  builds assets/models/hero/hero.tscn directly (no MainLoop await needed),
##  then exits with 0 on success / non-zero on failure.
##
##  Usage:  godot --headless --script tools/ci_build_hero.gd
## =============================================================================
extends RefCounted


func _init() -> void:
	# When running via --headless --script, Godot executes _init() synchronously
	# then quits. Using await/SceneTree here can hang because the main loop
	# never pumps. Build the hero directly.
	print("[CIBuildHero] Starting automated hero build")
	var ok := HeroBuilder.build_hero()
	if not ok:
		printerr("[CIBuildHero] Hero build FAILED")
		OS.exit_code = 1
		return
	print("[CIBuildHero] Hero build OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	OS.exit_code = 0

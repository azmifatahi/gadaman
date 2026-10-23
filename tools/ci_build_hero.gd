#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero build for GitHub Actions.
## -----------------------------------------------------------------------------
##  Pass --strict on the command line (after a -- argument delimiter) to make
##  failures fatal. In the validate job we use --relaxed (a missing FBX2glTF
##  just means the procedural model ships temporarily); in the APK job we use
##  --strict so we never accidentally ship a capsule-model APK.
## =============================================================================
extends SceneTree

func _initialize() -> void:
	var strict := "--strict" in OS.get_cmdline_args()
	print("[CIBuildHero] Starting automated hero build (strict=%s)" % strict)
	var ok := HeroBuilder.build_hero(not strict)
	if not ok:
		if strict:
			printerr("[CIBuildHero] Hero build FAILED")
			quit(1)
			return
		push_warning("[CIBuildHero] Hero build skipped (FBX2glTF missing or FBX not imported); procedural model will ship this run.")
		quit(0)
		return
	print("[CIBuildHero] Hero build OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	quit(0)

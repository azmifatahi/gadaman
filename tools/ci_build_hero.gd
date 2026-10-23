#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero build for GitHub Actions.
##  ----------------------------------------------------------------------------
##  When run via `godot --headless --script <path>`, Godot attaches the script
##  to the SceneTree and calls _initialize() once. We build the hero
##  synchronously there and call quit() immediately. We DO NOT use await here
##  because headless --script mode does not pump the main loop the way a
##  running scene does, so awaiting a signal/frame hangs forever.
## =============================================================================
extends SceneTree


func _initialize() -> void:
	print("[CIBuildHero] Starting automated hero build")
	var ok := HeroBuilder.build_hero()
	if not ok:
		printerr("[CIBuildHero] Hero build FAILED")
		quit(1)
		return
	print("[CIBuildHero] Hero build OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	quit(0)

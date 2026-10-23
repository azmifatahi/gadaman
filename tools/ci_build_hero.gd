#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero scene build for GitHub Actions.
## -----------------------------------------------------------------------------
##  Invoked from build.yml AFTER `godot --headless --import` (which converts all
##  .fbx assets using Godot's built-in ufbx importer) and BEFORE
##  `godot --export-release`. Pass --strict to fail the build if the hero is
##  missing (APK job); without it (validate job) warnings are non-fatal.
## =============================================================================
extends SceneTree


func _initialize() -> void:
	# `--strict` may arrive before or after the `--` separator depending on how
	# the workflow invokes us, so accept both forms.
	var strict: bool = "--strict" in OS.get_cmdline_args() \
		or "--strict" in OS.get_cmdline_user_args()
	print("[CIBuildHero] starting (strict=%s)" % strict)
	var ok: bool = HeroBuilder.build_hero(strict)
	if not ok:
		var report: Dictionary = HeroBuilder.verify()
		printerr("[CIBuildHero] FAILED: %s" % JSON.stringify(report, "  "))
		quit(1 if strict else 0)
		return
	print("[CIBuildHero] OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	quit(0)

#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_verify_hero.gd — proves that the generated hero scene is really drawable.
## -----------------------------------------------------------------------------
##  Run AFTER tools/ci_build_hero.gd in both CI jobs:
##      godot --headless --script tools/ci_verify_hero.gd -- --strict
##
##  It instantiates res://assets/models/hero/hero.tscn and checks that it holds
##  a skinned mesh with a sane size, a working skeleton, an AnimationTree and
##  every required clip with tracks that resolve inside the scene.
##
##  --strict makes the job fail (used by the APK job, so we can never publish an
##  APK whose runner is invisible again). Without it the report is informational.
## =============================================================================
extends SceneTree


func _initialize() -> void:
	var strict: bool = "--strict" in OS.get_cmdline_args() \
		or "--strict" in OS.get_cmdline_user_args()
	var report: Dictionary = HeroBuilder.verify()
	print("[CIVerifyHero] %s" % JSON.stringify(report, "  "))

	if not bool(report.get("ok", false)):
		var problems: Array = report.get("problems", [])
		for problem in problems:
			printerr("[CIVerifyHero] PROBLEM: %s" % String(problem))
		if strict:
			printerr("[CIVerifyHero] FAILED — refusing to ship an unusable hero.")
			quit(1)
			return
		print("[CIVerifyHero] finished with %d problem(s) (non-strict, not fatal)." % problems.size())
		quit(0)
		return

	print("[CIVerifyHero] OK meshes=%d verts=%d bones=%d height=%.2fm feet=%.2fm clips=%s" % [
		int(report["meshes"]), int(report["vertices"]), int(report["bones"]),
		float(report["height"]), float(report["feet"]), report["clips"]])
	quit(0)

#!/usr/bin/env -S godot --headless --script
## =============================================================================
##  ci_build_hero.gd  —  Headless hero build for GitHub Actions.
## =============================================================================
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_args()
	var strict := "--strict" in args
	print("[CIBuildHero] start strict=%s" % strict)
	# Only attempt the build if we can see FBX2glTF on PATH (FBX files) OR if
	# there are GLB files in الشخصيه/. We probe by shelling out to `which`
	# because Godot's FBX importer will hang indefinitely if FBX2glTF is not
	# installed, even for "exists" checks.
	var dir_path := ""
	for cand in ["res://الشخصيه/", "res://الشخصية/"]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cand)):
			dir_path = cand
			break
	if dir_path == "":
		print("[CIBuildHero] Arabic folder not found; skipping.")
		quit(0 if not strict else 1)
		return
	var fbx2gltf_ok := false
	var output: Array = []
	var exit_code := OS.execute("bash", ["-c", "command -v FBX2glTF >/dev/null 2>&1 && echo YES || echo NO"], output, true)
	if exit_code == OK:
		for line in output:
			if "YES" in String(line):
				fbx2gltf_ok = true
	# Check whether there are any GLB files.
	var has_glb := false
	var da := DirAccess.open(dir_path)
	if da:
		da.list_dir_begin()
		var n := da.get_next()
		while n != "":
			if n.to_lower().ends_with(".glb") or n.to_lower().ends_with(".gltf"):
				has_glb = true
			n = da.get_next()
		da.list_dir_end()
	if not fbx2gltf_ok and not has_glb:
		print("[CIBuildHero] FBX2glTF not on PATH and no GLB files; hero build skipped (procedural model used).")
		quit(0 if not strict else 1)
		return
	print("[CIBuildHero] FBX2glTF_OK=%s GLB_OK=%s - building hero" % [fbx2gltf_ok, has_glb])
	var ok := HeroBuilder.build_hero(not strict)
	if not ok:
		printerr("[CIBuildHero] Hero build FAILED")
		quit(1 if strict else 0)
		return
	print("[CIBuildHero] Hero build OK -> %s" % HeroBuilder.HERO_SCENE_PATH)
	quit(0)

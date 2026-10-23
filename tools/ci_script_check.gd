extends SceneTree
## =============================================================================
##  ci_script_check.gd — compiles every GDScript in the project.
## -----------------------------------------------------------------------------
##  gdparse only checks syntax, so it happily accepts code that GDScript 2
##  rejects at compile time (a property read on a base-typed variable, an
##  uninferable `:=`, a missing enum member...). Those failures only surface
##  when the engine loads the script, which used to mean "somewhere deep in the
##  APK job". Loading every script here makes them a 20 second step.
##
##  Usage:  godot --headless --script tools/ci_script_check.gd
## =============================================================================

const ROOTS := ["res://scripts", "res://tools"]
## Loaded by design only through preload(); listed so a broken file cannot hide.
var _problems: Array[String] = []


func _initialize() -> void:
	var count := 0
	for root_path in ROOTS:
		count += _walk(root_path)
	if _problems.is_empty():
		print("[CIScripts] OK: %d scripts compiled." % count)
		quit(0)
		return
	for path in _problems:
		printerr("[CIScripts] CANNOT COMPILE: %s" % path)
	printerr("[CIScripts] FAILED: %d script(s) do not compile." % _problems.size())
	quit(1)


func _walk(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				count += _walk(full)
		elif entry.ends_with(".gd"):
			count += 1
			# `load()` runs the compiler; a broken script returns null and the
			# engine has already printed the exact parse error into the log.
			if load(full) == null:
				_problems.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return count

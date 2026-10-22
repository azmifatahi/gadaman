## Version + migration manager.
##
## Tracks the last-installed version in `user://version.cfg`. On first run after
## an upgrade (including the jump from the old 1.0.0 debug-signed APK to the
## new stable-signed 1.1.0), exposes `update_notes` so the UI can show a short
## "What's new" popup instead of surprising the player.
extends Node

const CURRENT_VERSION := ProjectSettings.get_setting("application/config/version", "1.1.0")
const VERSION_FILE := "user://version.cfg"

var previous_version: String = ""
var just_installed: bool = false
var just_upgraded: bool = false
var update_notes: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_version_file()
	just_installed = previous_version == ""
	just_upgraded = not just_installed and previous_version != CURRENT_VERSION
	_build_notes()
	_save_version_file()
	if just_upgraded:
		push_warning("Upgraded from %s to %s" % [previous_version, CURRENT_VERSION])
	elif just_installed:
		print("First run of Sudan Runner %s" % CURRENT_VERSION)


func _load_version_file() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(VERSION_FILE)
	if err == OK:
		previous_version = str(cfg.get_value("version", "last", ""))
	else:
		# No version file -> first install.
		previous_version = ""


func _save_version_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("version", "last", CURRENT_VERSION)
	cfg.save(VERSION_FILE)


func _build_notes() -> void:
	if just_installed:
		return
	if _version_less(previous_version, "1.1.0"):
		update_notes.append(_t("update.hero"))       # New 3D hero model
		update_notes.append(_t("update.suit"))       # Sudan flag PBR suit
		update_notes.append(_t("update.upgrade_fix"))# Seamless future updates
		update_notes.append(_t("update.anims"))      # Imported Run/Jump/Slide...


func _t(key: String) -> String:
	if has_node("/root/Loc"):
		return get_node("/root/Loc").t(key)
	return key


func _version_less(a: String, b: String) -> bool:
	var pa := _parse(a)
	var pb := _parse(b)
	for i in range(maxi(pa.size(), pb.size())):
		var xa := pa[i] if i < pa.size() else 0
		var xb := pb[i] if i < pb.size() else 0
		if xa < xb:
			return true
		if xa > xb:
			return false
	return false


func _parse(v: String) -> Array:
	var parts := v.split(".")
	var out := []
	for p in parts:
		var n := p.to_int()
		out.append(n if n != 0 or p.is_valid_int() else 0)
	return out

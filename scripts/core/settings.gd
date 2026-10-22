## Persistent player settings + quality toggles.
##
## Lives at the top of the autoload stack because PerformanceManager reads
## `graphics_preset` during _ready(), so this node must be initialised first.
extends Node

signal changed(key: String)
signal language_changed(lang: String)

const SAVE_PATH := "user://sudan_runner_settings.cfg"

## 0 = automatic (hardware detection), 1 = low, 2 = medium, 3 = high.
const PRESETS: Array[String] = ["auto", "low", "medium", "high"]

var graphics_preset: int = 0
## 0 = follow the device refresh rate, otherwise 30 / 60 / 90 / 120.
var fps_cap: int = 0
var tilt_enabled: bool = false
var haptics_enabled: bool = true
var music_volume: float = 0.75
var sfx_volume: float = 0.9
var language: String = "ar"
## Set once the player has finished (or skipped) the tutorial overlay.
var tutorial_seen: bool = false
## Locally cached best run, GameManager keeps its own copy in "user://progress.cfg".
var player_name: String = ""

var _config := ConfigFile.new()
var _save_queued: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Arabic is the default; the OS locale only switches us to English when the
	# device is clearly not Arabic speaking.
	if not _config.has_section_key("general", "language"):
		var locale := OS.get_locale_language()
		if locale in ["ar"]:
			language = "ar"
		elif locale in ["en", "fr", "es", "de", "tr", "id"]:
			language = "en"
	_apply_audio()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func set_graphics_preset(value: int) -> void:
	graphics_preset = clampi(value, 0, 3)
	_save()
	changed.emit("graphics_preset")
	if has_node("/root/Perf"):
		get_node("/root/Perf").apply_preset(graphics_preset)


func set_fps_cap(value: int) -> void:
	fps_cap = value
	_save()
	changed.emit("fps_cap")
	if has_node("/root/Perf"):
		get_node("/root/Perf").apply_fps_cap(value)


func set_tilt_enabled(value: bool) -> void:
	tilt_enabled = value
	_save()
	changed.emit("tilt_enabled")


func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_save()
	changed.emit("haptics_enabled")


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save()
	changed.emit("music_volume")


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save()
	changed.emit("sfx_volume")


func set_language(value: String) -> void:
	if value == language:
		return
	language = "ar" if value == "ar" else "en"
	_save()
	language_changed.emit(language)
	changed.emit("language")


func set_tutorial_seen(value: bool) -> void:
	tutorial_seen = value
	_save()
	changed.emit("tutorial_seen")


## Haptics wrapper: silently no-ops on desktop and when the player disabled it.
func vibrate(duration_ms: int) -> void:
	if not haptics_enabled:
		return
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	Input.vibrate_handheld(duration_ms)


func reset_progress_flags() -> void:
	tutorial_seen = false
	_save()


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
func load_settings() -> void:
	var err := _config.load(SAVE_PATH)
	if err != OK:
		return
	graphics_preset = int(_config.get_value("video", "graphics_preset", graphics_preset))
	fps_cap = int(_config.get_value("video", "fps_cap", fps_cap))
	tilt_enabled = bool(_config.get_value("input", "tilt_enabled", tilt_enabled))
	haptics_enabled = bool(_config.get_value("input", "haptics_enabled", haptics_enabled))
	music_volume = float(_config.get_value("audio", "music", music_volume))
	sfx_volume = float(_config.get_value("audio", "sfx", sfx_volume))
	language = String(_config.get_value("general", "language", language))
	tutorial_seen = bool(_config.get_value("general", "tutorial_seen", tutorial_seen))
	player_name = String(_config.get_value("general", "player_name", player_name))


func _apply_audio() -> void:
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_volumes(music_volume, sfx_volume)


func _save() -> void:
	if _save_queued:
		return
	_save_queued = true
	# Coalesce bursts (sliders!) into one disk write per frame.
	_flush_save.call_deferred()


func _flush_save() -> void:
	_save_queued = false
	_config.set_value("video", "graphics_preset", graphics_preset)
	_config.set_value("video", "fps_cap", fps_cap)
	_config.set_value("input", "tilt_enabled", tilt_enabled)
	_config.set_value("input", "haptics_enabled", haptics_enabled)
	_config.set_value("audio", "music", music_volume)
	_config.set_value("audio", "sfx", sfx_volume)
	_config.set_value("general", "language", language)
	_config.set_value("general", "tutorial_seen", tutorial_seen)
	_config.set_value("general", "player_name", player_name)
	_config.save(SAVE_PATH)

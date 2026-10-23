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
## Lane control.
##   TOUCH_SWIPE  (0) drag anywhere on the screen  - the original scheme
##   TOUCH_BUTTONS(1) on-screen arrows + jump/slide pads
##   GYROSCOPE    (2) tilt the phone left/right
## The player picks in Settings; the on-screen buttons also appear as a
## supplement to swipes whenever `show_buttons` is on.
enum LaneControl { TOUCH_SWIPE, TOUCH_BUTTONS, GYROSCOPE }
var lane_control: int = LaneControl.TOUCH_SWIPE
## Show the on-screen button cluster even when swiping is enabled.
var show_buttons: bool = false
## Legacy switch kept for saved files: true == gyroscope lane control.
var tilt_enabled: bool = false
## Gyroscope steering sensitivity multiplier (0.4 .. 2.5).
var gyro_sensitivity: float = 1.0
## Invert the tilt axis (for players who hold the phone the other way round).
var gyro_invert: bool = false
## Street theme: -1 = rotate through every district automatically, otherwise a
## fixed SegmentBuilder variant (0 Khartoum, 1 market, 2 corniche, 3 Bahri
## houses, 4 Mac Nimir bridge, 5 Shambat bridge, 6 old Bahri shopfronts).
var district: int = -1
## Photographic textures + shadows. OFF is the "battery saver" look.
var photo_graphics: bool = true
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


## Lane control: keeps the legacy `tilt_enabled` flag in sync so old saved
## files and any code that still reads it keep working.
func set_lane_control(value: int) -> void:
	lane_control = clampi(value, 0, 2)
	tilt_enabled = lane_control == LaneControl.GYROSCOPE
	# Picking the gyroscope implies the player wants the tilt, and picking
	# buttons means the buttons must be visible.
	if lane_control == LaneControl.TOUCH_BUTTONS:
		show_buttons = true
	_save()
	changed.emit("lane_control")
	changed.emit("tilt_enabled")


func set_show_buttons(value: bool) -> void:
	show_buttons = value
	_save()
	changed.emit("show_buttons")


func set_tilt_enabled(value: bool) -> void:
	tilt_enabled = value
	if value and lane_control == LaneControl.TOUCH_SWIPE:
		lane_control = LaneControl.GYROSCOPE
	elif not value and lane_control == LaneControl.GYROSCOPE:
		lane_control = LaneControl.TOUCH_SWIPE
	_save()
	changed.emit("tilt_enabled")
	changed.emit("lane_control")


func set_gyro_sensitivity(value: float) -> void:
	gyro_sensitivity = clampf(value, 0.4, 2.5)
	_save()
	changed.emit("gyro_sensitivity")


func set_gyro_invert(value: bool) -> void:
	gyro_invert = value
	_save()
	changed.emit("gyro_invert")


func set_district(value: int) -> void:
	district = clampi(value, -1, 6)
	_save()
	changed.emit("district")


func set_photo_graphics(value: bool) -> void:
	photo_graphics = value
	_save()
	changed.emit("photo_graphics")


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
	lane_control = clampi(int(_config.get_value("input", "lane_control", lane_control)),
			0, LaneControl.GYROSCOPE)
	show_buttons = bool(_config.get_value("input", "show_buttons", show_buttons))
	tilt_enabled = bool(_config.get_value("input", "tilt_enabled", tilt_enabled))
	# Saved files from before 1.3.0 only have the boolean tilt flag.
	if not _config.has_section_key("input", "lane_control") and tilt_enabled:
		lane_control = LaneControl.GYROSCOPE
	gyro_sensitivity = clampf(float(_config.get_value("input", "gyro_sensitivity",
			gyro_sensitivity)), 0.4, 2.5)
	gyro_invert = bool(_config.get_value("input", "gyro_invert", gyro_invert))
	# Clamp what came off disk: an out-of-range district would pick a variant
	# that does not exist and leave the street empty.
	district = clampi(int(_config.get_value("general", "district", district)), -1, 6)
	photo_graphics = bool(_config.get_value("video", "photo_graphics", photo_graphics))
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
	_config.set_value("input", "lane_control", lane_control)
	_config.set_value("input", "show_buttons", show_buttons)
	_config.set_value("input", "tilt_enabled", tilt_enabled)
	_config.set_value("input", "gyro_sensitivity", gyro_sensitivity)
	_config.set_value("input", "gyro_invert", gyro_invert)
	_config.set_value("general", "district", district)
	_config.set_value("video", "photo_graphics", photo_graphics)
	_config.set_value("input", "haptics_enabled", haptics_enabled)
	_config.set_value("audio", "music", music_volume)
	_config.set_value("audio", "sfx", sfx_volume)
	_config.set_value("general", "language", language)
	_config.set_value("general", "tutorial_seen", tutorial_seen)
	_config.set_value("general", "player_name", player_name)
	_config.save(SAVE_PATH)


## Human readable district name key (localisation suffix).
static func district_key(index: int) -> String:
	match index:
		0: return "khartoum"
		1: return "market"
		2: return "corniche"
		3: return "houses"
		4: return "mac_nimir"
		5: return "shambat"
		6: return "bahri"
		_: return "auto"


static func lane_control_key(index: int) -> String:
	match index:
		0: return "swipe"
		1: return "buttons"
		2: return "gyro"
		_: return "swipe"

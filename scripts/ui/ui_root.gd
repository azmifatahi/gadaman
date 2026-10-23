## All menus and the in-game HUD, built in code.
##
## Layout strategy for mobile:
##   * Everything is anchored, so portrait/landscape and any aspect ratio work.
##   * The HUD is a thin top bar: score on the leading edge, pause + cups on the
##     trailing edge - reachable by either thumb.
##   * Menus are centered panels with big 64 px+ touch targets.
##   * Pure Controls with MOUSE_FILTER_IGNORE cover the screen at rest, so swipes
##     always reach PlayerController.
##
## The UI owns no gameplay state: it emits intent signals (play, restart, menu)
## and renders whatever GameManager reports.
class_name UiRoot
extends CanvasLayer

signal play_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal milestone_passed(meters: int)
## Emitted by the on-screen pads. World forwards it to the player, which keeps
## the UI free of a node reference and makes the cluster testable on its own.
signal control_pressed(direction: String)

const CUP_ICON := "res://assets/art/hud_cup.png"

var _theme: Theme
var _root: Control

var _hud: Control
var _menu: Control
var _pause: Control
var _gameover: Control
var _settings: Control
var _howto: Control
var _toast: Label

# HUD
var _score_value: Label
var _distance_value: Label
var _cups_value: Label
var _combo_chip: PanelContainer
var _combo_label: Label
var _pause_button: Button
var _hud_score_caption: Label
var _hud_distance_caption: Label
## Touch button cluster (opt-in alternative to swiping).
var _buttons: Control
var _btn_left: Button
var _btn_right: Button
var _btn_jump: Button
var _btn_slide: Button

# Menu
var _best_caption: Label
var _best_menu_value: Label
var _play_button: Button
var _settings_button: Button
var _howto_button: Button
var _quit_button: Button
var _menu_footer: Label

# Pause
var _pause_title: Label
var _resume_button: Button
var _pause_restart_button: Button
var _pause_settings_button: Button
var _pause_menu_button: Button

# Game over
var _go_title: Label
var _go_best_badge: Label
var _go_stats: Dictionary = {}
var _go_restart_button: Button
var _go_menu_button: Button
var _go_captions: Dictionary = {}

# Settings
var _settings_title: Label
var _settings_captions: Dictionary = {}
var _preset_buttons: Array[Button] = []
var _fps_buttons: Array[Button] = []
var _lane_buttons: Array[Button] = []
var _gyro_slider: HSlider
var _gyro_value: Label
var _invert_button: Button
var _district_buttons: Array[Button] = []
var _photo_button: Button
var _haptics_button: Button
var _buttons_button: Button
var _language_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _music_value: Label
var _sfx_value: Label
var _device_label: Label
var _reset_button: Button
var _settings_back_button: Button

# How to play
var _howto_title: Label
var _howto_lines: Label
var _howto_ok_button: Button

var _toast_tween: Tween
var _gameover_token := 0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = UiTheme.build()
	_build_root()
	_build_hud()
	_build_touch_buttons()
	_build_menu()
	_build_pause()
	_build_gameover()
	_build_settings()
	_build_howto()
	_build_toast()

	Game.score_changed.connect(_on_score_changed)
	Game.combo_changed.connect(_on_combo_changed)
	Game.milestone_reached.connect(_on_milestone)
	Game.run_finished.connect(_on_run_finished)
	Game.state_changed.connect(_on_state_changed)
	Game.best_changed.connect(_on_best_changed)
	Settings.language_changed.connect(_on_language_changed)
	Settings.changed.connect(_on_setting_changed)

	retranslate()
	_on_state_changed(Game.state)
	_refresh_settings_widgets()


# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------
func _build_root() -> void:
	_root = Control.new()
	_root.name = "UiRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)


func _full_rect(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control


func _label(text: String, variation: String = "", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, variation: String = "", min_size: Vector2 = Vector2(0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(Audio.play_click)
	return b


func _chip(text: String, group: ButtonGroup = null) -> Button:
	var b := _button(text, "ChipButton", Vector2(96, 52))
	b.toggle_mode = true
	if group != null:
		b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _vspace(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _hsep(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _centered_panel(width: float) -> Array:
	"""Returns [overlay, content_box]. The overlay dims the game behind it."""
	var overlay := Control.new()
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	_root.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.72)
	_full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return [overlay, box]


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _build_hud() -> void:
	_hud = Control.new()
	_full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)

	var margin := MarginContainer.new()
	_full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_hud.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	# Score block (leading edge).
	var score_panel := PanelContainer.new()
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Panels must hug their content: by default an HBoxContainer stretches all
	# children to the tallest sibling, which would make a full-height column.
	score_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(score_panel)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_panel.add_child(score_box)
	_hud_score_caption = _label("", "MutedLabel")
	score_box.add_child(_hud_score_caption)
	_score_value = _label("0", "DisplayLabel", 44)
	score_box.add_child(_score_value)
	var dist_row := HBoxContainer.new()
	dist_row.add_theme_constant_override("separation", 6)
	score_box.add_child(dist_row)
	_hud_distance_caption = _label("", "MutedLabel")
	dist_row.add_child(_hud_distance_caption)
	_distance_value = _label("0 m", "HudLabel", 20)
	_distance_value.add_theme_color_override("font_color", UiTheme.GOLD)
	dist_row.add_child(_distance_value)

	# Combo chip under the score.
	_combo_chip = PanelContainer.new()
	_combo_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label = _label("", "TitleLabel", 22)
	_combo_chip.add_child(_combo_label)
	_combo_chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_combo_chip.visible = false
	row.add_child(_combo_chip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Cups + pause (trailing edge, thumb reachable).
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 10)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	var cups_panel := PanelContainer.new()
	cups_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cups_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(cups_panel)
	var cups_row := HBoxContainer.new()
	cups_row.add_theme_constant_override("separation", 8)
	cups_panel.add_child(cups_row)
	var cup_icon := TextureRect.new()
	cup_icon.texture = load(CUP_ICON)
	cup_icon.custom_minimum_size = Vector2(34, 34)
	cup_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cup_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cups_row.add_child(cup_icon)
	_cups_value = _label("0", "HudLabel", 24)
	cups_row.add_child(_cups_value)

	_pause_button = _button("II", "GhostButton", Vector2(76, 56))
	_pause_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_pause_button.pressed.connect(_on_pause_pressed)
	right.add_child(_pause_button)


# ---------------------------------------------------------------------------
# On-screen buttons (alternative to swiping)
# ---------------------------------------------------------------------------
## Four translucent pads in thumb reach: steer left/right on the leading edge,
## jump/slide on the trailing edge. They are added to the HUD layer, so they are
## hidden in menus and paused screens automatically, and they only accept touches
## that land on the button itself (everything else falls through to the swipe
## handler).
func _build_touch_buttons() -> void:
	_buttons = Control.new()
	_buttons.name = "TouchButtons"
	_full_rect(_buttons)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_buttons)

	# Anchored to the bottom corners with a 26 px safe margin. PRESET_MODE_MINSIZE
	# makes the container exactly as big as its two 96 px pads, so the pads sit in
	# thumb reach without covering the runner.
	var left_group := HBoxContainer.new()
	left_group.name = "LeftPads"
	left_group.add_theme_constant_override("separation", 14)
	left_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_child(left_group)

	var right_group := HBoxContainer.new()
	right_group.name = "RightPads"
	right_group.add_theme_constant_override("separation", 14)
	right_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_child(right_group)

	_btn_jump = _pad("JUMP", "JumpButton")
	_btn_jump.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_jump.pressed.connect(_on_jump_pressed)
	right_group.add_child(_btn_jump)

	_btn_slide = _pad("SLIDE", "SlideButton")
	_btn_slide.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_slide.pressed.connect(_on_slide_pressed)
	right_group.add_child(_btn_slide)

	_btn_left = _pad("<", "PadButton")
	_btn_left.pressed.connect(_on_left_pressed)
	left_group.add_child(_btn_left)

	_btn_right = _pad(">", "PadButton")
	_btn_right.pressed.connect(_on_right_pressed)
	left_group.add_child(_btn_right)

	# Anchoring has to happen AFTER the pads are children: PRESET_MODE_MINSIZE
	# computes the offsets from the container's minimum size, which is 0 while it
	# is still empty. Doing it early left the pads hanging off the bottom edge.
	left_group.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT,
			Control.PRESET_MODE_MINSIZE, 26)
	right_group.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 26)

	_refresh_button_visibility()


## 96 px round pad: big enough for a gloved thumb, small enough not to hide the
## runner on a 5" screen.
##
## `theme_type_variation` is the supported way to pick up a type variation: the
## old `has_stylebox(variation, "Button")` lookup asked for a stylebox *named*
## after the variation on the base Button type, which never exists, so every pad
## silently fell back to the stock grey button.
func _pad(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.theme = _theme
	b.custom_minimum_size = Vector2(96, 96)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.modulate.a = 0.88
	return b


func _refresh_button_visibility() -> void:
	if _buttons == null:
		return
	var wanted := Settings.show_buttons or Settings.lane_control == Settings.LaneControl.TOUCH_BUTTONS
	_buttons.visible = wanted and Game.state == Game.State.RUNNING
	# The arrows are spatial, not textual: the left pad must always point left,
	# whatever the UI language. Do not mirror them for RTL.
	if _btn_left != null:
		_btn_left.text = "<"
	if _btn_right != null:
		_btn_right.text = ">"
	if _btn_jump != null:
		_btn_jump.text = Loc.t("buttons.jump")
	if _btn_slide != null:
		_btn_slide.text = Loc.t("buttons.slide")


func _on_left_pressed() -> void:
	_forward_input("left")


func _on_right_pressed() -> void:
	_forward_input("right")


func _on_jump_pressed() -> void:
	_forward_input("up")


func _on_slide_pressed() -> void:
	_forward_input("down")


## Mirrors the button press to the player. Kept in one place so haptics and the
## "did the input land" check live together.
func _forward_input(direction: String) -> void:
	if Game.state != Game.State.RUNNING:
		return
	control_pressed.emit(direction)
	Settings.vibrate(12)


# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	_menu = Control.new()
	_full_rect(_menu)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu)

	var bg := TextureRect.new()
	# Photographic Khartoum sunset (generated from art_src/ by build_textures.py),
	# with the old painted art as the fallback for stripped builds.
	const PHOTO_BG := "res://assets/textures/menu_bg.jpg"
	bg.texture = load(PHOTO_BG) if ResourceLoader.exists(PHOTO_BG) \
			else load("res://assets/art/menu_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.30)
	_full_rect(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(shade)

	var margin := MarginContainer.new()
	_full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_menu.add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var flag := TextureRect.new()
	flag.texture = load("res://assets/art/icon.png")
	flag.custom_minimum_size = Vector2(104, 104)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(flag)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/art/logo.png")
	logo.custom_minimum_size = Vector2(560, 196)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(logo)

	var best_row := HBoxContainer.new()
	best_row.alignment = BoxContainer.ALIGNMENT_CENTER
	best_row.add_theme_constant_override("separation", 10)
	best_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(best_row)
	_best_caption = _label("", "MutedLabel", 20)
	best_row.add_child(_best_caption)
	_best_menu_value = _label("0", "HudLabel", 28)
	_best_menu_value.add_theme_color_override("font_color", UiTheme.GOLD)
	best_row.add_child(_best_menu_value)

	column.add_child(_vspace(10))

	_play_button = _button("", "PrimaryButton", Vector2(380, 84))
	_play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play_button.pressed.connect(func(): play_requested.emit())
	column.add_child(_play_button)

	var secondary := HBoxContainer.new()
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	secondary.add_theme_constant_override("separation", 14)
	secondary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(secondary)

	_settings_button = _button("", "GhostButton", Vector2(184, 60))
	_settings_button.pressed.connect(_open_settings)
	secondary.add_child(_settings_button)

	_howto_button = _button("", "GhostButton", Vector2(184, 60))
	_howto_button.pressed.connect(_open_howto)
	secondary.add_child(_howto_button)

	_quit_button = _button("", "GhostButton", Vector2(120, 48))
	_quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_button.visible = not OS.has_feature("mobile")
	column.add_child(_quit_button)

	_menu_footer = _label("", "MutedLabel", 14)
	_menu_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_footer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_menu_footer)


# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------
func _build_pause() -> void:
	var parts := _centered_panel(460)
	_pause = parts[0]
	var box: VBoxContainer = parts[1]

	_pause_title = _label("", "TitleLabel", 34)
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_title)

	_resume_button = _button("", "PrimaryButton", Vector2(0, 70))
	_resume_button.pressed.connect(func(): resume_requested.emit())
	box.add_child(_resume_button)

	_pause_restart_button = _button("", "GhostButton", Vector2(0, 60))
	_pause_restart_button.pressed.connect(func(): restart_requested.emit())
	box.add_child(_pause_restart_button)

	_pause_settings_button = _button("", "GhostButton", Vector2(0, 60))
	_pause_settings_button.pressed.connect(_open_settings)
	box.add_child(_pause_settings_button)

	_pause_menu_button = _button("", "GhostButton", Vector2(0, 60))
	_pause_menu_button.pressed.connect(func(): menu_requested.emit())
	box.add_child(_pause_menu_button)


# ---------------------------------------------------------------------------
# Game over
# ---------------------------------------------------------------------------
func _build_gameover() -> void:
	var parts := _centered_panel(520)
	_gameover = parts[0]
	var box: VBoxContainer = parts[1]

	_go_title = _label("", "TitleLabel", 38)
	_go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_go_title)

	_go_best_badge = _label("", "TitleLabel", 22)
	_go_best_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_best_badge.add_theme_color_override("font_color", UiTheme.GREEN.lightened(0.25))
	_go_best_badge.visible = false
	box.add_child(_go_best_badge)

	for key in ["score", "distance", "cups"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var cap := _label("", "MutedLabel", 20)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cap)
		var value := _label("0", "HudLabel", 30)
		value.custom_minimum_size = Vector2(96, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_go_captions[key] = cap
		_go_stats[key] = value

	box.add_child(_vspace(6))

	_go_restart_button = _button("", "PrimaryButton", Vector2(0, 74))
	_go_restart_button.pressed.connect(func(): restart_requested.emit())
	box.add_child(_go_restart_button)

	_go_menu_button = _button("", "GhostButton", Vector2(0, 58))
	_go_menu_button.pressed.connect(func(): menu_requested.emit())
	box.add_child(_go_menu_button)


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
func _build_settings() -> void:
	var parts := _centered_panel(700)
	_settings = parts[0]
	var box: VBoxContainer = parts[1]

	_settings_title = _label("", "TitleLabel", 32)
	_settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_settings_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	# Graphics preset.
	var graphics_caption := _label("", "MutedLabel", 17)
	content.add_child(graphics_caption)
	_settings_captions["graphics"] = graphics_caption
	var preset_group := ButtonGroup.new()
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	content.add_child(preset_row)
	for i in 4:
		var chip := _chip("", preset_group)
		chip.pressed.connect(_on_preset_pressed.bind(i))
		preset_row.add_child(chip)
		_preset_buttons.append(chip)

	# Frame rate cap.
	var fps_caption := _label("", "MutedLabel", 17)
	content.add_child(fps_caption)
	_settings_captions["fps"] = fps_caption
	var fps_group := ButtonGroup.new()
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 8)
	content.add_child(fps_row)
	for cap in [0, 30, 60, 120]:
		var chip := _chip("" if cap == 0 else str(cap), fps_group)
		chip.pressed.connect(_on_fps_pressed.bind(cap))
		fps_row.add_child(chip)
		_fps_buttons.append(chip)

	# Toggles.
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	content.add_child(toggles)
	_haptics_button = _chip("")
	_haptics_button.toggle_mode = true
	_haptics_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haptics_button.pressed.connect(_on_haptics_pressed)
	toggles.add_child(_haptics_button)

	# Independent switch: the pads can be added to the swipe scheme or removed
	# again without changing how the player steers.
	_buttons_button = _chip("")
	_buttons_button.toggle_mode = true
	_buttons_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons_button.pressed.connect(_on_show_buttons_pressed)
	toggles.add_child(_buttons_button)

	# --- controls: swipes / buttons / gyroscope -------------------------
	var control_caption := _label("", "MutedLabel", 17)
	content.add_child(control_caption)
	_settings_captions["lane"] = control_caption
	var lane_group := ButtonGroup.new()
	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 8)
	content.add_child(lane_row)
	for i in 3:
		var chip := _chip("", lane_group)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.pressed.connect(_on_lane_control_pressed.bind(i))
		lane_row.add_child(chip)
		_lane_buttons.append(chip)

	# Gyroscope sensitivity (only meaningful in gyro mode, but always editable).
	var gyro_caption := _label("", "MutedLabel", 17)
	content.add_child(gyro_caption)
	_settings_captions["gyro"] = gyro_caption
	var gyro_row := HBoxContainer.new()
	gyro_row.add_theme_constant_override("separation", 12)
	content.add_child(gyro_row)
	_gyro_slider = HSlider.new()
	_gyro_slider.min_value = 0.4
	_gyro_slider.max_value = 2.5
	_gyro_slider.step = 0.1
	_gyro_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gyro_slider.custom_minimum_size = Vector2(0, 44)
	_gyro_slider.value_changed.connect(_on_gyro_sensitivity_changed)
	gyro_row.add_child(_gyro_slider)
	_gyro_value = _label("1.0x", "MutedLabel", 17)
	_gyro_value.custom_minimum_size = Vector2(64, 0)
	_gyro_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gyro_row.add_child(_gyro_value)

	var gyro_toggles := HBoxContainer.new()
	gyro_toggles.add_theme_constant_override("separation", 10)
	content.add_child(gyro_toggles)
	_invert_button = _chip("")
	_invert_button.toggle_mode = true
	_invert_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invert_button.pressed.connect(_on_gyro_invert_pressed)
	gyro_toggles.add_child(_invert_button)
	_photo_button = _chip("")
	_photo_button.toggle_mode = true
	_photo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_button.pressed.connect(_on_photo_graphics_pressed)
	gyro_toggles.add_child(_photo_button)

	# --- street / district ----------------------------------------------
	var district_caption := _label("", "MutedLabel", 17)
	content.add_child(district_caption)
	_settings_captions["district"] = district_caption
	# Two columns: the Arabic district names ("شوارع بحري العتيقة") do not fit a
	# four-across grid on a phone and were being clipped.
	var district_grid := GridContainer.new()
	district_grid.columns = 2
	district_grid.add_theme_constant_override("h_separation", 8)
	district_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(district_grid)
	var district_group := ButtonGroup.new()
	for i in range(-1, 7):
		var chip := _chip("", district_group)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.pressed.connect(_on_district_pressed.bind(i))
		district_grid.add_child(chip)
		_district_buttons.append(chip)

	_language_button = _chip("")
	_language_button.toggle_mode = false
	_language_button.pressed.connect(_on_language_pressed)
	toggles.add_child(_language_button)

	# Volumes.
	var music_caption := _label("", "MutedLabel", 17)
	content.add_child(music_caption)
	_settings_captions["music"] = music_caption
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 12)
	content.add_child(music_row)
	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_slider.custom_minimum_size = Vector2(0, 44)
	_music_slider.value_changed.connect(_on_music_changed)
	music_row.add_child(_music_slider)
	_music_value = _label("0%", "MutedLabel", 17)
	_music_value.custom_minimum_size = Vector2(60, 0)
	_music_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(_music_value)

	var sfx_caption := _label("", "MutedLabel", 17)
	content.add_child(sfx_caption)
	_settings_captions["sfx"] = sfx_caption
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 12)
	content.add_child(sfx_row)
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.custom_minimum_size = Vector2(0, 44)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_row.add_child(_sfx_slider)
	_sfx_value = _label("0%", "MutedLabel", 17)
	_sfx_value.custom_minimum_size = Vector2(60, 0)
	_sfx_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_row.add_child(_sfx_value)

	# Device info + reset.
	_device_label = _label("", "MutedLabel", 15)
	_device_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_device_label)

	_reset_button = _button("", "GhostButton", Vector2(0, 50))
	_reset_button.pressed.connect(_on_reset_progress)
	content.add_child(_reset_button)

	# Back out.
	_settings_back_button = _button("", "PrimaryButton", Vector2(0, 64))
	_settings_back_button.pressed.connect(_close_settings)
	box.add_child(_settings_back_button)


# ---------------------------------------------------------------------------
# How to play
# ---------------------------------------------------------------------------
func _build_howto() -> void:
	var parts := _centered_panel(600)
	_howto = parts[0]
	var box: VBoxContainer = parts[1]

	_howto_title = _label("", "TitleLabel", 32)
	_howto_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_howto_title)

	_howto_lines = _label("", "HudLabel", 20)
	_howto_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_howto_lines.add_theme_constant_override("line_spacing", 10)
	box.add_child(_howto_lines)

	_howto_ok_button = _button("", "PrimaryButton", Vector2(0, 70))
	_howto_ok_button.pressed.connect(_on_howto_ok)
	box.add_child(_howto_ok_button)


func _build_toast() -> void:
	_toast = _label("", "DisplayLabel", 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_top = 132.0
	_toast.offset_bottom = 212.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)


# ---------------------------------------------------------------------------
# State / data
# ---------------------------------------------------------------------------
func _on_state_changed(state: int) -> void:
	_menu.visible = state == Game.State.MENU
	_hud.visible = state != Game.State.MENU
	_pause.visible = state == Game.State.PAUSED
	if state != Game.State.PAUSED:
		get_tree().paused = false
	# Any modal overlay belongs to the screen it was opened from: entering a run
	# (or leaving one) always dismisses them.
	_settings.visible = false
	_howto.visible = false
	_refresh_button_visibility()
	if state == Game.State.MENU:
		_gameover.visible = false
		_best_menu_value.text = _format_int(Game.best_score)
	if state == Game.State.GAME_OVER:
		_show_gameover_deferred()
	else:
		_gameover.visible = false


func _show_gameover_deferred() -> void:
	_gameover_token += 1
	var token := _gameover_token
	# Let the crash animation play before the panel covers the screen.
	await get_tree().create_timer(0.85).timeout
	if token != _gameover_token or Game.state != Game.State.GAME_OVER:
		return
	_fill_gameover(Game.last_summary())
	_gameover.visible = true
	# The crash toast would otherwise sit on top of the title.
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0


func _fill_gameover(summary: Dictionary) -> void:
	_go_stats["score"].text = _format_int(int(summary.get("score", 0)))
	_go_stats["distance"].text = "%d %s" % [int(summary.get("distance", 0)), Loc.t("hud.meters")]
	_go_stats["cups"].text = _format_int(int(summary.get("cups", 0)))
	_go_best_badge.visible = bool(summary.get("is_best", false))
	if _go_best_badge.visible:
		Audio.play_sfx("cheer", 0.0, 0.7)


func _on_score_changed(score: int, distance: float, cups: int) -> void:
	_score_value.text = _format_int(score)
	_distance_value.text = "%d %s" % [int(distance), Loc.t("hud.meters")]
	_cups_value.text = _format_int(cups)


func _on_combo_changed(combo: int, multiplier: int) -> void:
	if combo >= 3:
		_combo_chip.visible = true
		_combo_label.text = "%s ×%d" % [Loc.t("hud.combo"), multiplier]
		_combo_chip.scale = Vector2.ONE
		var tween := create_tween()
		tween.tween_property(_combo_chip, "scale", Vector2(1.08, 1.08), 0.08)
		tween.tween_property(_combo_chip, "scale", Vector2.ONE, 0.12)
	else:
		_combo_chip.visible = false


func _on_milestone(meters: int) -> void:
	show_toast(Loc.tf("toast.milestone", [meters]))
	milestone_passed.emit(meters)


func _on_run_finished(_summary: Dictionary) -> void:
	_combo_chip.visible = false


func _on_best_changed(best_score: int, _best_distance: float) -> void:
	_best_menu_value.text = _format_int(best_score)


func _on_pause_pressed() -> void:
	Audio.play_click()
	Game.toggle_pause()


func _on_quit_pressed() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# Settings behaviour
# ---------------------------------------------------------------------------
func _open_settings() -> void:
	Audio.play_click()
	_refresh_settings_widgets()
	_settings.visible = true
	_settings.move_to_front()


func _close_settings() -> void:
	Audio.play_click()
	_settings.visible = false


func _refresh_settings_widgets() -> void:
	for i in _preset_buttons.size():
		_preset_buttons[i].button_pressed = Settings.graphics_preset == i
	var caps := [0, 30, 60, 120]
	for i in _fps_buttons.size():
		_fps_buttons[i].button_pressed = Settings.fps_cap == caps[i]
	_haptics_button.button_pressed = Settings.haptics_enabled
	_buttons_button.button_pressed = Settings.show_buttons
	for i in range(mini(_lane_buttons.size(), 3)):
		_lane_buttons[i].button_pressed = Settings.lane_control == i
	_gyro_slider.set_value_no_signal(Settings.gyro_sensitivity)
	_gyro_value.text = "%.1fx" % Settings.gyro_sensitivity
	_invert_button.button_pressed = Settings.gyro_invert
	_photo_button.button_pressed = Settings.photo_graphics
	for i in range(_district_buttons.size()):
		var value := i - 1          # -1 = auto, 0..6 = districts
		_district_buttons[i].button_pressed = Settings.district == value
	_refresh_button_visibility()
	_music_slider.set_value_no_signal(Settings.music_volume)
	_sfx_slider.set_value_no_signal(Settings.sfx_volume)
	_music_value.text = "%d%%" % int(Settings.music_volume * 100.0)
	_sfx_value.text = "%d%%" % int(Settings.sfx_volume * 100.0)
	_device_label.text = "%s: %s\n%s" % [Loc.t("settings.tier"), Loc.t("settings.tier_" + Perf.tier_label()),
			Perf.summary()]
	_language_button.text = "العربية / EN"


func _on_preset_pressed(index: int) -> void:
	Audio.play_click()
	Settings.set_graphics_preset(index)
	_refresh_settings_widgets()
	show_toast(Loc.t("settings.graphics") + ": " + Loc.t("settings." + Settings.PRESETS[index]))


func _on_fps_pressed(cap: int) -> void:
	Audio.play_click()
	Settings.set_fps_cap(cap)


func _on_lane_control_pressed(index: int) -> void:
	Settings.set_lane_control(index)
	_refresh_settings_widgets()
	var key := Settings.lane_control_key(index)
	show_toast(Loc.t("settings.controls") + ": " + Loc.t("settings.lane_" + key))


func _on_gyro_sensitivity_changed(value: float) -> void:
	Settings.set_gyro_sensitivity(value)
	_gyro_value.text = "%.1fx" % value


func _on_gyro_invert_pressed() -> void:
	Settings.set_gyro_invert(not Settings.gyro_invert)
	_refresh_settings_widgets()


func _on_photo_graphics_pressed() -> void:
	Settings.set_photo_graphics(not Settings.photo_graphics)
	_refresh_settings_widgets()
	show_toast(Loc.t("settings.photo_graphics") + ": " +
			Loc.t("settings.on" if Settings.photo_graphics else "settings.off"))


func _on_district_pressed(value: int) -> void:
	Settings.set_district(value)
	_refresh_settings_widgets()
	show_toast(Loc.t("settings.district") + ": " + Loc.t("district." + Settings.district_key(value)))


## Any setting that changes rendering or input while the settings panel is open
## (e.g. from the pause menu) needs the live scene to react immediately.
func _on_setting_changed(_key: String) -> void:
	_refresh_button_visibility()


func _on_haptics_pressed() -> void:
	Audio.play_click()
	Settings.set_haptics_enabled(not Settings.haptics_enabled)
	Settings.vibrate(20)
	_refresh_settings_widgets()


## Toggle the on-screen pads. Turning them off while they are the selected
## scheme also puts swiping back, so the player is never left with no control.
func _on_show_buttons_pressed() -> void:
	Audio.play_click()
	var wanted := not Settings.show_buttons
	Settings.set_show_buttons(wanted)
	if not wanted and Settings.lane_control == Settings.LaneControl.TOUCH_BUTTONS:
		Settings.set_lane_control(Settings.LaneControl.TOUCH_SWIPE)
	_refresh_settings_widgets()
	var state_key := "settings.on" if wanted else "settings.off"
	show_toast(Loc.t("settings.show_buttons") + ": " + Loc.t(state_key))


func _on_language_pressed() -> void:
	Audio.play_click()
	Settings.set_language("en" if Settings.language == "ar" else "ar")


func _on_music_changed(value: float) -> void:
	Settings.set_music_volume(value)
	_music_value.text = "%d%%" % int(value * 100.0)


func _on_sfx_changed(value: float) -> void:
	Settings.set_sfx_volume(value)
	_sfx_value.text = "%d%%" % int(value * 100.0)


func _on_reset_progress() -> void:
	Audio.play_click()
	Game.reset_progress()
	show_toast(Loc.t("settings.reset"))
	_refresh_settings_widgets()


func open_howto() -> void:
	_open_howto()


func open_settings() -> void:
	_open_settings()


func close_overlays() -> void:
	_settings.visible = false
	_howto.visible = false
	_refresh_button_visibility()


func _open_howto() -> void:
	Audio.play_click()
	_howto.visible = true
	_howto.move_to_front()


func _on_howto_ok() -> void:
	Audio.play_click()
	Settings.set_tutorial_seen(true)
	_howto.visible = false
	play_requested.emit()


# ---------------------------------------------------------------------------
# Localisation
# ---------------------------------------------------------------------------
func _on_language_changed(_lang: String) -> void:
	retranslate()
	_refresh_settings_widgets()


func retranslate() -> void:
	_root.layout_direction = Control.LAYOUT_DIRECTION_RTL if Loc.is_rtl() else \
			Control.LAYOUT_DIRECTION_LTR

	_hud_score_caption.text = Loc.t("hud.score")
	_hud_distance_caption.text = Loc.t("hud.distance")
	_pause_button.text = "II"
	_combo_label.text = Loc.t("hud.combo")

	_best_caption.text = Loc.t("menu.best")
	_play_button.text = Loc.t("menu.play")
	_settings_button.text = Loc.t("menu.settings")
	_howto_button.text = Loc.t("menu.howto")
	_quit_button.text = Loc.t("menu.quit")
	_menu_footer.text = "GODOT 4 · GADAMAN"
	_best_menu_value.text = _format_int(Game.best_score)

	_pause_title.text = Loc.t("state.paused")
	_resume_button.text = Loc.t("state.resume")
	_pause_restart_button.text = Loc.t("state.restart")
	_pause_settings_button.text = Loc.t("settings.title")
	_pause_menu_button.text = Loc.t("state.menu")

	_go_title.text = Loc.t("state.gameover")
	_go_best_badge.text = Loc.t("state.newbest")
	_go_captions["score"].text = Loc.t("state.score")
	_go_captions["distance"].text = Loc.t("state.distance")
	_go_captions["cups"].text = Loc.t("state.cups")
	_go_restart_button.text = Loc.t("state.restart")
	_go_menu_button.text = Loc.t("state.menu")

	_settings_title.text = Loc.t("settings.title")
	_settings_captions["graphics"].text = Loc.t("settings.graphics")
	_settings_captions["fps"].text = Loc.t("settings.fps")
	_settings_captions["music"].text = Loc.t("settings.music")
	_settings_captions["sfx"].text = Loc.t("settings.sfx")
	var preset_keys := ["settings.auto", "settings.low", "settings.medium", "settings.high"]
	for i in _preset_buttons.size():
		_preset_buttons[i].text = Loc.t(preset_keys[i])
	for i in _fps_buttons.size():
		_fps_buttons[i].text = Loc.t("settings.fps_auto") if i == 0 else str([0, 30, 60, 120][i])
	_haptics_button.text = Loc.t("settings.haptics")
	_buttons_button.text = Loc.t("settings.show_buttons")
	_settings_captions["lane"].text = Loc.t("settings.controls")
	for i in range(_lane_buttons.size()):
		_lane_buttons[i].text = Loc.t("settings.lane_" + Settings.lane_control_key(i))
	_settings_captions["gyro"].text = Loc.t("settings.gyro")
	_invert_button.text = Loc.t("settings.gyro_invert")
	_photo_button.text = Loc.t("settings.photo_graphics")
	_settings_captions["district"].text = Loc.t("settings.district")
	for i in range(_district_buttons.size()):
		_district_buttons[i].text = Loc.t("district." + Settings.district_key(i - 1))
	_refresh_button_visibility()
	_reset_button.text = Loc.t("settings.reset")
	_settings_back_button.text = Loc.t("settings.back")

	_howto_title.text = Loc.t("howto.title")
	# The help card must describe the scheme the player actually picked, or it
	# sends them swiping when the pads are on.
	var lane_key := "howto.swipe"
	match Settings.lane_control:
		Settings.LaneControl.TOUCH_BUTTONS:
			lane_key = "howto.lane_buttons"
		Settings.LaneControl.GYROSCOPE:
			lane_key = "howto.lane_gyro"
	var lines := PackedStringArray([Loc.t(lane_key)])
	if Settings.show_buttons and Settings.lane_control != Settings.LaneControl.TOUCH_BUTTONS:
		lines.append(Loc.t("howto.buttons_extra"))
	lines.append(Loc.t("howto.up"))
	lines.append(Loc.t("howto.down"))
	lines.append(Loc.t("howto.collect"))
	_howto_lines.text = "• " + "\n• ".join(lines)
	_howto_ok_button.text = Loc.t("howto.start")


# ---------------------------------------------------------------------------
# System input (this layer runs with PROCESS_MODE_ALWAYS, so it still works
# while the game tree is paused)
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if Game.state == Game.State.RUNNING or Game.state == Game.State.PAUSED:
			Game.toggle_pause()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if Game.state == Game.State.RUNNING:
			Game.toggle_pause()
		elif Game.state == Game.State.PAUSED:
			menu_requested.emit()
		elif Game.state == Game.State.GAME_OVER:
			menu_requested.emit()
		else:
			get_tree().quit()


# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
func show_toast(text: String, hold: float = 0.9) -> void:
	if _gameover != null and _gameover.visible:
		return
	_toast.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.92, 0.92)
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.12)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35).set_delay(hold)


func show_crash_reason(reason_key: String) -> void:
	show_toast(Loc.t("toast.crash") + " " + Loc.t(reason_key), 0.8)


func refresh_best() -> void:
	_best_menu_value.text = _format_int(Game.best_score)


func _format_int(value: int) -> String:
	# Thousands separator without allocating a locale-aware formatter.
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

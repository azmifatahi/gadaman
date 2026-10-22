## Code-built UI theme.
##
## Built at runtime instead of shipping a .tres theme so the palette lives in one
## readable place and the fonts are resolved through Godot's importer (Cairo,
## SIL Open Font License - excellent Arabic shaping, included in assets/fonts).
class_name UiTheme
extends RefCounted

const INK := Color("#0b0d10")
const PANEL_BG := Color(0.043, 0.051, 0.059, 0.96)
const PANEL_BG_SOLID := Color(0.043, 0.051, 0.059, 1.0)
const GOLD := Color("#f2b705")
const RED := Color("#d21034")
const GREEN := Color("#009a00")
const TEXT := Color("#f4efe4")
const MUTED := Color(0.80, 0.77, 0.70, 0.78)

const FONT_BODY := "res://assets/fonts/Cairo-Medium.ttf"
const FONT_BOLD := "res://assets/fonts/Cairo-Bold.ttf"
const FONT_DISPLAY := "res://assets/fonts/Cairo-Black.ttf"


static func build() -> Theme:
	var theme := Theme.new()
	var body: Font = load(FONT_BODY)
	var bold: Font = load(FONT_BOLD)
	theme.default_font = body
	theme.default_font_size = 22

	theme.set_font("Label", "Label", body)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("shadow_outline_size", "Label", 2)

	theme.set_stylebox("panel", "PanelContainer", _panel(PANEL_BG, GOLD * Color(1, 1, 1, 0.35), 20, 2))
	theme.set_stylebox("panel", "Panel", _panel(PANEL_BG, GOLD * Color(1, 1, 1, 0.25), 20, 2))

	# --- default button -----------------------------------------------------
	theme.set_stylebox("normal", "Button", _panel(Color(0.10, 0.11, 0.13, 0.92),
			Color(1, 1, 1, 0.18), 16, 2))
	theme.set_stylebox("hover", "Button", _panel(Color(0.15, 0.16, 0.19, 0.96), GOLD, 16, 2))
	theme.set_stylebox("pressed", "Button", _panel(GOLD, GOLD, 16, 2))
	theme.set_stylebox("disabled", "Button", _panel(Color(0.08, 0.08, 0.09, 0.7),
			Color(1, 1, 1, 0.08), 16, 2))
	theme.set_stylebox("focus", "Button", _panel(Color(0, 0, 0, 0), GOLD * Color(1, 1, 1, 0.5), 16, 2))
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	theme.set_font("font", "Button", bold)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_constant("outline_size", "Button", 0)
	theme.set_constant("h_separation", "Button", 10)

	# --- primary (flag red) -------------------------------------------------
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _panel(RED, RED.lightened(0.35), 18, 2))
	theme.set_stylebox("hover", "PrimaryButton", _panel(RED.lightened(0.12), GOLD, 18, 3))
	theme.set_stylebox("pressed", "PrimaryButton", _panel(RED.darkened(0.2), GOLD, 18, 3))
	theme.set_stylebox("focus", "PrimaryButton", _panel(Color(0, 0, 0, 0), GOLD, 18, 3))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(state, "PrimaryButton", Color.WHITE)
	theme.set_font("font", "PrimaryButton", bold)
	theme.set_font_size("font_size", "PrimaryButton", 28)

	# --- ghost / secondary --------------------------------------------------
	theme.set_type_variation("GhostButton", "Button")
	theme.set_stylebox("normal", "GhostButton", _panel(Color(1, 1, 1, 0.05),
			Color(1, 1, 1, 0.22), 14, 1))
	theme.set_stylebox("hover", "GhostButton", _panel(Color(1, 1, 1, 0.12), GOLD, 14, 1))
	theme.set_stylebox("pressed", "GhostButton", _panel(GOLD * Color(1, 1, 1, 0.9), GOLD, 14, 1))
	theme.set_color("font_pressed_color", "GhostButton", INK)
	theme.set_font_size("font_size", "GhostButton", 20)

	# --- toggle chips (settings) -------------------------------------------
	theme.set_type_variation("ChipButton", "Button")
	theme.set_stylebox("normal", "ChipButton", _panel(Color(1, 1, 1, 0.06),
			Color(1, 1, 1, 0.16), 12, 1))
	theme.set_stylebox("hover", "ChipButton", _panel(Color(1, 1, 1, 0.12), GOLD, 12, 1))
	theme.set_stylebox("pressed", "ChipButton", _panel(GOLD, GOLD, 12, 1))
	theme.set_stylebox("focus", "ChipButton", _panel(Color(0, 0, 0, 0), GOLD, 12, 1))
	theme.set_color("font_color", "ChipButton", TEXT)
	theme.set_color("font_pressed_color", "ChipButton", INK)
	theme.set_color("font_hover_color", "ChipButton", GOLD)
	theme.set_font_size("font_size", "ChipButton", 18)
	theme.set_constant("h_separation", "ChipButton", 6)

	# --- labels variations --------------------------------------------------
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", bold)
	theme.set_font_size("font_size", "TitleLabel", 40)
	theme.set_color("font_color", "TitleLabel", TEXT)

	theme.set_type_variation("DisplayLabel", "Label")
	theme.set_font("font", "DisplayLabel", load(FONT_DISPLAY))
	theme.set_font_size("font_size", "DisplayLabel", 46)
	theme.set_color("font_color", "DisplayLabel", GOLD)

	theme.set_type_variation("MutedLabel", "Label")
	theme.set_font_size("font_size", "MutedLabel", 16)
	theme.set_color("font_color", "MutedLabel", MUTED)

	theme.set_type_variation("HudLabel", "Label")
	theme.set_font("font", "HudLabel", bold)
	theme.set_font_size("font_size", "HudLabel", 30)
	theme.set_color("font_color", "HudLabel", TEXT)

	# --- misc controls ------------------------------------------------------
	theme.set_stylebox("slider", "HSlider", _panel(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.1), 8, 0))
	theme.set_stylebox("grabber_area", "HSlider", _panel(GOLD, GOLD, 8, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _panel(GOLD.lightened(0.2), GOLD, 8, 0))
	theme.set_stylebox("background", "ProgressBar", _panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 8, 0))
	theme.set_stylebox("fill", "ProgressBar", _panel(GOLD, GOLD, 8, 0))
	theme.set_color("font_color", "ProgressBar", INK)

	theme.set_stylebox("panel", "PopupPanel", _panel(PANEL_BG_SOLID, GOLD, 18, 2))
	theme.set_stylebox("panel", "ScrollContainer", _panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	return theme


static func _panel(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	return sb

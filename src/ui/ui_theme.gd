# Programmatic UI Styling and Cyber/Tech-War Theme Generator
class_name UITheme
extends RefCounted

const COLOR_BG_DARK: Color = Color(0.05, 0.07, 0.11, 1.0)
const COLOR_PANEL_BG: Color = Color(0.09, 0.13, 0.20, 0.95)
const COLOR_PANEL_BORDER: Color = Color(0.16, 0.38, 0.56, 1.0)

const COLOR_PRIMARY: Color = Color(0.12, 0.32, 0.52, 1.0)
const COLOR_PRIMARY_HOVER: Color = Color(0.18, 0.45, 0.72, 1.0)
const COLOR_PRIMARY_PRESSED: Color = Color(0.08, 0.22, 0.36, 1.0)

const COLOR_ACCENT_CYAN: Color = Color(0.18, 0.82, 1.0, 1.0)
const COLOR_SUCCESS_GREEN: Color = Color(0.25, 0.88, 0.45, 1.0)
const COLOR_WARNING_GOLD: Color = Color(1.0, 0.8, 0.2, 1.0)
const COLOR_DANGER_RED: Color = Color(0.95, 0.3, 0.35, 1.0)

const COLOR_TEXT_MAIN: Color = Color(0.94, 0.96, 0.98, 1.0)
const COLOR_TEXT_MUTED: Color = Color(0.60, 0.68, 0.76, 1.0)

static func create_panel_style(
	bg_color: Color = COLOR_PANEL_BG,
	border_color: Color = COLOR_PANEL_BORDER,
	corner_radius: int = 8,
	border_width: int = 1,
	padding: int = 12
) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	return sb

static func style_button(
	btn: Button,
	base_color: Color = COLOR_PRIMARY,
	accent_border: Color = COLOR_ACCENT_CYAN,
	min_height: int = 42,
	font_size: int = 16
) -> void:
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, min_height)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT_CYAN)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	# Normal
	var sb_normal = create_panel_style(base_color, accent_border.darkened(0.4), 6, 1, 8)
	btn.add_theme_stylebox_override("normal", sb_normal)
	
	# Hover
	var sb_hover = create_panel_style(base_color.lightened(0.2), accent_border, 6, 2, 8)
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	# Pressed
	var sb_pressed = create_panel_style(base_color.darkened(0.2), accent_border, 6, 2, 8)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	
	# Disabled
	var sb_disabled = create_panel_style(base_color.darkened(0.5), Color(0.2, 0.25, 0.3), 6, 1, 8)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	
	# Focus
	var sb_focus = create_panel_style(base_color, accent_border, 6, 2, 8)
	btn.add_theme_stylebox_override("focus", sb_focus)

static func style_line_edit(
	edit: LineEdit,
	font_size: int = 15,
	bg_color: Color = Color(0.04, 0.06, 0.09, 0.95),
	border_color: Color = Color(0.2, 0.35, 0.5)
) -> void:
	edit.custom_minimum_size = Vector2(edit.custom_minimum_size.x, 38)
	edit.add_theme_font_size_override("font_size", font_size)
	edit.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	edit.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED.darkened(0.2))
	
	var sb_normal = create_panel_style(bg_color, border_color, 6, 1, 8)
	var sb_focus = create_panel_style(bg_color, COLOR_ACCENT_CYAN, 6, 2, 8)
	
	edit.add_theme_stylebox_override("normal", sb_normal)
	edit.add_theme_stylebox_override("focus", sb_focus)

static func create_badge(text: String, bg_color: Color, text_color: Color = Color.WHITE) -> PanelContainer:
	var container = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	container.add_theme_stylebox_override("panel", sb)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", text_color)
	container.add_child(lbl)
	return container

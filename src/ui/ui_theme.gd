# Overwatch / Factory of War Futuristic Cyber Theme Generator
class_name UITheme
extends RefCounted

# Color Palette
const COLOR_BG_DARK: Color = Color(0.03, 0.05, 0.09, 1.0)
const COLOR_PANEL_BG: Color = Color(0.06, 0.09, 0.15, 0.90)
const COLOR_PANEL_BORDER: Color = Color(0.12, 0.28, 0.44, 0.8)

const COLOR_MODAL_BG: Color = Color(0.04, 0.07, 0.12, 0.96)
const COLOR_MODAL_HEADER_BG: Color = Color(0.82, 0.88, 0.94, 1.0)
const COLOR_MODAL_HEADER_TEXT: Color = Color(0.05, 0.08, 0.12, 1.0)

const COLOR_ACCENT_CYAN: Color = Color(0.0, 0.90, 1.0, 1.0)
const COLOR_ACCENT_ORANGE: Color = Color(1.0, 0.60, 0.10, 1.0)
const COLOR_ACCENT_RED: Color = Color(1.0, 0.25, 0.25, 1.0)
const COLOR_SUCCESS_GREEN: Color = Color(0.20, 0.90, 0.45, 1.0)
const COLOR_WARNING_GOLD: Color = Color(1.0, 0.82, 0.20, 1.0)

const COLOR_PRIMARY: Color = Color(0.08, 0.18, 0.30, 0.9)
const COLOR_PRIMARY_HOVER: Color = Color(0.14, 0.28, 0.46, 0.95)
const COLOR_PRIMARY_PRESSED: Color = Color(0.05, 0.12, 0.22, 0.95)

const COLOR_TEXT_MAIN: Color = Color(0.96, 0.98, 1.0, 1.0)
const COLOR_TEXT_MUTED: Color = Color(0.55, 0.65, 0.78, 1.0)

static func create_panel_style(
	bg_color: Color = COLOR_PANEL_BG,
	border_color: Color = COLOR_PANEL_BORDER,
	corner_radius: int = 4,
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
	base_color: Color = Color(0.08, 0.18, 0.30, 0.9),
	accent_border: Color = COLOR_ACCENT_CYAN,
	min_height: int = 42,
	font_size: int = 16
) -> void:
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, min_height)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT_CYAN)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED.darkened(0.4))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var sb_normal = create_panel_style(base_color, accent_border.darkened(0.5), 3, 1, 8)
	var sb_hover = create_panel_style(base_color.lightened(0.2), accent_border, 3, 2, 8)
	var sb_pressed = create_panel_style(base_color.darkened(0.2), COLOR_ACCENT_CYAN, 3, 2, 8)
	var sb_disabled = create_panel_style(base_color.darkened(0.6), Color(0.15, 0.20, 0.25), 3, 1, 8)
	
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_stylebox_override("focus", sb_hover)

static func style_menu_action_button(btn: Button, font_size: int = 24) -> void:
	btn.custom_minimum_size = Vector2(280, 48)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT_CYAN)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT_ORANGE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var sb_empty = StyleBoxEmpty.new()
	sb_empty.content_margin_left = 8
	btn.add_theme_stylebox_override("normal", sb_empty)
	btn.add_theme_stylebox_override("hover", sb_empty)
	btn.add_theme_stylebox_override("pressed", sb_empty)
	btn.add_theme_stylebox_override("focus", sb_empty)

static func style_line_edit(
	edit: LineEdit,
	font_size: int = 15,
	bg_color: Color = Color(0.04, 0.07, 0.12, 0.95),
	border_color: Color = Color(0.16, 0.32, 0.48)
) -> void:
	edit.custom_minimum_size = Vector2(edit.custom_minimum_size.x, 38)
	edit.add_theme_font_size_override("font_size", font_size)
	edit.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	edit.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED.darkened(0.3))
	
	var sb_normal = create_panel_style(bg_color, border_color, 4, 1, 10)
	var sb_focus = create_panel_style(bg_color, COLOR_ACCENT_CYAN, 4, 2, 10)
	
	edit.add_theme_stylebox_override("normal", sb_normal)
	edit.add_theme_stylebox_override("focus", sb_focus)

static func create_badge(text: String, bg_color: Color, text_color: Color = Color.WHITE) -> PanelContainer:
	var container = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(3)
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

static func load_texture_safe(res_path: String) -> Texture2D:
	# 1. Try standard ResourceLoader
	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Texture2D:
			return res
			
	# 2. Try Image.load_from_file with global path
	var global_path = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global_path):
		var img = Image.load_from_file(global_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
			
		# 3. Binary PNG buffer decode fallback
		var file = FileAccess.open(global_path, FileAccess.READ)
		if file != null:
			var buffer = file.get_buffer(file.get_length())
			var raw_img = Image.new()
			var err = raw_img.load_png_from_buffer(buffer)
			if err == OK and not raw_img.is_empty():
				return ImageTexture.create_from_image(raw_img)
				
	# 4. Try direct res:// path with Image.load_from_file
	var res_img = Image.load_from_file(res_path)
	if res_img != null and not res_img.is_empty():
		return ImageTexture.create_from_image(res_img)
		
	return null

# Overwatch / Factory of War Main Menu View with Background Slides & Clean Dynamic Profile Layout
class_name MenuView
extends Control

signal host_requested(port: int, player_name: String, is_public: bool, host_ip: String)
signal join_by_code_requested(code: String, player_name: String)
signal join_direct_requested(ip: String, port: int, player_name: String)
signal open_settings_requested()

var network_manager: NetworkManager
var settings_manager: SettingsManager

# Background Animation
var banner_rect1: TextureRect
var banner_rect2: TextureRect
var banner_timer: float = 0.0
var active_banner_idx: int = 0
var banner_textures: Array[Texture2D] = []

# UI References
var profile_name_lbl: Label
var status_lbl: Label

func _init(p_net: NetworkManager = null, p_settings: SettingsManager = null) -> void:
	network_manager = p_net
	settings_manager = p_settings
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_load_banner_textures()
	_build_ui()
	_update_profile_display()

func _process(delta: float) -> void:
	if banner_textures.size() >= 2:
		banner_timer += delta
		if banner_timer >= 6.0:
			banner_timer = 0.0
			_crossfade_banner()

func _load_banner_textures() -> void:
	banner_textures.clear()
	var tex1 = UITheme.load_texture_safe("res://public/ui/menu_banner.png")
	var tex2 = UITheme.load_texture_safe("res://public/ui/menu_banner_cyber.png")
	
	if tex1 != null:
		banner_textures.append(tex1)
	if tex2 != null:
		banner_textures.append(tex2)

func _build_ui() -> void:
	# Fallback dark background
	var bg_fallback = ColorRect.new()
	bg_fallback.color = Color(0.02, 0.04, 0.08, 1.0)
	bg_fallback.set_anchors_preset(PRESET_FULL_RECT)
	bg_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_fallback)
	
	# 1. Background Layers for smooth crossfade
	banner_rect1 = TextureRect.new()
	banner_rect1.set_anchors_preset(PRESET_FULL_RECT)
	banner_rect1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner_rect1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not banner_textures.is_empty():
		banner_rect1.texture = banner_textures[0]
	add_child(banner_rect1)
	
	banner_rect2 = TextureRect.new()
	banner_rect2.set_anchors_preset(PRESET_FULL_RECT)
	banner_rect2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner_rect2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_rect2.modulate = Color(1, 1, 1, 0)
	if banner_textures.size() >= 2:
		banner_rect2.texture = banner_textures[1]
	add_child(banner_rect2)
	
	# Vignette overlay
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.color = Color(0.01, 0.03, 0.07, 0.35)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	
	# 2. Main Layout Container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	margin.add_child(main_vbox)
	
	# --- TOP ROW (Title on Left, Dynamic Profile on Right) ---
	var top_hbox = HBoxContainer.new()
	top_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(top_hbox)
	
	# Top Left: Title
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 4)
	top_hbox.add_child(title_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "FACTORY OF WAR"
	title_lbl.add_theme_font_size_override("font_size", 46)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_vbox.add_child(title_lbl)
	
	var subtitle_lbl = Label.new()
	subtitle_lbl.text = "Hackaton 2026 #1 · do 4 graczy"
	subtitle_lbl.add_theme_font_size_override("font_size", 16)
	subtitle_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	title_vbox.add_child(subtitle_lbl)
	
	# Top Right: Dynamic Profile Badge (Premium Overwatch-style card)
	var profile_panel = PanelContainer.new()
	profile_panel.custom_minimum_size = Vector2(320, 68)
	var profile_sb = StyleBoxFlat.new()
	profile_sb.bg_color = Color(0.04, 0.07, 0.14, 0.95)
	profile_sb.border_color = UITheme.COLOR_ACCENT_ORANGE
	profile_sb.border_width_bottom = 3
	profile_sb.border_width_right = 4
	profile_sb.set_corner_radius_all(6)
	profile_sb.content_margin_left = 20
	profile_sb.content_margin_right = 20
	profile_sb.content_margin_top = 10
	profile_sb.content_margin_bottom = 10
	profile_panel.add_theme_stylebox_override("panel", profile_sb)
	top_hbox.add_child(profile_panel)
	
	var prof_hbox = HBoxContainer.new()
	prof_hbox.add_theme_constant_override("separation", 14)
	prof_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	profile_panel.add_child(prof_hbox)
	
	# Avatar circle
	var avatar_circle = ColorRect.new()
	avatar_circle.custom_minimum_size = Vector2(44, 44)
	avatar_circle.color = UITheme.COLOR_ACCENT_CYAN.darkened(0.3)
	prof_hbox.add_child(avatar_circle)
	
	var avatar_letter = Label.new()
	avatar_letter.text = "P"
	avatar_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_letter.add_theme_font_size_override("font_size", 22)
	avatar_letter.add_theme_color_override("font_color", Color.WHITE)
	avatar_letter.set_anchors_preset(PRESET_FULL_RECT)
	avatar_circle.add_child(avatar_letter)
	
	var prof_info_vbox = VBoxContainer.new()
	prof_info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_info_vbox.add_theme_constant_override("separation", 2)
	prof_hbox.add_child(prof_info_vbox)
	
	profile_name_lbl = Label.new()
	profile_name_lbl.text = "PRACOWNIK"
	profile_name_lbl.add_theme_font_size_override("font_size", 20)
	profile_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	profile_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	profile_name_lbl.clip_text = true
	prof_info_vbox.add_child(profile_name_lbl)
	
	var prof_rank = Label.new()
	prof_rank.text = "GRACZ · ONLINE"
	prof_rank.add_theme_font_size_override("font_size", 13)
	prof_rank.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	prof_info_vbox.add_child(prof_rank)
	
	# Edit pencil button
	var edit_btn = Button.new()
	edit_btn.text = "✏️"
	edit_btn.custom_minimum_size = Vector2(44, 44)
	edit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var edit_sb = StyleBoxFlat.new()
	edit_sb.bg_color = Color(0.08, 0.14, 0.24, 0.9)
	edit_sb.set_corner_radius_all(6)
	edit_sb.content_margin_left = 6
	edit_sb.content_margin_right = 6
	edit_btn.add_theme_stylebox_override("normal", edit_sb)
	var edit_sb_h = StyleBoxFlat.new()
	edit_sb_h.bg_color = UITheme.COLOR_ACCENT_ORANGE.darkened(0.3)
	edit_sb_h.set_corner_radius_all(6)
	edit_sb_h.content_margin_left = 6
	edit_sb_h.content_margin_right = 6
	edit_btn.add_theme_stylebox_override("hover", edit_sb_h)
	edit_btn.add_theme_stylebox_override("pressed", edit_sb_h)
	edit_btn.add_theme_font_size_override("font_size", 20)
	edit_btn.pressed.connect(_on_edit_nickname_pressed)
	prof_hbox.add_child(edit_btn)
	
	# --- SPACER BETWEEN TITLE AND MENU BUTTONS ---
	var spacer_top = Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 80)
	main_vbox.add_child(spacer_top)
	
	# --- ACTION MENU BUTTONS ---
	var menu_vbox = VBoxContainer.new()
	menu_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_vbox.add_theme_constant_override("separation", 22)
	main_vbox.add_child(menu_vbox)
	
	# 1. STWÓRZ GRĘ
	var btn_host = Button.new()
	btn_host.text = "STWÓRZ GRĘ"
	UITheme.style_menu_action_button(btn_host, 34)
	btn_host.pressed.connect(_on_create_game_pressed)
	menu_vbox.add_child(btn_host)
	
	# 2. DOŁĄCZ DO GRY
	var btn_join = Button.new()
	btn_join.text = "DOŁĄCZ DO GRY"
	UITheme.style_menu_action_button(btn_join, 34)
	btn_join.pressed.connect(_on_join_game_pressed)
	menu_vbox.add_child(btn_join)
	
	# 3. USTAWIENIA
	var btn_settings = Button.new()
	btn_settings.text = "USTAWIENIA"
	UITheme.style_menu_action_button(btn_settings, 28)
	btn_settings.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	btn_settings.pressed.connect(_on_settings_pressed)
	menu_vbox.add_child(btn_settings)
	
	# 4. WYJDŹ Z GRY
	var btn_quit = Button.new()
	btn_quit.text = "WYJDŹ Z GRY"
	UITheme.style_menu_action_button(btn_quit, 28)
	btn_quit.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
	btn_quit.add_theme_color_override("font_hover_color", UITheme.COLOR_ACCENT_RED.lightened(0.3))
	btn_quit.pressed.connect(func(): get_tree().quit())
	menu_vbox.add_child(btn_quit)
	
	# Status message
	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.add_theme_font_size_override("font_size", 16)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	menu_vbox.add_child(status_lbl)
	
	# --- EXPANDING SPACER PUSHING WATERMARK TO BOTTOM ---
	var spacer_bottom = Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer_bottom)
	
	# --- BOTTOM WATERMARK ---
	var bottom_lbl = Label.new()
	bottom_lbl.text = "v0.1 · RTS multiplayer"
	bottom_lbl.add_theme_font_size_override("font_size", 14)
	bottom_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED.darkened(0.2))
	main_vbox.add_child(bottom_lbl)

func _crossfade_banner() -> void:
	if banner_textures.size() < 2: return
	
	var tween = create_tween()
	if active_banner_idx == 0:
		active_banner_idx = 1
		tween.tween_property(banner_rect2, "modulate:a", 1.0, 1.2)
	else:
		active_banner_idx = 0
		tween.tween_property(banner_rect2, "modulate:a", 0.0, 1.2)

func _update_profile_display() -> void:
	if settings_manager != null and profile_name_lbl != null:
		profile_name_lbl.text = settings_manager.player_name.to_upper()

func set_status(msg: String, is_error: bool = false) -> void:
	if status_lbl != null:
		status_lbl.text = msg
		if is_error:
			status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
		else:
			status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)

func _on_create_game_pressed() -> void:
	var p_name = settings_manager.player_name if settings_manager else "MatthewMill"
	var port = settings_manager.custom_port if settings_manager else GameState.DEFAULT_PORT
	var host_ip = settings_manager.custom_host_ip if settings_manager else ""
	host_requested.emit(port, p_name, true, host_ip)

func _on_join_game_pressed() -> void:
	var join_modal = JoinModal.new(network_manager, settings_manager)
	join_modal.join_by_code_requested.connect(func(code, p_name): join_by_code_requested.emit(code, p_name))
	join_modal.join_direct_requested.connect(func(ip, port, p_name): join_direct_requested.emit(ip, port, p_name))
	add_child(join_modal)

func _on_settings_pressed() -> void:
	var modal = SettingsModal.new(settings_manager, network_manager, false)
	modal.settings_closed.connect(func(_saved):
		_update_profile_display()
	)
	add_child(modal)

func _on_edit_nickname_pressed() -> void:
	# Dedicated premium nickname edit popup
	var overlay = Control.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)
	
	# Dim backdrop (click to close)
	var dim = ColorRect.new()
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	overlay.add_child(dim)
	
	# Center card
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 280)
	var card_sb = StyleBoxFlat.new()
	card_sb.bg_color = Color(0.04, 0.06, 0.12, 0.98)
	card_sb.border_color = UITheme.COLOR_ACCENT_ORANGE
	card_sb.border_width_top = 4
	card_sb.set_corner_radius_all(10)
	card_sb.content_margin_left = 36
	card_sb.content_margin_right = 36
	card_sb.content_margin_top = 28
	card_sb.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 18)
	card.add_child(cvbox)
	
	# Header
	var header = Label.new()
	header.text = "ZMIEŃ NICK GRACZA"
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvbox.add_child(header)
	
	# Current nick display
	var current_row = HBoxContainer.new()
	current_row.alignment = BoxContainer.ALIGNMENT_CENTER
	current_row.add_theme_constant_override("separation", 10)
	cvbox.add_child(current_row)
	
	var curr_label = Label.new()
	curr_label.text = "Aktualny nick:"
	curr_label.add_theme_font_size_override("font_size", 16)
	curr_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	current_row.add_child(curr_label)
	
	var curr_val = Label.new()
	curr_val.text = settings_manager.player_name if settings_manager else "Pracownik"
	curr_val.add_theme_font_size_override("font_size", 18)
	curr_val.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	current_row.add_child(curr_val)
	
	# Input field
	var input = LineEdit.new()
	input.placeholder_text = "Wpisz nowy nick..."
	input.text = settings_manager.player_name if settings_manager else ""
	input.max_length = 32
	input.select_all_on_focus = true
	input.custom_minimum_size = Vector2(0, 48)
	UITheme.style_line_edit(input, 18)
	cvbox.add_child(input)
	
	# Buttons row
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	cvbox.add_child(btn_row)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "ANULUJ"
	btn_cancel.custom_minimum_size = Vector2(140, 46)
	UITheme.style_button(btn_cancel, Color(0.12, 0.16, 0.24), UITheme.COLOR_TEXT_MUTED, 46, 16)
	btn_cancel.pressed.connect(func(): overlay.queue_free())
	btn_row.add_child(btn_cancel)
	
	var btn_save = Button.new()
	btn_save.text = "ZAPISZ"
	btn_save.custom_minimum_size = Vector2(140, 46)
	UITheme.style_button(btn_save, Color(0.14, 0.32, 0.18), UITheme.COLOR_SUCCESS_GREEN, 46, 16)
	btn_save.pressed.connect(func():
		var new_name = input.text.strip_edges()
		if new_name.is_empty():
			return
		if settings_manager:
			settings_manager.player_name = new_name
			settings_manager.save_settings()
		_update_profile_display()
		overlay.queue_free()
	)
	btn_row.add_child(btn_save)
	
	# Enter to confirm
	input.text_submitted.connect(func(_t):
		btn_save.pressed.emit()
	)
	
	# Auto-focus
	input.call_deferred("grab_focus")

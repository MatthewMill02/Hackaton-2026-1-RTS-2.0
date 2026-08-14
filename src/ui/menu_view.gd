# Overwatch / Factory of War Main Menu View with Background Slides & Clean Layout
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
	print("[MenuView] Loaded background banner textures: ", banner_textures.size())

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
	
	# 2. Main Layout Container (Single MarginContainer -> Single VBoxContainer)
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_right", 70)
	margin.add_theme_constant_override("margin_top", 45)
	margin.add_theme_constant_override("margin_bottom", 35)
	add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	margin.add_child(main_vbox)
	
	# --- TOP ROW (Title on Left, Profile on Right) ---
	var top_hbox = HBoxContainer.new()
	top_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(top_hbox)
	
	# Top Left: Title
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	top_hbox.add_child(title_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "FACTORY OF WAR"
	title_lbl.add_theme_font_size_override("font_size", 44)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_vbox.add_child(title_lbl)
	
	var subtitle_lbl = Label.new()
	subtitle_lbl.text = "Hackaton 2026 #1 · do 4 graczy"
	subtitle_lbl.add_theme_font_size_override("font_size", 13)
	subtitle_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	title_vbox.add_child(subtitle_lbl)
	
	# Top Right: Profile Badge
	var profile_btn = Button.new()
	var profile_sb = StyleBoxFlat.new()
	profile_sb.bg_color = Color(0.05, 0.08, 0.15, 0.92)
	profile_sb.border_color = UITheme.COLOR_ACCENT_ORANGE
	profile_sb.border_width_right = 5
	profile_sb.set_corner_radius_all(2)
	profile_sb.content_margin_left = 18
	profile_sb.content_margin_right = 18
	profile_sb.content_margin_top = 8
	profile_sb.content_margin_bottom = 8
	profile_btn.add_theme_stylebox_override("normal", profile_sb)
	profile_btn.add_theme_stylebox_override("hover", profile_sb)
	profile_btn.add_theme_stylebox_override("pressed", profile_sb)
	profile_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	profile_btn.pressed.connect(_on_settings_pressed)
	top_hbox.add_child(profile_btn)
	
	var prof_vbox = VBoxContainer.new()
	prof_vbox.add_theme_constant_override("separation", 2)
	profile_btn.add_child(prof_vbox)
	
	profile_name_lbl = Label.new()
	profile_name_lbl.text = "MATTHEWMILL"
	profile_name_lbl.add_theme_font_size_override("font_size", 15)
	profile_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	prof_vbox.add_child(profile_name_lbl)
	
	var prof_hint = Label.new()
	prof_hint.text = "KLIKNIJ ABY ZMIENIĆ"
	prof_hint.add_theme_font_size_override("font_size", 10)
	prof_hint.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_ORANGE)
	prof_vbox.add_child(prof_hint)
	
	# --- SPACER BETWEEN TITLE AND MENU BUTTONS ---
	var spacer_top = Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 70)
	main_vbox.add_child(spacer_top)
	
	# --- ACTION MENU BUTTONS ---
	var menu_vbox = VBoxContainer.new()
	menu_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_vbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(menu_vbox)
	
	# 1. STWÓRZ GRĘ
	var btn_host = Button.new()
	btn_host.text = "STWÓRZ GRĘ"
	UITheme.style_menu_action_button(btn_host, 32)
	btn_host.pressed.connect(_on_create_game_pressed)
	menu_vbox.add_child(btn_host)
	
	# 2. DOŁĄCZ DO GRY
	var btn_join = Button.new()
	btn_join.text = "DOŁĄCZ DO GRY"
	UITheme.style_menu_action_button(btn_join, 32)
	btn_join.pressed.connect(_on_join_game_pressed)
	menu_vbox.add_child(btn_join)
	
	# 3. USTAWIENIA
	var btn_settings = Button.new()
	btn_settings.text = "USTAWIENIA"
	UITheme.style_menu_action_button(btn_settings, 24)
	btn_settings.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	btn_settings.pressed.connect(_on_settings_pressed)
	menu_vbox.add_child(btn_settings)
	
	# Status message
	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	menu_vbox.add_child(status_lbl)
	
	# --- EXPANDING SPACER PUSHING WATERMARK TO BOTTOM ---
	var spacer_bottom = Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer_bottom)
	
	# --- BOTTOM WATERMARK ---
	var bottom_lbl = Label.new()
	bottom_lbl.text = "v0.1 · RTS multiplayer"
	bottom_lbl.add_theme_font_size_override("font_size", 11)
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
	var modal = SettingsModal.new(settings_manager, network_manager)
	modal.settings_closed.connect(func(_saved):
		_update_profile_display()
	)
	add_child(modal)

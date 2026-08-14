# Overwatch / Factory of War Main Menu View with Background Slides
class_name MenuView
extends Control

signal host_requested(port: int, player_name: String, is_public: bool, host_ip: String)
signal join_by_code_requested(code: String, player_name: String)
signal join_direct_requested(ip: String, port: int, player_name: String)
signal open_settings_requested()

var network_manager: NetworkManager
var settings_manager: SettingsManager

# UI Elements
var banner_rect1: TextureRect
var banner_rect2: TextureRect
var banner_timer: float = 0.0
var active_banner_idx: int = 0
var banner_textures: Array[Texture2D] = []

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
		if banner_timer >= 7.0:
			banner_timer = 0.0
			_crossfade_banner()

func _load_banner_textures() -> void:
	banner_textures.clear()
	var path1 = "res://public/ui/menu_banner.png"
	var path2 = "res://public/ui/menu_banner_cyber.png"
	
	if ResourceLoader.exists(path1):
		banner_textures.append(load(path1))
	if ResourceLoader.exists(path2):
		banner_textures.append(load(path2))

func _build_ui() -> void:
	# 1. Background Layers for smooth crossfade
	banner_rect1 = TextureRect.new()
	banner_rect1.set_anchors_preset(PRESET_FULL_RECT)
	banner_rect1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if not banner_textures.is_empty():
		banner_rect1.texture = banner_textures[0]
	add_child(banner_rect1)
	
	banner_rect2 = TextureRect.new()
	banner_rect2.set_anchors_preset(PRESET_FULL_RECT)
	banner_rect2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner_rect2.modulate = Color(1, 1, 1, 0)
	if banner_textures.size() >= 2:
		banner_rect2.texture = banner_textures[1]
	add_child(banner_rect2)
	
	# Dark cyber vignette overlay
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.color = Color(0.02, 0.05, 0.10, 0.45)
	add_child(vignette)
	
	# Margin Layout for UI Controls
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	
	# Top Bar (Title on Left, Profile on Right)
	var top_hbox = HBoxContainer.new()
	top_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_hbox)
	
	# Top Left: Title
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "FACTORY OF WAR"
	title_lbl.add_theme_font_size_override("font_size", 42)
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
	profile_sb.bg_color = Color(0.06, 0.10, 0.18, 0.90)
	profile_sb.border_color = UITheme.COLOR_ACCENT_ORANGE
	profile_sb.border_width_right = 4
	profile_sb.set_corner_radius_all(2)
	profile_sb.content_margin_left = 16
	profile_sb.content_margin_right = 16
	profile_sb.content_margin_top = 8
	profile_sb.content_margin_bottom = 8
	profile_btn.add_theme_stylebox_override("normal", profile_sb)
	profile_btn.add_theme_stylebox_override("hover", profile_sb)
	profile_btn.add_theme_stylebox_override("pressed", profile_sb)
	profile_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	profile_btn.pressed.connect(_on_settings_pressed)
	top_hbox.add_child(profile_btn)
	
	var prof_vbox = VBoxContainer.new()
	prof_vbox.add_theme_constant_override("separation", 1)
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
	
	# Middle/Left: Action Menu Buttons (Stacked vertically)
	var menu_vbox = VBoxContainer.new()
	menu_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_vbox.add_theme_constant_override("separation", 18)
	margin.add_child(menu_vbox)
	
	# STWÓRZ GRĘ
	var btn_host = Button.new()
	btn_host.text = "STWÓRZ GRĘ"
	UITheme.style_menu_action_button(btn_host, 28)
	btn_host.pressed.connect(_on_create_game_pressed)
	menu_vbox.add_child(btn_host)
	
	# DOŁĄCZ DO GRY
	var btn_join = Button.new()
	btn_join.text = "DOŁĄCZ DO GRY"
	UITheme.style_menu_action_button(btn_join, 28)
	btn_join.pressed.connect(_on_join_game_pressed)
	menu_vbox.add_child(btn_join)
	
	# USTAWIENIA
	var btn_settings = Button.new()
	btn_settings.text = "USTAWIENIA"
	UITheme.style_menu_action_button(btn_settings, 24)
	btn_settings.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	btn_settings.pressed.connect(_on_settings_pressed)
	menu_vbox.add_child(btn_settings)
	
	# Status label
	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	menu_vbox.add_child(status_lbl)
	
	# Bottom Left: Watermark
	var bottom_lbl = Label.new()
	bottom_lbl.text = "v0.1 · RTS multiplayer"
	bottom_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_lbl.add_theme_font_size_override("font_size", 11)
	bottom_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED.darkened(0.2))
	margin.add_child(bottom_lbl)

func _crossfade_banner() -> void:
	if banner_textures.size() < 2: return
	
	var tween = create_tween()
	if active_banner_idx == 0:
		active_banner_idx = 1
		tween.tween_property(banner_rect2, "modulate:a", 1.0, 1.5)
	else:
		active_banner_idx = 0
		tween.tween_property(banner_rect2, "modulate:a", 0.0, 1.5)

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

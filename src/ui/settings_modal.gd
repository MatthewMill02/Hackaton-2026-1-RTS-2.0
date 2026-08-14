# Overwatch-style Settings Pop-up Modal
class_name SettingsModal
extends Control

signal settings_closed(saved: bool)

var settings_manager: SettingsManager
var network_manager: NetworkManager

var name_input: LineEdit
var res_options: OptionButton
var res_info_lbl: Label
var scroll_slider: HSlider
var scroll_value_lbl: Label
var host_ip_options: OptionButton
var host_ip_input: LineEdit
var host_port_input: LineEdit
var save_btn: Button

func _init(p_settings: SettingsManager, p_network: NetworkManager = null) -> void:
	settings_manager = p_settings
	network_manager = p_network
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_load_current_values()

func _build_ui() -> void:
	# Dark semi-transparent backdrop
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.08, 0.85)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	# Modal Box
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 560)
	var panel_sb = UITheme.create_panel_style(
		UITheme.COLOR_MODAL_BG,
		Color(0.14, 0.28, 0.44, 0.9),
		6, 2, 0
	)
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	# --- 1. HEADER BANNER (Ice-blue slanted bar) ---
	var header_bar = PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 52)
	var header_sb = StyleBoxFlat.new()
	header_sb.bg_color = UITheme.COLOR_MODAL_HEADER_BG
	header_sb.content_margin_left = 20
	header_sb.content_margin_top = 10
	header_sb.content_margin_bottom = 10
	header_bar.add_theme_stylebox_override("panel", header_sb)
	vbox.add_child(header_bar)
	
	var header_lbl = Label.new()
	header_lbl.text = "USTAWIENIA"
	header_lbl.add_theme_font_size_override("font_size", 24)
	header_lbl.add_theme_color_override("font_color", UITheme.COLOR_MODAL_HEADER_TEXT)
	header_bar.add_child(header_lbl)
	
	# Content margins
	var content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 20)
	vbox.add_child(content_margin)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 18)
	content_margin.add_child(content_vbox)
	
	# --- 2. NICK GRACZA ---
	var nick_box = VBoxContainer.new()
	nick_box.add_theme_constant_override("separation", 6)
	content_vbox.add_child(nick_box)
	
	var nick_lbl = Label.new()
	nick_lbl.text = "NICK GRACZA"
	nick_lbl.add_theme_font_size_override("font_size", 14)
	nick_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	nick_box.add_child(nick_lbl)
	
	name_input = LineEdit.new()
	UITheme.style_line_edit(name_input, 15)
	nick_box.add_child(name_input)
	
	# --- 3. ROZDZIELCZOŚĆ ---
	var res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 4)
	content_vbox.add_child(res_box)
	
	var res_lbl = Label.new()
	res_lbl.text = "ROZDZIELCZOŚĆ"
	res_lbl.add_theme_font_size_override("font_size", 14)
	res_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	res_box.add_child(res_lbl)
	
	res_options = OptionButton.new()
	res_options.add_item("Auto (Maksymalny rozmiar monitora)", 0)
	res_options.add_item("1920x1080 (Okno)", 1)
	res_options.add_item("1280x720 (Okno)", 2)
	res_options.custom_minimum_size = Vector2(0, 36)
	res_box.add_child(res_options)
	
	var screen_sz = DisplayServer.screen_get_size()
	var win_sz = DisplayServer.window_get_size()
	res_info_lbl = Label.new()
	res_info_lbl.text = "Monitor %dx%d · okno %dx%d" % [screen_sz.x, screen_sz.y, win_sz.x, win_sz.y]
	res_info_lbl.add_theme_font_size_override("font_size", 12)
	res_info_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	res_box.add_child(res_info_lbl)
	
	# --- 4. SZYBKOŚĆ RUCHU MAPY ---
	var scroll_box = VBoxContainer.new()
	scroll_box.add_theme_constant_override("separation", 6)
	content_vbox.add_child(scroll_box)
	
	var scroll_lbl = Label.new()
	scroll_lbl.text = "SZYBKOŚĆ RUCHU MAPY"
	scroll_lbl.add_theme_font_size_override("font_size", 14)
	scroll_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	scroll_box.add_child(scroll_lbl)
	
	scroll_slider = HSlider.new()
	scroll_slider.min_value = 0.4
	scroll_slider.max_value = 2.5
	scroll_slider.step = 0.1
	scroll_slider.value = 1.0
	scroll_slider.value_changed.connect(func(v: float):
		scroll_value_lbl.text = "Wartość: %.1fx  (0.4 — 2.5)" % v
	)
	scroll_box.add_child(scroll_slider)
	
	scroll_value_lbl = Label.new()
	scroll_value_lbl.text = "Wartość: 1.0x  (0.4 — 2.5)"
	scroll_value_lbl.add_theme_font_size_override("font_size", 12)
	scroll_value_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	scroll_box.add_child(scroll_value_lbl)
	
	# --- 5. SERWER P2P (RADMIN / LAN) ---
	var ip_box = VBoxContainer.new()
	ip_box.add_theme_constant_override("separation", 6)
	content_vbox.add_child(ip_box)
	
	var ip_lbl = Label.new()
	ip_lbl.text = "SERWER P2P (RADMIN / LAN)"
	ip_lbl.add_theme_font_size_override("font_size", 14)
	ip_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	ip_box.add_child(ip_lbl)
	
	host_ip_options = OptionButton.new()
	host_ip_options.custom_minimum_size = Vector2(0, 34)
	host_ip_options.item_selected.connect(_on_ip_option_selected)
	ip_box.add_child(host_ip_options)
	
	var ip_input_row = HBoxContainer.new()
	ip_input_row.add_theme_constant_override("separation", 8)
	ip_box.add_child(ip_input_row)
	
	host_ip_input = LineEdit.new()
	host_ip_input.placeholder_text = "IP Radmin (np. 26.x.x.x lub puste)"
	host_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(host_ip_input, 13)
	ip_input_row.add_child(host_ip_input)
	
	host_port_input = LineEdit.new()
	host_port_input.text = "7777"
	host_port_input.custom_minimum_size = Vector2(80, 0)
	UITheme.style_line_edit(host_port_input, 13)
	ip_input_row.add_child(host_port_input)
	
	# --- 6. SAVE & CLOSE BUTTON ---
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content_vbox.add_child(spacer)
	
	save_btn = Button.new()
	save_btn.text = "ZAPISZ I ZAMKNIJ"
	UITheme.style_button(save_btn, Color(0.12, 0.28, 0.44), UITheme.COLOR_ACCENT_CYAN, 46, 18)
	save_btn.pressed.connect(_on_save_pressed)
	content_vbox.add_child(save_btn)

func _load_current_values() -> void:
	if settings_manager != null:
		name_input.text = settings_manager.player_name
		res_options.selected = settings_manager.window_mode
		scroll_slider.value = settings_manager.map_scroll_speed
		scroll_value_lbl.text = "Wartość: %.1fx  (0.4 — 2.5)" % settings_manager.map_scroll_speed
		host_ip_input.text = settings_manager.custom_host_ip
		host_port_input.text = str(settings_manager.custom_port)
		
	# Populate IP options
	host_ip_options.clear()
	var ips: Array[String] = []
	if network_manager != null:
		ips = network_manager.get_available_local_ips()
		
	var selected_idx = 0
	var found_radmin = false
	for i in range(ips.size()):
		var ip_str = ips[i]
		var label_str = ip_str
		if ip_str.begins_with("26."):
			label_str += " (Radmin VPN)"
			if not found_radmin:
				selected_idx = i
				found_radmin = true
		elif ip_str.begins_with("192.168.") or ip_str.begins_with("10."):
			label_str += " (LAN / Wi-Fi)"
		host_ip_options.add_item(label_str, i)
		
	host_ip_options.add_item("Własne IP (Wpisz obok)", ips.size())
	if not ips.is_empty():
		host_ip_options.selected = selected_idx
		if host_ip_input.text.is_empty():
			host_ip_input.text = ips[selected_idx]

func _on_ip_option_selected(index: int) -> void:
	var ips: Array[String] = []
	if network_manager != null:
		ips = network_manager.get_available_local_ips()
	if index < ips.size():
		host_ip_input.text = ips[index]

func _on_save_pressed() -> void:
	if settings_manager != null:
		var p_name = name_input.text.strip_edges()
		if not p_name.is_empty():
			settings_manager.player_name = p_name
		settings_manager.window_mode = res_options.selected
		settings_manager.map_scroll_speed = scroll_slider.value
		settings_manager.custom_host_ip = host_ip_input.text.strip_edges()
		settings_manager.custom_port = host_port_input.text.to_int() if host_port_input.text.to_int() > 1024 else GameState.DEFAULT_PORT
		settings_manager.save_settings()
		settings_manager.apply_display_mode()
		
	settings_closed.emit(true)
	queue_free()

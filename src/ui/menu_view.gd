# Pure Code Main Menu View with Host IP Selector, Public Server Browser & Room Codes
class_name MenuView
extends Control

signal host_requested(port: int, player_name: String, is_public: bool, host_ip: String)
signal join_by_code_requested(code: String, player_name: String)
signal join_direct_requested(ip: String, port: int, player_name: String)
signal refresh_lobbies_requested()

var network_manager: NetworkManager

# UI Elements - Host Section
var name_input: LineEdit
var host_ip_options: OptionButton
var host_ip_row: HBoxContainer
var host_ip_input: LineEdit
var host_port_input: LineEdit
var host_public_check: CheckBox
var host_btn: Button

# UI Elements - Join Section
var code_input: LineEdit
var join_code_btn: Button

var refresh_btn: Button
var server_list_vbox: VBoxContainer
var empty_servers_lbl: Label

var direct_ip_input: LineEdit
var direct_port_input: LineEdit
var direct_join_btn: Button

var status_lbl: Label

func _init(net_mgr: NetworkManager = null) -> void:
	network_manager = net_mgr
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_populate_detected_ips()
	if network_manager != null and network_manager.discovery != null:
		network_manager.discovery.lobbies_updated.connect(_on_lobbies_updated)
		network_manager.discovery.start_listener()
		_on_lobbies_updated(network_manager.discovery.get_public_lobbies())

func _build_ui() -> void:
	# Background
	var bg = ColorRect.new()
	bg.color = UITheme.COLOR_BG_DARK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# Margin Layout
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)
	
	# ==========================================================================
	# 1. HEADER / TITLE & NICKNAME
	# ==========================================================================
	var top_panel = PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 12
	))
	main_vbox.add_child(top_panel)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	top_panel.add_child(top_hbox)
	
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(title_box)
	
	var title_lbl = Label.new()
	title_lbl.text = "AUTOMATA TECH-WAR"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	title_box.add_child(title_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "RTS MULTIPLAYER — LAN / RADMIN VPN"
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	title_box.add_child(sub_lbl)
	
	var name_box = HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 10)
	top_hbox.add_child(name_box)
	
	var name_lbl = Label.new()
	name_lbl.text = "TWÓJ NICK:"
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	name_box.add_child(name_lbl)
	
	name_input = LineEdit.new()
	name_input.text = "Gracz_" + str(randi_range(1000, 9999))
	name_input.custom_minimum_size = Vector2(200, 36)
	UITheme.style_line_edit(name_input, 14)
	name_box.add_child(name_input)
	
	# ==========================================================================
	# 2. MAIN TWO COLUMNS (HOST vs JOIN)
	# ==========================================================================
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(cols)
	
	# --- LEFT COLUMN: HOST A GAME ---
	var host_card = PanelContainer.new()
	host_card.custom_minimum_size = Vector2(420, 0)
	host_card.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 16
	))
	cols.add_child(host_card)
	
	var host_vbox = VBoxContainer.new()
	host_vbox.add_theme_constant_override("separation", 12)
	host_card.add_child(host_vbox)
	
	var host_header = Label.new()
	host_header.text = "STWÓRZ NOWĄ GRĘ (HOST)"
	host_header.add_theme_font_size_override("font_size", 18)
	host_header.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	host_vbox.add_child(host_header)
	
	# Host IP selection row
	var host_ip_title = Label.new()
	host_ip_title.text = "Twoje IP do łączenia (Radmin VPN / LAN):"
	host_ip_title.add_theme_font_size_override("font_size", 13)
	host_ip_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	host_vbox.add_child(host_ip_title)
	
	host_ip_options = OptionButton.new()
	host_ip_options.custom_minimum_size = Vector2(0, 34)
	host_ip_options.item_selected.connect(_on_ip_option_selected)
	host_vbox.add_child(host_ip_options)
	
	host_ip_row = HBoxContainer.new()
	host_ip_row.add_theme_constant_override("separation", 8)
	host_ip_row.visible = false
	host_vbox.add_child(host_ip_row)
	
	var custom_ip_lbl = Label.new()
	custom_ip_lbl.text = "Własne IP:"
	custom_ip_lbl.custom_minimum_size = Vector2(70, 0)
	host_ip_row.add_child(custom_ip_lbl)
	
	host_ip_input = LineEdit.new()
	host_ip_input.placeholder_text = "np. 26.120.45.10"
	host_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(host_ip_input, 13)
	host_ip_row.add_child(host_ip_input)
	
	# Port & Public checkbox
	var port_row = HBoxContainer.new()
	var port_lbl = Label.new()
	port_lbl.text = "Port gry:"
	port_lbl.custom_minimum_size = Vector2(70, 0)
	port_row.add_child(port_lbl)
	
	host_port_input = LineEdit.new()
	host_port_input.text = str(GameState.DEFAULT_PORT)
	host_port_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(host_port_input, 13)
	port_row.add_child(host_port_input)
	host_vbox.add_child(port_row)
	
	host_public_check = CheckBox.new()
	host_public_check.text = "Pokój publiczny (widoczny na liście)"
	host_public_check.button_pressed = true
	host_public_check.add_theme_font_size_override("font_size", 13)
	host_public_check.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	host_vbox.add_child(host_public_check)
	
	var spacer_h = Control.new()
	spacer_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host_vbox.add_child(spacer_h)
	
	host_btn = Button.new()
	host_btn.text = "STWÓRZ POKÓJ"
	UITheme.style_button(host_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 44, 15)
	host_btn.pressed.connect(_on_host_pressed)
	host_vbox.add_child(host_btn)
	
	# --- RIGHT COLUMN: JOIN OPTIONS ---
	var join_card = PanelContainer.new()
	join_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_card.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 16
	))
	cols.add_child(join_card)
	
	var join_vbox = VBoxContainer.new()
	join_vbox.add_theme_constant_override("separation", 12)
	join_card.add_child(join_vbox)
	
	# Option 1: 6-letter room code
	var code_section = PanelContainer.new()
	code_section.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		Color(0.06, 0.09, 0.14, 0.9),
		Color(0.16, 0.35, 0.52, 0.7),
		8, 1, 10
	))
	join_vbox.add_child(code_section)
	
	var code_vbox = VBoxContainer.new()
	code_vbox.add_theme_constant_override("separation", 8)
	code_section.add_child(code_vbox)
	
	var code_header = Label.new()
	code_header.text = "OPCJA 1: DOŁĄCZ PRZEZ KOD POKOJU"
	code_header.add_theme_font_size_override("font_size", 14)
	code_header.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	code_vbox.add_child(code_header)
	
	var code_row = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_vbox.add_child(code_row)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "Wpisz 6 liter (np. XKZRAW)"
	code_input.max_length = RoomCodeHelper.CODE_LENGTH
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(code_input, 15)
	code_input.text_changed.connect(func(new_text: String):
		code_input.text = RoomCodeHelper.normalize(new_text)
		code_input.caret_column = code_input.text.length()
	)
	code_input.text_submitted.connect(func(_t): _on_join_by_code_pressed())
	code_row.add_child(code_input)
	
	join_code_btn = Button.new()
	join_code_btn.text = "DOŁĄCZ KODEM"
	join_code_btn.custom_minimum_size = Vector2(130, 36)
	UITheme.style_button(join_code_btn, Color(0.12, 0.38, 0.28), UITheme.COLOR_SUCCESS_GREEN, 36, 13)
	join_code_btn.pressed.connect(_on_join_by_code_pressed)
	code_row.add_child(join_code_btn)
	
	# Option 2: Public server list
	var server_header_row = HBoxContainer.new()
	server_header_row.add_theme_constant_override("separation", 10)
	join_vbox.add_child(server_header_row)
	
	var server_header_lbl = Label.new()
	server_header_lbl.text = "OPCJA 2: LISTA PUBLICZNYCH POKOI"
	server_header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_header_lbl.add_theme_font_size_override("font_size", 14)
	server_header_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	server_header_row.add_child(server_header_lbl)
	
	refresh_btn = Button.new()
	refresh_btn.text = "🔄 Odśwież"
	refresh_btn.custom_minimum_size = Vector2(85, 28)
	UITheme.style_button(refresh_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 28, 12)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	server_header_row.add_child(refresh_btn)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 110)
	join_vbox.add_child(scroll)
	
	server_list_vbox = VBoxContainer.new()
	server_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(server_list_vbox)
	
	empty_servers_lbl = Label.new()
	empty_servers_lbl.text = "Szukanie publicznych pokoi w sieci LAN / Radmin VPN..."
	empty_servers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_servers_lbl.add_theme_font_size_override("font_size", 12)
	empty_servers_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	server_list_vbox.add_child(empty_servers_lbl)
	
	# Direct IP
	var direct_row = HBoxContainer.new()
	direct_row.add_theme_constant_override("separation", 8)
	join_vbox.add_child(direct_row)
	
	var ip_lbl = Label.new()
	ip_lbl.text = "Bezpośrednie IP:"
	direct_row.add_child(ip_lbl)
	
	direct_ip_input = LineEdit.new()
	direct_ip_input.text = "127.0.0.1"
	direct_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(direct_ip_input, 13)
	direct_row.add_child(direct_ip_input)
	
	var direct_p_lbl = Label.new()
	direct_p_lbl.text = "Port:"
	direct_row.add_child(direct_p_lbl)
	
	direct_port_input = LineEdit.new()
	direct_port_input.text = str(GameState.DEFAULT_PORT)
	direct_port_input.custom_minimum_size = Vector2(65, 0)
	UITheme.style_line_edit(direct_port_input, 13)
	direct_row.add_child(direct_port_input)
	
	direct_join_btn = Button.new()
	direct_join_btn.text = "Połącz IP"
	direct_join_btn.custom_minimum_size = Vector2(80, 32)
	UITheme.style_button(direct_join_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 32, 12)
	direct_join_btn.pressed.connect(_on_direct_join_pressed)
	direct_row.add_child(direct_join_btn)
	
	# ==========================================================================
	# 3. STATUS FOOTER
	# ==========================================================================
	status_lbl = Label.new()
	status_lbl.text = "Gotowy do połączenia. Wybierz opcję..."
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	main_vbox.add_child(status_lbl)

# ==============================================================================
# Helper & State Updates
# ==============================================================================

func _populate_detected_ips() -> void:
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
		else:
			label_str += " (Karta sieciowa)"
			
		host_ip_options.add_item(label_str, i)
		
	host_ip_options.add_item("Własne IP (Wpisz poniżej)", ips.size())
	
	if not ips.is_empty():
		host_ip_options.selected = selected_idx
		host_ip_input.text = ips[selected_idx]
		host_ip_row.visible = false
	else:
		host_ip_options.selected = 0
		host_ip_input.text = "127.0.0.1"
		host_ip_row.visible = true

func _on_ip_option_selected(index: int) -> void:
	var ips: Array[String] = []
	if network_manager != null:
		ips = network_manager.get_available_local_ips()
		
	if index < ips.size():
		host_ip_input.text = ips[index]
		host_ip_row.visible = false
	else:
		host_ip_row.visible = true
		host_ip_input.grab_focus()

func set_status(msg: String, is_error: bool = false) -> void:
	if status_lbl != null:
		status_lbl.text = msg
		if is_error:
			status_lbl.add_theme_color_override("font_color", UITheme.COLOR_DANGER_RED)
		else:
			status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)

func set_controls_enabled(enabled: bool) -> void:
	if host_btn: host_btn.disabled = not enabled
	if join_code_btn: join_code_btn.disabled = not enabled
	if direct_join_btn: direct_join_btn.disabled = not enabled
	if name_input: name_input.editable = enabled

func _on_lobbies_updated(lobbies: Array) -> void:
	if server_list_vbox == null:
		return
		
	for child in server_list_vbox.get_children():
		child.queue_free()
		
	if lobbies.is_empty():
		empty_servers_lbl = Label.new()
		empty_servers_lbl.text = "Brak aktywnych publicznych pokoi w sieci LAN / Radmin VPN.\nStwórz własny lub wpisz kod pokoju."
		empty_servers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_servers_lbl.add_theme_font_size_override("font_size", 12)
		empty_servers_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		server_list_vbox.add_child(empty_servers_lbl)
		return
		
	for lobby in lobbies:
		var item = _create_server_list_item(lobby)
		server_list_vbox.add_child(item)

func _create_server_list_item(lobby: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 44)
	
	var sb = UITheme.create_panel_style(
		Color(0.08, 0.12, 0.18, 0.9),
		Color(0.18, 0.38, 0.58, 0.6),
		6, 1, 8
	)
	panel.add_theme_stylebox_override("panel", sb)
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "Pokój: " + str(lobby.get("host_name", "Host"))
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	info_vbox.add_child(name_lbl)
	
	var ip_sub = Label.new()
	ip_sub.text = "%s:%d" % [lobby.get("ip", ""), lobby.get("port", GameState.DEFAULT_PORT)]
	ip_sub.add_theme_font_size_override("font_size", 11)
	ip_sub.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	info_vbox.add_child(ip_sub)
	
	var code_badge = UITheme.create_badge("KOD: " + str(lobby.get("code", "------")), Color(0.12, 0.28, 0.44), UITheme.COLOR_ACCENT_CYAN)
	row.add_child(code_badge)
	
	var count_lbl = Label.new()
	count_lbl.text = "%d/%d graczy" % [lobby.get("players", 1), lobby.get("max_players", GameState.MAX_PLAYERS)]
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	row.add_child(count_lbl)
	
	var btn_join = Button.new()
	btn_join.text = "Dołącz"
	btn_join.custom_minimum_size = Vector2(75, 30)
	UITheme.style_button(btn_join, Color(0.12, 0.38, 0.25), UITheme.COLOR_SUCCESS_GREEN, 30, 12)
	btn_join.pressed.connect(func():
		var p_name = name_input.text.strip_edges()
		if p_name.is_empty():
			set_status("Wprowadź swój nick!", true)
			return
		join_direct_requested.emit(str(lobby.get("ip", "127.0.0.1")), int(lobby.get("port", GameState.DEFAULT_PORT)), p_name)
	)
	row.add_child(btn_join)
	
	return panel

# ==============================================================================
# Button Callbacks
# ==============================================================================

func _on_host_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		set_status("Wprowadź swój nick!", true)
		return
		
	var port = host_port_input.text.to_int()
	if port <= 1024 or port > 65535:
		port = GameState.DEFAULT_PORT
		
	var ips: Array[String] = []
	if network_manager != null:
		ips = network_manager.get_available_local_ips()
		
	var chosen_ip = ""
	var selected_idx = host_ip_options.selected
	if selected_idx >= 0 and selected_idx < ips.size():
		chosen_ip = ips[selected_idx]
	else:
		chosen_ip = host_ip_input.text.strip_edges()
		if chosen_ip.is_empty():
			chosen_ip = "127.0.0.1"
	
	set_controls_enabled(false)
	host_requested.emit(port, p_name, host_public_check.button_pressed, chosen_ip)

func _on_join_by_code_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		set_status("Wprowadź swój nick!", true)
		return
		
	var code = RoomCodeHelper.normalize(code_input.text)
	if code.length() != RoomCodeHelper.CODE_LENGTH:
		set_status("Wpisz pełny 6-literowy kod pokoju!", true)
		return
		
	set_status("Szukanie pokoju o kodzie %s..." % code, false)
	join_by_code_requested.emit(code, p_name)

func _on_refresh_pressed() -> void:
	set_status("Odświeżanie listy pokoi w sieci...", false)
	if network_manager != null and network_manager.discovery != null:
		network_manager.discovery.request_refresh()
	refresh_lobbies_requested.emit()

func _on_direct_join_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		set_status("Wprowadź swój nick!", true)
		return
		
	var ip = direct_ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
		
	var port = direct_port_input.text.to_int()
	if port <= 1024 or port > 65535:
		port = GameState.DEFAULT_PORT
		
	set_controls_enabled(false)
	join_direct_requested.emit(ip, port, p_name)

# Overwatch-style Join Game Modal (Room Code + Public Server Browser)
class_name JoinModal
extends Control

signal join_by_code_requested(code: String, player_name: String)
signal join_direct_requested(ip: String, port: int, player_name: String)
signal modal_closed()

var network_manager: NetworkManager
var settings_manager: SettingsManager

var code_input: LineEdit
var join_code_btn: Button
var refresh_btn: Button
var server_list_vbox: VBoxContainer
var empty_servers_lbl: Label
var direct_ip_input: LineEdit
var direct_port_input: LineEdit
var direct_join_btn: Button
var close_btn: Button
var status_lbl: Label

func _init(p_net: NetworkManager, p_settings: SettingsManager) -> void:
	network_manager = p_net
	settings_manager = p_settings
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	if network_manager != null and network_manager.discovery != null:
		network_manager.discovery.lobbies_updated.connect(_on_lobbies_updated)
		network_manager.discovery.start_listener()
		_on_lobbies_updated(network_manager.discovery.get_public_lobbies())

func _build_ui() -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.08, 0.85)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 580)
	var panel_sb = UITheme.create_panel_style(
		UITheme.COLOR_MODAL_BG,
		Color(0.14, 0.28, 0.44, 0.9),
		6, 2, 0
	)
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# Header
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
	header_lbl.text = "DOŁĄCZ DO GRY"
	header_lbl.add_theme_font_size_override("font_size", 22)
	header_lbl.add_theme_color_override("font_color", UITheme.COLOR_MODAL_HEADER_TEXT)
	header_bar.add_child(header_lbl)
	
	var content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_top", 4)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	vbox.add_child(content_margin)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 14)
	content_margin.add_child(content_vbox)
	
	# --- SECTION 1: CODE ---
	var code_card = PanelContainer.new()
	code_card.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		Color(0.06, 0.09, 0.15, 0.8),
		Color(0.16, 0.32, 0.48, 0.6),
		4, 1, 12
	))
	content_vbox.add_child(code_card)
	
	var code_vbox = VBoxContainer.new()
	code_vbox.add_theme_constant_override("separation", 8)
	code_card.add_child(code_vbox)
	
	var code_lbl = Label.new()
	code_lbl.text = "OPCJA 1: DOŁĄCZ PRZEZ KOD POKOJU"
	code_lbl.add_theme_font_size_override("font_size", 14)
	code_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	code_vbox.add_child(code_lbl)
	
	var code_row = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_vbox.add_child(code_row)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "Wpisz 6-literowy kod (np. HUJFFC)"
	code_input.max_length = RoomCodeHelper.CODE_LENGTH
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(code_input, 16)
	code_input.text_changed.connect(func(t: String):
		code_input.text = RoomCodeHelper.normalize(t)
		code_input.caret_column = code_input.text.length()
	)
	code_input.text_submitted.connect(func(_t): _on_join_code_pressed())
	code_row.add_child(code_input)
	
	join_code_btn = Button.new()
	join_code_btn.text = "DOŁĄCZ KODEM"
	join_code_btn.custom_minimum_size = Vector2(140, 38)
	UITheme.style_button(join_code_btn, Color(0.12, 0.35, 0.25), UITheme.COLOR_SUCCESS_GREEN, 38, 14)
	join_code_btn.pressed.connect(_on_join_code_pressed)
	code_row.add_child(join_code_btn)
	
	# --- SECTION 2: PUBLIC LOBBIES ---
	var list_header = HBoxContainer.new()
	content_vbox.add_child(list_header)
	
	var list_lbl = Label.new()
	list_lbl.text = "OPCJA 2: PUBLICZNE POKOJE W SIECI"
	list_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_lbl.add_theme_font_size_override("font_size", 14)
	list_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	list_header.add_child(list_lbl)
	
	refresh_btn = Button.new()
	refresh_btn.text = "🔄 Odśwież"
	refresh_btn.custom_minimum_size = Vector2(85, 28)
	UITheme.style_button(refresh_btn, UITheme.COLOR_PANEL_BG, UITheme.COLOR_ACCENT_CYAN, 28, 12)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	list_header.add_child(refresh_btn)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 130)
	content_vbox.add_child(scroll)
	
	server_list_vbox = VBoxContainer.new()
	server_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(server_list_vbox)
	
	empty_servers_lbl = Label.new()
	empty_servers_lbl.text = "Szukanie pokoi w sieci LAN / Radmin VPN..."
	empty_servers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_servers_lbl.add_theme_font_size_override("font_size", 12)
	empty_servers_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	server_list_vbox.add_child(empty_servers_lbl)
	
	# Direct IP
	var direct_row = HBoxContainer.new()
	direct_row.add_theme_constant_override("separation", 8)
	content_vbox.add_child(direct_row)
	
	var ip_lbl = Label.new()
	ip_lbl.text = "Bezpośrednie IP:"
	direct_row.add_child(ip_lbl)
	
	direct_ip_input = LineEdit.new()
	direct_ip_input.text = "127.0.0.1"
	direct_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(direct_ip_input, 13)
	direct_row.add_child(direct_ip_input)
	
	direct_port_input = LineEdit.new()
	direct_port_input.text = "7777"
	direct_port_input.custom_minimum_size = Vector2(70, 0)
	UITheme.style_line_edit(direct_port_input, 13)
	direct_row.add_child(direct_port_input)
	
	direct_join_btn = Button.new()
	direct_join_btn.text = "Połącz IP"
	direct_join_btn.custom_minimum_size = Vector2(80, 32)
	UITheme.style_button(direct_join_btn, UITheme.COLOR_PANEL_BG, UITheme.COLOR_ACCENT_CYAN, 32, 12)
	direct_join_btn.pressed.connect(_on_direct_join_pressed)
	direct_row.add_child(direct_join_btn)
	
	# Status
	status_lbl = Label.new()
	status_lbl.text = "Wpisz kod lub wybierz pokój z listy..."
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	content_vbox.add_child(status_lbl)
	
	# Close button
	close_btn = Button.new()
	close_btn.text = "ANULUJ"
	UITheme.style_button(close_btn, Color(0.25, 0.10, 0.12), UITheme.COLOR_ACCENT_RED, 40, 14)
	close_btn.pressed.connect(func():
		modal_closed.emit()
		queue_free()
	)
	content_vbox.add_child(close_btn)

func _on_lobbies_updated(lobbies: Array) -> void:
	if server_list_vbox == null: return
	for c in server_list_vbox.get_children():
		c.queue_free()
		
	if lobbies.is_empty():
		empty_servers_lbl = Label.new()
		empty_servers_lbl.text = "Brak aktywnych publicznych pokoi w sieci LAN / Radmin VPN."
		empty_servers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_servers_lbl.add_theme_font_size_override("font_size", 12)
		empty_servers_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		server_list_vbox.add_child(empty_servers_lbl)
		return
		
	for lobby in lobbies:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(0, 42)
		panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
			Color(0.08, 0.12, 0.18, 0.9), Color(0.18, 0.38, 0.58, 0.6), 4, 1, 8
		))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		
		var name_lbl = Label.new()
		name_lbl.text = "Host: " + str(lobby.get("host_name", "Host"))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(name_lbl)
		
		var badge = UITheme.create_badge("KOD: " + str(lobby.get("code", "------")), Color(0.12, 0.28, 0.44), UITheme.COLOR_ACCENT_CYAN)
		row.add_child(badge)
		
		var count_lbl = Label.new()
		count_lbl.text = "%d/%d" % [lobby.get("players", 1), lobby.get("max_players", GameState.MAX_PLAYERS)]
		count_lbl.add_theme_font_size_override("font_size", 13)
		count_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
		row.add_child(count_lbl)
		
		var btn = Button.new()
		btn.text = "Dołącz"
		btn.custom_minimum_size = Vector2(70, 30)
		UITheme.style_button(btn, Color(0.12, 0.38, 0.25), UITheme.COLOR_SUCCESS_GREEN, 30, 12)
		btn.pressed.connect(func():
			var p_name = settings_manager.player_name if settings_manager else "Gracz"
			join_direct_requested.emit(str(lobby.get("ip", "127.0.0.1")), int(lobby.get("port", GameState.DEFAULT_PORT)), p_name)
			queue_free()
		)
		row.add_child(btn)
		server_list_vbox.add_child(panel)

func _on_join_code_pressed() -> void:
	var code = RoomCodeHelper.normalize(code_input.text)
	if code.length() != RoomCodeHelper.CODE_LENGTH:
		status_lbl.text = "Wpisz pełny 6-literowy kod pokoju!"
		status_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
		return
	var p_name = settings_manager.player_name if settings_manager else "Gracz"
	join_by_code_requested.emit(code, p_name)
	queue_free()

func _on_refresh_pressed() -> void:
	status_lbl.text = "Odświeżanie listy pokoi..."
	if network_manager != null and network_manager.discovery != null:
		network_manager.discovery.request_refresh()

func _on_direct_join_pressed() -> void:
	var ip = direct_ip_input.text.strip_edges()
	if ip.is_empty(): ip = "127.0.0.1"
	var port = direct_port_input.text.to_int()
	if port <= 1024: port = GameState.DEFAULT_PORT
	var p_name = settings_manager.player_name if settings_manager else "Gracz"
	join_direct_requested.emit(ip, port, p_name)
	queue_free()

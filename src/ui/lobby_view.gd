# Pure Code Multiplayer Lobby View with Room Code Banner & Public Lobby Switch
class_name LobbyView
extends Control

signal leave_lobby_requested()
signal ready_toggled()
signal slot_selected(slot_index: int)
signal chat_submitted(message: String)
signal start_game_requested()
signal public_toggled(is_public: bool)

var network_manager: NetworkManager

# UI References
var header_title_lbl: Label
var header_info_lbl: Label
var code_display_lbl: Label
var copy_code_btn: Button
var public_checkbox: CheckBox
var slot_cards: Array[PanelContainer] = []
var slot_name_lbls: Array[Label] = []
var slot_status_lbls: Array[Label] = []
var slot_buttons: Array[Button] = []
var chat_log: RichTextLabel
var chat_input: LineEdit
var ready_btn: Button
var start_btn: Button
var leave_btn: Button

func _init(net_mgr: NetworkManager = null) -> void:
	network_manager = net_mgr
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_update_header_info()
	if network_manager != null:
		network_manager.lobby_public_status_changed.connect(_on_public_status_changed)

func _build_ui() -> void:
	# Dark Background
	var bg = ColorRect.new()
	bg.color = UITheme.COLOR_BG_DARK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# Margin Layout
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)
	
	# ==========================================================================
	# 1. HEADER & ROOM CODE BANNER
	# ==========================================================================
	var header_panel = PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 14
	))
	main_vbox.add_child(header_panel)
	
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	header_panel.add_child(header_hbox)
	
	# Left: Title & Info
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_box)
	
	header_title_lbl = Label.new()
	header_title_lbl.text = "LOBBY ROZGRYWKI"
	header_title_lbl.add_theme_font_size_override("font_size", 22)
	header_title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	title_box.add_child(header_title_lbl)
	
	header_info_lbl = Label.new()
	header_info_lbl.text = "Pobieranie informacji o sieci..."
	header_info_lbl.add_theme_font_size_override("font_size", 12)
	header_info_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	title_box.add_child(header_info_lbl)
	
	# Middle/Right: Room Code Banner
	var code_box = PanelContainer.new()
	var code_sb = UITheme.create_panel_style(
		Color(0.04, 0.08, 0.14, 0.95),
		UITheme.COLOR_ACCENT_CYAN,
		8, 2, 8
	)
	code_box.add_theme_stylebox_override("panel", code_sb)
	header_hbox.add_child(code_box)
	
	var code_row = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_box.add_child(code_row)
	
	var code_title = Label.new()
	code_title.text = "KOD POKOJU:"
	code_title.add_theme_font_size_override("font_size", 13)
	code_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	code_row.add_child(code_title)
	
	code_display_lbl = Label.new()
	code_display_lbl.text = "------"
	code_display_lbl.add_theme_font_size_override("font_size", 22)
	code_display_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	code_row.add_child(code_display_lbl)
	
	copy_code_btn = Button.new()
	copy_code_btn.text = "Kopiuj"
	copy_code_btn.custom_minimum_size = Vector2(70, 32)
	UITheme.style_button(copy_code_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 32, 12)
	copy_code_btn.pressed.connect(_on_copy_code_pressed)
	code_row.add_child(copy_code_btn)
	
	# Rightmost: Public Toggle CheckBox
	public_checkbox = CheckBox.new()
	public_checkbox.text = "Lobby publiczne"
	public_checkbox.button_pressed = true
	public_checkbox.add_theme_font_size_override("font_size", 14)
	public_checkbox.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	public_checkbox.toggled.connect(_on_public_toggled)
	header_hbox.add_child(public_checkbox)
	
	# ==========================================================================
	# 2. MAIN CONTENT (SLOTS + CHAT)
	# ==========================================================================
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 18)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)
	
	# --- LEFT: 4 PLAYER SLOTS ---
	var slots_panel = PanelContainer.new()
	slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_panel.custom_minimum_size = Vector2(460, 0)
	slots_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 14
	))
	content_hbox.add_child(slots_panel)
	
	var slots_vbox = VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 10)
	slots_panel.add_child(slots_vbox)
	
	var slots_header = Label.new()
	slots_header.text = "POZYCJE STARTOWE I BAZY (1-4)"
	slots_header.add_theme_font_size_override("font_size", 15)
	slots_header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	slots_vbox.add_child(slots_header)
	
	slot_cards.clear()
	slot_name_lbls.clear()
	slot_status_lbls.clear()
	slot_buttons.clear()
	
	for i in range(GameState.MAX_PLAYERS):
		var card = _create_slot_card(i)
		slots_vbox.add_child(card)
		slot_cards.append(card)
	
	# --- RIGHT: CHAT & LOG ---
	var chat_panel = PanelContainer.new()
	chat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 14
	))
	content_hbox.add_child(chat_panel)
	
	var chat_vbox = VBoxContainer.new()
	chat_vbox.add_theme_constant_override("separation", 10)
	chat_panel.add_child(chat_vbox)
	
	var chat_header = Label.new()
	chat_header.text = "CZAT I KOMUNIKATY POKOJU"
	chat_header.add_theme_font_size_override("font_size", 15)
	chat_header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	chat_vbox.add_child(chat_header)
	
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.scroll_following = true
	chat_log.bbcode_enabled = true
	chat_log.add_theme_stylebox_override("normal", UITheme.create_panel_style(
		Color(0.04, 0.06, 0.09, 0.9),
		Color(0.12, 0.22, 0.35, 0.6),
		6, 1, 8
	))
	chat_vbox.add_child(chat_log)
	
	var chat_input_row = HBoxContainer.new()
	chat_input_row.add_theme_constant_override("separation", 8)
	chat_vbox.add_child(chat_input_row)
	
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Napisz wiadomość na czacie..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_line_edit(chat_input)
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input_row.add_child(chat_input)
	
	var send_btn = Button.new()
	send_btn.text = "Wyślij"
	send_btn.custom_minimum_size = Vector2(80, 38)
	UITheme.style_button(send_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 38, 14)
	send_btn.pressed.connect(_on_send_btn_pressed)
	chat_input_row.add_child(send_btn)
	
	# ==========================================================================
	# 3. BOTTOM CONTROLS
	# ==========================================================================
	var bottom_panel = PanelContainer.new()
	bottom_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_PANEL_BORDER,
		8, 1, 12
	))
	main_vbox.add_child(bottom_panel)
	
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 16)
	bottom_panel.add_child(bottom_hbox)
	
	leave_btn = Button.new()
	leave_btn.text = "OPUŚĆ LOBBY"
	leave_btn.custom_minimum_size = Vector2(160, 44)
	UITheme.style_button(leave_btn, Color(0.35, 0.12, 0.14, 1.0), UITheme.COLOR_DANGER_RED, 44, 15)
	leave_btn.pressed.connect(func(): leave_lobby_requested.emit())
	bottom_hbox.add_child(leave_btn)
	
	var spacer_b = Control.new()
	spacer_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(spacer_b)
	
	ready_btn = Button.new()
	ready_btn.text = "ZAZNACZ GOTOWOŚĆ"
	ready_btn.custom_minimum_size = Vector2(200, 44)
	UITheme.style_button(ready_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 44, 15)
	ready_btn.pressed.connect(func(): ready_toggled.emit())
	bottom_hbox.add_child(ready_btn)
	
	start_btn = Button.new()
	start_btn.text = "ROZPOCZNIJ ROZGRYWKĘ"
	start_btn.custom_minimum_size = Vector2(230, 44)
	UITheme.style_button(start_btn, Color(0.12, 0.42, 0.25, 1.0), UITheme.COLOR_SUCCESS_GREEN, 44, 16)
	start_btn.pressed.connect(func(): start_game_requested.emit())
	bottom_hbox.add_child(start_btn)

func _create_slot_card(slot_idx: int) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 52)
	
	var color_slot = GameState.SLOT_COLORS[slot_idx]
	var sb = UITheme.create_panel_style(
		Color(0.06, 0.09, 0.14, 0.85),
		color_slot.darkened(0.3),
		6, 1, 8
	)
	card.add_theme_stylebox_override("panel", sb)
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	
	var color_box = ColorRect.new()
	color_box.custom_minimum_size = Vector2(16, 32)
	color_box.color = color_slot
	row.add_child(color_box)
	
	var text_box = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	
	var base_title = Label.new()
	base_title.text = GameState.SLOT_NAMES[slot_idx]
	base_title.add_theme_font_size_override("font_size", 11)
	base_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	text_box.add_child(base_title)
	
	var p_name_lbl = Label.new()
	p_name_lbl.text = "Wolny slot"
	p_name_lbl.add_theme_font_size_override("font_size", 14)
	p_name_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	text_box.add_child(p_name_lbl)
	slot_name_lbls.append(p_name_lbl)
	
	var status_lbl = Label.new()
	status_lbl.text = "[WOLNY]"
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	row.add_child(status_lbl)
	slot_status_lbls.append(status_lbl)
	
	var btn_take = Button.new()
	btn_take.text = "Zajmij"
	btn_take.custom_minimum_size = Vector2(70, 30)
	UITheme.style_button(btn_take, Color(0.12, 0.22, 0.35), color_slot, 30, 12)
	btn_take.pressed.connect(func(): slot_selected.emit(slot_idx))
	row.add_child(btn_take)
	slot_buttons.append(btn_take)
	
	return card

func update_lobby_state(players: Array, is_host: bool, local_peer_id: int) -> void:
	if network_manager != null and not network_manager.room_code.is_empty():
		code_display_lbl.text = network_manager.room_code
		
	if is_host:
		header_title_lbl.text = "LOBBY ROZGRYWKI (JESTEŚ HOSTEM)"
		start_btn.visible = true
		public_checkbox.visible = true
		public_checkbox.disabled = false
	else:
		header_title_lbl.text = "LOBBY ROZGRYWKI (KLIENT)"
		start_btn.visible = false
		public_checkbox.visible = true
		public_checkbox.disabled = true
		
	if network_manager != null:
		public_checkbox.set_pressed_no_signal(network_manager.is_public)
		
	# Reset slots
	for i in range(GameState.MAX_PLAYERS):
		slot_name_lbls[i].text = "Wolny slot"
		slot_name_lbls[i].add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		slot_status_lbls[i].text = "[WOLNY]"
		slot_status_lbls[i].add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		slot_buttons[i].visible = true
		slot_buttons[i].disabled = false

	var all_ready = true
	for p in players:
		var slot_idx: int = p.slot
		if slot_idx >= 0 and slot_idx < GameState.MAX_PLAYERS:
			var is_me = (p.peer_id == local_peer_id)
			var name_display = p.name
			if is_me:
				name_display += " (TY)"
			if p.is_host:
				name_display += " 👑"
				
			slot_name_lbls[slot_idx].text = name_display
			slot_name_lbls[slot_idx].add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
			
			if p.is_host:
				slot_status_lbls[slot_idx].text = "[HOST]"
				slot_status_lbls[slot_idx].add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
			elif p.is_ready:
				slot_status_lbls[slot_idx].text = "[GOTOWY]"
				slot_status_lbls[slot_idx].add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
			else:
				slot_status_lbls[slot_idx].text = "[CZEKA]"
				slot_status_lbls[slot_idx].add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
				all_ready = false
				
			slot_buttons[slot_idx].visible = false

	# Update Ready button
	for p in players:
		if p.peer_id == local_peer_id:
			if p.is_host:
				ready_btn.visible = false
			else:
				ready_btn.visible = true
				if p.is_ready:
					ready_btn.text = "ZMIEŃ NA: NIEGOTOWY"
					UITheme.style_button(ready_btn, Color(0.35, 0.22, 0.12), UITheme.COLOR_WARNING_GOLD, 44, 15)
				else:
					ready_btn.text = "ZAZNACZ GOTOWOŚĆ"
					UITheme.style_button(ready_btn, UITheme.COLOR_PRIMARY, UITheme.COLOR_ACCENT_CYAN, 44, 15)

	if is_host:
		start_btn.disabled = not all_ready

func add_chat_entry(sender: String, message: String, is_system: bool = false) -> void:
	if is_system:
		chat_log.append_text("[color=#ffd166][b]📢 %s:[/b] %s[/color]\n" % [sender, message])
	else:
		chat_log.append_text("[color=#2ec4b6][b]%s:[/b][/color] %s\n" % [sender, message])

func _update_header_info() -> void:
	if network_manager == null:
		return
		
	var info_text = ""
	if network_manager.is_host:
		info_text = "Twoje IP Hosta: %s | Port: %d" % [network_manager.host_ip, network_manager.server_port]
	else:
		info_text = "Połączono z serwerem: %s:%d" % [network_manager.server_ip, network_manager.server_port]
		
	header_info_lbl.text = info_text
	code_display_lbl.text = network_manager.room_code if not network_manager.room_code.is_empty() else "------"

func _on_public_status_changed(is_pub: bool) -> void:
	public_checkbox.set_pressed_no_signal(is_pub)

func _on_public_toggled(button_pressed: bool) -> void:
	if network_manager != null and network_manager.is_host:
		network_manager.set_lobby_public(button_pressed)
		public_toggled.emit(button_pressed)

func _on_copy_code_pressed() -> void:
	if network_manager != null and not network_manager.room_code.is_empty():
		DisplayServer.clipboard_set(network_manager.room_code)
		copy_code_btn.text = "Skopiowano!"
		var timer = get_tree().create_timer(1.5)
		timer.timeout.connect(func():
			if copy_code_btn: copy_code_btn.text = "Kopiuj"
		)

func _on_chat_submitted(text: String) -> void:
	var clean = text.strip_edges()
	if not clean.is_empty():
		chat_submitted.emit(clean)
		chat_input.clear()

func _on_send_btn_pressed() -> void:
	_on_chat_submitted(chat_input.text)

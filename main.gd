# Main Entry Point & Orchestrator (100% Pure Code / Script-driven)
extends Node

var network_manager: NetworkManager
var current_view: Control = null
var current_phase: GameState.GamePhase = GameState.GamePhase.MENU

func _ready() -> void:
	randomize()
	
	# Instantiate Network Manager
	network_manager = NetworkManager.new()
	network_manager.name = "NetworkManager"
	add_child(network_manager)
	
	# Connect Network Signals
	network_manager.lobby_joined.connect(_on_lobby_joined)
	network_manager.player_list_updated.connect(_on_player_list_updated)
	network_manager.chat_message_received.connect(_on_chat_message_received)
	network_manager.match_started.connect(_on_match_started)
	network_manager.session_disconnected.connect(_on_session_disconnected)
	network_manager.connection_status_changed.connect(_on_connection_status_changed)
	
	# Display initial Menu
	show_menu_view()

# ==============================================================================
# View Switching & Scene Management
# ==============================================================================

func show_menu_view(status_msg: String = "", is_error: bool = false) -> void:
	current_phase = GameState.GamePhase.MENU
	_clear_current_view()
	
	var menu = MenuView.new(network_manager)
	menu.host_requested.connect(_on_host_requested)
	menu.join_by_code_requested.connect(_on_join_by_code_requested)
	menu.join_direct_requested.connect(_on_join_direct_requested)
	add_child(menu)
	current_view = menu
	
	if not status_msg.is_empty():
		menu.set_status(status_msg, is_error)

func show_lobby_view(is_host: bool) -> void:
	current_phase = GameState.GamePhase.LOBBY
	_clear_current_view()
	
	var lobby = LobbyView.new(network_manager)
	lobby.leave_lobby_requested.connect(_on_leave_lobby_requested)
	lobby.ready_toggled.connect(_on_ready_toggled)
	lobby.slot_selected.connect(_on_slot_selected)
	lobby.chat_submitted.connect(_on_chat_submitted)
	lobby.start_game_requested.connect(_on_start_game_requested)
	
	add_child(lobby)
	current_view = lobby
	
	lobby.update_lobby_state(
		network_manager.get_players_list(),
		is_host,
		multiplayer.get_unique_id()
	)

func show_game_view() -> void:
	current_phase = GameState.GamePhase.PLAYING
	_clear_current_view()
	
	var game_layer = Control.new()
	game_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.10, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_layer.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_layer.add_child(center)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 320)
	panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		UITheme.COLOR_PANEL_BG,
		UITheme.COLOR_ACCENT_CYAN,
		12, 2, 24
	))
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "⚔️ ROZGRYWKA ROZPOCZĘTA! ⚔️"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "Wszyscy gracze zostali pomyślnie zsynchronizowani w sesji ENet.\n\nGotowi do portowania mechanik RTS (ekonomia, mapa, jednostki, walka)."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MAIN)
	vbox.add_child(desc)
	
	var btn_back = Button.new()
	btn_back.text = "POWRÓT DO MENU (ROZŁĄCZ)"
	UITheme.style_button(btn_back, Color(0.35, 0.12, 0.14), UITheme.COLOR_DANGER_RED, 44, 15)
	btn_back.pressed.connect(func():
		network_manager.disconnect_session()
		show_menu_view("Rozłączono z gry.", false)
	)
	vbox.add_child(btn_back)
	
	add_child(game_layer)
	current_view = game_layer

func _clear_current_view() -> void:
	if current_view != null:
		current_view.queue_free()
		current_view = null

# ==============================================================================
# Signal Handlers — MenuView
# ==============================================================================

func _on_host_requested(port: int, player_name: String, is_public: bool, custom_ip: String) -> void:
	var err = network_manager.host_game(port, player_name, is_public, custom_ip)
	if err != OK and current_view is MenuView:
		(current_view as MenuView).set_controls_enabled(true)

func _on_join_by_code_requested(code: String, player_name: String) -> void:
	network_manager.join_by_code(code, player_name)

func _on_join_direct_requested(ip: String, port: int, player_name: String) -> void:
	var err = network_manager.join_game(ip, port, player_name)
	if err != OK and current_view is MenuView:
		(current_view as MenuView).set_controls_enabled(true)

# ==============================================================================
# Signal Handlers — NetworkManager
# ==============================================================================

func _on_connection_status_changed(message: String, is_error: bool) -> void:
	if current_view is MenuView:
		(current_view as MenuView).set_status(message, is_error)

func _on_lobby_joined(is_host: bool) -> void:
	show_lobby_view(is_host)

func _on_player_list_updated(players: Array) -> void:
	if current_view is LobbyView:
		(current_view as LobbyView).update_lobby_state(
			players,
			network_manager.is_host,
			multiplayer.get_unique_id()
		)

func _on_chat_message_received(sender: String, message: String, is_system: bool) -> void:
	if current_view is LobbyView:
		(current_view as LobbyView).add_chat_entry(sender, message, is_system)

func _on_match_started() -> void:
	show_game_view()

func _on_session_disconnected(reason: String) -> void:
	show_menu_view(reason, true)

# ==============================================================================
# Signal Handlers — LobbyView
# ==============================================================================

func _on_leave_lobby_requested() -> void:
	network_manager.disconnect_session("Opuszczono lobby.")
	show_menu_view("Opuszczono lobby.", false)

func _on_ready_toggled() -> void:
	network_manager.toggle_ready()

func _on_slot_selected(slot_index: int) -> void:
	network_manager.change_slot(slot_index)

func _on_chat_submitted(message: String) -> void:
	network_manager.send_chat(message)

func _on_start_game_requested() -> void:
	network_manager.start_match()

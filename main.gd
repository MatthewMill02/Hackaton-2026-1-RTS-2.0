# Main Entry Point & Orchestrator (100% Pure Code / Script-driven)
extends Node

var settings_manager: SettingsManager
var network_manager: NetworkManager
var ui_layer: CanvasLayer = null
var current_view: Control = null
var current_phase: GameState.GamePhase = GameState.GamePhase.MENU

func _ready() -> void:
	randomize()
	
	# 1. Initialize Persistent Settings & Apply Screen Display Mode
	settings_manager = SettingsManager.new()
	settings_manager.apply_display_mode()
	
	# 2. Setup UI Canvas Layer for automatic full viewport scaling
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)
	
	# 3. Instantiate Network Manager
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
	
	# 4. Display Initial Overwatch-style Main Menu
	show_menu_view()

# ==============================================================================
# View Switching & Scene Management
# ==============================================================================

func show_menu_view(status_msg: String = "", is_error: bool = false) -> void:
	current_phase = GameState.GamePhase.MENU
	_clear_current_view()
	
	var menu = MenuView.new(network_manager, settings_manager)
	menu.host_requested.connect(_on_host_requested)
	menu.join_by_code_requested.connect(_on_join_by_code_requested)
	menu.join_direct_requested.connect(_on_join_direct_requested)
	ui_layer.add_child(menu)
	current_view = menu
	
	if not status_msg.is_empty():
		menu.set_status(status_msg, is_error)

func show_lobby_view(is_host: bool) -> void:
	current_phase = GameState.GamePhase.LOBBY
	_clear_current_view()
	
	var lobby = LobbyView.new(network_manager, settings_manager)
	lobby.leave_lobby_requested.connect(_on_leave_lobby_requested)
	lobby.ready_toggled.connect(_on_ready_toggled)
	lobby.slot_selected.connect(_on_slot_selected)
	lobby.chat_submitted.connect(_on_chat_submitted)
	lobby.start_game_requested.connect(_on_start_game_requested)
	
	ui_layer.add_child(lobby)
	current_view = lobby
	
	lobby.update_lobby_state(
		network_manager.get_players_list(),
		is_host,
		multiplayer.get_unique_id()
	)

func show_game_view() -> void:
	current_phase = GameState.GamePhase.PLAYING
	_clear_current_view()
	
	var hud = InGameHUD.new(network_manager, settings_manager)
	hud.exit_to_menu_requested.connect(func():
		network_manager.disconnect_session()
		show_menu_view("Rozłączono z gry.", false)
	)
	hud.chat_sent.connect(func(msg):
		network_manager.send_chat(msg)
	)
	
	ui_layer.add_child(hud)
	current_view = hud

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
		(current_view as MenuView).set_status("Błąd tworzenia gry!", true)

func _on_join_by_code_requested(code: String, player_name: String) -> void:
	network_manager.join_by_code(code, player_name)

func _on_join_direct_requested(ip: String, port: int, player_name: String) -> void:
	var err = network_manager.join_game(ip, port, player_name)
	if err != OK and current_view is MenuView:
		(current_view as MenuView).set_status("Błąd połączenia z serwerem!", true)

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
	elif current_view is InGameHUD:
		if (current_view as InGameHUD).in_game_chat_log != null:
			if is_system:
				(current_view as InGameHUD).in_game_chat_log.append_text("[color=#ffd166][b]📢 %s:[/b] %s[/color]\n" % [sender, message])
			else:
				(current_view as InGameHUD).in_game_chat_log.append_text("[color=#00f0ff][b]%s:[/b][/color] %s\n" % [sender, message])

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

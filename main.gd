# Main Entry Point & Orchestrator (100% Pure Code / Script-driven)
extends Node

var settings_manager: SettingsManager
var network_manager: NetworkManager
var ui_layer: CanvasLayer = null
var current_view: Control = null
var current_phase: GameState.GamePhase = GameState.GamePhase.MENU
var active_map: MapData = null

# F3 Debug Overlay
var debug_layer: CanvasLayer = null
var debug_overlay: PanelContainer = null
var debug_lbl: Label = null
var is_debug_visible: bool = false

func _ready() -> void:
	randomize()
	
	# 1. Initialize Persistent Settings & Apply Screen Display Mode
	settings_manager = SettingsManager.new()
	settings_manager.apply_display_mode()
	
	# 2. Setup UI Canvas Layer for automatic full viewport scaling
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)
	
	# 3. Setup Top-level F3 Debug Layer
	_build_debug_overlay()
	
	# 4. Instantiate Network Manager
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
	network_manager.map_seed_synced.connect(_on_map_seed_synced)
	network_manager.match_settings_synced.connect(_on_match_settings_synced)
	
	# 5. Display Initial Overwatch-style Main Menu
	show_menu_view()

func _build_debug_overlay() -> void:
	debug_layer = CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 125
	add_child(debug_layer)
	
	debug_overlay = PanelContainer.new()
	debug_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	debug_overlay.position = Vector2(16, 16)
	debug_overlay.custom_minimum_size = Vector2(210, 0)
	debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.04, 0.07, 0.88), Color(1.0, 0.88, 0.15, 0.95), 4, 1.5, 6)
	debug_overlay.add_theme_stylebox_override("panel", sb)
	debug_overlay.visible = false
	debug_layer.add_child(debug_overlay)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay.add_child(margin)
	
	debug_lbl = Label.new()
	debug_lbl.add_theme_font_size_override("font_size", 13)
	debug_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.20)) # Yellow text
	debug_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(debug_lbl)

func _process(_delta: float) -> void:
	if is_debug_visible and debug_lbl != null:
		var fps = Engine.get_frames_per_second()
		var frame_ms = 1000.0 / maxf(1.0, float(fps))
		var tps = Engine.physics_ticks_per_second
		var mem_mb = OS.get_static_memory_usage() / (1024.0 * 1024.0)
		var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		
		debug_lbl.text = "⚡ FPS: %d (%.1f ms)\n⏱️ TPS: %d\n💾 RAM: %.1f MB\n🎨 Draw calls: %d" % [
			fps, frame_ms, tps, mem_mb, int(draw_calls)
		]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# F3: Toggle Yellow App Stats (FPS, TPS, RAM)
		if event.keycode == KEY_F3:
			is_debug_visible = not is_debug_visible
			if debug_overlay != null:
				debug_overlay.visible = is_debug_visible
			get_viewport().set_input_as_handled()
			
		# F11: Toggle Fullscreen
		elif event.keycode == KEY_F11:
			settings_manager.toggle_fullscreen()
			get_viewport().set_input_as_handled()

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
	
	# Generate new procedural 50x50 map for this lobby
	if is_host:
		active_map = MapGenerator.generate_map()
		network_manager.send_map_seed(active_map.seed_value)
	elif active_map == null:
		if network_manager.current_map_seed != 0:
			active_map = MapGenerator.generate_map(network_manager.current_map_seed)
		else:
			active_map = MapGenerator.generate_map()
	
	var lobby = LobbyView.new(network_manager, settings_manager, active_map)
	lobby.leave_lobby_requested.connect(_on_leave_lobby_requested)
	lobby.ready_toggled.connect(_on_ready_toggled)
	lobby.slot_selected.connect(_on_slot_selected)
	lobby.chat_submitted.connect(_on_chat_submitted)
	lobby.start_game_requested.connect(_on_start_game_requested)
	lobby.match_settings_changed.connect(_on_match_settings_changed)
	
	ui_layer.add_child(lobby)
	current_view = lobby
	
	lobby.update_lobby_state(
		network_manager.get_players_list(),
		is_host,
		multiplayer.get_unique_id()
	)

func _on_match_settings_changed(creative: bool, points: int, duration_min: int) -> void:
	network_manager.send_match_settings(creative, points, duration_min)

func _on_match_settings_synced(creative: bool, points: int, duration_min: int) -> void:
	if current_view is LobbyView:
		(current_view as LobbyView).sync_settings_ui(creative, points, duration_min)

func _on_map_seed_synced(seed_val: int) -> void:
	active_map = MapGenerator.generate_map(seed_val)
	if current_view is LobbyView:
		(current_view as LobbyView).set_map_data(active_map)

func show_game_view() -> void:
	current_phase = GameState.GamePhase.PLAYING
	_clear_current_view()
	
	if active_map == null:
		active_map = MapGenerator.generate_map()
		
	var hud = InGameHUD.new(network_manager, settings_manager, active_map)
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

# High-Level Multiplayer Manager using Godot 4 ENetMultiplayerPeer + UDP Discovery
class_name NetworkManager
extends Node

signal connection_status_changed(message: String, is_error: bool)
signal lobby_joined(is_host: bool)
signal player_list_updated(players: Array)
signal chat_message_received(sender_name: String, message: String, is_system: bool)
signal match_started()
signal session_disconnected(reason: String)
signal lobby_public_status_changed(is_public: bool)

var peer: ENetMultiplayerPeer = null
var discovery: LobbyDiscovery = null

var players: Dictionary = {} # peer_id: int -> PlayerData
var local_player: PlayerData = null
var local_player_data: PlayerData:
	get:
		return local_player
var is_host: bool = false
var host_ip: String = "127.0.0.1"
var server_ip: String = "127.0.0.1"
var server_port: int = GameState.DEFAULT_PORT
var room_code: String = ""
var is_public: bool = true

func _ready() -> void:
	discovery = LobbyDiscovery.new()
	discovery.name = "LobbyDiscovery"
	add_child(discovery)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ==============================================================================
# Public Interface
# ==============================================================================

func host_game(p_port: int, player_name: String, p_is_public: bool = true, p_host_ip: String = "") -> Error:
	disconnect_session()
	
	server_port = p_port
	is_host = true
	is_public = p_is_public
	room_code = RoomCodeHelper.generate_code()
	
	# Determine effective host IP (use custom provided or detect best Radmin/LAN)
	var chosen_ip = p_host_ip.strip_edges()
	if chosen_ip.is_empty():
		chosen_ip = get_preferred_host_ip()
	host_ip = chosen_ip
	server_ip = host_ip
	
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(server_port, GameState.MAX_PLAYERS)
	if err != OK:
		var err_msg = "Błąd tworzenia serwera na porcie %d (Kod: %d)" % [server_port, err]
		connection_status_changed.emit(err_msg, true)
		return err
	
	multiplayer.multiplayer_peer = peer
	
	# Host is peer_id 1, slot 0
	local_player = PlayerData.new(1, player_name, 0, true)
	players[1] = local_player
	
	# Start UDP beacon broadcaster with explicit host IP
	discovery.start_broadcaster(room_code, player_name, server_port, is_public, host_ip)
	
	connection_status_changed.emit("Serwer uruchomiony! IP: %s | Kod: %s" % [host_ip, room_code], false)
	lobby_joined.emit(true)
	player_list_updated.emit(get_players_list())
	chat_message_received.emit("SYSTEM", "Pokój utworzony! Twoje IP: [b]%s[/b], Kod: [b]%s[/b]" % [host_ip, room_code], true)
	return OK

func join_game(p_ip: String, p_port: int, player_name: String) -> Error:
	disconnect_session()
	
	server_ip = p_ip.strip_edges()
	if server_ip.is_empty():
		server_ip = "127.0.0.1"
		
	server_port = p_port
	is_host = false
	
	local_player = PlayerData.new(0, player_name, -1, false)
	
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(server_ip, server_port)
	if err != OK:
		var err_msg = "Nie można połączyć z %s:%d (Kod: %d)" % [server_ip, server_port, err]
		connection_status_changed.emit(err_msg, true)
		return err
		
	multiplayer.multiplayer_peer = peer
	connection_status_changed.emit("Łączenie z %s:%d..." % [server_ip, server_port], false)
	return OK

func join_by_code(code: String, player_name: String) -> void:
	var clean = RoomCodeHelper.normalize(code)
	if clean.length() != RoomCodeHelper.CODE_LENGTH:
		connection_status_changed.emit("Nieprawidłowy kod pokoju! Wpisz 6 liter.", true)
		return
		
	var lobby_info = discovery.get_lobby_by_code(clean)
	if not lobby_info.is_empty():
		var target_ip = str(lobby_info.get("ip", "127.0.0.1"))
		var target_port = int(lobby_info.get("port", server_port))
		connection_status_changed.emit("Znaleziono pokój %s (%s:%d)! Łączenie..." % [clean, target_ip, target_port], false)
		join_game(target_ip, target_port, player_name)
		return
		
	connection_status_changed.emit("Szukanie pokoju %s w sieci..." % clean, false)
	discovery.query_room_code(clean)
	
	var timer = get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		var info = discovery.get_lobby_by_code(clean)
		if not info.is_empty():
			var target_ip = str(info.get("ip", "127.0.0.1"))
			var target_port = int(info.get("port", server_port))
			join_game(target_ip, target_port, player_name)
		else:
			connection_status_changed.emit("Nie znaleziono pokoju %s. Upewnij się, że jesteście w tej samej sieci Radmin VPN." % clean, true)
	)

func set_lobby_public(p_is_public: bool) -> void:
	if not multiplayer.is_server():
		return
		
	is_public = p_is_public
	discovery.update_broadcaster(is_public, players.size())
	rpc("sync_lobby_settings", room_code, is_public)
	lobby_public_status_changed.emit(is_public)

func disconnect_session(reason: String = "") -> void:
	if discovery != null:
		discovery.stop()
		
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	peer = null
	players.clear()
	is_host = false
	local_player = null
	room_code = ""
	
	if not reason.is_empty():
		session_disconnected.emit(reason)

func toggle_ready() -> void:
	if local_player == null:
		return
		
	var new_ready = not local_player.is_ready
	rpc("set_player_ready", multiplayer.get_unique_id(), new_ready)

func change_slot(desired_slot: int) -> void:
	if local_player == null or desired_slot < 0 or desired_slot >= GameState.MAX_PLAYERS:
		return
	if multiplayer.is_server():
		_perform_slot_change(1, desired_slot)
	else:
		rpc_id(1, "request_slot_change", multiplayer.get_unique_id(), desired_slot)

func send_chat(message: String) -> void:
	var clean_msg = message.strip_edges()
	if clean_msg.is_empty() or local_player == null:
		return
	rpc("receive_chat", local_player.name, clean_msg, false)

func start_match() -> void:
	if not multiplayer.is_server():
		return
		
	for p_id in players:
		var p: PlayerData = players[p_id]
		if not p.is_ready and not p.is_host:
			chat_message_received.emit("SYSTEM", "Nie wszyscy gracze są gotowi!", true)
			return
			
	rpc("trigger_match_start")

func get_players_list() -> Array:
	var list: Array = []
	for p_id in players:
		list.append(players[p_id])
	list.sort_custom(func(a: PlayerData, b: PlayerData): return a.slot < b.slot)
	return list

func get_available_local_ips() -> Array[String]:
	var ips: Array[String] = []
	for ip_str in IP.get_local_addresses():
		if ":" not in ip_str and ip_str != "127.0.0.1":
			ips.append(ip_str)
	return ips

func get_preferred_host_ip() -> String:
	var ips = get_available_local_ips()
	# 1. Look for Radmin VPN (starts with 26.)
	for ip_str in ips:
		if ip_str.begins_with("26."):
			return ip_str
	# 2. Look for standard LAN (192.168. or 10.)
	for ip_str in ips:
		if ip_str.begins_with("192.168.") or ip_str.begins_with("10."):
			return ip_str
	# 3. Fallback
	if not ips.is_empty():
		return ips[0]
	return "127.0.0.1"

# ==============================================================================
# Godot Multiplayer Signal Callbacks
# ==============================================================================

func _on_peer_connected(id: int) -> void:
	print("[Network] Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: ", id)
	if multiplayer.is_server():
		if players.has(id):
			var leaving_player: PlayerData = players[id]
			var leave_name = leaving_player.name
			players.erase(id)
			_broadcast_player_list()
			discovery.update_broadcaster(is_public, players.size())
			rpc("receive_chat", "SYSTEM", "%s opuścił lobby." % leave_name, true)

func _on_connected_to_server() -> void:
	print("[Network] Connected to server successfully.")
	local_player.peer_id = multiplayer.get_unique_id()
	connection_status_changed.emit("Połączono z serwerem!", false)
	lobby_joined.emit(false)
	
	rpc_id(1, "register_player", local_player.to_dict())

func _on_connection_failed() -> void:
	print("[Network] Connection failed.")
	disconnect_session("Nie udało się nawiązać połączenia z serwerem.")

func _on_server_disconnected() -> void:
	print("[Network] Server disconnected.")
	disconnect_session("Serwer został zamknięty przez hosta.")

# ==============================================================================
# RPC Methods
# ==============================================================================

@rpc("any_peer", "reliable")
func register_player(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	var new_player = PlayerData.from_dict(data)
	new_player.peer_id = sender_id
	new_player.is_host = false
	
	var used_slots: Array[int] = []
	for p in players.values():
		used_slots.append(p.slot)
		
	var assigned_slot = 0
	for i in range(GameState.MAX_PLAYERS):
		if not used_slots.has(i):
			assigned_slot = i
			break
			
	new_player.slot = assigned_slot
	new_player.color = GameState.SLOT_COLORS[assigned_slot]
	
	players[sender_id] = new_player
	
	_broadcast_player_list()
	discovery.update_broadcaster(is_public, players.size())
	
	rpc_id(sender_id, "sync_lobby_settings", room_code, is_public)
	rpc("receive_chat", "SYSTEM", "%s dołączył do lobby!" % new_player.name, true)

@rpc("any_peer", "call_local", "reliable")
func request_slot_change(sender_id: int, target_slot: int) -> void:
	if not multiplayer.is_server():
		return
	_perform_slot_change(sender_id, target_slot)

func _perform_slot_change(sender_id: int, target_slot: int) -> void:
	if not multiplayer.is_server():
		return
		
	if target_slot < 0 or target_slot >= GameState.MAX_PLAYERS:
		return
		
	for p in players.values():
		if p.slot == target_slot and p.peer_id != sender_id:
			return
			
	if players.has(sender_id):
		var p: PlayerData = players[sender_id]
		p.slot = target_slot
		p.color = GameState.SLOT_COLORS[target_slot]
		if sender_id == multiplayer.get_unique_id() and local_player != null:
			local_player.slot = target_slot
			local_player.color = GameState.SLOT_COLORS[target_slot]
		_broadcast_player_list()
		var slot_names = ["Niebieską (Baza 1)", "Czerwoną (Baza 2)", "Zieloną (Baza 3)", "Żółtą (Baza 4)"]
		var s_name = slot_names[target_slot] if target_slot < slot_names.size() else "Bazę %d" % (target_slot + 1)
		rpc("receive_chat", "GRACZ", "%s wybrał %s!" % [p.name, s_name], true)

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(p_id: int, ready_val: bool) -> void:
	if players.has(p_id):
		players[p_id].is_ready = ready_val
		if p_id == multiplayer.get_unique_id() and local_player != null:
			local_player.is_ready = ready_val
		player_list_updated.emit(get_players_list())
		
		if multiplayer.is_server():
			_broadcast_player_list()
			rpc("receive_chat", "GRACZ", "%s jest %s!" % [players[p_id].name, "GOTOWY" if ready_val else "NIEGOTOWY"], true)

@rpc("authority", "reliable")
func sync_player_list(players_array: Array) -> void:
	players.clear()
	for p_dict in players_array:
		var p = PlayerData.from_dict(p_dict)
		players[p.peer_id] = p
		if p.peer_id == multiplayer.get_unique_id():
			local_player = p
			
	player_list_updated.emit(get_players_list())

@rpc("authority", "reliable")
func sync_lobby_settings(p_code: String, p_is_public: bool) -> void:
	room_code = p_code
	is_public = p_is_public
	lobby_public_status_changed.emit(is_public)

@rpc("any_peer", "call_local", "reliable")
func receive_chat(sender: String, msg: String, is_sys: bool) -> void:
	chat_message_received.emit(sender, msg, is_sys)

@rpc("authority", "call_local", "reliable")
func trigger_match_start() -> void:
	chat_message_received.emit("START", "Gra rozpoczęta! Przygotuj swoje jednostki i broń bazy!", true)
	match_started.emit()

# ==============================================================================
# Helper Methods
# ==============================================================================

func _broadcast_player_list() -> void:
	if not multiplayer.is_server():
		return
		
	var arr: Array = []
	for p in players.values():
		arr.append(p.to_dict())
		
	rpc("sync_player_list", arr)
	player_list_updated.emit(get_players_list())

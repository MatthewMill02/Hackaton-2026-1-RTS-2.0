# LAN and Radmin VPN UDP Beacon Discovery for Public Lobbies and Room Codes
class_name LobbyDiscovery
extends Node

signal lobbies_updated(public_lobbies: Array)
signal lobby_found_by_code(lobby_info: Dictionary)

const DISCOVERY_PORT: int = 7778
const BEACON_INTERVAL: float = 1.0
const LOBBY_EXPIRY_MS: int = 4000

var udp_peer: PacketPeerUDP = null
var is_broadcasting: bool = false
var is_listening: bool = false

# Host state
var room_code: String = ""
var host_name: String = "Host"
var host_ip: String = ""
var game_port: int = GameState.DEFAULT_PORT
var is_public: bool = true
var current_players: int = 1
var max_players: int = GameState.MAX_PLAYERS
var beacon_timer: float = 0.0

# Listener state
var discovered_lobbies: Dictionary = {} # code: String -> Dictionary

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if is_broadcasting:
		beacon_timer += delta
		if beacon_timer >= BEACON_INTERVAL:
			beacon_timer = 0.0
			_send_broadcast_beacon()
			
	if is_listening or is_broadcasting:
		_poll_incoming_packets()
		
	if is_listening:
		_prune_expired_lobbies()

# ==============================================================================
# Broadcaster (Host)
# ==============================================================================

func start_broadcaster(p_code: String, p_host_name: String, p_game_port: int, p_is_public: bool, p_host_ip: String = "") -> void:
	stop()
	
	room_code = p_code
	host_name = p_host_name
	game_port = p_game_port
	is_public = p_is_public
	host_ip = p_host_ip.strip_edges()
	current_players = 1
	beacon_timer = 0.0
	
	udp_peer = PacketPeerUDP.new()
	udp_peer.set_broadcast_enabled(true)
	udp_peer.bind(DISCOVERY_PORT)
	is_broadcasting = true
	
	_send_broadcast_beacon()

func update_broadcaster(p_is_public: bool, p_players_count: int) -> void:
	is_public = p_is_public
	current_players = p_players_count
	if is_broadcasting:
		_send_broadcast_beacon()

func _send_broadcast_beacon() -> void:
	if udp_peer == null or not is_broadcasting:
		return
		
	var packet_dict = {
		"type": "beacon",
		"code": room_code,
		"host_name": host_name,
		"ip": host_ip,
		"port": game_port,
		"players": current_players,
		"max_players": max_players,
		"is_public": is_public
	}
	
	var json_str = JSON.stringify(packet_dict)
	var bytes = json_str.to_utf8_buffer()
	
	# Broadcast to generic LAN broadcast
	udp_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	udp_peer.put_packet(bytes)
	
	# Explicit broadcast to Radmin VPN broadcast address if host IP is Radmin
	if host_ip.begins_with("26."):
		udp_peer.set_dest_address("26.255.255.255", DISCOVERY_PORT)
		udp_peer.put_packet(bytes)
	
	# Also send to detected local subnet broadcasts
	for ip_str in IP.get_local_addresses():
		if ":" not in ip_str and ip_str != "127.0.0.1":
			var parts = ip_str.split(".")
			if parts.size() == 4:
				var subnet_broadcast = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
				udp_peer.set_dest_address(subnet_broadcast, DISCOVERY_PORT)
				udp_peer.put_packet(bytes)

# ==============================================================================
# Listener (Client / Menu Browser)
# ==============================================================================

func start_listener() -> void:
	if is_listening:
		return
		
	stop()
	discovered_lobbies.clear()
	
	udp_peer = PacketPeerUDP.new()
	udp_peer.set_broadcast_enabled(true)
	var err = udp_peer.bind(DISCOVERY_PORT)
	if err != OK:
		print("[Discovery] Info: Binding discovery port %d returned code: %d" % [DISCOVERY_PORT, err])
		
	is_listening = true
	request_refresh()

func request_refresh() -> void:
	if udp_peer == null:
		return
		
	var query_dict = {
		"type": "query_all"
	}
	var bytes = JSON.stringify(query_dict).to_utf8_buffer()
	udp_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	udp_peer.put_packet(bytes)
	
	# Also query Radmin broadcast if any local IP is Radmin
	for ip_str in IP.get_local_addresses():
		if ip_str.begins_with("26."):
			udp_peer.set_dest_address("26.255.255.255", DISCOVERY_PORT)
			udp_peer.put_packet(bytes)

func query_room_code(code: String) -> void:
	var clean_code = RoomCodeHelper.normalize(code)
	if clean_code.is_empty() or udp_peer == null:
		return
		
	var query_dict = {
		"type": "query_code",
		"code": clean_code
	}
	var bytes = JSON.stringify(query_dict).to_utf8_buffer()
	udp_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	udp_peer.put_packet(bytes)
	
	for ip_str in IP.get_local_addresses():
		if ip_str.begins_with("26."):
			udp_peer.set_dest_address("26.255.255.255", DISCOVERY_PORT)
			udp_peer.put_packet(bytes)

func get_public_lobbies() -> Array:
	var list: Array = []
	for code in discovered_lobbies:
		var entry: Dictionary = discovered_lobbies[code]
		if entry.get("is_public", true) == true:
			list.append(entry)
	return list

func get_lobby_by_code(code: String) -> Dictionary:
	var clean_code = RoomCodeHelper.normalize(code)
	if discovered_lobbies.has(clean_code):
		return discovered_lobbies[clean_code]
	return {}

# ==============================================================================
# Packet Handling & Cleanup
# ==============================================================================

func _poll_incoming_packets() -> void:
	if udp_peer == null:
		return
		
	while udp_peer.get_available_packet_count() > 0:
		var sender_ip = udp_peer.get_packet_ip()
		var sender_port = udp_peer.get_packet_port()
		var raw_data = udp_peer.get_packet().get_string_from_utf8()
		
		var json = JSON.new()
		var parse_err = json.parse(raw_data)
		if parse_err != OK:
			continue
			
		var data = json.data
		if not (data is Dictionary):
			continue
			
		var type = str(data.get("type", ""))
		
		# Host answering queries
		if is_broadcasting and (type == "query_all" or (type == "query_code" and data.get("code") == room_code)):
			_send_direct_reply(sender_ip, sender_port)
			continue
			
		# Client receiving beacon or reply
		if is_listening and (type == "beacon" or type == "reply"):
			var code = str(data.get("code", ""))
			if code.is_empty():
				continue
				
			# Prioritize explicit announced IP from host (e.g. Radmin IP 26.x.x.x)
			var announced_ip = str(data.get("ip", "")).strip_edges()
			var resolved_ip = announced_ip if not announced_ip.is_empty() and announced_ip != "127.0.0.1" else sender_ip
			
			var lobby_entry = {
				"code": code,
				"host_name": str(data.get("host_name", "Host")),
				"ip": resolved_ip,
				"port": int(data.get("port", GameState.DEFAULT_PORT)),
				"players": int(data.get("players", 1)),
				"max_players": int(data.get("max_players", GameState.MAX_PLAYERS)),
				"is_public": bool(data.get("is_public", true)),
				"updated_at": Time.get_ticks_msec()
			}
			
			discovered_lobbies[code] = lobby_entry
			lobbies_updated.emit(get_public_lobbies())
			lobby_found_by_code.emit(lobby_entry)

func _send_direct_reply(dest_ip: String, dest_port: int) -> void:
	if udp_peer == null or not is_broadcasting:
		return
		
	var reply_dict = {
		"type": "reply",
		"code": room_code,
		"host_name": host_name,
		"ip": host_ip,
		"port": game_port,
		"players": current_players,
		"max_players": max_players,
		"is_public": is_public
	}
	var bytes = JSON.stringify(reply_dict).to_utf8_buffer()
	udp_peer.set_dest_address(dest_ip, dest_port)
	udp_peer.put_packet(bytes)

func _prune_expired_lobbies() -> void:
	var now = Time.get_ticks_msec()
	var to_remove: Array[String] = []
	for code in discovered_lobbies:
		var entry = discovered_lobbies[code]
		if now - entry.get("updated_at", 0) > LOBBY_EXPIRY_MS:
			to_remove.append(code)
			
	if not to_remove.is_empty():
		for code in to_remove:
			discovered_lobbies.erase(code)
		lobbies_updated.emit(get_public_lobbies())

func stop() -> void:
	if udp_peer != null:
		udp_peer.close()
		udp_peer = null
	is_broadcasting = false
	is_listening = false
	discovered_lobbies.clear()

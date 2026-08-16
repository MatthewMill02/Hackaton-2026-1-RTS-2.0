# Data container for player information in network sessions
class_name PlayerData
extends RefCounted

var peer_id: int = 1
var name: String = "Gracz"
var slot: int = 0
var color: Color = Color(0.18, 0.77, 1.0, 1.0)
var is_ready: bool = false
var is_host: bool = false
var is_bot: bool = false
var bot_difficulty: int = 2 # 1: Łatwy, 2: Normalny, 3: Trudny, 4: Ekspert, 5: Koszmar
var ping: int = 0

func _init(p_id: int = 1, p_name: String = "Gracz", p_slot: int = 0, p_is_host: bool = false, p_is_bot: bool = false) -> void:
	peer_id = p_id
	name = p_name
	slot = p_slot
	is_host = p_is_host
	is_bot = p_is_bot
	is_ready = p_is_host or p_is_bot  # Host and bots are ready by default
	if slot >= 0 and slot < GameState.SLOT_COLORS.size():
		color = GameState.SLOT_COLORS[slot]

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": name,
		"slot": slot,
		"color": [color.r, color.g, color.b, color.a],
		"is_ready": is_ready,
		"is_host": is_host,
		"is_bot": is_bot,
		"bot_difficulty": bot_difficulty,
		"ping": ping
	}

static func from_dict(data: Dictionary) -> PlayerData:
	var player = PlayerData.new(
		int(data.get("peer_id", 1)),
		str(data.get("name", "Gracz")),
		int(data.get("slot", 0)),
		bool(data.get("is_host", false)),
		bool(data.get("is_bot", false))
	)
	player.is_ready = bool(data.get("is_ready", false))
	player.bot_difficulty = int(data.get("bot_difficulty", 2))
	player.ping = int(data.get("ping", 0))
	
	var c_arr = data.get("color", [])
	if c_arr is Array and c_arr.size() >= 4:
		player.color = Color(c_arr[0], c_arr[1], c_arr[2], c_arr[3])
	elif player.slot >= 0 and player.slot < GameState.SLOT_COLORS.size():
		player.color = GameState.SLOT_COLORS[player.slot]
		
	return player

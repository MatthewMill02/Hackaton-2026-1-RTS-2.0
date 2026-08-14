# Persistent Settings Manager (Nick, Resolution / Fullscreen, Map Scroll Speed, Radmin IP)
class_name SettingsManager
extends RefCounted

const SAVE_PATH: String = "user://settings.cfg"

var player_name: String = ""
var map_scroll_speed: float = 1.0
var window_mode: int = 0 # 0: Fullscreen (F11), 1: Maximized, 2: Windowed 1920x1080, 3: Windowed 1280x720
var custom_host_ip: String = ""
var custom_port: int = GameState.DEFAULT_PORT

# Match settings
var creative_mode: bool = false
var victory_points: int = 1200
var match_duration_min: int = 45

func _init() -> void:
	load_settings()

func _generate_default_nick() -> String:
	return "Pracownik-umowa-zlecenie#%d" % randi_range(1, 1000)

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		var saved_name = config.get_value("player", "name", "")
		if saved_name.is_empty() or saved_name == "MatthewMill":
			player_name = _generate_default_nick()
		else:
			player_name = saved_name
		map_scroll_speed = float(config.get_value("gameplay", "scroll_speed", 1.0))
		window_mode = int(config.get_value("display", "window_mode", 0))
		custom_host_ip = str(config.get_value("network", "custom_ip", ""))
		custom_port = int(config.get_value("network", "port", GameState.DEFAULT_PORT))
		creative_mode = bool(config.get_value("match", "creative", false))
		victory_points = int(config.get_value("match", "points", 1200))
		match_duration_min = int(config.get_value("match", "duration", 45))
	else:
		player_name = _generate_default_nick()

func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("gameplay", "scroll_speed", map_scroll_speed)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("network", "custom_ip", custom_host_ip)
	config.set_value("network", "port", custom_port)
	config.set_value("match", "creative", creative_mode)
	config.set_value("match", "points", victory_points)
	config.set_value("match", "duration", match_duration_min)
	config.save(SAVE_PATH)

func apply_display_mode() -> void:
	match window_mode:
		0: # Fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1: # Maximized
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2: # 1920x1080 Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		3: # 1280x720 Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(1280, 720))

func toggle_fullscreen() -> void:
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		window_mode = 1 # Return to maximized / windowed
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	else:
		window_mode = 0 # Fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	save_settings()

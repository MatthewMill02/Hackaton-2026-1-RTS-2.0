# Persistent Settings Manager (Nick, Resolution, Map Scroll Speed, Radmin IP)
class_name SettingsManager
extends RefCounted

const SAVE_PATH: String = "user://settings.cfg"

var player_name: String = "MatthewMill"
var map_scroll_speed: float = 1.0
var window_mode: int = 0 # 0: Auto (Fullscreen/Maximized), 1: Windowed 1920x1080, 2: Windowed 1280x720
var custom_host_ip: String = ""
var custom_port: int = GameState.DEFAULT_PORT

# Match settings
var creative_mode: bool = false
var victory_points: int = 1200
var match_duration_min: int = 45

func _init() -> void:
	load_settings()

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		player_name = config.get_value("player", "name", "MatthewMill")
		map_scroll_speed = float(config.get_value("gameplay", "scroll_speed", 1.0))
		window_mode = int(config.get_value("display", "window_mode", 0))
		custom_host_ip = str(config.get_value("network", "custom_ip", ""))
		custom_port = int(config.get_value("network", "port", GameState.DEFAULT_PORT))
		creative_mode = bool(config.get_value("match", "creative", false))
		victory_points = int(config.get_value("match", "points", 1200))
		match_duration_min = int(config.get_value("match", "duration", 45))
	else:
		# First run: pick random suffix if default
		if player_name == "MatthewMill":
			pass

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
		0: # Auto / Maximized
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		1: # 1920x1080 Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		2: # 1280x720 Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(1280, 720))

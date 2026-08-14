# In-Game Tactical HUD, 50x50 Map View, HQ & Drone Spawn, and ESC Modal
class_name InGameHUD
extends Control

signal exit_to_menu_requested()
signal chat_sent(msg: String)

var network_manager: NetworkManager
var settings_manager: SettingsManager
var active_map: MapData

# Resources (dynamic simulation)
var stone: int = 200
var iron: int = 100
var oil: int = 50
var redstone: int = 0
var max_storage: int = 300
var power_production: int = 645
var power_consumption: int = 595
var power_capacity: int = 1000

# Match Stats
var match_timer_seconds: float = 45 * 60
var current_score: int = 0
var target_score: int = 1200
var is_paused: bool = false

# UI Labels
var res_stone_lbl: Label
var res_iron_lbl: Label
var res_oil_lbl: Label
var res_redstone_lbl: Label
var power_lbl: Label
var player_name_lbl: Label
var timer_lbl: Label
var score_lbl: Label

# Map View
var map_viewport: Control
var map_camera_pos: Vector2 = Vector2.ZERO
var map_zoom: float = 1.0
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
const TILE_PX: float = 48.0 # Base tile size in pixels

# Textures
var hq_texture: Texture2D = null
var worker_textures: Array[Texture2D] = []

# Game Entities
class PlacedBuilding:
	var type_name: String
	var slot: int
	var grid_pos: Vector2i
	var size_tiles: Vector2i
	var hp: int
	var max_hp: int

class UnitEntity:
	var type_name: String
	var slot: int
	var world_pos: Vector2
	var target_pos: Vector2
	var hp: int
	var selected: bool = false

var buildings: Array[PlacedBuilding] = []
var units: Array[UnitEntity] = []

# In-Game Chat
var in_game_chat_log: RichTextLabel
var in_game_chat_input: LineEdit
var active_settings_modal: SettingsModal = null

func _init(p_net: NetworkManager = null, p_settings: SettingsManager = null, p_map: MapData = null) -> void:
	network_manager = p_net
	settings_manager = p_settings
	if p_map != null:
		active_map = p_map
	else:
		active_map = MapGenerator.generate_map()
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_load_assets()
	_spawn_initial_hq_and_drones()
	_build_ui()
	_center_camera_on_player_base()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_toggle_esc_settings_modal()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T and not in_game_chat_input.has_focus():
			in_game_chat_input.grab_focus()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_paused:
		if match_timer_seconds > 0:
			match_timer_seconds -= delta
			_update_timer_display()
			
		# Move units towards targets
		for u in units:
			if u.world_pos.distance_to(u.target_pos) > 2.0:
				u.world_pos = u.world_pos.move_toward(u.target_pos, 120.0 * delta)
				if map_viewport: map_viewport.queue_redraw()
		
	# Keyboard map pan
	var pan_speed = 500.0 * (settings_manager.map_scroll_speed if settings_manager else 1.0)
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x -= 1
	
	if move != Vector2.ZERO:
		map_camera_pos += move * pan_speed * delta
		if map_viewport: map_viewport.queue_redraw()

func _load_assets() -> void:
	hq_texture = UITheme.load_texture_safe("res://public/sprites/buildings/building_hq.png")
	
	worker_textures.clear()
	for i in range(4):
		var w_tex = UITheme.load_texture_safe("res://public/sprites/units/unit_worker_p%d.png" % i)
		worker_textures.append(w_tex)

func _spawn_initial_hq_and_drones() -> void:
	buildings.clear()
	units.clear()
	
	var my_slot = 0
	if network_manager != null and network_manager.local_player_data != null:
		my_slot = network_manager.local_player_data.slot
		
	# Spawn HQ for all base slots
	for b_spawn in active_map.bases:
		var hq = PlacedBuilding.new()
		hq.type_name = "Kwatera Główna"
		hq.slot = b_spawn.slot
		hq.grid_pos = b_spawn.grid_pos
		hq.size_tiles = Vector2i(3, 3)
		hq.hp = 2500
		hq.max_hp = 2500
		buildings.append(hq)
		
		# Spawn controllable Drone (Worker) next to HQ
		var drone = UnitEntity.new()
		drone.type_name = "Dron"
		drone.slot = b_spawn.slot
		var spawn_world = Vector2((b_spawn.grid_pos.x + 2.0) * TILE_PX, (b_spawn.grid_pos.y + 2.0) * TILE_PX)
		drone.world_pos = spawn_world
		drone.target_pos = spawn_world
		drone.hp = 150
		drone.selected = (b_spawn.slot == my_slot)
		units.append(drone)

func _center_camera_on_player_base() -> void:
	var my_slot = 0
	if network_manager != null and network_manager.local_player_data != null:
		my_slot = network_manager.local_player_data.slot
	if my_slot >= 0 and my_slot < active_map.bases.size():
		var b_pos = active_map.bases[my_slot].grid_pos
		var vp_size = get_viewport_rect().size
		map_camera_pos = vp_size * 0.5 - Vector2(b_pos.x * TILE_PX, b_pos.y * TILE_PX)

func _build_ui() -> void:
	# 1. 2D Map Canvas (Background layer)
	map_viewport = Control.new()
	map_viewport.set_anchors_preset(PRESET_FULL_RECT)
	map_viewport.draw.connect(_on_map_draw)
	map_viewport.gui_input.connect(_on_map_gui_input)
	add_child(map_viewport)
	
	# 2. TOP BAR (Resource Dashboard + Match Timer & Score)
	var top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 64)
	var top_sb = StyleBoxFlat.new()
	top_sb.bg_color = Color(0.02, 0.04, 0.08, 0.90)
	top_sb.content_margin_left = 20
	top_sb.content_margin_right = 20
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 28)
	top_bar.add_child(top_hbox)
	
	# Left: Resources Box
	var res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 3)
	top_hbox.add_child(res_box)
	
	var res_row1 = HBoxContainer.new()
	res_row1.add_theme_constant_override("separation", 20)
	res_box.add_child(res_row1)
	
	res_stone_lbl = Label.new()
	res_stone_lbl.text = "● %d/%d" % [stone, max_storage]
	res_stone_lbl.add_theme_font_size_override("font_size", 16)
	res_stone_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	res_row1.add_child(res_stone_lbl)
	
	res_iron_lbl = Label.new()
	res_iron_lbl.text = "● %d/%d" % [iron, max_storage]
	res_iron_lbl.add_theme_font_size_override("font_size", 16)
	res_iron_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	res_row1.add_child(res_iron_lbl)
	
	res_oil_lbl = Label.new()
	res_oil_lbl.text = "● %d/%d" % [oil, max_storage]
	res_oil_lbl.add_theme_font_size_override("font_size", 16)
	res_oil_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	res_row1.add_child(res_oil_lbl)
	
	res_redstone_lbl = Label.new()
	res_redstone_lbl.text = "● %d/%d" % [redstone, max_storage]
	res_redstone_lbl.add_theme_font_size_override("font_size", 16)
	res_redstone_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	res_row1.add_child(res_redstone_lbl)
	
	var res_row2 = HBoxContainer.new()
	res_row2.add_theme_constant_override("separation", 16)
	res_box.add_child(res_row2)
	
	power_lbl = Label.new()
	power_lbl.text = "⚡ +%d | %d/%d kW" % [power_production - power_consumption, power_production, power_capacity]
	power_lbl.add_theme_font_size_override("font_size", 14)
	power_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	res_row2.add_child(power_lbl)
	
	player_name_lbl = Label.new()
	player_name_lbl.text = settings_manager.player_name if settings_manager else "Gracz 1"
	player_name_lbl.add_theme_font_size_override("font_size", 14)
	player_name_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	res_row2.add_child(player_name_lbl)
	
	var spacer_t = Control.new()
	spacer_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer_t)
	
	# Right: Timer & Score
	var score_box = VBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_child(score_box)
	
	timer_lbl = Label.new()
	timer_lbl.text = "44:57"
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_lbl.add_theme_font_size_override("font_size", 22)
	timer_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_box.add_child(timer_lbl)
	
	score_lbl = Label.new()
	score_lbl.text = "★ 0 / 1200 pkt"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.add_theme_font_size_override("font_size", 15)
	score_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	score_box.add_child(score_lbl)
	
	var btn_menu = Button.new()
	btn_menu.text = "MENU"
	btn_menu.custom_minimum_size = Vector2(90, 40)
	UITheme.style_button(btn_menu, Color(0.12, 0.24, 0.38), UITheme.COLOR_ACCENT_CYAN, 40, 16)
	btn_menu.pressed.connect(_toggle_esc_settings_modal)
	top_hbox.add_child(btn_menu)
	
	# 3. LEFT BUILD BAR
	_build_left_construction_panel()
	
	# 4. BOTTOM CHAT OVERLAY & HINTS
	_build_in_game_chat_overlay()
	
	# 5. BOTTOM RIGHT MINIMAP
	_build_minimap_box()

func _build_left_construction_panel() -> void:
	var build_panel = PanelContainer.new()
	build_panel.set_anchors_preset(PRESET_TOP_LEFT)
	build_panel.position = Vector2(16, 80)
	build_panel.custom_minimum_size = Vector2(180, 0)
	
	var sb = UITheme.create_panel_style(Color(0.04, 0.07, 0.12, 0.92), Color(0.14, 0.28, 0.44, 0.7), 4, 1, 8)
	build_panel.add_theme_stylebox_override("panel", sb)
	add_child(build_panel)
	
	var bvbox = VBoxContainer.new()
	bvbox.add_theme_constant_override("separation", 6)
	build_panel.add_child(bvbox)
	
	var building_items = [
		{"name": "Kopalnia Kamienia", "color": UITheme.COLOR_PRIMARY},
		{"name": "Kopalnia Żelaza", "color": UITheme.COLOR_PRIMARY},
		{"name": "Pylon", "color": UITheme.COLOR_PRIMARY},
		{"name": "Fabryka", "color": UITheme.COLOR_PRIMARY},
		{"name": "Magazyn", "color": UITheme.COLOR_PRIMARY},
		{"name": "Mur", "color": UITheme.COLOR_PRIMARY},
		{"name": "Wieżyczka", "color": UITheme.COLOR_PRIMARY},
		{"name": "Elektrownia", "color": UITheme.COLOR_PRIMARY},
		{"name": "Bank Energii", "color": UITheme.COLOR_PRIMARY},
		{"name": "Przetwórnia Danych", "color": UITheme.COLOR_PRIMARY},
		{"name": "Zniszcz budynek", "color": Color(0.40, 0.12, 0.14)}
	]
	
	for item in building_items:
		var btn = Button.new()
		btn.text = item.name
		btn.custom_minimum_size = Vector2(164, 32)
		var accent = UITheme.COLOR_ACCENT_RED if item.name == "Zniszcz budynek" else UITheme.COLOR_ACCENT_CYAN
		UITheme.style_button(btn, item.color, accent, 32, 14)
		btn.pressed.connect(func(): _on_build_btn_pressed(item.name))
		bvbox.add_child(btn)

func _build_in_game_chat_overlay() -> void:
	var chat_box = PanelContainer.new()
	chat_box.set_anchors_preset(PRESET_BOTTOM_LEFT)
	chat_box.position = Vector2(16, -190)
	chat_box.custom_minimum_size = Vector2(340, 160)
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.04, 0.08, 0.88), Color(0.12, 0.24, 0.38, 0.5), 4, 1, 8)
	chat_box.add_theme_stylebox_override("panel", sb)
	add_child(chat_box)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	chat_box.add_child(cvbox)
	
	var hint = Label.new()
	hint.text = "Gra rozpoczęta! T — czat · LPM zamyka"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	cvbox.add_child(hint)
	
	in_game_chat_log = RichTextLabel.new()
	in_game_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	in_game_chat_log.scroll_following = true
	in_game_chat_log.bbcode_enabled = true
	in_game_chat_log.add_theme_font_size_override("normal_font_size", 14)
	cvbox.add_child(in_game_chat_log)
	
	in_game_chat_input = LineEdit.new()
	in_game_chat_input.placeholder_text = "T — napisz wiadomość..."
	UITheme.style_line_edit(in_game_chat_input, 14)
	in_game_chat_input.text_submitted.connect(_on_chat_submitted)
	cvbox.add_child(in_game_chat_input)
	
	# Bottom Center Control Hints
	var hint_lbl = Label.new()
	hint_lbl.set_anchors_preset(PRESET_BOTTOM_WIDE)
	hint_lbl.position = Vector2(0, -32)
	hint_lbl.text = "LPM: zaznacz  PPM: rozkaz  T: czat  ESC/MENU: ustawienia  TAB: statystyki"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 15)
	hint_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	add_child(hint_lbl)

func _build_minimap_box() -> void:
	var minimap = PanelContainer.new()
	minimap.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(-170, -140)
	minimap.custom_minimum_size = Vector2(150, 120)
	
	var sb = UITheme.create_panel_style(Color(0.03, 0.05, 0.09, 0.92), UITheme.COLOR_ACCENT_CYAN.darkened(0.4), 4, 1, 4)
	minimap.add_theme_stylebox_override("panel", sb)
	add_child(minimap)
	
	var mini_inner = Control.new()
	mini_inner.set_anchors_preset(PRESET_FULL_RECT)
	mini_inner.draw.connect(_on_minimap_draw)
	minimap.add_child(mini_inner)

func _on_minimap_draw() -> void:
	# Mini overview of 50x50 map
	if active_map == null: return

# ==============================================================================
# Map Canvas Drawing (50x50 Grid, HQ Buildings, Units, Resources, Camps)
# ==============================================================================

func _on_map_draw() -> void:
	if map_viewport == null or active_map == null: return
	var rect = map_viewport.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	
	# Background
	map_viewport.draw_rect(rect, Color(0.03, 0.05, 0.08, 1.0), true)
	
	var tile_sz = TILE_PX * map_zoom
	var origin = map_camera_pos
	
	# 1. Non-buildable 1-tile border
	var map_rect = Rect2(origin, Vector2(active_map.width * tile_sz, active_map.height * tile_sz))
	map_viewport.draw_rect(map_rect, Color(0.04, 0.07, 0.11, 1.0), true)
	map_viewport.draw_rect(map_rect, Color(0.20, 0.30, 0.45, 0.8), false, 2.0)
	
	# 2. 50x50 Grid Lines
	var grid_col = Color(0.08, 0.14, 0.22, 0.35)
	for gx in range(active_map.width + 1):
		var lx = origin.x + gx * tile_sz
		map_viewport.draw_line(Vector2(lx, origin.y), Vector2(lx, origin.y + active_map.height * tile_sz), grid_col, 1.0)
	for gy in range(active_map.height + 1):
		var ly = origin.y + gy * tile_sz
		map_viewport.draw_line(Vector2(origin.x, ly), Vector2(origin.x + active_map.width * tile_sz, ly), grid_col, 1.0)
		
	# 3. Boss Area & Neutral Camps
	for c in active_map.camps:
		var c_world = origin + Vector2(c.grid_pos.x * tile_sz, c.grid_pos.y * tile_sz)
		if c.type == MapData.CampType.BOSS:
			var boss_box = Rect2(c_world - Vector2(tile_sz * 2, tile_sz * 2), Vector2(tile_sz * 5, tile_sz * 5))
			map_viewport.draw_rect(boss_box, Color(0.0, 0.4, 0.5, 0.2), true)
			map_viewport.draw_rect(boss_box, UITheme.COLOR_ACCENT_CYAN, false, 2.0)
			map_viewport.draw_circle(c_world + Vector2(tile_sz * 0.5, tile_sz * 0.5), tile_sz * 1.2, Color(0.9, 0.2, 0.2, 0.85))
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-20, -10), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, UITheme.COLOR_TEXT_MUTED)
		else:
			map_viewport.draw_circle(c_world + Vector2(tile_sz * 0.5, tile_sz * 0.5), tile_sz * 0.8, UITheme.COLOR_ACCENT_ORANGE)
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-18, -10), "OBÓZ", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UITheme.COLOR_TEXT_MUTED)

	# 4. Resources
	for r in active_map.resources:
		var r_pos = origin + Vector2(r.grid_pos.x * tile_sz, r.grid_pos.y * tile_sz)
		var r_rect = Rect2(r_pos + Vector2(2, 2), Vector2(tile_sz - 4, tile_sz - 4))
		
		var r_col = Color(0.75, 0.75, 0.75)
		match r.type:
			MapData.ResourceType.STONE: r_col = Color(0.75, 0.75, 0.75)
			MapData.ResourceType.IRON: r_col = Color(0.35, 0.85, 1.0)
			MapData.ResourceType.OIL: r_col = Color(1.0, 0.75, 0.20)
			MapData.ResourceType.REDSTONE: r_col = Color(1.0, 0.25, 0.25)
			
		map_viewport.draw_rect(r_rect, r_col.darkened(0.5), true)
		map_viewport.draw_rect(r_rect, r_col, false, 1.5)
		map_viewport.draw_circle(r_rect.get_center(), tile_sz * 0.3, r_col)

	# 5. Buildings (HQ)
	for b in buildings:
		var b_pos = origin + Vector2(b.grid_pos.x * tile_sz, b.grid_pos.y * tile_sz)
		var b_box = Rect2(b_pos - Vector2(tile_sz * 1.0, tile_sz * 1.0), Vector2(tile_sz * 3, tile_sz * 3))
		
		if hq_texture != null:
			map_viewport.draw_texture_rect(hq_texture, b_box, false)
		else:
			map_viewport.draw_rect(b_box, Color(0.2, 0.5, 0.9, 0.7), true)
			
		# Slot indicator ring
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		map_viewport.draw_arc(b_box.get_center(), tile_sz * 2.2, 0, TAU, 32, slot_col, 2.0)

	# 6. Units (Drones / Workers)
	for u in units:
		var u_pos = origin + u.world_pos * map_zoom
		var u_tex = worker_textures[u.slot] if u.slot < worker_textures.size() else null
		var u_sz = Vector2(32, 32) * map_zoom
		
		if u_tex != null:
			map_viewport.draw_texture_rect(u_tex, Rect2(u_pos - u_sz * 0.5, u_sz), false)
		else:
			map_viewport.draw_circle(u_pos, 12.0 * map_zoom, GameState.SLOT_COLORS[u.slot])
			
		if u.selected:
			map_viewport.draw_arc(u_pos, 18.0 * map_zoom, 0, TAU, 24, UITheme.COLOR_SUCCESS_GREEN, 2.0)

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			drag_start = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Command selected drone to move to clicked tile
			var click_world = (event.position - map_camera_pos) / map_zoom
			for u in units:
				if u.selected:
					u.target_pos = click_world
					map_viewport.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Select drone
			var click_world = (event.position - map_camera_pos) / map_zoom
			for u in units:
				if u.world_pos.distance_to(click_world) < 25.0:
					u.selected = true
				else:
					u.selected = false
			map_viewport.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_zoom = clampf(map_zoom + 0.1, 0.4, 2.5)
			map_viewport.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_zoom = clampf(map_zoom - 0.1, 0.4, 2.5)
			map_viewport.queue_redraw()
	elif event is InputEventMouseMotion and is_dragging:
		map_camera_pos += event.relative
		map_viewport.queue_redraw()

func _update_timer_display() -> void:
	var total_sec = int(match_timer_seconds)
	var mins = total_sec / 60
	var secs = total_sec % 60
	timer_lbl.text = "%02d:%02d" % [mins, secs]

func _on_build_btn_pressed(building_name: String) -> void:
	in_game_chat_log.append_text("[color=#00f0ff]Wybrano konstrukcję: [b]%s[/b] (Wskaż wolne pole na mapie)[/color]\n" % building_name)

func _on_chat_submitted(text: String) -> void:
	var clean = text.strip_edges()
	if not clean.is_empty():
		in_game_chat_log.append_text("[color=#2ec4b6][b]%s:[/b][/color] %s\n" % [settings_manager.player_name if settings_manager else "Gracz", clean])
		chat_sent.emit(clean)
		in_game_chat_input.clear()

func _toggle_esc_settings_modal() -> void:
	if active_settings_modal != null and is_instance_valid(active_settings_modal):
		active_settings_modal.queue_free()
		active_settings_modal = null
		return
		
	active_settings_modal = SettingsModal.new(settings_manager, network_manager, true)
	active_settings_modal.leave_game_requested.connect(func():
		exit_to_menu_requested.emit()
	)
	active_settings_modal.pause_game_toggled.connect(func(p: bool):
		is_paused = p
	)
	active_settings_modal.settings_closed.connect(func(_saved):
		active_settings_modal = null
	)
	add_child(active_settings_modal)

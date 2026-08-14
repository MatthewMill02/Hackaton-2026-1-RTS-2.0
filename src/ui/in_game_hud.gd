# In-Game Tactical HUD, Grid Building System, Drone Mining Loop, Combat & TAB Ranking
class_name InGameHUD
extends Control

signal exit_to_menu_requested()
signal chat_sent(msg: String)

var network_manager: NetworkManager
var settings_manager: SettingsManager
var active_map: MapData

# Subsystems
var economy: EconomyManager
var buildings: BuildingSystem
var units: UnitManager
var combat: CombatSystem
var research: ResearchSystem

# Match Stats
var match_timer_seconds: float = 45 * 60
var current_score: int = 0
var target_score: int = 1200
var is_paused: bool = false
var local_slot: int = 0

# UI Labels
var res_stone_lbl: Label
var res_iron_lbl: Label
var res_oil_lbl: Label
var res_redstone_lbl: Label
var power_lbl: Label
var timer_lbl: Label
var score_lbl: Label

# Map View & Camera
var map_viewport: Control
var map_camera_pos: Vector2 = Vector2.ZERO
var map_zoom: float = 1.0
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
const TILE_PX: float = 48.0
var minimap_canvas: Control = null

# Box Selection (Marquee drag select)
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO
var box_select_current: Vector2 = Vector2.ZERO
var selected_units_container: PanelContainer = null
var selected_units_vbox: VBoxContainer = null

# Building Placement Mode
var active_placing_def_id: String = ""
var is_demolish_mode: bool = false
var hover_grid_pos: Vector2i = Vector2i.ZERO

# In-Game Chat & Modals
var in_game_chat_log: RichTextLabel
var in_game_chat_input: LineEdit
var active_settings_modal: SettingsModal = null
var scoreboard_overlay: ScoreboardModal = null

func _init(p_net: NetworkManager = null, p_settings: SettingsManager = null, p_map: MapData = null) -> void:
	network_manager = p_net
	settings_manager = p_settings
	if p_map != null:
		active_map = p_map
	else:
		active_map = MapGenerator.generate_map()
		
	if network_manager != null and network_manager.local_player != null:
		local_slot = network_manager.local_player.slot
		
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	# 1. Initialize Subsystems
	economy = EconomyManager.new()
	economy.reset_for_match(300)
	
	buildings = BuildingSystem.new()
	units = UnitManager.new()
	combat = CombatSystem.new()
	research = ResearchSystem.new()
	
	# Connect Combat & Research Signals
	combat.camp_destroyed.connect(_on_camp_destroyed)
	research.card_unlocked.connect(_on_card_unlocked)
	
	# 2. Spawn Starting HQ and Initial Drone
	_spawn_starting_entities()
	
	# 3. Build HUD UI
	_build_ui()
	_center_camera_on_player_base()

func _spawn_starting_entities() -> void:
	for b_spawn in active_map.bases:
		# Spawn HQ on grid (skip validation — no power grid exists yet)
		var hq_inst = buildings.place_building("hq", b_spawn.grid_pos, b_spawn.slot, active_map, economy, true)
		
		# Spawn starting Worker Drone next to HQ
		var spawn_pos = Vector2((b_spawn.grid_pos.x + 2.0) * TILE_PX, (b_spawn.grid_pos.y + 2.0) * TILE_PX)
		var drone = units.spawn_unit("worker_drone", b_spawn.slot, spawn_pos)
		if b_spawn.slot == local_slot and drone != null:
			drone.selected = true

func _center_camera_on_player_base() -> void:
	if local_slot >= 0 and local_slot < active_map.bases.size():
		var b_pos = active_map.bases[local_slot].grid_pos
		var vp_size = get_viewport_rect().size
		var b_center = Vector2((b_pos.x + 1.5) * TILE_PX, (b_pos.y + 1.5) * TILE_PX)
		map_camera_pos = vp_size * 0.5 - b_center * map_zoom
		_clamp_camera_bounds()

func _clamp_camera_bounds() -> void:
	if active_map == null: return
	var vp_size = get_viewport_rect().size
	const EXTRA_TILES: float = 4.0
	var min_cam_x = vp_size.x - (active_map.width + EXTRA_TILES) * TILE_PX * map_zoom
	var max_cam_x = EXTRA_TILES * TILE_PX * map_zoom
	var min_cam_y = vp_size.y - (active_map.height + EXTRA_TILES) * TILE_PX * map_zoom
	var max_cam_y = EXTRA_TILES * TILE_PX * map_zoom
	
	if min_cam_x > max_cam_x:
		map_camera_pos.x = (vp_size.x - active_map.width * TILE_PX * map_zoom) * 0.5
	else:
		map_camera_pos.x = clampf(map_camera_pos.x, min_cam_x, max_cam_x)
		
	if min_cam_y > max_cam_y:
		map_camera_pos.y = (vp_size.y - active_map.height * TILE_PX * map_zoom) * 0.5
	else:
		map_camera_pos.y = clampf(map_camera_pos.y, min_cam_y, max_cam_y)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_TAB:
			if event.pressed and not event.echo:
				_show_scoreboard()
			elif not event.pressed:
				_hide_scoreboard()
			get_viewport().set_input_as_handled()
		elif event.pressed:
			if event.keycode == KEY_ESCAPE:
				if not active_placing_def_id.is_empty() or is_demolish_mode:
					active_placing_def_id = ""
					is_demolish_mode = false
					map_viewport.queue_redraw()
				else:
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
			
		# Subsystem update loop
		economy.update_grid(delta, buildings.building_instances)
		units.update_units(delta, active_map, buildings.building_instances, economy, TILE_PX)
		combat.update_combat(delta, buildings.building_instances, units.units, active_map, economy, TILE_PX)
		_update_resource_labels()
		_update_selected_units_ui()
		if map_viewport: map_viewport.queue_redraw()
		if minimap_canvas: minimap_canvas.queue_redraw()
		
	# Camera Pan (Keyboard + Screen Edge Panning)
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x -= 1
	
	# Edge mouse panning (within 24px from screen border)
	var vp_rect = get_viewport_rect()
	var m_pos = get_viewport().get_mouse_position()
	const EDGE_MARGIN: float = 24.0
	
	if m_pos.x >= 0 and m_pos.x <= EDGE_MARGIN:
		move.x += 1
	elif m_pos.x >= vp_rect.size.x - EDGE_MARGIN and m_pos.x <= vp_rect.size.x:
		move.x -= 1
		
	if m_pos.y >= 0 and m_pos.y <= EDGE_MARGIN:
		move.y += 1
	elif m_pos.y >= vp_rect.size.y - EDGE_MARGIN and m_pos.y <= vp_rect.size.y:
		move.y -= 1
	
	if move != Vector2.ZERO:
		var scroll_speed_mult = settings_manager.map_scroll_speed if settings_manager else 1.0
		var pan_speed = 650.0 * scroll_speed_mult
		map_camera_pos += move.normalized() * pan_speed * delta
		_clamp_camera_bounds()
		if map_viewport: map_viewport.queue_redraw()
		if minimap_canvas: minimap_canvas.queue_redraw()

func _build_ui() -> void:
	# 1. 2D Map Canvas (Background)
	map_viewport = Control.new()
	map_viewport.set_anchors_preset(PRESET_FULL_RECT)
	map_viewport.draw.connect(_on_map_draw)
	map_viewport.gui_input.connect(_on_map_gui_input)
	add_child(map_viewport)
	
	# 2. TOP RESOURCE & STATUS BAR
	var top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 64)
	var top_sb = StyleBoxFlat.new()
	top_sb.bg_color = Color(0.02, 0.04, 0.08, 0.92)
	top_sb.content_margin_left = 20
	top_sb.content_margin_right = 20
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 28)
	top_bar.add_child(top_hbox)
	
	# Left: Resources
	var res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 3)
	top_hbox.add_child(res_box)
	
	var res_row1 = HBoxContainer.new()
	res_row1.add_theme_constant_override("separation", 20)
	res_box.add_child(res_row1)
	
	res_stone_lbl = Label.new()
	res_stone_lbl.add_theme_font_size_override("font_size", 16)
	res_stone_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	res_row1.add_child(res_stone_lbl)
	
	res_iron_lbl = Label.new()
	res_iron_lbl.add_theme_font_size_override("font_size", 16)
	res_iron_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	res_row1.add_child(res_iron_lbl)
	
	res_oil_lbl = Label.new()
	res_oil_lbl.add_theme_font_size_override("font_size", 16)
	res_oil_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	res_row1.add_child(res_oil_lbl)
	
	res_redstone_lbl = Label.new()
	res_redstone_lbl.add_theme_font_size_override("font_size", 16)
	res_redstone_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	res_row1.add_child(res_redstone_lbl)
	
	var res_row2 = HBoxContainer.new()
	res_row2.add_theme_constant_override("separation", 16)
	res_box.add_child(res_row2)
	
	power_lbl = Label.new()
	power_lbl.add_theme_font_size_override("font_size", 14)
	power_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	res_row2.add_child(power_lbl)
	
	var spacer_t = Control.new()
	spacer_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer_t)
	
	# Right: Timer & Score & Menu
	var score_box = VBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_child(score_box)
	
	timer_lbl = Label.new()
	timer_lbl.text = "45:00"
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_lbl.add_theme_font_size_override("font_size", 22)
	timer_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_box.add_child(timer_lbl)
	
	score_lbl = Label.new()
	score_lbl.text = "★ %d / %d pkt" % [current_score, target_score]
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
	
	# 3. LEFT CONSTRUCTION PANEL
	_build_left_construction_panel()
	
	# 4. IN-GAME CHAT OVERLAY & HINTS
	_build_in_game_chat_overlay()
	
	# 5. BOTTOM RIGHT MINIMAP & SELECTED UNITS PANEL
	_build_minimap_box()
	_build_selected_units_panel()
	
	_update_resource_labels()

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
	
	var building_list = [
		{"id": "stone_mine", "name": "Kopalnia Kamienia"},
		{"id": "iron_mine", "name": "Kopalnia Żelaza"},
		{"id": "pylon", "name": "Pylon"},
		{"id": "factory", "name": "Fabryka"},
		{"id": "storage", "name": "Magazyn"},
		{"id": "wall", "name": "Mur"},
		{"id": "turret", "name": "Wieżyczka"},
		{"id": "power_plant", "name": "Elektrownia"},
		{"id": "battery", "name": "Bank Energii"},
		{"id": "lab", "name": "Przetwórnia Danych"},
		{"id": "DEMOLISH", "name": "Zniszcz budynek"}
	]
	
	for item in building_list:
		var btn = Button.new()
		btn.text = item.name
		btn.custom_minimum_size = Vector2(164, 32)
		var is_dem = (item.id == "DEMOLISH")
		var accent = UITheme.COLOR_ACCENT_RED if is_dem else UITheme.COLOR_ACCENT_CYAN
		var base_col = Color(0.40, 0.12, 0.14) if is_dem else UITheme.COLOR_PRIMARY
		UITheme.style_button(btn, base_col, accent, 32, 14)
		
		var b_id = item.id
		btn.pressed.connect(func(): _on_build_selected(b_id))
		bvbox.add_child(btn)

func _build_in_game_chat_overlay() -> void:
	var chat_box = PanelContainer.new()
	chat_box.set_anchors_preset(PRESET_BOTTOM_LEFT)
	chat_box.anchor_left = 0.0
	chat_box.anchor_top = 1.0
	chat_box.anchor_right = 0.0
	chat_box.anchor_bottom = 1.0
	chat_box.offset_left = 16.0
	chat_box.offset_top = -200.0
	chat_box.offset_right = 376.0
	chat_box.offset_bottom = -38.0
	chat_box.grow_horizontal = Control.GROW_DIRECTION_END
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.04, 0.08, 0.88), Color(0.12, 0.24, 0.38, 0.5), 4, 1, 8)
	chat_box.add_theme_stylebox_override("panel", sb)
	add_child(chat_box)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	chat_box.add_child(cvbox)
	
	var hint = Label.new()
	hint.text = "Gra rozpoczęta! T — czat · TAB — ranking"
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
	
	# Bottom Hint
	var hint_lbl = Label.new()
	hint_lbl.set_anchors_preset(PRESET_BOTTOM_WIDE)
	hint_lbl.position = Vector2(0, -32)
	hint_lbl.text = "LPM: zaznacz / postaw  PPM: ruch / kopanie / atak  ESC: anuluj / menu  TAB: ranking"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 15)
	hint_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	add_child(hint_lbl)

func _build_minimap_box() -> void:
	var minimap_panel = PanelContainer.new()
	minimap_panel.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	minimap_panel.position = Vector2(-200, -210)
	minimap_panel.custom_minimum_size = Vector2(184, 184)
	var sb = UITheme.create_panel_style(Color(0.02, 0.04, 0.07, 0.95), UITheme.COLOR_ACCENT_CYAN, 4, 2, 6)
	minimap_panel.add_theme_stylebox_override("panel", sb)
	add_child(minimap_panel)
	
	minimap_canvas = Control.new()
	minimap_canvas.custom_minimum_size = Vector2(172, 172)
	minimap_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	minimap_canvas.draw.connect(_on_minimap_draw)
	minimap_canvas.gui_input.connect(_on_minimap_gui_input)
	minimap_panel.add_child(minimap_canvas)

func _on_minimap_draw() -> void:
	if minimap_canvas == null or active_map == null: return
	var m_sz = minimap_canvas.get_rect().size
	var map_w = active_map.width
	var map_h = active_map.height
	var cell_w = m_sz.x / float(map_w)
	var cell_h = m_sz.y / float(map_h)
	
	# Background
	minimap_canvas.draw_rect(Rect2(Vector2.ZERO, m_sz), Color(0.03, 0.05, 0.09, 1.0), true)
	
	# Boss Zone (Strefa Boss)
	for c in active_map.camps:
		if c.type == MapData.CampType.BOSS and c.hp > 0:
			var bx = (c.grid_pos.x - 2) * cell_w
			var by = (c.grid_pos.y - 2) * cell_h
			minimap_canvas.draw_rect(Rect2(bx, by, cell_w * 5, cell_h * 5), Color(0.85, 0.2, 0.2, 0.45), true)
			minimap_canvas.draw_circle(Vector2(bx + cell_w * 2.5, by + cell_h * 2.5), cell_w * 1.8, Color(0.9, 0.15, 0.15, 0.9))
		elif c.type == MapData.CampType.CAMP and c.hp > 0:
			var cx = c.grid_pos.x * cell_w
			var cy = c.grid_pos.y * cell_h
			minimap_canvas.draw_circle(Vector2(cx + cell_w * 0.5, cy + cell_h * 0.5), cell_w * 1.4, UITheme.COLOR_ACCENT_ORANGE)
			
	# Resources
	for r in active_map.resources:
		if r.amount <= 0: continue
		var rx = r.grid_pos.x * cell_w
		var ry = r.grid_pos.y * cell_h
		var r_col = Color.WHITE
		match r.type:
			MapData.ResourceType.STONE: r_col = Color(0.65, 0.65, 0.65)
			MapData.ResourceType.IRON: r_col = Color(0.35, 0.85, 1.0)
			MapData.ResourceType.OIL: r_col = Color(1.0, 0.75, 0.20)
			MapData.ResourceType.REDSTONE: r_col = Color(1.0, 0.25, 0.25)
		minimap_canvas.draw_rect(Rect2(rx, ry, maxf(cell_w, 2.0), maxf(cell_h, 2.0)), r_col, true)
		
	# Bases / HQ
	for b in active_map.bases:
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		var bx = b.grid_pos.x * cell_w
		var by = b.grid_pos.y * cell_h
		minimap_canvas.draw_rect(Rect2(bx, by, cell_w * 3, cell_h * 3), slot_col, true)
		
	# Buildings
	for b in buildings.building_instances:
		if b.hp <= 0: continue
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		var bx = b.grid_pos.x * cell_w
		var by = b.grid_pos.y * cell_h
		minimap_canvas.draw_rect(Rect2(bx, by, maxf(cell_w * b.size.x, 3.0), maxf(cell_h * b.size.y, 3.0)), slot_col, true)
		
	# Units
	for u in units.units:
		if u.hp <= 0: continue
		var ux = (u.world_pos.x / TILE_PX) * cell_w
		var uy = (u.world_pos.y / TILE_PX) * cell_h
		var slot_col = GameState.SLOT_COLORS[u.slot] if u.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		minimap_canvas.draw_circle(Vector2(ux, uy), 2.5, slot_col)
		
	# Camera Viewport Box on Minimap (Current visible screen area)
	var vp_size = get_viewport_rect().size
	var top_left_world = (Vector2.ZERO - map_camera_pos) / map_zoom
	var bottom_right_world = (vp_size - map_camera_pos) / map_zoom
	
	var cam_x1 = (top_left_world.x / (map_w * TILE_PX)) * m_sz.x
	var cam_y1 = (top_left_world.y / (map_h * TILE_PX)) * m_sz.y
	var cam_x2 = (bottom_right_world.x / (map_w * TILE_PX)) * m_sz.x
	var cam_y2 = (bottom_right_world.y / (map_h * TILE_PX)) * m_sz.y
	
	var cam_rect = Rect2(cam_x1, cam_y1, maxf(cam_x2 - cam_x1, 4.0), maxf(cam_y2 - cam_y1, 4.0))
	minimap_canvas.draw_rect(cam_rect, Color(1.0, 0.85, 0.2, 0.15), true)
	minimap_canvas.draw_rect(cam_rect, Color(1.0, 0.90, 0.3, 0.95), false, 1.5)

func _on_minimap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT) and event.pressed:
			_center_camera_on_minimap(event.position)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_center_camera_on_minimap(event.position)

func _center_camera_on_minimap(minimap_pos: Vector2) -> void:
	if minimap_canvas == null or active_map == null: return
	var m_sz = minimap_canvas.get_rect().size
	var map_world_size = Vector2(active_map.width * TILE_PX, active_map.height * TILE_PX)
	var world_target = Vector2(
		(minimap_pos.x / m_sz.x) * map_world_size.x,
		(minimap_pos.y / m_sz.y) * map_world_size.y
	)
	var vp_size = get_viewport_rect().size
	map_camera_pos = vp_size * 0.5 - world_target * map_zoom
	_clamp_camera_bounds()
	map_viewport.queue_redraw()
	minimap_canvas.queue_redraw()

func _build_selected_units_panel() -> void:
	selected_units_container = PanelContainer.new()
	selected_units_container.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	selected_units_container.position = Vector2(-280, -470)
	selected_units_container.custom_minimum_size = Vector2(260, 0)
	selected_units_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxEmpty.new()
	selected_units_container.add_theme_stylebox_override("panel", sb)
	add_child(selected_units_container)
	
	selected_units_vbox = VBoxContainer.new()
	selected_units_vbox.add_theme_constant_override("separation", 6)
	selected_units_vbox.alignment = BoxContainer.ALIGNMENT_END
	selected_units_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_units_container.add_child(selected_units_vbox)

func _update_selected_units_ui() -> void:
	if selected_units_vbox == null or units == null: return
	
	for c in selected_units_vbox.get_children():
		c.queue_free()
		
	var selected_list = units.units.filter(func(u): return u.slot == local_slot and u.selected and u.hp > 0)
	if selected_list.is_empty():
		return
		
	var display_count = mini(selected_list.size(), 5)
	for i in range(display_count):
		var u = selected_list[i]
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(250, 56)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb = UITheme.create_panel_style(Color(0.04, 0.08, 0.15, 0.94), UITheme.COLOR_ACCENT_CYAN, 4, 1, 6)
		card.add_theme_stylebox_override("panel", sb)
		
		var cvbox = VBoxContainer.new()
		cvbox.add_theme_constant_override("separation", 2)
		card.add_child(cvbox)
		
		# Top Row: Unit Name + HP
		var top_row = HBoxContainer.new()
		cvbox.add_child(top_row)
		
		var name_lbl = Label.new()
		name_lbl.text = "🤖 %s #%d" % [u.name, u.instance_id]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_lbl)
		
		var hp_lbl = Label.new()
		hp_lbl.text = "%d/%d HP" % [u.hp, u.max_hp]
		hp_lbl.add_theme_font_size_override("font_size", 12)
		hp_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN if u.hp > u.max_hp * 0.4 else UITheme.COLOR_ACCENT_RED)
		top_row.add_child(hp_lbl)
		
		# HP mini bar
		var hp_bar = ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(0, 4)
		hp_bar.max_value = u.max_hp
		hp_bar.value = u.hp
		hp_bar.show_percentage = false
		cvbox.add_child(hp_bar)
		
		# Status row
		var status_text = "💤 Oczekiwanie"
		match u.state:
			UnitManager.UnitState.MINING:
				var res_name = "Kamień"
				if u.target_resource:
					match u.target_resource.type:
						MapData.ResourceType.STONE: res_name = "🪨 Kamień"
						MapData.ResourceType.IRON: res_name = "⚙️ Żelazo"
						MapData.ResourceType.OIL: res_name = "🛢️ Ropa"
						MapData.ResourceType.REDSTONE: res_name = "🔴 Redstone"
				status_text = "⛏️ Wydobywa %s (%d/%d)" % [res_name, u.carried_amount, u.max_carry]
			UnitManager.UnitState.RETURNING_TO_HQ:
				var res_name = "Surowiec"
				match u.carried_type:
					MapData.ResourceType.STONE: res_name = "🪨 Kamień"
					MapData.ResourceType.IRON: res_name = "⚙️ Żelazo"
					MapData.ResourceType.OIL: res_name = "🛢️ Ropa"
					MapData.ResourceType.REDSTONE: res_name = "🔴 Redstone"
				status_text = "🚚 Transport %s (%d) -> Baza" % [res_name, u.carried_amount]
			UnitManager.UnitState.MOVING, UnitManager.UnitState.MOVING_TO_RESOURCE:
				status_text = "🏃 Ruch do celu"
			UnitManager.UnitState.ATTACKING:
				status_text = "⚔️ Atakowanie wroga"
				
		var stat_lbl = Label.new()
		stat_lbl.text = status_text
		stat_lbl.add_theme_font_size_override("font_size", 12)
		stat_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		cvbox.add_child(stat_lbl)
		
		selected_units_vbox.add_child(card)
		
	if selected_list.size() > display_count:
		var more_lbl = Label.new()
		more_lbl.text = "+ %d więcej zaznaczonych" % (selected_list.size() - display_count)
		more_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more_lbl.add_theme_font_size_override("font_size", 12)
		more_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
		selected_units_vbox.add_child(more_lbl)

func _update_resource_labels() -> void:
	if res_stone_lbl: res_stone_lbl.text = "🪨 %d/%d" % [economy.stone, economy.max_storage]
	if res_iron_lbl: res_iron_lbl.text = "⚙️ %d/%d" % [economy.iron, economy.max_storage]
	if res_oil_lbl: res_oil_lbl.text = "🛢️ %d/%d" % [economy.oil, economy.max_storage]
	if res_redstone_lbl: res_redstone_lbl.text = "🔴 %d/%d" % [economy.redstone, economy.max_storage]
	
	var net_pow = economy.power_production - economy.power_consumption
	if power_lbl:
		power_lbl.text = "⚡ %+d | %d/%d kW (Bat: %d kJ)" % [net_pow, economy.power_production, economy.power_consumption, int(economy.stored_energy_kj)]
		if economy.is_blackout:
			power_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
		else:
			power_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)

# ==============================================================================
# Map Canvas Rendering
# ==============================================================================

func _on_map_draw() -> void:
	if map_viewport == null or active_map == null: return
	var rect = map_viewport.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	
	map_viewport.draw_rect(rect, Color(0.03, 0.05, 0.08, 1.0), true)
	
	var tile_sz = TILE_PX * map_zoom
	var origin = map_camera_pos
	
	# 1. 1-tile Non-buildable Border
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
		var c_world = origin + Vector2((c.grid_pos.x + 0.5) * tile_sz, (c.grid_pos.y + 0.5) * tile_sz)
		if c.hp <= 0: continue
		if c.type == MapData.CampType.BOSS:
			var boss_box = Rect2(c_world - Vector2(tile_sz * 2, tile_sz * 2), Vector2(tile_sz * 4, tile_sz * 4))
			map_viewport.draw_rect(boss_box, Color(0.0, 0.4, 0.5, 0.2), true)
			map_viewport.draw_rect(boss_box, UITheme.COLOR_ACCENT_CYAN, false, 2.0)
			map_viewport.draw_circle(c_world, tile_sz * 1.0, Color(0.9, 0.2, 0.2, 0.85))
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-22, -10), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, UITheme.COLOR_TEXT_MUTED)
			_draw_health_bar(c_world + Vector2(0, tile_sz * 1.2), c.hp, 3000, 60.0 * map_zoom)
		else:
			map_viewport.draw_circle(c_world, tile_sz * 0.7, UITheme.COLOR_ACCENT_ORANGE)
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-20, -10), "OBÓZ", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UITheme.COLOR_TEXT_MUTED)
			_draw_health_bar(c_world + Vector2(0, tile_sz * 0.9), c.hp, 800, 44.0 * map_zoom)

	# 4. Resource Deposits
	for r in active_map.resources:
		if r.amount <= 0: continue
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

	# 5. Buildings
	for b in buildings.building_instances:
		var b_pos = origin + Vector2(b.grid_pos.x * tile_sz, b.grid_pos.y * tile_sz)
		var b_box = Rect2(b_pos, Vector2(b.size.x * tile_sz, b.size.y * tile_sz))
		
		if b.sprite_texture != null:
			map_viewport.draw_texture_rect(b.sprite_texture, b_box, false)
		else:
			map_viewport.draw_rect(b_box, Color(0.12, 0.28, 0.44, 0.9), true)
			map_viewport.draw_rect(b_box, UITheme.COLOR_ACCENT_CYAN, false, 1.5)
			
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		map_viewport.draw_rect(b_box, slot_col, false, 1.5)
		
		# Draw Power Grid coverage for Pylons and HQ (tile-based with corner cuts)
		if b.def_id in ["hq", "pylon"]:
			var radius = BuildingSystem.POWER_GRID_HQ_RADIUS if b.def_id == "hq" else BuildingSystem.POWER_GRID_PYLON_RADIUS
			var b_center_tile = b.grid_pos + Vector2i(1, 1) if b.def_id == "hq" else b.grid_pos
			var power_tiles = BuildingSystem.get_powered_tiles(b_center_tile, radius)
			var power_col = Color(slot_col.r, slot_col.g, slot_col.b, 0.08)
			var power_border_col = Color(slot_col.r, slot_col.g, slot_col.b, 0.18)
			for pt in power_tiles:
				var pt_pos = origin + Vector2(pt.x * tile_sz, pt.y * tile_sz)
				var pt_rect = Rect2(pt_pos, Vector2(tile_sz, tile_sz))
				map_viewport.draw_rect(pt_rect, power_col, true)
			# Draw border outline of the power area
			for pt in power_tiles:
				var pt_v = Vector2i(pt.x, pt.y)
				# Check each edge — if neighbor is not powered, draw edge
				for edge_data in [
					[Vector2i(0, -1), Vector2(0, 0), Vector2(1, 0)],  # top
					[Vector2i(0, 1), Vector2(0, 1), Vector2(1, 1)],   # bottom
					[Vector2i(-1, 0), Vector2(0, 0), Vector2(0, 1)],  # left
					[Vector2i(1, 0), Vector2(1, 0), Vector2(1, 1)]    # right
				]:
					var neighbor = pt_v + edge_data[0]
					if not power_tiles.has(neighbor):
						var e1 = origin + Vector2((pt.x + edge_data[1].x) * tile_sz, (pt.y + edge_data[1].y) * tile_sz)
						var e2 = origin + Vector2((pt.x + edge_data[2].x) * tile_sz, (pt.y + edge_data[2].y) * tile_sz)
						map_viewport.draw_line(e1, e2, power_border_col, 1.5)

	# 6. Units
	for u in units.units:
		if u.hp <= 0: continue
		var u_pos = origin + u.world_pos * map_zoom
		var u_sz = Vector2(34, 34) * map_zoom
		
		if u.sprite_texture != null:
			map_viewport.draw_texture_rect(u.sprite_texture, Rect2(u_pos - u_sz * 0.5, u_sz), false)
		else:
			map_viewport.draw_circle(u_pos, 12.0 * map_zoom, GameState.SLOT_COLORS[u.slot])
			
		if u.selected:
			map_viewport.draw_arc(u_pos, 20.0 * map_zoom, 0, TAU, 24, UITheme.COLOR_SUCCESS_GREEN, 2.0)
			
		# Carried resource cargo indicator
		if u.carried_amount > 0:
			var c_col = Color(0.75, 0.75, 0.75)
			match u.carried_type:
				MapData.ResourceType.STONE: c_col = Color(0.75, 0.75, 0.75)
				MapData.ResourceType.IRON: c_col = Color(0.35, 0.85, 1.0)
				MapData.ResourceType.OIL: c_col = Color(1.0, 0.75, 0.20)
				MapData.ResourceType.REDSTONE: c_col = Color(1.0, 0.25, 0.25)
			map_viewport.draw_circle(u_pos + Vector2(0, -16 * map_zoom), 5.0 * map_zoom, c_col)

	# 7. Combat Beams
	for beam in combat.active_beams:
		var from_scr = origin + beam.from_pos * map_zoom
		var to_scr = origin + beam.to_pos * map_zoom
		map_viewport.draw_line(from_scr, to_scr, beam.color, 3.0)

	# 8. Snap to Grid Ghost Placement Preview
	if not active_placing_def_id.is_empty():
		var def = buildings.get_def(active_placing_def_id)
		if def != null:
			var g_pos = hover_grid_pos
			var p_world = origin + Vector2(g_pos.x * tile_sz, g_pos.y * tile_sz)
			var p_rect = Rect2(p_world, Vector2(def.size.x * tile_sz, def.size.y * tile_sz))
			
			var val = buildings.is_position_valid_for_building(active_placing_def_id, g_pos, local_slot, active_map)
			var can_buy = economy.can_afford(def.cost)
			var is_ok = val.valid and can_buy
			
			var preview_col = Color(0.2, 0.9, 0.4, 0.4) if is_ok else Color(0.9, 0.2, 0.2, 0.4)
			var border_col = UITheme.COLOR_SUCCESS_GREEN if is_ok else UITheme.COLOR_ACCENT_RED
			
			map_viewport.draw_rect(p_rect, preview_col, true)
			map_viewport.draw_rect(p_rect, border_col, false, 2.0)
			
			if not val.valid:
				map_viewport.draw_string(ThemeDB.fallback_font, p_world + Vector2(0, -10), val.reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.COLOR_ACCENT_RED)
			elif not can_buy:
				map_viewport.draw_string(ThemeDB.fallback_font, p_world + Vector2(0, -10), "Brak surowców!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.COLOR_ACCENT_RED)

	# 9. Box Selection Marquee (Windows desktop style)
	if is_box_selecting:
		var min_x = minf(box_select_start.x, box_select_current.x)
		var max_x = maxf(box_select_start.x, box_select_current.x)
		var min_y = minf(box_select_start.y, box_select_current.y)
		var max_y = maxf(box_select_start.y, box_select_current.y)
		var sel_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		map_viewport.draw_rect(sel_rect, Color(0.15, 0.55, 0.95, 0.18), true)
		map_viewport.draw_rect(sel_rect, Color(0.35, 0.85, 1.0, 0.90), false, 1.5)

func _draw_health_bar(center_pos: Vector2, hp: int, max_hp: int, bar_width: float) -> void:
	var bar_h = 5.0
	var bar_rect = Rect2(center_pos - Vector2(bar_width * 0.5, bar_h * 0.5), Vector2(bar_width, bar_h))
	map_viewport.draw_rect(bar_rect, Color(0.1, 0.1, 0.1, 0.8), true)
	var pct = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var fill_rect = Rect2(bar_rect.position, Vector2(bar_width * pct, bar_h))
	var fill_col = UITheme.COLOR_SUCCESS_GREEN if pct > 0.4 else UITheme.COLOR_ACCENT_RED
	map_viewport.draw_rect(fill_rect, fill_col, true)

# ==============================================================================
# Mouse Interaction & Unit Control
# ==============================================================================

func _on_map_gui_input(event: InputEvent) -> void:
	var tile_sz = TILE_PX * map_zoom
	
	if event is InputEventMouseMotion:
		# Calculate hover grid tile
		var m_local = event.position - map_camera_pos
		hover_grid_pos = Vector2i(int(floor(m_local.x / tile_sz)), int(floor(m_local.y / tile_sz)))
		if is_dragging:
			map_camera_pos += event.relative
			_clamp_camera_bounds()
			if minimap_canvas: minimap_canvas.queue_redraw()
		if is_box_selecting:
			box_select_current = event.position
		map_viewport.queue_redraw()
		
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			drag_start = event.position
			
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not active_placing_def_id.is_empty():
					# Attempt building placement
					var placed = buildings.place_building(active_placing_def_id, hover_grid_pos, local_slot, active_map, economy)
					if placed != null:
						in_game_chat_log.append_text("[color=#00f0ff]Postawiono: [b]%s[/b][/color]\n" % placed.name)
						active_placing_def_id = "" # Reset
						map_viewport.queue_redraw()
				elif is_demolish_mode:
					# Attempt demolition
					if buildings.demolish_building_at(hover_grid_pos, local_slot, economy):
						in_game_chat_log.append_text("[color=#ff4655]Zniszczono budynek (Zwrócono 50% surowców)[/color]\n")
						is_demolish_mode = false
						map_viewport.queue_redraw()
				else:
					# Start box selection
					is_box_selecting = true
					box_select_start = event.position
					box_select_current = event.position
					map_viewport.queue_redraw()
			else:
				# LMB Released - finalize selection
				if is_box_selecting:
					is_box_selecting = false
					box_select_current = event.position
					var box_w = absf(box_select_current.x - box_select_start.x)
					var box_h = absf(box_select_current.y - box_select_start.y)
					
					if box_w < 8.0 and box_h < 8.0:
						# Single-click selection
						var click_world = (event.position - map_camera_pos) / map_zoom
						var closest_u = null
						var min_d = 32.0
						for u in units.units:
							if u.slot == local_slot and u.hp > 0:
								var d = u.world_pos.distance_to(click_world)
								if d < min_d:
									min_d = d
									closest_u = u
						for u in units.units:
							if u.slot == local_slot:
								u.selected = (u == closest_u)
					else:
						# Box selection (marquee drag)
						var min_x = minf(box_select_start.x, box_select_current.x)
						var max_x = maxf(box_select_start.x, box_select_current.x)
						var min_y = minf(box_select_start.y, box_select_current.y)
						var max_y = maxf(box_select_start.y, box_select_current.y)
						var sel_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
						
						for u in units.units:
							if u.slot == local_slot and u.hp > 0:
								var u_screen = map_camera_pos + u.world_pos * map_zoom
								u.selected = sel_rect.has_point(u_screen)
							else:
								u.selected = false
								
					map_viewport.queue_redraw()
					_update_selected_units_ui()
				
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not active_placing_def_id.is_empty() or is_demolish_mode:
				active_placing_def_id = ""
				is_demolish_mode = false
				map_viewport.queue_redraw()
				return
				
			var click_world = (event.position - map_camera_pos) / map_zoom
			var clicked_tile = Vector2i(int(floor(click_world.x / TILE_PX)), int(floor(click_world.y / TILE_PX)))
			
			var selected_units = units.units.filter(func(u): return u.slot == local_slot and u.selected)
			if selected_units.is_empty(): return
			
			# Check if clicked resource node
			var target_res: MapData.ResourceNode = null
			for r in active_map.resources:
				if r.grid_pos == clicked_tile and r.amount > 0:
					target_res = r
					break
					
			if target_res != null:
				units.command_gather(selected_units, target_res)
				in_game_chat_log.append_text("[color=#2ec4b6]Dron wysłany do wydobycia surowca.[/color]\n")
				return
				
			# Check if clicked enemy camp
			var target_camp: MapData.CampNode = null
			for c in active_map.camps:
				if c.hp > 0 and (c.grid_pos - clicked_tile).length() <= 1:
					target_camp = c
					break
					
			if target_camp != null:
				units.command_attack_camp(selected_units, target_camp)
				in_game_chat_log.append_text("[color=#ff9f1c]Wydano rozkaz ataku na obóz/bossa![/color]\n")
				return
				
			# Standard move command
			units.command_move(selected_units, click_world)
			map_viewport.queue_redraw()
			
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_point(event.position, 0.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_point(event.position, -0.12)

func _zoom_at_point(screen_pos: Vector2, zoom_delta: float) -> void:
	var old_zoom = map_zoom
	var new_zoom = clampf(map_zoom + zoom_delta, 0.45, 2.5)
	if is_equal_approx(old_zoom, new_zoom): return
	
	var world_at_mouse = (screen_pos - map_camera_pos) / old_zoom
	map_zoom = new_zoom
	map_camera_pos = screen_pos - world_at_mouse * new_zoom
	
	_clamp_camera_bounds()
	map_viewport.queue_redraw()
	if minimap_canvas: minimap_canvas.queue_redraw()

func _on_build_selected(def_id: String) -> void:
	if def_id == "DEMOLISH":
		is_demolish_mode = true
		active_placing_def_id = ""
		in_game_chat_log.append_text("[color=#ff4655]Tryb wyburzania: Kliknij własny budynek, aby go zniszczyć.[/color]\n")
	else:
		active_placing_def_id = def_id
		is_demolish_mode = false
		var def = buildings.get_def(def_id)
		if def != null:
			in_game_chat_log.append_text("[color=#00f0ff]Tryb budowy: [b]%s[/b] (Wskaż wolne pole w zasięgu zasilania)[/color]\n" % def.name)

func _on_camp_destroyed(camp: MapData.CampNode, killer_slot: int) -> void:
	current_score += 300 if camp.type == MapData.CampType.BOSS else 100
	score_lbl.text = "★ %d / %d pkt" % [current_score, target_score]
	
	var drawn_card = research.draw_random_card(killer_slot)
	var card_info = " (%s)" % drawn_card.name if drawn_card != null else ""
	in_game_chat_log.append_text("[color=#ffd166]📢 [b]ZNISZCZONO OBÓZ![/b] Zdobyto surowce i Kartę Badań%s![/color]\n" % card_info)

func _on_card_unlocked(card: ResearchSystem.CardDef, player_slot: int) -> void:
	in_game_chat_log.append_text("[color=#a855f7]✨ Odblokowano technologię: [b]%s[/b] — %s[/color]\n" % [card.name, card.description])

func _update_timer_display() -> void:
	var total_sec = int(match_timer_seconds)
	var mins = total_sec / 60
	var secs = total_sec % 60
	timer_lbl.text = "%02d:%02d" % [mins, secs]

func _on_chat_submitted(text: String) -> void:
	var clean = text.strip_edges()
	if not clean.is_empty():
		var col_hex = GameState.SLOT_COLORS[local_slot].to_html(false)
		in_game_chat_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [col_hex, settings_manager.player_name if settings_manager else "Pracownik", clean])
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

func _show_scoreboard() -> void:
	if scoreboard_overlay == null or not is_instance_valid(scoreboard_overlay):
		scoreboard_overlay = ScoreboardModal.new(network_manager, settings_manager, target_score, match_timer_seconds)
		add_child(scoreboard_overlay)

func _hide_scoreboard() -> void:
	if scoreboard_overlay != null and is_instance_valid(scoreboard_overlay):
		scoreboard_overlay.queue_free()
		scoreboard_overlay = null

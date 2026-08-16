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
var bot_ai: BotAIController
var bot_status_vbox: VBoxContainer = null

# Match Stats
var match_timer_seconds: float = 45 * 60
var current_score: int = 0
var target_score: int = 1200
var is_paused: bool = false
var is_game_over: bool = false
var local_slot: int = 0
var kills_count: int = 0
var camps_count: int = 0
var buildings_built_count: int = 1

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
var active_production_modal: BuildingProductionModal = null
var active_lab_modal: LabResearchModal = null
var scoreboard_overlay: ScoreboardModal = null
var building_card_popup: PanelContainer = null
var snapshot_timer: float = 0.0
var f3_diagnostics_overlay: PanelContainer = null
var f3_diag_labels: Dictionary = {}
var camp_card_popup: PanelContainer = null
var last_hovered_camp: MapData.CampNode = null
var pause_banner_overlay: PanelContainer = null

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
	if network_manager != null and network_manager.is_creative:
		economy.enable_creative_mode()
		
	if network_manager != null:
		target_score = network_manager.match_target_score
		match_timer_seconds = float(network_manager.match_duration_min * 60)
	
	buildings = BuildingSystem.new()
	units = UnitManager.new()
	combat = CombatSystem.new()
	research = ResearchSystem.new()
	bot_ai = BotAIController.new()
	if network_manager != null:
		bot_ai.setup_bots(network_manager.get_players_list())
	
	# Connect Combat & Research Signals
	combat.camp_destroyed.connect(_on_camp_destroyed)
	combat.turret_fired.connect(_on_local_turret_fired)
	combat.unit_killed_reward.connect(_on_unit_killed_reward)
	units.unit_killed_reward.connect(_on_unit_killed_reward)
	research.card_obtained.connect(_on_card_obtained)
	research.card_revealed.connect(_on_card_revealed)
	research.card_sold.connect(_on_card_sold)
	
	# Connect Network Gameplay Synchronization Signals
	if network_manager != null:
		network_manager.remote_building_placed.connect(_on_remote_building_placed)
		network_manager.remote_building_demolished.connect(_on_remote_building_demolished)
		network_manager.remote_unit_moved.connect(_on_remote_unit_moved)
		network_manager.remote_unit_gathered.connect(_on_remote_unit_gathered)
		network_manager.remote_unit_attacked.connect(_on_remote_unit_attacked)
		network_manager.remote_unit_constructed.connect(_on_remote_unit_constructed)
		network_manager.remote_unit_spawned.connect(_on_remote_unit_spawned)
		network_manager.remote_units_snapshot.connect(_on_remote_units_snapshot)
		network_manager.remote_turret_fired.connect(_on_remote_turret_fired)
		network_manager.remote_camp_damaged.connect(_on_remote_camp_damaged)
		network_manager.match_victory_declared.connect(_on_remote_match_victory)
		network_manager.match_pause_toggled.connect(_on_network_pause_toggled)
	
	# 2. Spawn Starting HQ and Initial Drone (Deterministic IDs)
	_spawn_starting_entities()
	
	# 3. Build HUD UI
	_build_ui()
	_build_f3_diagnostics_overlay()
	_center_camera_on_player_base()

func _spawn_starting_entities() -> void:
	for b_spawn in active_map.bases:
		var base_center = Vector2(b_spawn.grid_pos.x + 1.0, b_spawn.grid_pos.y + 1.0)
		
		# 1. Spawn Starting HQ on grid with deterministic ID
		var hq_id = b_spawn.slot * 10000 + 1
		var _hq_inst = buildings.place_building("hq", b_spawn.grid_pos, b_spawn.slot, active_map, economy, true, hq_id)
		
		# 2. Spawn 2 Free Starting Stone Mines and 2 Free Iron Mines on near resource deposits
		var base_stone_nodes: Array = []
		var base_iron_nodes: Array = []
		for r in active_map.resources:
			var d = base_center.distance_to(Vector2(r.grid_pos.x, r.grid_pos.y))
			if d <= 8.0:
				if r.type == MapData.ResourceType.STONE:
					base_stone_nodes.append(r)
				elif r.type == MapData.ResourceType.IRON:
					base_iron_nodes.append(r)
					
		base_stone_nodes.sort_custom(func(a, b): return base_center.distance_to(Vector2(a.grid_pos.x, a.grid_pos.y)) < base_center.distance_to(Vector2(b.grid_pos.x, b.grid_pos.y)))
		base_iron_nodes.sort_custom(func(a, b): return base_center.distance_to(Vector2(a.grid_pos.x, a.grid_pos.y)) < base_center.distance_to(Vector2(b.grid_pos.x, b.grid_pos.y)))
		
		# Place 2 starter Stone Mines
		for s_idx in range(mini(2, base_stone_nodes.size())):
			var s_node = base_stone_nodes[s_idx]
			var s_id = b_spawn.slot * 10000 + 10 + s_idx
			buildings.place_building("stone_mine", s_node.grid_pos, b_spawn.slot, active_map, economy, true, s_id)
			
		# Place 2 starter Iron Mines
		for i_idx in range(mini(2, base_iron_nodes.size())):
			var i_node = base_iron_nodes[i_idx]
			var i_id = b_spawn.slot * 10000 + 20 + i_idx
			buildings.place_building("iron_mine", i_node.grid_pos, b_spawn.slot, active_map, economy, true, i_id)
		
		# 3. Spawn starting Worker Drone next to HQ with deterministic ID
		var spawn_pos = Vector2((b_spawn.grid_pos.x + 2.0) * TILE_PX, (b_spawn.grid_pos.y + 2.0) * TILE_PX)
		var drone_id = b_spawn.slot * 10000 + 1
		var drone = units.spawn_unit("worker_drone", b_spawn.slot, spawn_pos, drone_id)
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
	if is_game_over: return
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
				elif active_production_modal != null and is_instance_valid(active_production_modal):
					active_production_modal.queue_free()
					active_production_modal = null
				elif active_lab_modal != null and is_instance_valid(active_lab_modal):
					active_lab_modal.queue_free()
					active_lab_modal = null
				else:
					_toggle_esc_settings_modal()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_F3:
				_toggle_f3_diagnostics()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_T and not in_game_chat_input.has_focus():
				in_game_chat_input.grab_focus()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if f3_diagnostics_overlay != null and f3_diagnostics_overlay.visible:
		_update_f3_diagnostics()
		
	if not is_paused:
		if match_timer_seconds > 0:
			match_timer_seconds -= delta
			_update_timer_display()
			
		# Subsystem update loop strictly filtering local slot for private economy
		buildings.update_timers(delta, local_slot, research)
		economy.update_grid(delta, buildings.building_instances, local_slot, research)
		units.update_units(delta, active_map, buildings.building_instances, economy, TILE_PX, local_slot, research)
		combat.update_combat(delta, buildings.building_instances, units.units, active_map, economy, TILE_PX, local_slot, research)
		
		# Bot AI Update (Host / Server / Offline authority)
		if bot_ai != null and (network_manager == null or network_manager.is_host):
			bot_ai.update(delta, active_map, buildings, units, TILE_PX)
			
		_update_bot_status_ui()
		
		# Periodic units snapshot sync (5 Hz heartbeat)
		if network_manager != null:
			snapshot_timer += delta
			if snapshot_timer >= 0.2:
				snapshot_timer = 0.0
				var snap = units.get_units_snapshot(local_slot)
				if not snap.is_empty():
					network_manager.send_units_snapshot(local_slot, snap)
		
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
		{"id": "stone_mine", "name": "🪨 Kopalnia Kamienia"},
		{"id": "iron_mine", "name": "⚙️ Kopalnia Żelaza"},
		{"id": "oil_pump", "name": "🛢️ Pompa Ropy"},
		{"id": "redstone_mine", "name": "🔴 Kopalnia Czerwienitu"},
		{"id": "pylon", "name": "⚡ Pylon Zasilania"},
		{"id": "power_plant", "name": "🏭 Elektrownia"},
		{"id": "battery", "name": "🔋 Bank Energii"},
		{"id": "factory", "name": "🏗️ Fabryka"},
		{"id": "storage", "name": "📦 Magazyn"},
		{"id": "wall", "name": "🧱 Mur Obronny"},
		{"id": "turret", "name": "🎯 Wieżyczka Laserowa"},
		{"id": "lab", "name": "🔬 Przetwórnia Danych"},
		{"id": "DEMOLISH", "name": "💥 Zniszcz budynek"}
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
		btn.mouse_entered.connect(func(): _show_building_card(b_id, btn.global_position))
		btn.mouse_exited.connect(_hide_building_card)
		bvbox.add_child(btn)

func _show_building_card(b_id: String, btn_pos: Vector2) -> void:
	_hide_building_card()
	
	building_card_popup = PanelContainer.new()
	building_card_popup.custom_minimum_size = Vector2(340, 0)
	var sb = UITheme.create_panel_style(
		Color(0.03, 0.06, 0.12, 0.98),
		UITheme.COLOR_ACCENT_CYAN,
		6, 2, 12
	)
	building_card_popup.add_theme_stylebox_override("panel", sb)
	building_card_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(building_card_popup)
	
	# Position to the right of the left construction menu
	var card_x = btn_pos.x + 184.0
	var card_y = clampf(btn_pos.y - 20.0, 75.0, get_viewport_rect().size.y - 280.0)
	building_card_popup.global_position = Vector2(card_x, card_y)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 8)
	building_card_popup.add_child(cvbox)
	
	if b_id == "DEMOLISH":
		var h_title = Label.new()
		h_title.text = "💥 WYBURZANIE STRUKTURY"
		h_title.add_theme_font_size_override("font_size", 16)
		h_title.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
		cvbox.add_child(h_title)
		
		var d_desc = Label.new()
		d_desc.text = "Kliknij LPM na dowolnym własnym budynku, aby go zdemontować.\n\n💰 Zwraca 50% zainwestowanych surowców bezpośrednio do magazynu."
		d_desc.add_theme_font_size_override("font_size", 13)
		d_desc.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
		d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cvbox.add_child(d_desc)
		return
		
	var def = buildings.get_def(b_id)
	if def == null: return
	
	# --- 1. HEADER ROW: Image Preview + Name + Category ---
	var h_row = HBoxContainer.new()
	h_row.add_theme_constant_override("separation", 10)
	cvbox.add_child(h_row)
	
	var img_panel = PanelContainer.new()
	img_panel.custom_minimum_size = Vector2(56, 56)
	var img_sb = UITheme.create_panel_style(Color(0.06, 0.12, 0.20, 0.95), UITheme.COLOR_ACCENT_CYAN, 4, 1, 6)
	img_panel.add_theme_stylebox_override("panel", img_sb)
	h_row.add_child(img_panel)
	
	var tex = buildings.textures_cache.get(b_id, null)
	if tex == null:
		var tex_path = "res://public/sprites/buildings/%s.png" % def.sprite_key
		tex = UITheme.load_texture_safe(tex_path)
		
	if tex != null:
		var trect = TextureRect.new()
		trect.texture = tex
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.custom_minimum_size = Vector2(48, 48)
		trect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		trect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		img_panel.add_child(trect)
	else:
		var ico_lbl = Label.new()
		ico_lbl.text = "🏛️"
		ico_lbl.add_theme_font_size_override("font_size", 28)
		ico_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ico_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		img_panel.add_child(ico_lbl)
		
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	h_row.add_child(title_vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = def.name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	title_vbox.add_child(name_lbl)
	
	var cat_str = "ROZMIAR %dx%d · %d HP" % [def.size.x, def.size.y, def.max_hp]
	var cat_lbl = Label.new()
	cat_lbl.text = "%s (%s)" % [def.category, cat_str]
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	title_vbox.add_child(cat_lbl)
	
	# Separator
	var sep1 = HSeparator.new()
	sep1.add_theme_stylebox_override("separator", UITheme.create_panel_style(Color(0.14, 0.28, 0.44, 0.5), Color.TRANSPARENT, 0, 0, 1))
	cvbox.add_child(sep1)
	
	# --- 2. KOSZT BUDOWY ---
	var cost_vbox = VBoxContainer.new()
	cost_vbox.add_theme_constant_override("separation", 3)
	cvbox.add_child(cost_vbox)
	
	var c_title = Label.new()
	c_title.text = "💰 KOSZT BUDOWY:"
	c_title.add_theme_font_size_override("font_size", 11)
	c_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	cost_vbox.add_child(c_title)
	
	var cost_row = HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 10)
	cost_vbox.add_child(cost_row)
	
	var cost_dict = def.cost
	var res_icons = {
		"stone": {"name": "Kamień", "icon": "🪨", "have": economy.stone},
		"iron": {"name": "Żelazo", "icon": "⚙️", "have": economy.iron},
		"oil": {"name": "Ropa", "icon": "🛢️", "have": economy.oil},
		"redstone": {"name": "Czerwienit", "icon": "🔴", "have": economy.redstone}
	}
	
	var has_cost = false
	for r_key in ["stone", "iron", "oil", "redstone"]:
		var req = cost_dict.get(r_key, 0)
		if req > 0:
			has_cost = true
			var r_info = res_icons[r_key]
			var enough = (r_info.have >= req)
			var r_lbl = Label.new()
			r_lbl.text = "%s %d" % [r_info.icon, req]
			r_lbl.add_theme_font_size_override("font_size", 12)
			r_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN if enough else UITheme.COLOR_ACCENT_RED)
			cost_row.add_child(r_lbl)
			
	if not has_cost:
		var free_lbl = Label.new()
		free_lbl.text = "Darmowe (0)"
		free_lbl.add_theme_font_size_override("font_size", 12)
		free_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
		cost_row.add_child(free_lbl)
		
	# --- 3. BILANS ENERGETYCZNY & STATYSTYKI ---
	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 2)
	cvbox.add_child(stats_vbox)
	
	if def.power_generation > 0:
		var p_lbl = Label.new()
		p_lbl.text = "⚡ Produkcja energii: +%d kW" % def.power_generation
		p_lbl.add_theme_font_size_override("font_size", 12)
		p_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
		stats_vbox.add_child(p_lbl)
		
	if def.power_draw_active > 0:
		var p_lbl = Label.new()
		p_lbl.text = "⚡ Zużycie prądu: -%d kW (Aktywne) / -%d kW (Czuwanie)" % [def.power_draw_active, def.power_draw_standby]
		p_lbl.add_theme_font_size_override("font_size", 12)
		p_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_ORANGE)
		stats_vbox.add_child(p_lbl)
	elif def.power_generation == 0 and def.power_draw_active == 0:
		var p_lbl = Label.new()
		p_lbl.text = "⚡ Zużycie prądu: Brak (0 kW)"
		p_lbl.add_theme_font_size_override("font_size", 12)
		p_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		stats_vbox.add_child(p_lbl)
		
	if def.battery_capacity_bonus > 0:
		var b_lbl = Label.new()
		b_lbl.text = "🔋 Pojemność baterii: +%d kJ" % def.battery_capacity_bonus
		b_lbl.add_theme_font_size_override("font_size", 12)
		b_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
		stats_vbox.add_child(b_lbl)
		
	if def.storage_bonus > 0:
		var s_lbl = Label.new()
		s_lbl.text = "📦 Pojemność magazynu bazy: +%d jedn." % def.storage_bonus
		s_lbl.add_theme_font_size_override("font_size", 12)
		s_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
		stats_vbox.add_child(s_lbl)
		
	if def.ammo_cost_iron > 0:
		var a_lbl = Label.new()
		a_lbl.text = "🎯 Amunicja: 1 Żelazo / pocisk (Szybkostrzelność: 0.25s)"
		a_lbl.add_theme_font_size_override("font_size", 12)
		a_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
		stats_vbox.add_child(a_lbl)
		
	# --- 4. OPIS TAKTYCZNY ---
	var desc_lbl = Label.new()
	var desc_text = ""
	match b_id:
		"stone_mine": desc_text = "Wymaga postawienia na złożu kamienia. Drony wydobywają surowiec i transportują do Kwatery."
		"iron_mine": desc_text = "Wymaga postawienia na złożu żelaza. Kluczowe źródło metalu do budowy i amunicji."
		"oil_pump": desc_text = "Wymaga postawienia na złożu ropy. Paliwo do fabryk i jednostek zmechanizowanych."
		"redstone_mine": desc_text = "Wymaga postawienia na złożu czerwienitu. Niezbędny do technologii i zaawansowanych baterii."
		"pylon": desc_text = "Przesyła prąd i rozszerza pole zasilania bazy o 3 kratki w każdym kierunku."
		"power_plant": desc_text = "Wytwarza 100 kW stabilnej energii dla całej bazy i struktur obronnych."
		"battery": desc_text = "Magazynuje nadwyżki energii (500 kJ) na wypadek przeciążenia sieci."
		"factory": desc_text = "Produkuje roboty bojowe (Scoutbot, EMP Drone, Terminus Titan). Posiada ruchome okno produkcyjne."
		"storage": desc_text = "Zwiększa maksymalną pojemność każdego zebranych surowców o 500 jednostek."
		"wall": desc_text = "Solidna przeszkoda terenowa o wysokiej wytrzymałości (600 HP)."
		"turret": desc_text = "Szybki laser obronny. Atakuje wrogie jednostki i struktury w zasięgu 3 kratek (1 pocisk/0.25s)."
		"lab": desc_text = "Centrum badań i ulepszeń. Pozwala tworzyć, odkrywać i sprzedawać karty technologiczne."
		_: desc_text = "Struktura budowlana."
		
	desc_lbl.text = desc_text
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cvbox.add_child(desc_lbl)

func _hide_building_card() -> void:
	if building_card_popup != null and is_instance_valid(building_card_popup):
		building_card_popup.queue_free()
		building_card_popup = null

func _show_camp_card(camp: MapData.CampNode, screen_pos: Vector2) -> void:
	if camp == null or camp.hp <= 0:
		_hide_camp_card()
		return
		
	if camp_card_popup != null and last_hovered_camp == camp and is_instance_valid(camp_card_popup):
		_position_camp_card(screen_pos)
		return
		
	_hide_camp_card()
	last_hovered_camp = camp
	
	camp_card_popup = PanelContainer.new()
	camp_card_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camp_card_popup.custom_minimum_size = Vector2(360, 0)
	var is_boss = (camp.type == MapData.CampType.BOSS)
	var border_col = UITheme.COLOR_WARNING_GOLD if is_boss else UITheme.COLOR_ACCENT_ORANGE
	var sb = UITheme.create_panel_style(Color(0.02, 0.05, 0.10, 0.96), border_col, 6, 2, 14)
	camp_card_popup.add_theme_stylebox_override("panel", sb)
	add_child(camp_card_popup)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	camp_card_popup.add_child(vbox)
	
	# Header
	var title_lbl = Label.new()
	title_lbl.text = "☠️ CYBER-BEHEMOTH [BOSS 2.0]" if is_boss else "⚔️ WROGIE OBOZOWISKO [POZIOM 2]"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", border_col)
	vbox.add_child(title_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "ZAGROŻENIE: EKSTREMALNE · BASTION CENTRALNY" if is_boss else "ZAGROŻENIE: ŚREDNIE · UGRUPOWANIE ZBUNTOWANYCH ROBOTÓW"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if is_boss else Color(1.0, 0.7, 0.2))
	vbox.add_child(sub_lbl)
	
	var sep1 = HSeparator.new()
	sep1.add_theme_stylebox_override("separator", UITheme.create_separator_style(border_col))
	vbox.add_child(sep1)
	
	# HP Stat
	var hp_row = HBoxContainer.new()
	vbox.add_child(hp_row)
	var hp_title = Label.new()
	hp_title.text = "❤️ Punkty Życia:"
	hp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_title.add_theme_font_size_override("font_size", 12)
	hp_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	hp_row.add_child(hp_title)
	
	var hp_val = Label.new()
	var pct = int((float(camp.hp) / float(camp.max_hp)) * 100.0)
	hp_val.text = "%d / %d HP (%d%%)" % [camp.hp, camp.max_hp, pct]
	hp_val.add_theme_font_size_override("font_size", 12)
	hp_val.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN if pct > 40 else UITheme.COLOR_ACCENT_RED)
	hp_row.add_child(hp_val)
	
	# Defense stat
	var def_row = HBoxContainer.new()
	vbox.add_child(def_row)
	var def_title = Label.new()
	def_title.text = "🛡️ Pancerz / Odporność:"
	def_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	def_title.add_theme_font_size_override("font_size", 12)
	def_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	def_row.add_child(def_title)
	
	var def_val = Label.new()
	def_val.text = "Pancerz Ciężki Tytanowy" if is_boss else "Pancerz Średni Wzmocniony"
	def_val.add_theme_font_size_override("font_size", 12)
	def_val.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	def_row.add_child(def_val)
	
	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", UITheme.create_separator_style(Color(0.2, 0.3, 0.4, 0.4)))
	vbox.add_child(sep2)
	
	# Loot Section
	var loot_title = Label.new()
	loot_title.text = "🎁 GWARANTOWANY ŁUP PO ZNISZCZENIU:"
	loot_title.add_theme_font_size_override("font_size", 12)
	loot_title.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	vbox.add_child(loot_title)
	
	var loot_res = Label.new()
	if is_boss:
		loot_res.text = "• +300 🪨 Kamień  • +300 ⚙️ Żelazo  • +150 🛢️ Ropa\n• 🧬 1x Rzadka Karta Technologii do Przetwórni\n• 🏆 +300 punktów zwycięstwa meczu"
	else:
		loot_res.text = "• +100 🪨 Kamień  • +100 ⚙️ Żelazo  • +50 🛢️ Ropa\n• 🧬 1x Karta Badań Przetwórni Danych\n• 🏆 +100 punktów zwycięstwa meczu"
	loot_res.add_theme_font_size_override("font_size", 11)
	loot_res.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	vbox.add_child(loot_res)
	
	# Tactical Hint
	var hint_lbl = Label.new()
	hint_lbl.text = "Kliknij PPM swoimi jednostkami, aby wydać rozkaz natarcia."
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	vbox.add_child(hint_lbl)
	
	_position_camp_card(screen_pos)

func _position_camp_card(screen_pos: Vector2) -> void:
	if camp_card_popup == null: return
	var vp_sz = get_viewport_rect().size
	var target_pos = screen_pos + Vector2(20, -30)
	if target_pos.x + 370 > vp_sz.x:
		target_pos.x = screen_pos.x - 370
	if target_pos.y + 250 > vp_sz.y:
		target_pos.y = vp_sz.y - 260
	if target_pos.y < 10:
		target_pos.y = 10
	camp_card_popup.global_position = target_pos

func _hide_camp_card() -> void:
	if camp_card_popup != null and is_instance_valid(camp_card_popup):
		camp_card_popup.queue_free()
		camp_card_popup = null
	last_hovered_camp = null

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
	# Bot Status Overlay (above minimap)
	var bot_status_panel = PanelContainer.new()
	bot_status_panel.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	bot_status_panel.position = Vector2(-220, -320)
	bot_status_panel.custom_minimum_size = Vector2(204, 0)
	var sb_bot = UITheme.create_panel_style(Color(0.02, 0.04, 0.08, 0.90), Color(0.15, 0.28, 0.44, 0.6), 4, 1, 6)
	bot_status_panel.add_theme_stylebox_override("panel", sb_bot)
	add_child(bot_status_panel)
	
	bot_status_vbox = VBoxContainer.new()
	bot_status_vbox.add_theme_constant_override("separation", 3)
	bot_status_panel.add_child(bot_status_vbox)
	
	# Minimap Panel
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

func _update_bot_status_ui() -> void:
	if bot_status_vbox == null or bot_ai == null: return
	
	for c in bot_status_vbox.get_children():
		c.queue_free()
		
	if bot_ai.active_bots.is_empty():
		bot_status_vbox.get_parent().visible = false
		return
		
	bot_status_vbox.get_parent().visible = true
	
	var hdr = Label.new()
	hdr.text = "🤖 STATUS BOTÓW:"
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	bot_status_vbox.add_child(hdr)
	
	for b in bot_ai.active_bots:
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else UITheme.COLOR_TEXT_LIGHT
		var lbl = Label.new()
		lbl.text = "• %s: %s" % [b.data.name, b.current_status]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", slot_col)
		bot_status_vbox.add_child(lbl)

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
			UnitManager.UnitState.CONSTRUCTING:
				var b_name = u.target_building.name if u.target_building != null else "budynek"
				var b_pct = int(u.target_building.build_progress * 100.0) if u.target_building != null else 0
				status_text = "🔨 Buduje: %s (%d%%)" % [b_name, b_pct]
			UnitManager.UnitState.MINING:
				var res_name = "Kamień"
				if u.target_resource:
					match u.target_resource.type:
						MapData.ResourceType.STONE: res_name = "🪨 Kamień"
						MapData.ResourceType.IRON: res_name = "⚙️ Żelazo"
						MapData.ResourceType.OIL: res_name = "🛢️ Ropa"
						MapData.ResourceType.REDSTONE: res_name = "🔴 Czerwienit"
				status_text = "⛏️ Wydobywa %s (%d/%d)" % [res_name, u.carried_amount, u.max_carry]
			UnitManager.UnitState.RETURNING_TO_HQ:
				var res_name = "Surowiec"
				match u.carried_type:
					MapData.ResourceType.STONE: res_name = "🪨 Kamień"
					MapData.ResourceType.IRON: res_name = "⚙️ Żelazo"
					MapData.ResourceType.OIL: res_name = "🛢️ Ropa"
					MapData.ResourceType.REDSTONE: res_name = "🔴 Czerwienit"
				status_text = "🚚 Transport %s (%d) -> Baza" % [res_name, u.carried_amount]
			UnitManager.UnitState.MOVING, UnitManager.UnitState.MOVING_TO_RESOURCE:
				status_text = "🏃 Ruch do celu"
			UnitManager.UnitState.ATTACKING:
				status_text = "⚔️ Atakowanie wroga"
				
		var stat_lbl = Label.new()
		stat_lbl.text = status_text
		stat_lbl.add_theme_font_size_override("font_size", 12)
		if u.state == UnitManager.UnitState.CONSTRUCTING:
			stat_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
		else:
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
		
	# 3. Boss Area & Neutral Camps 2.0
	for c in active_map.camps:
		if c.hp <= 0: continue
		var c_world = origin + Vector2((c.grid_pos.x + 0.5) * tile_sz, (c.grid_pos.y + 0.5) * tile_sz)
		if c.type == MapData.CampType.BOSS:
			# Boss 2.0: 5x5 restricted zone with hazard crosshatch and 3x3 fortified bastion
			var boss_zone = Rect2(c_world - Vector2(tile_sz * 2.5, tile_sz * 2.5), Vector2(tile_sz * 5.0, tile_sz * 5.0))
			map_viewport.draw_rect(boss_zone, Color(0.35, 0.05, 0.08, 0.20), true)
			map_viewport.draw_rect(boss_zone, Color(0.95, 0.25, 0.25, 0.75), false, 2.0)
			
			# Fortified Bastion Core (3x3)
			var core_rect = Rect2(c_world - Vector2(tile_sz * 1.5, tile_sz * 1.5), Vector2(tile_sz * 3.0, tile_sz * 3.0))
			map_viewport.draw_rect(core_rect, Color(0.10, 0.02, 0.04, 0.90), true)
			map_viewport.draw_rect(core_rect, UITheme.COLOR_WARNING_GOLD, false, 2.5)
			
			# Pulsating Central Core Reactor
			map_viewport.draw_circle(c_world, tile_sz * 1.0, Color(0.9, 0.15, 0.2, 0.85))
			map_viewport.draw_circle(c_world, tile_sz * 0.6, Color(1.0, 0.4, 0.2, 0.95))
			map_viewport.draw_circle(c_world, tile_sz * 0.25, Color(1.0, 0.95, 0.5, 1.0))
			
			# Bastion Spikes / Turret Emplacements at 4 corners
			for offset in [Vector2(-1.3, -1.3), Vector2(1.3, -1.3), Vector2(-1.3, 1.3), Vector2(1.3, 1.3)]:
				var spike_pos = c_world + offset * tile_sz
				map_viewport.draw_circle(spike_pos, 5.0 * map_zoom, Color(1.0, 0.3, 0.3))
				map_viewport.draw_line(c_world, spike_pos, Color(1.0, 0.2, 0.2, 0.5), 1.5)
				
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-48, -tile_sz * 1.6), "☠️ CYBER-BEHEMOTH", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, UITheme.COLOR_WARNING_GOLD)
			_draw_health_bar(c_world + Vector2(0, tile_sz * 1.7), c.hp, c.max_hp, 90.0 * map_zoom, true)
		else:
			# Neutral Camp 2.0: 2x2 Fortified Bunker Outpost
			var camp_rect = Rect2(c_world - Vector2(tile_sz * 0.9, tile_sz * 0.9), Vector2(tile_sz * 1.8, tile_sz * 1.8))
			map_viewport.draw_rect(camp_rect, Color(0.18, 0.08, 0.02, 0.85), true)
			map_viewport.draw_rect(camp_rect, UITheme.COLOR_ACCENT_ORANGE, false, 2.0)
			
			# Inner Bunker Core
			map_viewport.draw_circle(c_world, tile_sz * 0.65, Color(0.9, 0.45, 0.1, 0.9))
			map_viewport.draw_circle(c_world, tile_sz * 0.35, Color(1.0, 0.75, 0.2, 0.95))
			
			# Barbed Outpost corner nodes
			for offset in [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8), Vector2(0.8, 0.8)]:
				var p_pos = c_world + offset * tile_sz
				map_viewport.draw_circle(p_pos, 3.5 * map_zoom, Color(1.0, 0.6, 0.1))
				
			map_viewport.draw_string(ThemeDB.fallback_font, c_world + Vector2(-42, -tile_sz * 1.05), "⚔️ WROGI POSTERUNEK", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, UITheme.COLOR_ACCENT_ORANGE)
			_draw_health_bar(c_world + Vector2(0, tile_sz * 1.15), c.hp, c.max_hp, 60.0 * map_zoom, true)

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

	# 4.5 High-Voltage Electric Power Transmission Lines (Linie wysokiego napięcia)
	var power_emitters = buildings.building_instances.filter(func(b): 
		return (b.def_id in ["hq", "pylon", "power_plant"]) and b.build_progress >= 1.0
	)
	for i in range(power_emitters.size()):
		var b1 = power_emitters[i]
		var c1 = origin + (Vector2(b1.grid_pos) + Vector2(b1.size) * 0.5) * tile_sz
		var center1_tile = b1.grid_pos + Vector2i(1, 1) if b1.def_id == "hq" else b1.grid_pos
		
		for j in range(i + 1, power_emitters.size()):
			var b2 = power_emitters[j]
			if b1.slot != b2.slot: continue
			
			var center2_tile = b2.grid_pos + Vector2i(1, 1) if b2.def_id == "hq" else b2.grid_pos
			
			# Connect only if pylons/nodes are strictly within each other's power field
			var in_range = BuildingSystem.is_tile_powered(center2_tile, [b1], b1.slot) or BuildingSystem.is_tile_powered(center1_tile, [b2], b2.slot)
			
			if in_range:
				var c2 = origin + (Vector2(b2.grid_pos) + Vector2(b2.size) * 0.5) * tile_sz
				var slot_col = GameState.SLOT_COLORS[b1.slot] if b1.slot < GameState.SLOT_COLORS.size() else UITheme.COLOR_ACCENT_CYAN
				
				# Electric Glow halo
				map_viewport.draw_line(c1, c2, Color(slot_col.r, slot_col.g, slot_col.b, 0.25), 6.0 * map_zoom)
				# Main cable sheath
				map_viewport.draw_line(c1, c2, Color(0.04, 0.10, 0.18, 0.90), 3.0 * map_zoom)
				# High-voltage energetic core line
				map_viewport.draw_line(c1, c2, Color(slot_col.r, slot_col.g, slot_col.b, 0.95), 1.5 * map_zoom)
				
				# Insulator terminal nodes
				map_viewport.draw_circle(c1, 4.0 * map_zoom, Color(slot_col.r, slot_col.g, slot_col.b, 0.8))
				map_viewport.draw_circle(c2, 4.0 * map_zoom, Color(slot_col.r, slot_col.g, slot_col.b, 0.8))

	# 5. Buildings
	for b in buildings.building_instances:
		if b.hp <= 0: continue
		var b_pos = origin + Vector2(b.grid_pos.x * tile_sz, b.grid_pos.y * tile_sz)
		var b_box = Rect2(b_pos, Vector2(b.size.x * tile_sz, b.size.y * tile_sz))
		var is_ghost = (b.build_progress < 1.0)
		var modulate_col = Color(1.0, 1.0, 1.0, 0.45) if is_ghost else Color.WHITE
		
		if b.sprite_texture != null:
			if is_ghost:
				map_viewport.draw_texture_rect(b.sprite_texture, b_box, false, modulate_col)
			else:
				map_viewport.draw_texture_rect(b.sprite_texture, b_box, false)
		else:
			var fill_c = Color(0.12, 0.28, 0.44, 0.45) if is_ghost else Color(0.12, 0.28, 0.44, 0.9)
			map_viewport.draw_rect(b_box, fill_c, true)
			map_viewport.draw_rect(b_box, UITheme.COLOR_ACCENT_CYAN, false, 1.5)
			
		var slot_col = GameState.SLOT_COLORS[b.slot] if b.slot < GameState.SLOT_COLORS.size() else Color.WHITE
		var border_alpha = 0.5 if is_ghost else 1.0
		map_viewport.draw_rect(b_box, Color(slot_col.r, slot_col.g, slot_col.b, border_alpha), false, 1.5)
		
		# Draw construction blueprint progress bar above building if unbuilt
		if is_ghost:
			var bar_w = maxf(44.0 * map_zoom, b_box.size.x * 0.8)
			var bar_h = 6.0 * map_zoom
			var bar_pos = Vector2(b_box.get_center().x - bar_w * 0.5, b_box.position.y - 14.0 * map_zoom)
			var bg_rect = Rect2(bar_pos, Vector2(bar_w, bar_h))
			map_viewport.draw_rect(bg_rect, Color(0.05, 0.08, 0.12, 0.9), true)
			map_viewport.draw_rect(bg_rect, Color(0.2, 0.4, 0.6, 0.8), false, 1.0)
			var fill_w = bar_w * clampf(b.build_progress, 0.0, 1.0)
			if fill_w > 0:
				map_viewport.draw_rect(Rect2(bar_pos, Vector2(fill_w, bar_h)), UITheme.COLOR_ACCENT_CYAN, true)
			var pct_txt = "%d%%" % int(b.build_progress * 100.0)
			map_viewport.draw_string(ThemeDB.fallback_font, bar_pos + Vector2(bar_w * 0.5 - 12, -3), pct_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, UITheme.COLOR_ACCENT_CYAN)
		
		# Draw EMP Overload indicator if building is overloaded
		if b.emp_overload_timer > 0.0:
			map_viewport.draw_rect(b_box, Color(0.15, 0.45, 0.95, 0.30), true)
			map_viewport.draw_rect(b_box, Color(0.35, 0.75, 1.0, 0.90), false, 2.0)
			var ov_txt = "⚡ EMP (%ds)" % int(ceil(b.emp_overload_timer))
			map_viewport.draw_string(ThemeDB.fallback_font, b_pos + Vector2(0, -4 * map_zoom), ov_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.8, 1.0))
		
		# Draw Power Grid coverage for Pylons and HQ (tile-based with corner cuts)
		if b.def_id in ["hq", "pylon"] and b.build_progress >= 1.0:
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

	# 8b. Demolish Mode Ghost Cross (X) Preview
	if is_demolish_mode:
		var hovered_dem_b = buildings.get_building_at(hover_grid_pos)
		var dem_rect: Rect2
		var can_demolish = false
		if hovered_dem_b != null and hovered_dem_b.slot == local_slot and hovered_dem_b.def_id != "hq":
			can_demolish = true
			var b_world = origin + Vector2(hovered_dem_b.grid_pos.x * tile_sz, hovered_dem_b.grid_pos.y * tile_sz)
			dem_rect = Rect2(b_world, Vector2(hovered_dem_b.size.x * tile_sz, hovered_dem_b.size.y * tile_sz))
		else:
			var t_world = origin + Vector2(hover_grid_pos.x * tile_sz, hover_grid_pos.y * tile_sz)
			dem_rect = Rect2(t_world, Vector2(tile_sz, tile_sz))
			
		var fill_col = Color(0.9, 0.1, 0.1, 0.35) if can_demolish else Color(0.8, 0.2, 0.2, 0.18)
		var border_col = UITheme.COLOR_ACCENT_RED if can_demolish else Color(0.8, 0.2, 0.2, 0.6)
		
		map_viewport.draw_rect(dem_rect, fill_col, true)
		map_viewport.draw_rect(dem_rect, border_col, false, 2.0)
		
		# Draw diagonal X cross
		map_viewport.draw_line(dem_rect.position, dem_rect.position + dem_rect.size, border_col, 3.0)
		map_viewport.draw_line(Vector2(dem_rect.position.x + dem_rect.size.x, dem_rect.position.y), Vector2(dem_rect.position.x, dem_rect.position.y + dem_rect.size.y), border_col, 3.0)
		
		if can_demolish and hovered_dem_b != null:
			map_viewport.draw_string(ThemeDB.fallback_font, dem_rect.position + Vector2(0, -10), "Zniszcz: %s (+50%% zwrotu)" % hovered_dem_b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.COLOR_ACCENT_RED)
		elif hovered_dem_b != null and hovered_dem_b.def_id == "hq":
			map_viewport.draw_string(ThemeDB.fallback_font, dem_rect.position + Vector2(0, -10), "Nie można zniszczyć Kwatery Głównej!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.COLOR_ACCENT_RED)
		else:
			map_viewport.draw_string(ThemeDB.fallback_font, dem_rect.position + Vector2(0, -10), "Wskaż budynek do wyburzenia", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.COLOR_TEXT_MUTED)

	# 9. Box Selection Marquee (Windows desktop style)
	if is_box_selecting:
		var min_x = minf(box_select_start.x, box_select_current.x)
		var max_x = maxf(box_select_start.x, box_select_current.x)
		var min_y = minf(box_select_start.y, box_select_current.y)
		var max_y = maxf(box_select_start.y, box_select_current.y)
		var sel_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		map_viewport.draw_rect(sel_rect, Color(0.15, 0.55, 0.95, 0.18), true)
		map_viewport.draw_rect(sel_rect, Color(0.35, 0.85, 1.0, 0.90), false, 1.5)

	# 10. Dynamic Hover Tooltip (Etykieta)
	_draw_hover_tooltip(hover_grid_pos, tile_sz, origin)

func _draw_hover_tooltip(grid_pos: Vector2i, tile_sz: float, origin: Vector2) -> void:
	if not active_placing_def_id.is_empty() or is_demolish_mode or is_box_selecting:
		return
		
	var hovered_b = buildings.get_building_at(grid_pos)
	var hovered_res: MapData.ResourceNode = null
	if hovered_b == null:
		for r in active_map.resources:
			if r.grid_pos == grid_pos and r.amount > 0:
				hovered_res = r
				break
				
	if hovered_b == null and hovered_res == null:
		return
		
	var mouse_screen = origin + Vector2((grid_pos.x + 1) * tile_sz, grid_pos.y * tile_sz) + Vector2(16, 16)
	var vp_rect = map_viewport.get_rect()
	
	if hovered_b != null:
		var panel_w = 240.0
		var panel_h = 135.0
		if mouse_screen.x + panel_w > vp_rect.size.x - 20:
			mouse_screen.x = origin.x + grid_pos.x * tile_sz - panel_w - 16
		if mouse_screen.y + panel_h > vp_rect.size.y - 20:
			mouse_screen.y = vp_rect.size.y - panel_h - 20
			
		var t_rect = Rect2(mouse_screen, Vector2(panel_w, panel_h))
		map_viewport.draw_rect(t_rect, Color(0.02, 0.04, 0.08, 0.94), true)
		map_viewport.draw_rect(t_rect, UITheme.COLOR_ACCENT_CYAN, false, 1.5)
		
		# Title
		var slot_name = "Gracz %d" % (hovered_b.slot + 1)
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 22), hovered_b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.COLOR_ACCENT_CYAN)
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 40), "Właściciel: %s" % slot_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.COLOR_TEXT_MUTED)
		
		# Health Bar
		var hp_str = "HP: %d / %d" % [hovered_b.hp, hovered_b.max_hp]
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 58), hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		_draw_health_bar(mouse_screen + Vector2(panel_w * 0.5, 68), hovered_b.hp, hovered_b.max_hp, panel_w - 24.0)
		
		# Build status / Power Status
		var is_built = (hovered_b.build_progress >= 1.0)
		if not is_built:
			var p_txt = "🔨 Budowa: %d%%" % int(hovered_b.build_progress * 100.0)
			map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 92), p_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.COLOR_WARNING_GOLD)
			map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 112), "(PPM dronem, aby budować)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COLOR_ACCENT_CYAN)
		else:
			var is_powered = BuildingSystem.is_tile_powered(hovered_b.grid_pos, buildings.building_instances, hovered_b.slot)
			if hovered_b.slot == local_slot and economy.is_blackout:
				is_powered = false
				
			var pwr_str = "⚡ ZASILANY" if is_powered else "⚠️ BRAK PRĄDU"
			var pwr_col = UITheme.COLOR_SUCCESS_GREEN if is_powered else UITheme.COLOR_ACCENT_RED
			map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 92), pwr_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pwr_col)
			
			# Dynamic Production / Power Draw stats
			var stat_str = ""
			match hovered_b.def_id:
				"hq": stat_str = "Zasilanie: +50 kW · Pojemność: +1000 kJ"
				"power_plant": stat_str = "Zasilanie: +100 kW"
				"pylon": stat_str = "Zasięg: 3 kratki · Pobór: -1 kW"
				"battery": stat_str = "Pojemność: +500 kJ"
				"stone_mine": stat_str = "Wydobycie: +8 Kamień/s · Pobór: -5 kW"
				"iron_mine": stat_str = "Wydobycie: +6 Żelazo/s · Pobór: -8 kW"
				"oil_pump": stat_str = "Wydobycie: +4 Ropa/s · Pobór: -10 kW"
				"redstone_mine": stat_str = "Wydobycie: +3 Czerwienit/s · Pobór: -12 kW"
				"storage": stat_str = "Magazyn: +500 jedn."
				"turret", "wall_turret": stat_str = "Obrona laserowa (6 kr.) · Pobór: -2 kW"
				_: stat_str = "Struktura operacyjna"
				
			map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 112), stat_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COLOR_TEXT_MUTED)

	elif hovered_res != null:
		var panel_w = 210.0
		var panel_h = 80.0
		if mouse_screen.x + panel_w > vp_rect.size.x - 20:
			mouse_screen.x = origin.x + grid_pos.x * tile_sz - panel_w - 16
		if mouse_screen.y + panel_h > vp_rect.size.y - 20:
			mouse_screen.y = vp_rect.size.y - panel_h - 20
			
		var t_rect = Rect2(mouse_screen, Vector2(panel_w, panel_h))
		map_viewport.draw_rect(t_rect, Color(0.02, 0.04, 0.08, 0.94), true)
		map_viewport.draw_rect(t_rect, UITheme.COLOR_WARNING_GOLD, false, 1.5)
		
		var r_name = "Złoże Surowca"
		var req_b = "Kopalnia"
		match hovered_res.type:
			MapData.ResourceType.STONE:
				r_name = "🪨 Złoże Kamienia"
				req_b = "Wymaga: Kopalnia Kamienia"
			MapData.ResourceType.IRON:
				r_name = "⚙️ Złoże Żelaza"
				req_b = "Wymaga: Kopalnia Żelaza"
			MapData.ResourceType.OIL:
				r_name = "🛢️ Źródło Ropy"
				req_b = "Wymaga: Pompa Ropy"
			MapData.ResourceType.REDSTONE:
				r_name = "🔴 Złoże Czerwienitu"
				req_b = "Wymaga: Kopalnia Czerwienitu"
				
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 24), r_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.COLOR_WARNING_GOLD)
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 46), "Pozostałe złoże: %d szt." % hovered_res.amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		map_viewport.draw_string(ThemeDB.fallback_font, mouse_screen + Vector2(12, 66), req_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.COLOR_TEXT_MUTED)

func _draw_health_bar(center_pos: Vector2, hp: int, max_hp: int, bar_width: float, show_text: bool = false) -> void:
	var bar_h = 7.0 if show_text else 5.0
	var bar_rect = Rect2(center_pos - Vector2(bar_width * 0.5, bar_h * 0.5), Vector2(bar_width, bar_h))
	map_viewport.draw_rect(bar_rect, Color(0.06, 0.08, 0.12, 0.9), true)
	map_viewport.draw_rect(bar_rect, Color(0.2, 0.3, 0.4, 0.8), false, 1.0)
	var pct = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var fill_rect = Rect2(bar_rect.position, Vector2(bar_width * pct, bar_h))
	var fill_col = UITheme.COLOR_SUCCESS_GREEN if pct > 0.4 else UITheme.COLOR_ACCENT_RED
	map_viewport.draw_rect(fill_rect, fill_col, true)
	if show_text and map_zoom >= 0.7:
		var hp_str = "%d / %d" % [hp, max_hp]
		map_viewport.draw_string(ThemeDB.fallback_font, center_pos + Vector2(-22, 13), hp_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.95, 0.95, 0.95, 0.95))

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
			
		# Check hover over active camps/boss
		var hovered_camp: MapData.CampNode = null
		if active_placing_def_id.is_empty() and not is_demolish_mode and not is_box_selecting and not is_dragging:
			for c in active_map.camps:
				if c.hp > 0:
					var radius_tiles = 2.5 if c.type == MapData.CampType.BOSS else 1.2
					if (Vector2(c.grid_pos) - Vector2(hover_grid_pos)).length() <= radius_tiles:
						hovered_camp = c
						break
		if hovered_camp != null:
			_show_camp_card(hovered_camp, event.position)
		else:
			_hide_camp_card()
			
		map_viewport.queue_redraw()
		
	elif event is InputEventMouseButton:
		if is_paused and event.button_index != MOUSE_BUTTON_MIDDLE and event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			drag_start = event.position
			
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not active_placing_def_id.is_empty():
					var def = buildings.get_def(active_placing_def_id)
					if def != null and not economy.can_afford(def.cost):
						_show_floating_mouse_alert("⚠️ ZA DROGO!", event.position, UITheme.COLOR_ACCENT_RED)
						in_game_chat_log.append_text("[color=#ff4655]⚠️ Za drogo! Brakuje surowców na postawienie tego budynku![/color]\n")
					else:
						var validation = buildings.is_position_valid_for_building(active_placing_def_id, hover_grid_pos, local_slot, active_map)
						if not validation.valid:
							_show_floating_mouse_alert("⚠️ " + validation.reason, event.position, UITheme.COLOR_ACCENT_ORANGE)
						else:
							var placed = buildings.place_building(active_placing_def_id, hover_grid_pos, local_slot, active_map, economy)
							if placed != null:
								_animate_resource_deductions(def.cost)
								var pts = _get_building_score_points(placed.def_id)
								_add_score(pts, "Postawiono: %s (+%d pkt)" % [placed.name, pts])
								in_game_chat_log.append_text("[color=#00f0ff]Postawiono: [b]%s[/b] (+%d pkt do zwycięstwa)[/color]\n" % [placed.name, pts])
								if network_manager != null:
									network_manager.send_place_building(placed.def_id, hover_grid_pos, local_slot, placed.instance_id)
								map_viewport.queue_redraw()
								if minimap_canvas: minimap_canvas.queue_redraw()
				elif is_demolish_mode:
					# Attempt demolition (continuous mode: stays active until right-click/ESC)
					if buildings.demolish_building_at(hover_grid_pos, local_slot, economy):
						in_game_chat_log.append_text("[color=#ff4655]Zniszczono budynek (Zwrócono 50% surowców)[/color]\n")
						if network_manager != null:
							network_manager.send_demolish_building(hover_grid_pos, local_slot)
						map_viewport.queue_redraw()
						if minimap_canvas: minimap_canvas.queue_redraw()
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
						# Single-click interaction
						var click_world = (event.position - map_camera_pos) / map_zoom
						var click_tile = Vector2i(int(floor(click_world.x / TILE_PX)), int(floor(click_world.y / TILE_PX)))
						
						# Check if clicked own building (HQ, Factory, or Lab)
						var clicked_b = buildings.get_building_at(click_tile)
						if clicked_b != null and clicked_b.slot == local_slot and clicked_b.build_progress >= 1.0:
							if clicked_b.def_id == "hq" or clicked_b.def_id == "factory":
								_open_building_production_modal(clicked_b)
								map_viewport.queue_redraw()
								return
							elif clicked_b.def_id == "lab":
								_open_lab_research_modal(clicked_b)
								map_viewport.queue_redraw()
								return
							
						# Single-click unit selection
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
			
			# 0. Check if clicked an enemy building to attack / EMP
			var target_enemy_b = buildings.get_building_at(clicked_tile)
			if target_enemy_b != null and target_enemy_b.slot != local_slot and target_enemy_b.hp > 0:
				units.command_attack_building(selected_units, target_enemy_b)
				in_game_chat_log.append_text("[color=#ff9f1c]Wydano rozkaz ataku na budynek wroga: [b]%s[/b]![/color]\n" % target_enemy_b.name)
				map_viewport.queue_redraw()
				return

			# 1. Check if clicked an unbuilt/ghost building to construct
			var target_b = buildings.get_building_at(clicked_tile)
			if target_b != null and target_b.slot == local_slot and target_b.build_progress < 1.0:
				units.command_construct(selected_units, target_b)
				in_game_chat_log.append_text("[color=#00f0ff]Dron skierowany do budowy: [b]%s[/b][/color]\n" % target_b.name)
				if network_manager != null:
					var u_ids: Array = []
					for u in selected_units: u_ids.append(u.instance_id)
					network_manager.send_unit_construct(u_ids, target_b.instance_id)
				map_viewport.queue_redraw()
				return

			# 2. Check if clicked resource node (for combat / other units if any)
			var target_res: MapData.ResourceNode = null
			for r in active_map.resources:
				if r.grid_pos == clicked_tile and r.amount > 0:
					target_res = r
					break
					
			if target_res != null:
				in_game_chat_log.append_text("[color=#ffd166]Postaw odpowiednią kopalnię na tym złożu, aby wydobywać surowiec.[/color]\n")
				map_viewport.queue_redraw()
				return
				
			# 3. Check if clicked enemy camp
			var target_camp: MapData.CampNode = null
			for c in active_map.camps:
				if c.hp > 0 and (c.grid_pos - clicked_tile).length() <= 1:
					target_camp = c
					break
					
			if target_camp != null:
				units.command_attack_camp(selected_units, target_camp)
				in_game_chat_log.append_text("[color=#ff9f1c]Wydano rozkaz ataku na obóz/bossa![/color]\n")
				if network_manager != null:
					var u_ids: Array = []
					for u in selected_units: u_ids.append(u.instance_id)
					network_manager.send_unit_attack(u_ids, target_camp.grid_pos)
				map_viewport.queue_redraw()
				return
				
			# 4. Standard move command
			units.command_move(selected_units, click_world)
			if network_manager != null:
				var u_ids: Array = []
				for u in selected_units: u_ids.append(u.instance_id)
				network_manager.send_unit_move(u_ids, click_world)
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
		in_game_chat_log.append_text("[color=#ff4655]Tryb wyburzania: Klikaj kolejne budynki, aby je niszczyć (PPM lub ESC anuluje).[/color]\n")
	else:
		active_placing_def_id = def_id
		is_demolish_mode = false
		var def = buildings.get_def(def_id)
		if def != null:
			if not economy.can_afford(def.cost):
				_show_floating_mouse_alert("⚠️ ZA DROGO!", get_global_mouse_position(), UITheme.COLOR_ACCENT_RED)
				in_game_chat_log.append_text("[color=#ff4655]⚠️ Za drogo! Brakuje surowców na budowę: [b]%s[/b][/color]\n" % def.name)
			else:
				in_game_chat_log.append_text("[color=#00f0ff]Tryb budowy: [b]%s[/b] (Klikaj, aby stawiać; PPM lub ESC anuluje)[/color]\n" % def.name)

func _show_floating_mouse_alert(text: String, screen_pos: Vector2, color: Color = Color(1.0, 0.25, 0.25)) -> void:
	var alert_panel = PanelContainer.new()
	alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = UITheme.create_panel_style(Color(0.18, 0.04, 0.06, 0.96), color, 4, 1, 6)
	alert_panel.add_theme_stylebox_override("panel", sb)
	alert_panel.global_position = screen_pos + Vector2(16, -24)
	add_child(alert_panel)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	alert_panel.add_child(lbl)
	
	# Animate float up and fade out
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(alert_panel, "global_position:y", alert_panel.global_position.y - 35.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(alert_panel, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(alert_panel.queue_free)

func _animate_resource_deductions(cost_dict: Dictionary) -> void:
	for r_key in ["stone", "iron", "oil", "redstone"]:
		var req = cost_dict.get(r_key, 0)
		if req > 0:
			_animate_resource_change(r_key, req, true)

func _animate_resource_change(r_key: String, amount: int, is_deduction: bool = true) -> void:
	var target_lbl: Label = null
	var res_name = ""
	match r_key:
		"stone":
			target_lbl = res_stone_lbl
			res_name = "kamienia"
		"iron":
			target_lbl = res_iron_lbl
			res_name = "żelaza"
		"oil":
			target_lbl = res_oil_lbl
			res_name = "ropy"
		"redstone":
			target_lbl = res_redstone_lbl
			res_name = "czerwienitu"
			
	if target_lbl == null: return
	
	var badge = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_col = Color(0.24, 0.04, 0.06, 0.95) if is_deduction else Color(0.04, 0.22, 0.10, 0.95)
	var border_col = UITheme.COLOR_ACCENT_RED if is_deduction else UITheme.COLOR_SUCCESS_GREEN
	var sb = UITheme.create_panel_style(bg_col, border_col, 3, 1, 4)
	badge.add_theme_stylebox_override("panel", sb)
	
	var pos = target_lbl.global_position + Vector2(0, 24)
	badge.global_position = pos
	add_child(badge)
	
	var l = Label.new()
	l.text = "-%d %s" % [amount, res_name] if is_deduction else "+%d %s" % [amount, res_name]
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", border_col)
	badge.add_child(l)
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(badge, "global_position:y", pos.y + 24.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(badge, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(badge.queue_free)

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

func _open_building_production_modal(b: BuildingSystem.BuildingInstance) -> void:
	if active_production_modal != null and is_instance_valid(active_production_modal):
		active_production_modal.queue_free()
		active_production_modal = null
	var def = buildings.get_def(b.def_id)
	active_production_modal = BuildingProductionModal.new(b, def, economy, units, network_manager)
	active_production_modal.unit_trained.connect(_on_unit_trained)
	active_production_modal.closed.connect(func(): active_production_modal = null)
	add_child(active_production_modal)

func _open_lab_research_modal(b: BuildingSystem.BuildingInstance) -> void:
	if active_lab_modal != null and is_instance_valid(active_lab_modal):
		active_lab_modal.queue_free()
		active_lab_modal = null
	active_lab_modal = LabResearchModal.new(b, economy, research, network_manager)
	active_lab_modal.closed.connect(func(): active_lab_modal = null)
	add_child(active_lab_modal)

func _on_camp_destroyed(camp_node: MapData.CampNode, killer_slot: int) -> void:
	current_score += 300 if camp_node.type == MapData.CampType.BOSS else 100
	if killer_slot == local_slot:
		camps_count += 1
		var s_amt = 300 if camp_node.type == MapData.CampType.BOSS else 100
		var i_amt = 300 if camp_node.type == MapData.CampType.BOSS else 100
		var o_amt = 150 if camp_node.type == MapData.CampType.BOSS else 50
		_animate_resource_change("stone", s_amt, false)
		_animate_resource_change("iron", i_amt, false)
		_animate_resource_change("oil", o_amt, false)
	if score_lbl != null:
		score_lbl.text = "★ %d / %d pkt" % [current_score, target_score]
		
	var camp_name = "Boss (Baza Centralna)" if camp_node.type == MapData.CampType.BOSS else "Wrogie Obozowisko"
	if killer_slot == local_slot:
		in_game_chat_log.append_text("[color=#00ff88]Zniszczono: [b]%s[/b]! Otrzymano surowce oraz kartę technologii![/color]\n" % camp_name)
	else:
		in_game_chat_log.append_text("[color=#ffaa00]Gracz %d zniszczył %s![/color]\n" % [killer_slot + 1, camp_name])
	_update_resource_labels()

func _on_unit_killed_reward(stone: int, iron: int, oil: int, redstone: int) -> void:
	kills_count += 1
	in_game_chat_log.append_text("[color=#38bdf8]💀 [b]POKONANO WROGA![/b] Zdobyto: +%d Kamień, +%d Żelazo, +%d Ropa, +%d Czerwienit[/color]\n" % [stone, iron, oil, redstone])
	_add_score(15, "Zabicie jednostki (+15 pkt)")
	if stone > 0: _animate_resource_change("stone", stone, false)
	if iron > 0: _animate_resource_change("iron", iron, false)
	if oil > 0: _animate_resource_change("oil", oil, false)
	if redstone > 0: _animate_resource_change("redstone", redstone, false)
	_update_resource_labels()

func _get_building_score_points(def_id: String) -> int:
	match def_id:
		"hq": return 100
		"lab": return 60
		"factory": return 50
		"power_plant": return 40
		"turret", "wall_turret": return 30
		"mine_stone", "mine_iron", "mine_oil", "mine_redstone": return 25
		"battery", "storage": return 20
		"pylon": return 15
		"wall": return 5
		_: return 15

func _add_score(amount: int, _reason: String = "") -> void:
	current_score += amount
	if score_lbl != null:
		score_lbl.text = "★ %d / %d pkt" % [current_score, target_score]
	if current_score >= target_score and not is_game_over:
		_trigger_victory()

func _on_remote_match_victory(winner_slot: int, winner_name: String, final_score: int) -> void:
	if not is_game_over:
		_trigger_victory(winner_slot, winner_name, final_score, false)

func _trigger_victory(winner_slot: int = -1, winner_name: String = "", final_score: int = -1, broadcast: bool = true) -> void:
	if is_game_over: return
	is_game_over = true
	is_paused = true
	
	if winner_slot < 0:
		winner_slot = local_slot
	if final_score < 0:
		final_score = current_score
	if winner_name.is_empty():
		winner_name = settings_manager.player_name if settings_manager else ("Gracz %d" % (winner_slot + 1))
		
	if broadcast and network_manager != null:
		network_manager.send_match_victory(winner_slot, winner_name, final_score)
		
	in_game_chat_log.append_text("[color=#ffd700]🏆 [b]KONIEC GRY![/b] Gracz %s osiągnął limit punktów (%d / %d pkt)![/color]\n" % [winner_name, final_score, target_score])
	
	# Close any open active sub-windows
	if active_production_modal != null and is_instance_valid(active_production_modal):
		active_production_modal.queue_free()
		active_production_modal = null
	if active_lab_modal != null and is_instance_valid(active_lab_modal):
		active_lab_modal.queue_free()
		active_lab_modal = null
	if active_settings_modal != null and is_instance_valid(active_settings_modal):
		active_settings_modal.queue_free()
		active_settings_modal = null
	if scoreboard_overlay != null and is_instance_valid(scoreboard_overlay):
		scoreboard_overlay.queue_free()
		scoreboard_overlay = null
		
	_show_endgame_victory_modal(winner_slot, winner_name, final_score)

func _show_endgame_victory_modal(winner_slot: int, winner_name: String, final_score: int) -> void:
	# Fullscreen dark scrim layer (blocks all clicks to map & HUD)
	var overlay = PanelContainer.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim_sb = StyleBoxFlat.new()
	scrim_sb.bg_color = Color(0.01, 0.02, 0.05, 0.95)
	overlay.add_theme_stylebox_override("panel", scrim_sb)
	add_child(overlay)
	
	var center_box = CenterContainer.new()
	center_box.set_anchors_preset(PRESET_FULL_RECT)
	overlay.add_child(center_box)
	
	var is_local_winner = (winner_slot == local_slot)
	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(760, 0)
	var border_col = UITheme.COLOR_WARNING_GOLD if is_local_winner else UITheme.COLOR_ACCENT_CYAN
	var panel_sb = UITheme.create_panel_style(Color(0.03, 0.07, 0.14, 0.98), border_col, 8, 3, 24)
	main_panel.add_theme_stylebox_override("panel", panel_sb)
	center_box.add_child(main_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	main_panel.add_child(vbox)
	
	# Header
	var crown = Label.new()
	crown.text = "🏆" if is_local_winner else "👑"
	crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crown.add_theme_font_size_override("font_size", 48)
	vbox.add_child(crown)
	
	var vic_title = Label.new()
	vic_title.text = "MISJA ZAKOŃCZONA SUKCESEM — ZWYCIĘSTWO!" if is_local_winner else "KONIEC MECZU — ZWYCIĘŻYŁ: %s!" % winner_name.to_upper()
	vic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vic_title.add_theme_font_size_override("font_size", 22)
	vic_title.add_theme_color_override("font_color", border_col)
	vbox.add_child(vic_title)
	
	var vic_sub = Label.new()
	vic_sub.text = "Osiągnięto wymagany pułap punktów zwycięstwa: %d / %d pkt" % [final_score, target_score]
	vic_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vic_sub.add_theme_font_size_override("font_size", 14)
	vic_sub.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	vbox.add_child(vic_sub)
	
	var sep1 = HSeparator.new()
	sep1.add_theme_stylebox_override("separator", UITheme.create_separator_style(border_col))
	vbox.add_child(sep1)
	
	# Statistics Section
	var stats_title = Label.new()
	stats_title.text = "📊 STATYSTYKI KOŃCOWE MECZU"
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	vbox.add_child(stats_title)
	
	# Table Header
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(header_hbox)
	
	_add_stat_cell(header_hbox, "POZ", 55, UITheme.COLOR_TEXT_MUTED, true)
	_add_stat_cell(header_hbox, "GRACZ", 170, UITheme.COLOR_TEXT_MUTED, false)
	_add_stat_cell(header_hbox, "PUNKTY", 90, UITheme.COLOR_TEXT_MUTED, true)
	_add_stat_cell(header_hbox, "BUDYNKI", 80, UITheme.COLOR_TEXT_MUTED, true)
	_add_stat_cell(header_hbox, "JEDNOSTKI", 90, UITheme.COLOR_TEXT_MUTED, true)
	_add_stat_cell(header_hbox, "ZABÓJSTWA", 95, UITheme.COLOR_TEXT_MUTED, true)
	_add_stat_cell(header_hbox, "OBOZOWISKA", 95, UITheme.COLOR_TEXT_MUTED, true)
	
	# Gather all players/participants
	var p_list: Array = []
	if network_manager != null:
		p_list = network_manager.get_players_list()
	if p_list.is_empty():
		var dummy = PlayerData.new()
		dummy.name = settings_manager.player_name if settings_manager else "Pracownik"
		dummy.is_host = true
		dummy.slot = local_slot
		dummy.color = GameState.SLOT_COLORS[local_slot]
		p_list.append(dummy)
		
	var stats_list: Array = []
	for p in p_list:
		var slot_bld_count = 0
		var slot_bld_points = 0
		if buildings != null:
			for b in buildings.building_instances:
				if b.slot == p.slot and b.hp > 0:
					slot_bld_count += 1
					slot_bld_points += _get_building_score_points(b.def_id)
					
		var slot_units_count = 0
		if units != null:
			for u in units.units:
				if u.slot == p.slot and u.hp > 0:
					slot_units_count += 1
					
		var p_pts = 0
		var p_kills = 0
		var p_camps = 0
		
		if p.slot == local_slot:
			p_pts = current_score
			p_kills = kills_count
			p_camps = camps_count
		else:
			p_pts = slot_bld_points + (slot_units_count * 15)
			p_kills = maxi(0, slot_units_count / 2)
			p_camps = 0
			if p.slot == winner_slot:
				p_pts = maxi(p_pts, final_score)
				
		stats_list.append({
			"player": p,
			"pts": p_pts,
			"bld": slot_bld_count,
			"units": slot_units_count,
			"kills": p_kills,
			"camps": p_camps
		})
		
	# Sort leaderboard by points descending
	stats_list.sort_custom(func(a, b): return a.pts > b.pts)
	
	var rows_vbox = VBoxContainer.new()
	rows_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(rows_vbox)
	
	var rank_idx = 1
	for st in stats_list:
		var p = st.player
		var row_panel = PanelContainer.new()
		var is_me = (p.slot == local_slot)
		var is_win = (p.slot == winner_slot)
		var row_bg = Color(0.15, 0.12, 0.02, 0.90) if is_win else (Color(0.04, 0.10, 0.20, 0.90) if is_me else Color(0.04, 0.07, 0.12, 0.70))
		var row_border = UITheme.COLOR_WARNING_GOLD if is_win else (UITheme.COLOR_ACCENT_CYAN if is_me else Color(0.15, 0.25, 0.40, 0.50))
		var row_sb = UITheme.create_panel_style(row_bg, row_border, 4, 1, 8)
		row_panel.add_theme_stylebox_override("panel", row_sb)
		rows_vbox.add_child(row_panel)
		
		var row_hbox = HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 10)
		row_panel.add_child(row_hbox)
		
		var rank_str = "#%d" % rank_idx
		if rank_idx == 1: rank_str = "🥇 #1"
		elif rank_idx == 2: rank_str = "🥈 #2"
		elif rank_idx == 3: rank_str = "🥉 #3"
		
		var p_col = p.color if p.color != Color.TRANSPARENT else GameState.SLOT_COLORS[p.slot]
		_add_stat_cell(row_hbox, rank_str, 55, UITheme.COLOR_WARNING_GOLD if rank_idx == 1 else UITheme.COLOR_TEXT_LIGHT, true)
		_add_stat_cell(row_hbox, ("★ " if is_me else "") + p.name, 170, p_col, false)
		_add_stat_cell(row_hbox, "%d pkt" % st.pts, 90, UITheme.COLOR_WARNING_GOLD, true)
		_add_stat_cell(row_hbox, str(st.bld), 80, UITheme.COLOR_TEXT_LIGHT, true)
		_add_stat_cell(row_hbox, str(st.units), 90, UITheme.COLOR_TEXT_LIGHT, true)
		_add_stat_cell(row_hbox, str(st.kills), 95, UITheme.COLOR_ACCENT_RED, true)
		_add_stat_cell(row_hbox, str(st.camps), 95, UITheme.COLOR_SUCCESS_GREEN, true)
		rank_idx += 1
		
	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", UITheme.create_separator_style(Color(0.2, 0.3, 0.4, 0.4)))
	vbox.add_child(sep2)
	
	# Only Action Button: Exit to Main Menu
	var exit_btn = Button.new()
	exit_btn.text = "🚪 WYJDŹ DO MENU GŁÓWNEGO"
	exit_btn.custom_minimum_size = Vector2(280, 48)
	exit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.style_button(exit_btn, Color(0.45, 0.12, 0.15), UITheme.COLOR_ACCENT_RED, 48, 16)
	exit_btn.pressed.connect(func():
		exit_to_menu_requested.emit()
	)
	vbox.add_child(exit_btn)

func _add_stat_cell(parent: Control, text: String, width: float, col: Color, center: bool = true) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)

func _on_card_obtained(_item: ResearchSystem.CardItem) -> void:
	in_game_chat_log.append_text("[color=#00f0ff]Otrzymano nową zaszyfrowaną kartę badań do ekwipunku Przetwórni Danych![/color]\n")

func _on_card_revealed(item: ResearchSystem.CardItem) -> void:
	in_game_chat_log.append_text("[color=#ffd700]ODKRYTO KARTĘ BADAŃ: %s %s (%s)[/color]\n" % [item.def.emoji, item.def.name, item.def.description])

func _on_card_sold(_item: ResearchSystem.CardItem) -> void:
	in_game_chat_log.append_text("[color=#ff9900]Sprzedano kartę technologii za 100%% zwrotu surowców.[/color]\n")
	_update_resource_labels()

func _on_unit_trained(def_id: String, building: BuildingSystem.BuildingInstance) -> void:
	var spawn_pos = Vector2((building.grid_pos.x + building.size.x + 0.5) * TILE_PX, (building.grid_pos.y + 0.5) * TILE_PX)
	var u = units.spawn_unit(def_id, building.slot, spawn_pos)
	if u != null:
		in_game_chat_log.append_text("[color=#00f0ff]Wyprodukowano: [b]%s[/b][/color]\n" % u.name)
		if network_manager != null:
			network_manager.send_unit_spawn(def_id, building.slot, u.instance_id, spawn_pos)
		map_viewport.queue_redraw()
		_update_resource_labels()

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
		scoreboard_overlay = ScoreboardModal.new(network_manager, settings_manager, target_score, buildings, units, economy, local_slot, self)
		add_child(scoreboard_overlay)

func _hide_scoreboard() -> void:
	if scoreboard_overlay != null and is_instance_valid(scoreboard_overlay):
		scoreboard_overlay.queue_free()
		scoreboard_overlay = null

# ==============================================================================
# Remote Network Handlers
# ==============================================================================

func _on_remote_building_placed(def_id: String, grid_pos: Vector2i, slot: int, building_id: int) -> void:
	buildings.spawn_remote_building(def_id, grid_pos, slot, building_id)
	if map_viewport: map_viewport.queue_redraw()
	if minimap_canvas: minimap_canvas.queue_redraw()

func _on_remote_building_demolished(grid_pos: Vector2i, slot: int) -> void:
	buildings.demolish_building_at(grid_pos, slot, null)
	if map_viewport: map_viewport.queue_redraw()
	if minimap_canvas: minimap_canvas.queue_redraw()

func _on_remote_unit_moved(unit_ids: Array, target_pos: Vector2) -> void:
	units.command_move_by_ids(unit_ids, target_pos)
	if map_viewport: map_viewport.queue_redraw()

func _on_remote_unit_constructed(unit_ids: Array, building_id: int) -> void:
	units.command_construct_by_ids(unit_ids, building_id, buildings.building_instances)
	if map_viewport: map_viewport.queue_redraw()

func _on_remote_unit_gathered(unit_ids: Array, res_grid_pos: Vector2i) -> void:
	units.command_gather_by_ids(unit_ids, res_grid_pos, active_map)
	if map_viewport: map_viewport.queue_redraw()

func _on_remote_unit_attacked(unit_ids: Array, camp_grid_pos: Vector2i) -> void:
	units.command_attack_camp_by_ids(unit_ids, camp_grid_pos, active_map)
	if map_viewport: map_viewport.queue_redraw()

func _on_remote_unit_spawned(def_id: String, slot: int, unit_id: int, spawn_pos: Vector2) -> void:
	units.spawn_unit(def_id, slot, spawn_pos, unit_id)
	if map_viewport: map_viewport.queue_redraw()

func _on_remote_units_snapshot(slot: int, snapshot: Array) -> void:
	if slot != local_slot:
		units.apply_units_snapshot(slot, snapshot)

func _on_remote_turret_fired(from_pos: Vector2, to_pos: Vector2, is_wall_turret: bool) -> void:
	combat.spawn_beam(from_pos, to_pos, is_wall_turret)
	if map_viewport: map_viewport.queue_redraw()

func _on_local_turret_fired(from_pos: Vector2, to_pos: Vector2, is_wall_turret: bool) -> void:
	if network_manager != null:
		network_manager.send_turret_fire(from_pos, to_pos, is_wall_turret)

func _on_remote_camp_damaged(camp_grid_pos: Vector2i, damage: int, killer_slot: int) -> void:
	for c in active_map.camps:
		if c.grid_pos == camp_grid_pos and c.hp > 0:
			c.hp -= damage
			if c.hp <= 0 and c.max_hp > 0:
				combat._on_camp_defeated(c, killer_slot, null)
			break
	if map_viewport: map_viewport.queue_redraw()

# ==============================================================================
# F3 Network Diagnostics & Ping Overlay
# ==============================================================================

func _toggle_f3_diagnostics() -> void:
	if f3_diagnostics_overlay == null: return
	f3_diagnostics_overlay.visible = not f3_diagnostics_overlay.visible
	if f3_diagnostics_overlay.visible:
		_update_f3_diagnostics()

func _build_f3_diagnostics_overlay() -> void:
	f3_diagnostics_overlay = PanelContainer.new()
	f3_diagnostics_overlay.set_anchors_preset(PRESET_TOP_LEFT)
	f3_diagnostics_overlay.offset_left = 16.0
	f3_diagnostics_overlay.offset_top = 70.0
	f3_diagnostics_overlay.custom_minimum_size = Vector2(340, 0)
	f3_diagnostics_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f3_diagnostics_overlay.visible = false
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.05, 0.10, 0.94), UITheme.COLOR_ACCENT_CYAN, 6, 2, 12)
	f3_diagnostics_overlay.add_theme_stylebox_override("panel", sb)
	add_child(f3_diagnostics_overlay)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	f3_diagnostics_overlay.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "⚡ DIAGNOSTYKA SIECIOWA & PING [F3]"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	vbox.add_child(title_lbl)
	
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", UITheme.create_separator_style(UITheme.COLOR_ACCENT_CYAN))
	vbox.add_child(sep)
	
	f3_diag_labels["ping"] = _create_f3_hud_diag_row(vbox, "⏱️ PING / OPÓŹNIENIE:", "0 ms")
	f3_diag_labels["status"] = _create_f3_hud_diag_row(vbox, "🌐 STATUS POŁĄCZENIA:", "POŁĄCZONO Z SERWEREM")
	f3_diag_labels["role"] = _create_f3_hud_diag_row(vbox, "👑 ROLA W SESJI:", "HOST SERWER")
	f3_diag_labels["address"] = _create_f3_hud_diag_row(vbox, "📡 ADRES SERWERA:", "127.0.0.1:7777")
	f3_diag_labels["code"] = _create_f3_hud_diag_row(vbox, "🔑 KOD POKOJU:", "ABCD-1234")
	f3_diag_labels["peer"] = _create_f3_hud_diag_row(vbox, "🆔 MULTI-PEER ID:", "1")
	f3_diag_labels["players"] = _create_f3_hud_diag_row(vbox, "👥 GRACZE W GRZE:", "1 / 4")
	f3_diag_labels["fps"] = _create_f3_hud_diag_row(vbox, "🖥️ WYDAJNOŚĆ (FPS):", "60 FPS")
	
	var hint_lbl = Label.new()
	hint_lbl.text = "Wciśnij [F3], aby ukryć to okno"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	vbox.add_child(hint_lbl)

func _create_f3_hud_diag_row(parent: Control, label_text: String, default_val: String) -> Label:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	
	var l_title = Label.new()
	l_title.text = label_text
	l_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_title.add_theme_font_size_override("font_size", 12)
	l_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	hbox.add_child(l_title)
	
	var l_val = Label.new()
	l_val.text = default_val
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_val.add_theme_font_size_override("font_size", 12)
	l_val.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	hbox.add_child(l_val)
	return l_val

func _update_f3_diagnostics() -> void:
	if network_manager == null: return
	
	var ping_ms = network_manager.current_ping_ms
	var ping_col = UITheme.COLOR_SUCCESS_GREEN if ping_ms < 50 else (UITheme.COLOR_WARNING_GOLD if ping_ms < 120 else UITheme.COLOR_ACCENT_RED)
	if network_manager.is_host:
		f3_diag_labels["ping"].text = "0 ms (HOST)"
		f3_diag_labels["ping"].add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	else:
		f3_diag_labels["ping"].text = "%d ms" % ping_ms
		f3_diag_labels["ping"].add_theme_color_override("font_color", ping_col)
		
	var is_connected = (multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	f3_diag_labels["status"].text = "POŁĄCZONO" if is_connected else "ROZŁĄCZONO"
	f3_diag_labels["status"].add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN if is_connected else UITheme.COLOR_ACCENT_RED)
	
	f3_diag_labels["role"].text = "👑 HOST (SERWER)" if network_manager.is_host else "🎮 KLIENT"
	f3_diag_labels["role"].add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD if network_manager.is_host else UITheme.COLOR_ACCENT_CYAN)
	
	f3_diag_labels["address"].text = "%s:%d" % [network_manager.server_ip, network_manager.server_port]
	f3_diag_labels["code"].text = network_manager.room_code if not network_manager.room_code.is_empty() else "BRAK"
	
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	f3_diag_labels["peer"].text = str(my_id)
	
	var p_count = network_manager.get_players_list().size()
	f3_diag_labels["players"].text = "%d / 4" % p_count
	
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / maxf(1.0, float(fps))
	f3_diag_labels["fps"].text = "%d FPS (%.1f ms)" % [fps, frame_ms]

# ==============================================================================
# Synchronized Match Pause
# ==============================================================================

func _on_network_pause_toggled(p_is_paused: bool, by_peer_id: int, by_player_name: String) -> void:
	is_paused = p_is_paused
	if is_paused:
		_show_pause_banner(by_peer_id, by_player_name)
		if in_game_chat_log != null:
			in_game_chat_log.append_text("[color=#ffbe00]⏸️ [b]%s[/b] wstrzymał rozgrywkę dla wszystkich.[/color]\n" % by_player_name)
	else:
		_hide_pause_banner()
		if in_game_chat_log != null:
			in_game_chat_log.append_text("[color=#00f0ff]▶️ [b]%s[/b] wznowił rozgrywkę.[/color]\n" % by_player_name)

func _show_pause_banner(by_peer_id: int, by_player_name: String) -> void:
	_hide_pause_banner()
	
	pause_banner_overlay = PanelContainer.new()
	pause_banner_overlay.set_anchors_preset(PRESET_CENTER_TOP)
	pause_banner_overlay.offset_top = 80.0
	pause_banner_overlay.custom_minimum_size = Vector2(520, 0)
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.05, 0.10, 0.96), UITheme.COLOR_WARNING_GOLD, 6, 2, 16)
	pause_banner_overlay.add_theme_stylebox_override("panel", sb)
	add_child(pause_banner_overlay)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	pause_banner_overlay.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "⏸️ ROZGRYWKA WSTRZYMANA"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	vbox.add_child(title_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "Gracz [ %s ] zatrzymał mecz dla wszystkich graczy." % by_player_name
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
	vbox.add_child(sub_lbl)
	
	var my_id = multiplayer.get_unique_id() if (multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED) else 1
	
	if by_peer_id == my_id or by_peer_id == 0:
		var resume_btn = Button.new()
		resume_btn.text = "▶️ WZNÓW ROZGRYWKĘ"
		resume_btn.custom_minimum_size = Vector2(240, 42)
		resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UITheme.style_button(resume_btn, Color(0.10, 0.35, 0.20), UITheme.COLOR_SUCCESS_GREEN, 42, 15)
		resume_btn.pressed.connect(func():
			if network_manager != null:
				network_manager.request_toggle_pause()
			else:
				_on_network_pause_toggled(false, my_id, by_player_name)
		)
		vbox.add_child(resume_btn)
	else:
		var lock_lbl = Label.new()
		lock_lbl.text = "🔒 Tylko gracz %s może wznowić rozgrywkę." % by_player_name
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 12)
		lock_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		vbox.add_child(lock_lbl)

func _hide_pause_banner() -> void:
	if pause_banner_overlay != null and is_instance_valid(pause_banner_overlay):
		pause_banner_overlay.queue_free()
		pause_banner_overlay = null

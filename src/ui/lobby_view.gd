# Overwatch / Factory of War Interactive 50x50 Map Lobby View with Colored Bases & Categories
class_name LobbyView
extends Control

signal leave_lobby_requested()
signal ready_toggled()
signal slot_selected(slot_index: int)
signal chat_submitted(message: String)
signal start_game_requested()
signal match_settings_changed(creative: bool, points: int, duration_min: int)

var network_manager: NetworkManager
var settings_manager: SettingsManager
var active_map: MapData

# UI References - Left: Map Preview
var map_container: Control
var map_canvas: Control
var base_buttons: Array[Button] = []
var base_player_lbls: Array[Label] = []

# Chat
var chat_log: RichTextLabel
var chat_input: LineEdit

# Right: Sidebar
var header_status_lbl: Label
var code_lbl: Label
var player_list_vbox: VBoxContainer
var creative_check: CheckBox
var points_val_lbl: Label
var duration_val_lbl: Label
var public_check: CheckBox
var add_bot_btn: Button
var start_btn: Button
var exit_btn: Button

# Match Settings
var current_points: int = 1200
var current_duration: int = 45
var is_creative: bool = false

func _init(p_net: NetworkManager = null, p_settings: SettingsManager = null, p_map: MapData = null) -> void:
	network_manager = p_net
	settings_manager = p_settings
	if p_map != null:
		active_map = p_map
	else:
		active_map = MapGenerator.generate_map()
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_build_ui()
	_update_room_code_display()
	
	# Initial welcome in chat
	if network_manager and network_manager.is_host:
		add_chat_entry("SYSTEM", "Utworzono pokój [KOD: %s]. Oczekiwanie na graczy..." % network_manager.room_code, true)

func set_map_data(new_map: MapData) -> void:
	active_map = new_map
	if map_canvas != null:
		map_canvas.queue_redraw()

func _build_ui() -> void:
	# Fullscreen dark background
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.07, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# Main Split HBox (70% Map Preview, 30% Lobby Sidebar)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 0)
	add_child(main_hbox)
	
	# ==========================================================================
	# 1. LEFT SIDE: PROCEDURAL 50x50 MAP PREVIEW (70%)
	# ==========================================================================
	map_container = Control.new()
	map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_container.size_flags_stretch_ratio = 2.4
	main_hbox.add_child(map_container)
	
	map_canvas = Control.new()
	map_canvas.set_anchors_preset(PRESET_FULL_RECT)
	map_canvas.draw.connect(_on_map_canvas_draw)
	map_container.add_child(map_canvas)
	
	_build_map_interactive_elements(map_container)
	_build_map_chat_overlay(map_container)
	
	# Orange vertical divider line
	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(4, 0)
	divider.color = UITheme.COLOR_ACCENT_ORANGE
	main_hbox.add_child(divider)
	
	# ==========================================================================
	# 2. RIGHT SIDE: LOBBY SETTINGS & PLAYERS (30%)
	# ==========================================================================
	var side_panel = PanelContainer.new()
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_panel.size_flags_stretch_ratio = 1.0
	side_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style(
		Color(0.04, 0.06, 0.11, 0.98),
		Color(0.14, 0.28, 0.44, 0.8),
		0, 0, 24
	))
	main_hbox.add_child(side_panel)
	
	var side_vbox = VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 16)
	side_panel.add_child(side_vbox)
	
	# Header & Exit
	var header_row = HBoxContainer.new()
	side_vbox.add_child(header_row)
	
	var header_vbox = VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_vbox)
	
	var lobby_title = Label.new()
	lobby_title.text = "LOBBY"
	lobby_title.add_theme_font_size_override("font_size", 30)
	lobby_title.add_theme_color_override("font_color", Color.WHITE)
	header_vbox.add_child(lobby_title)
	
	header_status_lbl = Label.new()
	header_status_lbl.text = "Oczekiwanie na graczy — wybierz bazę"
	header_status_lbl.add_theme_font_size_override("font_size", 14)
	header_status_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	header_vbox.add_child(header_status_lbl)
	
	exit_btn = Button.new()
	exit_btn.text = "WYJDŹ"
	exit_btn.add_theme_font_size_override("font_size", 16)
	exit_btn.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_RED)
	exit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb_empty = StyleBoxEmpty.new()
	exit_btn.add_theme_stylebox_override("normal", sb_empty)
	exit_btn.add_theme_stylebox_override("hover", sb_empty)
	exit_btn.add_theme_stylebox_override("pressed", sb_empty)
	exit_btn.pressed.connect(func(): leave_lobby_requested.emit())
	header_row.add_child(exit_btn)
	
	# Room Code
	var code_box = VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 4)
	side_vbox.add_child(code_box)
	
	var code_header_lbl = Label.new()
	code_header_lbl.text = "KOD POKOJU"
	code_header_lbl.add_theme_font_size_override("font_size", 14)
	code_header_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	code_box.add_child(code_header_lbl)
	
	var code_btn = Button.new()
	code_btn.custom_minimum_size = Vector2(0, 52)
	code_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb_code = UITheme.create_panel_style(Color(0.06, 0.10, 0.18, 0.8), UITheme.COLOR_ACCENT_CYAN, 4, 1, 8)
	code_btn.add_theme_stylebox_override("normal", sb_code)
	code_btn.add_theme_stylebox_override("hover", sb_code)
	code_btn.add_theme_stylebox_override("pressed", sb_code)
	code_btn.pressed.connect(_on_copy_code_pressed)
	code_box.add_child(code_btn)
	
	code_lbl = Label.new()
	code_lbl.text = "------"
	code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_lbl.add_theme_font_size_override("font_size", 30)
	code_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	code_btn.add_child(code_lbl)
	
	var code_hint = Label.new()
	code_hint.text = "Kliknij kod, aby skopiować"
	code_hint.add_theme_font_size_override("font_size", 14)
	code_hint.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	code_box.add_child(code_hint)
	
	# Players Header & List
	var players_title = Label.new()
	players_title.text = "GRACZE"
	players_title.add_theme_font_size_override("font_size", 16)
	players_title.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	side_vbox.add_child(players_title)
	
	player_list_vbox = VBoxContainer.new()
	player_list_vbox.add_theme_constant_override("separation", 6)
	side_vbox.add_child(player_list_vbox)
	
	# Match Settings Section
	var settings_header = Label.new()
	settings_header.text = "USTAWIENIA MECZU"
	settings_header.add_theme_font_size_override("font_size", 16)
	settings_header.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	side_vbox.add_child(settings_header)
	
	creative_check = CheckBox.new()
	creative_check.text = "TRYB KREATYWNY"
	creative_check.add_theme_font_size_override("font_size", 15)
	creative_check.toggled.connect(func(v):
		is_creative = v
		match_settings_changed.emit(is_creative, current_points, current_duration)
	)
	side_vbox.add_child(creative_check)
	
	# Points Stepper
	var pts_row = HBoxContainer.new()
	side_vbox.add_child(pts_row)
	var pts_lbl = Label.new()
	pts_lbl.text = "PUNKTY DO WYGRANEJ:"
	pts_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pts_lbl.add_theme_font_size_override("font_size", 14)
	pts_row.add_child(pts_lbl)
	
	var btn_pts_minus = Button.new()
	btn_pts_minus.text = "-"
	btn_pts_minus.custom_minimum_size = Vector2(34, 34)
	btn_pts_minus.add_theme_font_size_override("font_size", 16)
	btn_pts_minus.pressed.connect(func(): _change_points(-100))
	pts_row.add_child(btn_pts_minus)
	
	points_val_lbl = Label.new()
	points_val_lbl.text = "1200"
	points_val_lbl.custom_minimum_size = Vector2(60, 0)
	points_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_val_lbl.add_theme_font_size_override("font_size", 16)
	pts_row.add_child(points_val_lbl)
	
	var btn_pts_plus = Button.new()
	btn_pts_plus.text = "+"
	btn_pts_plus.custom_minimum_size = Vector2(34, 34)
	btn_pts_plus.add_theme_font_size_override("font_size", 16)
	btn_pts_plus.pressed.connect(func(): _change_points(100))
	pts_row.add_child(btn_pts_plus)
	
	# Duration Stepper
	var dur_row = HBoxContainer.new()
	side_vbox.add_child(dur_row)
	var dur_lbl = Label.new()
	dur_lbl.text = "CZAS GRY (MIN):"
	dur_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dur_lbl.add_theme_font_size_override("font_size", 14)
	dur_row.add_child(dur_lbl)
	
	var btn_dur_minus = Button.new()
	btn_dur_minus.text = "-5"
	btn_dur_minus.custom_minimum_size = Vector2(34, 34)
	btn_dur_minus.add_theme_font_size_override("font_size", 15)
	btn_dur_minus.pressed.connect(func(): _change_duration(-5))
	dur_row.add_child(btn_dur_minus)
	
	duration_val_lbl = Label.new()
	duration_val_lbl.text = "45"
	duration_val_lbl.custom_minimum_size = Vector2(60, 0)
	duration_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	duration_val_lbl.add_theme_font_size_override("font_size", 16)
	dur_row.add_child(duration_val_lbl)
	
	var btn_dur_plus = Button.new()
	btn_dur_plus.text = "+5"
	btn_dur_plus.custom_minimum_size = Vector2(34, 34)
	btn_dur_plus.add_theme_font_size_override("font_size", 15)
	btn_dur_plus.pressed.connect(func(): _change_duration(5))
	dur_row.add_child(btn_dur_plus)
	
	# Public lobby check
	public_check = CheckBox.new()
	public_check.text = "LOBBY PUBLICZNE"
	public_check.button_pressed = true
	public_check.add_theme_font_size_override("font_size", 15)
	public_check.toggled.connect(func(v):
		if network_manager and network_manager.is_host:
			network_manager.set_lobby_public(v)
	)
	side_vbox.add_child(public_check)
	
	# Add Bot option
	add_bot_btn = Button.new()
	add_bot_btn.text = "DODAJ BOTA (MAX 3)"
	UITheme.style_button(add_bot_btn, Color(0.10, 0.18, 0.28), UITheme.COLOR_ACCENT_CYAN, 40, 15)
	add_bot_btn.pressed.connect(_on_add_bot_pressed)
	side_vbox.add_child(add_bot_btn)
	
	var spacer_s = Control.new()
	spacer_s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_vbox.add_child(spacer_s)
	
	# START MATCH BUTTON
	start_btn = Button.new()
	start_btn.text = "START (MIN. 2)"
	UITheme.style_button(start_btn, Color(0.12, 0.40, 0.25), UITheme.COLOR_SUCCESS_GREEN, 54, 20)
	start_btn.pressed.connect(func(): start_game_requested.emit())
	side_vbox.add_child(start_btn)

# ==============================================================================
# Map Interactive Layout & Elements
# ==============================================================================

func _build_map_interactive_elements(container: Control) -> void:
	base_buttons.clear()
	base_player_lbls.clear()
	
	# Base buttons will be repositioned in _on_map_canvas_draw via deferred call
	for i in range(4):
		var slot_col = GameState.SLOT_COLORS[i]
		var base_btn = Button.new()
		base_btn.name = "BaseBtn%d" % i
		base_btn.custom_minimum_size = Vector2(10, 10)
		base_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		base_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		var sb_base = StyleBoxFlat.new()
		sb_base.bg_color = Color(0, 0, 0, 0.01) # Nearly transparent, visual drawn on canvas
		sb_base.border_color = Color(0, 0, 0, 0) # No border, drawn by canvas
		sb_base.set_corner_radius_all(0)
		base_btn.add_theme_stylebox_override("normal", sb_base)
		base_btn.add_theme_stylebox_override("hover", sb_base)
		base_btn.add_theme_stylebox_override("pressed", sb_base)
		
		var idx = i
		base_btn.pressed.connect(func():
			slot_selected.emit(idx)
		)
		
		container.add_child(base_btn)
		base_buttons.append(base_btn)
		
		# Player name label floating on map
		var b_user = Label.new()
		b_user.text = "[KLIKNIJ ABY WYBRAĆ]"
		b_user.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_user.add_theme_font_size_override("font_size", 14)
		b_user.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		container.add_child(b_user)
		base_player_lbls.append(b_user)

func _position_base_buttons_on_map() -> void:
	# Called after drawing, to position buttons precisely over base areas
	if active_map == null or map_canvas == null:
		return
	var rect = map_canvas.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	var map_w = active_map.width
	var map_h = active_map.height
	var margin_px = 30.0
	var avail_w = w - margin_px * 2
	var avail_h = h - margin_px * 2
	var cell_size = minf(avail_w / float(map_w), avail_h / float(map_h))
	var origin_x = margin_px + (avail_w - cell_size * map_w) * 0.5
	var origin_y = margin_px + (avail_h - cell_size * map_h) * 0.5
	
	for i in range(mini(active_map.bases.size(), base_buttons.size())):
		var b_spawn = active_map.bases[i]
		var hq_radius = BuildingSystem.POWER_GRID_HQ_RADIUS
		var hq_center = b_spawn.grid_pos  # HQ top-left, center at +1,+1
		var center_tile = hq_center + Vector2i(1, 1)
		
		# Button covers the power field area
		var area_left = (center_tile.x - hq_radius) * cell_size + origin_x
		var area_top = (center_tile.y - hq_radius) * cell_size + origin_y
		var area_size = (hq_radius * 2 + 1) * cell_size
		
		base_buttons[i].position = Vector2(area_left, area_top)
		base_buttons[i].size = Vector2(area_size, area_size)
		
		# Position label below the HQ
		var lbl_x = origin_x + (hq_center.x + 1.5) * cell_size
		var lbl_y = origin_y + (hq_center.y + 3.5) * cell_size
		base_player_lbls[i].position = Vector2(lbl_x - 80, lbl_y)
		base_player_lbls[i].size = Vector2(160, 24)

func _build_map_chat_overlay(container: Control) -> void:
	var chat_box = PanelContainer.new()
	chat_box.set_anchors_preset(PRESET_BOTTOM_LEFT)
	chat_box.anchor_left = 0.0
	chat_box.anchor_top = 1.0
	chat_box.anchor_right = 0.0
	chat_box.anchor_bottom = 1.0
	chat_box.offset_left = 20.0
	chat_box.offset_top = -190.0
	chat_box.offset_right = 380.0
	chat_box.offset_bottom = -20.0
	chat_box.grow_horizontal = Control.GROW_DIRECTION_END
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	var sb = UITheme.create_panel_style(Color(0.03, 0.06, 0.10, 0.90), Color(0.14, 0.26, 0.40, 0.6), 4, 1, 10)
	chat_box.add_theme_stylebox_override("panel", sb)
	container.add_child(chat_box)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 6)
	chat_box.add_child(cvbox)
	
	var chat_hint = Label.new()
	chat_hint.text = "Czat lobby — T lub kliknij pole na dole. LPM zamyka"
	chat_hint.add_theme_font_size_override("font_size", 14)
	chat_hint.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	cvbox.add_child(chat_hint)
	
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.scroll_following = true
	chat_log.bbcode_enabled = true
	chat_log.add_theme_font_size_override("normal_font_size", 14)
	cvbox.add_child(chat_log)
	
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "T — napisz wiadomość..."
	UITheme.style_line_edit(chat_input, 14)
	chat_input.text_submitted.connect(_on_chat_submitted)
	cvbox.add_child(chat_input)

# ==============================================================================
# Map Canvas Drawing (Procedural 50x50 Grid & Resource Cluster visualization)
# ==============================================================================

func _on_map_canvas_draw() -> void:
	if map_canvas == null or active_map == null: return
	var rect = map_canvas.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	
	var map_w = active_map.width
	var map_h = active_map.height
	
	var margin_px = 30.0
	var avail_w = w - margin_px * 2
	var avail_h = h - margin_px * 2
	
	var cell_size = minf(avail_w / float(map_w), avail_h / float(map_h))
	var origin_x = margin_px + (avail_w - cell_size * map_w) * 0.5
	var origin_y = margin_px + (avail_h - cell_size * map_h) * 0.5
	
	# 1. Non-buildable 1-tile border background
	var full_map_rect = Rect2(origin_x, origin_y, cell_size * map_w, cell_size * map_h)
	map_canvas.draw_rect(full_map_rect, Color(0.04, 0.06, 0.09, 1.0), true)
	map_canvas.draw_rect(full_map_rect, Color(0.18, 0.25, 0.35, 0.8), false, 2.0)
	
	# Playable area
	var play_rect = Rect2(origin_x + cell_size, origin_y + cell_size, cell_size * (map_w - 2), cell_size * (map_h - 2))
	map_canvas.draw_rect(play_rect, Color(0.06, 0.09, 0.14, 1.0), true)
	
	# 2. 50x50 Grid Lines
	var grid_col = Color(0.10, 0.18, 0.28, 0.25)
	for gx in range(map_w + 1):
		var lx = origin_x + gx * cell_size
		map_canvas.draw_line(Vector2(lx, origin_y), Vector2(lx, origin_y + map_h * cell_size), grid_col, 1.0)
	for gy in range(map_h + 1):
		var ly = origin_y + gy * cell_size
		map_canvas.draw_line(Vector2(origin_x, ly), Vector2(origin_x + map_w * cell_size, ly), grid_col, 1.0)
	
	# 3. Draw BASE POWER FIELDS + HQ preview for each base
	for i in range(active_map.bases.size()):
		var b_spawn = active_map.bases[i]
		var slot_col = GameState.SLOT_COLORS[i] if i < GameState.SLOT_COLORS.size() else Color.WHITE
		var hq_center_tile = b_spawn.grid_pos + Vector2i(1, 1)
		var hq_radius = BuildingSystem.POWER_GRID_HQ_RADIUS
		
		# Draw power coverage tiles (rounded-square)
		var power_tiles = BuildingSystem.get_powered_tiles(hq_center_tile, hq_radius)
		var power_fill = Color(slot_col.r, slot_col.g, slot_col.b, 0.06)
		for pt in power_tiles:
			var pt_rect = Rect2(origin_x + pt.x * cell_size, origin_y + pt.y * cell_size, cell_size, cell_size)
			map_canvas.draw_rect(pt_rect, power_fill, true)
		
		# Draw power field border (only outer edges)
		var power_edge_col = Color(slot_col.r, slot_col.g, slot_col.b, 0.3)
		for pt in power_tiles:
			for edge_data in [
				[Vector2i(0, -1), Vector2(0, 0), Vector2(1, 0)],
				[Vector2i(0, 1), Vector2(0, 1), Vector2(1, 1)],
				[Vector2i(-1, 0), Vector2(0, 0), Vector2(0, 1)],
				[Vector2i(1, 0), Vector2(1, 0), Vector2(1, 1)]
			]:
				var neighbor = Vector2i(pt.x, pt.y) + edge_data[0]
				if not power_tiles.has(neighbor):
					var e1 = Vector2(origin_x + (pt.x + edge_data[1].x) * cell_size, origin_y + (pt.y + edge_data[1].y) * cell_size)
					var e2 = Vector2(origin_x + (pt.x + edge_data[2].x) * cell_size, origin_y + (pt.y + edge_data[2].y) * cell_size)
					map_canvas.draw_line(e1, e2, power_edge_col, 1.5)
		
		# Draw HQ building preview (3x3 block)
		var hq_x = origin_x + b_spawn.grid_pos.x * cell_size
		var hq_y = origin_y + b_spawn.grid_pos.y * cell_size
		var hq_rect = Rect2(hq_x, hq_y, cell_size * 3, cell_size * 3)
		
		# HQ body fill
		map_canvas.draw_rect(hq_rect, Color(slot_col.r * 0.3, slot_col.g * 0.3, slot_col.b * 0.3, 0.7), true)
		map_canvas.draw_rect(hq_rect, slot_col, false, 2.0)
		
		# HQ inner detail (cross pattern)
		var hq_cx = hq_x + cell_size * 1.5
		var hq_cy = hq_y + cell_size * 1.5
		map_canvas.draw_rect(Rect2(hq_cx - cell_size * 0.4, hq_y + 2, cell_size * 0.8, cell_size * 3 - 4), Color(slot_col.r, slot_col.g, slot_col.b, 0.25), true)
		map_canvas.draw_rect(Rect2(hq_x + 2, hq_cy - cell_size * 0.4, cell_size * 3 - 4, cell_size * 0.8), Color(slot_col.r, slot_col.g, slot_col.b, 0.25), true)
		
		# HQ label
		var base_names = ["B1", "B2", "B3", "B4"]
		var label_text = base_names[i] if i < base_names.size() else "B?"
		map_canvas.draw_string(ThemeDB.fallback_font, Vector2(hq_cx - 10, hq_cy + 6), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, slot_col)
		
		# "KWATERA" label above HQ
		map_canvas.draw_string(ThemeDB.fallback_font, Vector2(hq_cx - 30, hq_y - 6), "KWATERA", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(slot_col.r, slot_col.g, slot_col.b, 0.6))
	
	# 4. Draw Center Boss Area (Strefa Boss)
	var boss_node = null
	for c in active_map.camps:
		if c.type == MapData.CampType.BOSS:
			boss_node = c
			break
	if boss_node != null:
		var bx = origin_x + (boss_node.grid_pos.x - 2) * cell_size
		var by = origin_y + (boss_node.grid_pos.y - 2) * cell_size
		var boss_box = Rect2(bx, by, cell_size * 5, cell_size * 5)
		map_canvas.draw_rect(boss_box, Color(0.0, 0.45, 0.55, 0.25), true)
		map_canvas.draw_rect(boss_box, UITheme.COLOR_ACCENT_CYAN, false, 1.5)
		
		var b_center = Vector2(origin_x + (boss_node.grid_pos.x + 0.5) * cell_size, origin_y + (boss_node.grid_pos.y + 0.5) * cell_size)
		map_canvas.draw_circle(b_center, cell_size * 1.3, Color(0.9, 0.2, 0.2, 0.85))
		map_canvas.draw_string(ThemeDB.fallback_font, b_center + Vector2(-24, -14), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UITheme.COLOR_TEXT_MUTED)
		map_canvas.draw_string(ThemeDB.fallback_font, b_center + Vector2(-30, 20), "Strefa", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, UITheme.COLOR_ACCENT_CYAN)
		
	# 5. Draw Neutral Camps (OBÓZ)
	for c in active_map.camps:
		if c.type == MapData.CampType.CAMP:
			var c_center = Vector2(origin_x + (c.grid_pos.x + 0.5) * cell_size, origin_y + (c.grid_pos.y + 0.5) * cell_size)
			map_canvas.draw_circle(c_center, cell_size * 0.9, UITheme.COLOR_ACCENT_ORANGE)
			map_canvas.draw_string(ThemeDB.fallback_font, c_center + Vector2(-22, -12), "OBÓZ", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, UITheme.COLOR_TEXT_MUTED)
			
	# 6. Draw Generated Resource Nodes (Stone, Iron, Oil, Redstone)
	for r in active_map.resources:
		var rx = origin_x + r.grid_pos.x * cell_size
		var ry = origin_y + r.grid_pos.y * cell_size
		var r_rect = Rect2(rx + 1, ry + 1, cell_size - 2, cell_size - 2)
		
		var r_col = Color(0.75, 0.75, 0.75)
		match r.type:
			MapData.ResourceType.STONE: r_col = Color(0.75, 0.75, 0.75)
			MapData.ResourceType.IRON: r_col = Color(0.30, 0.85, 1.0)
			MapData.ResourceType.OIL: r_col = Color(1.0, 0.75, 0.20)
			MapData.ResourceType.REDSTONE: r_col = Color(1.0, 0.25, 0.25)
			
		map_canvas.draw_rect(r_rect, r_col.darkened(0.5), true)
		map_canvas.draw_rect(r_rect, r_col, false, 1.0)
		map_canvas.draw_circle(r_rect.get_center(), cell_size * 0.35, r_col)
	
	# Reposition base buttons on top of map
	_position_base_buttons_on_map()

# ==============================================================================
# State Updates & Synchronization
# ==============================================================================

func update_lobby_state(players: Array, is_host: bool, local_peer_id: int) -> void:
	_update_room_code_display()
	
	for i in range(GameState.MAX_PLAYERS):
		base_player_lbls[i].text = "[KLIKNIJ ABY WYBRAĆ]"
		base_player_lbls[i].add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		
	for c in player_list_vbox.get_children():
		c.queue_free()
		
	var count = players.size()
	for p in players:
		var slot_col = GameState.SLOT_COLORS[p.slot] if p.slot < GameState.SLOT_COLORS.size() else UITheme.COLOR_ACCENT_CYAN
		
		# Update base button label
		if p.slot >= 0 and p.slot < GameState.MAX_PLAYERS:
			var slot_name = p.name
			if p.is_host: slot_name += " 👑"
			base_player_lbls[p.slot].text = slot_name
			base_player_lbls[p.slot].add_theme_color_override("font_color", slot_col)
			
		# Add to right sidebar
		var p_card = Label.new()
		var desc = p.name
		if p.is_host: desc += " · HOST"
		desc += " · BAZA %d" % (p.slot + 1)
		p_card.text = desc
		p_card.add_theme_font_size_override("font_size", 16)
		p_card.add_theme_color_override("font_color", slot_col)
		player_list_vbox.add_child(p_card)

	if is_host:
		header_status_lbl.text = "Jesteś Hostem — wybierz bazę i kliknij Start"
		start_btn.visible = true
		start_btn.disabled = false
		start_btn.text = "START ROZGRYWKI" if count >= 1 else "START (MIN. 2)"
	else:
		header_status_lbl.text = "Oczekiwanie na start przez Hosta..."
		start_btn.visible = false

func add_chat_entry(sender: String, message: String, is_system: bool = false) -> void:
	if is_system:
		match sender.to_upper():
			"USTAWIENIA":
				chat_log.append_text("[color=#c084fc][b]⚙️ USTAWIENIA:[/b] %s[/color]\n" % message)
			"GRACZ":
				chat_log.append_text("[color=#22d3ee][b]🔄 GRACZ:[/b] %s[/color]\n" % message)
			"START":
				chat_log.append_text("[color=#fb923c][b]🚀 START:[/b] %s[/color]\n" % message)
			_:
				chat_log.append_text("[color=#ffd166][b]📢 %s:[/b] %s[/color]\n" % [sender, message])
	else:
		# Check if sender has slot color
		var col_hex = "00f0ff"
		if network_manager != null:
			for p in network_manager.get_players_list():
				if p.name == sender and p.slot < GameState.SLOT_COLORS.size():
					col_hex = GameState.SLOT_COLORS[p.slot].to_html(false)
					break
		chat_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [col_hex, sender, message])

func _update_room_code_display() -> void:
	if network_manager != null and not network_manager.room_code.is_empty():
		code_lbl.text = network_manager.room_code

func _change_points(delta_pts: int) -> void:
	current_points = clampi(current_points + delta_pts, 100, 5000)
	points_val_lbl.text = str(current_points)
	match_settings_changed.emit(is_creative, current_points, current_duration)
	if network_manager and network_manager.is_host:
		network_manager.send_chat("Zmieniono cel punktowy: %d pkt" % current_points)

func _change_duration(delta_dur: int) -> void:
	current_duration = clampi(current_duration + delta_dur, 5, 120)
	duration_val_lbl.text = str(current_duration)
	match_settings_changed.emit(is_creative, current_points, current_duration)
	if network_manager and network_manager.is_host:
		network_manager.send_chat("Zmieniono czas rozgrywki: %d min" % current_duration)

func _on_add_bot_pressed() -> void:
	add_chat_entry("SYSTEM", "Dodano wirtualnego Bota do wolnej bazy.", true)

func _on_copy_code_pressed() -> void:
	if network_manager and not network_manager.room_code.is_empty():
		DisplayServer.clipboard_set(network_manager.room_code)
		add_chat_entry("SYSTEM", "Skopiowano kod pokoju (%s) do schowka!" % network_manager.room_code, true)

func _on_chat_submitted(text: String) -> void:
	var clean = text.strip_edges()
	if not clean.is_empty():
		chat_submitted.emit(clean)
		chat_input.clear()

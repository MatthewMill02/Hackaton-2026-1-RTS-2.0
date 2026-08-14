# In-Game Tactical HUD and Map View matching Image 4
class_name InGameHUD
extends Control

signal exit_to_menu_requested()
signal chat_sent(msg: String)

var network_manager: NetworkManager
var settings_manager: SettingsManager

# Resources (simulated dynamic economy)
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

var hq_texture: Texture2D = null

# In-Game Chat
var in_game_chat_log: RichTextLabel
var in_game_chat_input: LineEdit

func _init(p_net: NetworkManager = null, p_settings: SettingsManager = null) -> void:
	network_manager = p_net
	settings_manager = p_settings
	set_anchors_preset(PRESET_FULL_RECT)

func _ready() -> void:
	_load_assets()
	_build_ui()

func _process(delta: float) -> void:
	# Timer countdown
	if match_timer_seconds > 0:
		match_timer_seconds -= delta
		_update_timer_display()
		
	# Keyboard map pan
	var pan_speed = 400.0 * (settings_manager.map_scroll_speed if settings_manager else 1.0)
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x -= 1
	
	if move != Vector2.ZERO:
		map_camera_pos += move * pan_speed * delta
		if map_viewport: map_viewport.queue_redraw()

func _load_assets() -> void:
	var hq_path = "res://public/sprites/buildings/building_hq.png"
	if ResourceLoader.exists(hq_path):
		hq_texture = load(hq_path)

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
	top_bar.custom_minimum_size = Vector2(0, 56)
	var top_sb = StyleBoxFlat.new()
	top_sb.bg_color = Color(0.02, 0.04, 0.08, 0.85)
	top_sb.content_margin_left = 16
	top_sb.content_margin_right = 16
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 24)
	top_bar.add_child(top_hbox)
	
	# Left: Resources Box
	var res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 2)
	top_hbox.add_child(res_box)
	
	var res_row1 = HBoxContainer.new()
	res_row1.add_theme_constant_override("separation", 16)
	res_box.add_child(res_row1)
	
	res_stone_lbl = Label.new()
	res_stone_lbl.text = "● %d/%d" % [stone, max_storage]
	res_stone_lbl.add_theme_font_size_override("font_size", 12)
	res_stone_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	res_row1.add_child(res_stone_lbl)
	
	res_iron_lbl = Label.new()
	res_iron_lbl.text = "● %d/%d" % [iron, max_storage]
	res_iron_lbl.add_theme_font_size_override("font_size", 12)
	res_iron_lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	res_row1.add_child(res_iron_lbl)
	
	res_oil_lbl = Label.new()
	res_oil_lbl.text = "● %d/%d" % [oil, max_storage]
	res_oil_lbl.add_theme_font_size_override("font_size", 12)
	res_oil_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	res_row1.add_child(res_oil_lbl)
	
	res_redstone_lbl = Label.new()
	res_redstone_lbl.text = "● %d/%d" % [redstone, max_storage]
	res_redstone_lbl.add_theme_font_size_override("font_size", 12)
	res_redstone_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	res_row1.add_child(res_redstone_lbl)
	
	var res_row2 = HBoxContainer.new()
	res_row2.add_theme_constant_override("separation", 12)
	res_box.add_child(res_row2)
	
	power_lbl = Label.new()
	power_lbl.text = "⚡ +%d | %d/%d kW" % [power_production - power_consumption, power_production, power_capacity]
	power_lbl.add_theme_font_size_override("font_size", 11)
	power_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
	res_row2.add_child(power_lbl)
	
	player_name_lbl = Label.new()
	player_name_lbl.text = settings_manager.player_name if settings_manager else "Gracz 1"
	player_name_lbl.add_theme_font_size_override("font_size", 11)
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
	timer_lbl.add_theme_font_size_override("font_size", 18)
	timer_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_box.add_child(timer_lbl)
	
	score_lbl = Label.new()
	score_lbl.text = "★ 0 / 1200 pkt"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.add_theme_font_size_override("font_size", 12)
	score_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	score_box.add_child(score_lbl)
	
	var btn_menu = Button.new()
	btn_menu.text = "MENU"
	btn_menu.custom_minimum_size = Vector2(80, 36)
	UITheme.style_button(btn_menu, Color(0.12, 0.24, 0.38), UITheme.COLOR_ACCENT_CYAN, 36, 13)
	btn_menu.pressed.connect(_on_menu_pressed)
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
	build_panel.position = Vector2(16, 72)
	build_panel.custom_minimum_size = Vector2(160, 0)
	
	var sb = UITheme.create_panel_style(Color(0.04, 0.07, 0.12, 0.90), Color(0.12, 0.24, 0.38, 0.6), 4, 1, 6)
	build_panel.add_theme_stylebox_override("panel", sb)
	add_child(build_panel)
	
	var bvbox = VBoxContainer.new()
	bvbox.add_theme_constant_override("separation", 4)
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
		btn.custom_minimum_size = Vector2(148, 28)
		var accent = UITheme.COLOR_ACCENT_RED if item.name == "Zniszcz budynek" else UITheme.COLOR_ACCENT_CYAN
		UITheme.style_button(btn, item.color, accent, 28, 11)
		btn.pressed.connect(func(): _on_build_btn_pressed(item.name))
		bvbox.add_child(btn)

func _build_in_game_chat_overlay() -> void:
	var chat_box = PanelContainer.new()
	chat_box.set_anchors_preset(PRESET_BOTTOM_LEFT)
	chat_box.position = Vector2(16, -170)
	chat_box.custom_minimum_size = Vector2(300, 150)
	
	var sb = UITheme.create_panel_style(Color(0.02, 0.04, 0.08, 0.85), Color(0.10, 0.20, 0.32, 0.4), 4, 1, 8)
	chat_box.add_theme_stylebox_override("panel", sb)
	add_child(chat_box)
	
	var cvbox = VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	chat_box.add_child(cvbox)
	
	var hint = Label.new()
	hint.text = "Gra rozpoczęta!\nT — czat · kliknij mapę LPM, aby zamknąć"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	cvbox.add_child(hint)
	
	in_game_chat_log = RichTextLabel.new()
	in_game_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	in_game_chat_log.scroll_following = true
	in_game_chat_log.bbcode_enabled = true
	cvbox.add_child(in_game_chat_log)
	
	in_game_chat_input = LineEdit.new()
	in_game_chat_input.placeholder_text = "T — napisz wiadomość..."
	UITheme.style_line_edit(in_game_chat_input, 11)
	in_game_chat_input.text_submitted.connect(_on_chat_submitted)
	cvbox.add_child(in_game_chat_input)
	
	# Bottom Center Control Hints
	var hint_lbl = Label.new()
	hint_lbl.set_anchors_preset(PRESET_BOTTOM_WIDE)
	hint_lbl.position = Vector2(0, -28)
	hint_lbl.text = "LPM: zaznacz  PPM: rozkaz  T: czat  ESC/MENU: ustawienia  TAB: statystyki"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	add_child(hint_lbl)

func _build_minimap_box() -> void:
	var minimap = PanelContainer.new()
	minimap.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(-150, -120)
	minimap.custom_minimum_size = Vector2(130, 100)
	
	var sb = UITheme.create_panel_style(Color(0.03, 0.05, 0.09, 0.90), UITheme.COLOR_ACCENT_CYAN.darkened(0.4), 4, 1, 4)
	minimap.add_theme_stylebox_override("panel", sb)
	add_child(minimap)
	
	var mini_inner = Control.new()
	mini_inner.set_anchors_preset(PRESET_FULL_RECT)
	mini_inner.draw.connect(func():
		mini_inner.draw_rect(Rect2(Vector2(20, 20), Vector2(40, 30)), UITheme.COLOR_ACCENT_CYAN, false, 1.0)
	)
	minimap.add_child(mini_inner)

# ==============================================================================
# Map Canvas Drawing (HQ Sprite, Grid, Resource Nodes)
# ==============================================================================

func _on_map_draw() -> void:
	if map_viewport == null: return
	var rect = map_viewport.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	
	# Background
	map_viewport.draw_rect(rect, Color(0.04, 0.06, 0.10, 1.0), true)
	
	# Tactical Grid
	var step = 48.0 * map_zoom
	var offset_x = fmod(map_camera_pos.x, step)
	var offset_y = fmod(map_camera_pos.y, step)
	var grid_col = Color(0.08, 0.14, 0.22, 0.35)
	
	var x = offset_x
	while x < w:
		map_viewport.draw_line(Vector2(x, 0), Vector2(x, h), grid_col, 1.0)
		x += step
	var y = offset_y
	while y < h:
		map_viewport.draw_line(Vector2(0, y), Vector2(w, y), grid_col, 1.0)
		y += step
		
	# Draw Base HQ Building Sprite
	var hq_pos = Vector2(w * 0.28, h * 0.42) + map_camera_pos
	if hq_texture != null:
		var tex_sz = hq_texture.get_size()
		map_viewport.draw_texture(hq_texture, hq_pos - tex_sz * 0.5)
	else:
		map_viewport.draw_rect(Rect2(hq_pos - Vector2(40, 40), Vector2(80, 80)), Color(0.2, 0.5, 0.9, 0.6), true)
		
	# Draw Base Selection / Power zone
	map_viewport.draw_circle(hq_pos, 160.0 * map_zoom, Color(0.0, 0.8, 1.0, 0.06))
	map_viewport.draw_arc(hq_pos, 160.0 * map_zoom, 0, TAU, 32, UITheme.COLOR_ACCENT_CYAN.darkened(0.4), 1.0)
	
	# Draw Resource Nodes (Stone / Iron / Oil / Redstone)
	var nodes = [
		{"pos": hq_pos + Vector2(70, 50), "col": Color(0.7, 0.7, 0.7), "name": "Kamień"},
		{"pos": hq_pos + Vector2(110, 80), "col": Color(0.3, 0.8, 1.0), "name": "Żelazo"},
		{"pos": Vector2(w * 0.55, h * 0.65) + map_camera_pos, "col": Color(0.9, 0.25, 0.25), "name": "Czerwienit"},
		{"pos": Vector2(w * 0.75, h * 0.65) + map_camera_pos, "col": Color(0.9, 0.25, 0.25), "name": "Czerwienit"}
	]
	for node in nodes:
		map_viewport.draw_rect(Rect2(node.pos - Vector2(16, 16), Vector2(32, 32)), Color(0.08, 0.12, 0.18, 0.85), true)
		map_viewport.draw_rect(Rect2(node.pos - Vector2(16, 16), Vector2(32, 32)), node.col, false, 1.5)
		map_viewport.draw_circle(node.pos, 9.0, node.col)
		
	# Neutral Camps
	var camp_pos = Vector2(w * 0.62, h * 0.82) + map_camera_pos
	map_viewport.draw_circle(camp_pos, 14.0, UITheme.COLOR_ACCENT_ORANGE)
	map_viewport.draw_string(ThemeDB.fallback_font, camp_pos + Vector2(-16, -18), "OBÓZ", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, UITheme.COLOR_TEXT_MUTED)

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_dragging = true
				drag_start = event.position
			else:
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_zoom = clampf(map_zoom + 0.1, 0.5, 2.0)
			map_viewport.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_zoom = clampf(map_zoom - 0.1, 0.5, 2.0)
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
	in_game_chat_log.append_text("[color=#00f0ff]Wybrano konstrukcję: [b]%s[/b] (Wskaż miejsce na mapie)[/color]\n" % building_name)

func _on_chat_submitted(text: String) -> void:
	var clean = text.strip_edges()
	if not clean.is_empty():
		in_game_chat_log.append_text("[color=#2ec4b6][b]%s:[/b][/color] %s\n" % [settings_manager.player_name if settings_manager else "Gracz", clean])
		chat_sent.emit(clean)
		in_game_chat_input.clear()

func _on_menu_pressed() -> void:
	var modal = SettingsModal.new(settings_manager, network_manager)
	add_child(modal)

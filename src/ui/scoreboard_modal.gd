# Overwatch-style TAB In-Game Ranking & Scoreboard Overlay
class_name ScoreboardModal
extends Control

var network_manager: NetworkManager
var settings_manager: SettingsManager
var target_points: int = 1200
var match_timer_seconds: float = 45 * 60

var player_rows_vbox: VBoxContainer
var my_pts_lbl: Label
var my_kills_lbl: Label
var my_destr_lbl: Label
var my_bld_lbl: Label
var my_units_lbl: Label
var my_res_lbl: Label
var timer_lbl: Label

func _init(p_net: NetworkManager, p_settings: SettingsManager, p_pts: int = 1200, p_timer_sec: float = 2700.0) -> void:
	network_manager = p_net
	settings_manager = p_settings
	target_points = p_pts
	match_timer_seconds = p_timer_sec
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_build_ui()
	_populate_data()

func _build_ui() -> void:
	# Semi-transparent backdrop
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.08, 0.85)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	
	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(980, 520)
	var panel_sb = UITheme.create_panel_style(
		Color(0.04, 0.07, 0.12, 0.95),
		Color(0.14, 0.28, 0.44, 0.8),
		4, 1, 0
	)
	main_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(main_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(main_vbox)
	
	# --- 1. TOP HEADER BANNER ---
	var top_bar = PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 54)
	var top_sb = StyleBoxFlat.new()
	top_sb.bg_color = UITheme.COLOR_MODAL_HEADER_BG
	top_sb.content_margin_left = 24
	top_sb.content_margin_right = 24
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", top_sb)
	main_vbox.add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_bar.add_child(top_hbox)
	
	var rank_lbl = Label.new()
	rank_lbl.text = "RANKING"
	rank_lbl.add_theme_font_size_override("font_size", 28)
	rank_lbl.add_theme_color_override("font_color", UITheme.COLOR_MODAL_HEADER_TEXT)
	top_hbox.add_child(rank_lbl)
	
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer1)
	
	var goal_lbl = Label.new()
	goal_lbl.text = "CEL %d PKT" % target_points
	goal_lbl.add_theme_font_size_override("font_size", 18)
	goal_lbl.add_theme_color_override("font_color", Color(0.12, 0.20, 0.30))
	top_hbox.add_child(goal_lbl)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer2)
	
	var mins = int(match_timer_seconds) / 60
	var secs = int(match_timer_seconds) % 60
	timer_lbl = Label.new()
	timer_lbl.text = "00:02 · -%02d:%02d" % [mins, secs]
	timer_lbl.add_theme_font_size_override("font_size", 18)
	timer_lbl.add_theme_color_override("font_color", Color(0.12, 0.20, 0.30))
	top_hbox.add_child(timer_lbl)
	
	# --- 2. TABLE HEADERS ---
	var margin_content = MarginContainer.new()
	margin_content.add_theme_constant_override("margin_left", 24)
	margin_content.add_theme_constant_override("margin_right", 24)
	margin_content.add_theme_constant_override("margin_top", 4)
	margin_content.add_theme_constant_override("margin_bottom", 16)
	main_vbox.add_child(margin_content)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	margin_content.add_child(content_vbox)
	
	var col_header_row = HBoxContainer.new()
	content_vbox.add_child(col_header_row)
	
	var h_player = Label.new()
	h_player.text = "GRACZ"
	h_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_player.add_theme_font_size_override("font_size", 14)
	h_player.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	col_header_row.add_child(h_player)
	
	var columns = [
		{"name": "PKT", "sub": "PUNKTY"},
		{"name": "BUD", "sub": "BUDYNKI"},
		{"name": "JDN", "sub": "JEDNOSTKI"},
		{"name": "ZAB", "sub": "ZABICIA"},
		{"name": "ZNS", "sub": "ZNISZCZ."}
	]
	
	for col in columns:
		var c_vbox = VBoxContainer.new()
		c_vbox.custom_minimum_size = Vector2(80, 0)
		c_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		col_header_row.add_child(c_vbox)
		
		var t1 = Label.new()
		t1.text = col.name
		t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t1.add_theme_font_size_override("font_size", 15)
		t1.add_theme_color_override("font_color", Color.WHITE)
		c_vbox.add_child(t1)
		
		var t2 = Label.new()
		t2.text = col.sub
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t2.add_theme_font_size_override("font_size", 11)
		t2.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		c_vbox.add_child(t2)
		
	# Separator
	var sep1 = HSeparator.new()
	sep1.add_theme_stylebox_override("separator", UITheme.create_panel_style(Color(0.14, 0.28, 0.44, 0.5), Color.TRANSPARENT, 0, 0, 1))
	content_vbox.add_child(sep1)
	
	# Player rows container
	player_rows_vbox = VBoxContainer.new()
	player_rows_vbox.add_theme_constant_override("separation", 8)
	content_vbox.add_child(player_rows_vbox)
	
	# Spacer
	var spacer_mid = Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 10)
	content_vbox.add_child(spacer_mid)
	
	# --- 3. BOTTOM PANEL: TWOJE STATYSTYKI ---
	var stats_panel = PanelContainer.new()
	var sp_sb = UITheme.create_panel_style(Color(0.02, 0.05, 0.09, 0.90), Color(0.12, 0.24, 0.38, 0.6), 4, 1, 14)
	stats_panel.add_theme_stylebox_override("panel", sp_sb)
	content_vbox.add_child(stats_panel)
	
	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 10)
	stats_panel.add_child(stats_vbox)
	
	var st_title = Label.new()
	st_title.text = "TWOJE STATYSTYKI"
	st_title.add_theme_font_size_override("font_size", 14)
	st_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	stats_vbox.add_child(st_title)
	
	var metrics_row = HBoxContainer.new()
	metrics_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_child(metrics_row)
	
	var my_metrics = [
		{"val": "0", "name": "PUNKTY"},
		{"val": "0", "name": "ZABICIA JEDNOSTEK"},
		{"val": "0", "name": "ZNISZCZONE BUDYNKI"},
		{"val": "1", "name": "BUDYNKI"},
		{"val": "1", "name": "JEDNOSTKI"},
		{"val": "0", "name": "ZEBRANE SUROWCE"}
	]
	
	for m in my_metrics:
		var m_box = VBoxContainer.new()
		m_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m_box.alignment = BoxContainer.ALIGNMENT_CENTER
		metrics_row.add_child(m_box)
		
		var num = Label.new()
		num.text = m.val
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 28)
		num.add_theme_color_override("font_color", Color.WHITE)
		m_box.add_child(num)
		
		var desc = Label.new()
		desc.text = m.name
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		m_box.add_child(desc)
		
	# Footer hint
	var footer = Label.new()
	footer.text = "Ping 0 ms · Puść TAB, aby zamknąć"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	stats_vbox.add_child(footer)

func _populate_data() -> void:
	for c in player_rows_vbox.get_children():
		c.queue_free()
		
	var players: Array = []
	if network_manager != null:
		players = network_manager.get_players_list()
	if players.is_empty():
		var dummy = PlayerData.new()
		dummy.name = settings_manager.player_name if settings_manager else "Pracownik"
		dummy.is_host = true
		dummy.slot = 0
		dummy.color = GameState.SLOT_COLORS[0]
		players.append(dummy)
		
	var rank_idx = 1
	for p in players:
		var row_panel = PanelContainer.new()
		var slot_col = GameState.SLOT_COLORS[p.slot] if p.slot < GameState.SLOT_COLORS.size() else UITheme.COLOR_ACCENT_CYAN
		var r_sb = UITheme.create_panel_style(Color(0.06, 0.10, 0.16, 0.90), Color.TRANSPARENT, 2, 0, 8)
		row_panel.add_theme_stylebox_override("panel", r_sb)
		player_rows_vbox.add_child(row_panel)
		
		var row_hbox = HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 12)
		row_panel.add_child(row_hbox)
		
		# Rank Number
		var rank_lbl = Label.new()
		rank_lbl.text = str(rank_idx)
		rank_lbl.custom_minimum_size = Vector2(24, 0)
		rank_lbl.add_theme_font_size_override("font_size", 18)
		rank_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		row_hbox.add_child(rank_lbl)
		
		# Color bar indicator
		var c_bar = ColorRect.new()
		c_bar.custom_minimum_size = Vector2(4, 32)
		c_bar.color = slot_col
		row_hbox.add_child(c_bar)
		
		# Player info
		var p_vbox = VBoxContainer.new()
		p_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_vbox.add_theme_constant_override("separation", 1)
		row_hbox.add_child(p_vbox)
		
		var p_name_lbl = Label.new()
		var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
		var is_me = (p.peer_id == my_id or (network_manager == null and p.is_host))
		p_name_lbl.text = p.name.to_upper() + (" · TY" if is_me else "")
		p_name_lbl.add_theme_font_size_override("font_size", 18)
		p_name_lbl.add_theme_color_override("font_color", slot_col)
		p_vbox.add_child(p_name_lbl)
		
		var p_role_lbl = Label.new()
		p_role_lbl.text = "HOST" if p.is_host else "GRACZ"
		p_role_lbl.add_theme_font_size_override("font_size", 12)
		p_role_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		p_vbox.add_child(p_role_lbl)
		
		# Columns: PKT (0), BUD (1), JDN (1), ZAB (0), ZNS (0)
		var values = ["0", "1", "1", "0", "0"]
		for v in values:
			var val_lbl = Label.new()
			val_lbl.text = v
			val_lbl.custom_minimum_size = Vector2(80, 0)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			val_lbl.add_theme_font_size_override("font_size", 22)
			val_lbl.add_theme_color_override("font_color", Color.WHITE)
			row_hbox.add_child(val_lbl)
			
		rank_idx += 1

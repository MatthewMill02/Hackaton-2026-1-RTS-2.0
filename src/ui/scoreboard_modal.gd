# Overwatch-style Dynamic TAB In-Game Ranking & Scoreboard Overlay
class_name ScoreboardModal
extends Control

var network_manager: NetworkManager
var settings_manager: SettingsManager
var target_points: int = 1200
var buildings: BuildingSystem
var units: UnitManager
var economy: EconomyManager
var local_slot: int = 0
var hud: InGameHUD

var timer_lbl: Label
var goal_lbl: Label
var player_rows_vbox: VBoxContainer
var ping_lbl: Label

# Bottom My Metrics Labels
var lbl_my_pts: Label
var lbl_my_kills: Label
var lbl_my_camps: Label
var lbl_my_bld: Label
var lbl_my_units: Label
var lbl_my_res: Label

var refresh_timer: float = 0.0

func _init(
	p_net: NetworkManager,
	p_settings: SettingsManager,
	p_pts: int,
	p_buildings: BuildingSystem,
	p_units: UnitManager,
	p_economy: EconomyManager,
	p_local_slot: int,
	p_hud: InGameHUD
) -> void:
	network_manager = p_net
	settings_manager = p_settings
	target_points = p_pts
	buildings = p_buildings
	units = p_units
	economy = p_economy
	local_slot = p_local_slot
	hud = p_hud
	
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_build_ui()
	_update_dynamic_data()

func _process(delta: float) -> void:
	# Update match timer in header
	if hud != null and timer_lbl != null:
		var mins = int(hud.match_timer_seconds) / 60
		var secs = int(hud.match_timer_seconds) % 60
		timer_lbl.text = "⏱️ %02d:%02d" % [mins, secs]
		
	# Refresh table stats periodically (every 0.15s)
	refresh_timer += delta
	if refresh_timer >= 0.15:
		refresh_timer = 0.0
		_update_dynamic_data()

func _build_ui() -> void:
	# Semi-transparent dark cinematic backdrop
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.08, 0.88)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	
	var main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(1000, 560)
	var panel_sb = UITheme.create_panel_style(
		Color(0.04, 0.07, 0.12, 0.96),
		Color(0.14, 0.28, 0.44, 0.85),
		6, 2, 0
	)
	main_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(main_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_panel.add_child(main_vbox)
	
	# --- 1. TOP HEADER BANNER ---
	var top_bar = PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 56)
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
	rank_lbl.text = "🏆 RANKING NA ŻYWO"
	rank_lbl.add_theme_font_size_override("font_size", 24)
	rank_lbl.add_theme_color_override("font_color", UITheme.COLOR_MODAL_HEADER_TEXT)
	top_hbox.add_child(rank_lbl)
	
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer1)
	
	goal_lbl = Label.new()
	goal_lbl.text = "CEL: %d PKT" % target_points
	goal_lbl.add_theme_font_size_override("font_size", 17)
	goal_lbl.add_theme_color_override("font_color", Color(0.12, 0.20, 0.30))
	top_hbox.add_child(goal_lbl)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer2)
	
	timer_lbl = Label.new()
	var mins = int(hud.match_timer_seconds) / 60 if hud else 45
	var secs = int(hud.match_timer_seconds) % 60 if hud else 0
	timer_lbl.text = "⏱️ %02d:%02d" % [mins, secs]
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
	col_header_row.add_theme_constant_override("separation", 12)
	content_vbox.add_child(col_header_row)
	
	var h_rank = Label.new()
	h_rank.text = "#"
	h_rank.custom_minimum_size = Vector2(28, 0)
	h_rank.add_theme_font_size_override("font_size", 13)
	h_rank.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	col_header_row.add_child(h_rank)
	
	var h_player = Label.new()
	h_player.text = "GRACZ / DRUŻYNA"
	h_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_player.add_theme_font_size_override("font_size", 13)
	h_player.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	col_header_row.add_child(h_player)
	
	var columns = [
		{"name": "PKT", "sub": "WYNIK"},
		{"name": "BUD", "sub": "BUDYNKI"},
		{"name": "JDN", "sub": "JEDNOSTKI"},
		{"name": "ZAB", "sub": "ZABICIA"},
		{"name": "OBOZY", "sub": "ZNISZCZONE"}
	]
	
	for col in columns:
		var c_vbox = VBoxContainer.new()
		c_vbox.custom_minimum_size = Vector2(90, 0)
		c_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		col_header_row.add_child(c_vbox)
		
		var t1 = Label.new()
		t1.text = col.name
		t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t1.add_theme_font_size_override("font_size", 14)
		t1.add_theme_color_override("font_color", Color.WHITE)
		c_vbox.add_child(t1)
		
		var t2 = Label.new()
		t2.text = col.sub
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t2.add_theme_font_size_override("font_size", 10)
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
	st_title.text = "TWOJE STATYSTYKI BIEŻĄCE"
	st_title.add_theme_font_size_override("font_size", 13)
	st_title.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	stats_vbox.add_child(st_title)
	
	var metrics_row = HBoxContainer.new()
	metrics_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_child(metrics_row)
	
	var my_metrics = [
		{"key": "pts", "name": "PUNKTY"},
		{"key": "kills", "name": "ZABICIA WROGÓW"},
		{"key": "camps", "name": "ZNISZCZONE OBOZY"},
		{"key": "bld", "name": "STRUKTURY"},
		{"key": "units", "name": "JEDNOSTKI"},
		{"key": "res", "name": "SUROWCE W BAZIE"}
	]
	
	for m in my_metrics:
		var m_box = VBoxContainer.new()
		m_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m_box.alignment = BoxContainer.ALIGNMENT_CENTER
		metrics_row.add_child(m_box)
		
		var num = Label.new()
		num.text = "0"
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 26)
		num.add_theme_color_override("font_color", Color.WHITE)
		m_box.add_child(num)
		
		match m.key:
			"pts": lbl_my_pts = num
			"kills": lbl_my_kills = num
			"camps": lbl_my_camps = num
			"bld": lbl_my_bld = num
			"units": lbl_my_units = num
			"res": lbl_my_res = num
			
		var desc = Label.new()
		desc.text = m.name
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		m_box.add_child(desc)
		
	# Footer hint
	ping_lbl = Label.new()
	ping_lbl.text = "⏱️ Dynamiczna aktualizacja na żywo · Puść [TAB], aby powrócić do gry"
	ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_lbl.add_theme_font_size_override("font_size", 12)
	ping_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	stats_vbox.add_child(ping_lbl)

func _update_dynamic_data() -> void:
	if player_rows_vbox == null: return
	
	for c in player_rows_vbox.get_children():
		c.queue_free()
		
	var players: Array = []
	if network_manager != null:
		players = network_manager.get_players_list()
	if players.is_empty():
		var dummy = PlayerData.new()
		dummy.name = settings_manager.player_name if settings_manager else "Pracownik"
		dummy.is_host = true
		dummy.slot = local_slot
		dummy.color = GameState.SLOT_COLORS[local_slot]
		players.append(dummy)
		
	# Compute live statistics for each participant
	var stats_list: Array = []
	for p in players:
		var slot_bld_count = 0
		var slot_bld_points = 0
		if buildings != null:
			for b in buildings.building_instances:
				if b.slot == p.slot and b.hp > 0:
					slot_bld_count += 1
					if hud != null:
						slot_bld_points += hud._get_building_score_points(b.def_id)
					else:
						slot_bld_points += 20
						
		var slot_units_count = 0
		if units != null:
			for u in units.units:
				if u.slot == p.slot and u.hp > 0:
					slot_units_count += 1
					
		var p_pts = 0
		var p_kills = 0
		var p_camps = 0
		
		if p.slot == local_slot and hud != null:
			p_pts = hud.current_score
			p_kills = hud.kills_count
			p_camps = hud.camps_count
		else:
			p_pts = slot_bld_points + (slot_units_count * 15)
			p_kills = maxi(0, slot_units_count / 2)
			p_camps = 0
			
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
	
	# Render dynamic rows
	var rank_idx = 1
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	
	for entry in stats_list:
		var p: PlayerData = entry.player
		var row_panel = PanelContainer.new()
		var slot_col = GameState.SLOT_COLORS[p.slot] if p.slot < GameState.SLOT_COLORS.size() else UITheme.COLOR_ACCENT_CYAN
		var is_me = (p.slot == local_slot or p.peer_id == my_id or (network_manager == null and p.is_host))
		
		var bg_col = Color(0.10, 0.18, 0.28, 0.95) if is_me else Color(0.05, 0.09, 0.14, 0.85)
		var border_col = Color(slot_col.r, slot_col.g, slot_col.b, 0.6) if is_me else Color.TRANSPARENT
		var r_sb = UITheme.create_panel_style(bg_col, border_col, 4, 1 if is_me else 0, 8)
		row_panel.add_theme_stylebox_override("panel", r_sb)
		player_rows_vbox.add_child(row_panel)
		
		var row_hbox = HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 12)
		row_panel.add_child(row_hbox)
		
		# Rank Number (#1, #2, #3, #4)
		var rank_lbl = Label.new()
		rank_lbl.text = "#%d" % rank_idx
		rank_lbl.custom_minimum_size = Vector2(28, 0)
		rank_lbl.add_theme_font_size_override("font_size", 16)
		var rank_col = UITheme.COLOR_WARNING_GOLD if rank_idx == 1 else UITheme.COLOR_TEXT_MUTED
		rank_lbl.add_theme_color_override("font_color", rank_col)
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
		var tag = " (BOT)" if p.is_bot else (" (TY)" if is_me else "")
		p_name_lbl.text = p.name.to_upper() + tag
		p_name_lbl.add_theme_font_size_override("font_size", 16)
		p_name_lbl.add_theme_color_override("font_color", slot_col)
		p_vbox.add_child(p_name_lbl)
		
		var p_role_lbl = Label.new()
		var role_str = "AI BOT (POZ. %d)" % p.bot_difficulty if p.is_bot else ("HOST POKOJU" if p.is_host else "GRACZ SIECIOWY")
		p_role_lbl.text = role_str + " · Baza %d" % (p.slot + 1)
		p_role_lbl.add_theme_font_size_override("font_size", 11)
		p_role_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		p_vbox.add_child(p_role_lbl)
		
		# Metric columns: PKT, BUD, JDN, ZAB, OBOZY
		var values = [
			str(entry.pts),
			str(entry.bld),
			str(entry.units),
			str(entry.kills),
			str(entry.camps)
		]
		
		for i in range(values.size()):
			var val_lbl = Label.new()
			val_lbl.text = values[i]
			val_lbl.custom_minimum_size = Vector2(90, 0)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			val_lbl.add_theme_font_size_override("font_size", 20)
			if i == 0:
				val_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
			else:
				val_lbl.add_theme_color_override("font_color", Color.WHITE)
			row_hbox.add_child(val_lbl)
			
		rank_idx += 1
		
	# Update bottom "TWOJE STATYSTYKI" summary panel
	if lbl_my_pts != null and hud != null:
		lbl_my_pts.text = str(hud.current_score)
		lbl_my_pts.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	if lbl_my_kills != null and hud != null:
		lbl_my_kills.text = str(hud.kills_count)
	if lbl_my_camps != null and hud != null:
		lbl_my_camps.text = str(hud.camps_count)
	if lbl_my_bld != null and buildings != null:
		var my_b_cnt = buildings.building_instances.filter(func(b): return b.slot == local_slot and b.hp > 0).size()
		lbl_my_bld.text = str(my_b_cnt)
	if lbl_my_units != null and units != null:
		var my_u_cnt = units.units.filter(func(u): return u.slot == local_slot and u.hp > 0).size()
		lbl_my_units.text = str(my_u_cnt)
	if lbl_my_res != null and economy != null:
		var total_res = economy.stone + economy.iron + economy.oil + economy.redstone
		lbl_my_res.text = str(total_res)

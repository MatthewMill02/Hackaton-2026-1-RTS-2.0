# RTS Lab & Research Cards Modal (Przetwórnia Danych)
class_name LabResearchModal
extends PanelContainer

signal card_crafted()
signal card_revealed(item: ResearchSystem.CardItem)
signal card_sold(item: ResearchSystem.CardItem)
signal closed()

var target_building: BuildingSystem.BuildingInstance
var economy: EconomyManager
var research: ResearchSystem
var network_manager: NetworkManager

var current_filter: String = "ALL" # "ALL", "REVEALED", "COVERED"
var grid_container: HFlowContainer
var pool_count_lbl: Label
var craft_btn: Button

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var is_minimized: bool = false

var minimize_btn: Button
var body_vbox: VBoxContainer

func _init(
	p_building: BuildingSystem.BuildingInstance,
	p_economy: EconomyManager,
	p_research: ResearchSystem,
	p_net: NetworkManager = null
) -> void:
	target_building = p_building
	economy = p_economy
	research = p_research
	network_manager = p_net
	
	custom_minimum_size = Vector2(820, 0)
	
	var sb = UITheme.create_panel_style(Color(0.03, 0.06, 0.10, 0.96), UITheme.COLOR_ACCENT_CYAN, 6, 2, 12)
	add_theme_stylebox_override("panel", sb)

func _ready() -> void:
	var vp_size = get_viewport_rect().size
	position = Vector2(maxf(40, vp_size.x * 0.5 - 410), maxf(50, vp_size.y * 0.5 - 280))
	_build_ui()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		move_to_front()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
		
	var mvbox = VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 10)
	add_child(mvbox)
	
	# 1. Header: Draggable Bar with Title + Minimize + Close
	var header_panel = PanelContainer.new()
	var sb_hdr = UITheme.create_panel_style(Color(0.06, 0.12, 0.20, 0.95), UITheme.COLOR_ACCENT_CYAN, 4, 1, 8)
	header_panel.add_theme_stylebox_override("panel", sb_hdr)
	header_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header_panel.gui_input.connect(_on_header_gui_input)
	mvbox.add_child(header_panel)
	
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_row.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header_row)
	
	var title_lbl = Label.new()
	title_lbl.text = "🔬 PRZETWÓRNIA DANYCH & KARTY BADAWCZE"
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(title_lbl)
	
	var is_powered = target_building.is_powered and not economy.is_blackout and target_building.emp_overload_timer <= 0.0
	var pwr_lbl = Label.new()
	pwr_lbl.text = "⚡ ZASILANIE: AKTYWNE" if is_powered else "⚠️ BRAK ZASILANIA"
	pwr_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN if is_powered else UITheme.COLOR_ACCENT_RED)
	pwr_lbl.add_theme_font_size_override("font_size", 12)
	pwr_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(pwr_lbl)
	
	var drag_hint = Label.new()
	drag_hint.text = "⋮⋮ PRZESUŃ"
	drag_hint.add_theme_font_size_override("font_size", 11)
	drag_hint.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	drag_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(drag_hint)
	
	# Minimize / Expand Button
	minimize_btn = Button.new()
	minimize_btn.text = "▼" if is_minimized else "─"
	minimize_btn.tooltip_text = "Rozwiń okno badań" if is_minimized else "Zwiń okno badań"
	minimize_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(minimize_btn, Color(0.10, 0.20, 0.32), UITheme.COLOR_ACCENT_CYAN, 30, 14)
	minimize_btn.pressed.connect(_toggle_minimize)
	header_row.add_child(minimize_btn)
	
	# Close Button
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Zamknij okno badań"
	close_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(close_btn, Color(0.35, 0.10, 0.14), UITheme.COLOR_ACCENT_RED, 30, 14)
	close_btn.pressed.connect(func():
		closed.emit()
		queue_free()
	)
	header_row.add_child(close_btn)
	
	# Collapsible Body
	body_vbox = VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 12)
	body_vbox.visible = not is_minimized
	mvbox.add_child(body_vbox)
	
	# 2. Crafting & Passive Summary Row
	var craft_summary_hbox = HBoxContainer.new()
	craft_summary_hbox.add_theme_constant_override("separation", 16)
	body_vbox.add_child(craft_summary_hbox)
	
	# Crafting Card Panel
	var craft_panel = PanelContainer.new()
	craft_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_craft = UITheme.create_panel_style(Color(0.06, 0.11, 0.18, 0.95), Color(0.18, 0.35, 0.55, 0.7), 4, 1, 8)
	craft_panel.add_theme_stylebox_override("panel", sb_craft)
	craft_summary_hbox.add_child(craft_panel)
	
	var craft_vbox = VBoxContainer.new()
	craft_vbox.add_theme_constant_override("separation", 6)
	craft_panel.add_child(craft_vbox)
	
	var craft_title = Label.new()
	craft_title.text = "🧪 Skraftuj Kartę Badań (Tier 1 / Common)"
	craft_title.add_theme_font_size_override("font_size", 15)
	craft_title.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	craft_vbox.add_child(craft_title)
	
	var craft_cost_lbl = Label.new()
	craft_cost_lbl.text = "Koszt: ⚙️ 80 Żelazo  🛢️ 40 Ropa  🔴 15 Czerwienit"
	craft_cost_lbl.add_theme_font_size_override("font_size", 12)
	craft_cost_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	craft_vbox.add_child(craft_cost_lbl)
	
	var pool_row = HBoxContainer.new()
	craft_vbox.add_child(pool_row)
	
	pool_count_lbl = Label.new()
	pool_count_lbl.text = "Dostępne w puli meczu: %d szt." % research.common_pool.size()
	pool_count_lbl.add_theme_font_size_override("font_size", 12)
	pool_count_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	pool_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_row.add_child(pool_count_lbl)
	
	var can_afford = economy.can_afford(ResearchSystem.COMMON_CRAFT_COST)
	var has_pool = not research.common_pool.is_empty()
	var can_craft = is_powered and can_afford and has_pool
	
	craft_btn = Button.new()
	if not has_pool:
		craft_btn.text = "PULA WYCZERPANA"
	elif not is_powered:
		craft_btn.text = "BRAK ZASILANIA"
	elif not can_afford:
		craft_btn.text = "BRAK SUROWCÓW"
	else:
		craft_btn.text = "SKRAFTUJ KARTĘ"
		
	craft_btn.custom_minimum_size = Vector2(160, 36)
	var btn_bg = Color(0.12, 0.40, 0.25) if can_craft else Color(0.25, 0.12, 0.14)
	var btn_acc = UITheme.COLOR_SUCCESS_GREEN if can_craft else UITheme.COLOR_ACCENT_RED
	UITheme.style_button(craft_btn, btn_bg, btn_acc, 36, 13)
	craft_btn.disabled = not can_craft
	craft_btn.pressed.connect(_on_craft_pressed)
	pool_row.add_child(craft_btn)
	
	# Active Bonuses Summary Panel
	var summary_panel = PanelContainer.new()
	summary_panel.custom_minimum_size = Vector2(280, 0)
	var sb_sum = UITheme.create_panel_style(Color(0.04, 0.08, 0.14, 0.90), Color(0.15, 0.30, 0.45, 0.6), 4, 1, 8)
	summary_panel.add_theme_stylebox_override("panel", sb_sum)
	craft_summary_hbox.add_child(summary_panel)
	
	var sum_vbox = VBoxContainer.new()
	sum_vbox.add_theme_constant_override("separation", 3)
	summary_panel.add_child(sum_vbox)
	
	var sum_title = Label.new()
	sum_title.text = "⚡ AKTYWNE BONUSY BADAWCZE"
	sum_title.add_theme_font_size_override("font_size", 13)
	sum_title.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	sum_vbox.add_child(sum_title)
	
	var m_txt = "⛏️ Wydobycie: +%d%%" % int((research.mining_multiplier - 1.0) * 100.0)
	var b_txt = "🔋 Baterie: +%d%%" % int((research.battery_capacity_mult - 1.0) * 100.0)
	var s_txt = "🛡️ HP Struktur: +%d%%" % int((research.structure_hp_mult - 1.0) * 100.0)
	var u_txt = "🏎️ Szybkość: +%d%%" % int((research.unit_speed_mult - 1.0) * 100.0)
	var t_txt = "🎯 Wieżyczki: +%d%% dmg" % int((research.turret_damage_mult - 1.0) * 100.0)
	
	for line in [m_txt, b_txt, s_txt, u_txt, t_txt]:
		var l = Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
		sum_vbox.add_child(l)
		
	# 3. Filter Bar
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	body_vbox.add_child(filter_row)
	
	var total_cards = research.player_cards.size()
	var revealed_cards = research.player_cards.filter(func(c): return c.is_revealed).size()
	var covered_cards = total_cards - revealed_cards
	
	var btn_all = Button.new()
	btn_all.text = "Wszystkie (%d)" % total_cards
	_style_filter_btn(btn_all, current_filter == "ALL")
	btn_all.pressed.connect(func(): current_filter = "ALL"; _build_ui())
	filter_row.add_child(btn_all)
	
	var btn_rev = Button.new()
	btn_rev.text = "Odkryte / Aktywne (%d)" % revealed_cards
	_style_filter_btn(btn_rev, current_filter == "REVEALED")
	btn_rev.pressed.connect(func(): current_filter = "REVEALED"; _build_ui())
	filter_row.add_child(btn_rev)
	
	var btn_cov = Button.new()
	btn_cov.text = "Zakryte w Ekwipunku (%d)" % covered_cards
	_style_filter_btn(btn_cov, current_filter == "COVERED")
	btn_cov.pressed.connect(func(): current_filter = "COVERED"; _build_ui())
	filter_row.add_child(btn_cov)
	
	# 4. Scrollable Cards Container
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_vbox.add_child(scroll)
	
	grid_container = HFlowContainer.new()
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 14)
	grid_container.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid_container)
	
	var filtered_list = research.player_cards.filter(func(c):
		if current_filter == "REVEALED": return c.is_revealed
		if current_filter == "COVERED": return not c.is_revealed
		return true
	)
	
	if filtered_list.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Brak kart w tej kategorii. Skraftuj karty powyżej lub zdobądź je niszcząc obozy i bossów!"
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		grid_container.add_child(empty_lbl)
	else:
		for item in filtered_list:
			_render_card_widget(item)

func _style_filter_btn(btn: Button, is_active: bool) -> void:
	btn.custom_minimum_size = Vector2(140, 30)
	var bg = Color(0.12, 0.28, 0.44) if is_active else Color(0.05, 0.09, 0.15)
	var acc = UITheme.COLOR_ACCENT_CYAN if is_active else Color(0.2, 0.35, 0.5)
	UITheme.style_button(btn, bg, acc, 30, 12)

func _render_card_widget(item: ResearchSystem.CardItem) -> void:
	var c_panel = PanelContainer.new()
	c_panel.custom_minimum_size = Vector2(165, 230)
	
	if item.is_revealed:
		# Revealed (Awers) - White / Tech Frame with Rarity Border
		var rarity_col = Color(0.3, 0.8, 0.4) # Common green/gray
		var rarity_txt = "ZWYKŁA"
		if item.def.rarity == ResearchSystem.CardRarity.RARE:
			rarity_col = Color(0.1, 0.6, 1.0) # Rare blue
			rarity_txt = "RZADKA"
		elif item.def.rarity == ResearchSystem.CardRarity.LEGENDARY:
			rarity_col = Color(1.0, 0.75, 0.1) # Legendary gold
			rarity_txt = "LEGENDARNA"
			
		var sb_card = UITheme.create_panel_style(Color(0.92, 0.94, 0.97, 0.98), rarity_col, 4, 2, 8)
		c_panel.add_theme_stylebox_override("panel", sb_card)
		grid_container.add_child(c_panel)
		
		var cvbox = VBoxContainer.new()
		cvbox.add_theme_constant_override("separation", 4)
		c_panel.add_child(cvbox)
		
		var r_lbl = Label.new()
		r_lbl.text = rarity_txt
		r_lbl.add_theme_font_size_override("font_size", 10)
		r_lbl.add_theme_color_override("font_color", rarity_col)
		r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(r_lbl)
		
		var emoji_lbl = Label.new()
		emoji_lbl.text = item.def.emoji
		emoji_lbl.add_theme_font_size_override("font_size", 34)
		emoji_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(emoji_lbl)
		
		var name_lbl = Label.new()
		name_lbl.text = item.def.name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cvbox.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = item.def.description
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.38))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cvbox.add_child(desc_lbl)
		
		var active_badge = Label.new()
		active_badge.text = "● AKTYWNY BONUS"
		active_badge.add_theme_font_size_override("font_size", 10)
		active_badge.add_theme_color_override("font_color", Color(0.1, 0.65, 0.25))
		active_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(active_badge)
		
	else:
		# Covered (Rewers) - Cyberpunk Face-down Frame
		var sb_rewers = UITheme.create_panel_style(Color(0.04, 0.08, 0.15, 0.95), UITheme.COLOR_ACCENT_CYAN, 4, 1.5, 8)
		c_panel.add_theme_stylebox_override("panel", sb_rewers)
		grid_container.add_child(c_panel)
		
		var cvbox = VBoxContainer.new()
		cvbox.add_theme_constant_override("separation", 6)
		c_panel.add_child(cvbox)
		
		var rew_hdr = Label.new()
		rew_hdr.text = "ZAKRYTA"
		rew_hdr.add_theme_font_size_override("font_size", 10)
		rew_hdr.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
		rew_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(rew_hdr)
		
		var lock_lbl = Label.new()
		lock_lbl.text = "💾"
		lock_lbl.add_theme_font_size_override("font_size", 32)
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(lock_lbl)
		
		var rew_sub = Label.new()
		rew_sub.text = "Nieodkryta karta badań. Odkryj, aby aktywować."
		rew_sub.add_theme_font_size_override("font_size", 10)
		rew_sub.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		rew_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rew_sub.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cvbox.add_child(rew_sub)
		
		var rev_btn = Button.new()
		rev_btn.text = "🔓 ODKRYJ"
		rev_btn.custom_minimum_size = Vector2(0, 30)
		UITheme.style_button(rev_btn, Color(0.10, 0.35, 0.22), UITheme.COLOR_SUCCESS_GREEN, 30, 11)
		var item_id = item.item_id
		rev_btn.pressed.connect(func():
			_on_reveal_pressed(item_id)
		)
		cvbox.add_child(rev_btn)
		
		var sell_btn = Button.new()
		sell_btn.text = "💰 SPRZEDAJ (100%)"
		sell_btn.custom_minimum_size = Vector2(0, 26)
		UITheme.style_button(sell_btn, Color(0.28, 0.16, 0.08), UITheme.COLOR_WARNING_GOLD, 26, 10)
		sell_btn.pressed.connect(func():
			_on_sell_pressed(item_id)
		)
		cvbox.add_child(sell_btn)

func _on_craft_pressed() -> void:
	var item = research.craft_common_card(economy)
	if item != null:
		card_crafted.emit()
		_build_ui()

func _on_reveal_pressed(item_id: int) -> void:
	if research.reveal_card(item_id):
		for item in research.player_cards:
			if item.item_id == item_id:
				card_revealed.emit(item)
				break
		_build_ui()

func _on_sell_pressed(item_id: int) -> void:
	for item in research.player_cards:
		if item.item_id == item_id:
			if research.sell_covered_card(item_id, economy):
				card_sold.emit(item)
				break
	_build_ui()

func _toggle_minimize() -> void:
	is_minimized = not is_minimized
	if body_vbox != null:
		body_vbox.visible = not is_minimized
	if minimize_btn != null:
		minimize_btn.text = "▼" if is_minimized else "─"
		minimize_btn.tooltip_text = "Rozwiń okno badań" if is_minimized else "Zwiń okno badań (tryb kompaktowy)"

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			if is_dragging:
				drag_offset = get_global_mouse_position() - global_position
				move_to_front()
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position() - drag_offset
		_clamp_to_screen()

func _clamp_to_screen() -> void:
	var vp_size = get_viewport_rect().size
	var cur_sz = get_rect().size
	global_position.x = clampf(global_position.x, 10, maxf(10, vp_size.x - cur_sz.x - 10))
	global_position.y = clampf(global_position.y, 10, maxf(10, vp_size.y - cur_sz.y - 10))

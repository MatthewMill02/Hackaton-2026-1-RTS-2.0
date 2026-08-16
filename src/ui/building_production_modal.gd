# RTS Building Production Modal (HQ Drones & Factory Combat Units) - Draggable & Minimizable Window
class_name BuildingProductionModal
extends PanelContainer

signal unit_trained(def_id: String, building: BuildingSystem.BuildingInstance)
signal closed()

var target_building: BuildingSystem.BuildingInstance
var building_def: BuildingSystem.BuildingDef
var economy: EconomyManager
var unit_manager: UnitManager
var network_manager: NetworkManager

var card_buttons: Array[Button] = []
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var is_minimized: bool = false

var minimize_btn: Button
var body_vbox: VBoxContainer
var status_lbl: Label
var queue_container: VBoxContainer = null
var refresh_timer: float = 0.0

func _init(
	p_building: BuildingSystem.BuildingInstance,
	p_bdef: BuildingSystem.BuildingDef,
	p_economy: EconomyManager,
	p_units: UnitManager,
	p_net: NetworkManager = null
) -> void:
	target_building = p_building
	building_def = p_bdef
	economy = p_economy
	unit_manager = p_units
	network_manager = p_net
	
	custom_minimum_size = Vector2(460, 0)
	var sb = UITheme.create_panel_style(Color(0.03, 0.06, 0.10, 0.96), UITheme.COLOR_ACCENT_CYAN, 6, 2, 12)
	add_theme_stylebox_override("panel", sb)

func _ready() -> void:
	# Default initial placement on screen (center-left floating window)
	var vp_size = get_viewport_rect().size
	position = Vector2(maxf(40, vp_size.x * 0.5 - 230), maxf(80, vp_size.y * 0.5 - 220))
	_build_content()

func _process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer >= 0.25:
		refresh_timer = 0.0
		_refresh_queue_display()
		_refresh_buttons()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		move_to_front()

func _build_content() -> void:
	for c in get_children():
		c.queue_free()
		
	var mvbox = VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 10)
	add_child(mvbox)
	
	# Header: Draggable Bar with Title + Minimize + Close
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
	title_lbl.text = "🏛️ " + target_building.name if target_building.def_id == "hq" else "🏗️ " + target_building.name
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(title_lbl)
	
	var drag_hint = Label.new()
	drag_hint.text = "⋮⋮ PRZESUŃ"
	drag_hint.add_theme_font_size_override("font_size", 11)
	drag_hint.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	drag_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	header_row.add_child(drag_hint)
	
	# Minimize / Expand Button
	minimize_btn = Button.new()
	minimize_btn.text = "▼" if is_minimized else "─"
	minimize_btn.tooltip_text = "Rozwiń okno" if is_minimized else "Zwiń okno (tryb kompaktowy)"
	minimize_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(minimize_btn, Color(0.10, 0.20, 0.32), UITheme.COLOR_ACCENT_CYAN, 30, 14)
	minimize_btn.pressed.connect(_toggle_minimize)
	header_row.add_child(minimize_btn)
	
	# Close Button
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Zamknij okno produkcji"
	close_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(close_btn, Color(0.35, 0.10, 0.14), UITheme.COLOR_ACCENT_RED, 30, 14)
	close_btn.pressed.connect(func():
		closed.emit()
		queue_free()
	)
	header_row.add_child(close_btn)
	
	# Collapsible Body
	body_vbox = VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 10)
	body_vbox.visible = not is_minimized
	mvbox.add_child(body_vbox)
	
	# Subtitle / Status
	var is_powered = target_building.is_powered and not economy.is_blackout and target_building.emp_overload_timer <= 0.0
	var pwr_str = "⚡ STATUS: ZASILANIE AKTYWNE" if is_powered else "⚠️ STATUS: BRAK ZASILANIA / PRZECIĄŻENIE"
	var pwr_col = UITheme.COLOR_SUCCESS_GREEN if is_powered else UITheme.COLOR_ACCENT_RED
	
	status_lbl = Label.new()
	status_lbl.text = pwr_str
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", pwr_col)
	body_vbox.add_child(status_lbl)
	
	var div = ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.15, 0.28, 0.44, 0.7)
	body_vbox.add_child(div)
	
	# === TRAINING QUEUE DISPLAY ===
	queue_container = VBoxContainer.new()
	queue_container.add_theme_constant_override("separation", 6)
	body_vbox.add_child(queue_container)
	_refresh_queue_display()
	
	var div2 = ColorRect.new()
	div2.custom_minimum_size = Vector2(0, 1)
	div2.color = Color(0.15, 0.28, 0.44, 0.5)
	body_vbox.add_child(div2)
	
	# Production List
	var units_list: Array = []
	if target_building.def_id == "hq":
		units_list = [
			{
				"id": "worker_drone",
				"name": "Dron Konstrukcyjny",
				"desc": "Szybki dron budowlany. Wznosi i stawia budynki bazy.",
				"stats": "HP: 100 · Szybkość: 140 · Czas: 8s",
				"cost_text": "⚙️ 40 Żelazo  🛢️ 15 Ropa"
			}
		]
	elif target_building.def_id == "factory":
		units_list = [
			{
				"id": "scout_bot",
				"name": "Scoutbot",
				"desc": "Standardowa szybka jednostka bojowa. Skuteczna w patrolach i nękaniu wroga.",
				"stats": "HP: 120 · Atak: 15 · Zasięg: 96px · Szybkość: 180 · Czas: 12s",
				"cost_text": "⚙️ 60 Żelazo  🛢️ 25 Ropa"
			},
			{
				"id": "terminus_bot",
				"name": "Terminus",
				"desc": "Wielki, ciężki i silnie opancerzony robot bitewny. Miażdżąca siła ognia.",
				"stats": "HP: 1500 · Atak: 80 · Zasięg: 80px · Szybkość: 70 · Czas: 30s",
				"cost_text": "⚙️ 350 Żelazo  🛢️ 180 Ropa  🔴 60 Czerwienit"
			},
			{
				"id": "emp_drone",
				"name": "Dron EMP",
				"desc": "Dron kamikadze. Wybucha na 3.5 kratki, przeciążając budynki wroga na 15s (odcina zasilanie i pylony).",
				"stats": "HP: 180 · Zasięg wybuchu: 3.5 kratki · Efekt: EMP 15s · Czas: 15s",
				"cost_text": "⚙️ 100 Żelazo  🛢️ 50 Ropa  🔴 20 Czerwienit"
			}
		]
		
	card_buttons.clear()
	for item in units_list:
		var u_def = unit_manager.definitions.get(item.id, null)
		if u_def == null: continue
		
		var can_afford = economy.can_afford(u_def.cost)
		var queue_count = unit_manager.get_queue_for_building(target_building.instance_id).size()
		var queue_full = queue_count >= unit_manager.MAX_QUEUE_PER_BUILDING
		var can_build = is_powered and can_afford and not queue_full
		
		var u_panel = PanelContainer.new()
		var sb_item = UITheme.create_panel_style(Color(0.05, 0.09, 0.16, 0.90), Color(0.16, 0.32, 0.50, 0.6), 4, 1, 8)
		u_panel.add_theme_stylebox_override("panel", sb_item)
		body_vbox.add_child(u_panel)
		
		var u_hbox = HBoxContainer.new()
		u_hbox.add_theme_constant_override("separation", 14)
		u_panel.add_child(u_hbox)
		
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 3)
		u_hbox.add_child(info_vbox)
		
		var u_name_lbl = Label.new()
		u_name_lbl.text = item.name
		u_name_lbl.add_theme_font_size_override("font_size", 16)
		u_name_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
		info_vbox.add_child(u_name_lbl)
		
		var u_desc_lbl = Label.new()
		u_desc_lbl.text = item.desc
		u_desc_lbl.add_theme_font_size_override("font_size", 12)
		u_desc_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		u_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(u_desc_lbl)
		
		var u_stats_lbl = Label.new()
		u_stats_lbl.text = item.stats
		u_stats_lbl.add_theme_font_size_override("font_size", 11)
		u_stats_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_ORANGE)
		info_vbox.add_child(u_stats_lbl)
		
		var u_cost_lbl = Label.new()
		u_cost_lbl.text = item.cost_text
		u_cost_lbl.add_theme_font_size_override("font_size", 12)
		u_cost_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD if can_afford else UITheme.COLOR_ACCENT_RED)
		info_vbox.add_child(u_cost_lbl)
		
		var train_btn = Button.new()
		if queue_full:
			train_btn.text = "KOLEJKA PEŁNA"
		elif not is_powered:
			train_btn.text = "BRAK PRĄDU"
		elif not can_afford:
			train_btn.text = "BRAK SUROWCÓW"
		else:
			train_btn.text = "DODAJ DO KOLEJKI"
		train_btn.custom_minimum_size = Vector2(140, 42)
		train_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		var btn_base = Color(0.12, 0.40, 0.25) if can_build else Color(0.25, 0.12, 0.14)
		var btn_acc = UITheme.COLOR_SUCCESS_GREEN if can_build else UITheme.COLOR_ACCENT_RED
		UITheme.style_button(train_btn, btn_base, btn_acc, 42, 14)
		
		train_btn.disabled = not can_build
		
		var u_id = item.id
		train_btn.pressed.connect(func():
			_train_unit(u_id)
		)
		u_hbox.add_child(train_btn)
		card_buttons.append(train_btn)

func _refresh_queue_display() -> void:
	if queue_container == null: return
	
	for c in queue_container.get_children():
		c.queue_free()
	
	var queue = unit_manager.get_queue_for_building(target_building.instance_id)
	if queue.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "📋 Kolejka produkcyjna: pusta"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
		queue_container.add_child(empty_lbl)
		return
	
	var header_lbl = Label.new()
	header_lbl.text = "📋 KOLEJKA PRODUKCYJNA (%d/%d):" % [queue.size(), unit_manager.MAX_QUEUE_PER_BUILDING]
	header_lbl.add_theme_font_size_override("font_size", 12)
	header_lbl.add_theme_color_override("font_color", UITheme.COLOR_WARNING_GOLD)
	queue_container.add_child(header_lbl)
	
	for i in range(queue.size()):
		var entry = queue[i]
		var u_def = unit_manager.definitions.get(entry.def_id, null)
		var u_name = u_def.name if u_def != null else entry.def_id
		var is_active = (i == 0)
		
		var entry_hbox = HBoxContainer.new()
		entry_hbox.add_theme_constant_override("separation", 8)
		queue_container.add_child(entry_hbox)
		
		# Index + name
		var idx_lbl = Label.new()
		if is_active:
			var pct = int((entry.progress / entry.total_time) * 100.0)
			var remaining = int(ceil(entry.total_time - entry.progress))
			idx_lbl.text = "⏳ %s — %d%% (%ds)" % [u_name, pct, remaining]
			idx_lbl.add_theme_color_override("font_color", UITheme.COLOR_SUCCESS_GREEN)
		else:
			idx_lbl.text = "  %d. %s (oczekuje)" % [i + 1, u_name]
			idx_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LIGHT)
		idx_lbl.add_theme_font_size_override("font_size", 12)
		idx_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry_hbox.add_child(idx_lbl)
		
		# Progress bar for active entry
		if is_active:
			var bar_bg = ColorRect.new()
			bar_bg.custom_minimum_size = Vector2(120, 10)
			bar_bg.color = Color(0.08, 0.14, 0.22, 0.9)
			entry_hbox.add_child(bar_bg)
			
			var bar_fill = ColorRect.new()
			var fill_pct = clampf(entry.progress / entry.total_time, 0.0, 1.0)
			bar_fill.custom_minimum_size = Vector2(int(120.0 * fill_pct), 10)
			bar_fill.color = UITheme.COLOR_SUCCESS_GREEN
			bar_bg.add_child(bar_fill)
		
		# Cancel button
		var cancel_btn = Button.new()
		cancel_btn.text = "✕"
		cancel_btn.custom_minimum_size = Vector2(24, 24)
		UITheme.style_button(cancel_btn, Color(0.30, 0.10, 0.12), UITheme.COLOR_ACCENT_RED, 24, 12)
		cancel_btn.tooltip_text = "Anuluj (zwrot 100% surowców)"
		var captured_entry = entry
		cancel_btn.pressed.connect(func():
			unit_manager.cancel_queue_entry(captured_entry, economy)
			_refresh_queue_display()
			_build_content()
		)
		entry_hbox.add_child(cancel_btn)

func _refresh_buttons() -> void:
	# Update status label
	if status_lbl != null and is_instance_valid(status_lbl):
		var is_powered = target_building.is_powered and not economy.is_blackout and target_building.emp_overload_timer <= 0.0
		var pwr_str = "⚡ STATUS: ZASILANIE AKTYWNE" if is_powered else "⚠️ STATUS: BRAK ZASILANIA / PRZECIĄŻENIE"
		var pwr_col = UITheme.COLOR_SUCCESS_GREEN if is_powered else UITheme.COLOR_ACCENT_RED
		status_lbl.text = pwr_str
		status_lbl.add_theme_color_override("font_color", pwr_col)

func _toggle_minimize() -> void:
	is_minimized = not is_minimized
	if body_vbox != null:
		body_vbox.visible = not is_minimized
	if minimize_btn != null:
		minimize_btn.text = "▼" if is_minimized else "─"
		minimize_btn.tooltip_text = "Rozwiń okno" if is_minimized else "Zwiń okno (tryb kompaktowy)"

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

func _train_unit(def_id: String) -> void:
	var u_def = unit_manager.definitions.get(def_id, null)
	if u_def == null: return
	
	if not economy.can_afford(u_def.cost):
		return
		
	if not target_building.is_powered or economy.is_blackout:
		return
	
	var queue_count = unit_manager.get_queue_for_building(target_building.instance_id).size()
	if queue_count >= unit_manager.MAX_QUEUE_PER_BUILDING:
		return
		
	if economy.spend_resources(u_def.cost):
		unit_manager.queue_unit_training(def_id, target_building.instance_id, target_building.slot)
		_build_content()

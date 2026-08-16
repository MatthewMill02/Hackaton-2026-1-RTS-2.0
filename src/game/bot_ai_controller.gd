# RTS Bot AI Controller System (Territory Expansion, Turret Fortification, Patrol & Aggro)
class_name BotAIController
extends RefCounted

class BotInstance:
	var data: PlayerData
	var slot: int
	var difficulty: int
	var pylon_interval: float
	var turret_interval: float
	var train_interval: float
	
	var pylon_timer: float = 0.0
	var turret_timer: float = 0.0
	var train_timer: float = 0.0
	var patrol_timer: float = 0.0
	var current_status: String = "Inicjalizacja bazy"

var active_bots: Array[BotInstance] = []

func setup_bots(players_list: Array) -> void:
	active_bots.clear()
	for p in players_list:
		if p.is_bot:
			var b = BotInstance.new()
			b.data = p
			b.slot = p.slot
			b.difficulty = clampi(p.bot_difficulty, 1, 5)
			
			# Scale intervals with difficulty level (1..5)
			match b.difficulty:
				1: # Łatwy
					b.pylon_interval = 35.0
					b.turret_interval = 45.0
					b.train_interval = 28.0
				2: # Normalny
					b.pylon_interval = 22.0
					b.turret_interval = 30.0
					b.train_interval = 18.0
				3: # Trudny
					b.pylon_interval = 15.0
					b.turret_interval = 20.0
					b.train_interval = 12.0
				4: # Ekspert
					b.pylon_interval = 10.0
					b.turret_interval = 14.0
					b.train_interval = 8.0
				5: # Koszmar
					b.pylon_interval = 6.0
					b.turret_interval = 8.0
					b.train_interval = 5.0
					
			# Add initial slight random offsets so all bots don't tick on the exact same frame
			b.pylon_timer = randf_range(3.0, 7.0)
			b.turret_timer = randf_range(6.0, 12.0)
			b.train_timer = randf_range(2.0, 6.0)
			b.patrol_timer = randf_range(1.0, 3.0)
			
			active_bots.append(b)

func update(
	delta: float,
	map_data: MapData,
	buildings: BuildingSystem,
	unit_mgr: UnitManager,
	tile_px: float
) -> void:
	for bot in active_bots:
		_update_single_bot(delta, bot, map_data, buildings, unit_mgr, tile_px)

func get_bot_status(slot: int) -> String:
	for b in active_bots:
		if b.slot == slot:
			return b.current_status
	return ""

func _update_single_bot(
	delta: float,
	bot: BotInstance,
	map_data: MapData,
	buildings: BuildingSystem,
	unit_mgr: UnitManager,
	tile_px: float
) -> void:
	# 1. Pylon Expansion Loop
	bot.pylon_timer += delta
	if bot.pylon_timer >= bot.pylon_interval:
		bot.pylon_timer = 0.0
		_try_expand_pylon(bot, map_data, buildings)
		
	# 2. Turret Placement Loop
	bot.turret_timer += delta
	if bot.turret_timer >= bot.turret_interval:
		bot.turret_timer = 0.0
		_try_build_turret(bot, map_data, buildings)
		
	# 3. Unit Training Loop
	bot.train_timer += delta
	if bot.train_timer >= bot.train_interval:
		bot.train_timer = 0.0
		_try_train_unit(bot, buildings, unit_mgr, tile_px)
		
	# 4. Units Behavior & 5-tile Enemy Detection Aggro
	bot.patrol_timer += delta
	var should_repatrol = (bot.patrol_timer >= 6.0)
	if should_repatrol:
		bot.patrol_timer = 0.0
		
	_update_bot_units_ai(bot, buildings, unit_mgr, tile_px, should_repatrol)

func _try_expand_pylon(bot: BotInstance, map_data: MapData, buildings: BuildingSystem) -> void:
	# Find all bot's power nodes
	var bot_power_nodes: Array[BuildingSystem.BuildingInstance] = []
	for b in buildings.building_instances:
		if b.slot == bot.slot and b.hp > 0 and (b.def_id == "hq" or b.def_id == "pylon"):
			bot_power_nodes.append(b)
			
	if bot_power_nodes.is_empty():
		return
		
	var map_center = Vector2i(map_data.width / 2, map_data.height / 2)
	
	# Sort nodes by proximity to map center
	bot_power_nodes.sort_custom(func(a, b):
		return a.grid_pos.distance_squared_to(map_center) < b.grid_pos.distance_squared_to(map_center)
	)
	
	# Try placing a pylon extending 3-4 tiles from the closest node towards the center
	for node in bot_power_nodes:
		var dir_to_center = Vector2(map_center - node.grid_pos).normalized()
		var candidate_offsets = [
			Vector2i(int(round(dir_to_center.x * 4.0)), int(round(dir_to_center.y * 4.0))),
			Vector2i(int(round(dir_to_center.x * 3.0)), int(round(dir_to_center.y * 3.0))),
			Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4),
			Vector2i(3, 2), Vector2i(-3, 2), Vector2i(2, 3), Vector2i(-2, 3)
		]
		
		for offset in candidate_offsets:
			var check_pos = node.grid_pos + offset
			var val = buildings.is_position_valid_for_building("pylon", check_pos, bot.slot, map_data)
			if val.get("valid", false):
				var pylon = buildings.place_building("pylon", check_pos, bot.slot, map_data, null, true)
				if pylon != null:
					pylon.build_progress = 1.0 # Instant complete for bot
					bot.current_status = "Rozszerza sieć (Pylon)"
					return

func _try_build_turret(bot: BotInstance, map_data: MapData, buildings: BuildingSystem) -> void:
	# Find bot power structures
	var candidates: Array[BuildingSystem.BuildingInstance] = []
	for b in buildings.building_instances:
		if b.slot == bot.slot and b.hp > 0 and (b.def_id == "pylon" or b.def_id == "hq"):
			candidates.append(b)
			
	if candidates.is_empty():
		return
		
	candidates.shuffle()
	for node in candidates:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx == 0 and dy == 0: continue
				var pos = node.grid_pos + Vector2i(dx, dy)
				var val = buildings.is_position_valid_for_building("turret", pos, bot.slot, map_data)
				if val.get("valid", false):
					var t = buildings.place_building("turret", pos, bot.slot, map_data, null, true)
					if t != null:
						t.build_progress = 1.0
						bot.current_status = "Buduje wieżyczkę obronną"
						return

func _try_train_unit(bot: BotInstance, buildings: BuildingSystem, unit_mgr: UnitManager, tile_px: float) -> void:
	# Find bot HQ
	var hq: BuildingSystem.BuildingInstance = null
	for b in buildings.building_instances:
		if b.slot == bot.slot and b.hp > 0 and b.def_id == "hq":
			hq = b
			break
			
	if hq == null:
		return
		
	# Select unit type based on difficulty
	var unit_pool = ["scout_bot"]
	if bot.difficulty >= 2:
		unit_pool.append("emp_drone")
	if bot.difficulty >= 3:
		unit_pool.append("terminus_bot")
	if bot.difficulty >= 4:
		unit_pool.append("terminus_bot")
		unit_pool.append("scout_bot")
		
	var chosen_type = unit_pool.pick_random()
	var spawn_pos = Vector2((hq.grid_pos.x + 2.5) * tile_px, (hq.grid_pos.y + 2.5) * tile_px)
	var u = unit_mgr.spawn_unit(chosen_type, bot.slot, spawn_pos)
	if u != null:
		bot.current_status = "Tworzy jednostkę (%s)" % u.name

func _update_bot_units_ai(
	bot: BotInstance,
	buildings: BuildingSystem,
	unit_mgr: UnitManager,
	tile_px: float,
	should_repatrol: bool
) -> void:
	const AGGRO_RANGE_PX: float = 5.0 * 48.0 # 240.0 px (5 tiles)
	
	# Collect bot's power nodes for territory boundaries
	var territory_centers: Array[Vector2] = []
	for b in buildings.building_instances:
		if b.slot == bot.slot and b.hp > 0 and (b.def_id == "hq" or b.def_id == "pylon"):
			territory_centers.append(Vector2((b.grid_pos.x + 0.5) * tile_px, (b.grid_pos.y + 0.5) * tile_px))
			
	if territory_centers.is_empty():
		territory_centers.append(Vector2(25.0 * tile_px, 25.0 * tile_px))
		
	var bot_units = unit_mgr.units.filter(func(u): return u.slot == bot.slot and u.hp > 0 and u.def_id != "worker_drone")
	var is_any_attacking = false
	
	for u in bot_units:
		# 1. Vision check for enemies within 5 tiles (units and buildings)
		var closest_enemy_unit: UnitManager.UnitInstance = null
		var closest_unit_dist = AGGRO_RANGE_PX
		
		for other_u in unit_mgr.units:
			if other_u.slot != bot.slot and other_u.hp > 0:
				var dist = u.world_pos.distance_to(other_u.world_pos)
				if dist <= closest_unit_dist:
					closest_unit_dist = dist
					closest_enemy_unit = other_u
					
		if closest_enemy_unit != null:
			# Aggro on enemy unit!
			u.target_enemy_unit = closest_enemy_unit
			u.target_enemy_building = null
			u.target_enemy_camp = null
			u.target_resource = null
			u.state = UnitManager.UnitState.ATTACKING
			is_any_attacking = true
			continue
			
		# Check for nearby enemy buildings within 5 tiles
		var closest_enemy_b: BuildingSystem.BuildingInstance = null
		var closest_b_dist = AGGRO_RANGE_PX
		for b in buildings.building_instances:
			if b.slot != bot.slot and b.hp > 0:
				var b_pos = Vector2((b.grid_pos.x + b.size.x * 0.5) * tile_px, (b.grid_pos.y + b.size.y * 0.5) * tile_px)
				var dist = u.world_pos.distance_to(b_pos)
				if dist <= closest_b_dist:
					closest_b_dist = dist
					closest_enemy_b = b
					
		if closest_enemy_b != null:
			u.target_enemy_building = closest_enemy_b
			u.target_enemy_unit = null
			u.target_enemy_camp = null
			u.target_resource = null
			u.state = UnitManager.UnitState.ATTACKING
			is_any_attacking = true
			continue
			
		# 2. No enemy in 5 tiles -> Territory Patrol
		if u.state == UnitManager.UnitState.ATTACKING:
			u.state = UnitManager.UnitState.IDLE
			u.target_enemy_unit = null
			u.target_enemy_building = null
			
		if u.state == UnitManager.UnitState.IDLE or should_repatrol:
			var rand_center = territory_centers.pick_random()
			var rand_offset = Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
			u.target_pos = rand_center + rand_offset
			u.state = UnitManager.UnitState.MOVING
			
	if is_any_attacking:
		bot.current_status = "Atakuje wykrytych wrogów!"
	elif not bot_units.is_empty():
		bot.current_status = "Patroluje terytorium"

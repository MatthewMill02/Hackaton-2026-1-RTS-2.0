# RTS Unit Manager (Drones, Mining Automation Loop, Combat Units, Selection)
class_name UnitManager
extends RefCounted

signal unit_killed_reward(stone: int, iron: int, oil: int, redstone: int)

enum UnitState { IDLE, MOVING, MOVING_TO_RESOURCE, MINING, RETURNING_TO_HQ, ATTACKING, CONSTRUCTING }

class UnitDef:
	var id: String
	var name: String
	var max_hp: int
	var speed: float
	var attack_damage: int
	var attack_range: float
	var attack_cooldown: float
	var gather_rate: int
	var cost: Dictionary
	var unit_type: String
	var sprite_prefix: String
	var collision_radius: float = 12.0

class UnitInstance:
	var instance_id: int
	var def_id: String
	var name: String
	var slot: int
	var world_pos: Vector2
	var target_pos: Vector2
	var hp: int
	var max_hp: int
	var speed: float
	var attack_damage: int
	var attack_range: float
	var attack_cooldown: float
	var attack_timer: float = 0.0
	var selected: bool = false
	var collision_radius: float = 12.0
	
	# State & Gathering / Construction / Combat
	var state: UnitState = UnitState.IDLE
	var target_resource: MapData.ResourceNode = null
	var target_building: BuildingSystem.BuildingInstance = null
	var target_enemy_camp: MapData.CampNode = null
	var target_enemy_building: BuildingSystem.BuildingInstance = null
	var target_enemy_unit: UnitInstance = null
	var carried_type: int = 0
	var carried_amount: int = 0
	var max_carry: int = 15
	var mining_timer: float = 0.0
	var sprite_texture: Texture2D = null

var definitions: Dictionary = {}
var units: Array = []
var next_unit_id: int = 1
var textures_cache: Dictionary = {}

func _init() -> void:
	_register_definitions()

func _register_definitions() -> void:
	_add_def("worker_drone", "Dron Konstrukcyjny", 100, 140.0, 5, 32.0, 1.0, 0, {"iron": 30, "oil": 10}, "WORKER", "unit_worker", 12.0)
	_add_def("scout_bot", "Scoutbot", 120, 180.0, 15, 96.0, 0.8, 0, {"iron": 50, "oil": 20}, "SCOUT", "unit_scout", 14.0)
	_add_def("terminus_bot", "Terminus", 1500, 70.0, 80, 80.0, 1.8, 0, {"iron": 300, "oil": 150, "redstone": 50}, "SUPER", "unit_behemoth", 24.0)
	_add_def("emp_drone", "Dron EMP", 180, 160.0, 30, 48.0, 1.0, 0, {"iron": 90, "oil": 40, "redstone": 15}, "EMP", "unit_emp", 13.0)

func _add_def(
	p_id: String, p_name: String, p_hp: int, p_speed: float,
	p_dmg: int, p_range: float, p_cd: float, p_gather: int,
	p_cost: Dictionary, p_type: String, p_prefix: String,
	p_collision_radius: float = 12.0
) -> void:
	var d = UnitDef.new()
	d.id = p_id
	d.name = p_name
	d.max_hp = p_hp
	d.speed = p_speed
	d.attack_damage = p_dmg
	d.attack_range = p_range
	d.attack_cooldown = p_cd
	d.gather_rate = p_gather
	d.cost = p_cost
	d.unit_type = p_type
	d.sprite_prefix = p_prefix
	d.collision_radius = p_collision_radius
	definitions[p_id] = d
	
	# Cache player slot variations (p0..p3)
	for slot_i in range(4):
		var key = "%s_p%d" % [p_id, slot_i]
		var path = "res://public/sprites/units/%s_p%d.png" % [p_prefix, slot_i]
		var tex = UITheme.load_texture_safe(path)
		if tex != null:
			textures_cache[key] = tex

func find_free_spawn_position(base_pos: Vector2, required_radius: float = 14.0) -> Vector2:
	var is_occupied = false
	for u in units:
		if u.hp > 0 and u.world_pos.distance_to(base_pos) < (u.collision_radius + required_radius):
			is_occupied = true
			break
			
	if not is_occupied:
		return base_pos
		
	# Spiral search for nearest unoccupied spot
	for ring in range(1, 8):
		var ring_dist = ring * (required_radius * 2.2)
		var sample_count = ring * 8
		for i in range(sample_count):
			var angle = (float(i) / float(sample_count)) * TAU
			var cand = base_pos + Vector2(cos(angle), sin(angle)) * ring_dist
			var cand_clear = true
			for u in units:
				if u.hp > 0 and u.world_pos.distance_to(cand) < (u.collision_radius + required_radius):
					cand_clear = false
					break
			if cand_clear:
				return cand
				
	return base_pos + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))

func spawn_unit(def_id: String, slot: int, spawn_pos: Vector2, override_id: int = -1) -> UnitInstance:
	var def = definitions.get(def_id, null)
	if def == null: return null
	
	var effective_pos = spawn_pos
	if override_id <= 0:
		effective_pos = find_free_spawn_position(spawn_pos, def.collision_radius)
		
	var u = UnitInstance.new()
	if override_id > 0:
		u.instance_id = override_id
		next_unit_id = maxi(next_unit_id, override_id + 1)
	else:
		u.instance_id = slot * 10000 + next_unit_id
		next_unit_id += 1
		
	u.def_id = def.id
	u.name = def.name
	u.slot = slot
	u.world_pos = effective_pos
	u.target_pos = effective_pos
	u.hp = def.max_hp
	u.max_hp = def.max_hp
	u.speed = def.speed
	u.attack_damage = def.attack_damage
	u.attack_range = def.attack_range
	u.attack_cooldown = def.attack_cooldown
	u.collision_radius = def.collision_radius
	
	var tex_key = "%s_p%d" % [def_id, slot]
	u.sprite_texture = textures_cache.get(tex_key, null)
	
	units.append(u)
	return u

func get_unit_by_id(u_id: int) -> UnitInstance:
	for u in units:
		if u.instance_id == u_id and u.hp > 0:
			return u
	return null

func update_units(delta: float, map_data: MapData, buildings: Array, economy: EconomyManager, tile_px: float, local_slot: int = -1, research: ResearchSystem = null) -> void:
	for u in units:
		if u.hp <= 0: continue
		
		var speed_mult = research.unit_speed_mult if (research != null and u.slot == local_slot) else 1.0
		
		match u.state:
			UnitState.IDLE, UnitState.MOVING:
				if u.state == UnitState.MOVING:
					if u.world_pos.distance_to(u.target_pos) > 4.0:
						u.world_pos = u.world_pos.move_toward(u.target_pos, u.speed * speed_mult * delta)
					else:
						u.state = UnitState.IDLE
						
				# Check for direct overlap / contact with enemy units
				if u.def_id == "emp_drone":
					var contact_enemy = _find_nearest_enemy_unit(u, units, 36.0)
					if contact_enemy != null:
						_trigger_emp_blast(u, buildings, tile_px)
						u.hp = 0
						continue
				else:
					# Overlap / collision combat check (within attack range or physical overlap)
					var nearby_enemy = _find_nearest_enemy_unit(u, units, maxf(u.attack_range, 32.0))
					if nearby_enemy != null:
						# If idle or overlapping close (collision), auto-engage in combat!
						if u.state == UnitState.IDLE or u.world_pos.distance_to(nearby_enemy.world_pos) <= 24.0:
							u.target_enemy_unit = nearby_enemy
							u.state = UnitState.ATTACKING
					
			UnitState.MOVING_TO_RESOURCE:
				if u.target_resource == null or u.target_resource.amount <= 0:
					u.state = UnitState.IDLE
					continue
				var res_world = Vector2((u.target_resource.grid_pos.x + 0.5) * tile_px, (u.target_resource.grid_pos.y + 0.5) * tile_px)
				if u.world_pos.distance_to(res_world) > 18.0:
					u.world_pos = u.world_pos.move_toward(res_world, u.speed * delta)
				else:
					u.state = UnitState.MINING
					u.mining_timer = 0.0
					
			UnitState.MINING:
				if u.target_resource == null or u.target_resource.amount <= 0:
					u.state = UnitState.RETURNING_TO_HQ if u.carried_amount > 0 else UnitState.IDLE
					continue
				u.mining_timer += delta
				if u.mining_timer >= 1.0: # Mine 5 per second
					u.mining_timer = 0.0
					var mined = mini(5, u.target_resource.amount)
					u.target_resource.amount -= mined
					u.carried_type = u.target_resource.type
					u.carried_amount = mined
					u.state = UnitState.RETURNING_TO_HQ
					
			UnitState.RETURNING_TO_HQ:
				# Find nearest HQ or Storage of this player
				var nearest_drop = _find_nearest_depot(u.world_pos, u.slot, buildings, tile_px)
				if nearest_drop == Vector2.ZERO:
					u.state = UnitState.IDLE
					continue
				if u.world_pos.distance_to(nearest_drop) > 25.0:
					u.world_pos = u.world_pos.move_toward(nearest_drop, u.speed * delta)
				else:
					# Deposit: only add to local economy if this unit belongs to local player
					if u.carried_amount > 0:
						if local_slot < 0 or u.slot == local_slot:
							economy.add_resource(u.carried_type, u.carried_amount)
						u.carried_amount = 0
					# Return to mining if resource still exists
					if u.target_resource != null and u.target_resource.amount > 0:
						u.state = UnitState.MOVING_TO_RESOURCE
					else:
						u.state = UnitState.IDLE
						
			UnitState.ATTACKING:
				if u.target_enemy_camp != null:
					if u.target_enemy_camp.hp <= 0:
						u.state = UnitState.IDLE
						u.target_enemy_camp = null
						continue
					var camp_world = Vector2((u.target_enemy_camp.grid_pos.x + 0.5) * tile_px, (u.target_enemy_camp.grid_pos.y + 0.5) * tile_px)
					var dist = u.world_pos.distance_to(camp_world)
					if dist > u.attack_range:
						u.world_pos = u.world_pos.move_toward(camp_world, u.speed * delta)
					else:
						if u.def_id == "emp_drone":
							_trigger_emp_blast(u, buildings, tile_px)
							u.hp = 0
							continue
						u.attack_timer += delta
						if u.attack_timer >= u.attack_cooldown:
							u.attack_timer = 0.0
							u.target_enemy_camp.hp -= u.attack_damage
				elif u.target_enemy_building != null:
					if u.target_enemy_building.hp <= 0:
						u.state = UnitState.IDLE
						u.target_enemy_building = null
						continue
					var b_world = Vector2((u.target_enemy_building.grid_pos.x + u.target_enemy_building.size.x * 0.5) * tile_px, (u.target_enemy_building.grid_pos.y + u.target_enemy_building.size.y * 0.5) * tile_px)
					var dist = u.world_pos.distance_to(b_world)
					if dist > u.attack_range:
						u.world_pos = u.world_pos.move_toward(b_world, u.speed * speed_mult * delta)
					else:
						if u.def_id == "emp_drone":
							_trigger_emp_blast(u, buildings, tile_px)
							u.hp = 0
							continue
						u.attack_timer += delta
						if u.attack_timer >= u.attack_cooldown:
							u.attack_timer = 0.0
							u.target_enemy_building.hp -= u.attack_damage
				elif u.target_enemy_unit != null:
					if u.target_enemy_unit.hp <= 0:
						# Immediate chain to next overlapping/in-range enemy
						var next_enemy = _find_nearest_enemy_unit(u, units, u.attack_range + 32.0)
						if next_enemy != null:
							u.target_enemy_unit = next_enemy
						else:
							u.state = UnitState.IDLE
							u.target_enemy_unit = null
							continue
					var dist = u.world_pos.distance_to(u.target_enemy_unit.world_pos)
					if dist > u.attack_range:
						u.world_pos = u.world_pos.move_toward(u.target_enemy_unit.world_pos, u.speed * speed_mult * delta)
					else:
						if u.def_id == "emp_drone":
							_trigger_emp_blast(u, buildings, tile_px)
							u.hp = 0
							continue
						u.attack_timer += delta
						if u.attack_timer >= u.attack_cooldown:
							u.attack_timer = 0.0
							u.target_enemy_unit.hp -= u.attack_damage
							
							# Target auto-retaliates if idle or moving without current enemy
							if u.target_enemy_unit.hp > 0 and u.target_enemy_unit.target_enemy_unit == null:
								if u.target_enemy_unit.state == UnitState.IDLE or u.target_enemy_unit.state == UnitState.MOVING:
									u.target_enemy_unit.target_enemy_unit = u
									u.target_enemy_unit.state = UnitState.ATTACKING
									
							if u.target_enemy_unit.hp <= 0:
								if local_slot < 0 or u.slot == local_slot:
									_reward_unit_kill(economy)
								var next_target = _find_nearest_enemy_unit(u, units, u.attack_range + 32.0)
								if next_target != null:
									u.target_enemy_unit = next_target
								else:
									u.state = UnitState.IDLE
									u.target_enemy_unit = null
				else:
					u.state = UnitState.IDLE

			UnitState.CONSTRUCTING:
				if u.target_building == null or u.target_building.hp <= 0:
					u.state = UnitState.IDLE
					u.target_building = null
					continue
				if u.target_building.build_progress >= 1.0:
					u.state = UnitState.IDLE
					u.target_building = null
					continue
				var b_center = Vector2((u.target_building.grid_pos.x + u.target_building.size.x * 0.5) * tile_px, (u.target_building.grid_pos.y + u.target_building.size.y * 0.5) * tile_px)
				if u.world_pos.distance_to(b_center) > 36.0:
					u.world_pos = u.world_pos.move_toward(b_center, u.speed * delta)
				else:
					# Construct building (takes ~4 seconds to reach 100%)
					var build_rate = 0.25
					u.target_building.build_progress = minf(1.0, u.target_building.build_progress + delta * build_rate)
					if u.target_building.build_progress >= 1.0:
						u.state = UnitState.IDLE
						u.target_building = null
						
	# Unit-to-unit Collision & Hitbox Separation Loop
	_resolve_unit_collisions(delta, map_data, tile_px)

func _resolve_unit_collisions(delta: float, _map_data: MapData, tile_px: float) -> void:
	var active_units: Array = []
	for u in units:
		if u.hp > 0:
			active_units.append(u)
			
	var count = active_units.size()
	if count < 2: return
	
	# Push overlapping units apart smoothly
	for i in range(count):
		var u1: UnitInstance = active_units[i]
		for j in range(i + 1, count):
			var u2: UnitInstance = active_units[j]
			var min_dist = u1.collision_radius + u2.collision_radius
			var diff = u1.world_pos - u2.world_pos
			var dist = diff.length()
			
			if dist < min_dist:
				var overlap = min_dist - dist
				var push_dir: Vector2
				if dist < 0.001:
					var angle = float(u1.instance_id % 360) * (PI / 180.0)
					push_dir = Vector2(cos(angle), sin(angle))
				else:
					push_dir = diff / dist
					
				var push_amount = overlap * 0.5 * minf(1.0, delta * 15.0)
				u1.world_pos += push_dir * push_amount
				u2.world_pos -= push_dir * push_amount
				
	# Keep units safely within playable map bounds
	if _map_data != null:
		var min_x = tile_px * 1.5
		var min_y = tile_px * 1.5
		var max_x = (_map_data.width - 1.5) * tile_px
		var max_y = (_map_data.height - 1.5) * tile_px
		for u in active_units:
			u.world_pos.x = clampf(u.world_pos.x, min_x, max_x)
			u.world_pos.y = clampf(u.world_pos.y, min_y, max_y)

func _find_nearest_enemy_unit(u: UnitInstance, all_units: Array, max_dist: float) -> UnitInstance:
	var closest: UnitInstance = null
	var min_d = max_dist
	for other in all_units:
		if other != u and other.slot != u.slot and other.hp > 0:
			var d = u.world_pos.distance_to(other.world_pos)
			if d <= min_d:
				min_d = d
				closest = other
	return closest

func _reward_unit_kill(economy: EconomyManager) -> void:
	if economy == null: return
	var stone = randi_range(3, 12)
	var iron = randi_range(4, 15)
	var oil = randi_range(2, 10)
	var redstone = randi_range(1, 6)
	economy.add_resource(MapData.ResourceType.STONE, stone)
	economy.add_resource(MapData.ResourceType.IRON, iron)
	economy.add_resource(MapData.ResourceType.OIL, oil)
	economy.add_resource(MapData.ResourceType.REDSTONE, redstone)
	unit_killed_reward.emit(stone, iron, oil, redstone)

func _trigger_emp_blast(u: UnitInstance, buildings: Array, tile_px: float) -> void:
	var blast_center = u.world_pos
	var blast_radius = 2.5 * tile_px # 2 tiles radius
	for b in buildings:
		if b.slot != u.slot and b.hp > 0:
			var b_center = Vector2((b.grid_pos.x + b.size.x * 0.5) * tile_px, (b.grid_pos.y + b.size.y * 0.5) * tile_px)
			if blast_center.distance_to(b_center) <= blast_radius + b.size.x * tile_px * 0.5:
				b.hp = maxi(1, b.hp - 40)
				b.emp_overload_timer = 15.0 # 15s power overload!
				b.is_powered = false

func _find_nearest_depot(pos: Vector2, player_slot: int, buildings: Array, tile_px: float) -> Vector2:
	var closest_pos = Vector2.ZERO
	var closest_dist = 999999.0
	for b in buildings:
		if b.slot == player_slot and b.hp > 0 and (b.def_id == "hq" or b.def_id == "storage"):
			var b_center = Vector2((b.grid_pos.x + b.size.x * 0.5) * tile_px, (b.grid_pos.y + b.size.y * 0.5) * tile_px)
			var dist = pos.distance_to(b_center)
			if dist < closest_dist:
				closest_dist = dist
				closest_pos = b_center
	return closest_pos

func command_gather(selected_units: Array, res_node: MapData.ResourceNode) -> void:
	for u in selected_units:
		if u.def_id == "worker_drone":
			u.target_resource = res_node
			u.target_enemy_camp = null
			u.target_building = null
			u.state = UnitState.MOVING_TO_RESOURCE

func command_construct(selected_units: Array, target_b: BuildingSystem.BuildingInstance) -> void:
	for u in selected_units:
		if u.def_id == "worker_drone":
			u.target_building = target_b
			u.target_resource = null
			u.target_enemy_camp = null
			u.state = UnitState.CONSTRUCTING

func command_move(selected_units: Array, target_world: Vector2) -> void:
	for u in selected_units:
		u.target_pos = target_world
		u.target_resource = null
		u.target_enemy_camp = null
		u.target_building = null
		u.state = UnitState.MOVING

func command_attack_camp(selected_units: Array, camp_node: MapData.CampNode) -> void:
	for u in selected_units:
		u.target_enemy_camp = camp_node
		u.target_enemy_building = null
		u.target_resource = null
		u.target_building = null
		u.state = UnitState.ATTACKING

func command_attack_building(selected_units: Array, target_b: BuildingSystem.BuildingInstance) -> void:
	for u in selected_units:
		u.target_enemy_building = target_b
		u.target_enemy_camp = null
		u.target_enemy_unit = null
		u.target_resource = null
		u.target_building = null
		u.state = UnitState.ATTACKING

func command_attack_unit(selected_units: Array, target_u: UnitInstance) -> void:
	for u in selected_units:
		u.target_enemy_unit = target_u
		u.target_enemy_building = null
		u.target_enemy_camp = null
		u.target_resource = null
		u.target_building = null
		u.state = UnitState.ATTACKING

func command_move_by_ids(unit_ids: Array, target_world: Vector2) -> void:
	for u_id in unit_ids:
		var u = get_unit_by_id(u_id)
		if u != null:
			u.target_pos = target_world
			u.target_resource = null
			u.target_enemy_camp = null
			u.target_building = null
			u.state = UnitState.MOVING

func command_construct_by_ids(unit_ids: Array, building_id: int, buildings: Array) -> void:
	var target_b: BuildingSystem.BuildingInstance = null
	for b in buildings:
		if b.instance_id == building_id and b.build_progress < 1.0:
			target_b = b
			break
	if target_b == null: return
	for u_id in unit_ids:
		var u = get_unit_by_id(u_id)
		if u != null and u.def_id == "worker_drone":
			u.target_building = target_b
			u.target_resource = null
			u.target_enemy_camp = null
			u.state = UnitState.CONSTRUCTING

func command_gather_by_ids(unit_ids: Array, res_grid_pos: Vector2i, map_data: MapData) -> void:
	var res_node: MapData.ResourceNode = null
	for r in map_data.resources:
		if r.grid_pos == res_grid_pos and r.amount > 0:
			res_node = r
			break
	if res_node == null: return
	for u_id in unit_ids:
		var u = get_unit_by_id(u_id)
		if u != null and u.def_id == "worker_drone":
			u.target_resource = res_node
			u.target_enemy_camp = null
			u.target_building = null
			u.state = UnitState.MOVING_TO_RESOURCE

func command_attack_camp_by_ids(unit_ids: Array, camp_grid_pos: Vector2i, map_data: MapData) -> void:
	var target_camp: MapData.CampNode = null
	for c in map_data.camps:
		if c.grid_pos == camp_grid_pos and c.hp > 0:
			target_camp = c
			break
	if target_camp == null: return
	for u_id in unit_ids:
		var u = get_unit_by_id(u_id)
		if u != null:
			u.target_enemy_camp = target_camp
			u.target_resource = null
			u.target_building = null
			u.state = UnitState.ATTACKING

func get_units_snapshot(for_slot: int) -> Array:
	var snapshot: Array = []
	for u in units:
		if u.slot == for_slot and u.hp > 0:
			snapshot.append({
				"id": u.instance_id,
				"x": u.world_pos.x,
				"y": u.world_pos.y,
				"hp": u.hp,
				"st": int(u.state),
				"ct": u.carried_type,
				"ca": u.carried_amount
			})
	return snapshot

func apply_units_snapshot(slot: int, snapshot: Array) -> void:
	for data in snapshot:
		var u_id = data.get("id", -1)
		var u = get_unit_by_id(u_id)
		if u != null and u.slot == slot:
			var target_p = Vector2(data.get("x", u.world_pos.x), data.get("y", u.world_pos.y))
			if u.world_pos.distance_to(target_p) > 50.0:
				u.world_pos = target_p
			else:
				u.world_pos = u.world_pos.lerp(target_p, 0.4)
			u.hp = data.get("hp", u.hp)
			u.carried_type = data.get("ct", u.carried_type)
			u.carried_amount = data.get("ca", u.carried_amount)

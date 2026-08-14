# RTS Unit Manager (Drones, Mining Automation Loop, Combat Units, Selection)
class_name UnitManager
extends RefCounted

enum UnitState { IDLE, MOVING, MOVING_TO_RESOURCE, MINING, RETURNING_TO_HQ, ATTACKING }

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
	
	# State & Gathering
	var state: UnitState = UnitState.IDLE
	var target_resource: MapData.ResourceNode = null
	var carried_type: int = 0
	var carried_amount: int = 0
	var max_carry: int = 15
	var mining_timer: float = 0.0
	var target_enemy_camp: MapData.CampNode = null
	var sprite_texture: Texture2D = null

var definitions: Dictionary = {}
var units: Array = []
var next_unit_id: int = 1
var textures_cache: Dictionary = {}

func _init() -> void:
	_register_definitions()

func _register_definitions() -> void:
	_add_def("worker_drone", "Dron Roboczy", 80, 130.0, 5, 32.0, 1.0, 10, {"iron": 30, "oil": 10}, "WORKER", "unit_worker")
	_add_def("scout_bot", "Scout Bot", 120, 180.0, 15, 96.0, 0.8, 0, {"iron": 50, "oil": 20}, "SCOUT", "unit_scout")
	_add_def("emp_drone", "Dron EMP", 220, 140.0, 12, 48.0, 1.2, 0, {"iron": 90, "oil": 40, "redstone": 15}, "EMP", "unit_emp")
	_add_def("heavy_bot", "Heavy Bot", 350, 90.0, 40, 64.0, 1.5, 0, {"iron": 120, "oil": 60, "redstone": 10}, "HEAVY", "unit_heavy")
	_add_def("behemoth_bot", "Tytan Przemysłowy", 1500, 60.0, 80, 80.0, 2.0, 0, {"iron": 300, "oil": 150, "redstone": 50}, "SUPER", "unit_behemoth")

func _add_def(
	p_id: String, p_name: String, p_hp: int, p_speed: float,
	p_dmg: int, p_range: float, p_cd: float, p_gather: int,
	p_cost: Dictionary, p_type: String, p_prefix: String
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
	definitions[p_id] = d
	
	# Cache player slot variations (p0..p3)
	for slot_i in range(4):
		var key = "%s_p%d" % [p_id, slot_i]
		var path = "res://public/sprites/units/%s_p%d.png" % [p_prefix, slot_i]
		var tex = UITheme.load_texture_safe(path)
		if tex != null:
			textures_cache[key] = tex

func spawn_unit(def_id: String, slot: int, spawn_pos: Vector2) -> UnitInstance:
	var def = definitions.get(def_id, null)
	if def == null: return null
	
	var u = UnitInstance.new()
	u.instance_id = next_unit_id
	next_unit_id += 1
	u.def_id = def.id
	u.name = def.name
	u.slot = slot
	u.world_pos = spawn_pos
	u.target_pos = spawn_pos
	u.hp = def.max_hp
	u.max_hp = def.max_hp
	u.speed = def.speed
	u.attack_damage = def.attack_damage
	u.attack_range = def.attack_range
	u.attack_cooldown = def.attack_cooldown
	
	var tex_key = "%s_p%d" % [def_id, slot]
	u.sprite_texture = textures_cache.get(tex_key, null)
	
	units.append(u)
	return u

func update_units(delta: float, map_data: MapData, buildings: Array, economy: EconomyManager, tile_px: float) -> void:
	for u in units:
		if u.hp <= 0: continue
		
		match u.state:
			UnitState.IDLE:
				pass
				
			UnitState.MOVING:
				if u.world_pos.distance_to(u.target_pos) > 3.0:
					u.world_pos = u.world_pos.move_toward(u.target_pos, u.speed * delta)
				else:
					u.state = UnitState.IDLE
					
			UnitState.MOVING_TO_RESOURCE:
				if u.target_resource == null:
					u.state = UnitState.IDLE
					continue
				var res_world = Vector2((u.target_resource.grid_pos.x + 0.5) * tile_px, (u.target_resource.grid_pos.y + 0.5) * tile_px)
				if u.world_pos.distance_to(res_world) > 20.0:
					u.world_pos = u.world_pos.move_toward(res_world, u.speed * delta)
				else:
					u.state = UnitState.MINING
					u.mining_timer = 0.0
					
			UnitState.MINING:
				if u.target_resource == null or u.target_resource.amount <= 0:
					u.state = UnitState.RETURNING_TO_HQ
					continue
				u.mining_timer += delta
				if u.mining_timer >= 1.5:
					u.mining_timer = 0.0
					var mined = mini(15, u.target_resource.amount)
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
					# Deposit
					if u.carried_amount > 0:
						economy.add_resource(u.carried_type, u.carried_amount)
						u.carried_amount = 0
					# Return to mining if resource still exists
					if u.target_resource != null and u.target_resource.amount > 0:
						u.state = UnitState.MOVING_TO_RESOURCE
					else:
						u.state = UnitState.IDLE
						
			UnitState.ATTACKING:
				if u.target_enemy_camp == null or u.target_enemy_camp.hp <= 0:
					u.state = UnitState.IDLE
					continue
				var camp_world = Vector2((u.target_enemy_camp.grid_pos.x + 0.5) * tile_px, (u.target_enemy_camp.grid_pos.y + 0.5) * tile_px)
				var dist = u.world_pos.distance_to(camp_world)
				if dist > u.attack_range:
					u.world_pos = u.world_pos.move_toward(camp_world, u.speed * delta)
				else:
					u.attack_timer += delta
					if u.attack_timer >= u.attack_cooldown:
						u.attack_timer = 0.0
						u.target_enemy_camp.hp -= u.attack_damage

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
			u.state = UnitState.MOVING_TO_RESOURCE

func command_move(selected_units: Array, target_world: Vector2) -> void:
	for u in selected_units:
		u.target_pos = target_world
		u.target_resource = null
		u.target_enemy_camp = null
		u.state = UnitState.MOVING

func command_attack_camp(selected_units: Array, camp_node: MapData.CampNode) -> void:
	for u in selected_units:
		u.target_enemy_camp = camp_node
		u.target_resource = null
		u.state = UnitState.ATTACKING

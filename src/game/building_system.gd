# RTS Building Definitions, Grid Placement, Power Radius & Demolition System
class_name BuildingSystem
extends RefCounted

class BuildingDef:
	var id: String
	var name: String
	var category: String
	var max_hp: int
	var size: Vector2i
	var cost: Dictionary
	var power_generation: int
	var power_draw_standby: int
	var power_draw_active: int
	var storage_bonus: int
	var battery_capacity_bonus: int
	var ammo_cost_iron: int
	var wall_mounted: bool
	var sprite_key: String
	var build_time: float

class BuildingInstance:
	var instance_id: int
	var def_id: String
	var name: String
	var slot: int
	var grid_pos: Vector2i
	var size: Vector2i
	var hp: int
	var max_hp: int
	var is_powered: bool = true
	var build_progress: float = 1.0 # 0.0 to 1.0
	var power_generation: int = 0
	var power_draw_standby: int = 0
	var storage_bonus: int = 0
	var battery_capacity_bonus: int = 0
	var sprite_texture: Texture2D = null

var definitions: Dictionary = {}
var building_instances: Array = []
var next_instance_id: int = 1
var textures_cache: Dictionary = {}

const POWER_GRID_HQ_RADIUS: float = 8.0
const POWER_GRID_PYLON_RADIUS: float = 6.5

func _init() -> void:
	_register_definitions()

func _register_definitions() -> void:
	_add_def("hq", "Kwatera Główna", "HQ", 2500, Vector2i(3, 3), {}, 50, 0, 0, 300, 1000, 0, false, "building_hq", 0.0)
	_add_def("stone_mine", "Kopalnia Kamienia", "MINE", 400, Vector2i(1, 1), {"stone": 50, "iron": 20}, 0, 5, 5, 0, 0, 0, false, "building_mine_stone", 4.0)
	_add_def("iron_mine", "Kopalnia Żelaza", "MINE", 400, Vector2i(1, 1), {"stone": 80, "iron": 30}, 0, 8, 8, 0, 0, 0, false, "building_mine_iron", 4.0)
	_add_def("pylon", "Pylon", "PYLON", 200, Vector2i(1, 1), {"stone": 40, "iron": 30}, 0, 1, 1, 0, 0, 0, false, "building_pylon", 2.5)
	_add_def("factory", "Fabryka", "FACTORY", 500, Vector2i(2, 1), {"stone": 150, "iron": 100, "oil": 30}, 0, 10, 20, 0, 0, 0, false, "building_factory", 5.0)
	_add_def("storage", "Magazyn", "STORAGE", 300, Vector2i(1, 1), {"stone": 100, "iron": 50}, 0, 0, 0, 500, 0, 0, false, "building_storage", 4.0)
	_add_def("wall", "Mur", "WALL", 600, Vector2i(1, 1), {"stone": 30}, 0, 0, 0, 0, 0, 0, false, "building_wall", 2.0)
	_add_def("turret", "Wieżyczka", "TURRET", 350, Vector2i(1, 1), {"stone": 80, "iron": 60}, 0, 2, 15, 0, 0, 1, false, "building_turret", 4.0)
	_add_def("wall_turret", "Wieżyczka na Murze", "TURRET", 400, Vector2i(1, 1), {"stone": 60, "iron": 80}, 0, 2, 15, 0, 0, 1, true, "building_turret_wall", 4.0)
	_add_def("power_plant", "Elektrownia", "POWER", 450, Vector2i(2, 1), {"stone": 120, "iron": 80, "oil": 40}, 100, 0, 0, 0, 0, 0, false, "building_power", 5.0)
	_add_def("battery", "Bank Energii", "BATTERY", 300, Vector2i(1, 1), {"stone": 60, "iron": 50, "redstone": 10}, 0, 0, 0, 0, 500, 0, false, "building_battery", 3.5)
	_add_def("lab", "Przetwórnia Danych", "LAB", 400, Vector2i(2, 1), {"stone": 200, "iron": 150, "redstone": 30}, 0, 15, 25, 0, 0, 0, false, "building_lab", 6.0)

func _add_def(
	p_id: String, p_name: String, p_cat: String, p_hp: int, p_sz: Vector2i,
	p_cost: Dictionary, p_gen: int, p_stby: int, p_act: int,
	p_stor: int, p_bat: int, p_ammo: int, p_wall: bool, p_sprite: String, p_time: float
) -> void:
	var d = BuildingDef.new()
	d.id = p_id
	d.name = p_name
	d.category = p_cat
	d.max_hp = p_hp
	d.size = p_sz
	d.cost = p_cost
	d.power_generation = p_gen
	d.power_draw_standby = p_stby
	d.power_draw_active = p_act
	d.storage_bonus = p_stor
	d.battery_capacity_bonus = p_bat
	d.ammo_cost_iron = p_ammo
	d.wall_mounted = p_wall
	d.sprite_key = p_sprite
	d.build_time = p_time
	definitions[p_id] = d
	
	# Pre-cache texture
	var path = "res://public/sprites/buildings/%s.png" % p_sprite
	var tex = UITheme.load_texture_safe(path)
	if tex != null:
		textures_cache[p_id] = tex

func get_def(id: String) -> BuildingDef:
	return definitions.get(id, null)

func is_position_valid_for_building(
	def_id: String,
	grid_pos: Vector2i,
	player_slot: int,
	map_data: MapData
) -> Dictionary:
	var def = get_def(def_id)
	if def == null:
		return {"valid": false, "reason": "Nieznany budynek"}
		
	# 1. Bounds check (must be inside 1-tile non-buildable border)
	for dy in range(def.size.y):
		for dx in range(def.size.x):
			var check_pos = grid_pos + Vector2i(dx, dy)
			if not map_data.is_playable_tile(check_pos.x, check_pos.y):
				return {"valid": false, "reason": "Poza grywalnym obszarem mapy"}
				
	# 2. Overlap check with other buildings
	for b in building_instances:
		var r1 = Rect2i(grid_pos, def.size)
		var r2 = Rect2i(b.grid_pos, b.size)
		if r1.intersects(r2):
			# Allow wall turret to be placed directly on a Wall
			if def.wall_mounted and b.def_id == "wall" and b.slot == player_slot:
				continue
			return {"valid": false, "reason": "Pole jest już zajęte przez inną strukturę"}
			
	# 3. Overlap check with Boss area & Camps
	for camp in map_data.camps:
		var camp_rect = Rect2i(camp.grid_pos - Vector2i(1, 1), Vector2i(3, 3))
		if Rect2i(grid_pos, def.size).intersects(camp_rect):
			return {"valid": false, "reason": "Nie można budować w strefie neutralnej/bossa"}
			
	# 4. Power Grid Radius Check (Must be within HQ or Pylon range of the player)
	var in_power_range = false
	var build_center = Vector2(grid_pos.x + def.size.x * 0.5, grid_pos.y + def.size.y * 0.5)
	
	for b in building_instances:
		if b.slot != player_slot or b.hp <= 0:
			continue
		var b_center = Vector2(b.grid_pos.x + b.size.x * 0.5, b.grid_pos.y + b.size.y * 0.5)
		var dist = build_center.distance_to(b_center)
		
		if b.def_id == "hq" and dist <= POWER_GRID_HQ_RADIUS:
			in_power_range = true
			break
		elif b.def_id == "pylon" and dist <= POWER_GRID_PYLON_RADIUS:
			in_power_range = true
			break
			
	if not in_power_range:
		return {"valid": false, "reason": "Brak zasilania sieci — postaw Pylon w pobliżu!"}
		
	return {"valid": true, "reason": "OK"}

func place_building(
	def_id: String,
	grid_pos: Vector2i,
	player_slot: int,
	map_data: MapData,
	economy: EconomyManager
) -> BuildingInstance:
	var def = get_def(def_id)
	if def == null: return null
	
	var validation = is_position_valid_for_building(def_id, grid_pos, player_slot, map_data)
	if not validation.valid:
		return null
		
	if not economy.spend_resources(def.cost):
		return null
		
	# Replace wall if wall turret
	if def.wall_mounted:
		for i in range(building_instances.size() - 1, -1, -1):
			var b = building_instances[i]
			if b.def_id == "wall" and b.grid_pos == grid_pos:
				building_instances.remove_at(i)
				break
				
	var inst = BuildingInstance.new()
	inst.instance_id = next_instance_id
	next_instance_id += 1
	inst.def_id = def.id
	inst.name = def.name
	inst.slot = player_slot
	inst.grid_pos = grid_pos
	inst.size = def.size
	inst.hp = def.max_hp
	inst.max_hp = def.max_hp
	inst.power_generation = def.power_generation
	inst.power_draw_standby = def.power_draw_standby
	inst.storage_bonus = def.storage_bonus
	inst.battery_capacity_bonus = def.battery_capacity_bonus
	inst.sprite_texture = textures_cache.get(def.id, null)
	inst.build_progress = 1.0
	
	building_instances.append(inst)
	return inst

func demolish_building_at(grid_pos: Vector2i, player_slot: int, economy: EconomyManager) -> bool:
	for i in range(building_instances.size() - 1, -1, -1):
		var b = building_instances[i]
		var b_rect = Rect2i(b.grid_pos, b.size)
		if b_rect.has_point(grid_pos) and b.slot == player_slot:
			if b.def_id == "hq":
				return false # Cannot demolish HQ!
			var def = get_def(b.def_id)
			if def != null:
				economy.refund_resources(def.cost, 0.5)
			building_instances.remove_at(i)
			return true
	return false

func get_building_at(grid_pos: Vector2i) -> BuildingInstance:
	for b in building_instances:
		if Rect2i(b.grid_pos, b.size).has_point(grid_pos):
			return b
	return null

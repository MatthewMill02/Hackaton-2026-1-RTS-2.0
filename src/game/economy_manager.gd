# RTS Economy Manager (Resources, Storage Limits, Power Grid kW/kJ)
class_name EconomyManager
extends RefCounted

signal economy_updated(stone: int, iron: int, oil: int, redstone: int, max_storage: int, net_power: int, stored_kj: int)
signal blackout_started()
signal blackout_ended()

var stone: int = 200
var iron: int = 150
var oil: int = 50
var redstone: int = 20

var base_storage: int = 300
var max_storage: int = 300

# Power Grid (kW / kJ)
var power_production: int = 50
var power_consumption: int = 0
var battery_capacity_kj: int = 1000
var stored_energy_kj: float = 1000.0
var is_blackout: bool = false

# Mining timer accumulator
var mining_accumulator: float = 0.0

func _init() -> void:
	pass

func reset_for_match(starting_storage: int = 300) -> void:
	stone = 200
	iron = 150
	oil = 50
	redstone = 20
	base_storage = starting_storage
	max_storage = starting_storage
	power_production = 50
	power_consumption = 0
	battery_capacity_kj = 1000
	stored_energy_kj = 1000.0
	is_blackout = false

func enable_creative_mode() -> void:
	stone = 10000000
	iron = 10000000
	oil = 10000000
	redstone = 10000000
	base_storage = 100000000
	max_storage = 100000000
	power_production = 100000
	battery_capacity_kj = 10000000
	stored_energy_kj = 10000000.0
	is_blackout = false

func can_afford(cost: Dictionary) -> bool:
	var req_stone = cost.get("stone", 0)
	var req_iron = cost.get("iron", 0)
	var req_oil = cost.get("oil", 0)
	var req_red = cost.get("redstone", 0)
	return stone >= req_stone and iron >= req_iron and oil >= req_oil and redstone >= req_red

func spend_resources(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	stone -= cost.get("stone", 0)
	iron -= cost.get("iron", 0)
	oil -= cost.get("oil", 0)
	redstone -= cost.get("redstone", 0)
	_emit_update()
	return true

func add_resource(type: int, amount: int) -> int:
	var actual_added = 0
	match type:
		MapData.ResourceType.STONE:
			actual_added = mini(amount, max_storage - stone)
			stone += actual_added
		MapData.ResourceType.IRON:
			actual_added = mini(amount, max_storage - iron)
			iron += actual_added
		MapData.ResourceType.OIL:
			actual_added = mini(amount, max_storage - oil)
			oil += actual_added
		MapData.ResourceType.REDSTONE:
			actual_added = mini(amount, max_storage - redstone)
			redstone += actual_added
	_emit_update()
	return actual_added

func refund_resources(cost: Dictionary, ratio: float = 0.5) -> void:
	var ret_stone = int(cost.get("stone", 0) * ratio)
	var ret_iron = int(cost.get("iron", 0) * ratio)
	var ret_oil = int(cost.get("oil", 0) * ratio)
	var ret_red = int(cost.get("redstone", 0) * ratio)
	
	stone = mini(stone + ret_stone, max_storage)
	iron = mini(iron + ret_iron, max_storage)
	oil = mini(oil + ret_oil, max_storage)
	redstone = mini(redstone + ret_red, max_storage)
	_emit_update()

func update_grid(delta: float, buildings: Array, local_slot: int = -1, research: ResearchSystem = null) -> void:
	# Recalculate Power & Storage strictly for the local player's operational buildings
	var prod = 50 # Base HQ power
	if research != null:
		prod += int(research.hq_power_bonus)
		
	var cons = 0
	var extra_storage = 0
	var extra_battery = 1000 # Base HQ battery
	
	var active_mines: Array = []
	
	for b in buildings:
		if b.build_progress < 1.0 or b.hp <= 0 or b.emp_overload_timer > 0.0:
			continue
		if local_slot >= 0 and b.slot != local_slot:
			continue
			
		prod += b.power_generation
		cons += b.power_draw_standby
		extra_storage += b.storage_bonus
		extra_battery += b.battery_capacity_bonus
		
		if b.def_id in ["stone_mine", "iron_mine", "oil_pump", "redstone_mine"] and not is_blackout:
			active_mines.append(b)
			
	power_production = prod
	power_consumption = cons
	max_storage = base_storage + extra_storage
	var bat_mult = research.battery_capacity_mult if research != null else 1.0
	battery_capacity_kj = int(extra_battery * bat_mult)
	
	var net_power = power_production - power_consumption
	
	if net_power >= 0:
		# Charging batteries
		stored_energy_kj = minf(stored_energy_kj + net_power * delta, float(battery_capacity_kj))
		if is_blackout:
			is_blackout = false
			blackout_ended.emit()
	else:
		# Discharging batteries
		var deficit = absf(net_power) * delta
		stored_energy_kj -= deficit
		if stored_energy_kj <= 0.0:
			stored_energy_kj = 0.0
			if not is_blackout:
				is_blackout = true
				blackout_started.emit()
				
	# Passive mining ticks (every 1.0 second)
	mining_accumulator += delta
	if mining_accumulator >= 1.0:
		mining_accumulator = 0.0
		var mine_mult = research.mining_multiplier if research != null else 1.0
		for mine in active_mines:
			if mine.def_id == "stone_mine":
				add_resource(MapData.ResourceType.STONE, int(8 * mine_mult))
			elif mine.def_id == "iron_mine":
				add_resource(MapData.ResourceType.IRON, int(6 * mine_mult))
			elif mine.def_id == "oil_pump":
				add_resource(MapData.ResourceType.OIL, int(4 * mine_mult))
			elif mine.def_id == "redstone_mine":
				add_resource(MapData.ResourceType.REDSTONE, int(3 * mine_mult))
				
	_emit_update()

func _emit_update() -> void:
	economy_updated.emit(
		stone, iron, oil, redstone,
		max_storage,
		power_production - power_consumption,
		int(stored_energy_kj)
	)

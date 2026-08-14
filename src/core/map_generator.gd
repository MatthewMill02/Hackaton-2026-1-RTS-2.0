# Procedural RTS Map Generator (50x50 + 1-tile border)
class_name MapGenerator
extends RefCounted

static func generate_map(seed_val: int = 0) -> MapData:
	if seed_val == 0:
		seed_val = randi()
		
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	var map = MapData.new()
	map.seed_value = seed_val
	map.width = MapData.MAP_SIZE
	map.height = MapData.MAP_SIZE
	
	# 1. Spawn 4 Corner Base Centers
	var b1_pos = Vector2i(5, 5)
	var b2_pos = Vector2i(map.width - 6, 5)
	var b3_pos = Vector2i(5, map.height - 6)
	var b4_pos = Vector2i(map.width - 6, map.height - 6)
	
	map.bases.clear()
	map.bases.append(MapData.BaseSpawn.new(0, b1_pos))
	map.bases.append(MapData.BaseSpawn.new(1, b2_pos))
	map.bases.append(MapData.BaseSpawn.new(2, b3_pos))
	map.bases.append(MapData.BaseSpawn.new(3, b4_pos))
	
	var occupied: Dictionary = {}
	
	# Mark base areas as occupied
	for b in map.bases:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				occupied[b.grid_pos + Vector2i(dx, dy)] = true
				
	# 2. Central Boss Area
	var center = Vector2i(map.width / 2, map.height / 2) # (25, 25)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			occupied[center + Vector2i(dx, dy)] = true
	map.camps.append(MapData.CampNode.new(MapData.CampType.BOSS, center, 3000))
	
	# 3. Neutral Camps (4 around center)
	var camp_positions = [
		Vector2i(17, 17),
		Vector2i(32, 17),
		Vector2i(17, 32),
		Vector2i(32, 32)
	]
	for c_pos in camp_positions:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				occupied[c_pos + Vector2i(dx, dy)] = true
		map.camps.append(MapData.CampNode.new(MapData.CampType.CAMP, c_pos, 800))
		
	# 4. Generate Resources for Each Base
	for b in map.bases:
		var base_pos = Vector2(b.grid_pos.x, b.grid_pos.y)
		var center_vec = Vector2(center.x, center.y)
		var to_center_dir = (center_vec - base_pos).normalized()
		
		# A) Near Base: 1 to 4 Iron deposits & 1 to 4 Stone deposits
		var iron_count = rng.randi_range(1, 4)
		for _i in range(iron_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.IRON, b.grid_pos, 4, 8, 1400)
			
		var stone_count = rng.randi_range(1, 4)
		for _s in range(stone_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.STONE, b.grid_pos, 4, 8, 1800)
			
		# B) Mid-range towards center: 1 to 4 Redstone deposits & 1 to 4 Oil deposits
		var redstone_count = rng.randi_range(1, 4)
		for _r in range(redstone_count):
			var mid_target = base_pos + to_center_dir * rng.randf_range(9.0, 16.0)
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.REDSTONE, Vector2i(int(mid_target.x), int(mid_target.y)), 1, 4, 600)
			
		var oil_count = rng.randi_range(1, 4)
		for _o in range(oil_count):
			var mid_target = base_pos + to_center_dir * rng.randf_range(10.0, 18.0)
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.OIL, Vector2i(int(mid_target.x), int(mid_target.y)), 1, 4, 1000)

	return map

static func _place_resource_cluster(
	map: MapData,
	rng: RandomNumberGenerator,
	occupied: Dictionary,
	res_type: MapData.ResourceType,
	origin: Vector2i,
	min_dist: int,
	max_dist: int,
	base_amount: int
) -> void:
	for attempt in range(16):
		var angle = rng.randf_range(0, TAU)
		var dist = rng.randf_range(min_dist, max_dist)
		var gx = int(round(origin.x + cos(angle) * dist))
		var gy = int(round(origin.y + sin(angle) * dist))
		var pos = Vector2i(gx, gy)
		
		if map.is_playable_tile(gx, gy) and not occupied.has(pos):
			occupied[pos] = true
			var amount = base_amount + rng.randi_range(-200, 300)
			map.resources.append(MapData.ResourceNode.new(res_type, pos, amount))
			break

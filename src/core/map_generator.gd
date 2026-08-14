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
	
	# 1. Spawn 4 Corner Base Centers (HQ top-left corners)
	var b1_pos = Vector2i(5, 5)
	var b2_pos = Vector2i(map.width - 8, 5)
	var b3_pos = Vector2i(5, map.height - 8)
	var b4_pos = Vector2i(map.width - 8, map.height - 8)
	
	map.bases.clear()
	map.bases.append(MapData.BaseSpawn.new(0, b1_pos))
	map.bases.append(MapData.BaseSpawn.new(1, b2_pos))
	map.bases.append(MapData.BaseSpawn.new(2, b3_pos))
	map.bases.append(MapData.BaseSpawn.new(3, b4_pos))
	
	var occupied: Dictionary = {}
	
	# Mark base HQ (3x3) and immediate clearance as occupied
	for b in map.bases:
		for dy in range(-1, 4):
			for dx in range(-1, 4):
				occupied[b.grid_pos + Vector2i(dx, dy)] = true
				
	# 2. Central Boss Area (5x5 occupied core)
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
		var base_center = Vector2(b.grid_pos.x + 1.0, b.grid_pos.y + 1.0)
		var center_vec = Vector2(center.x, center.y)
		var to_center_dir = (center_vec - base_center).normalized()
		
		# A) Near Base (Max 5 tiles from base center, outside HQ)
		# Stone
		if rng.randf() <= ResourceConfig.BASE_STONE_SPAWN_RATE:
			var stone_count = rng.randi_range(ResourceConfig.BASE_STONE_MIN_COUNT, ResourceConfig.BASE_STONE_MAX_COUNT)
			for _s in range(stone_count):
				_place_resource_cluster(map, rng, occupied, MapData.ResourceType.STONE, Vector2i(int(base_center.x), int(base_center.y)), ResourceConfig.BASE_NEAR_MIN_DIST, ResourceConfig.BASE_NEAR_MAX_DIST, ResourceConfig.BASE_STONE_AMOUNT)
		
		# Iron
		if rng.randf() <= ResourceConfig.BASE_IRON_SPAWN_RATE:
			var iron_count = rng.randi_range(ResourceConfig.BASE_IRON_MIN_COUNT, ResourceConfig.BASE_IRON_MAX_COUNT)
			for _i in range(iron_count):
				_place_resource_cluster(map, rng, occupied, MapData.ResourceType.IRON, Vector2i(int(base_center.x), int(base_center.y)), ResourceConfig.BASE_NEAR_MIN_DIST, ResourceConfig.BASE_NEAR_MAX_DIST, ResourceConfig.BASE_IRON_AMOUNT)
			
		# B) Mid-range towards center (Redstone & Oil)
		# Redstone
		if rng.randf() <= ResourceConfig.MID_REDSTONE_SPAWN_RATE:
			var redstone_count = rng.randi_range(ResourceConfig.MID_REDSTONE_MIN_COUNT, ResourceConfig.MID_REDSTONE_MAX_COUNT)
			for _r in range(redstone_count):
				var mid_target = base_center + to_center_dir * rng.randf_range(ResourceConfig.MID_REDSTONE_MIN_DIST, ResourceConfig.MID_REDSTONE_MAX_DIST)
				_place_resource_cluster(map, rng, occupied, MapData.ResourceType.REDSTONE, Vector2i(int(mid_target.x), int(mid_target.y)), 1.0, 3.0, ResourceConfig.MID_REDSTONE_AMOUNT)
		
		# Oil
		if rng.randf() <= ResourceConfig.MID_OIL_SPAWN_RATE:
			var oil_count = rng.randi_range(ResourceConfig.MID_OIL_MIN_COUNT, ResourceConfig.MID_OIL_MAX_COUNT)
			for _o in range(oil_count):
				var mid_target = base_center + to_center_dir * rng.randf_range(ResourceConfig.MID_OIL_MIN_DIST, ResourceConfig.MID_OIL_MAX_DIST)
				_place_resource_cluster(map, rng, occupied, MapData.ResourceType.OIL, Vector2i(int(mid_target.x), int(mid_target.y)), 1.0, 3.0, ResourceConfig.MID_OIL_AMOUNT)

	# 5. Generate Boss Area Perimeter Resources (All 4 Types)
	if rng.randf() <= ResourceConfig.BOSS_STONE_SPAWN_RATE:
		var b_stone_count = rng.randi_range(ResourceConfig.BOSS_STONE_MIN_COUNT, ResourceConfig.BOSS_STONE_MAX_COUNT)
		for _bs in range(b_stone_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.STONE, center, ResourceConfig.BOSS_RESOURCE_MIN_DIST, ResourceConfig.BOSS_RESOURCE_MAX_DIST, ResourceConfig.BOSS_STONE_AMOUNT)

	if rng.randf() <= ResourceConfig.BOSS_IRON_SPAWN_RATE:
		var b_iron_count = rng.randi_range(ResourceConfig.BOSS_IRON_MIN_COUNT, ResourceConfig.BOSS_IRON_MAX_COUNT)
		for _bi in range(b_iron_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.IRON, center, ResourceConfig.BOSS_RESOURCE_MIN_DIST, ResourceConfig.BOSS_RESOURCE_MAX_DIST, ResourceConfig.BOSS_IRON_AMOUNT)

	if rng.randf() <= ResourceConfig.BOSS_OIL_SPAWN_RATE:
		var b_oil_count = rng.randi_range(ResourceConfig.BOSS_OIL_MIN_COUNT, ResourceConfig.BOSS_OIL_MAX_COUNT)
		for _bo in range(b_oil_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.OIL, center, ResourceConfig.BOSS_RESOURCE_MIN_DIST, ResourceConfig.BOSS_RESOURCE_MAX_DIST, ResourceConfig.BOSS_OIL_AMOUNT)

	if rng.randf() <= ResourceConfig.BOSS_REDSTONE_SPAWN_RATE:
		var b_redstone_count = rng.randi_range(ResourceConfig.BOSS_REDSTONE_MIN_COUNT, ResourceConfig.BOSS_REDSTONE_MAX_COUNT)
		for _br in range(b_redstone_count):
			_place_resource_cluster(map, rng, occupied, MapData.ResourceType.REDSTONE, center, ResourceConfig.BOSS_RESOURCE_MIN_DIST, ResourceConfig.BOSS_RESOURCE_MAX_DIST, ResourceConfig.BOSS_REDSTONE_AMOUNT)

	return map

static func _place_resource_cluster(
	map: MapData,
	rng: RandomNumberGenerator,
	occupied: Dictionary,
	res_type: MapData.ResourceType,
	origin: Vector2i,
	min_dist: float,
	max_dist: float,
	base_amount: int
) -> void:
	for _attempt in range(24):
		var angle = rng.randf_range(0, TAU)
		var dist = rng.randf_range(min_dist, max_dist)
		var gx = int(round(origin.x + cos(angle) * dist))
		var gy = int(round(origin.y + sin(angle) * dist))
		var pos = Vector2i(gx, gy)
		
		if map.is_playable_tile(gx, gy) and not occupied.has(pos):
			occupied[pos] = true
			var amount = base_amount + rng.randi_range(-ResourceConfig.AMOUNT_VARIANCE, ResourceConfig.AMOUNT_VARIANCE)
			map.resources.append(MapData.ResourceNode.new(res_type, pos, amount))
			break

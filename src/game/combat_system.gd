# RTS Combat System (Turret Defense 3 Tiles @ 0.25s, Unit & Building Targeting, Resource Drops, Camps & Boss)
class_name CombatSystem
extends RefCounted

signal camp_destroyed(camp_node: MapData.CampNode, killer_slot: int)
signal turret_fired(from_world: Vector2, to_world: Vector2, is_wall_turret: bool)
signal unit_killed_reward(stone: int, iron: int, oil: int, redstone: int)

class ActiveBeam:
	var from_pos: Vector2
	var to_pos: Vector2
	var duration: float = 0.12
	var color: Color

var active_beams: Array = []
var turret_cooldowns: Dictionary = {} # building_instance_id -> float

func update_combat(
	delta: float,
	buildings: Array,
	units: Array,
	map_data: MapData,
	economy: EconomyManager,
	tile_px: float,
	local_slot: int = -1,
	research: ResearchSystem = null
) -> void:
	# 1. Update visual laser beams
	for i in range(active_beams.size() - 1, -1, -1):
		active_beams[i].duration -= delta
		if active_beams[i].duration <= 0:
			active_beams.remove_at(i)
			
	# 2. Update Turret Defense Logic (3 Tiles Range = 144px, 1 shot / 0.25s)
	const TURRET_RANGE_TILES: float = 3.0
	const TURRET_COOLDOWN_SEC: float = 0.25
	
	for b in buildings:
		if b.hp <= 0 or b.build_progress < 1.0:
			continue
		if local_slot >= 0 and b.slot != local_slot:
			continue
		if b.def_id != "turret" and b.def_id != "wall_turret":
			continue
			
		var b_id = b.instance_id
		var cd = turret_cooldowns.get(b_id, 0.0)
		if cd > 0:
			turret_cooldowns[b_id] = cd - delta
			continue
			
		# Check power & iron ammo in local economy
		if economy.is_blackout or economy.iron < 1:
			continue
			
		var turret_world = Vector2((b.grid_pos.x + 0.5) * tile_px, (b.grid_pos.y + 0.5) * tile_px)
		var fire_range_px = TURRET_RANGE_TILES * tile_px * (research.turret_range_mult if research else 1.0)
		var fire_range_sq = fire_range_px * fire_range_px
		
		# --- TARGET PRIORITY 1: Enemy Units in 3 tiles ---
		var target_unit: UnitManager.UnitInstance = null
		var closest_unit_dist_sq = fire_range_sq
		for u in units:
			if u.slot != b.slot and u.hp > 0:
				var dist_sq = turret_world.distance_squared_to(u.world_pos)
				if dist_sq <= closest_unit_dist_sq:
					closest_unit_dist_sq = dist_sq
					target_unit = u
					
		if target_unit != null:
			economy.iron -= 1 # 1 Iron ammo
			var base_dmg = 18.0 if b.def_id == "turret" else 28.0
			var dmg = int(base_dmg * (research.turret_damage_mult if research else 1.0))
			target_unit.hp -= dmg
			turret_cooldowns[b_id] = TURRET_COOLDOWN_SEC
			
			spawn_beam(turret_world, target_unit.world_pos, b.def_id == "wall_turret")
			turret_fired.emit(turret_world, target_unit.world_pos, b.def_id == "wall_turret")
			
			if target_unit.hp <= 0:
				_reward_unit_kill(economy)
			continue
			
		# --- TARGET PRIORITY 2: Enemy Buildings in 3 tiles ---
		var target_enemy_b: BuildingSystem.BuildingInstance = null
		var closest_b_dist_sq = fire_range_sq
		for other_b in buildings:
			if other_b.slot != b.slot and other_b.hp > 0:
				var b_center = Vector2((other_b.grid_pos.x + other_b.size.x * 0.5) * tile_px, (other_b.grid_pos.y + other_b.size.y * 0.5) * tile_px)
				var dist_sq = turret_world.distance_squared_to(b_center)
				if dist_sq <= closest_b_dist_sq:
					closest_b_dist_sq = dist_sq
					target_enemy_b = other_b
					
		if target_enemy_b != null:
			economy.iron -= 1
			var base_dmg = 15.0 if b.def_id == "turret" else 24.0
			var dmg = int(base_dmg * (research.turret_damage_mult if research else 1.0))
			target_enemy_b.hp -= dmg
			turret_cooldowns[b_id] = TURRET_COOLDOWN_SEC
			
			var target_pos = Vector2((target_enemy_b.grid_pos.x + target_enemy_b.size.x * 0.5) * tile_px, (target_enemy_b.grid_pos.y + target_enemy_b.size.y * 0.5) * tile_px)
			spawn_beam(turret_world, target_pos, b.def_id == "wall_turret")
			turret_fired.emit(turret_world, target_pos, b.def_id == "wall_turret")
			continue
			
		# --- TARGET PRIORITY 3: Neutral Camps & Boss in 3 tiles ---
		var target_camp: MapData.CampNode = null
		var closest_camp_dist_sq = fire_range_sq
		for camp in map_data.camps:
			if camp.hp <= 0: continue
			var camp_world = Vector2((camp.grid_pos.x + 0.5) * tile_px, (camp.grid_pos.y + 0.5) * tile_px)
			var dist_sq = turret_world.distance_squared_to(camp_world)
			if dist_sq <= closest_camp_dist_sq:
				closest_camp_dist_sq = dist_sq
				target_camp = camp
				
		if target_camp != null:
			economy.iron -= 1
			var camp_world = Vector2((target_camp.grid_pos.x + 0.5) * tile_px, (target_camp.grid_pos.y + 0.5) * tile_px)
			var base_dmg = 18.0 if b.def_id == "turret" else 28.0
			var dmg = int(base_dmg * (research.turret_damage_mult if research else 1.0))
			target_camp.hp -= dmg
			turret_cooldowns[b_id] = TURRET_COOLDOWN_SEC
			
			spawn_beam(turret_world, camp_world, b.def_id == "wall_turret")
			turret_fired.emit(turret_world, camp_world, b.def_id == "wall_turret")
			
			if target_camp.hp <= 0:
				_on_camp_defeated(target_camp, b.slot, economy, research)

	# 3. Check Camps Defeated by Units
	for camp in map_data.camps:
		if camp.hp <= 0 and camp.max_hp > 0:
			_on_camp_defeated(camp, local_slot, economy, research)

func spawn_beam(from_pos: Vector2, to_pos: Vector2, is_wall_turret: bool) -> void:
	var beam = ActiveBeam.new()
	beam.from_pos = from_pos
	beam.to_pos = to_pos
	beam.color = UITheme.COLOR_ACCENT_ORANGE if is_wall_turret else UITheme.COLOR_ACCENT_CYAN
	active_beams.append(beam)

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

func _on_camp_defeated(camp: MapData.CampNode, killer_slot: int, economy: EconomyManager, research: ResearchSystem = null) -> void:
	camp.max_hp = 0 # Mark as processed
	if economy != null:
		if camp.type == MapData.CampType.BOSS:
			economy.add_resource(MapData.ResourceType.STONE, 300)
			economy.add_resource(MapData.ResourceType.IRON, 300)
			economy.add_resource(MapData.ResourceType.OIL, 150)
			economy.add_resource(MapData.ResourceType.REDSTONE, 80)
			if research != null:
				research.drop_boss_card()
		else:
			economy.add_resource(MapData.ResourceType.STONE, 100)
			economy.add_resource(MapData.ResourceType.IRON, 100)
			economy.add_resource(MapData.ResourceType.OIL, 50)
			if research != null:
				research.drop_camp_card()
	camp_destroyed.emit(camp, killer_slot)

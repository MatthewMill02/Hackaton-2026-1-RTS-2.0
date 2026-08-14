# RTS Combat System (Turret Defense, Ammo Consumption, Laser Tracers, Neutral Camps & Boss)
class_name CombatSystem
extends RefCounted

signal camp_destroyed(camp_node: MapData.CampNode, killer_slot: int)
signal turret_fired(from_world: Vector2, to_world: Vector2, is_wall_turret: bool)

class ActiveBeam:
	var from_pos: Vector2
	var to_pos: Vector2
	var duration: float = 0.15
	var color: Color

var active_beams: Array = []
var turret_cooldowns: Dictionary = {} # building_instance_id -> float

func update_combat(
	delta: float,
	buildings: Array,
	units: Array,
	map_data: MapData,
	economy: EconomyManager,
	tile_px: float
) -> void:
	# 1. Update visual laser beams
	for i in range(active_beams.size() - 1, -1, -1):
		active_beams[i].duration -= delta
		if active_beams[i].duration <= 0:
			active_beams.remove_at(i)
			
	# 2. Update Turret Defense Logic
	for b in buildings:
		if b.hp <= 0 or b.build_progress < 1.0:
			continue
		if b.def_id != "turret" and b.def_id != "wall_turret":
			continue
			
		var b_id = b.instance_id
		var cd = turret_cooldowns.get(b_id, 0.0)
		if cd > 0:
			turret_cooldowns[b_id] = cd - delta
			continue
			
		# Check power & iron ammo
		if economy.is_blackout or economy.iron < 1:
			continue
			
		var turret_world = Vector2((b.grid_pos.x + 0.5) * tile_px, (b.grid_pos.y + 0.5) * tile_px)
		var fire_range_px = 6.0 * tile_px
		
		# Find target in range (Enemy camps or Boss)
		var target_camp: MapData.CampNode = null
		var closest_dist = fire_range_px
		for camp in map_data.camps:
			if camp.hp <= 0: continue
			var camp_world = Vector2((camp.grid_pos.x + 0.5) * tile_px, (camp.grid_pos.y + 0.5) * tile_px)
			var dist = turret_world.distance_to(camp_world)
			if dist <= closest_dist:
				closest_dist = dist
				target_camp = camp
				
		if target_camp != null:
			# Fire turret!
			economy.iron -= 1 # Consume 1 iron ammo
			var camp_world = Vector2((target_camp.grid_pos.x + 0.5) * tile_px, (target_camp.grid_pos.y + 0.5) * tile_px)
			var dmg = 35 if b.def_id == "turret" else 50 # Wall turret deals higher damage
			target_camp.hp -= dmg
			turret_cooldowns[b_id] = 0.8
			
			# Create visual beam
			var beam = ActiveBeam.new()
			beam.from_pos = turret_world
			beam.to_pos = camp_world
			beam.color = UITheme.COLOR_ACCENT_CYAN if b.def_id == "turret" else UITheme.COLOR_ACCENT_ORANGE
			active_beams.append(beam)
			turret_fired.emit(turret_world, camp_world, b.def_id == "wall_turret")
			
			if target_camp.hp <= 0:
				_on_camp_defeated(target_camp, b.slot, economy)

	# 3. Check Camps Defeated by Units
	for camp in map_data.camps:
		if camp.hp <= 0 and camp.max_hp > 0:
			_on_camp_defeated(camp, 0, economy)

func _on_camp_defeated(camp: MapData.CampNode, killer_slot: int, economy: EconomyManager) -> void:
	camp.max_hp = 0 # Mark as processed
	if camp.type == MapData.CampType.BOSS:
		economy.add_resource(MapData.ResourceType.STONE, 300)
		economy.add_resource(MapData.ResourceType.IRON, 300)
		economy.add_resource(MapData.ResourceType.OIL, 150)
		economy.add_resource(MapData.ResourceType.REDSTONE, 80)
	else:
		economy.add_resource(MapData.ResourceType.STONE, 100)
		economy.add_resource(MapData.ResourceType.IRON, 100)
		economy.add_resource(MapData.ResourceType.OIL, 50)
	camp_destroyed.emit(camp, killer_slot)

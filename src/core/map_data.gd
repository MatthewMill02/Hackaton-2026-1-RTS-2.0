# Data structure for Procedural RTS Map
class_name MapData
extends RefCounted

enum ResourceType { STONE, IRON, OIL, REDSTONE }
enum CampType { CAMP, BOSS }

const MAP_SIZE: int = 50 # 50x50 grid
const BORDER_SIZE: int = 1 # 1-tile non-buildable border

class ResourceNode:
	var type: ResourceType
	var grid_pos: Vector2i
	var amount: int
	var max_amount: int
	
	func _init(p_type: ResourceType, p_pos: Vector2i, p_amount: int) -> void:
		type = p_type
		grid_pos = p_pos
		amount = p_amount
		max_amount = p_amount
		
	func to_dict() -> Dictionary:
		return {
			"type": type,
			"x": grid_pos.x,
			"y": grid_pos.y,
			"amount": amount
		}
		
	static func from_dict(d: Dictionary) -> ResourceNode:
		return ResourceNode.new(d.get("type", ResourceType.STONE), Vector2i(d.get("x", 0), d.get("y", 0)), d.get("amount", 1000))

class CampNode:
	var type: CampType
	var grid_pos: Vector2i
	var hp: int
	var max_hp: int
	
	func _init(p_type: CampType, p_pos: Vector2i, p_hp: int) -> void:
		type = p_type
		grid_pos = p_pos
		hp = p_hp
		max_hp = p_hp
		
	func to_dict() -> Dictionary:
		return {
			"type": type,
			"x": grid_pos.x,
			"y": grid_pos.y,
			"hp": hp
		}
		
	static func from_dict(d: Dictionary) -> CampNode:
		return CampNode.new(d.get("type", CampType.CAMP), Vector2i(d.get("x", 0), d.get("y", 0)), d.get("hp", 800))

class BaseSpawn:
	var slot: int
	var grid_pos: Vector2i
	var base_rect: Rect2i # 5x5 base area
	
	func _init(p_slot: int, p_pos: Vector2i) -> void:
		slot = p_slot
		grid_pos = p_pos
		base_rect = Rect2i(p_pos - Vector2i(2, 2), Vector2i(5, 5))

var seed_value: int = 0
var width: int = MAP_SIZE
var bases: Array = []
var resources: Array = []
var camps: Array = []

func is_in_bounds(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < width and gy < height

func is_playable_tile(gx: int, gy: int) -> bool:
	# Inside non-buildable 1-tile border
	return gx >= BORDER_SIZE and gy >= BORDER_SIZE and gx < (width - BORDER_SIZE) and gy < (height - BORDER_SIZE)

func to_dict() -> Dictionary:
	var res_arr: Array = []
	for r in resources: res_arr.append(r.to_dict())
	var camp_arr: Array = []
	for c in camps: camp_arr.append(c.to_dict())
	return {
		"seed": seed_value,
		"width": width,
		"height": height,
		"resources": res_arr,
		"camps": camp_arr
	}

static func from_dict(d: Dictionary) -> MapData:
	var md = MapData.new()
	md.seed_value = d.get("seed", 0)
	md.width = d.get("width", MAP_SIZE)
	md.height = d.get("height", MAP_SIZE)
	
	# Re-create bases
	md.bases.clear()
	md.bases.append(BaseSpawn.new(0, Vector2i(5, 5)))
	md.bases.append(BaseSpawn.new(1, Vector2i(md.width - 6, 5)))
	md.bases.append(BaseSpawn.new(2, Vector2i(5, md.height - 6)))
	md.bases.append(BaseSpawn.new(3, Vector2i(md.width - 6, md.height - 6)))
	
	md.resources.clear()
	for r in d.get("resources", []):
		md.resources.append(ResourceNode.from_dict(r))
		
	md.camps.clear()
	for c in d.get("camps", []):
		md.camps.append(CampNode.from_dict(c))
		
	return md

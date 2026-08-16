# RTS Research Cards & Tech Database System
class_name ResearchSystem
extends RefCounted

signal card_obtained(card_item: CardItem)
signal card_revealed(card_item: CardItem)
signal card_sold(card_item: CardItem)

enum CardRarity { COMMON, RARE, LEGENDARY }

class CardDef:
	var id: String
	var name: String
	var rarity: CardRarity
	var emoji: String
	var description: String
	var effect_type: String
	var effect_val: float

class CardItem:
	var item_id: int
	var def: CardDef
	var is_revealed: bool = false
	var refund_cost: Dictionary = {}

const COMMON_CRAFT_COST: Dictionary = {"iron": 80, "oil": 40, "redstone": 15}

var all_definitions: Dictionary = {}
var common_pool: Array[CardDef] = []
var rare_pool: Array[CardDef] = []
var legendary_pool: Array[CardDef] = []

var player_cards: Array[CardItem] = []
var next_item_id: int = 1

# Active Passive Multipliers & Modifiers
var mining_multiplier: float = 1.0
var battery_capacity_mult: float = 1.0
var structure_hp_mult: float = 1.0
var unit_speed_mult: float = 1.0
var turret_damage_mult: float = 1.0
var turret_range_mult: float = 1.0
var hq_power_bonus: float = 0.0
var structure_regen_pct: float = 0.0
var pylon_range_mult: float = 1.0
var emp_duration_bonus: float = 0.0

func _init() -> void:
	_register_all_cards()
	_init_deck_pools()

func _register_all_cards() -> void:
	# --- TIER 1: KARTY ZWYKŁE (COMMON) ---
	_add_card("card_deep_drilling", "Głębokie Wiercenia", CardRarity.COMMON, "⛏️", "Kopalnie wydobywają +100% surowców.", "MINING_RATE_BUFF", 2.0)
	_add_card("card_supercapacitors", "Superkondensatory", CardRarity.COMMON, "🔋", "Pojemność Banków Energii wzrasta o +200%.", "BATTERY_CAPACITY_BUFF", 3.0)
	_add_card("card_titanium_fibers", "Włókna Tytanowe", CardRarity.COMMON, "🛡️", "Mury i Pylony zyskują +100% HP.", "STRUCTURE_HP_BUFF", 2.0)
	_add_card("card_assembly_line", "Linia Taśmowa", CardRarity.COMMON, "⚙️", "Czas produkcji jednostek w fabryce skrócony o 50%.", "PRODUCTION_SPEED_BUFF", 0.5)
	_add_card("card_high_pressure_hydraulics", "Hydraulika Wysokociśnieniowa", CardRarity.COMMON, "🏎️", "Jednostki bojowe poruszają się o +35% szybciej.", "UNIT_SPEED_BUFF", 1.35)
	_add_card("card_long_range_relay", "Nadajnik Dalekiego Zasięgu", CardRarity.COMMON, "📡", "Zasięg i odległość łączenia Pylonów wzrasta o +50%.", "PYLON_RANGE_BUFF", 1.5)
	_add_card("card_military_recycling", "Recykling Wojskowy", CardRarity.COMMON, "♻️", "Zniszczone budynki zwracają 40% surowców.", "DEATH_REFUND_BUFF", 0.4)
	_add_card("card_fast_logistics", "Szybka Logistyka", CardRarity.COMMON, "🚀", "Drony budowlane poruszają się o +100% szybciej.", "DRONE_SPEED_BUFF", 2.0)
	_add_card("card_geoscanner", "Geoskaner", CardRarity.COMMON, "🛰️", "Odkrywa złoża Ropy i Czerwienitu na mapie.", "REVEAL_NODES", 1.0)
	_add_card("card_self_repair_protocol", "Autonaprawa Struktur", CardRarity.COMMON, "🔧", "Zasilane budynki regenerują 2% max HP na sekundę.", "STRUCTURE_REGEN", 0.02)

	# --- TIER 2: KARTY RZADKIE (RARE - DROPY Z OBOZÓW) ---
	_add_card("card_magnetic_accelerator", "Młynek Magnetyczny", CardRarity.RARE, "⚡", "Wieżyczki strzelają 2x szybciej i zadają +50% obrażeń.", "TURRET_BURST_BUFF", 1.5)
	_add_card("card_overload_detonation", "Protokół Detonacji", CardRarity.RARE, "💥", "Zniszczone Pylony i Mury wybuchają zadając obrażenia.", "DEATH_EXPLOSION", 150.0)
	_add_card("card_kinetic_shielding", "Tarcza Kinetyczna", CardRarity.RARE, "🛡️", "Ciężkie jednostki i Terminus zyskują +40% odporności.", "DAMAGE_REDUCTION", 0.4)
	_add_card("card_pulse_amplification", "Impuls EMP", CardRarity.RARE, "⚡", "Drony EMP paraliżują wrogie budynki na 20 sekund.", "EMP_DURATION_BUFF", 5.0)
	_add_card("card_laser_targeter", "Celownik Laserowy", CardRarity.RARE, "🎯", "Wieże Laserowe zyskują +60% zasięgu ognia.", "LASER_RANGE_BUFF", 1.6)
	_add_card("card_reverse_engineering", "Inżynieria Rewersyjna", CardRarity.RARE, "🔬", "Niszczenie jednostek wroga daje Czerwienit.", "KILL_REWARD_REDSTONE", 1.0)
	_add_card("card_wireless_grid", "Bezprzewodowy Przesył", CardRarity.RARE, "🌐", "Budynki działają bez Pylonów w promieniu bazy.", "WIRELESS_POWER", 1.0)
	_add_card("card_orbital_drop", "Satelita Zasobów", CardRarity.RARE, "📦", "Pasywny zrzut surowców do bazy.", "PASSIVE_DROP", 1.0)
	_add_card("card_armor_piercing_rounds", "Amunicja Przebijająca", CardRarity.RARE, "💥", "Wieżyczki i Scoutboty zadają +50% obrażeń budynkom.", "STRUCTURE_DMG_BUFF", 1.5)
	_add_card("card_giga_assembly", "Giga-Fabryka", CardRarity.RARE, "🏭", "Jednostki produkowane w fabryce mają +20% HP.", "UNIT_HP_BUFF", 1.2)
	_add_card("card_energy_leach", "Absorpcja Energii", CardRarity.RARE, "⚡", "Niszczenie wrogów natychmiastowo ładuje Akumulatory.", "ENERGY_LEACH", 1.0)
	_add_card("card_redstone_alchemy", "Synteza Czerwienitu", CardRarity.RARE, "🔴", "Pasywna generacja +2 Czerwienitu na sekundę.", "REDSTONE_SYNTHESIS", 2.0)

	# --- TIER 3: KARTY LEGENDARNE (LEGENDARY - DROPY Z BOSSA) ---
	_add_card("card_cyber_sabotage", "Wirus Trojan", CardRarity.LEGENDARY, "👾", "Paraliż wrogich systemów obronnych.", "HACK_BUILDINGS", 1.0)
	_add_card("card_industrial_behemoth", "Tytan Przemysłowy", CardRarity.LEGENDARY, "🤖", "Odblokowuje produkcję gigantycznego Mecha Tytana.", "SUPER_UNIT", 1.0)
	_add_card("card_overclock_protocol", "Giga-Storm Protocol", CardRarity.LEGENDARY, "🔥", "3x szybkostrzelność wszystkich systemów obrony.", "SUPER_OVERCLOCK", 3.0)
	_add_card("card_grid_subversion", "Dominacja Sieci", CardRarity.LEGENDARY, "⚡", "Przejęcie zasilania wrogich struktur.", "GRID_DOMINATION", 1.0)
	_add_card("card_hq_bastion", "Pole Siłowe HQ", CardRarity.LEGENDARY, "🏰", "Kwatera Główna jest niezniszczalna dopóki masz Prąd.", "HQ_INVULNERABLE", 1.0)
	_add_card("card_antimatter_core", "Reaktor Antymaterii", CardRarity.LEGENDARY, "⚛️", "Elektrownie produkują +500% Prądu (+500 kW).", "SUPER_POWER", 500.0)

func _add_card(p_id: String, p_name: String, p_rarity: CardRarity, p_emoji: String, p_desc: String, p_eff: String, p_val: float) -> void:
	var c = CardDef.new()
	c.id = p_id
	c.name = p_name
	c.rarity = p_rarity
	c.emoji = p_emoji
	c.description = p_desc
	c.effect_type = p_eff
	c.effect_val = p_val
	all_definitions[p_id] = c

func _init_deck_pools() -> void:
	common_pool.clear()
	rare_pool.clear()
	legendary_pool.clear()
	
	for c in all_definitions.values():
		match c.rarity:
			CardRarity.COMMON:
				# 2 copies each in common pool (Deck 20)
				common_pool.append(c)
				common_pool.append(c)
			CardRarity.RARE:
				rare_pool.append(c)
			CardRarity.LEGENDARY:
				legendary_pool.append(c)
				
	common_pool.shuffle()
	rare_pool.shuffle()
	legendary_pool.shuffle()

func craft_common_card(economy: EconomyManager) -> CardItem:
	if common_pool.is_empty():
		return null
		
	if not economy.can_afford(COMMON_CRAFT_COST):
		return null
		
	if not economy.spend_resources(COMMON_CRAFT_COST):
		return null
		
	var def = common_pool.pop_back()
	var item = CardItem.new()
	item.item_id = next_item_id
	next_item_id += 1
	item.def = def
	item.is_revealed = false
	item.refund_cost = COMMON_CRAFT_COST.duplicate()
	
	player_cards.append(item)
	card_obtained.emit(item)
	return item

func drop_camp_card() -> CardItem:
	if rare_pool.is_empty():
		return null
	var def = rare_pool.pop_back()
	var item = CardItem.new()
	item.item_id = next_item_id
	next_item_id += 1
	item.def = def
	item.is_revealed = false
	item.refund_cost = {"iron": 120, "oil": 60, "redstone": 30}
	
	player_cards.append(item)
	card_obtained.emit(item)
	return item

func drop_boss_card() -> CardItem:
	if legendary_pool.is_empty():
		return null
	var def = legendary_pool.pop_back()
	var item = CardItem.new()
	item.item_id = next_item_id
	next_item_id += 1
	item.def = def
	item.is_revealed = false
	item.refund_cost = {"iron": 250, "oil": 150, "redstone": 80}
	
	player_cards.append(item)
	card_obtained.emit(item)
	return item

func reveal_card(item_id: int) -> bool:
	for item in player_cards:
		if item.item_id == item_id:
			if not item.is_revealed:
				item.is_revealed = true
				_recalculate_bonuses()
				card_revealed.emit(item)
				return true
	return false

func sell_covered_card(item_id: int, economy: EconomyManager) -> bool:
	for i in range(player_cards.size()):
		var item = player_cards[i]
		if item.item_id == item_id:
			if not item.is_revealed:
				# 100% cost refund!
				economy.add_resource(MapData.ResourceType.IRON, item.refund_cost.get("iron", 0))
				economy.add_resource(MapData.ResourceType.OIL, item.refund_cost.get("oil", 0))
				economy.add_resource(MapData.ResourceType.REDSTONE, item.refund_cost.get("redstone", 0))
				player_cards.remove_at(i)
				card_sold.emit(item)
				return true
	return false

func _recalculate_bonuses() -> void:
	# Reset multipliers to base
	mining_multiplier = 1.0
	battery_capacity_mult = 1.0
	structure_hp_mult = 1.0
	unit_speed_mult = 1.0
	turret_damage_mult = 1.0
	turret_range_mult = 1.0
	hq_power_bonus = 0.0
	structure_regen_pct = 0.0
	pylon_range_mult = 1.0
	emp_duration_bonus = 0.0
	
	for item in player_cards:
		if not item.is_revealed: continue
		var def = item.def
		match def.effect_type:
			"MINING_RATE_BUFF":
				mining_multiplier *= def.effect_val
			"BATTERY_CAPACITY_BUFF":
				battery_capacity_mult *= def.effect_val
			"STRUCTURE_HP_BUFF":
				structure_hp_mult *= def.effect_val
			"UNIT_SPEED_BUFF", "DRONE_SPEED_BUFF":
				unit_speed_mult *= def.effect_val
			"TURRET_BURST_BUFF":
				turret_damage_mult *= def.effect_val
			"LASER_RANGE_BUFF":
				turret_range_mult *= def.effect_val
			"SUPER_POWER":
				hq_power_bonus += def.effect_val
			"STRUCTURE_REGEN":
				structure_regen_pct += def.effect_val
			"PYLON_RANGE_BUFF":
				pylon_range_mult *= def.effect_val
			"EMP_DURATION_BUFF":
				emp_duration_bonus += def.effect_val

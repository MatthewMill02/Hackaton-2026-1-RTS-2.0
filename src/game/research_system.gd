# RTS Research Cards & Tech Database System
class_name ResearchSystem
extends RefCounted

signal card_unlocked(card_def: CardDef, player_slot: int)

enum CardRarity { COMMON, RARE, LEGENDARY }

class CardDef:
	var id: String
	var name: String
	var rarity: CardRarity
	var description: String
	var effect_type: String
	var effect_val: float

var all_cards: Array[CardDef] = []
var deck_pool: Array[CardDef] = []
var unlocked_cards: Array[CardDef] = []

# Modifiers
var mining_multiplier: float = 1.0
var battery_capacity_mult: float = 1.0
var structure_hp_mult: float = 1.0
var unit_speed_mult: float = 1.0

func _init() -> void:
	_register_cards()
	_reset_deck()

func _register_cards() -> void:
	_add_card("card_deep_drilling", "Głębokie Wiercenia", CardRarity.COMMON, "Kopalnie wydobywają +50% surowców.", "MINING_BUFF", 1.5)
	_add_card("card_supercapacitors", "Superkondensatory", CardRarity.COMMON, "Pojemność Banków Energii wzrasta o +100%.", "BATTERY_BUFF", 2.0)
	_add_card("card_titanium_fibers", "Włókna Tytanowe", CardRarity.COMMON, "Mury i Pylony zyskują +50% HP.", "STRUCTURE_HP", 1.5)
	_add_card("card_assembly_line", "Linia Taśmowa", CardRarity.COMMON, "Szybkość poruszania się dronów +25%.", "UNIT_SPEED", 1.25)
	_add_card("card_high_pressure", "Hydraulika Wysokociśnieniowa", CardRarity.RARE, "Jednostki poruszają się o +40% szybciej.", "UNIT_SPEED", 1.4)
	_add_card("card_laser_turrets", "Kondensatory Plazmowe", CardRarity.RARE, "Wieżyczki zadają +50% obrażeń.", "TURRET_BUFF", 1.5)
	_add_card("card_giga_core", "Rdzeń Antymaterii", CardRarity.LEGENDARY, "Kwatera Główna produkuje +150 kW energii.", "HQ_POWER", 150.0)

func _add_card(p_id: String, p_name: String, p_rarity: CardRarity, p_desc: String, p_eff: String, p_val: float) -> void:
	var c = CardDef.new()
	c.id = p_id
	c.name = p_name
	c.rarity = p_rarity
	c.description = p_desc
	c.effect_type = p_eff
	c.effect_val = p_val
	all_cards.append(c)

func _reset_deck() -> void:
	deck_pool = all_cards.duplicate()
	deck_pool.shuffle()

func draw_random_card(player_slot: int = 0) -> CardDef:
	if deck_pool.is_empty():
		_reset_deck()
	if deck_pool.is_empty():
		return null
		
	var drawn = deck_pool.pop_back()
	unlocked_cards.append(drawn)
	_apply_card_effect(drawn)
	card_unlocked.emit(drawn, player_slot)
	return drawn

func _apply_card_effect(card: CardDef) -> void:
	match card.effect_type:
		"MINING_BUFF":
			mining_multiplier *= card.effect_val
		"BATTERY_BUFF":
			battery_capacity_mult *= card.effect_val
		"STRUCTURE_HP":
			structure_hp_mult *= card.effect_val
		"UNIT_SPEED":
			unit_speed_mult *= card.effect_val

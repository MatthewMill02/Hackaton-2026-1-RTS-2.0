# Global game state definitions and constants
class_name GameState
extends RefCounted

enum GamePhase {
	MENU,
	LOBBY,
	COUNTDOWN,
	PLAYING,
	GAME_OVER
}

const MAX_PLAYERS: int = 4
const DEFAULT_PORT: int = 7777

const SLOT_COLORS: Array[Color] = [
	Color(0.18, 0.77, 1.0, 1.0),   # Slot 0: Cyan
	Color(1.0, 0.35, 0.35, 1.0),   # Slot 1: Neon Crimson
	Color(0.25, 0.88, 0.45, 1.0),  # Slot 2: Emerald
	Color(1.0, 0.82, 0.2, 1.0)     # Slot 3: Amber
]

const SLOT_NAMES: Array[String] = [
	"Baza Północno-Zachodnia (Niebieska)",
	"Baza Północno-Wschodnia (Czerwona)",
	"Baza Południowo-Zachodnia (Zielona)",
	"Baza Południowo-Wschodnia (Żółta)"
]

# Resource Spawning & Generation Configuration
class_name ResourceConfig
extends RefCounted

# ==============================================================================
# 1. NEAR BASE RESOURCES (Stone & Iron)
# Max distance is 5 tiles from base, strictly outside the HQ (3x3) area
# ==============================================================================
const BASE_NEAR_MIN_DIST: float = 2.5
const BASE_NEAR_MAX_DIST: float = 5.0

const BASE_STONE_MIN_COUNT: int = 1
const BASE_STONE_MAX_COUNT: int = 4
const BASE_STONE_AMOUNT: int = 1800
const BASE_STONE_SPAWN_RATE: float = 1.0 # Probability weight

const BASE_IRON_MIN_COUNT: int = 1
const BASE_IRON_MAX_COUNT: int = 4
const BASE_IRON_AMOUNT: int = 1400
const BASE_IRON_SPAWN_RATE: float = 1.0 # Probability weight

# ==============================================================================
# 2. MID-RANGE BASE RESOURCES (Redstone & Oil)
# Between base and map center
# ==============================================================================
const MID_REDSTONE_MIN_DIST: float = 9.0
const MID_REDSTONE_MAX_DIST: float = 15.0
const MID_REDSTONE_MIN_COUNT: int = 1
const MID_REDSTONE_MAX_COUNT: int = 3
const MID_REDSTONE_AMOUNT: int = 600
const MID_REDSTONE_SPAWN_RATE: float = 0.8

const MID_OIL_MIN_DIST: float = 10.0
const MID_OIL_MAX_DIST: float = 17.0
const MID_OIL_MIN_COUNT: int = 1
const MID_OIL_MAX_COUNT: int = 3
const MID_OIL_AMOUNT: int = 1000
const MID_OIL_SPAWN_RATE: float = 0.8

# ==============================================================================
# 3. BOSS PERIMETER RESOURCES (All 4 Types: Stone, Iron, Oil, Redstone)
# Distributed around boss center (outside 5x5 boss core)
# ==============================================================================
const BOSS_RESOURCE_MIN_DIST: float = 4.5
const BOSS_RESOURCE_MAX_DIST: float = 9.5

const BOSS_STONE_MIN_COUNT: int = 1
const BOSS_STONE_MAX_COUNT: int = 3
const BOSS_STONE_AMOUNT: int = 2200
const BOSS_STONE_SPAWN_RATE: float = 1.0

const BOSS_IRON_MIN_COUNT: int = 1
const BOSS_IRON_MAX_COUNT: int = 3
const BOSS_IRON_AMOUNT: int = 1800
const BOSS_IRON_SPAWN_RATE: float = 1.0

const BOSS_OIL_MIN_COUNT: int = 1
const BOSS_OIL_MAX_COUNT: int = 3
const BOSS_OIL_AMOUNT: int = 1500
const BOSS_OIL_SPAWN_RATE: float = 1.0

const BOSS_REDSTONE_MIN_COUNT: int = 1
const BOSS_REDSTONE_MAX_COUNT: int = 3
const BOSS_REDSTONE_AMOUNT: int = 900
const BOSS_REDSTONE_SPAWN_RATE: float = 1.0

# Variance in node amount (+/- range)
const AMOUNT_VARIANCE: int = 200

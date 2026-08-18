extends Node
## Persistent player state + all upgrade-tunable values.
## The upgrade tree calls buy_upgrade between rounds; gameplay code must
## read stats from here instead of hard-coding numbers. Stats are always
## recomputed from BASE_STATS + upgrade_levels (idempotent, no drift).

signal currency_changed(amount: int)
signal upgrades_changed

const BASE_STATS := {
	"fire_interval": 1.0,
	"damage": 2,
	"target_size": Vector2(24, 24),
	"enemy_size": Vector2(24, 24),
	"round_duration": 30.0,
	"spawn_interval": 2.0,
	"enemy_max_hp": 10,
	"initial_enemies": 10,
	"currency_per_kill": 1,
}

const DAMAGE_PER_LEVEL := 2
const SIZE_PER_LEVEL := 0.25
const FIRE_INTERVALS := [1.0, 0.8, 0.6, 0.4]

var currency: int = 0
var stats := BASE_STATS.duplicate()
var upgrade_levels := {"dmg": 0, "size": 0, "speed": 0}


func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)


func buy_upgrade(id: String) -> bool:
	var level: int = upgrade_levels[id]
	var costs: Array = Upgrades.DEFS[id].costs
	if level >= costs.size():
		return false
	var cost: int = costs[level]
	if currency < cost:
		return false
	currency -= cost
	upgrade_levels[id] = level + 1
	_recompute_stats()
	currency_changed.emit(currency)
	upgrades_changed.emit()
	return true


func _recompute_stats() -> void:
	stats = BASE_STATS.duplicate()
	stats.damage = BASE_STATS.damage + DAMAGE_PER_LEVEL * upgrade_levels.dmg
	stats.target_size = BASE_STATS.target_size * (1.0 + SIZE_PER_LEVEL * upgrade_levels.size)
	stats.fire_interval = FIRE_INTERVALS[upgrade_levels.speed]

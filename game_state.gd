extends Node
## Persistent player state + all upgrade-tunable values.
## The upgrade tree calls buy_upgrade between rounds; gameplay code must
## read stats from here instead of hard-coding numbers. Stats are always
## recomputed from BASE_STATS + upgrade_levels (idempotent, no drift).
## Also tracks round number and escalation state (session-only, like currency).

signal currency_changed(amount: int)
signal upgrades_changed

const BASE_STATS := {
	"fire_interval": 1.0,
	"damage": 2,
	"target_size": Vector2(24, 24),
	"round_duration": 30.0,
	"spawn_interval": 2.0,
	"initial_enemies": 10,
	"currency_per_kill": 1,
}

const DAMAGE_PER_LEVEL := 2
const SIZE_PER_LEVEL := 0.25
const FIRE_INTERVALS := [1.0, 0.8, 0.6, 0.4]

const FRENZY_CHANCE := 0.3
const TOUGHNESS_HP_STEP := 0.2
const FRENZY_SPEED_MULT := 1.5
const ESCALATION_START_ROUND := 6

var currency: int = 0
var stats := BASE_STATS.duplicate()
var upgrade_levels := {"dmg": 0, "size": 0, "speed": 0}

var round_number: int = 0
var toughness_level: int = 0
var frenzy: bool = false


func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)


func advance_round() -> void:
	round_number += 1
	frenzy = false
	if round_number >= ESCALATION_START_ROUND:
		if randf() < FRENZY_CHANCE:
			frenzy = true
		else:
			toughness_level += 1


func hp_mult() -> float:
	return 1.0 + TOUGHNESS_HP_STEP * toughness_level


func speed_mult() -> float:
	return FRENZY_SPEED_MULT if frenzy else 1.0


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

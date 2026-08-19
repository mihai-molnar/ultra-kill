class_name EnemyTypes
## Static per-enemy-type tunables (mirrors the Upgrades.DEFS pattern).
## "coins" is the number of drop sprites a kill pops out; each drop is
## worth GameState.stats.currency_per_kill. The boss lives outside DEFS
## so the random spawn pool is just "unlocked DEFS entries" — the boss
## spawns once at the start of boss rounds, never from the timer.

const DEFS := {
	"rabbit": {
		"sprite": "res://sprites/enemy.png",
		"size": Vector2(24, 24),
		"max_hp": 10,
		"coins": 3,
		"unlock_round": 1,
		"speed_scale": 1.0,
	},
	"pig": {
		"sprite": "res://sprites/pig.png",
		"size": Vector2(24, 24),
		"max_hp": 16,
		"coins": 4,
		"unlock_round": 2,
		"speed_scale": 1.0,
	},
	"giant_rabbit": {
		"sprite": "res://sprites/giant_rabbit.png",
		"size": Vector2(32, 32),
		"max_hp": 20,
		"coins": 5,
		"unlock_round": 3,
		"speed_scale": 1.0,
	},
	"giant_pig": {
		"sprite": "res://sprites/giant_pig.png",
		"size": Vector2(32, 32),
		"max_hp": 26,
		"coins": 6,
		"unlock_round": 4,
		"speed_scale": 1.0,
	},
}

const BOSS := {
	"sprite": "res://sprites/boss_rabbit.png",
	"size": Vector2(48, 48),
	"max_hp": 100,
	"coins": 50,
	"speed_scale": 0.5,
}


static func unlocked(round_number: int) -> Array:
	var pool := []
	for def in DEFS.values():
		if def.unlock_round <= round_number:
			pool.append(def)
	return pool

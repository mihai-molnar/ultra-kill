extends Node
## Persistent player state + all upgrade-tunable values.
## The future level-up screen mutates `stats` between rounds; gameplay
## code must read from here instead of hard-coding numbers.

signal currency_changed(amount: int)

var currency: int = 0

var stats := {
	"fire_interval": 1.0,
	"damage": 2,
	"target_size": Vector2(100, 100),
	"round_duration": 30.0,
	"spawn_interval": 2.0,
	"enemy_max_hp": 10,
	"initial_enemies": 10,
	"currency_per_kill": 1,
}


func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)

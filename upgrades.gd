class_name Upgrades
## Static upgrade definitions. costs.size() is an upgrade's max level and
## its pip count, so deeper upgrades later are just longer arrays. Effect
## formulas live in GameState._recompute_stats.

const DEFS := {
	"dmg": {
		"name": "DMG",
		"description": "+2 damage per level",
		"icon": "res://sprites/icon_dmg.png",
		"costs": [5, 7, 10],
	},
	"size": {
		"name": "SIZE",
		"description": "+25% target area per level",
		"icon": "res://sprites/icon_size.png",
		"costs": [10, 20, 30],
	},
	"speed": {
		"name": "SPEED",
		"description": "Fires faster each level",
		"icon": "res://sprites/icon_speed.png",
		"costs": [7, 25, 35],
	},
}

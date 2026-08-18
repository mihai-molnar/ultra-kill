class_name CurrencyDrop
extends Node2D
## Placeholder currency: small gold rectangle dropped where an enemy died.
## Collected (self-frees) when the targeting area passes over it.

const SIZE := Vector2(14, 14)
const GOLD := Color(1.0, 0.84, 0.2)

var target: TargetingArea


func _process(_delta: float) -> void:
	if target and target.get_rect().intersects(get_rect()):
		GameState.add_currency(GameState.stats.currency_per_kill)
		queue_free()


func get_rect() -> Rect2:
	return Rect2(global_position - SIZE / 2.0, SIZE)


func _draw() -> void:
	draw_rect(Rect2(-SIZE / 2.0, SIZE), GOLD, true)

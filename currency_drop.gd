class_name CurrencyDrop
extends Node2D
## Placeholder currency: small peach sprite that pops out of a dying enemy.
## Collected (self-frees) when the targeting area passes over it, but only
## after the pop finishes — otherwise a kill under the reticle would
## auto-collect the drop the frame it spawns.

const SPRITE := preload("res://sprites/drop.png")
const SIZE := Vector2(4, 4)
const POP_DURATION := 0.2

var target: TargetingArea
var _collectable := false


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = SPRITE
	add_child(sprite)


func pop_to(dest: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", dest, POP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: _collectable = true)


func _process(_delta: float) -> void:
	if _collectable and target and target.get_rect().intersects(get_rect()):
		GameState.add_currency(GameState.stats.currency_per_kill)
		queue_free()


func get_rect() -> Rect2:
	return Rect2(global_position - SIZE / 2.0, SIZE)

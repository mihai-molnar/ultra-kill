class_name CurrencyDrop
extends Node2D
## Placeholder currency: small peach sprite that pops out of a dying enemy.
## Collected (self-frees) when the targeting area passes over it, but only
## after the pop finishes — otherwise a kill under the reticle would
## auto-collect the drop the frame it spawns.

const SPRITE := preload("res://sprites/drop.png")
const SIZE := Vector2(4, 4)
const POP_DURATION := 0.2
const COLLECT_DURATION := 0.12
const COLLECT_SCALE := Vector2(2.5, 2.5)

var target: TargetingArea
var _collectable := false


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = SPRITE
	add_child(sprite)


func pop_to(dest: Vector2) -> void:
	scale = Vector2.ZERO
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position", dest, POP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, POP_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void: _collectable = true)


func _process(_delta: float) -> void:
	if _collectable and target and target.get_rect().intersects(get_rect()):
		_collect()


func _collect() -> void:
	_collectable = false
	GameState.add_currency(GameState.stats.currency_per_kill)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", COLLECT_SCALE, COLLECT_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, COLLECT_DURATION)
	tween.chain().tween_callback(queue_free)


func get_rect() -> Rect2:
	return Rect2(global_position - SIZE / 2.0, SIZE)

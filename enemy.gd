class_name Enemy
extends Node2D
## Wandering enemy rectangle. Same size as the targeting area (for now).
## HP is drawn as a dark-red bar (left-anchored) over a light-red base:
## fully dark = full HP, fully light = dead.

signal died(at_position: Vector2)

const DARK_RED := Color(0.55, 0.08, 0.08)
const LIGHT_RED := Color(0.94, 0.55, 0.55)
const SPEED_MIN := 80.0
const SPEED_MAX := 160.0
const DIRECTION_TIME_MIN := 1.0
const DIRECTION_TIME_MAX := 3.0

var max_hp: int
var hp: int
var _velocity := Vector2.ZERO
var _direction_time := 0.0


func _ready() -> void:
	max_hp = GameState.stats.enemy_max_hp
	hp = max_hp
	_roll_direction()


func _process(delta: float) -> void:
	_direction_time -= delta
	if _direction_time <= 0.0:
		_roll_direction()
	global_position += _velocity * delta
	_bounce_off_edges()
	queue_redraw()


func get_rect() -> Rect2:
	var size: Vector2 = GameState.stats.target_size
	return Rect2(global_position - size / 2.0, size)


func on_target_fired(target_rect: Rect2) -> void:
	if target_rect.intersects(get_rect()):
		take_damage(GameState.stats.damage)


func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	queue_redraw()
	if hp == 0:
		died.emit(global_position)
		queue_free()


func _roll_direction() -> void:
	_velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(SPEED_MIN, SPEED_MAX)
	_direction_time = randf_range(DIRECTION_TIME_MIN, DIRECTION_TIME_MAX)


func _bounce_off_edges() -> void:
	var half: Vector2 = GameState.stats.target_size / 2.0
	var bounds := get_viewport_rect().size
	if global_position.x < half.x or global_position.x > bounds.x - half.x:
		_velocity.x = -_velocity.x
	if global_position.y < half.y or global_position.y > bounds.y - half.y:
		_velocity.y = -_velocity.y
	global_position.x = clampf(global_position.x, half.x, bounds.x - half.x)
	global_position.y = clampf(global_position.y, half.y, bounds.y - half.y)


func _draw() -> void:
	var size: Vector2 = GameState.stats.target_size
	draw_rect(Rect2(-size / 2.0, size), LIGHT_RED, true)
	var hp_width := size.x * float(hp) / float(max_hp)
	draw_rect(Rect2(-size / 2.0, Vector2(hp_width, size.y)), DARK_RED, true)

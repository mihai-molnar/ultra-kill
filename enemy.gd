class_name Enemy
extends Node2D
## Wandering enemy sprite. Same size as the targeting area (for now).
## Damage is shown by the enemy_damage shader: the purple body erodes to
## peach left to right (fully purple = full HP, fully peach = dead).

signal died(at_position: Vector2)

const SPRITE := preload("res://sprites/enemy.png")
const DAMAGE_SHADER := preload("res://shaders/enemy_damage.gdshader")
const SPEED_MIN := 20.0
const SPEED_MAX := 40.0
const DIRECTION_TIME_MIN := 1.0
const DIRECTION_TIME_MAX := 3.0
const HIT_FLASH_TIME := 0.06
const HIT_SQUASH := Vector2(1.25, 0.75)
const HIT_SQUASH_TIME := 0.12

var max_hp: int
var hp: int
var _velocity := Vector2.ZERO
var _direction_time := 0.0
var _sprite: Sprite2D
var _hit_tween: Tween


func _ready() -> void:
	max_hp = GameState.stats.enemy_max_hp
	hp = max_hp
	_sprite = Sprite2D.new()
	_sprite.texture = SPRITE
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	mat.set_shader_parameter("hp_ratio", 1.0)
	_sprite.material = mat
	add_child(_sprite)
	_roll_direction()


func _process(delta: float) -> void:
	_direction_time -= delta
	if _direction_time <= 0.0:
		_roll_direction()
	global_position += _velocity * delta
	_bounce_off_edges()


func get_rect() -> Rect2:
	var size: Vector2 = GameState.stats.enemy_size
	return Rect2(global_position - size / 2.0, size)


func on_target_fired(target_rect: Rect2) -> void:
	if target_rect.intersects(get_rect()):
		take_damage(GameState.stats.damage)


func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	_sprite.material.set_shader_parameter("hp_ratio", float(hp) / float(max_hp))
	if hp == 0:
		died.emit(global_position)
		queue_free()
		return
	_play_hit_feedback()


func _play_hit_feedback() -> void:
	_sprite.material.set_shader_parameter("flash", 1.0)
	_sprite.scale = HIT_SQUASH
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(_sprite, "scale", Vector2.ONE, HIT_SQUASH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.parallel().tween_callback(_end_flash).set_delay(HIT_FLASH_TIME)


func _end_flash() -> void:
	_sprite.material.set_shader_parameter("flash", 0.0)


func _roll_direction() -> void:
	_velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(SPEED_MIN, SPEED_MAX)
	_direction_time = randf_range(DIRECTION_TIME_MIN, DIRECTION_TIME_MAX)


func _bounce_off_edges() -> void:
	var half: Vector2 = GameState.stats.enemy_size / 2.0
	var bounds := get_viewport_rect().size
	if global_position.x < half.x or global_position.x > bounds.x - half.x:
		_velocity.x = -_velocity.x
	if global_position.y < half.y or global_position.y > bounds.y - half.y:
		_velocity.y = -_velocity.y
	global_position.x = clampf(global_position.x, half.x, bounds.x - half.x)
	global_position.y = clampf(global_position.y, half.y, bounds.y - half.y)

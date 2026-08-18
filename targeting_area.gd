class_name TargetingArea
extends Node2D
## Mouse-following semi-transparent rectangle that auto-fires on a timer.
## Flashes brighter for a split second when it fires.

signal fired(rect: Rect2)

const FLASH_DURATION := 0.1
const FILL_COLOR := Color(Palette.BLACK, 0.08)
const FLASH_COLOR := Color(Palette.BLACK, 0.25)
const BORDER_COLOR := Palette.BLACK

var _flash_time := 0.0
var _fire_timer: Timer


func _ready() -> void:
	_fire_timer = Timer.new()
	_fire_timer.timeout.connect(_on_fire)
	add_child(_fire_timer)


func _process(delta: float) -> void:
	global_position = get_global_mouse_position()
	if _flash_time > 0.0:
		_flash_time -= delta
	queue_redraw()


func get_rect() -> Rect2:
	var size: Vector2 = GameState.stats.target_size
	return Rect2(global_position - size / 2.0, size)


func set_firing(enabled: bool) -> void:
	if enabled:
		_fire_timer.wait_time = GameState.stats.fire_interval
		_fire_timer.start()
	else:
		_fire_timer.stop()


func _on_fire() -> void:
	_flash_time = FLASH_DURATION
	fired.emit(get_rect())


func _draw() -> void:
	var size: Vector2 = GameState.stats.target_size
	var local := Rect2(-size / 2.0, size)
	var fill := FLASH_COLOR if _flash_time > 0.0 else FILL_COLOR
	draw_rect(local, fill, true)
	draw_rect(local, BORDER_COLOR, false, 1.0)

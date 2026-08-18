extends Node2D
## Owns the round lifecycle: spawning, fire routing, countdown, cleanup,
## round-over UI. Future level-up screen slots in between _on_round_over
## and start_round.

const DROP_OFFSET_MIN := 40.0
const DROP_OFFSET_MAX := 120.0

@onready var targeting_area: TargetingArea = $TargetingArea
@onready var enemies: Node2D = $Enemies
@onready var pickups: Node2D = $Pickups
@onready var round_timer: Timer = $RoundTimer
@onready var spawn_timer: Timer = $SpawnTimer
@onready var time_label: Label = $HUD/TimeLabel
@onready var currency_label: Label = $HUD/CurrencyLabel
@onready var round_over_panel: CenterContainer = $HUD/RoundOverPanel
@onready var restart_button: Button = $HUD/RoundOverPanel/VBoxContainer/RestartButton


func _ready() -> void:
	targeting_area.fired.connect(_on_target_fired)
	round_timer.timeout.connect(_on_round_over)
	spawn_timer.timeout.connect(_spawn_enemy)
	restart_button.pressed.connect(start_round)
	GameState.currency_changed.connect(_on_currency_changed)
	_on_currency_changed(GameState.currency)
	start_round()


func _process(_delta: float) -> void:
	if not round_timer.is_stopped():
		time_label.text = str(ceili(round_timer.time_left))


func start_round() -> void:
	round_over_panel.visible = false
	for i in GameState.stats.initial_enemies:
		_spawn_enemy()
	round_timer.start(GameState.stats.round_duration)
	spawn_timer.start(GameState.stats.spawn_interval)
	targeting_area.set_firing(true)


func _spawn_enemy() -> void:
	var enemy := Enemy.new()
	var half: Vector2 = GameState.stats.target_size / 2.0
	var bounds := get_viewport_rect().size
	enemy.position = Vector2(
		randf_range(half.x, bounds.x - half.x),
		randf_range(half.y, bounds.y - half.y)
	)
	enemy.died.connect(_on_enemy_died)
	enemies.add_child(enemy)


func _on_target_fired(rect: Rect2) -> void:
	for enemy in enemies.get_children():
		enemy.on_target_fired(rect)


func _on_enemy_died(at_position: Vector2) -> void:
	if round_timer.is_stopped():
		return
	var drop := CurrencyDrop.new()
	drop.position = at_position
	drop.target = targeting_area
	pickups.add_child(drop)
	var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(DROP_OFFSET_MIN, DROP_OFFSET_MAX)
	var bounds := get_viewport_rect().size
	var half := CurrencyDrop.SIZE / 2.0
	var dest := at_position + offset
	dest.x = clampf(dest.x, half.x, bounds.x - half.x)
	dest.y = clampf(dest.y, half.y, bounds.y - half.y)
	drop.pop_to(dest)


func _on_currency_changed(amount: int) -> void:
	currency_label.text = "Gold: %d" % amount


func _on_round_over() -> void:
	spawn_timer.stop()
	targeting_area.set_firing(false)
	for child in enemies.get_children() + pickups.get_children():
		child.queue_free()
	time_label.text = "0"
	round_over_panel.visible = true

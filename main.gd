extends Node2D
## Owns the round lifecycle: spawning, fire routing, countdown, cleanup;
## on round over it mounts the upgrade tree on the Screens CanvasLayer and
## restarts via its start_pressed signal.

const DROP_OFFSET_MIN := 10.0
const DROP_OFFSET_MAX := 30.0
const UPGRADE_TREE_SCENE := preload("res://upgrade_tree.tscn")

@onready var targeting_area: TargetingArea = $TargetingArea
@onready var enemies: Node2D = $Enemies
@onready var pickups: Node2D = $Pickups
@onready var effects: Node2D = $Effects
@onready var round_timer: Timer = $RoundTimer
@onready var spawn_timer: Timer = $SpawnTimer
@onready var time_label: Label = $HUD/TimeLabel
@onready var currency_label: Label = $HUD/CurrencyLabel
@onready var hud: CanvasLayer = $HUD
@onready var screens: CanvasLayer = $Screens


func _ready() -> void:
	Input.set_custom_mouse_cursor(preload("res://sprites/cursor.png"), Input.CURSOR_ARROW, Vector2.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	targeting_area.fired.connect(_on_target_fired)
	round_timer.timeout.connect(_on_round_over)
	spawn_timer.timeout.connect(_on_spawn_tick)
	GameState.currency_changed.connect(_on_currency_changed)
	_on_currency_changed(GameState.currency)
	start_round()


func _process(_delta: float) -> void:
	if not round_timer.is_stopped():
		time_label.text = str(ceili(round_timer.time_left))


func start_round() -> void:
	for child in enemies.get_children() + pickups.get_children() + effects.get_children():
		child.queue_free()
	for i in GameState.stats.initial_enemies:
		_spawn_enemy(EnemyTypes.DEFS.rabbit)
	round_timer.start(GameState.stats.round_duration)
	spawn_timer.start(GameState.stats.spawn_interval)
	targeting_area.set_firing(true)


func _on_spawn_tick() -> void:
	_spawn_enemy(EnemyTypes.DEFS.rabbit)


func _spawn_enemy(def: Dictionary) -> void:
	var enemy := Enemy.new()
	enemy.setup(def, GameState.hp_mult(), GameState.speed_mult())
	var half: Vector2 = def.size / 2.0
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


func _on_enemy_died(at_position: Vector2, coins: int) -> void:
	if round_timer.is_stopped():
		return
	var burst := KillBurst.new()
	burst.position = at_position
	effects.add_child(burst)
	var bounds := get_viewport_rect().size
	var half := CurrencyDrop.SIZE / 2.0
	# Each coin gets a random angle inside its own slice of the circle (the
	# slices themselves randomly rotated) so drops never clump together.
	var base_angle := randf() * TAU
	for i in coins:
		var drop := CurrencyDrop.new()
		drop.position = at_position
		drop.target = targeting_area
		pickups.add_child(drop)
		var angle := base_angle + (float(i) + randf()) * TAU / coins
		var offset := Vector2.RIGHT.rotated(angle) * randf_range(DROP_OFFSET_MIN, DROP_OFFSET_MAX)
		var dest := at_position + offset
		dest.x = clampf(dest.x, half.x, bounds.x - half.x)
		dest.y = clampf(dest.y, half.y, bounds.y - half.y)
		drop.pop_to(dest)


func _on_currency_changed(amount: int) -> void:
	currency_label.text = "Gold: %d" % amount


func _on_round_over() -> void:
	spawn_timer.stop()
	targeting_area.set_firing(false)
	for child in enemies.get_children() + pickups.get_children() + effects.get_children():
		child.queue_free()
	targeting_area.visible = false
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tree: UpgradeTree = UPGRADE_TREE_SCENE.instantiate()
	tree.start_pressed.connect(_on_start_pressed.bind(tree))
	screens.add_child(tree)


func _on_start_pressed(tree: UpgradeTree) -> void:
	tree.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	targeting_area.visible = true
	hud.visible = true
	time_label.text = str(ceili(GameState.stats.round_duration))
	start_round()

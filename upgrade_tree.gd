class_name UpgradeTree
extends Control
## Full-screen between-rounds upgrade screen. Draws the hub square and the
## hub-to-node connector lines (trimmed to node edges); the three UpgradeNodes
## are created in code from NODE_POSITIONS.

signal start_pressed

const HUB_POS := Vector2(240, 130)
const NODE_POSITIONS := {
	"dmg": Vector2(90, 130),
	"size": Vector2(240, 40),
	"speed": Vector2(390, 130),
}
const SQUARE_HALF := Vector2(12, 12)

@onready var gold_label: Label = $GoldLabel
@onready var stats_label: Label = $StatsLabel
@onready var start_button: Button = $StartButton


func _ready() -> void:
	for id in NODE_POSITIONS:
		var node := UpgradeNode.new(id)
		node.position = NODE_POSITIONS[id] - SQUARE_HALF
		add_child(node)
	start_button.pressed.connect(func() -> void: start_pressed.emit())
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.upgrades_changed.connect(_update_stats_label)
	_on_currency_changed(GameState.currency)
	_update_stats_label()


func _on_currency_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount


func _update_stats_label() -> void:
	var s: Dictionary = GameState.stats
	stats_label.text = "DMG: %d\nFIRE: %.1fs\nSIZE: %dx%d" % [
		s.damage, s.fire_interval, int(s.target_size.x), int(s.target_size.y)
	]


func _draw() -> void:
	# The root draws its own background: a ColorRect child would render
	# above this _draw and hide the lines and hub.
	draw_rect(Rect2(Vector2.ZERO, size), Palette.WHITE, true)
	for id in NODE_POSITIONS:
		var node_pos: Vector2 = NODE_POSITIONS[id]
		var dir := (node_pos - HUB_POS).normalized()
		# Vertical approaches pass the pip row (2px gap + 4px pips below the
		# 24px square), so trim 18 from the node center instead of 12.
		var node_trim := 18.0 if absf(dir.y) > absf(dir.x) else 12.0
		draw_line(HUB_POS + dir * SQUARE_HALF.x, node_pos - dir * node_trim, Palette.BLACK, 1.0)
	var hub := Rect2(HUB_POS - SQUARE_HALF, SQUARE_HALF * 2.0)
	draw_rect(hub, Palette.WHITE, true)
	draw_rect(hub, Palette.BLACK, false, 1.0)

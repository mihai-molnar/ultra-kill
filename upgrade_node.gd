class_name UpgradeNode
extends Control
## One square node of the upgrade tree: black-bordered 24x24 square with a
## 16x16 icon, and one 4x4 level pip per level below (peach = owned).
## Click buys the next level via GameState.buy_upgrade. Hover shows a
## palette-styled tooltip (Godot's default tooltip theme is off-palette).

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const NODE_SIZE := 24.0
const ICON_OFFSET := Vector2(4, 4)
const PIP_SIZE := 4.0
const PIP_GAP := 2.0
const PIPS_OFFSET_Y := 26.0
const HOVER_FILL := Color(Palette.PEACH, 0.4)
const DIM_ALPHA := 0.5

var upgrade_id: String
var _hovered := false


func _init(id: String) -> void:
	upgrade_id = id
	size = Vector2(NODE_SIZE, PIPS_OFFSET_Y + PIP_SIZE)
	tooltip_text = " "  # non-empty so hover triggers _make_custom_tooltip


func _ready() -> void:
	var icon := TextureRect.new()
	icon.texture = load(Upgrades.DEFS[upgrade_id].icon)
	icon.position = ICON_OFFSET
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	GameState.currency_changed.connect(_on_state_changed)
	GameState.upgrades_changed.connect(_refresh)
	_refresh()


func next_cost() -> int:
	var costs: Array = Upgrades.DEFS[upgrade_id].costs
	var level: int = GameState.upgrade_levels[upgrade_id]
	return -1 if level >= costs.size() else costs[level]


func can_buy() -> bool:
	var cost := next_cost()
	return cost >= 0 and GameState.currency >= cost


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.buy_upgrade(upgrade_id)


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _on_state_changed(_amount: int) -> void:
	_refresh()


func _refresh() -> void:
	# Dim only when the next level exists but is unaffordable; maxed nodes
	# stay at full alpha (their filled pips carry the state).
	modulate.a = DIM_ALPHA if next_cost() >= 0 and not can_buy() else 1.0
	queue_redraw()


func _draw() -> void:
	var square := Rect2(Vector2.ZERO, Vector2(NODE_SIZE, NODE_SIZE))
	draw_rect(square, Palette.WHITE, true)
	if _hovered and can_buy():
		draw_rect(square, HOVER_FILL, true)
	draw_rect(square, Palette.BLACK, false, 1.0)
	var costs: Array = Upgrades.DEFS[upgrade_id].costs
	var level: int = GameState.upgrade_levels[upgrade_id]
	var total_w := costs.size() * PIP_SIZE + (costs.size() - 1) * PIP_GAP
	var x := (NODE_SIZE - total_w) / 2.0
	for i in costs.size():
		var pip := Rect2(Vector2(x + i * (PIP_SIZE + PIP_GAP), PIPS_OFFSET_Y), Vector2(PIP_SIZE, PIP_SIZE))
		draw_rect(pip, Palette.PEACH if i < level else Palette.WHITE, true)
		draw_rect(pip, Palette.BLACK, false, 1.0)


func _make_custom_tooltip(_for_text: String) -> Object:
	var def: Dictionary = Upgrades.DEFS[upgrade_id]
	var cost := next_cost()
	var last_line := "MAX" if cost < 0 else "Next: %d gold" % cost
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.WHITE
	style.border_color = Palette.BLACK
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "%s\n%s\n%s" % [def.name, def.description, last_line]
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Palette.BLACK)
	panel.add_child(label)
	return panel

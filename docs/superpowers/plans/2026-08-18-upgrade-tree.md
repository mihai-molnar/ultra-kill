# Upgrade Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Between-rounds upgrade tree screen: spend gold on DMG/SIZE/SPEED upgrades (3 levels each), then start the next round.

**Architecture:** Static upgrade definitions in `upgrades.gd`; purchase + idempotent stat recompute in the `GameState` autoload; a self-contained `upgrade_tree.tscn` overlay scene mounted by `main.gd` when a round ends (replacing the old RoundOverPanel). Enemies get their own `enemy_size` stat so the reticle can grow without growing them.

**Tech Stack:** Godot 4.5 (GDScript, Forward Plus), no physics nodes, no test framework (throwaway headless harness scenes instead).

**Spec:** `docs/superpowers/specs/2026-08-18-upgrade-tree-design.md`

## Global Constraints

- Godot binary: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"` (always quote — path has a space). Run all commands from the project root `/Users/mihai/Godot games/ultra-kill`.
- **Exactly four colors, ever:** reference `Palette.BLACK` (#0a0912), `Palette.PURPLE` (#70579c), `Palette.PEACH` (#e096a8), `Palette.WHITE` (#fff1eb) in scripts; the same hex values verbatim in `.tscn` files. Alpha variants of these are allowed. Never any other color.
- All world/UI coordinates are in the 480×270 base-resolution space.
- UI font: `res://fonts/PressStart2P-Regular.ttf`, font sizes in multiples of 8, black text.
- GDScript: snake_case files/functions/vars, PascalCase nodes/classes, typed where practical.
- If a headless run fails with "Could not find type" / "Identifier not declared" for class_names that clearly exist, rebuild the class cache: `"$GODOT" --headless --path . --import`, then re-run.
- `--check-only --script` cannot resolve autoloads/class_names and always exits 0 — "Identifier not found: GameState" there is spurious; syntax errors are real.
- Never edit or commit `.godot/`. Commit generated `.uid` sidecar files.
- Test harnesses run as scenes (`"$GODOT" --headless --path . res://tools/<harness>.tscn`) because `--script` runs skip autoloads. Every harness is deleted before its task's commit (`.uid` included).

Every harness scene in this plan uses this exact `.tscn` shape (only the script path changes):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/<harness>.gd" id="1"]

[node name="Harness" type="Node"]
script = ExtResource("1")
```

And every harness `.gd` includes this check helper verbatim:

```gdscript
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)
```

---

### Task 1: Upgrade definitions + purchase logic in GameState

**Files:**
- Create: `upgrades.gd`
- Modify: `game_state.gd` (whole file rewritten below)
- Test: `tools/test_upgrades.gd`, `tools/test_upgrades.tscn` (deleted before commit)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Upgrades.DEFS: Dictionary` (keys `"dmg"|"size"|"speed"`, each `{name: String, description: String, icon: String, costs: Array[int]}`); `GameState.upgrade_levels: Dictionary` (same keys → int); `GameState.buy_upgrade(id: String) -> bool`; `signal upgrades_changed`; `GameState.BASE_STATS` (adds `enemy_size: Vector2(24, 24)`, also now in `stats`).

- [ ] **Step 1: Write the failing harness**

`tools/test_upgrades.gd`:

```gdscript
extends Node
## Throwaway harness: exercises Upgrades.DEFS + GameState.buy_upgrade.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _ready() -> void:
	var events := {"currency": 0, "upgrades": 0}
	GameState.currency_changed.connect(func(_a: int) -> void: events.currency += 1)
	GameState.upgrades_changed.connect(func() -> void: events.upgrades += 1)

	GameState.currency = 4
	check(not GameState.buy_upgrade("dmg"), "refuses when broke (4 < 5)")
	check(GameState.currency == 4, "no gold deducted on refusal")
	check(events.upgrades == 0, "no upgrades_changed on refusal")

	GameState.currency = 100
	check(GameState.buy_upgrade("dmg"), "buys dmg lvl 1")
	check(GameState.currency == 95, "cost 5 deducted")
	check(GameState.stats.damage == 4, "damage 4 at lvl 1")
	check(events.currency >= 1 and events.upgrades == 1, "signals emitted on purchase")
	check(GameState.buy_upgrade("dmg"), "buys dmg lvl 2")
	check(GameState.buy_upgrade("dmg"), "buys dmg lvl 3")
	check(GameState.currency == 95 - 7 - 10, "costs 7 and 10 deducted")
	check(GameState.stats.damage == 8, "damage 8 at lvl 3")
	check(not GameState.buy_upgrade("dmg"), "refuses at max level")
	check(GameState.upgrade_levels.dmg == 3, "level capped at 3")

	GameState.currency = 100
	check(GameState.buy_upgrade("size"), "buys size lvl 1 (cost 10)")
	check(GameState.stats.target_size == Vector2(30, 30), "target 30x30 at lvl 1")
	check(GameState.stats.enemy_size == Vector2(24, 24), "enemy_size stays 24x24")
	GameState.buy_upgrade("size")
	GameState.buy_upgrade("size")
	check(GameState.stats.target_size == Vector2(42, 42), "target 42x42 at lvl 3")

	GameState.currency = 100
	check(GameState.buy_upgrade("speed"), "buys speed lvl 1 (cost 7)")
	check(GameState.stats.fire_interval == 0.8, "interval 0.8 at lvl 1")
	GameState.buy_upgrade("speed")
	GameState.buy_upgrade("speed")
	check(GameState.stats.fire_interval == 0.4, "interval 0.4 at lvl 3")

	check(GameState.stats.currency_per_kill == 1, "unrelated stats preserved after recompute")
	check(GameState.stats.round_duration == 30.0, "round_duration preserved")
	for id in Upgrades.DEFS:
		var def: Dictionary = Upgrades.DEFS[id]
		check(def.costs.size() == 3, id + " has 3 levels")
		check(def.has("name") and def.has("description") and def.has("icon"), id + " def complete")
	finish()
```

`tools/test_upgrades.tscn`: the harness scene shape from Global Constraints with `path="res://tools/test_upgrades.gd"`.

- [ ] **Step 2: Run harness, verify it fails**

Run: `"$GODOT" --headless --path . res://tools/test_upgrades.tscn 2>&1 | tail -20`
Expected: script errors — `Identifier not found: Upgrades` / `buy_upgrade` not found (compile failure counts as the failing state).

- [ ] **Step 3: Implement**

Create `upgrades.gd`:

```gdscript
class_name Upgrades
## Static upgrade definitions. costs.size() is an upgrade's max level and
## its pip count, so deeper upgrades later are just longer arrays. Effect
## formulas live in GameState._recompute_stats.

const DEFS := {
	"dmg": {
		"name": "DMG",
		"description": "+2 damage per level",
		"icon": "res://sprites/icon_dmg.png",
		"costs": [5, 7, 10],
	},
	"size": {
		"name": "SIZE",
		"description": "+25% target area per level",
		"icon": "res://sprites/icon_size.png",
		"costs": [10, 20, 30],
	},
	"speed": {
		"name": "SPEED",
		"description": "Fires faster each level",
		"icon": "res://sprites/icon_speed.png",
		"costs": [7, 25, 35],
	},
}
```

Rewrite `game_state.gd`:

```gdscript
extends Node
## Persistent player state + all upgrade-tunable values.
## The upgrade tree calls buy_upgrade between rounds; gameplay code must
## read stats from here instead of hard-coding numbers. Stats are always
## recomputed from BASE_STATS + upgrade_levels (idempotent, no drift).

signal currency_changed(amount: int)
signal upgrades_changed

const BASE_STATS := {
	"fire_interval": 1.0,
	"damage": 2,
	"target_size": Vector2(24, 24),
	"enemy_size": Vector2(24, 24),
	"round_duration": 30.0,
	"spawn_interval": 2.0,
	"enemy_max_hp": 10,
	"initial_enemies": 10,
	"currency_per_kill": 1,
}

const DAMAGE_PER_LEVEL := 2
const SIZE_PER_LEVEL := 0.25
const FIRE_INTERVALS := [1.0, 0.8, 0.6, 0.4]

var currency: int = 0
var stats := BASE_STATS.duplicate()
var upgrade_levels := {"dmg": 0, "size": 0, "speed": 0}


func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)


func buy_upgrade(id: String) -> bool:
	var level: int = upgrade_levels[id]
	var costs: Array = Upgrades.DEFS[id].costs
	if level >= costs.size():
		return false
	var cost: int = costs[level]
	if currency < cost:
		return false
	currency -= cost
	upgrade_levels[id] = level + 1
	_recompute_stats()
	currency_changed.emit(currency)
	upgrades_changed.emit()
	return true


func _recompute_stats() -> void:
	stats = BASE_STATS.duplicate()
	stats.damage = BASE_STATS.damage + DAMAGE_PER_LEVEL * upgrade_levels.dmg
	stats.target_size = BASE_STATS.target_size * (1.0 + SIZE_PER_LEVEL * upgrade_levels.size)
	stats.fire_interval = FIRE_INTERVALS[upgrade_levels.speed]
```

- [ ] **Step 4: Run harness, verify it passes**

Run: `"$GODOT" --headless --path . res://tools/test_upgrades.tscn 2>&1 | tail -30`
Expected: every line `ok: ...`, `FAILURES: 0`, exit code 0. (If "Identifier not found: Upgrades" appears, rebuild the class cache per Global Constraints.)

- [ ] **Step 5: Delete harness, smoke-run, commit**

```bash
rm tools/test_upgrades.gd tools/test_upgrades.tscn tools/test_upgrades.gd.uid
"$GODOT" --headless --path . --quit-after 300 2>&1 | tail -5   # boots clean
git add upgrades.gd upgrades.gd.uid game_state.gd
git commit -m "feat: upgrade definitions and GameState purchase/recompute logic"
```

---

### Task 2: enemy_size split — enemies stop sharing target_size

**Files:**
- Modify: `enemy.gd:44-46` (`get_rect`), `enemy.gd:67-75` (`_bounce_off_edges`)
- Modify: `main.gd:44-53` (`_spawn_enemy`)
- Test: `tools/test_enemy_size.gd`, `tools/test_enemy_size.tscn` (deleted before commit)

**Interfaces:**
- Consumes: `GameState.stats.enemy_size` and `GameState.buy_upgrade("size")` from Task 1.
- Produces: `Enemy.get_rect()` sized by `enemy_size` (no API change; behavior only).

- [ ] **Step 1: Write the failing harness**

`tools/test_enemy_size.gd` (plus the standard harness `.tscn` pointing at it):

```gdscript
extends Node
## Throwaway harness: enemy rect must stay 24x24 when target_size is upgraded.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _ready() -> void:
	GameState.currency = 100
	GameState.buy_upgrade("size")
	check(GameState.stats.target_size == Vector2(30, 30), "precondition: target upgraded to 30")
	var enemy := Enemy.new()
	add_child(enemy)
	check(enemy.get_rect().size == Vector2(24, 24), "enemy rect stays 24x24 after size upgrade")
	finish()
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `"$GODOT" --headless --path . res://tools/test_enemy_size.tscn 2>&1 | tail -10`
Expected: `FAIL: enemy rect stays 24x24 after size upgrade` (it reads `target_size` today), exit 1.

- [ ] **Step 3: Implement**

In `enemy.gd`, `get_rect()`: change `var size: Vector2 = GameState.stats.target_size` to `var size: Vector2 = GameState.stats.enemy_size`.
In `enemy.gd`, `_bounce_off_edges()`: change `var half: Vector2 = GameState.stats.target_size / 2.0` to `var half: Vector2 = GameState.stats.enemy_size / 2.0`.
In `main.gd`, `_spawn_enemy()`: change `var half: Vector2 = GameState.stats.target_size / 2.0` to `var half: Vector2 = GameState.stats.enemy_size / 2.0`.

- [ ] **Step 4: Run harness, verify it passes**

Run: `"$GODOT" --headless --path . res://tools/test_enemy_size.tscn 2>&1 | tail -10`
Expected: all `ok`, `FAILURES: 0`, exit 0.

- [ ] **Step 5: Delete harness, commit**

```bash
rm tools/test_enemy_size.gd tools/test_enemy_size.tscn tools/test_enemy_size.gd.uid
git add enemy.gd main.gd
git commit -m "feat: split enemy_size from target_size so upgrades only grow the reticle"
```

---

### Task 3: Icon + cursor sprites

**Files:**
- Modify: `tools/make_placeholders.gd`
- Create (generated): `sprites/icon_dmg.png`, `sprites/icon_size.png`, `sprites/icon_speed.png`, `sprites/icon_hub.png`, `sprites/cursor.png` (+ their `.import` files after the import step)

**Interfaces:**
- Consumes: nothing.
- Produces: the five PNGs at the paths above — 16×16 icons; `cursor.png` is 32×32 (8×8 art pre-upscaled ×4 nearest-neighbor, a documented exception: OS cursors render at window resolution, outside the 480×270 canvas). Hotspot is the top-left pixel.

- [ ] **Step 1: Add the pixel maps and a scale parameter to the tool**

In `tools/make_placeholders.gd`, add `"W": Palette.WHITE` to `COLORS`, add the maps below, extend `_write` with a scale parameter, and register the new files in `_init()`:

```gdscript
const ICON_DMG := [
	"................",
	"............BB..",
	"...........BBB..",
	"..........BBB...",
	".........BBB....",
	"........BBB.....",
	".......BBB......",
	"......BBB.......",
	"..H..BBB........",
	"..HHBBB.........",
	"...HHB..........",
	"..HHHH..........",
	".HH..HH.........",
	"BB....HH........",
	"................",
	"................",
]

const ICON_SIZE := [
	"BBBB............",
	"BB..............",
	"B.B.............",
	"B..B............",
	"....BBBBBBBB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BBBBBBBB....",
	"............B..B",
	".............B.B",
	"..............BB",
	"............BBBB",
]

const ICON_SPEED := [
	"........BB......",
	".......BHB......",
	"......BHHB......",
	".....BHHB.......",
	"....BHHB........",
	"...BHHHBBBB.....",
	"...BHHHHHHB.....",
	"...BBBBHHB......",
	"......BHHB......",
	".....BHHB.......",
	"....BHHB........",
	"...BHHB.........",
	"...BHB..........",
	"...BB...........",
	"................",
	"................",
]

const ICON_HUB := [
	"BBBB........BBBB",
	"B..............B",
	"B..............B",
	"B..............B",
	"................",
	"................",
	"......PPPP......",
	"......PPPP......",
	"......PPPP......",
	"......PPPP......",
	"................",
	"................",
	"B..............B",
	"B..............B",
	"B..............B",
	"BBBB........BBBB",
]

const CURSOR := [
	"B.......",
	"BB......",
	"BWB.....",
	"BWWB....",
	"BWWWB...",
	"BWWWWB..",
	"BWBBBB..",
	"BB......",
]
```

`_init()` gains:

```gdscript
	_write("res://sprites/icon_dmg.png", ICON_DMG)
	_write("res://sprites/icon_size.png", ICON_SIZE)
	_write("res://sprites/icon_speed.png", ICON_SPEED)
	_write("res://sprites/icon_hub.png", ICON_HUB)
	# Cursor is pre-upscaled x4: OS cursors render at window resolution,
	# outside the 480x270 integer-scaled canvas (documented spec exception).
	_write("res://sprites/cursor.png", CURSOR, 4)
```

`_write` signature becomes `func _write(path: String, rows: Array, scale: int = 1) -> void:` and, just before `img.save_png(path)`:

```gdscript
	if scale > 1:
		img.resize(rows[0].length() * scale, rows.size() * scale, Image.INTERPOLATE_NEAREST)
```

- [ ] **Step 2: Regenerate and verify dimensions**

```bash
"$GODOT" --headless --path . --script res://tools/make_placeholders.gd 2>&1 | tail -8
sips -g pixelWidth -g pixelHeight sprites/icon_dmg.png sprites/icon_size.png sprites/icon_speed.png sprites/icon_hub.png sprites/cursor.png
```

Expected: seven `wrote ...` lines (enemy + drop + 5 new); icons 16×16; cursor 32×32.

- [ ] **Step 3: Import and eyeball**

Run `"$GODOT" --headless --path . --import 2>&1 | tail -3` so `.import` metadata exists. Then upscale each icon ×10 nearest-neighbor (same pattern as the bunny check: a scratchpad `SceneTree` script calling `Image.load_from_file` + `resize(..., Image.INTERPOLATE_NEAREST)` + `save_png` into the scratchpad) and **look at the images**: sword/arrows/bolt/reticle/arrow must be recognizable. Adjust pixels and regenerate if not.

- [ ] **Step 4: Commit**

```bash
git add tools/make_placeholders.gd sprites/
git commit -m "feat: upgrade icons (dmg/size/speed/hub) and pixel-art cursor sprites"
```

---

### Task 4: UpgradeNode control

**Files:**
- Create: `upgrade_node.gd`
- Test: `tools/test_upgrade_node.gd`, `tools/test_upgrade_node.tscn` (deleted before commit)

**Interfaces:**
- Consumes: `Upgrades.DEFS`, `GameState.upgrade_levels`, `GameState.buy_upgrade(id)`, `GameState.currency`, signals `currency_changed`/`upgrades_changed` (Task 1); icon PNGs (Task 3).
- Produces: `class_name UpgradeNode extends Control` — constructed `UpgradeNode.new(id: String)`, control size 24×30 (24×24 square + pips below); `next_cost() -> int` (−1 when maxed); `can_buy() -> bool`. Position it by its top-left; the square's center is `position + Vector2(12, 12)`.

- [ ] **Step 1: Write the failing harness**

`tools/test_upgrade_node.gd` (plus the standard harness `.tscn` pointing at it):

```gdscript
extends Node
## Throwaway harness: UpgradeNode state logic + tooltip content.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _tooltip_text(node: UpgradeNode) -> String:
	var tip: Control = node._make_custom_tooltip("")
	var label: Label = tip.get_child(0)
	return label.text


func _ready() -> void:
	GameState.currency = 0
	var node := UpgradeNode.new("dmg")
	add_child(node)
	check(node.size == Vector2(24, 30), "control size 24x30")
	check(node.next_cost() == 5, "next cost 5 at lvl 0")
	check(not node.can_buy(), "not buyable when broke")
	check(node.modulate.a < 1.0, "dimmed when unaffordable")
	check(_tooltip_text(node).contains("DMG"), "tooltip has name")
	check(_tooltip_text(node).contains("Next: 5 gold"), "tooltip has next cost")

	GameState.currency = 100
	GameState.currency_changed.emit(GameState.currency)
	check(node.can_buy(), "buyable with gold")
	check(node.modulate.a == 1.0, "full alpha when affordable")

	GameState.buy_upgrade("dmg")
	GameState.buy_upgrade("dmg")
	GameState.buy_upgrade("dmg")
	check(node.next_cost() == -1, "next_cost -1 at max")
	check(not node.can_buy(), "not buyable at max")
	check(node.modulate.a == 1.0, "maxed node not dimmed")
	check(_tooltip_text(node).contains("MAX"), "tooltip shows MAX")
	finish()
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `"$GODOT" --headless --path . res://tools/test_upgrade_node.tscn 2>&1 | tail -10`
Expected: compile error `Identifier not found: UpgradeNode` (rebuild class cache only AFTER upgrade_node.gd exists).

- [ ] **Step 3: Implement**

Create `upgrade_node.gd`:

```gdscript
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
```

- [ ] **Step 4: Run harness, verify it passes**

Run: `"$GODOT" --headless --path . res://tools/test_upgrade_node.tscn 2>&1 | tail -20`
Expected: all `ok`, `FAILURES: 0`, exit 0. (Class cache rebuild likely needed first: `"$GODOT" --headless --path . --import`.)

- [ ] **Step 5: Delete harness, commit**

```bash
rm tools/test_upgrade_node.gd tools/test_upgrade_node.tscn tools/test_upgrade_node.gd.uid
git add upgrade_node.gd upgrade_node.gd.uid
git commit -m "feat: UpgradeNode control with pips, states, and palette tooltip"
```

---

### Task 5: UpgradeTree scene

**Files:**
- Create: `upgrade_tree.gd`, `upgrade_tree.tscn`
- Test: `tools/test_upgrade_tree.gd`, `tools/test_upgrade_tree.tscn` (deleted before commit)

**Interfaces:**
- Consumes: `UpgradeNode.new(id)` (Task 4), `Upgrades.DEFS`, `GameState` signals/stats (Task 1), `icon_hub.png` (Task 3).
- Produces: `class_name UpgradeTree extends Control` with `signal start_pressed`; instantiated via `preload("res://upgrade_tree.tscn").instantiate()`. Full-screen (480×270), self-updating labels.

- [ ] **Step 1: Write the failing harness**

`tools/test_upgrade_tree.gd` (plus the standard harness `.tscn` pointing at it):

```gdscript
extends Node
## Throwaway harness: tree scene mounts, labels update, start signal fires.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _ready() -> void:
	GameState.currency = 50
	var tree: UpgradeTree = (load("res://upgrade_tree.tscn") as PackedScene).instantiate()
	add_child(tree)
	var gold: Label = tree.get_node("GoldLabel")
	var stats: Label = tree.get_node("StatsLabel")
	check(gold.text == "Gold: 50", "gold label shows currency")
	check(stats.text.contains("DMG: 2"), "stats label shows base damage")
	check(stats.text.contains("FIRE: 1.0s"), "stats label shows base interval")
	check(stats.text.contains("SIZE: 24x24"), "stats label shows base size")
	var node_ids := {}
	for child in tree.get_children():
		if child is UpgradeNode:
			node_ids[child.upgrade_id] = true
	check(node_ids.size() == 3 and node_ids.has("dmg") and node_ids.has("size") and node_ids.has("speed"), "three upgrade nodes present")

	GameState.buy_upgrade("dmg")
	check(gold.text == "Gold: 45", "gold label updates on purchase")
	check(stats.text.contains("DMG: 4"), "stats label updates on purchase")

	var fired := {"count": 0}
	tree.start_pressed.connect(func() -> void: fired.count += 1)
	var button: Button = tree.get_node("StartButton")
	button.pressed.emit()
	check(fired.count == 1, "start_pressed relayed from button")
	finish()
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `"$GODOT" --headless --path . res://tools/test_upgrade_tree.tscn 2>&1 | tail -10`
Expected: fails to load `res://upgrade_tree.tscn` (doesn't exist yet).

- [ ] **Step 3: Implement**

Create `upgrade_tree.gd`:

```gdscript
class_name UpgradeTree
extends Control
## Full-screen between-rounds upgrade screen. Draws the hub square and the
## hub-to-node connector lines itself (children draw over the line ends);
## the three UpgradeNodes are created in code from NODE_POSITIONS.

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
		draw_line(HUB_POS, NODE_POSITIONS[id], Palette.BLACK, 1.0)
	var hub := Rect2(HUB_POS - SQUARE_HALF, SQUARE_HALF * 2.0)
	draw_rect(hub, Palette.WHITE, true)
	draw_rect(hub, Palette.BLACK, false, 1.0)
```

Create `upgrade_tree.tscn` (StyleBox values copied verbatim from the Restart button being removed in Task 6; HubIcon sits above the root's `_draw` so the icon renders over the hub square):

```
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://upgrade_tree.gd" id="1"]
[ext_resource type="FontFile" path="res://fonts/PressStart2P-Regular.ttf" id="2"]
[ext_resource type="Texture2D" path="res://sprites/icon_hub.png" id="3"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_normal"]
content_margin_left = 4.0
content_margin_top = 2.0
content_margin_right = 4.0
content_margin_bottom = 2.0
bg_color = Color(1, 0.945098, 0.921569, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.0392157, 0.0352941, 0.0705882, 1)

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_hover"]
content_margin_left = 4.0
content_margin_top = 2.0
content_margin_right = 4.0
content_margin_bottom = 2.0
bg_color = Color(0.878431, 0.588235, 0.658824, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.0392157, 0.0352941, 0.0705882, 1)

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_pressed"]
content_margin_left = 4.0
content_margin_top = 2.0
content_margin_right = 4.0
content_margin_bottom = 2.0
bg_color = Color(0.439216, 0.341176, 0.611765, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.0392157, 0.0352941, 0.0705882, 1)

[node name="UpgradeTree" type="Control"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")

[node name="GoldLabel" type="Label" parent="."]
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -60.0
offset_top = 8.0
offset_right = 60.0
offset_bottom = 18.0
grow_horizontal = 2
theme_override_colors/font_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_fonts/font = ExtResource("2")
theme_override_font_sizes/font_size = 8
text = "Gold: 0"
horizontal_alignment = 1

[node name="StatsLabel" type="Label" parent="."]
offset_left = 8.0
offset_top = 8.0
offset_right = 120.0
offset_bottom = 44.0
theme_override_colors/font_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_fonts/font = ExtResource("2")
theme_override_font_sizes/font_size = 8
text = "DMG: 2
FIRE: 1.0s
SIZE: 24x24"

[node name="HubIcon" type="TextureRect" parent="."]
offset_left = 232.0
offset_top = 122.0
offset_right = 248.0
offset_bottom = 138.0
mouse_filter = 2
texture = ExtResource("3")

[node name="StartButton" type="Button" parent="."]
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -48.0
offset_top = -28.0
offset_right = 48.0
offset_bottom = -14.0
grow_horizontal = 2
grow_vertical = 0
theme_override_colors/font_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_colors/font_hover_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_colors/font_pressed_color = Color(1, 0.945098, 0.921569, 1)
theme_override_colors/font_focus_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_fonts/font = ExtResource("2")
theme_override_font_sizes/font_size = 8
theme_override_styles/normal = SubResource("StyleBoxFlat_normal")
theme_override_styles/hover = SubResource("StyleBoxFlat_hover")
theme_override_styles/pressed = SubResource("StyleBoxFlat_pressed")
theme_override_styles/focus = SubResource("StyleBoxFlat_normal")
text = "Start Round"
```

Note: there is deliberately no `ColorRect` background — the root's `_draw` paints it (a child ColorRect would render above the lines/hub). `HubIcon` sets `mouse_filter = 2` (ignore) so it never eats node clicks.

- [ ] **Step 4: Run harness, verify it passes**

Run: `"$GODOT" --headless --path . res://tools/test_upgrade_tree.tscn 2>&1 | tail -20`
Expected: all `ok`, `FAILURES: 0`, exit 0.

- [ ] **Step 5: Delete harness, commit**

```bash
rm tools/test_upgrade_tree.gd tools/test_upgrade_tree.tscn tools/test_upgrade_tree.gd.uid
git add upgrade_tree.gd upgrade_tree.gd.uid upgrade_tree.tscn
git commit -m "feat: upgrade tree screen with hub, nodes, stats readout, start button"
```

---

### Task 6: Round-flow integration — tree replaces RoundOverPanel, cursor rules

**Files:**
- Modify: `main.gd`, `main.tscn`
- Test: `tools/test_round_flow.gd`, `tools/test_round_flow.tscn` (deleted before commit)

**Interfaces:**
- Consumes: `UpgradeTree` scene + `start_pressed` (Task 5).
- Produces: final round lifecycle. No new public API.

- [ ] **Step 1: Write the failing harness**

`tools/test_round_flow.gd` (plus the standard harness `.tscn` pointing at it):

```gdscript
extends Node
## Throwaway harness: round over mounts the tree; start_pressed restarts.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)


func finish() -> void:
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _ready() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	check(main.get_node_or_null("HUD/RoundOverPanel") == null, "RoundOverPanel removed from scene")
	main._on_round_over()
	await get_tree().process_frame
	var screens: CanvasLayer = main.get_node("Screens")
	check(screens.get_child_count() == 1 and screens.get_child(0) is UpgradeTree, "tree mounted on round over")
	check(not main.get_node("TargetingArea").visible, "reticle hidden on upgrade screen")
	check(not main.get_node("HUD").visible, "HUD hidden on upgrade screen")
	check(main.get_node("Enemies").get_child_count() == 0 or main.get_node("Enemies").get_children().all(func(c: Node) -> bool: return c.is_queued_for_deletion()), "enemies cleared on round over")
	var tree: UpgradeTree = screens.get_child(0)
	tree.start_pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(screens.get_child_count() == 0, "tree freed on start")
	check(main.get_node("TargetingArea").visible, "reticle shown in round")
	check(main.get_node("HUD").visible, "HUD shown in round")
	check(not main.get_node("RoundTimer").is_stopped(), "round timer running again")
	check(main.get_node("Enemies").get_child_count() >= GameState.stats.initial_enemies, "enemies respawned")
	finish()
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `"$GODOT" --headless --path . res://tools/test_round_flow.tscn 2>&1 | tail -15`
Expected: `FAIL: RoundOverPanel removed from scene`, `FAIL: tree mounted...` (no `Screens` node yet → error/null), exit 1.

- [ ] **Step 3: Implement**

`main.tscn`:
- Delete the `RoundOverPanel` node block and its children (`VBoxContainer`, `RoundOverLabel`, `RestartButton`) and the three `StyleBoxFlat` sub_resources (now only used by `upgrade_tree.tscn`); drop `load_steps` accordingly (from 7 to 4 — Godot will rewrite this on next editor save anyway).
- Add after the `TargetingArea` node (CanvasLayers render above Node2Ds regardless of order; HUD has default layer 1, Screens goes above it):

```
[node name="Screens" type="CanvasLayer" parent="."]
layer = 2
```

`main.gd`:
- Add near the top:

```gdscript
const UPGRADE_TREE_SCENE := preload("res://upgrade_tree.tscn")
```

- Replace the `round_over_panel` and `restart_button` @onready vars with:

```gdscript
@onready var hud: CanvasLayer = $HUD
@onready var screens: CanvasLayer = $Screens
```

- In `_ready()`: delete `restart_button.pressed.connect(start_round)`; add as the first lines (cursor is set up once, then only visibility toggles per screen):

```gdscript
	Input.set_custom_mouse_cursor(preload("res://sprites/cursor.png"), Input.CURSOR_ARROW, Vector2.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
```

- Replace `start_round()` with (defensive clear per CLAUDE.md; the panel line goes away):

```gdscript
func start_round() -> void:
	for child in enemies.get_children() + pickups.get_children() + effects.get_children():
		child.queue_free()
	for i in GameState.stats.initial_enemies:
		_spawn_enemy()
	round_timer.start(GameState.stats.round_duration)
	spawn_timer.start(GameState.stats.spawn_interval)
	targeting_area.set_firing(true)
```

- Replace `_on_round_over()` with:

```gdscript
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
```

- In `_on_round_over` the old `time_label.text = "0"` and `round_over_panel.visible = true/false` lines are gone (HUD is hidden instead).

- [ ] **Step 4: Run harness + smoke, verify**

Run: `"$GODOT" --headless --path . res://tools/test_round_flow.tscn 2>&1 | tail -20`
Expected: all `ok`, `FAILURES: 0`, exit 0.
Run: `"$GODOT" --headless --path . --quit-after 300 2>&1 | tail -5`
Expected: boots clean, no script errors (headless may log benign cursor warnings — those are fine; script errors are not).

- [ ] **Step 5: Delete harness, commit**

```bash
rm tools/test_round_flow.gd tools/test_round_flow.tscn tools/test_round_flow.gd.uid
git add main.gd main.tscn
git commit -m "feat: upgrade tree between rounds, replaces RoundOverPanel; cursor rules"
```

---

### Task 7: CLAUDE.md update + final verification

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none — documentation and verification only.

- [ ] **Step 1: Update CLAUDE.md**

Apply exactly these content changes (wording may be smoothed, facts must match):

1. **Project Overview**: the loop is no longer "intended long-term" — round → kill → collect → upgrade tree → next round is implemented. Add this spec/plan pair to the design-spec list (`docs/superpowers/specs/2026-08-18-upgrade-tree-design.md`).
2. **Architecture — `game_state.gd` bullet**: stats are recomputed from `BASE_STATS` + `upgrade_levels` by `buy_upgrade()`/`_recompute_stats()`; mention `upgrades.gd` (`class_name Upgrades`) holding `DEFS` (costs/name/description/icon; `costs.size()` = max level). The "upgrade seam" sentence now describes reality, not the future.
3. **Architecture — add bullets** for `upgrade_tree.gd`/`upgrade_tree.tscn` (full-screen between-rounds Control on the `Screens` CanvasLayer, draws hub + connector lines, emits `start_pressed`) and `upgrade_node.gd` (square node, pips, palette tooltip via `_make_custom_tooltip`, click buys).
4. **Architecture — `main.gd` bullet**: RoundOverPanel is gone; round over mounts the upgrade tree, hides HUD + reticle, shows the custom cursor; `start_round()` has a defensive container clear. Cursor rules: OS cursor hidden during rounds (`MOUSE_MODE_HIDDEN`, the reticle is the pointer), visible pixel-art cursor (`sprites/cursor.png`, hotspot 0,0) on the upgrade screen.
5. **Architecture — `enemy.gd` bullet**: reads `stats.enemy_size` (target_size is reticle-only now).
6. **Visual identity — sprite bullet**: add the icon sprites (16×16) and note the cursor exception: `cursor.png` is pre-upscaled ×4 (32×32) because OS cursors render at window resolution.
7. **Next slice / known deferred work**: remove the level-up-screen item, the target/enemy size split item, and the defensive-clear item (all done). Keep the remaining minors. Add plausible nexts: save/load persistence, balancing rounds against upgraded stats, deeper tree tiers.

- [ ] **Step 2: Full verification pass**

```bash
"$GODOT" --headless --path . --import 2>&1 | tail -3
"$GODOT" --headless --path . --quit-after 300 2>&1 | tail -5
git status --short   # expect: only CLAUDE.md modified, no stray harness files
```

Expected: clean boot, no leftover `tools/test_*` files.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record upgrade tree architecture, cursor rules, done deferred work"
```

- [ ] **Step 4: Hand off for playtest**

Launch for the user (do not skip — feel is a spec requirement): `"$GODOT" --path "/Users/mihai/Godot games/ultra-kill"` in the background; ask them to verify: cursor hidden in-round, pixel cursor on the tree, tooltips readable, pips fill, purchases apply next round (bigger reticle, faster fire, 4+ damage), bunnies still 24×24.

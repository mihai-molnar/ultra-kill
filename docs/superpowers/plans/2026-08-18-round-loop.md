# Core Round Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First playable slice of the incremental game: mouse-controlled auto-firing targeting rectangle kills wandering enemy rectangles, collects dropped currency, 30-second rounds with a restart button.

**Architecture:** All gameplay objects are lightweight `Node2D`s drawn with `_draw` and collided with plain `Rect2` intersection math — no physics. A `GameState` autoload holds persistent currency and a `stats` dictionary that all gameplay reads from, so future upgrades only mutate stats. `main.tscn` owns the round lifecycle (timers, spawning, cleanup, HUD).

**Tech Stack:** Godot 4.5.1 (GDScript, Forward Plus). Editor binary: `/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot`.

**Spec:** `docs/superpowers/specs/2026-08-18-round-loop-design.md`

## Global Constraints

- Project root: `/Users/mihai/Godot games/ultra-kill` (note the space in the path — always quote it).
- Godot binary (define once per shell): `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`
- Viewport is Godot's default 1152×648; do not change window settings.
- No physics nodes (Area2D/CharacterBody2D). All overlap tests are `Rect2.intersects`.
- All tunable gameplay values live in `GameState.stats` — never hard-code a value that appears in the stats dictionary (spec: `fire_interval` 1.0, `damage` 2, `target_size` Vector2(100, 100), `round_duration` 30.0, `spawn_interval` 2.0, `enemy_max_hp` 10, `initial_enemies` 10, `currency_per_kill` 1).
- No test framework in this slice (per spec). Verification per task is: GDScript static check via `--check-only`, then a headless smoke run and a manual playtest once the scene exists. Godot may generate `.uid` sidecar files during runs — commit them with the task.
- Run commands from the project root: `cd "/Users/mihai/Godot games/ultra-kill"`.

---

### Task 1: GameState autoload

**Files:**
- Create: `game_state.gd`
- Modify: `project.godot` (add `[autoload]` section)

**Interfaces:**
- Consumes: nothing.
- Produces (used by every later task):
  - Autoload singleton `GameState`
  - `GameState.currency: int`
  - `GameState.stats: Dictionary` (keys listed in Global Constraints)
  - `GameState.add_currency(amount: int) -> void`
  - `signal currency_changed(amount: int)`

- [ ] **Step 1: Write `game_state.gd`**

```gdscript
extends Node
## Persistent player state + all upgrade-tunable values.
## The future level-up screen mutates `stats` between rounds; gameplay
## code must read from here instead of hard-coding numbers.

signal currency_changed(amount: int)

var currency: int = 0

var stats := {
	"fire_interval": 1.0,
	"damage": 2,
	"target_size": Vector2(100, 100),
	"round_duration": 30.0,
	"spawn_interval": 2.0,
	"enemy_max_hp": 10,
	"initial_enemies": 10,
	"currency_per_kill": 1,
}


func add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)
```

- [ ] **Step 2: Register the autoload in `project.godot`**

Append this section to `project.godot` (keep existing sections untouched):

```ini
[autoload]

GameState="*res://game_state.gd"
```

- [ ] **Step 3: Verify the script parses**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --check-only --script res://game_state.gd; echo "exit: $?"
```

Expected: no `SCRIPT ERROR` / `Parse Error` lines, `exit: 0`.

- [ ] **Step 4: Commit**

```bash
git add game_state.gd game_state.gd.uid project.godot
git commit -m "feat: add GameState autoload with currency and upgrade-ready stats"
```

(If `game_state.gd.uid` was not generated, commit without it.)

---

### Task 2: Enemy

**Files:**
- Create: `enemy.gd`

**Interfaces:**
- Consumes: `GameState.stats` (`target_size`, `enemy_max_hp`, `damage`).
- Produces (used by Task 5):
  - `class_name Enemy extends Node2D` — constructed with `Enemy.new()`, caller sets `position` before `add_child`
  - `signal died(at_position: Vector2)` — emitted once, right before `queue_free()`
  - `on_target_fired(target_rect: Rect2) -> void` — applies `stats.damage` if overlapping
  - `get_rect() -> Rect2` — global-space rect

- [ ] **Step 1: Write `enemy.gd`**

```gdscript
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
	position += _velocity * delta
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
	if position.x < half.x or position.x > bounds.x - half.x:
		_velocity.x = -_velocity.x
	if position.y < half.y or position.y > bounds.y - half.y:
		_velocity.y = -_velocity.y
	position.x = clampf(position.x, half.x, bounds.x - half.x)
	position.y = clampf(position.y, half.y, bounds.y - half.y)


func _draw() -> void:
	var size: Vector2 = GameState.stats.target_size
	draw_rect(Rect2(-size / 2.0, size), LIGHT_RED, true)
	var hp_width := size.x * float(hp) / float(max_hp)
	draw_rect(Rect2(-size / 2.0, Vector2(hp_width, size.y)), DARK_RED, true)
```

- [ ] **Step 2: Verify the script parses**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --check-only --script res://enemy.gd; echo "exit: $?"
```

Expected: no errors, `exit: 0`. (The `GameState` identifier resolves because the autoload was registered in Task 1.)

- [ ] **Step 3: Commit**

```bash
git add enemy.gd enemy.gd.uid
git commit -m "feat: add Enemy with wandering movement, HP bar rendering, and fire-hit handling"
```

---

### Task 3: TargetingArea

**Files:**
- Create: `targeting_area.gd`

**Interfaces:**
- Consumes: `GameState.stats` (`target_size`, `fire_interval`).
- Produces (used by Tasks 4 and 5):
  - `class_name TargetingArea extends Node2D` — attached to a node in `main.tscn` (Task 5)
  - `signal fired(rect: Rect2)` — emitted every `stats.fire_interval` seconds while firing
  - `get_rect() -> Rect2` — global-space rect, used for currency pickup every frame
  - `set_firing(enabled: bool) -> void` — main starts/stops firing at round start/end

- [ ] **Step 1: Write `targeting_area.gd`**

```gdscript
class_name TargetingArea
extends Node2D
## Mouse-following semi-transparent rectangle that auto-fires on a timer.
## Flashes brighter for a split second when it fires.

signal fired(rect: Rect2)

const FLASH_DURATION := 0.1
const FILL_COLOR := Color(1, 1, 1, 0.22)
const FLASH_COLOR := Color(1, 1, 1, 0.55)
const BORDER_COLOR := Color(1, 1, 1, 0.8)

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
	draw_rect(local, BORDER_COLOR, false, 2.0)
```

- [ ] **Step 2: Verify the script parses**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --check-only --script res://targeting_area.gd; echo "exit: $?"
```

Expected: no errors, `exit: 0`.

- [ ] **Step 3: Commit**

```bash
git add targeting_area.gd targeting_area.gd.uid
git commit -m "feat: add TargetingArea with mouse follow, fire timer, and flash"
```

---

### Task 4: CurrencyDrop

**Files:**
- Create: `currency_drop.gd`

**Interfaces:**
- Consumes: `TargetingArea.get_rect()` (Task 3), `GameState.add_currency` / `stats.currency_per_kill` (Task 1).
- Produces (used by Task 5):
  - `class_name CurrencyDrop extends Node2D` — constructed with `CurrencyDrop.new()`; caller sets `position` AND `target` (a `TargetingArea`) before `add_child`

- [ ] **Step 1: Write `currency_drop.gd`**

```gdscript
class_name CurrencyDrop
extends Node2D
## Placeholder currency: small gold rectangle dropped where an enemy died.
## Collected (self-frees) when the targeting area passes over it.

const SIZE := Vector2(14, 14)
const GOLD := Color(1.0, 0.84, 0.2)

var target: TargetingArea


func _process(_delta: float) -> void:
	if target and target.get_rect().intersects(get_rect()):
		GameState.add_currency(GameState.stats.currency_per_kill)
		queue_free()


func get_rect() -> Rect2:
	return Rect2(global_position - SIZE / 2.0, SIZE)


func _draw() -> void:
	draw_rect(Rect2(-SIZE / 2.0, SIZE), GOLD, true)
```

- [ ] **Step 2: Verify the script parses**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --check-only --script res://currency_drop.gd; echo "exit: $?"
```

Expected: no errors, `exit: 0`.

- [ ] **Step 3: Commit**

```bash
git add currency_drop.gd currency_drop.gd.uid
git commit -m "feat: add CurrencyDrop collected by targeting-area overlap"
```

---

### Task 5: Main scene — round lifecycle, HUD, restart

**Files:**
- Create: `main.gd`
- Create: `main.tscn`
- Modify: `project.godot` (set `run/main_scene`)

**Interfaces:**
- Consumes: everything from Tasks 1–4 (exact signatures in those tasks' Produces blocks).
- Produces: the runnable game (`res://main.tscn` as main scene).

- [ ] **Step 1: Write `main.gd`**

```gdscript
extends Node2D
## Owns the round lifecycle: spawning, fire routing, countdown, cleanup,
## round-over UI. Future level-up screen slots in between _on_round_over
## and start_round.

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


func _on_currency_changed(amount: int) -> void:
	currency_label.text = "Gold: %d" % amount


func _on_round_over() -> void:
	spawn_timer.stop()
	targeting_area.set_firing(false)
	for child in enemies.get_children() + pickups.get_children():
		child.queue_free()
	time_label.text = "0"
	round_over_panel.visible = true
```

- [ ] **Step 2: Write `main.tscn`**

Exact file content (Godot will add `uid=` attributes on first editor open — that's fine, commit them when they appear):

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://main.gd" id="1"]
[ext_resource type="Script" path="res://targeting_area.gd" id="2"]

[node name="Main" type="Node2D"]
script = ExtResource("1")

[node name="TargetingArea" type="Node2D" parent="."]
script = ExtResource("2")

[node name="Enemies" type="Node2D" parent="."]

[node name="Pickups" type="Node2D" parent="."]

[node name="RoundTimer" type="Timer" parent="."]
one_shot = true

[node name="SpawnTimer" type="Timer" parent="."]

[node name="HUD" type="CanvasLayer" parent="."]

[node name="TimeLabel" type="Label" parent="HUD"]
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -50.0
offset_top = 8.0
offset_right = 50.0
offset_bottom = 40.0
grow_horizontal = 2
theme_override_font_sizes/font_size = 24
text = "30"
horizontal_alignment = 1

[node name="CurrencyLabel" type="Label" parent="HUD"]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -180.0
offset_top = 8.0
offset_right = -12.0
offset_bottom = 40.0
grow_horizontal = 0
theme_override_font_sizes/font_size = 24
text = "Gold: 0"
horizontal_alignment = 2

[node name="RoundOverPanel" type="CenterContainer" parent="HUD"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBoxContainer" type="VBoxContainer" parent="HUD/RoundOverPanel"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="RoundOverLabel" type="Label" parent="HUD/RoundOverPanel/VBoxContainer"]
layout_mode = 2
theme_override_font_sizes/font_size = 36
text = "Round Over"
horizontal_alignment = 1

[node name="RestartButton" type="Button" parent="HUD/RoundOverPanel/VBoxContainer"]
layout_mode = 2
text = "Restart"
```

- [ ] **Step 3: Set the main scene in `project.godot`**

In the `[application]` section, add this line under `config/name`:

```ini
run/main_scene="res://main.tscn"
```

- [ ] **Step 4: Static-check `main.gd`, then headless smoke run**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --check-only --script res://main.gd; echo "exit: $?"
"$GODOT" --headless --path . --quit-after 300 2>&1 | tee /tmp/smoke.log | grep -E "SCRIPT ERROR|ERROR|Parse" ; echo "smoke exit: $?"
```

Expected: check-only exits 0; the smoke run (≈300 frames ≈ 5 s of game time — enemies spawn, the fire timer ticks a few times) prints no `SCRIPT ERROR` lines, so the grep finds nothing and prints `smoke exit: 1`. In headless mode the mouse sits at (0,0), so the targeting area hugs the top-left corner — that's expected, not a bug.

- [ ] **Step 5: Commit**

```bash
git add main.gd main.gd.uid main.tscn project.godot
git commit -m "feat: add main scene with round lifecycle, HUD, and restart"
```

---

### Task 6: Manual playtest + docs

**Files:**
- Modify: `CLAUDE.md` (add Godot binary path and run/check commands)

**Interfaces:**
- Consumes: the complete game from Task 5.
- Produces: verified playable slice; CLAUDE.md documents how to run and check the project.

- [ ] **Step 1: Launch the game windowed for a human playtest**

```bash
cd "/Users/mihai/Godot games/ultra-kill"
GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"
"$GODOT" --path .
```

Ask the human partner to verify this checklist (this needs eyes and a mouse — do not skip or self-certify):

1. Semi-transparent rectangle follows the mouse; flashes brighter about once per second.
2. 10 enemies at start; one more appears every 2 s; they wander and bounce off screen edges only.
3. Enemies overlapping the target when it flashes lose HP: dark-red bar shrinks left-to-right in 5 visible steps (2 HP per hit, 10 HP total); several overlapping enemies get hit by one shot.
4. Fully light-red enemy disappears and leaves a small gold rectangle.
5. Sweeping the target over gold collects it; top-right "Gold:" label increments.
6. Top-center countdown runs 30 → 0; at 0 everything clears and "Round Over" + Restart appear.
7. Restart starts a fresh round; gold total is kept.

- [ ] **Step 2: Fix anything the playtest surfaces**

If a checklist item fails, use the superpowers:systematic-debugging skill before changing code; commit each fix separately.

- [ ] **Step 3: Update `CLAUDE.md`**

Replace the "The Godot editor binary is not on PATH..." bullet in the *Working with Godot* section with:

```markdown
- Godot 4.5.1 binary: `/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot` (quote the path — it has a space).
- Run the game: `"$GODOT" --path "/Users/mihai/Godot games/ultra-kill"`
- Static-check a script: `"$GODOT" --headless --path . --check-only --script res://<file>.gd`
- Headless smoke run: `"$GODOT" --headless --path . --quit-after 300` (mouse sits at 0,0 in headless — targeting area in the corner is expected).
```

Also update the "fresh project" line in *Project Overview* to describe the current state (core round loop implemented; see spec in `docs/superpowers/specs/`).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record Godot binary path and run/check commands"
```

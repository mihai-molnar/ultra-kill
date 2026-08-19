# Enemy Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-round enemy variety — new types unlock each round (pig, giant rabbit, giant pig), a boss every 5th round, adaptive spawn rate with a hard cap, late-round escalation, and a "ROUND N" splash.

**Architecture:** Per-type tunables move from `GameState.stats` into a new static `EnemyTypes` data class (same pattern as `Upgrades.DEFS`); `Enemy` gains a `setup(def, hp_mult, speed_mult)` call so one class renders every type; `main.gd` owns pool picking, the boss spawn, the cap, and the adaptive timer; round/escalation counters live in `GameState`.

**Tech Stack:** Godot 4.5 GDScript, no physics nodes, no test framework (throwaway SceneTree harness scripts + headless smoke runs, by design).

**Spec:** `docs/superpowers/specs/2026-08-19-enemy-progression-design.md`

## Global Constraints

- Godot binary: `GODOT="/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"` — always quote (`"$GODOT"`), the path has a space. Run from the project root `/Users/mihai/Godot games/ultra-kill`.
- Exactly four colors, ever: `Palette.BLACK #0a0912`, `Palette.PURPLE #70579c`, `Palette.PEACH #e096a8`, `Palette.WHITE #fff1eb`. Scripts reference `Palette.*`; `.tscn` files use the literal values verbatim.
- All world coordinates/sizes/speeds are in 480×270 base-resolution units. Fonts: Press Start 2P, antialiasing off, sizes in multiples of 8.
- Sprites: PNG, transparent background, 1:1 base-resolution scale, palette colors only, `Palette.PURPLE` body (the damage shader erodes purple → peach).
- Gameplay reads tunables from `GameState.stats` at point of use — never hard-code a value that has a stats key. (This plan deliberately *removes* `enemy_max_hp`/`enemy_size` from stats; per-type values live in `EnemyTypes` instead.)
- snake_case files/functions/variables, PascalCase classes/nodes. Commit `.uid` sidecars and regenerated `.import` files; never touch `.godot/`.
- If a headless run fails with "Could not find type"/"Identifier not declared" for class_names that clearly exist, rebuild the class cache: `"$GODOT" --headless --path . --import`, then re-run.
- Harness scripts are throwaway: they live at `tools/tmp_harness.gd` during a task and are **deleted before that task's commit**.

---

### Task 1: `EnemyTypes` data class

**Files:**
- Create: `enemy_types.gd`
- Test: `tools/tmp_harness.gd` (throwaway, deleted before commit)

**Interfaces:**
- Consumes: nothing new.
- Produces: `class_name EnemyTypes` with `const DEFS: Dictionary` (keys `rabbit`, `pig`, `giant_rabbit`, `giant_pig`; each value has `sprite: String`, `size: Vector2`, `max_hp: int`, `coins: int`, `unlock_round: int`, `speed_scale: float`), `const BOSS: Dictionary` (same fields minus `unlock_round`), and `static func unlocked(round_number: int) -> Array` returning the DEFS values (def dictionaries) with `unlock_round <= round_number`.

- [ ] **Step 1: Write the failing harness**

Create `tools/tmp_harness.gd`:

```gdscript
extends SceneTree
## Throwaway assertion harness for EnemyTypes. Delete before commit.

func _init() -> void:
	assert(EnemyTypes.unlocked(1).size() == 1, "round 1: rabbit only")
	assert(EnemyTypes.unlocked(2).size() == 2, "round 2 adds pig")
	assert(EnemyTypes.unlocked(3).size() == 3, "round 3 adds giant rabbit")
	assert(EnemyTypes.unlocked(4).size() == 4, "round 4 adds giant pig")
	assert(EnemyTypes.unlocked(99).size() == 4, "boss never in the pool")
	assert(EnemyTypes.unlocked(1)[0].max_hp == 10)
	assert(EnemyTypes.DEFS.pig.max_hp == 16 and EnemyTypes.DEFS.pig.coins == 4)
	assert(EnemyTypes.DEFS.giant_rabbit.max_hp == 20 and EnemyTypes.DEFS.giant_rabbit.coins == 5)
	assert(EnemyTypes.DEFS.giant_pig.max_hp == 26 and EnemyTypes.DEFS.giant_pig.coins == 6)
	assert(EnemyTypes.BOSS.max_hp == 100 and EnemyTypes.BOSS.coins == 50)
	assert(EnemyTypes.BOSS.speed_scale == 0.5)
	assert(EnemyTypes.DEFS.giant_pig.size == Vector2(32, 32))
	assert(EnemyTypes.BOSS.size == Vector2(48, 48))
	print("EnemyTypes OK")
	quit()
```

- [ ] **Step 2: Run harness to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tools/tmp_harness.gd
```

Expected: FAIL — parse error "Identifier not declared: EnemyTypes" (or "Could not find type"). That error is real here because the class genuinely doesn't exist yet.

- [ ] **Step 3: Write `enemy_types.gd`**

```gdscript
class_name EnemyTypes
## Static per-enemy-type tunables (mirrors the Upgrades.DEFS pattern).
## "coins" is the number of drop sprites a kill pops out; each drop is
## worth GameState.stats.currency_per_kill. The boss lives outside DEFS
## so the random spawn pool is just "unlocked DEFS entries" — the boss
## spawns once at the start of boss rounds, never from the timer.

const DEFS := {
	"rabbit": {
		"sprite": "res://sprites/enemy.png",
		"size": Vector2(24, 24),
		"max_hp": 10,
		"coins": 3,
		"unlock_round": 1,
		"speed_scale": 1.0,
	},
	"pig": {
		"sprite": "res://sprites/pig.png",
		"size": Vector2(24, 24),
		"max_hp": 16,
		"coins": 4,
		"unlock_round": 2,
		"speed_scale": 1.0,
	},
	"giant_rabbit": {
		"sprite": "res://sprites/giant_rabbit.png",
		"size": Vector2(32, 32),
		"max_hp": 20,
		"coins": 5,
		"unlock_round": 3,
		"speed_scale": 1.0,
	},
	"giant_pig": {
		"sprite": "res://sprites/giant_pig.png",
		"size": Vector2(32, 32),
		"max_hp": 26,
		"coins": 6,
		"unlock_round": 4,
		"speed_scale": 1.0,
	},
}

const BOSS := {
	"sprite": "res://sprites/boss_rabbit.png",
	"size": Vector2(48, 48),
	"max_hp": 100,
	"coins": 50,
	"speed_scale": 0.5,
}


static func unlocked(round_number: int) -> Array:
	var pool := []
	for def in DEFS.values():
		if def.unlock_round <= round_number:
			pool.append(def)
	return pool
```

- [ ] **Step 4: Rebuild class cache, run harness to verify it passes**

```bash
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tools/tmp_harness.gd
```

Expected: `EnemyTypes OK`. (The `--import` is required — the new class_name was added outside the editor.)

- [ ] **Step 5: Delete the harness and commit**

```bash
rm tools/tmp_harness.gd
git add enemy_types.gd enemy_types.gd.uid
git commit -m "feat: EnemyTypes static data class (per-type hp/coins/size/unlock)"
```

(If Godot didn't generate `enemy_types.gd.uid` during `--import`, commit just the `.gd`.)

---

### Task 2: Placeholder sprites for the four new types

**Files:**
- Modify: `tools/make_placeholders.gd` (add four ASCII maps + four `_write` calls in `_init`)
- Create (generated): `sprites/pig.png`, `sprites/giant_rabbit.png`, `sprites/giant_pig.png`, `sprites/boss_rabbit.png` (+ their `.import` files)

**Interfaces:**
- Consumes: nothing.
- Produces: the four PNG paths referenced by `EnemyTypes.DEFS`/`BOSS` in Task 1. Dimensions: pig 24×24, giant_rabbit 32×32, giant_pig 32×32, boss_rabbit 48×48. All have `Palette.PURPLE` bodies (damage-shader requirement).

- [ ] **Step 1: Add the four ASCII maps to `tools/make_placeholders.gd`**

Insert after the `DROP` const (chars: `.` transparent, `B` black, `P` purple, `H` peach — every row in a map must be the same length; the tool asserts this):

```gdscript
const PIG := [
	"........................",
	"....BB............BB....",
	"...BPPB..........BPPB...",
	"...BPPB..........BPPB...",
	"..BBBBBBBBBBBBBBBBBBBB..",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPBBPPPPPPPPPPBBPPPB.",
	".BPPPBBPPPPPPPPPPBBPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPPPBHHHHHHHHBPPPPPB.",
	".BPPPPPBHHBHHBHHBPPPPPB.",
	".BPPPPPBHHBHHBHHBPPPPPB.",
	".BPPPPPBHHHHHHHHBPPPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	".BPPPPPPPPPPPPPPPPPPPPB.",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"..BBBBBBBBBBBBBBBBBBBB..",
	"....BPPB........BPPB....",
	"....BPPB........BPPB....",
	"....BBBB........BBBB....",
	"........................",
]

const GIANT_RABBIT := [
	"........BB............BB........",
	".......BPPB..........BPPB.......",
	".......BHHB..........BHHB.......",
	".......BHHB..........BHHB.......",
	".......BHHB..........BHHB.......",
	".......BHHB..........BHHB.......",
	".......BHHB..........BHHB.......",
	".......BPPB..........BPPB.......",
	".......BPPB..........BPPB.......",
	".....BBBBBBBBBBBBBBBBBBBBBB.....",
	"....BPPPPPPPPPPPPPPPPPPPPPPB....",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPBBPPPPPPPPPPPPBBPPPPB...",
	"...BPPPPBBPPPPPPPPPPPPBBPPPPB...",
	"...BPPPPPPPPPPHHHHPPPPPPPPPPB...",
	"...BPPPPPPPPPBPPPPBPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"....BPPPPPPPPPPPPPPPPPPPPPPB....",
	".....BBBBBBBBBBBBBBBBBBBBBB.....",
	"........BPPB......BPPB..........",
	"........BPPB......BPPB..........",
	"........BPPB......BPPB..........",
	"........BBBB......BBBB..........",
	"................................",
]

const GIANT_PIG := [
	"................................",
	".....BBBB..............BBBB.....",
	"....BPPPB..............BPPPB....",
	"....BPPPB..............BPPPB....",
	"...BBBBBBBBBBBBBBBBBBBBBBBBBB...",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPBBPPPPPPPPPPPPPPBBPPPPB..",
	"..BPPPPBBPPPPPPPPPPPPPPBBPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPBHHHHHHHHHHBPPPPPPPB..",
	"..BPPPPPPPBHHHBHHBHHHBPPPPPPPB..",
	"..BPPPPPPPBHHHBHHBHHHBPPPPPPPB..",
	"..BPPPPPPPBHHHHHHHHHHBPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPPPPPPPPPB..",
	"...BPPPPPPPPPPPPPPPPPPPPPPPPB...",
	"...BBBBBBBBBBBBBBBBBBBBBBBBBB...",
	"......BPPB..........BPPB........",
	"......BPPB..........BPPB........",
	"......BPPB..........BPPB........",
	"......BBBB..........BBBB........",
	"................................",
	"................................",
]

const BOSS_RABBIT := [
	"..........BBBBBBB..............BBBBBBB..........",
	"..........BBBBBBB..............BBBBBBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	"..........BBHHHBB..............BBHHHBB..........",
	".....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.....",
	".....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPHHHHPPPPPPPPPPPPPPHHHHPPPPPPBB.....",
	".....BBPPPPPPHHHHPPPPPPPPPPPPPPHHHHPPPPPPBB.....",
	".....BBPPPPPPHHHHPPPPPPPPPPPPPPHHHHPPPPPPBB.....",
	".....BBPPPPPPHHHHPPPPPPPPPPPPPPHHHHPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPHHHHHHPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPHHHHHHPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPBPPPPPPBPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPBB.....",
	".....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.....",
	".....BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.....",
	"...........BBPPBB............BBPPBB.............",
	"...........BBPPBB............BBPPBB.............",
	"...........BBPPBB............BBPPBB.............",
	"...........BBPPBB............BBPPBB.............",
	"...........BBBBBB............BBBBBB.............",
	"................................................",
]
```

(Boss has a 2-px outline and peach eyes — peach pixels stay peach under the damage shader, which only erodes purple; that's intended.)

And add to `_init()` after the `drop.png` line:

```gdscript
	_write("res://sprites/pig.png", PIG)
	_write("res://sprites/giant_rabbit.png", GIANT_RABBIT)
	_write("res://sprites/giant_pig.png", GIANT_PIG)
	_write("res://sprites/boss_rabbit.png", BOSS_RABBIT)
```

- [ ] **Step 2: Regenerate sprites**

```bash
"$GODOT" --headless --path . --script res://tools/make_placeholders.gd
```

Expected: `wrote res://sprites/pig.png` (and the other three) among the output, no assert failures (a ragged row aborts with "ragged row in …" — fix the map if so).

- [ ] **Step 3: Verify dimensions and trigger import**

```bash
sips -g pixelWidth -g pixelHeight sprites/pig.png sprites/giant_rabbit.png sprites/giant_pig.png sprites/boss_rabbit.png
"$GODOT" --headless --path . --import
```

Expected: 24×24, 32×32, 32×32, 48×48; import run exits clean and generates `sprites/*.import` for the four new files. Also eyeball the four PNGs (open them with Read — they're images) to confirm they look like a pig, two giants, and a boss rabbit, not garbage.

- [ ] **Step 4: Commit**

```bash
git add tools/make_placeholders.gd sprites/pig.png sprites/giant_rabbit.png sprites/giant_pig.png sprites/boss_rabbit.png sprites/*.import
git commit -m "feat: placeholder sprites for pig, giant rabbit, giant pig, boss rabbit"
```

---

### Task 3: Round counter + escalation state in `GameState`

**Files:**
- Modify: `game_state.gd`
- Test: `tools/tmp_harness.gd` (throwaway, deleted before commit)

**Interfaces:**
- Consumes: nothing new.
- Produces (on the `GameState` autoload): `var round_number: int` (starts 0), `var toughness_level: int` (starts 0), `var frenzy: bool` (starts false), `func advance_round() -> void`, `func hp_mult() -> float`, `func speed_mult() -> float`. Constants `FRENZY_CHANCE := 0.3`, `TOUGHNESS_HP_STEP := 0.2`, `FRENZY_SPEED_MULT := 1.5`, `ESCALATION_START_ROUND := 6`. Do NOT remove `enemy_max_hp`/`enemy_size` from `BASE_STATS` yet — `enemy.gd`/`main.gd` still read them until Task 4.

- [ ] **Step 1: Write the failing harness**

Create `tools/tmp_harness.gd`. Autoloads don't exist in bare `--script` runs, so load the script manually:

```gdscript
extends SceneTree
## Throwaway assertion harness for GameState round/escalation. Delete before commit.

func _init() -> void:
	var gs: Node = load("res://game_state.gd").new()
	# Rounds 1-5: no escalation ever.
	for i in 5:
		gs.advance_round()
		assert(gs.toughness_level == 0 and gs.frenzy == false, "no escalation before round 6")
	assert(gs.round_number == 5)
	assert(gs.hp_mult() == 1.0 and gs.speed_mult() == 1.0)
	# Rounds 6+: each round is either frenzy (toughness unchanged) or +1 toughness.
	seed(1)
	for i in 40:
		var before: int = gs.toughness_level
		gs.advance_round()
		if gs.frenzy:
			assert(gs.toughness_level == before, "frenzy round leaves toughness alone")
			assert(gs.speed_mult() == 1.5)
		else:
			assert(gs.toughness_level == before + 1, "tough round increments toughness")
			assert(gs.speed_mult() == 1.0)
		assert(is_equal_approx(gs.hp_mult(), 1.0 + 0.2 * gs.toughness_level))
	assert(gs.round_number == 45)
	assert(gs.toughness_level >= 1, "40 rolls at 70% must escalate at least once")
	gs.free()
	print("GameState escalation OK")
	quit()
```

- [ ] **Step 2: Run harness to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tools/tmp_harness.gd
```

Expected: FAIL — "Invalid call. Nonexistent function 'advance_round'".

- [ ] **Step 3: Implement in `game_state.gd`**

Add below the `FIRE_INTERVALS` const:

```gdscript
const FRENZY_CHANCE := 0.3
const TOUGHNESS_HP_STEP := 0.2
const FRENZY_SPEED_MULT := 1.5
const ESCALATION_START_ROUND := 6
```

Add below `var upgrade_levels := ...`:

```gdscript
var round_number: int = 0
var toughness_level: int = 0
var frenzy: bool = false
```

Add these functions after `add_currency`:

```gdscript
func advance_round() -> void:
	round_number += 1
	frenzy = false
	if round_number >= ESCALATION_START_ROUND:
		if randf() < FRENZY_CHANCE:
			frenzy = true
		else:
			toughness_level += 1


func hp_mult() -> float:
	return 1.0 + TOUGHNESS_HP_STEP * toughness_level


func speed_mult() -> float:
	return FRENZY_SPEED_MULT if frenzy else 1.0
```

Also update the file's docstring (top `##` comment) to mention it now also tracks the round number and escalation state (session-only, like currency).

- [ ] **Step 4: Run harness to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tools/tmp_harness.gd
```

Expected: `GameState escalation OK`.

- [ ] **Step 5: Delete the harness and commit**

```bash
rm tools/tmp_harness.gd
git add game_state.gd
git commit -m "feat: round counter and late-round escalation state in GameState"
```

---

### Task 4: `Enemy.setup()` — per-type sprite, size, HP, coins, speed

**Files:**
- Modify: `enemy.gd`, `main.gd`, `game_state.gd`

**Interfaces:**
- Consumes: `EnemyTypes.DEFS` def dictionaries (Task 1), `GameState.hp_mult()`/`speed_mult()` (Task 3).
- Produces: `Enemy.setup(def: Dictionary, hp_mult: float, speed_mult: float) -> void` (must be called before `add_child`; defaults to an unscaled rabbit if never called), `Enemy.coins: int`, signal `died(at_position: Vector2, coins: int)`, and `main.gd`'s `_spawn_enemy(def: Dictionary) -> void`. After this task the game still spawns only rabbits — behavior is identical to before, but everything flows through defs. `enemy_max_hp`/`enemy_size` are gone from `BASE_STATS`, and `COINS_PER_KILL` is gone from `main.gd`.

- [ ] **Step 1: Rewrite `enemy.gd`'s data plumbing**

Replace the signal, the `SPRITE` const, and the var block:

```gdscript
signal died(at_position: Vector2, coins: int)
```

Delete `const SPRITE := preload("res://sprites/enemy.png")`. Change the vars to:

```gdscript
var max_hp: int
var hp: int
var coins: int
var _def: Dictionary = EnemyTypes.DEFS.rabbit
var _speed_factor := 1.0
var _velocity := Vector2.ZERO
var _direction_time := 0.0
var _sprite: Sprite2D
var _hit_tween: Tween
```

Add `setup` above `_ready` and adjust `_ready`:

```gdscript
func setup(def: Dictionary, hp_mult: float, speed_mult: float) -> void:
	_def = def
	max_hp = ceili(def.max_hp * hp_mult)
	coins = ceili(def.coins * hp_mult)
	_speed_factor = def.speed_scale * speed_mult


func _ready() -> void:
	if max_hp == 0:  # setup() not called — default to an unscaled rabbit
		setup(EnemyTypes.DEFS.rabbit, 1.0, 1.0)
	hp = max_hp
	_sprite = Sprite2D.new()
	_sprite.texture = load(_def.sprite)
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	mat.set_shader_parameter("hp_ratio", 1.0)
	_sprite.material = mat
	add_child(_sprite)
	_roll_direction()
```

Update the three remaining readers:

```gdscript
func get_rect() -> Rect2:
	var size: Vector2 = _def.size
	return Rect2(global_position - size / 2.0, size)
```

In `_roll_direction()`:

```gdscript
	_velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(SPEED_MIN, SPEED_MAX) * _speed_factor
```

In `_bounce_off_edges()`, change the first line to `var half: Vector2 = _def.size / 2.0`.

In `take_damage()`, change the death emit to `died.emit(global_position, coins)`.

Update the class docstring: it's no longer "same size as the targeting area" — it renders whichever `EnemyTypes` def it was `setup()` with.

- [ ] **Step 2: Update `main.gd` to the new signatures (still rabbit-only)**

Delete `const DROP_OFFSET_MIN/MAX`? No — keep those. Delete only `const COINS_PER_KILL := 3`.

In `_ready()`, change the spawn timer wiring (needed because `_spawn_enemy` now takes an argument):

```gdscript
	spawn_timer.timeout.connect(_on_spawn_tick)
```

Replace `_spawn_enemy` and add `_on_spawn_tick`:

```gdscript
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
```

In `start_round()`, change the initial-spawn loop body to `_spawn_enemy(EnemyTypes.DEFS.rabbit)`.

Change `_on_enemy_died` to take and use the coin count (replace the `COINS_PER_KILL` uses):

```gdscript
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
```

- [ ] **Step 3: Remove the dead stats keys from `game_state.gd`**

Delete the `"enemy_size": Vector2(24, 24),` and `"enemy_max_hp": 10,` lines from `BASE_STATS`. Confirm nothing still reads them:

```bash
grep -rn "enemy_max_hp\|enemy_size" --include="*.gd" .
```

Expected: no matches outside `docs/`.

- [ ] **Step 4: Smoke run**

```bash
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --quit-after 300
```

Expected: boots clean, no script errors (mouse at 0,0 in headless is normal). Behavior is unchanged rabbit gameplay — same HP (10), same 3 drops per kill.

- [ ] **Step 5: Commit**

```bash
git add enemy.gd main.gd game_state.gd
git commit -m "refactor: enemies configured from EnemyTypes defs via setup()"
```

---

### Task 5: Spawn pool, boss rounds, cap, adaptive rate

**Files:**
- Modify: `main.gd`

**Interfaces:**
- Consumes: `EnemyTypes.unlocked()`, `EnemyTypes.BOSS`, `GameState.advance_round()`/`round_number` (Tasks 1, 3), `_spawn_enemy(def)` (Task 4).
- Produces: the full spawning behavior — uniform pool pick, one boss on rounds 5/10/15…, `MAX_ENEMIES := 20` cap, adaptive interval (`FAST_SPAWN_INTERVAL := 0.5` below `LOW_ENEMIES := 6`, else `stats.spawn_interval`). Also: `GameState.advance_round()` is now called at the top of `start_round()` — Task 6's splash relies on that.

- [ ] **Step 1: Implement in `main.gd`**

Add constants next to the drop-offset consts:

```gdscript
const MAX_ENEMIES := 20
const LOW_ENEMIES := 6
const FAST_SPAWN_INTERVAL := 0.5
```

Replace `start_round()`:

```gdscript
func start_round() -> void:
	GameState.advance_round()
	for child in enemies.get_children() + pickups.get_children() + effects.get_children():
		child.queue_free()
	for i in GameState.stats.initial_enemies:
		_spawn_enemy(_pick_type())
	if GameState.round_number % 5 == 0:
		_spawn_enemy(EnemyTypes.BOSS)
	round_timer.start(GameState.stats.round_duration)
	spawn_timer.start(GameState.stats.spawn_interval)
	targeting_area.set_firing(true)
```

Replace `_on_spawn_tick()` (rabbit-only stub from Task 4). Note `spawn_timer.start(...)` rather than setting `wait_time` — a running Timer ignores `wait_time` changes until restarted:

```gdscript
func _on_spawn_tick() -> void:
	# queue_free'd children linger until end of frame, so count real ones.
	var alive := 0
	for enemy in enemies.get_children():
		if not enemy.is_queued_for_deletion():
			alive += 1
	if alive < MAX_ENEMIES:
		_spawn_enemy(_pick_type())
		alive += 1
	spawn_timer.start(FAST_SPAWN_INTERVAL if alive < LOW_ENEMIES else GameState.stats.spawn_interval)


func _pick_type() -> Dictionary:
	return EnemyTypes.unlocked(GameState.round_number).pick_random()
```

Update `main.gd`'s docstring to mention per-round enemy pools, boss rounds, and the adaptive spawn cap.

- [ ] **Step 2: Smoke run**

```bash
"$GODOT" --headless --path . --quit-after 300
```

Expected: boots clean. Round 1 spawns 10 rabbits and refills at 0.5 s while below 6 on screen (all rabbits die slowly in headless since the reticle sits in the corner, so mostly this verifies no crashes).

- [ ] **Step 3: Manual logic check via a fast-round playthrough (optional but cheap)**

Run windowed and play two rounds to confirm: round 2 visibly contains pigs, kills of pigs drop 4 coins, screen refills quickly after a sweep, and never floods past ~20 enemies:

```bash
"$GODOT" --path .
```

If the user isn't available to play, at minimum confirm in code review that `_pick_type` filters by `GameState.round_number` (which is 1 during the first round because `advance_round()` runs before spawning).

- [ ] **Step 4: Commit**

```bash
git add main.gd
git commit -m "feat: per-round spawn pool, boss rounds, enemy cap, adaptive spawn rate"
```

---

### Task 6: "ROUND N" splash

**Files:**
- Modify: `main.tscn`, `main.gd`

**Interfaces:**
- Consumes: `GameState.round_number` (already advanced by `start_round()`, Task 5).
- Produces: `$HUD/RoundLabel` (hidden by default) and `main.gd`'s `_show_round_splash() -> void` called from `start_round()`.

- [ ] **Step 1: Add the label to `main.tscn`**

Append after the `CurrencyLabel` node (font size 32 = 4×8; color is the `Palette.BLACK` literal used by the other labels; Labels ignore mouse by default so no `mouse_filter` needed; `anchors_preset = 8` is center):

```
[node name="RoundLabel" type="Label" parent="HUD"]
visible = false
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -128.0
offset_top = -16.0
offset_right = 128.0
offset_bottom = 16.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0.0392157, 0.0352941, 0.0705882, 1)
theme_override_fonts/font = ExtResource("3")
theme_override_font_sizes/font_size = 32
text = "ROUND 1"
horizontal_alignment = 1
vertical_alignment = 1
```

- [ ] **Step 2: Wire it up in `main.gd`**

Add constants next to the spawn consts:

```gdscript
const SPLASH_HOLD := 0.8
const SPLASH_FADE := 0.4
```

Add to the `@onready` block:

```gdscript
@onready var round_label: Label = $HUD/RoundLabel
```

Add a var next to the other members: `var _splash_tween: Tween`.

Add the function and call it from `start_round()` right after the spawn block (before `round_timer.start`):

```gdscript
func _show_round_splash() -> void:
	round_label.text = "ROUND %d" % GameState.round_number
	round_label.modulate.a = 1.0
	round_label.visible = true
	if _splash_tween:
		_splash_tween.kill()
	_splash_tween = create_tween()
	_splash_tween.tween_interval(SPLASH_HOLD)
	_splash_tween.tween_property(round_label, "modulate:a", 0.0, SPLASH_FADE)
	_splash_tween.tween_callback(func() -> void: round_label.visible = false)
```

The tween is owned by `Main` (not the label), and the label is a permanent HUD child, so there's no freed-node race; a restart mid-fade just kills and replays it.

- [ ] **Step 3: Smoke run**

```bash
"$GODOT" --headless --path . --quit-after 300
```

Expected: boots clean, no "Node not found: RoundLabel".

- [ ] **Step 4: Commit**

```bash
git add main.tscn main.gd
git commit -m "feat: ROUND N splash at round start"
```

---

### Task 7: Integration verification + docs

**Files:**
- Modify: `CLAUDE.md`
- Test: `tools/tmp_harness.gd` (throwaway, deleted before commit)

**Interfaces:**
- Consumes: everything above.
- Produces: verified integration + updated project docs. No behavior changes.

- [ ] **Step 1: Integration harness**

Create `tools/tmp_harness.gd` — boots the real `main.tscn` inside the running game (autoloads present because this drives the normal game boot, not a bare script; we use `--quit-after` instead of a SceneTree script). Simpler and sufficient: assert the pure seams end-to-end instead. Create:

```gdscript
extends SceneTree
## Throwaway integration harness. Delete before commit.

func _init() -> void:
	var gs: Node = load("res://game_state.gd").new()
	# Simulate 10 rounds; check pool composition and boss cadence per round.
	for i in 10:
		gs.advance_round()
		var pool: Array = EnemyTypes.unlocked(gs.round_number)
		var expected_pool: int = mini(gs.round_number, 4)
		assert(pool.size() == expected_pool, "round %d pool size" % gs.round_number)
		var boss_round: bool = gs.round_number % 5 == 0
		assert(boss_round == (gs.round_number in [5, 10]), "boss cadence")
	# Scaled enemy values: a level-2-toughness pig has hp 23 (ceil 22.4) and 6 coins (ceil 5.6).
	var e: Node2D = Enemy.new()
	e.setup(EnemyTypes.DEFS.pig, 1.4, 1.0)
	assert(e.max_hp == 23, "scaled pig hp, got %d" % e.max_hp)
	assert(e.coins == 6, "scaled pig coins, got %d" % e.coins)
	e.free()
	# Boss def flows through the same seam.
	var b: Node2D = Enemy.new()
	b.setup(EnemyTypes.BOSS, 1.0, 1.0)
	assert(b.max_hp == 100 and b.coins == 50)
	assert(b.get_rect().size == Vector2(48, 48))
	b.free()
	gs.free()
	print("Integration OK")
	quit()
```

Run:

```bash
"$GODOT" --headless --path . --script res://tools/tmp_harness.gd
```

Expected: `Integration OK`. (Note: `Enemy.new()` without `add_child` never runs `_ready`, so no sprite/GameState access happens — `setup` and `get_rect` are safe to call bare.)

- [ ] **Step 2: Full smoke run**

```bash
"$GODOT" --headless --path . --quit-after 600
```

Expected: clean boot, zero script errors over ~10 s.

- [ ] **Step 3: Update `CLAUDE.md`**

- Project Overview: add the enemy-progression slice to the "implemented" list and add the spec path `docs/superpowers/specs/2026-08-19-enemy-progression-design.md`.
- Architecture, `game_state.gd` bullet: remove `enemy_size`/`enemy_max_hp` from the stats-key list; add that it also tracks `round_number`, `toughness_level`, `frenzy` (session-only) with `advance_round()`/`hp_mult()`/`speed_mult()`.
- Architecture, add a bullet after `upgrades.gd`:
  > `enemy_types.gd` (`class_name EnemyTypes`) — static `DEFS` per-type data (sprite, size, max_hp, coins, unlock_round, speed_scale) plus `BOSS`; the spawn pool is `unlocked(round_number)`, the boss spawns once at the start of every 5th round. Per-type `coins` is the drop count; each drop is still worth `stats.currency_per_kill`.
- Architecture, `main.gd` bullet: mention the ROUND splash, uniform pool pick, `MAX_ENEMIES` 20 cap, and adaptive interval (0.5 s under 6 enemies).
- Architecture, `enemy.gd` bullet: sized/HP'd/paid via `setup(def, hp_mult, speed_mult)` (must precede `add_child`); `died(at_position, coins)`.
- Visual identity sprite list: add pig 24×24, giant_rabbit/giant_pig 32×32, boss_rabbit 48×48.
- Next slice: remove "balancing" phrasing that's now stale only if it conflicts; keep balancing listed — the 20 %/frenzy numbers are explicitly first guesses.

- [ ] **Step 4: Delete harness and commit**

```bash
rm tools/tmp_harness.gd
git add CLAUDE.md
git commit -m "docs: record enemy progression architecture in CLAUDE.md"
```

- [ ] **Step 5: Playtest handoff**

Ask the user to playtest windowed (`"$GODOT" --path .`), checking: splash timing/size, pig round pacing, giant readability at 32×32, boss feel on round 5 (slow, meaty, 50-coin burst), refill speed after sweeps, and that the screen never floods. Playtest feedback that changes numbers goes to `EnemyTypes.DEFS`/`GameState` constants and the spec gets updated per project convention.

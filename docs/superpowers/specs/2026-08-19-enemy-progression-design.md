# Enemy Progression — Design

Date: 2026-08-19
Status: approved (brainstormed and approved in session)

## Goal

Give rounds a reason to differ: each early round introduces a new, tougher,
better-paying enemy type (keeping all previous types), every 5th round adds a
boss, and rounds past 5 keep escalating (tougher or occasionally faster
enemies). A "ROUND N" splash announces each round. Spawning becomes adaptive —
fast refill when the screen is empty, hard cap so it never floods.

## Round tracking & splash

- `GameState.round_number: int` — starts at 0, incremented at the top of
  `main.gd start_round()`, so the first round is 1. Session-only (resets on
  quit, like `currency`).
- On round start, a **splash label** on the HUD `CanvasLayer` shows
  `"ROUND %d"`: centered on screen, Press Start 2P, size 32, `Palette.BLACK`,
  full alpha for 0.8 s then fading to 0 over 0.4 s (tween on `modulate:a`).
  Gameplay runs underneath — no pause, no input blocking
  (`mouse_filter = IGNORE`). The label is a permanent HUD child (hidden when
  not splashing), so it hides with the HUD on round over and no cleanup race
  exists; restarting a round just rewinds the tween.

## Enemy type data — `enemy_types.gd` (new, `class_name EnemyTypes`)

Pure static data, mirroring the `Upgrades.DEFS` pattern. Per-type tunables
move here from the global stats dictionary; **`enemy_max_hp` and `enemy_size`
leave `GameState.BASE_STATS`**, and `main.gd`'s `COINS_PER_KILL` becomes the
per-type `coins` (the number of drop sprites a kill pops out; each drop is
still worth `stats.currency_per_kill`, which stays upgrade-tunable).

```gdscript
const DEFS := {
    "rabbit": {
        "sprite": "res://sprites/enemy.png",
        "size": Vector2(24, 24),
        "max_hp": 10,
        "coins": 3,
        "unlock_round": 1,
        "speed_scale": 1.0,
    },
    "pig":          { sprite pig.png,          size 24×24, hp 16,  coins 4,  unlock 2, speed 1.0 },
    "giant_rabbit": { sprite giant_rabbit.png, size 32×32, hp 20,  coins 5,  unlock 3, speed 1.0 },
    "giant_pig":    { sprite giant_pig.png,    size 32×32, hp 26,  coins 6,  unlock 4, speed 1.0 },
}

const BOSS := {
    "sprite": "res://sprites/boss_rabbit.png",
    "size": Vector2(48, 48),
    "max_hp": 100,
    "coins": 50,
    "speed_scale": 0.5,
}
```

(Shorthand rows above are illustrative — the real file writes each entry in
full.) The boss lives outside `DEFS` so the random spawn pool is simply
"DEFS entries with `unlock_round <= round_number`" with no filtering flag.

## `enemy.gd` changes

- New `func setup(def: Dictionary, hp_mult: float, speed_mult: float)`,
  called by `main.gd` **before** `add_child`. Stores per-instance:
  `_def` (for sprite + size), `max_hp = ceili(def.max_hp * hp_mult)`,
  `coins = ceili(def.coins * hp_mult)`, and a speed factor
  `def.speed_scale * speed_mult` applied to the existing
  `SPEED_MIN/SPEED_MAX` roll.
- `_ready()` loads the sprite from `_def.sprite` instead of the hard-coded
  `SPRITE` constant; `get_rect()` and `_bounce_off_edges()` use `_def.size`
  instead of `stats.enemy_size`.
- `died` becomes `died(at_position: Vector2, coins: int)` so `main.gd` no
  longer owns the coin count.
- The damage shader path is unchanged — all new sprites keep
  `Palette.PURPLE` bodies, so `hp_ratio` erosion works for every type.

## Spawning — `main.gd`

- **Pool pick**: each spawn chooses uniformly among unlocked regular types
  (`EnemyTypes.DEFS` filtered by `unlock_round <= GameState.round_number`).
  `stats.initial_enemies` initial spawns use the same pick.
- **Boss rounds**: when `round_number % 5 == 0`, exactly one boss is
  additionally spawned at round start (never from the timer pool).
- **Cap**: `const MAX_ENEMIES := 20` — a spawn tick with
  `enemies.get_child_count() >= MAX_ENEMIES` does nothing (timer keeps
  ticking).
- **Adaptive rate**: after every spawn tick, the next interval is chosen:
  fewer than `LOW_ENEMIES := 6` on screen → `FAST_SPAWN_INTERVAL := 0.5` s,
  otherwise `stats.spawn_interval` (2 s, still upgrade-tunable). A cleared
  screen refills fast; a busy screen stays bounded.
- Spawn position margins use the picked type's own size (boss margins are
  bigger), keeping the whole sprite on screen.

## Late-round scaling (round 6+)

Escalation state lives in `GameState` next to `round_number` (session-only):

- `toughness_level: int` (starts 0) and `frenzy: bool` (per-round).
- At each round start with `round_number >= 6`: roll once — **30 % chance of
  a frenzy round** (`frenzy = true`, enemies move ×1.5 for this round,
  toughness unchanged), otherwise `toughness_level += 1`.
- `hp_mult = 1.0 + 0.2 * toughness_level` — applied to every spawn's HP
  **and coins** (reward tracks difficulty), including the boss on rounds
  10, 15, …
- `speed_mult = 1.5 if frenzy else 1.0` — applied on top of the type's own
  `speed_scale`.
- Rounds 1–5 always have `hp_mult = speed_mult = 1.0`.

## Sprites (added to `tools/make_placeholders.gd`)

Four new ASCII pixel maps, palette-only, transparent background, authored at
1:1 base-resolution scale, `Palette.PURPLE` body (shader requirement):

- `pig.png` 24×24 — round purple body, peach snout, small ears.
- `giant_rabbit.png` 32×32 — scaled-up rabbit silhouette (taller ears).
- `giant_pig.png` 32×32 — scaled-up pig silhouette.
- `boss_rabbit.png` 48×48 — big rabbit, heavier black outline, peach eyes.

Same hot-swap rule as existing sprites: keep file names to replace with real
art later.

## Edge cases

- **Cap reached**: tick is a no-op; no queue builds up.
- **Boss alive at round end**: the defensive clear in
  `start_round()`/`_on_round_over()` already frees everything in `Enemies`;
  no carryover, no partial-HP memory.
- **50 boss drops**: 50 four-pixel sprites popping in a circle is within
  performance budget; the existing angle-splitting loop generalizes to any
  coin count (thirds → fiftieths).
- **Kills after the timer ends** already return early in `_on_enemy_died`;
  signature change keeps that guard.
- **Restart during splash**: label is a persistent HUD child; starting a new
  round rewinds/replays its tween — no dangling tween on a freed node.

## Testing

No test framework (by design). Verification:

- Headless smoke run (`--quit-after 300`) boots clean.
- Throwaway harness (deleted after the run): assert the unlock pool per
  round (R1 rabbit only … R4 all four), boss presence exactly on rounds
  5/10, cap behavior at 20, and scaled HP/coin values for sample toughness
  levels (e.g. level 2 pig → hp 23, coins 6).
- User playtest for pacing, splash readability, and boss feel.

## Out of scope

- Save/load persistence (unchanged future slice).
- Fine balancing of the escalation curve against upgrade progression — the
  20 %/round and frenzy numbers are first guesses for the balancing slice.
- Per-type movement behaviors (everything wanders identically; the boss is
  just slower).
- Sound, boss health bar, round-transition effects beyond the splash.

# Ultra Kill — Core Round Loop Design

Date: 2026-08-18
Status: Approved (chat) — pending spec review

## Overview

An incremental game in Godot 4.5 (2D). The player controls a semi-transparent
targeting rectangle with the mouse. The rectangle auto-fires on a timer,
damaging every enemy rectangle it overlaps. Dead enemies drop currency
rectangles collected by sweeping the targeting area over them. Rounds last
30 seconds; the long-term loop is: round → kill → collect → round over →
level-up screen (later) → spend currency → next round. This spec covers the
first playable slice: round → kill → collect → round over → restart button.

## Decisions Made

- **Hit rule:** any overlap between enemy rect and targeting rect counts.
  One shot damages *all* overlapping enemies. Enemies do not collide with
  each other, so several can be hit by a single shot.
- **Currency:** persists across rounds (restart keeps the total). It will be
  the upgrade resource later.
- **Round end:** surviving enemies and uncollected drops are cleared;
  only collected currency counts.
- **Collision tech:** plain `Rect2` intersection math, not physics Areas.
  All shapes are axis-aligned rectangles with no physics response needed;
  edge bouncing is a manual position check. Nodes are lightweight `Node2D`s
  drawn with `_draw`.

## Components

### `game_state.gd` (autoload `GameState`)

The upgrade-ready core. Holds:

- `currency: int` — persistent across rounds.
- `stats` dictionary — every value future upgrades touch:
  - `fire_interval = 1.0` (seconds between shots)
  - `damage = 2` (HP per shot)
  - `target_size = Vector2(100, 100)` (targeting rectangle size; enemies use
    the same size for now; window runs at 1920×1080 per playtest feedback)
  - `round_duration = 30.0`
  - `spawn_interval = 2.0` (one new enemy per interval)
  - `enemy_max_hp = 10`
  - `initial_enemies = 10`
  - `currency_per_kill = 1`

All gameplay code reads from `GameState.stats`; the future level-up screen
only mutates these values between rounds.

### `main.tscn` / `main.gd` (root scene)

Owns the round lifecycle:

- Round timer (counts down from `round_duration`), spawn timer.
- `Enemies` and `Pickups` plain container nodes — round cleanup frees all
  their children.
- On round start: reset timer, spawn `initial_enemies` enemies at random
  positions inside the viewport.
- On spawn timer timeout: spawn one enemy.
- On round timer end: stop timers, clear containers, show Round Over panel.
- Restart button starts a new round (currency untouched).

### `targeting_area.gd` (Node2D, custom `_draw`)

- Follows the mouse each frame (centered on cursor).
- Own fire timer at `stats.fire_interval`. On fire: emit `fired(rect: Rect2)`
  and flash (brighter fill for ~0.1 s, via a short timer or tween).
- Semi-transparent rectangle; flash is a color/alpha change in `_draw`.
- Also reports its current rect each frame for currency pickup overlap.

### `enemy.gd` (Node2D, custom `_draw`)

- HP starts at `stats.enemy_max_hp`; takes `stats.damage` per hit.
- Visual: light-red full-size rect (depleted life) with a dark-red rect
  drawn on top, anchored to the right edge, whose *width* is
  `full_width * hp / max_hp` — damage eats the dark red from left to
  right; at full HP fully dark red, at 0 HP fully light red.
- At HP ≤ 0: emit `died(position)`, then `queue_free()`.
- Movement: random direction unit vector × constant speed; bounces off the
  viewport edges (position clamp + velocity component flip); re-rolls
  direction every 1–3 s (random per-enemy timer) so paths feel random.
- No enemy-enemy collision.

### `currency_drop.gd` (Node2D, custom `_draw`)

- Small rectangle that pops out of a dead enemy: spawns at the death
  position and tweens (~0.2 s) to a random point 40–120 px away, clamped
  to the viewport (kills happen under the reticle, so spawning in place
  would instantly auto-collect).
- Not collectable until the pop finishes. Then, each frame, if its rect
  intersects the targeting rect: add `stats.currency_per_kill` worth to
  `GameState.currency`, `queue_free()`.

### HUD (CanvasLayer in `main.tscn`)

- Countdown label, top-center (whole seconds remaining).
- Currency label, top-right.
- Hidden Round Over panel with a Restart button.

## Data Flow

1. `targeting_area` fires → emits `fired(rect)`.
2. `main` (or the enemies container) forwards the rect to all live enemies;
   each enemy checks `rect.intersects(my_rect)` and applies damage.
3. Enemy death → `died(position)` → `main` spawns a `currency_drop` there
   and grants nothing yet (currency comes from pickup, not the kill itself).
4. Drop overlap with targeting rect → `GameState.currency += value` → HUD
   updates (HUD reads/binds to GameState via signal `currency_changed`).

## Error Handling

Minimal by design: spawn positions are clamped inside the viewport; enemy
rects are clamped to the playable area every frame; timers are stopped
before clearing containers so no callback touches freed nodes.

## Testing

Manual playtest from the editor. Rect intersection / HP / color-proportion
logic is kept in small pure functions on their scripts so a GUT test suite
can cover them later; no test framework is added in this slice.

## Out of Scope (later slices)

Level-up screen, upgrades, enemy variety, currency value tiers, sounds,
juice/polish, difficulty scaling across rounds.

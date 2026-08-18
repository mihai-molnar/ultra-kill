# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"ultra kill" is a small incremental game in Godot 4.5 (Forward Plus renderer), hosted at https://github.com/mihai-molnar/ultra-kill (branch `master`). The player controls a mouse-following, auto-firing targeting rectangle that damages overlapping enemy rectangles; kills pop out currency drops collected by sweeping over them. Rounds last 30 seconds; the intended long-term loop is round → kill → collect → round over → level-up screen (spend currency on upgrades) → next round.

The first slice (core round loop with restart) is implemented, playtested, and merged. Design spec: `docs/superpowers/specs/2026-08-18-round-loop-design.md` (executed plan alongside it in `docs/superpowers/plans/`).

## Architecture

All gameplay objects are lightweight `Node2D`s drawn via `_draw`, with plain `Rect2.intersects` math — no physics nodes anywhere. Window runs at 1920×1080.

- `game_state.gd` — autoload `GameState`: persistent `currency` plus the `stats` dictionary (fire_interval, damage, target_size, round_duration, spawn_interval, enemy_max_hp, initial_enemies, currency_per_kill). **This is the upgrade seam**: all gameplay reads tunables from `GameState.stats` at point of use, so a future level-up screen only mutates stats between `_on_round_over` and `start_round` — never hard-code a value that has a stats key.
- `main.gd` / `main.tscn` — owns the round lifecycle: spawning into the `Enemies`/`Pickups` container nodes, routing `fired(rect)` to enemies, countdown + currency HUD (CanvasLayer), round-over panel with Restart. Node order matters: `TargetingArea` is deliberately last among Node2Ds so it draws on top.
- `enemy.gd` (`class_name Enemy`) — wanders (random velocity, re-rolled every 1–3 s), bounces off viewport edges, uses `global_position` consistently. HP bar: light-red base with right-anchored dark-red bar, so damage eats dark red left → right. Emits `died(at_position)` before `queue_free()`.
- `targeting_area.gd` (`class_name TargetingArea`) — follows mouse, fire timer emits `fired(rect: Rect2)`, ~0.1 s flash; firing is started/stopped only via `set_firing(bool)` from main.
- `currency_drop.gd` (`class_name CurrencyDrop`) — pops out (0.2 s tween) to a random point 40–120 px from the kill, and is only collectable after the pop (kills happen under the reticle, so in-place drops would auto-collect).

## Visual identity

- **The game uses exactly four colors — never introduce any other color.** They are defined once in `palette.gd` (`class_name Palette`); always reference `Palette.*`, never inline color literals in scripts (alpha variants of the palette colors are allowed, e.g. the reticle fill). In `.tscn`/`project.godot` (where scripts can't be referenced) use the same values verbatim.
  - `Palette.BLACK` `#0a0912` — edges and borders (also HUD text)
  - `Palette.PURPLE` `#70579c` — enemies (the remaining-HP portion)
  - `Palette.PEACH` `#e096a8` — hit enemies (the damage-revealed portion; also currency drops)
  - `Palette.WHITE` `#fff1eb` — background
- UI font: Russo One (`fonts/RussoOne-Regular.ttf`, SIL OFL — license alongside it). All labels/buttons should use it via `theme_override_fonts/font`.

## Next slice / known deferred work

- Next planned feature: the level-up screen (spend currency between rounds by mutating `GameState.stats`).
- Before a targeting-area size upgrade: split `stats.target_size` into target vs. `enemy_size` — enemies currently share the target's size constant.
- When `start_round()` becomes reachable from an upgrade screen: give it a defensive clear (or assert) on the `Enemies`/`Pickups` containers.
- Deferred minors (reviewed, agreed non-blocking): redundant per-frame `queue_redraw()` in enemy/targeting area (a future fix must still redraw on the flash-off edge); `is_instance_valid` would be the more idiomatic guard in `currency_drop.gd`.

## Working with Godot

- Godot 4.5.1 binary: `/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot` (quote the path — it has a space).
- Run the game: `"$GODOT" --path "/Users/mihai/Godot games/ultra-kill"`
- Headless smoke run (the real automated check — there is no test framework yet, by design): `"$GODOT" --headless --path . --quit-after 300` (mouse sits at 0,0 in headless — targeting area in the corner is expected).
- If a smoke run fails with "Could not find type"/"Identifier not declared" errors for class_names that clearly exist, the `.godot` class cache is stale (fresh clone, or scripts added outside the editor): rebuild it with `"$GODOT" --headless --path . --import`, then re-run.
- Static-check a script: `"$GODOT" --headless --path . --check-only --script res://<file>.gd` — but it cannot resolve autoloads or cross-file class_names and always exits 0; treat "Identifier not found: GameState" / "Could not find type" there as spurious. Syntax errors it reports are real.
- The `.godot/` directory is editor-generated cache — never edit or commit it (gitignored, as is `.claude/`).
- `project.godot` is the project configuration file; prefer editing it via the Godot editor, but small direct edits are fine.
- Scene files (`.tscn`) and resource files (`.tres`) are text-based and diffable; `.import` files are auto-generated metadata for assets. Commit Godot-generated `.uid` sidecars; `main.tscn` will gain `uid=` attributes on first editor save — commit that rewrite too.

## Conventions

- Scripts are written in GDScript (`.gd`); snake_case for file names, functions, and variables; PascalCase for node names and class names.
- Design specs go in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/` — update the spec when playtest feedback changes behavior (this has been done for the first slice).

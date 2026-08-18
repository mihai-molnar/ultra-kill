# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"ultra kill" is a small incremental game in Godot 4.5 (Forward Plus renderer), hosted at https://github.com/mihai-molnar/ultra-kill (branch `master`). The player controls a mouse-following, auto-firing targeting rectangle that damages overlapping enemy rectangles; kills pop out currency drops collected by sweeping over them. Rounds last 30 seconds; the loop is round → kill → collect → upgrade tree (spend currency on upgrades) → next round.

The first slice (core round loop with restart) is implemented, playtested, and merged, the pixel-art visual pass is implemented, and the upgrade tree is implemented. Design specs: `docs/superpowers/specs/2026-08-18-round-loop-design.md`, `docs/superpowers/specs/2026-08-18-pixel-art-feel-design.md`, and `docs/superpowers/specs/2026-08-18-upgrade-tree-design.md` (executed plans alongside them in `docs/superpowers/plans/`).

## Architecture

All gameplay objects are lightweight `Node2D`s with plain `Rect2.intersects` math — no physics nodes anywhere. The game renders at a **480×270 base resolution** integer-scaled ×4 into a 1920×1080 window (`canvas_items` stretch + nearest filtering + `snap_2d_transforms_to_pixel`), so **all world coordinates/sizes/speeds are in 480×270 units** while fonts stay sharp at window resolution. Enemies and drops are `Sprite2D`s (assets in `sprites/`); the targeting area is procedural `_draw`.

- `game_state.gd` — autoload `GameState`: persistent `currency` plus the `stats` dictionary (fire_interval, damage, target_size, enemy_size, round_duration, spawn_interval, enemy_max_hp, initial_enemies, currency_per_kill), always recomputed from `BASE_STATS` + `upgrade_levels` by `buy_upgrade()`/`_recompute_stats()` (idempotent, no drift). **This is the upgrade seam**: all gameplay reads tunables from `GameState.stats` at point of use; the upgrade tree mutates `upgrade_levels` between `_on_round_over` and `start_round` — never hard-code a value that has a stats key.
- `upgrades.gd` (`class_name Upgrades`) — static `DEFS` dictionary keyed by upgrade id (name, description, icon path, `costs` array whose length is that upgrade's max level and pip count); effect formulas live in `GameState._recompute_stats`, not here.
- `upgrade_tree.gd` / `upgrade_tree.tscn` — full-screen between-rounds `Control` mounted on the `Screens` CanvasLayer; draws the hub square and the hub-to-node connector lines itself, builds the three `UpgradeNode`s from `NODE_POSITIONS` in code, and emits `start_pressed` when the player clicks Start Round.
- `upgrade_node.gd` (`class_name UpgradeNode`) — one square upgrade node with an icon and one 4×4 level pip per level (peach = owned); click buys the next level via `GameState.buy_upgrade`. Hover shows a palette-styled tooltip built in `_make_custom_tooltip` (Godot's default tooltip theme is off-palette).
- `main.gd` / `main.tscn` — owns the round lifecycle: spawning into the `Enemies`/`Pickups`/`Effects` container nodes (`start_round()` clears them defensively before every round), routing `fired(rect)` to enemies, countdown + currency HUD (CanvasLayer). Round over hides the HUD and the reticle and mounts `upgrade_tree.tscn` onto `Screens`; pressing Start Round frees the tree and resumes. Cursor rules: the OS cursor is hidden during rounds (`Input.MOUSE_MODE_HIDDEN` — the reticle is the pointer) and shown as the pixel-art cursor (`sprites/cursor.png`, hotspot `(0,0)`) on the upgrade screen. Node order matters: `TargetingArea` is deliberately last among Node2Ds so it draws on top.
- `enemy.gd` (`class_name Enemy`) — wanders (random velocity, re-rolled every 1–3 s), bounces off viewport edges, uses `global_position` consistently, sized from `stats.enemy_size` (independent of the reticle's `stats.target_size`, so a size upgrade doesn't resize enemies). Damage is shown by `shaders/enemy_damage.gdshader` (`hp_ratio` uniform, set in `take_damage`): the purple body erodes to peach left → right; fully peach = dead. Emits `died(at_position)` before `queue_free()`.
- `targeting_area.gd` (`class_name TargetingArea`) — follows mouse, fire timer emits `fired(rect: Rect2)`, ~0.1 s flash; firing is started/stopped only via `set_firing(bool)` from main.
- `currency_drop.gd` (`class_name CurrencyDrop`) — pops out (0.2 s tween) to a random point 10–30 px from the kill, and is only collectable after the pop (kills happen under the reticle, so in-place drops would auto-collect).

## Visual identity

- **The game uses exactly four colors — never introduce any other color.** They are defined once in `palette.gd` (`class_name Palette`); always reference `Palette.*`, never inline color literals in scripts (alpha variants of the palette colors are allowed, e.g. the reticle fill). In `.tscn`/`project.godot` (where scripts can't be referenced) use the same values verbatim.
  - `Palette.BLACK` `#0a0912` — edges and borders (also HUD text)
  - `Palette.PURPLE` `#70579c` — enemies (the remaining-HP portion)
  - `Palette.PEACH` `#e096a8` — hit enemies (the damage-revealed portion; also currency drops)
  - `Palette.WHITE` `#fff1eb` — background
- UI font: Press Start 2P (`fonts/PressStart2P-Regular.ttf`, SIL OFL — license alongside it), antialiasing off, sizes in multiples of 8. All labels/buttons use it via `theme_override_fonts/font`.
- Sprite assets (`sprites/`): PNG with transparent background, authored at 1:1 base-resolution scale (no pre-upscaling), exactly the four palette colors, enemy 24×24 / drop 4×4 / upgrade icons 16×16 (`icon_dmg`, `icon_size`, `icon_speed`, `icon_hub`), same file names to hot-swap. Enemy art must keep `Palette.PURPLE` as the body color so the damage shader can find it. Exception: `sprites/cursor.png` is pre-upscaled ×4 to 32×32, because OS cursors render at window resolution, not the 480×270 canvas. Placeholders are regenerated by `"$GODOT" --headless --path . --script res://tools/make_placeholders.gd`.

## Next slice / known deferred work

- Plausible next slices: save/load persistence for `currency` and `upgrade_levels` across sessions, balancing round difficulty (spawn rate, enemy HP) against upgraded stats so later rounds stay challenging, deeper upgrade-tree tiers beyond the current 3-level pips.
- Deferred minors (reviewed, agreed non-blocking): `enemy.gd` no longer has a redundant per-frame `queue_redraw()` or a `_draw` HP bar (both removed with the sprite/shader switch); `targeting_area.gd` still redraws every frame (a future fix must still redraw on the flash-off edge); `is_instance_valid` would be the more idiomatic guard in `currency_drop.gd`.

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

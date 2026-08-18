# Upgrade Tree — Design

Date: 2026-08-18
Status: approved (brainstormed and section-approved in session)

## Goal

Close the core loop: round → kill → collect → **upgrade tree** → next round.
When a round ends, a full-screen upgrade tree replaces the old Round Over
panel. The player spends gold on three upgrades (DMG, SIZE, SPEED), each with
three levels, then starts the next round. Session-only persistence: gold and
upgrade levels reset when the game closes (save files are a future slice).

## Flow

1. `RoundTimer` fires → `main.gd` `_on_round_over()`: stop spawn timer, stop
   firing, clear `Enemies`/`Pickups`/`Effects` (as today), hide
   `TargetingArea`, show the OS cursor using the custom pixel-art cursor,
   instantiate `upgrade_tree.tscn` and add it as a child of `Main`.
2. The player buys upgrades by clicking nodes (instant purchase, no confirm).
3. The tree's **Start Round** button emits `start_pressed` → `main.gd` frees
   the tree, hides the OS cursor (`Input.MOUSE_MODE_HIDDEN` — the reticle is
   the cursor during play), shows `TargetingArea`, calls `start_round()`.
4. `start_round()` gains the defensive clear CLAUDE.md earmarked for this
   moment: `queue_free()` any stragglers in `Enemies`/`Pickups`/`Effects`
   before spawning.

Cursor rules (new):

- Gameplay: `Input.MOUSE_MODE_HIDDEN` from `_ready()` and on every round
  start. The targeting rectangle is the only pointer.
- Upgrade screen: `Input.MOUSE_MODE_VISIBLE` +
  `Input.set_custom_mouse_cursor(CURSOR_TEXTURE)` (set once at `_ready()`;
  toggling visibility per screen is enough after that).

Removed: `RoundOverPanel`, `RoundOverLabel`, `RestartButton` (nodes, styles,
and their wiring in `main.gd`). The upgrade tree is the between-rounds screen.

The HUD (`TimeLabel`, `CurrencyLabel`) hides while the tree is up — the tree
has its own gold readout; HUD shows again on round start.

## Data model

### `upgrades.gd` (new, `class_name Upgrades`)

Pure static data. One entry per upgrade; `costs.size()` is the max level and
the pip count, so deeper upgrades later are just longer arrays.

```gdscript
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

### `game_state.gd` changes

- `const BASE_STATS` — today's `stats` values, frozen, plus the new
  `enemy_size: Vector2(24, 24)`.
- `var stats` — starts as a duplicate of `BASE_STATS`; always **recomputed
  from base + levels** (idempotent, no incremental drift).
- `var upgrade_levels := {"dmg": 0, "size": 0, "speed": 0}`.
- `signal upgrades_changed` — emitted after a successful purchase (the tree
  UI refreshes node states from it).
- `func buy_upgrade(id: String) -> bool` — returns false (no side effects)
  if already at max level or `currency < cost`; otherwise deducts the cost,
  increments the level, recomputes stats, emits `currency_changed` and
  `upgrades_changed`, returns true.
- `func _recompute_stats()`:
  - `damage = BASE_STATS.damage + 2 * lvl(dmg)` → 2 / 4 / 6 / 8
  - `target_size = BASE_STATS.target_size * (1.0 + 0.25 * lvl(size))`
    → 24 / 30 / 36 / 42 px square
  - `fire_interval = [1.0, 0.8, 0.6, 0.4][lvl(speed)]`
  - everything else copied from `BASE_STATS` unchanged.

`fire_interval` is read once in `TargetingArea.set_firing(true)` and
`target_size` is read per-use, so recomputed stats take effect at the next
round start with no extra plumbing.

### `enemy_size` split (prerequisite folded in)

Enemies currently share `stats.target_size`; without the split, a SIZE
upgrade would grow the bunnies too.

- Add `enemy_size: Vector2(24, 24)` to `BASE_STATS`/`stats` (no upgrade
  touches it).
- `enemy.gd`: `get_rect()` and `_bounce_off_edges()` read
  `stats.enemy_size`.
- `main.gd`: `_spawn_enemy()` margin reads `stats.enemy_size`.

## Upgrade tree UI

### Scene: `upgrade_tree.tscn` + `upgrade_tree.gd` (new)

`CanvasLayer` (layer above the HUD) → full-screen `Control` with a
`Palette.WHITE` background `ColorRect`. All coordinates in 480×270 space.
Emits `signal start_pressed`.

Layout:

- **Gold label** top center: `"Gold: N"`, Press Start 2P, size 8,
  `Palette.BLACK`; updates live via `GameState.currency_changed`.
- **Current stats readout** top left: three lines, Press Start 2P size 8,
  `Palette.BLACK` — `"DMG: 4"`, `"FIRE: 0.8s"`, `"SIZE: 30x30"` — showing
  the *current* values from `GameState.stats`; refreshes on
  `upgrades_changed` so a purchase is reflected immediately.
- **Hub** at screen center (240, 130): a 24×24 square, 1px black border,
  white fill, reticle icon (`res://sprites/icon_hub.png`). Not clickable,
  no pips, no tooltip. Visual root only.
- **Three upgrade nodes**, 24×24, connected to the hub by 1px
  `Palette.BLACK` lines (drawn by the tree's own `_draw`, hub-edge to
  node-edge): **DMG left** (~90, 130), **SIZE top** (240, 40),
  **SPEED right** (~390, 130). Positions leave room for deeper tiers later.
- **Start Round button** bottom center, styled like the old Restart button
  (same StyleBoxFlat palette values, Press Start 2P size 8).

### `upgrade_node.gd` (new, one Control class used for all three)

Configured with an upgrade id; reads everything else from `Upgrades.DEFS`
and `GameState`.

- 24×24 square: 1px `Palette.BLACK` border, `Palette.WHITE` fill, 16×16
  icon centered.
- **Pips**: three 4×4 squares in a row below the node (2px gap), 1px black
  border; fill `Palette.PEACH` for each owned level, white when empty.
  Pip count = `costs.size()`.
- **States** (palette + alpha variants only):
  - Hover (buyable): fill becomes `Color(Palette.PEACH, 0.4)`.
  - Unaffordable (next cost > gold): whole node at 50% alpha
    (`modulate.a = 0.5`); click does nothing.
  - Maxed: full alpha, all pips filled, no hover fill, click does nothing.
- Click = `GameState.buy_upgrade(id)`; on success the node re-renders
  (pips, states) — all nodes refresh via `upgrades_changed` +
  `currency_changed` since one purchase can make another unaffordable.
- **Tooltip** via `_make_custom_tooltip` (Godot's default tooltip theme
  would break the palette/font): a `PanelContainer` — white fill, 1px black
  border — with Press Start 2P size-8 black text:
  `NAME`, description, and `"Next: N gold"` / `"MAX"`.
  `tooltip_text` is set to a non-empty placeholder so the hover triggers.

### Icons (added to `tools/make_placeholders.gd`, 16×16 each)

- `icon_dmg.png` — diagonal sword: black blade, peach guard/hilt.
- `icon_size.png` — small purple square with black arrows pointing out of
  two opposite corners.
- `icon_speed.png` — lightning bolt: peach fill, black outline.
- `icon_hub.png` — the reticle: 1px black square outline with a purple
  center dot.

### Cursor asset

`sprites/cursor.png` — an 8×8 pixel-art arrow (black outline, white fill)
authored in the ASCII map tool and saved **pre-upscaled ×4 nearest-neighbor
(32×32)**. Documented exception to the "no pre-upscaling" asset rule: OS
cursors render at window resolution, outside the 480×270 integer-scaled
canvas, so an 8×8 file would show 8×8 physical pixels. Hotspot `(0, 0)`
(the arrow tip is the top-left pixel).

## Edge cases

- Buy click with insufficient gold, or on a maxed node: no-op, no state
  change (`buy_upgrade` returns false before side effects).
- Purchase making a *different* node unaffordable: every node refreshes on
  `currency_changed`.
- Tooltip open during a purchase may show stale cost until re-hover:
  accepted (tooltip content is rebuilt on each hover).
- Round with zero kills: tree still appears; everything unaffordable is
  dimmed; player can only Start Round.
- Multiple rapid clicks: `buy_upgrade` is synchronous and guards itself, so
  double-purchase is impossible.

## Testing

No test framework (by design). Verification:

- Headless smoke run (`--quit-after 300`) — boots clean.
- Throwaway harness scene (same pattern as the kill-path test): grant gold,
  call `buy_upgrade` through all levels asserting gold totals, stat values
  (damage 4/6/8, target 30/36/42, interval 0.8/0.6/0.4), refusal when broke
  and when maxed, and `enemy_size` staying (24, 24); simulate round-over and
  assert the tree mounts and `start_pressed` restarts a round. Harness is
  deleted after the run.
- User playtest for feel and readability at gameplay size.

## Out of scope

- Saving progress to disk.
- Upgrade prerequisites/branching beyond the hub (layout leaves room).
- Rebalancing enemy HP/spawn rates against upgraded stats.
- Sound.

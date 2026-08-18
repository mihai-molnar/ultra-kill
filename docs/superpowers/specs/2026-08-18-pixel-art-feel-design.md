# Pixel Art Feel — Design

**Date:** 2026-08-18
**Status:** Approved (design discussed and accepted in-session)

## Goal

Give the game a true low-resolution pixel art look while keeping the
1920×1080 window and sharp, readable UI text. Gameplay logic (mouse-follow
reticle, `Rect2.intersects` damage, drop sweeping) is unchanged — only the
coordinate space, rendering config, and visuals change.

## Approach summary

- **True low-res** via `canvas_items` stretch: game logic runs at a
  **480×270 base resolution**, integer-scaled ×4 into the unchanged
  1920×1080 window. Not a SubViewport; not faux pixel art at 1080p.
- **Sprites with generated placeholders now**, hand-drawn art later —
  swapping art must require no code changes.
- **Damage = palette-swap erode shader**: the existing purple-eats-to-peach
  language, applied per-pixel on any sprite silhouette.

## Rendering configuration (`project.godot`)

| Setting | Value |
|---|---|
| `display/window/size/viewport_width/height` | 480×270 (new base resolution) |
| `display/window/size/window_width/height_override` | 1920×1080 (window stays big) |
| `display/window/stretch/mode` | `canvas_items` |
| `display/window/stretch/scale_mode` | `integer` |
| `rendering/textures/canvas_textures/default_texture_filter` | Nearest |
| `rendering/2d/snap/snap_2d_transforms_to_pixel` | on |

`canvas_items` stretch is the load-bearing choice: sprites are authored at
base resolution and scale ×4 chunky (nearest filter), while fonts rasterize
at window resolution, so text size is set in base pixels but renders sharp.
`snap_2d_transforms_to_pixel` makes motion step on the base-pixel grid
(4 screen px per step) instead of gliding — this sells the retro feel.

## Coordinate rescale (÷4)

All world-space values shrink to base-resolution units. Nothing about the
mechanics changes; per-second feel is identical.

| Value | Where | Old | New |
|---|---|---|---|
| `stats.target_size` | `game_state.gd` | (100, 100) | (24, 24) |
| Enemy `SPEED_MIN`/`SPEED_MAX` | `enemy.gd` | 80 / 160 | 20 / 40 |
| Drop `SIZE` | `currency_drop.gd` | (14, 14) | (4, 4) |
| `DROP_OFFSET_MIN`/`MAX` | `main.gd` | 40 / 120 | 10 / 30 |
| Reticle border width | `targeting_area.gd` | 2.0 | 1.0 |
| HUD label offsets / separations | `main.tscn` | various | ÷4, rounded to ints |

Round any non-integer result to whole base pixels.

## Sprite pipeline

New `sprites/` directory. Enemies and currency drops become textured
instead of `_draw` rects:

- `enemy.gd` — gains a `Sprite2D` child created in `_ready` showing
  `sprites/enemy.png` (24×24), with the damage shader material (below).
  `_draw` body/HP-bar drawing is removed; `get_rect`, wander, bounce, and
  damage logic are untouched.
- `currency_drop.gd` — `Sprite2D` child showing `sprites/drop.png` (4×4);
  `_draw` removed. Collection/pop logic untouched.
- `targeting_area.gd` — **stays procedural `_draw`** (it is a targeting
  overlay, not a creature): 1 px `Palette.BLACK` border, translucent black
  fill/flash as today.

### Placeholder assets (generated in this slice)

Small 4-color PNGs written by script (committed like any asset):

- `sprites/enemy.png` — 24×24, purple body with 1 px black outline,
  simple readable silhouette (not a plain filled square).
- `sprites/drop.png` — 4×4, peach with black outline.

### Asset spec (for future hand-drawn art)

Recorded in CLAUDE.md. Replacement art must be: PNG with transparent
background, authored at 1:1 base-resolution scale (no pre-upscaling),
using **exactly** the four palette colors, same file names and sizes as
the placeholders (enemy 24×24, drop 4×4). Enemy art keeps purple as the
body color so the damage shader can find it.

## Damage: palette-swap erode shader

`shaders/enemy_damage.gdshader`, a `canvas_item` shader on the enemy
sprite, uniform `hp_ratio` (1.0 = full HP, 0.0 = dead):

- A pixel whose color matches `Palette.PURPLE` (small tolerance) is
  swapped to `Palette.PEACH` when it lies in the damaged fraction:
  purple remains **right-anchored** (`UV.x > 1.0 - hp_ratio` stays
  purple), so damage eats left → right exactly like the current bar.
- Black outline and transparent pixels pass through unchanged.
- `enemy.gd` sets `hp_ratio` in `take_damage` (and on ready).

Result: fully purple = full HP, fully peach = dead — the existing visual
language, on any sprite shape, always within the 4-color palette.

## Font: Press Start 2P

Russo One is replaced by **Press Start 2P** (SIL OFL, fetched from the
google/fonts repo with its license file, like the Russo One flow).
`fonts/RussoOne-*` files are deleted; CLAUDE.md's font rule updates.

- Import/render with antialiasing off so glyphs stay hard-edged.
- Sizes in base pixels, multiples of 8 so glyph pixels align with the ×4
  art grid: timer + gold counter 8 (≈32 screen px), Round Over 16,
  Restart button 8.
- Button styleboxes: border width 1 base px, content margins ÷4.

## Testing

- Headless smoke run (`--quit-after 300`) stays the automated check; run
  `--import` first (new assets + shader need importing).
- Visual acceptance is a real run by the user: chunky ×4 pixels, stepped
  motion, sharp text, erode effect reading correctly on the placeholder
  sprite.

## Out of scope

- Hand-drawn final art (user provides later, per the asset spec).
- Animation frames (idle/walk), particles, screen shake, or other juice.
- Level-up screen (still the next gameplay slice; it inherits this look).
- Splitting `stats.target_size` into target vs. enemy size (still listed
  as deferred work in CLAUDE.md).

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"ultra kill" is a Godot 4.5 game project using the Forward Plus renderer. The core round loop is implemented; see the design spec in `docs/superpowers/specs/`.

## Working with Godot

- Godot 4.5.1 binary: `/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot` (quote the path — it has a space).
- Run the game: `"$GODOT" --path "/Users/mihai/Godot games/ultra-kill"`
- Static-check a script: `"$GODOT" --headless --path . --check-only --script res://<file>.gd`
- Headless smoke run: `"$GODOT" --headless --path . --quit-after 300` (mouse sits at 0,0 in headless — targeting area in the corner is expected).
- Known limitation: `--check-only --script` cannot resolve autoloads or cross-file class_names (no editor class cache) and always exits 0 — treat "Identifier not found: GameState" / "Could not find type" errors there as spurious; the headless smoke run is the real check.
- The `.godot/` directory is editor-generated cache — never edit or commit it (it is gitignored).
- `project.godot` is the project configuration file; prefer editing it via the Godot editor, but small direct edits are fine.
- Scene files (`.tscn`) and resource files (`.tres`) are text-based and diffable; `.import` files are auto-generated metadata for assets.

## Conventions

- Scripts are written in GDScript (`.gd`) unless otherwise decided.
- Godot convention: snake_case for file names, functions, and variables; PascalCase for node names and class names.

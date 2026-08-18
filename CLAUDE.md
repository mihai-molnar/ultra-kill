# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"ultra kill" is a Godot 4.5 game project using the Forward Plus renderer. It is currently a fresh project with no scenes or scripts yet — only the default project configuration.

## Working with Godot

- The Godot editor binary is not on PATH on this machine. On macOS it is typically at `/Applications/Godot.app/Contents/MacOS/Godot`; verify before running commands.
- Run the project headlessly / from CLI: `<godot-binary> --path "/Users/mihai/Godot games/ultra-kill"`
- The `.godot/` directory is editor-generated cache — never edit or commit it (it is gitignored).
- `project.godot` is the project configuration file; prefer editing it via the Godot editor, but small direct edits are fine.
- Scene files (`.tscn`) and resource files (`.tres`) are text-based and diffable; `.import` files are auto-generated metadata for assets.

## Conventions

- Scripts are written in GDScript (`.gd`) unless otherwise decided.
- Godot convention: snake_case for file names, functions, and variables; PascalCase for node names and class names.

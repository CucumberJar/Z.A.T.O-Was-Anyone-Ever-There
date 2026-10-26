# Z.A.T.O. — Was Anyone Ever There?

Z.A.T.O. is a Godot 4 survival-horror game set in a sealed Soviet research complex, CONTOUR, in 1987. The player is sent to start a supercomputer; the required archive manual is inaccessible, the diagnostic sequence fails, and the complex starts behaving as if something is responding from inside the system.

## Gameplay loop

- Arrive at the facility and inspect the sealed archive.
- Calibrate the supercomputer and confirm its inevitable critical failure.
- Survive the first blackout and gather supplies.
- Reach the electrical panel while an anomaly hunts the player.
- Survive the next shift and complete two of three final objectives to retain your humanity.

## Controls

| Action | Controls |
| --- | --- |
| Move | WASD / arrow keys |
| Interact | E |
| Sprint | Shift |
| Dash | Space |
| Fire when the weapon is enabled | Left mouse button |
| Pause / case notebook | Esc |
| Restart after an ending | R |

## Requirements

- Godot Engine **4.7.2 stable**.
- For exported builds, install the matching Godot export templates.

Open `project.godot` in the Godot editor and run the project with **F6/F5**. The main scene is `res://scenes/ui/start_menu.tscn`.

## Audio and settings

`AudioDirector` owns music, ambience and UI click/hover sounds. It chooses music from the active game phase, fades between tracks and suspends the ambience while paused. Master volume and fullscreen preferences are saved in `user://zato_settings.cfg`.

Track mappings and sound bus defaults are in `scripts/audio/audio_director.gd`. Keep music and ambience on separate buses when adjusting the mix; important footsteps and threat cues should remain audible over the soundtrack.

## Export profiles

The repository contains these presets in `export_presets.cfg`:

- **Web** — `build/web/index.html`
- **Windows Desktop** — `build/windows/ZATO.exe`
- **Linux/X11** — `build/linux/ZATO.x86_64`

Example:

```bash
godot --headless --path . --editor --quit
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

Serve the Web export over HTTP; opening the generated `index.html` directly from disk is not a supported deployment method.

## Project layout

- `scenes/` — levels, NPCs, HUD, menu and computer minigame.
- `scripts/` — gameplay flow, quests, NPC behaviour, UI and audio.
- `assets/` — artwork, fonts and sound.
- `shaders/` — screen glitches and pixel fog.
- `docs/CHANGELOG.md` — development history.
- `.github/workflows/godot-release.yml` — headless validation and release exports.

## Release checklist

The CI workflow imports the project, boots the menu and gameplay scene headlessly, then exports Web/Windows/Linux artefacts. A successful headless run does **not** replace a manual playthrough. Before tagging a release, test the whole run in the target browser and on Windows/Linux, review pause/resume and save/load, listen on headphones and speakers, and confirm redistribution rights for every audio/image asset.

#!/usr/bin/env python3
"""Install Z.A.T.O. custom guard + Shift sprint; no changes to map/UI/gameplay scenes.

Usage:
    python install_character_sprint.py
    python path/to/install_character_sprint.py path/to/godot/project

Safe to rerun; creates .pre-character-v080.bak copies before changing text files.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import shutil
import sys

PATCH = Path(__file__).resolve().parent
ROOT = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else PATCH
MARKER = "ZATO_HANDDRAWN_SPRINT_V080"
SPRITE = "res://assets/characters/guard_handdrawn_sheet.png"
NORMAL = "res://assets/characters/guard_handdrawn_normal.png"


def abort(message: str) -> None:
    raise SystemExit("INSTALLATION ABORTED: " + message + "\nNo project files were changed.")


def replace_once(text: str, old: str, new: str, file_name: str) -> str:
    count = text.count(old)
    if count != 1:
        abort(f"expected unique code block in {file_name}, found {count}. "
              "Your files differ from the supported GitHub version; do not overwrite manually.")
    return text.replace(old, new, 1)


def patch_guard(text: str) -> str:
    if MARKER in text:
        return text

    text = replace_once(text, "const MOVE_SPEED := 165.0",
                        "const MOVE_SPEED := 165.0\nconst SPRINT_SPEED := 255.0 # Shift; runs use frames from the supplied atlas\n# " + MARKER,
                        "scripts/guard.gd")

    # When unarmed, turn the character in the direction of travel. When armed,
    # preserve the existing mouse-aimed shooting and muzzle offsets.
    match = re.search(
        r'(?m)^([ \t]*)if aim\.length_squared\(\) > 36\.0:\n'
        r'\1[ \t]+facing = aim\.normalized\(\)\n'
        r'\1elif direction != Vector2\.ZERO:\n'
        r'\1[ \t]+facing = direction', text)
    if not match:
        abort("could not find direction/aim code in scripts/guard.gd")
    indent = match.group(1)
    original = match.group(0)
    original_lines = original.splitlines()
    body_indent = re.match(r"^[ \t]*", original_lines[1]).group(0)
    new = (f'{indent}if weapon_enabled and aim.length_squared() > 36.0:\n'
           f'{body_indent}facing = aim.normalized()\n'
           f'{indent}elif direction != Vector2.ZERO:\n'
           f'{body_indent}facing = direction')
    text = text.replace(original, new, 1)

    match = re.search(
        r'(?m)^([ \t]*)velocity = dash_direction \* DASH_SPEED if dash_time > 0\.0 else direction \* MOVE_SPEED$',
        text)
    if not match:
        abort("could not find movement-speed expression in scripts/guard.gd")
    indent = match.group(1)
    replacement = (f'{indent}var sprinting: bool = Input.is_action_pressed("sprint") and '
                   'direction.length_squared() > 0.01 and dash_time <= 0.0\n'
                   f'{indent}var current_speed: float = SPRINT_SPEED if sprinting else MOVE_SPEED\n'
                   f'{indent}velocity = dash_direction * DASH_SPEED if dash_time > 0.0 else direction * current_speed')
    text = text[:match.start()] + replacement + text[match.end():]

    anim_start = text.find('if velocity.length_squared() > 100.0:')
    anim_end = text.find('$Visual.modulate =', anim_start)
    if anim_start < 0 or anim_end < 0:
        abort("could not find existing sprite animation block in scripts/guard.gd")
    # Locate start of the corresponding line to preserve its indentation.
    line_start = text.rfind('\n', 0, anim_start) + 1
    end_line_start = text.rfind('\n', 0, anim_end) + 1
    block = text[line_start:end_line_start]
    if ('elapsed_walk' not in block or '$Visual.region_rect' not in block):
        abort("unexpected animation logic in scripts/guard.gd")
    indent = text[line_start:anim_start]
    replacement = (f'{indent}var running_animation: bool = sprinting or dash_time > 0.0\n'
                   f'{indent}var moving_animation: bool = direction.length_squared() > 0.01 or dash_time > 0.0\n'
                   f'{indent}_update_handdrawn_sprite(direction_index, moving_animation, running_animation, delta)\n')
    text = text[:line_start] + replacement + text[end_line_start:]

    helper = '''func _update_handdrawn_sprite(direction_index: int, moving: bool, running: bool, delta: float) -> void:
    # Source atlas: 32x64 frames, 320x1280 overall. Four complete sets:
    # down: rows 0,1,2; up: 3,4,5; left: 6,7,8; right: 9,10,11.
    # The artist drew four orientations, not eight; diagonal aim uses a side view.
    var direction_group: int = 0
    match direction_index:
        1, 2, 3:
            direction_group = 2
        4:
            direction_group = 1
        5, 6, 7:
            direction_group = 3
    var row: int = direction_group * 3
    var frames: int = 1
    var fps: float = 1.0
    if moving:
        row += 2 if running else 1
        fps = 13.0 if running else 9.0
        match row:
            1, 4, 8, 11:
                frames = 6
            2:
                frames = 9
            5:
                frames = 7
            7, 10:
                frames = 5
    if row != _previous_sprite_row:
        elapsed_walk = 0.0
        _previous_sprite_row = row
    var frame: int = 0
    if moving:
        elapsed_walk += delta
        frame = int(elapsed_walk * fps) % frames
    else:
        elapsed_walk = 0.0
    $Visual.region_rect = Rect2(frame * 32, row * 64, 32, 64)

'''
    # Godot disallows mixing indentation styles within a function.
    if "\t" in indent:
        helper = "\n".join(
            ("\t" * ((len(line) - len(line.lstrip(" "))) // 4) + line.lstrip(" "))
            if line.startswith(" ") else line
            for line in helper.split("\n")
        )
    if 'func _update_weapon_effects(' not in text:
        abort("cannot locate effect method in scripts/guard.gd")
    text = text.replace('func _update_weapon_effects(',
                        'var _previous_sprite_row: int = -1\n\n' + helper + 'func _update_weapon_effects(', 1)
    return text


def patch_scene(text: str) -> str:
    if SPRITE in text and NORMAL in text:
        return text
    if 'res://assets/characters/guard_32x64_sheet.png' not in text:
        abort("can't locate current guard texture in scenes/guard.tscn")
    if 'res://assets/characters/guard_32x64_normal.png' not in text:
        abort("can't locate current guard normal map in scenes/guard.tscn")
    text = text.replace('res://assets/characters/guard_32x64_sheet.png', SPRITE)
    text = text.replace('res://assets/characters/guard_32x64_normal.png', NORMAL)
    # The authored sprite has transparent padding at the top and bottom.
    # Keep its feet anchored to the character body; do not move the collider.
    text = text.replace('position = Vector2(0, -25)\nregion_enabled = true',
                        'position = Vector2(0, -39)\nregion_enabled = true')
    return text


SPRINT_ACTION = '''sprint={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":16,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194325,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
'''


def patch_project(text: str) -> str:
    if re.search(r'^sprint=\{', text, flags=re.M):
        return text
    if '[input]' not in text:
        abort("project.godot does not contain [input]")
    pos = text.find('dash={', text.index('[input]'))
    if pos < 0:
        abort("cannot locate dash action in project.godot")
    return text[:pos] + SPRINT_ACTION + text[pos:]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    required = ['project.godot', 'scenes/guard.tscn', 'scripts/guard.gd']
    for name in required:
        if not (ROOT / name).is_file():
            abort(f"missing {name}. Run from the project root, or pass that path as an argument")
    source_assets = [
        'assets/characters/guard_handdrawn_sheet.png',
        'assets/characters/guard_handdrawn_normal.png',
    ]
    for path in source_assets:
        if not (PATCH / path).is_file():
            abort(f"patch is missing {path}; extract the entire ZIP first")

    modified = {
        'scripts/guard.gd': patch_guard((ROOT / 'scripts/guard.gd').read_text(encoding='utf-8')),
        'scenes/guard.tscn': patch_scene((ROOT / 'scenes/guard.tscn').read_text(encoding='utf-8')),
        'project.godot': patch_project((ROOT / 'project.godot').read_text(encoding='utf-8')),
    }
    for filename, content in modified.items():
        dest = ROOT / filename
        if dest.read_text(encoding='utf-8') == content:
            print('Already up to date:', filename)
            continue
        backup = dest.with_name(dest.name + '.pre-character-v080.bak')
        if not backup.exists():
            shutil.copy2(dest, backup)
        dest.write_text(content, encoding='utf-8')
        print('Updated:', filename)

    for filename in source_assets:
        source = PATCH / filename
        dest = ROOT / filename
        dest.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() == dest.resolve():
            print('Already in project:', filename)
        elif dest.exists() and sha256(source) == sha256(dest):
            print('Already up to date:', filename)
        else:
            if dest.exists():
                backup = dest.with_suffix(dest.suffix + '.pre-character-v080.bak')
                if not backup.exists():
                    shutil.copy2(dest, backup)
            shutil.copy2(source, dest)
            print('Installed:', filename)
    print('Done. Run Godot. Hold Shift to sprint; Space still dashes.')


if __name__ == '__main__':
    main()

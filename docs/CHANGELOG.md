## 2026-10-26 — release-candidate pass

- Fixed audio scene detection: the director now looks for the actual `_start_first_night` gameplay controller and retains the current soundtrack while paused.
- Centralised master-volume/fullscreen settings in `AudioDirector` and persist them to the user's settings file.
- Corrected the electrical-panel action ID and made the sortie require interaction with the panel instead of auto-completing at timeout.
- The first blackout lasts 60 seconds; the sortie spawns an anomaly and penalises delays.
- The computer objective completes only after the player acknowledges the critical failure, rather than on opening the terminal.
- Added working final-shift objective checks and export presets for Windows/Linux alongside Web.
- Added a GitHub Actions workflow for headless project startup and release exports.

Release status: candidate only until CI passes and a complete interactive playthrough is verified in Godot.

---

# v0.4.2.1 — исправление GDScript

- Удалён неиспользуемый `DIRECTION_VECTORS`: `.normalized()` нельзя вызывать в константном выражении.
- Для `muzzle_offset` задан явный тип `Vector2`, чтобы индексирование массива не вызывало ошибку вывода типа.
- Игровая механика и структура уровня не изменены.
- Проверены пути ресурсов и синтаксическая структура затронутого файла; запуск через Godot в этой среде недоступен.

---

# v0.4.2
- Удалён легаси наружный проект.
- Перерисована планировка, разведены проходимость и стены.
- Многоклеточные предметы размещаются целиком из оригинального атласа.
- Созданы 4 независимых TileMapLayer и единый TileSet с двумя источниками.
- Позиции объектов и старт игрока синхронизированы с новым уровнем.

extends Node2D

# EDITOR-AUTHORED MAP: TileMapLayer data is saved directly inside
# scenes/indoor_institute.tscn. This script NEVER paints, clears or
# generates tiles. It only builds gameplay navigation and collisions.
const CELL: int = 48

@onready var floor_tiles: TileMapLayer = $FloorTiles
@onready var wall_tiles: TileMapLayer = $WallTiles
@onready var equipment_tiles: TileMapLayer = $EquipmentTiles
@onready var ceiling_tiles: TileMapLayer = $CeilingTiles
@onready var structure: StaticBody2D = $Structure

var navigation: AStarGrid2D
var map_region: Rect2i

func _ready() -> void:
    # Never modify any of the four TileMapLayer nodes here.
    map_region = floor_tiles.get_used_rect().merge(ceiling_tiles.get_used_rect())
    if map_region.size.x <= 0 or map_region.size.y <= 0:
        push_error("Z.A.T.O.: The tile map has no saved cells. Edit indoor_institute.tscn and save.")
        return
    _build_navigation()
    _build_wall_collisions()

func _equipment_blocks(cell: Vector2i) -> bool:
    # The desk papers and elevator floor dressing remain decorative.
    # All other EquipmentTiles cells count as obstacles by default.
    if equipment_tiles.get_cell_source_id(cell) == -1:
        return false
    var atlas: Vector2i = equipment_tiles.get_cell_atlas_coords(cell)
    if atlas.y >= 15 and atlas.y <= 17 and atlas.x >= 0 and atlas.x <= 2:
        return false  # Elevator cabin backdrop / floor dressing.
    if atlas.y >= 10 and atlas.y <= 11 and atlas.x >= 8 and atlas.x <= 9:
        return false  # Scattered office papers.
    return true

func is_walkable(cell: Vector2i) -> bool:
    if not map_region.has_point(cell):
        return false
    if floor_tiles.get_cell_source_id(cell) == -1:
        return false
    # Painting a WallTiles cell over the floor blocks that cell.
    if wall_tiles.get_cell_source_id(cell) != -1:
        return false
    return not _equipment_blocks(cell)

func _build_navigation() -> void:
    navigation = AStarGrid2D.new()
    navigation.region = map_region
    navigation.cell_size = Vector2(CELL, CELL)
    navigation.offset = Vector2(CELL / 2.0, CELL / 2.0)
    navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    navigation.update()
    for y in range(map_region.position.y, map_region.end.y):
        for x in range(map_region.position.x, map_region.end.x):
            var cell := Vector2i(x, y)
            navigation.set_point_solid(cell, not is_walkable(cell))

func _build_wall_collisions() -> void:
    # One collision rectangle per consecutive solid run. Uses the same
    # cells as A*, so edited walls and furniture affect both systems.
    for child in structure.get_children():
        child.queue_free()
    for y in range(map_region.position.y, map_region.end.y):
        var x: int = map_region.position.x
        while x < map_region.end.x:
            var cell := Vector2i(x, y)
            if is_walkable(cell):
                x += 1
                continue
            var start_x := x
            while x < map_region.end.x and not is_walkable(Vector2i(x, y)):
                x += 1
            var shape := RectangleShape2D.new()
            shape.size = Vector2(float(x - start_x) * CELL, CELL)
            var collision := CollisionShape2D.new()
            collision.position = Vector2((start_x + x) * CELL / 2.0, (y + 0.5) * CELL)
            collision.shape = shape
            structure.add_child(collision)

func path_to(start_position: Vector2, end_position: Vector2) -> PackedVector2Array:
    if navigation == null:
        return PackedVector2Array()
    var begin_cell := Vector2i(floori(start_position.x / CELL), floori(start_position.y / CELL))
    var end_cell := Vector2i(floori(end_position.x / CELL), floori(end_position.y / CELL))
    var start: Vector2i = _clamp_to_map(begin_cell)
    var goal: Vector2i = _clamp_to_map(end_cell)
    if navigation.is_point_solid(start):
        return PackedVector2Array()
    if navigation.is_point_solid(goal):
        var found := false
        for r in range(1, 7):
            if found:
                break
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    var candidate := goal + Vector2i(dx, dy)
                    if navigation.is_in_boundsv(candidate) and not navigation.is_point_solid(candidate):
                        goal = candidate
                        found = true
                        break
                if found:
                    break
        if not found:
            return PackedVector2Array()
    return navigation.get_point_path(start, goal)

func _clamp_to_map(cell: Vector2i) -> Vector2i:
    return Vector2i(
        clampi(cell.x, map_region.position.x, map_region.end.x - 1),
        clampi(cell.y, map_region.position.y, map_region.end.y - 1)
    )

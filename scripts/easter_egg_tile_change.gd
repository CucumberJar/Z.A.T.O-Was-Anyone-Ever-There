class_name EasterEggTileChange
extends Resource

# Each entry affects one TileMapLayer and one or more LOCAL tile coordinates.
# Create more entries to change different layers or use different tiles.
enum Operation { ERASE, PLACE, COPY }

@export_group("TileMapLayer")
@export var layer_path: NodePath
@export var cells: Array[Vector2i] = []

@export_group("After collecting the secret")
@export var operation: Operation = Operation.ERASE
# PLACE: TileSet source ID, atlas coordinate and optional alternative.
@export var source_id: int = 0
@export var atlas_coords: Vector2i = Vector2i.ZERO
@export var alternative_tile: int = 0
# COPY: coordinates of an existing tile within the same TileMapLayer.
@export var copy_from_cell: Vector2i = Vector2i.ZERO

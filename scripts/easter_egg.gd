extends "res://scripts/interactable.gd"

# Universal easter egg. Compatible with action="easter_egg" in main_indoor.gd.
# Requires scripts/easter_egg_tile_change.gd (class_name EasterEggTileChange).

@export_group("Пасхалка")
@export_range(1, 5, 1) var egg_id: int = 1
@export var hide_item_after_use: bool = false

@export_group("Карта / Видимость")
@export var hide_after_use: Array[NodePath] = []
@export var show_after_use: Array[NodePath] = []

@export_group("Карта / Коллизии")
@export var disable_collision_after_use: Array[NodePath] = []
@export var enable_collision_after_use: Array[NodePath] = []

@export_group("Карта / Изменения тайлов")
@export var tile_changes: Array[EasterEggTileChange] = []

@export_group("Меню паузы")
# Paths to hidden CanvasItem nodes, e.g. ../HUD/PauseRoot/DossierPage/SecretRecord1.
@export var show_in_pause_after_use: Array[NodePath] = []

var used: bool = false
var _original_cells: Array[Dictionary] = []
var _tiles_applied: bool = false
var _activation_token: int = 0

func _ready() -> void:
	action = "easter_egg"
	super._ready()
	add_to_group("easter_eggs")
	_cache_original_tiles()
	restore_state(false)

func _process(delta: float) -> void:
	if used:
		player_inside = false
		return
	super._process(delta)

# Called from main_indoor.gd's "easter_egg" branch.
func activate(game: Node) -> void:
	if used or not game.has_method("register_easter_egg"):
		return
	if not game.register_easter_egg(egg_id):
		return

	used = true
	player_inside = false
	_activation_token += 1
	var token: int = _activation_token

	if not text.is_empty():
		game._say(text, duration)
		await get_tree().create_timer(maxf(0.0, duration)).timeout

	# If the game was loaded while dialogue was playing, do not apply stale changes.
	if not is_inside_tree() or token != _activation_token or not used:
		return
	apply_map_change(true)

# Called on load by the existing easter egg save/load integration.
func restore_state(collected: bool) -> void:
	_activation_token += 1
	used = collected
	player_inside = false
	apply_map_change(collected)

func apply_map_change(collected: bool) -> void:
	for path in hide_after_use:
		_set_visible(path, not collected)
	for path in show_after_use:
		_set_visible(path, collected)
	for path in disable_collision_after_use:
		_set_collision_disabled(path, collected)
	for path in enable_collision_after_use:
		_set_collision_disabled(path, not collected)
	for path in show_in_pause_after_use:
		_set_visible(path, collected)

	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = not (collected and hide_item_after_use)

	if collected and not _tiles_applied:
		_apply_tile_changes()
		_tiles_applied = true
		_rebuild_map_navigation()
	elif not collected and _tiles_applied:
		_restore_original_tiles()
		_tiles_applied = false
		_rebuild_map_navigation()

func _cache_original_tiles() -> void:
	# Snapshot tile contents before any secret modifies the map.
	# Different EasterEgg instances should not edit the same cells.
	var seen: Dictionary = {}
	for change in tile_changes:
		if change == null:
			continue
		var layer: TileMapLayer = get_node_or_null(change.layer_path) as TileMapLayer
		if layer == null:
			push_warning("EasterEgg %d: TileMapLayer не найден: %s" % [egg_id, change.layer_path])
			continue
		for cell in change.cells:
			var key: String = "%d:%d:%d" % [layer.get_instance_id(), cell.x, cell.y]
			if seen.has(key):
				continue
			seen[key] = true
			_original_cells.append({
				"layer": layer,
				"cell": cell,
				"source": layer.get_cell_source_id(cell),
				"atlas": layer.get_cell_atlas_coords(cell),
				"alternative": layer.get_cell_alternative_tile(cell)
			})

func _apply_tile_changes() -> void:
	for change in tile_changes:
		if change == null:
			continue
		var layer: TileMapLayer = get_node_or_null(change.layer_path) as TileMapLayer
		if layer == null:
			continue
		var source: int = change.source_id
		var atlas: Vector2i = change.atlas_coords
		var alternative: int = change.alternative_tile
		if change.operation == EasterEggTileChange.Operation.COPY:
			source = layer.get_cell_source_id(change.copy_from_cell)
			atlas = layer.get_cell_atlas_coords(change.copy_from_cell)
			alternative = layer.get_cell_alternative_tile(change.copy_from_cell)
			if source == -1:
				push_warning("EasterEgg %d: COPY берёт пустую клетку %s" % [egg_id, change.copy_from_cell])
				continue
		for cell in change.cells:
			if change.operation == EasterEggTileChange.Operation.ERASE:
				layer.erase_cell(cell)
			else:
				layer.set_cell(cell, source, atlas, alternative)

func _restore_original_tiles() -> void:
	for snapshot in _original_cells:
		var layer: TileMapLayer = snapshot["layer"] as TileMapLayer
		if not is_instance_valid(layer):
			continue
		var cell: Vector2i = snapshot["cell"]
		var source: int = snapshot["source"]
		if source == -1:
			layer.erase_cell(cell)
		else:
			layer.set_cell(cell, source, snapshot["atlas"], snapshot["alternative"])

func _rebuild_map_navigation() -> void:
	# TileMapLayer changes its rendered/collision cells automatically.
	# The custom AStarGrid2D in Indoor does NOT update automatically.
	var game: Node = get_tree().current_scene
	if game != null:
		var indoor: Node = game.get_node_or_null("Indoor")
		if indoor != null and indoor.has_method("_build_navigation"):
			indoor.call_deferred("_build_navigation")

func _set_visible(path: NodePath, value: bool) -> void:
	var node: Node = get_node_or_null(path)
	if node is CanvasItem:
		(node as CanvasItem).visible = value
	else:
		push_warning("EasterEgg %d: визуальный узел не найден: %s" % [egg_id, path])

func _set_collision_disabled(path: NodePath, value: bool) -> void:
	var node: Node = get_node_or_null(path)
	if node is CollisionShape2D:
		(node as CollisionShape2D).set_deferred("disabled", value)
	else:
		push_warning("EasterEgg %d: CollisionShape2D не найден: %s" % [egg_id, path])

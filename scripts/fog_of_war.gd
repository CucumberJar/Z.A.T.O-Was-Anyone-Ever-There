extends CanvasLayer

# Z.A.T.O. Fog v0.9.4
# ONLY WallTiles and WeryWellTiles block the view.
# No collision raycasts, FloorTiles, EquipmentTiles or CeilingTiles involved.
# Existing FogOfWar/Overlay scene is reused; map data is never modified.

const FOG_SHADER: Shader = preload("res://shaders/pixel_fog.gdshader")
const RAY_COUNT: int = 768
const TWO_PI_VALUE: float = PI * 2.0
const EPSILON: float = 0.000001
const MAX_RAY_CELLS: int = 96

@export_group("Scene paths")
@export var guard_path: NodePath = NodePath("../Guard")
@export var wall_tiles_path: NodePath = NodePath("../Indoor/WallTiles")
@export var werywell_tiles_path: NodePath = NodePath("../Indoor/WeryWellTiles")
@export var fog_enabled: bool = true

@export_group("View radius (world pixels)")
@export_range(60.0, 650.0, 5.0) var day_radius: float = 250.0
@export_range(60.0, 650.0, 5.0) var night_radius: float = 165.0
@export_range(60.0, 650.0, 5.0) var panic_radius: float = 200.0
@export_range(60.0, 650.0, 5.0) var elevator_radius: float = 190.0
@export_range(20.0, 1000.0, 10.0) var radius_transition_speed: float = 280.0

@export_group("Pixel shadows")
@export_range(1.0, 12.0, 1.0) var pixel_size: float = 4.0
@export_range(0.0, 1.0, 0.01) var near_dim: float = 0.03
@export_range(0.0, 1.0, 0.01) var middle_dim: float = 0.17
@export_range(0.0, 1.0, 0.01) var far_dim: float = 0.40
@export_range(0.0, 1.0, 0.01) var edge_dim: float = 0.70
@export_range(0.6, 1.0, 0.005) var darkness: float = 0.985
@export_range(0.05, 0.95, 0.01) var near_boundary: float = 0.36
@export_range(0.05, 0.95, 0.01) var middle_boundary: float = 0.67
@export_range(0.05, 0.99, 0.01) var far_boundary: float = 0.88
@export var shadow_color: Color = Color(0.016, 0.022, 0.033, 1.0)

@export_group("Wall visibility")
# Reveal the actual occupied wall cells up to this maximum thickness;
# the first free cell BEHIND the wall is hidden.
# Set 96 for two stacked 48px cells, or 144 for three cells.
@export_range(0.0, 288.0, 4.0) var wall_reveal_depth: float = 96.0
@export_range(0.0, 4.0, 0.25) var wall_back_margin: float = 1.0
@export_range(0.0, 0.8, 0.01) var wall_dim: float = 0.16

@export_group("Updates")
@export_range(0.03, 0.3, 0.01) var ray_update_seconds: float = 0.08
@export var eye_offset: Vector2 = Vector2(0.0, -14.0)

@onready var overlay: ColorRect = $Overlay

var guard: CharacterBody2D
var reference_layer: TileMapLayer
var wall_layers: Array[TileMapLayer] = []
var blocked_cells: Dictionary = {}
var cell_size: Vector2 = Vector2(48.0, 48.0)
var vision_material: ShaderMaterial
var ray_image: Image
var ray_texture: ImageTexture
var current_radius: float = 250.0
var cast_eye: Vector2 = Vector2.ZERO
var last_eye: Vector2 = Vector2(INF, INF)
var last_radius: float = -1.0
var cast_elapsed: float = 1.0


func _ready() -> void:
	guard = get_node_or_null(guard_path) as CharacterBody2D
	if guard == null:
		push_error("FogOfWar: Guard was not found. Check Guard Path in Inspector.")
		overlay.visible = false
		set_process(false)
		set_physics_process(false)
		return

	var walls: TileMapLayer = get_node_or_null(wall_tiles_path) as TileMapLayer
	var more_walls: TileMapLayer = get_node_or_null(werywell_tiles_path) as TileMapLayer
	if walls != null:
		wall_layers.append(walls)
	if more_walls != null and more_walls != walls:
		wall_layers.append(more_walls)
	if wall_layers.is_empty():
		push_warning("FogOfWar: neither WallTiles nor WeryWellTiles was found; only the distance radius will apply.")
	elif more_walls == null:
		push_warning("FogOfWar: WeryWellTiles is missing. Only WallTiles will cast shadows.")

	refresh_wall_tiles()
	current_radius = _radius_for_phase()
	cast_eye = _snap_world(guard.global_position + eye_offset)
	ray_image = Image.create(RAY_COUNT, 1, false, Image.FORMAT_RGBA8)
	ray_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	ray_texture = ImageTexture.create_from_image(ray_image)
	vision_material = ShaderMaterial.new()
	vision_material.shader = FOG_SHADER
	vision_material.set_shader_parameter("vision_rays", ray_texture)
	vision_material.set_shader_parameter("ray_count", float(RAY_COUNT))
	overlay.material = vision_material
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = fog_enabled
	_cast_visibility()
	_send_parameters()


# Call this method if wall tiles are added/removed WHILE THE GAME IS RUNNING.
# Editing cells in the editor before playing needs no extra call.
func refresh_wall_tiles() -> void:
	blocked_cells.clear()
	reference_layer = null
	if wall_layers.is_empty():
		return
	reference_layer = wall_layers[0]
	if reference_layer.tile_set != null:
		cell_size = Vector2(reference_layer.tile_set.tile_size)

	for layer in wall_layers:
		for cell in layer.get_used_cells():
			# Transform through world coordinates, so two overlapping layers
			# occupy the same reference cell even if their nodes differ.
			var world_center: Vector2 = layer.to_global(layer.map_to_local(cell))
			var reference_cell: Vector2i = reference_layer.local_to_map(reference_layer.to_local(world_center))
			blocked_cells[reference_cell] = true


func _process(_delta: float) -> void:
	if not is_instance_valid(guard) or vision_material == null:
		return
	overlay.visible = fog_enabled
	if fog_enabled:
		_send_parameters()


func _physics_process(delta: float) -> void:
	if not fog_enabled or not is_instance_valid(guard):
		return
	current_radius = move_toward(current_radius, _radius_for_phase(), radius_transition_speed * delta)
	var eye: Vector2 = _snap_world(guard.global_position + eye_offset)
	cast_elapsed += delta
	if eye == last_eye and absf(current_radius - last_radius) < 1.0 and cast_elapsed < ray_update_seconds:
		return
	cast_eye = eye
	_cast_visibility()
	last_eye = eye
	last_radius = current_radius
	cast_elapsed = 0.0


func _snap_world(point: Vector2) -> Vector2:
	var block: float = maxf(pixel_size, 1.0)
	return Vector2(
		(floorf(point.x / block) + 0.5) * block,
		(floorf(point.y / block) + 0.5) * block
	)


func _radius_for_phase() -> float:
	var game: Node = get_parent()
	if game == null:
		return day_radius
	var state: String = str(game.get("phase"))
	match state:
		"NIGHT1", "NIGHT2": return night_radius
		"PANIC": return panic_radius
		"ELEVATOR": return elevator_radius
		_: return day_radius


func _send_parameters() -> void:
	var screen_transform: Transform2D = guard.get_global_transform_with_canvas()
	var zoom: float = maxf(screen_transform.basis_xform(Vector2.RIGHT).length(), 0.001)
	var camera_translation: Vector2 = screen_transform.origin - guard.global_position * zoom
	vision_material.set_shader_parameter("viewport_size", overlay.size)
	vision_material.set_shader_parameter("camera_translation", camera_translation)
	vision_material.set_shader_parameter("camera_zoom", zoom)
	vision_material.set_shader_parameter("eye_world", cast_eye)
	vision_material.set_shader_parameter("vision_radius", current_radius)
	vision_material.set_shader_parameter("pixel_size", pixel_size)
	vision_material.set_shader_parameter("shadow_color", shadow_color)
	vision_material.set_shader_parameter("near_dim", near_dim)
	vision_material.set_shader_parameter("middle_dim", middle_dim)
	vision_material.set_shader_parameter("far_dim", far_dim)
	vision_material.set_shader_parameter("edge_dim", edge_dim)
	vision_material.set_shader_parameter("darkness", darkness)
	vision_material.set_shader_parameter("near_boundary", near_boundary)
	vision_material.set_shader_parameter("middle_boundary", middle_boundary)
	vision_material.set_shader_parameter("far_boundary", far_boundary)
	vision_material.set_shader_parameter("wall_dim", wall_dim)


func _cast_visibility() -> void:
	# Deliberately NO PhysicsDirectSpaceState2D / intersect_ray here.
	# Walls are determined exclusively by the two selected TileMapLayers.
	for i in range(RAY_COUNT):
		var angle: float = -PI + (float(i) + 0.5) * TWO_PI_VALUE / float(RAY_COUNT)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var hit: Vector2 = _wall_reach(cast_eye, direction, current_radius)
		# R: wall front (0..1), G: ray touches wall, A: last visible position.
		var front: float = clampf(hit.x / maxf(current_radius, 0.001), 0.0, 1.0)
		var reach: float = clampf(hit.y / maxf(current_radius, 0.001), 0.0, 1.0)
		var blocked: float = 1.0 if hit.y < current_radius - 0.01 else 0.0
		ray_image.set_pixel(i, 0, Color(front, blocked, 0.0, reach))
	ray_texture.update(ray_image)


# Returns (front_distance, visible_reach). Beyond visible_reach: DARK.
# DDA visits each map cell exactly once, independent of overlapping collision
# rectangles or number of tiles in the other, non-occluding layers.
func _wall_reach(world_origin: Vector2, world_direction: Vector2, radius: float) -> Vector2:
	if reference_layer == null or blocked_cells.is_empty():
		return Vector2(radius, radius)

	var local_origin: Vector2 = reference_layer.to_local(world_origin)
	var local_direction: Vector2 = reference_layer.to_local(world_origin + world_direction) - local_origin
	var cell: Vector2i = reference_layer.local_to_map(local_origin)
	var step_x: int = 1 if local_direction.x >= 0.0 else -1
	var step_y: int = 1 if local_direction.y >= 0.0 else -1
	var next_x: float = INF
	var next_y: float = INF
	var delta_x: float = INF
	var delta_y: float = INF

	if absf(local_direction.x) > EPSILON:
		var border_x: float = float(cell.x + (1 if step_x > 0 else 0)) * cell_size.x
		next_x = maxf(0.0, (border_x - local_origin.x) / local_direction.x)
		delta_x = cell_size.x / absf(local_direction.x)
	if absf(local_direction.y) > EPSILON:
		var border_y: float = float(cell.y + (1 if step_y > 0 else 0)) * cell_size.y
		next_y = maxf(0.0, (border_y - local_origin.y) / local_direction.y)
		delta_y = cell_size.y / absf(local_direction.y)

	var travelled: float = 0.0
	var wall_front: float = -1.0
	for _n in range(MAX_RAY_CELLS):
		if travelled >= radius:
			break
		var solid: bool = blocked_cells.has(cell)
		if solid and wall_front < 0.0:
			wall_front = travelled
		elif not solid and wall_front >= 0.0:
			# First EMPTY cell behind the entire connected wall stack.
			var wall_back: float = maxf(wall_front, travelled - wall_back_margin)
			return Vector2(wall_front, minf(radius, minf(wall_back, wall_front + wall_reveal_depth)))

		var border_distance: float = minf(next_x, next_y)
		if wall_front >= 0.0 and border_distance - wall_front >= wall_reveal_depth:
			return Vector2(wall_front, minf(radius, wall_front + wall_reveal_depth))
		if border_distance >= radius:
			return Vector2(wall_front if wall_front >= 0.0 else radius, radius)

		if absf(next_x - next_y) < EPSILON:
			cell.x += step_x
			cell.y += step_y
			next_x += delta_x
			next_y += delta_y
		elif next_x < next_y:
			cell.x += step_x
			next_x += delta_x
		else:
			cell.y += step_y
			next_y += delta_y
		travelled = border_distance

	if wall_front >= 0.0:
		return Vector2(wall_front, minf(radius, wall_front + wall_reveal_depth))
	return Vector2(radius, radius)

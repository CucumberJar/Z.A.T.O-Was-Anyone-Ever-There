extends CanvasLayer

# Z.A.T.O. — smooth elliptical fog with physics-polygon occlusion.
# Scene structure: Main/FogOfWar/Overlay (ColorRect covering the viewport).
# The physics mask should match ONLY the wall collision layer.
const FOG_SHADER: Shader = preload("res://shaders/pixel_fog.gdshader")
const RAY_COUNT: int = 384
const TWO_PI_VALUE: float = PI * 2.0

@export_group("Scene references")
@export var guard_path: NodePath = NodePath("../Guard")
@export_flags_2d_physics var occluder_mask: int = 1
@export var fog_enabled: bool = true

@export_group("Vision radius")
@export_range(60.0, 650.0, 5.0) var day_radius: float = 250.0
@export_range(60.0, 650.0, 5.0) var night_radius: float = 165.0
@export_range(60.0, 650.0, 5.0) var panic_radius: float = 200.0
@export_range(60.0, 650.0, 5.0) var elevator_radius: float = 190.0
@export_range(20.0, 1000.0, 10.0) var radius_transition_speed: float = 280.0

@export_group("Oval footprint")
# Slightly oval, without an exaggerated spotlight footprint.
@export_range(0.5, 2.0, 0.05) var oval_width: float = 1.0
@export_range(0.3, 1.5, 0.05) var oval_height: float = 0.78
# Relative to the ray origin: move bright area toward the character's feet.
@export var oval_center_offset: Vector2 = Vector2(0.0, 16.0)
@export var eye_offset: Vector2 = Vector2(0.0, -14.0)

@export_group("Smooth fog gradient")
# The four dim levels below are control points of a continuous gradient.
# 0 = linear interpolation, 1 = gentle cubic interpolation.
@export_range(0.0, 1.0, 0.05) var gradient_smoothing: float = 0.70
# Larger values keep the area near the player brighter.
@export_range(0.5, 2.0, 0.05) var gradient_exponent: float = 1.0

# A small screen-aligned pixel grid retains the low-res feel without rings.
@export_range(1.0, 8.0, 1.0) var pixel_size: float = 2.0
@export_range(0.0, 1.0, 0.01) var near_dim: float = 0.04
@export_range(0.0, 1.0, 0.01) var middle_dim: float = 0.20
@export_range(0.0, 1.0, 0.01) var far_dim: float = 0.43
@export_range(0.0, 1.0, 0.01) var edge_dim: float = 0.71
@export_range(0.6, 1.0, 0.005) var darkness: float = 0.985
@export_range(0.05, 0.95, 0.01) var near_boundary: float = 0.30
@export_range(0.05, 0.95, 0.01) var middle_boundary: float = 0.59
@export_range(0.05, 0.99, 0.01) var far_boundary: float = 0.84
@export_range(0.0, 8.0, 0.5) var visibility_feather: float = 2.0
@export var shadow_color: Color = Color(0.016, 0.022, 0.033, 1.0)

@export_group("Visible wall faces")
@export_range(0.0, 192.0, 1.0) var wall_surface_depth: float = 96.0
@export_range(0.0, 0.8, 0.01) var wall_dim: float = 0.16

@export_group("Physics performance")
# 0: recast every moving physics tick. Increase to ~0.03 for low-power devices.
@export_range(0.0, 0.15, 0.005) var ray_update_seconds: float = 0.0

@onready var overlay: ColorRect = $Overlay

var guard: CharacterBody2D
var vision_material: ShaderMaterial
var ray_image: Image
var ray_texture: ImageTexture
var current_radius: float = 250.0
var cast_radius: float = 250.0
var cast_eye: Vector2 = Vector2.ZERO
var last_eye: Vector2 = Vector2(INF, INF)
var last_radius: float = -1.0
var cast_elapsed: float = 1.0

func _ready() -> void:
	guard = get_node_or_null(guard_path) as CharacterBody2D
	if guard == null:
		push_warning("FogOfWar: Guard not found; update Guard Path in Inspector.")
		overlay.visible = false
		set_process(false)
		set_physics_process(false)
		return

	current_radius = _radius_for_phase()
	cast_eye = (guard.global_position + eye_offset).round()
	ray_image = Image.create(RAY_COUNT, 1, false, Image.FORMAT_RGBA8)
	ray_image.fill(Color(1.0, 0.0, 0.0, 1.0))
	ray_texture = ImageTexture.create_from_image(ray_image)
	vision_material = ShaderMaterial.new()
	vision_material.shader = FOG_SHADER
	vision_material.set_shader_parameter("vision_rays", ray_texture)
	vision_material.set_shader_parameter("ray_count", float(RAY_COUNT))
	overlay.material = vision_material
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = fog_enabled
	# Physics queries are performed in _physics_process, after _ready.
	_send_parameters()

func _process(_delta: float) -> void:
	if not is_instance_valid(guard) or vision_material == null:
		return
	overlay.visible = fog_enabled
	if fog_enabled:
		_send_parameters()

func _physics_process(delta: float) -> void:
	if not fog_enabled or not is_instance_valid(guard):
		return

	current_radius = move_toward(
		current_radius, _radius_for_phase(), radius_transition_speed * delta
	)
	var eye: Vector2 = (guard.global_position + eye_offset).round()
	cast_elapsed += delta
	var moved: bool = eye.distance_squared_to(last_eye) >= 1.0
	var resized: bool = absf(current_radius - last_radius) >= 0.5
	if not moved and not resized:
		return
	if cast_elapsed < ray_update_seconds:
		return

	cast_eye = eye
	# Long enough to cover an off-center ellipse from its ray origin.
	cast_radius = current_radius * maxf(oval_width, oval_height) + oval_center_offset.length()
	_cast_visibility()
	last_eye = eye
	last_radius = current_radius
	cast_elapsed = 0.0

func _cast_visibility() -> void:
	var state: PhysicsDirectSpaceState2D = guard.get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		cast_eye, cast_eye, occluder_mask
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = false
	query.exclude = [guard.get_rid()]

	for i in range(RAY_COUNT):
		var angle: float = -PI + float(i) * TWO_PI_VALUE / float(RAY_COUNT)
		query.to = cast_eye + Vector2(cos(angle), sin(angle)) * cast_radius
		var hit: Dictionary = state.intersect_ray(query)
		if hit.is_empty():
			ray_image.set_pixel(i, 0, Color(1.0, 0.0, 0.0, 1.0))
			continue
		var hit_point: Vector2 = hit["position"]
		var wall_distance: float = cast_eye.distance_to(hit_point)
		var visible_distance: float = minf(wall_distance + wall_surface_depth, cast_radius)
		ray_image.set_pixel(
			i, 0,
			Color(
				clampf(wall_distance / cast_radius, 0.0, 1.0),
				1.0,
				0.0,
				clampf(visible_distance / cast_radius, 0.0, 1.0)
			)
		)
	ray_texture.update(ray_image)

func _radius_for_phase() -> float:
	var game: Node = get_parent()
	if game == null:
		return day_radius
	match str(game.get("phase")):
		"NIGHT1", "NIGHT2": return night_radius
		"PANIC": return panic_radius
		"ELEVATOR": return elevator_radius
		_: return day_radius

func _send_parameters() -> void:
	var transform: Transform2D = guard.get_global_transform_with_canvas()
	var zoom: float = maxf(transform.basis_xform(Vector2.RIGHT).length(), 0.001)
	var translation: Vector2 = transform.origin - guard.global_position * zoom
	vision_material.set_shader_parameter("viewport_size", overlay.size)
	vision_material.set_shader_parameter("camera_translation", translation)
	vision_material.set_shader_parameter("camera_zoom", zoom)
	vision_material.set_shader_parameter("eye_world", cast_eye)
	vision_material.set_shader_parameter("vision_radius", current_radius)
	vision_material.set_shader_parameter("ray_cast_radius", cast_radius)
	vision_material.set_shader_parameter("oval_width", oval_width)
	vision_material.set_shader_parameter("oval_height", oval_height)
	vision_material.set_shader_parameter("oval_center_offset", oval_center_offset)
	vision_material.set_shader_parameter("pixel_size", pixel_size)
	vision_material.set_shader_parameter("visibility_feather", visibility_feather)
	vision_material.set_shader_parameter("gradient_smoothing", gradient_smoothing)
	vision_material.set_shader_parameter("gradient_exponent", gradient_exponent)
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

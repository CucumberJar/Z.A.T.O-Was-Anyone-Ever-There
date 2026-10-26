extends CharacterBody2D

signal touched_player

const WALK_SPEED := 130.0
const SPRITE_GLITCH: Shader = preload("res://shaders/hunter_sprite_glitch.gdshader")
const SCREEN_GLITCH: Shader = preload("res://shaders/hunter_screen_glitch.gdshader")

@export_group("Гличи / Спрайт")
@export_range(0.0, 1.0, 0.05) var sprite_glitch_strength: float = 0.65
@export_range(1.0, 30.0, 1.0) var sprite_glitch_rate: float = 9.0
@export_range(0.0, 8.0, 0.5) var sprite_slice_pixels: float = 3.0
@export_range(0.0, 4.0, 0.5) var sprite_rgb_pixels: float = 1.0

@export_group("Анимация / Спрайт")
# Два кадра 128x128: обычно атлас 256x128 (горизонтально).
# Если Visual.texture в старой сцене ещё 64x32, назначь здесь новый атлас.
@export var sprite_sheet: Texture2D
@export var frame_size: Vector2i = Vector2i(128, 128)
@export var first_frame_position: Vector2i = Vector2i.ZERO
@export var frames_horizontal: bool = true
@export_range(0.1, 3.0, 0.05) var min_frame_interval: float = 0.35
@export_range(0.1, 3.0, 0.05) var max_frame_interval: float = 0.75
@export var face_player: bool = true
@export var enable_sprite_glitch: bool = true
@export var sprite_faces_right: bool = true
@export_range(0.0, 64.0, 1.0) var turn_deadzone: float = 12.0
@export_range(0.0, 0.6, 0.01) var turn_duration: float = 0.18
@export_range(0.0, 0.95, 0.05) var turn_compression: float = 0.72
@export var debug_sprite: bool = false
@export_range(0.0, 0.3, 0.01) var width_pulse: float = 0.10
@export_range(0.1, 4.0, 0.05) var width_pulse_speed: float = 0.85
@export_range(0.0, 20.0, 0.5) var sway_degrees: float = 5.0
@export_range(0.1, 4.0, 0.05) var sway_speed: float = 1.15

@export_group("Гличи / Камера")
@export_range(50.0, 800.0, 10.0) var screen_start_distance: float = 350.0
@export_range(10.0, 350.0, 5.0) var screen_full_distance: float = 75.0
@export_range(0.0, 1.0, 0.05) var screen_max_strength: float = 0.75
@export_range(0.5, 10.0, 0.1) var screen_transition_speed: float = 2.8
@export_range(1.0, 30.0, 1.0) var screen_glitch_rate: float = 8.0
@export_range(0.0, 18.0, 0.5) var screen_slice_pixels: float = 7.0
@export_range(0.0, 8.0, 0.5) var screen_rgb_pixels: float = 2.0

var player: CharacterBody2D
var map: Node2D
var pace_timer := 0.0
var attack_timer := 0.0
var stunned := 0.0
var path: PackedVector2Array = PackedVector2Array()
var path_cursor := 1
var active := true
var fortification_level := 0
var flash_timer := 0.0

@onready var visual: Sprite2D = $Visual

var _frame_index: int = 0
var _frame_timer: float = 0.0
var _frame_origin: Vector2 = Vector2.ZERO
var _frame_step: Vector2 = Vector2.ZERO
var _sprite_material: ShaderMaterial
var _frame_animation_enabled: bool = false
var _base_visual_scale: Vector2 = Vector2.ONE
var _base_visual_rotation: float = 0.0
var _visual_time: float = 0.0
var _wanted_flip: bool = false
var _turn_elapsed: float = 0.0
var _turn_active: bool = false

var _screen_strength: float = 0.0
var _screen_overlay: ColorRect
var _screen_material: ShaderMaterial

func _ready() -> void:
	add_to_group("anomalies")
	_setup_sprite_animation()
	_setup_glitch_effects()

func _process(delta: float) -> void:
	# Визуальная анимация идёт по кадрам, а не по шагам физики.
	_update_sprite_animation(delta)

func _setup_sprite_animation() -> void:
	_base_visual_scale = visual.scale
	_base_visual_rotation = visual.rotation
	_wanted_flip = visual.flip_h
	visual.visible = true
	visual.modulate = Color.WHITE

	if sprite_sheet != null:
		visual.texture = sprite_sheet

	# Только region_rect: не совмещаем его с hframes/vframes.
	# Иначе UV шейдера и фактическая область кадра могут разойтись.
	visual.region_enabled = false
	visual.hframes = 1
	visual.vframes = 1
	visual.frame = 0
	_frame_animation_enabled = false

	if visual.texture == null:
		push_error("Hunter: не назначена текстура. Укажи Sprite Sheet на Hunter.")
		return
	if frame_size.x <= 0 or frame_size.y <= 0:
		push_error("Hunter: Frame Size должен быть больше нуля.")
		return

	var texture_size: Vector2i = Vector2i(visual.texture.get_size())
	_frame_origin = Vector2(first_frame_position)
	_frame_step = Vector2(frame_size.x, 0) if frames_horizontal else Vector2(0, frame_size.y)
	var end_of_second: Vector2i = first_frame_position + Vector2i(_frame_step) + frame_size

	if first_frame_position.x < 0 or first_frame_position.y < 0 or end_of_second.x > texture_size.x or end_of_second.y > texture_size.y:
		push_warning("Hunter: неверный размер атласа %s, ожидались 2 кадра %s. Текстура показана целиком." % [texture_size, frame_size])
		return

	visual.region_enabled = true
	visual.region_filter_clip_enabled = true
	_frame_index = 0
	_frame_animation_enabled = true

	# Не переключаемся на полностью прозрачный кадр.
	# Проверяется один раз при загрузке; на FPS не влияет.
	var source_image: Image = visual.texture.get_image()
	if source_image != null and not source_image.is_empty():
		if source_image.is_compressed():
			if source_image.decompress() != OK:
				source_image = null
		if source_image != null:
			var first_has_pixels: bool = _frame_has_pixels(source_image, first_frame_position)
			var second_has_pixels: bool = _frame_has_pixels(source_image, first_frame_position + Vector2i(_frame_step))
			if not first_has_pixels or not second_has_pixels:
				_frame_animation_enabled = false
				_frame_index = 0 if first_has_pixels else 1
				push_warning("Hunter: один кадр полностью прозрачен. Переключение выключено, показываю непустой кадр %d." % _frame_index)

	_apply_sprite_frame()
	_frame_timer = randf_range(min_frame_interval, maxf(min_frame_interval, max_frame_interval))
	if debug_sprite:
		print("Hunter sprite: texture=%s, size=%s, frame=%s, origin=%s, horizontal=%s, animation=%s" % [visual.texture.resource_path, texture_size, frame_size, first_frame_position, frames_horizontal, _frame_animation_enabled])


func _frame_has_pixels(image: Image, origin: Vector2i) -> bool:
	# Достаточно выборки через 2 пикселя: это отладочная проверка атласа.
	for y in range(origin.y, origin.y + frame_size.y, 2):
		for x in range(origin.x, origin.x + frame_size.x, 2):
			if image.get_pixel(x, y).a > 0.04:
				return true
	return false


func _apply_sprite_frame() -> void:
	if not visual.region_enabled:
		return
	var frame_position: Vector2 = _frame_origin + _frame_step * float(_frame_index)
	visual.region_rect = Rect2(frame_position, Vector2(frame_size))
	if debug_sprite:
		print("Hunter: кадр %d, region_rect=%s, flip_h=%s" % [_frame_index, visual.region_rect, visual.flip_h])


func _update_sprite_animation(delta: float) -> void:
	_visual_time += delta

	if _frame_animation_enabled:
		_frame_timer -= delta
		if _frame_timer <= 0.0:
			_frame_index = 1 - _frame_index
			_apply_sprite_frame()
			_frame_timer = randf_range(min_frame_interval, maxf(min_frame_interval, max_frame_interval))

	_update_sprite_facing(delta)

	var pulse: float = sin(_visual_time * TAU * width_pulse_speed)
	var turn_squeeze: float = 1.0
	if _turn_active and turn_duration > 0.0:
		var progress: float = clampf(_turn_elapsed / turn_duration, 0.0, 1.0)
		turn_squeeze = 1.0 - turn_compression * sin(progress * PI)
	visual.scale = Vector2(
		_base_visual_scale.x * (1.0 + pulse * width_pulse) * turn_squeeze,
		_base_visual_scale.y
	)
	visual.rotation = _base_visual_rotation + deg_to_rad(sway_degrees) * sin(_visual_time * TAU * sway_speed)


func _update_sprite_facing(delta: float) -> void:
	if face_player and is_instance_valid(player):
		var dx: float = player.global_position.x - global_position.x
		if absf(dx) > turn_deadzone:
			var face_left: bool = dx < 0.0
			var desired_flip: bool = face_left if sprite_faces_right else not face_left
			if desired_flip != _wanted_flip:
				_wanted_flip = desired_flip
				_turn_elapsed = 0.0
				_turn_active = turn_duration > 0.0
				if not _turn_active:
					visual.flip_h = _wanted_flip
				if debug_sprite:
					print("Hunter: поворот, player_dx=%.1f, flip_h=%s" % [dx, desired_flip])

	if _turn_active:
		_turn_elapsed += delta
		if _turn_elapsed >= turn_duration * 0.5:
			visual.flip_h = _wanted_flip
		if _turn_elapsed >= turn_duration:
			_turn_active = false
	else:
		visual.flip_h = _wanted_flip


func _setup_glitch_effects() -> void:
	# Материал создаём отдельно для каждого врага.
	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = SPRITE_GLITCH
	_sprite_material.set_shader_parameter("glitch_strength", sprite_glitch_strength)
	_sprite_material.set_shader_parameter("glitch_rate", sprite_glitch_rate)
	_sprite_material.set_shader_parameter("slice_offset_pixels", sprite_slice_pixels)
	_sprite_material.set_shader_parameter("color_offset_pixels", sprite_rgb_pixels)
	visual.material = _sprite_material if enable_sprite_glitch else null
	# REGION_RECT автоматически указывает на выбранный кадр; UV вручную не пересчитываем.

	# Canvas layer 0 is drawn over the world, but under the game's HUD (layer 1).
	# No changes to indoor_hunter.tscn or main_indoor.tscn are needed.
	var screen_layer := CanvasLayer.new()
	screen_layer.name = "GlitchScreenLayer"
	screen_layer.layer = 0
	add_child(screen_layer)

	_screen_overlay = ColorRect.new()
	_screen_overlay.name = "GlitchScreen"
	_screen_overlay.color = Color.WHITE
	_screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_overlay.visible = false
	screen_layer.add_child(_screen_overlay)
	_screen_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_GLITCH
	_screen_material.set_shader_parameter("strength", 0.0)
	_screen_material.set_shader_parameter("glitch_rate", screen_glitch_rate)
	_screen_material.set_shader_parameter("slice_offset_pixels", screen_slice_pixels)
	_screen_material.set_shader_parameter("color_offset_pixels", screen_rgb_pixels)
	_screen_overlay.material = _screen_material

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(player):
		velocity = Vector2.ZERO
		_update_screen_glitch(delta)
		return

	pace_timer -= delta
	attack_timer = maxf(0.0, attack_timer - delta)
	stunned = maxf(0.0, stunned - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	visual.modulate = Color(1.0, 0.65, 0.75, 1.0) if flash_timer > 0.0 else Color.WHITE

	if pace_timer <= 0.0:
		path = map.path_to(global_position, player.global_position if player.active else Vector2(984, 1248))
		path_cursor = 1
		pace_timer = 0.35
	var target: Vector2 = player.global_position if player.active else Vector2(984, 1248)
	if path.size() > 1:
		while path_cursor < path.size() - 1 and global_position.distance_to(path[path_cursor]) < 15.0:
			path_cursor += 1
		target = path[path_cursor]
	var vector: Vector2 = target - global_position
	velocity = vector.normalized() * WALK_SPEED if vector.length() > 8.0 else Vector2.ZERO
	if stunned > 0.0:
		velocity *= 0.12
	if fortification_level > 0 and global_position.distance_to(Vector2(984, 1008)) < 150.0:
		velocity *= 1.0 / (1.0 + float(fortification_level) * 0.36)
	move_and_slide()

	_update_screen_glitch(delta)
	if player.active and global_position.distance_to(player.global_position) < 35.0 and attack_timer == 0.0:
		attack_timer = 1.2
		touched_player.emit()

func _update_screen_glitch(delta: float) -> void:
	var target_strength: float = 0.0
	if active and is_instance_valid(player):
		var distance: float = global_position.distance_to(player.global_position)
		# Falloff only depends on distance. No sharp on/off when crossing a radius.
		var far_limit: float = maxf(screen_start_distance, screen_full_distance + 1.0)
		var t: float = 1.0 - smoothstep(screen_full_distance, far_limit, distance)
		target_strength = t * screen_max_strength

	_screen_strength = move_toward(_screen_strength, target_strength, delta * screen_transition_speed)
	_screen_overlay.visible = _screen_strength > 0.002
	if _screen_overlay.visible:
		_screen_material.set_shader_parameter("strength", _screen_strength)

func take_damage(_amount: int, _from_direction: Vector2 = Vector2.ZERO) -> void:
	# The experiment is dangerous: bullets stun but cannot kill the threat.
	stunned = 0.75
	flash_timer = 0.18
	print("Мне больно!!")

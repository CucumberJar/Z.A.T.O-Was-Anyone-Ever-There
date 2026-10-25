extends CharacterBody2D

signal died

const PROJECTILE: PackedScene = preload("res://scenes/projectile.tscn")
const MOVE_SPEED := 165.0
const DASH_SPEED := 355.0
const DASH_DURATION := 0.14
const DASH_COOLDOWN := 0.85
const FIRE_INTERVAL := 0.16

var health := 5
var ammo := 8
var weapon_enabled := false
var facing: Vector2 = Vector2.DOWN
var fire_cooldown := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var hurt_timer := 0.0
var dash_direction := Vector2.ZERO
var active := true
var elapsed_walk := 0.0
var shake_timer := 0.0
var shake_strength := 0.0
var muzzle_flash_timer := 0.0
var move_multiplier := 1.0

const MUZZLE_OFFSETS := [
	Vector2(2, -6),
	Vector2(-6, -8),
	Vector2(-8, -7),
	Vector2(-6, -13),
	Vector2(0, -15),
	Vector2(7, -13),
	Vector2(9, -7),
	Vector2(8, -6),
]

func _ready() -> void:
	$Camera2D.make_current()
	if has_node("MuzzleFlash"):
		$MuzzleFlash.visible = false
		$MuzzleFlash.modulate.a = 0.0
	if has_node("MuzzleLight"):
		$MuzzleLight.enabled = true
		$MuzzleLight.energy = 0.0

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector2.ZERO
		return
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	dash_time = maxf(0.0, dash_time - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	hurt_timer = maxf(0.0, hurt_timer - delta)
	shake_timer = maxf(0.0, shake_timer - delta)
	muzzle_flash_timer = maxf(0.0, muzzle_flash_timer - delta)
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim: Vector2 = get_global_mouse_position() - global_position
	if aim.length_squared() > 36.0:
		facing = aim.normalized()
	elif direction != Vector2.ZERO:
		facing = direction
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
		dash_direction = direction if direction.length_squared() > 0.0 else facing
		dash_time = DASH_DURATION
		dash_cooldown = DASH_COOLDOWN
	velocity = dash_direction * DASH_SPEED if dash_time > 0.0 else direction * MOVE_SPEED
	velocity *= move_multiplier
	move_and_slide()
	var angle_from_south: float = wrapf(facing.angle() - PI * 0.5, 0.0, TAU)
	var direction_index: int = int(floor(angle_from_south / (PI / 4.0) + 0.5)) % 8
	_update_weapon_effects(direction_index, delta)
	if velocity.length_squared() > 100.0:
		elapsed_walk += delta
	else:
		elapsed_walk = 0.0
	var frame_index: int = int(elapsed_walk * 9.0) % 3 + 1 if velocity.length_squared() > 100.0 else 0
	$Visual.region_rect = Rect2(direction_index * 32, frame_index * 64, 32, 64)
	$Visual.modulate = Color("ffd3c4") if hurt_timer > 0.0 else Color.WHITE
	if weapon_enabled and ammo > 0 and Input.is_action_pressed("fire") and fire_cooldown <= 0.0:
		_shoot(direction_index)
		fire_cooldown = FIRE_INTERVAL

func _update_weapon_effects(direction_index: int, _delta: float) -> void:
	var muzzle_offset: Vector2 = MUZZLE_OFFSETS[direction_index]
	if has_node("MuzzlePivot"):
		$MuzzlePivot.position = muzzle_offset
		$MuzzlePivot.rotation = facing.angle()
	if has_node("MuzzleFlash"):
		if muzzle_flash_timer > 0.0:
			var t := muzzle_flash_timer / 0.06
			$MuzzleFlash.visible = true
			$MuzzleFlash.modulate.a = t
			$MuzzleFlash.scale = Vector2.ONE * lerpf(1.35, 0.8, 1.0 - t)
		else:
			$MuzzleFlash.visible = false
	if has_node("MuzzleLight"):
		$MuzzleLight.position = muzzle_offset
		$MuzzleLight.energy = 1.1 * (muzzle_flash_timer / 0.06) if muzzle_flash_timer > 0.0 else 0.0
	if shake_timer > 0.0:
		$Camera2D.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
		shake_strength = lerpf(shake_strength, 0.0, 0.28)
	else:
		$Camera2D.offset = Vector2.ZERO
		shake_strength = 0.0

func _shoot(direction_index: int) -> void:
	ammo -= 1
	var projectile = PROJECTILE.instantiate()
	projectile.direction = facing
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + MUZZLE_OFFSETS[direction_index] + facing * 4.0
	muzzle_flash_timer = 0.06
	shake_timer = 0.08
	shake_strength = 1.8

func take_damage(amount: int) -> void:
	if not active or hurt_timer > 0.0:
		return
	health = maxi(0, health - amount)
	hurt_timer = 0.65
	if health == 0:
		active = false
		died.emit()

func travel_to(world_point: Vector2, boundaries: Rect2) -> void:
	global_position = world_point
	$Camera2D.limit_left = roundi(boundaries.position.x)
	$Camera2D.limit_top = roundi(boundaries.position.y)
	$Camera2D.limit_right = roundi(boundaries.end.x)
	$Camera2D.limit_bottom = roundi(boundaries.end.y)
	$Camera2D.reset_smoothing()

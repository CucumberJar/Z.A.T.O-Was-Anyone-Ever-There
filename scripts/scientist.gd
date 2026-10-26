extends CharacterBody2D
# Учёный: бродит между точками и убегает от игрока, когда тот в роли ОНО.

signal caught(scientist)

const WALK_SPEED := 115.0
const FLEE_SPEED := 135.0
const SEE_RADIUS := 300.0
const CATCH_RADIUS := 30.0

var player: CharacterBody2D
var map: Node2D
var waypoints: Array = []
var display_name := "Сотрудник"
var fortification_level := 0  # нужен, потому что main_indoor.gd обновляет это поле у всех в $Hunters

var path: PackedVector2Array = PackedVector2Array()
var path_cursor := 1
var repath := 0.0
var goal := Vector2.ZERO
var fleeing := false
var sprite: Sprite2D
var walk_time := 0.0

func _ready() -> void:
	collision_layer = 8
	collision_mask = 5
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	shape.position = Vector2(0, -4)
	add_child(shape)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/characters/guard_32x64_sheet.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 32, 64)
	sprite.position = Vector2(0, -25)
	sprite.scale = Vector2(1.5, 1.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = Color(1.0, 0.85, 0.6)  # оттенок, чтобы отличать от героя
	add_child(sprite)
	add_to_group("scientists")
	goal = global_position

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(map):
		return
	var to_player: Vector2 = player.global_position - global_position
	fleeing = to_player.length() < SEE_RADIUS
	repath -= delta
	if repath <= 0.0:
		repath = 0.5 if fleeing else 1.0
		_choose_goal()
		path = map.path_to(global_position, goal)
		path_cursor = 1
	var target: Vector2 = goal
	if path.size() > 1:
		while path_cursor < path.size() - 1 and global_position.distance_to(path[path_cursor]) < 15.0:
			path_cursor += 1
		target = path[path_cursor]
	var vector: Vector2 = target - global_position
	var speed: float = FLEE_SPEED if fleeing else WALK_SPEED
	velocity = vector.normalized() * speed if vector.length() > 8.0 else Vector2.ZERO
	move_and_slide()
	_animate(delta)
	if player.active and to_player.length() < CATCH_RADIUS:
		set_physics_process(false)
		caught.emit(self)
		queue_free()

func _choose_goal() -> void:
	if waypoints.is_empty():
		return
	if fleeing:
		var from_player: Vector2 = (player.global_position - global_position).normalized()
		var best: Vector2 = waypoints[0]
		var best_score := -INF
		for point in waypoints:
			var wp: Vector2 = point
			var toward: float = maxf(0.0, (wp - global_position).normalized().dot(from_player))
			var score: float = wp.distance_to(player.global_position) - wp.distance_to(global_position) * 0.35 - toward * 300.0
			if score > best_score:
				best_score = score
				best = wp
		goal = best
	elif global_position.distance_to(goal) < 40.0 or goal == Vector2.ZERO:
		goal = waypoints.pick_random()

func _animate(delta: float) -> void:
	if velocity.length_squared() > 100.0:
		walk_time += delta
		var angle_from_south: float = wrapf(velocity.angle() - PI * 0.5, 0.0, TAU)
		var direction_index: int = int(floor(angle_from_south / (PI / 4.0) + 0.5)) % 8
		var frame_index: int = int(walk_time * 9.0) % 3 + 1
		sprite.region_rect = Rect2(direction_index * 32, frame_index * 64, 32, 64)
	else:
		walk_time = 0.0

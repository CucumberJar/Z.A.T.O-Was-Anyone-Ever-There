extends CharacterBody2D
# Учёный.
#
# Режимы:
#   WORK         — стоит у компьютера и работает, изредка оглядывается;
#   PANIC        — мечется между случайными точками карты (start_panic());
#   GATHER       — идёт к своему месту у общей точки сбора и жмётся к остальным (start_gather());
#   FLEE_MONSTER — прежний режим: убегает от игрока, когда тот в роли ОНО (сигнал caught);
#   DEAD         — убит охотником, остаётся лежать.
#
# Создаётся из кода: SCIENTIST_SCRIPT.new(), затем setup(...), add_child(...), global_position.
# Охотники бьют через take_damage(), поэтому метод называется так же, как у остальных.

signal caught(scientist)  # прежний режим: игрок-монстр поймал учёного
signal died(scientist)    # учёного убил охотник

enum Mode { WORK, PANIC, GATHER, FLEE_MONSTER, DEAD }

const SHEET_PATH := "res://assets/characters/sientiest_handdrawn_sheet.png"
const MAX_HEALTH := 2
const WALK_SPEED := 115.0
const GATHER_SPEED := 120.0
const PANIC_SPEED_MIN := 145.0
const PANIC_SPEED_MAX := 175.0
const FLEE_SPEED := 135.0
const SEE_RADIUS := 300.0
const CATCH_RADIUS := 30.0
const ARRIVE_DISTANCE := 14.0
const GATHER_RING_RADIUS := 56.0
const FEAR_RADIUS := 260.0
# Лист такой же, как у игрока: 32x64, 4 стороны по 3 строки (стоит / идёт / бежит).
# Строка листа -> число кадров анимации.
const FRAME_COUNTS := {1: 6, 2: 9, 4: 6, 5: 7, 7: 5, 8: 6, 10: 5, 11: 6}

var player: CharacterBody2D
var map: Node2D
var waypoints: Array = []
var display_name := "Сотрудник"
var fortification_level := 0  # нужен, потому что main_indoor.gd обновляет это поле у всех в $Hunters
var health := MAX_HEALTH
var mode: Mode = Mode.WORK

var look_target := Vector2.ZERO  # куда смотрит за работой (компьютер)
var facing := Vector2.DOWN

# Навигация.
var path: PackedVector2Array = PackedVector2Array()
var path_cursor := 1
var path_goal := Vector2.INF
var repath_timer := 0.0
var _stuck_time := 0.0

# Паника и сбор.
var react_delay := 0.0
var pause_timer := 0.0
var panic_goal := Vector2.INF
var panic_speed := PANIC_SPEED_MIN
var gather_center := Vector2.ZERO
var gather_slot := Vector2.ZERO

# Прежний режим.
var fleeing := false
var flee_goal := Vector2.ZERO
var flee_goal_timer := 0.0

# Внешний вид.
var sprite: Sprite2D
var shadow: Polygon2D
var walk_time := 0.0
var glance_timer := 0.0
var glance_offset := 0.0
var hurt_timer := 0.0
var fear_timer := 0.0
var _afraid := false
var _last_row := -1


func setup(p_map: Node2D, p_player: CharacterBody2D, p_waypoints: Array, p_name: String, p_look_target: Vector2) -> void:
	map = p_map
	player = p_player
	waypoints = p_waypoints
	display_name = p_name
	look_target = p_look_target


func _ready() -> void:
	collision_layer = 8
	collision_mask = 5
	z_index = 3
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	shape.position = Vector2(0, -4)
	add_child(shape)
	shadow = Polygon2D.new()
	shadow.color = Color(0.05, 0.11, 0.14, 0.48)
	shadow.polygon = PackedVector2Array([Vector2(-12, -1), Vector2(12, -1), Vector2(16, 5), Vector2(-16, 5)])
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = load(SHEET_PATH)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 32, 64)
	sprite.position = Vector2(0, -39)
	sprite.scale = Vector2(1.5, 1.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	add_to_group("scientists")
	glance_timer = randf_range(1.0, 4.5)
	fear_timer = randf_range(0.0, 0.25)


# ---------------------------------------------------------------------------
# Команды от main_indoor.gd
# ---------------------------------------------------------------------------

# Паника: бросить работу и бегать по карте.
func start_panic() -> void:
	if mode == Mode.DEAD or mode == Mode.PANIC:
		return
	mode = Mode.PANIC
	react_delay = randf_range(0.0, 0.7)
	pause_timer = 0.0
	panic_speed = randf_range(PANIC_SPEED_MIN, PANIC_SPEED_MAX)
	panic_goal = Vector2.INF
	path_goal = Vector2.INF


# Свет погас: идти к общей точке. index/count нужны, чтобы встать вокруг неё кругом.
func start_gather(center: Vector2, index: int, count: int) -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.GATHER
	gather_center = center
	var angle: float = TAU * float(index) / float(maxi(count, 1)) + 0.4
	var slot: Vector2 = center + Vector2.from_angle(angle) * GATHER_RING_RADIUS
	if is_instance_valid(map):
		slot = map.nearest_walkable_point(slot, 4)
	gather_slot = slot
	react_delay = randf_range(0.2, 1.4)
	pause_timer = 0.0
	path_goal = Vector2.INF


# Прежняя механика: игрок в роли монстра, учёный убегает от него.
func start_flee_monster() -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.FLEE_MONSTER
	flee_goal = global_position
	flee_goal_timer = 0.0
	path_goal = Vector2.INF


func is_alive() -> bool:
	return mode != Mode.DEAD


func take_damage(amount: int, from_direction: Vector2 = Vector2.ZERO) -> void:
	if mode == Mode.DEAD:
		return
	health -= amount
	hurt_timer = 0.3
	if health <= 0:
		_die(from_direction)


# ---------------------------------------------------------------------------
# Поведение
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	hurt_timer = maxf(0.0, hurt_timer - delta)
	fear_timer -= delta
	if fear_timer <= 0.0:
		fear_timer = 0.25
		_afraid = _hunter_nearby()
	match mode:
		Mode.WORK:
			_work_step(delta)
		Mode.PANIC:
			_panic_step(delta)
		Mode.GATHER:
			_gather_step(delta)
		Mode.FLEE_MONSTER:
			_flee_monster_step(delta)


func _work_step(delta: float) -> void:
	velocity = Vector2.ZERO
	glance_timer -= delta
	if glance_timer <= 0.0:
		if glance_offset == 0.0:
			glance_offset = (1.0 if randf() < 0.5 else -1.0) * PI * 0.5
			glance_timer = randf_range(0.5, 1.0)
		else:
			glance_offset = 0.0
			glance_timer = randf_range(2.5, 6.0)
	var to_look: Vector2 = look_target - global_position
	if to_look.length_squared() > 1.0:
		facing = to_look.normalized().rotated(glance_offset)
	_update_visual(delta, false)


func _panic_step(delta: float) -> void:
	if react_delay > 0.0:
		react_delay -= delta
		velocity = Vector2.ZERO
		_update_visual(delta, false)
		return
	if pause_timer > 0.0:
		# Остановился оглядеться, прежде чем бежать дальше.
		pause_timer -= delta
		velocity = Vector2.ZERO
		facing = facing.rotated(delta * 7.0)
		_update_visual(delta, false)
		return
	var reached: bool = panic_goal == Vector2.INF
	if not reached:
		reached = _walk_to(panic_goal, panic_speed, delta, 0.5)
	if reached:
		_pick_panic_goal()
		pause_timer = randf_range(0.1, 0.45)
		velocity = Vector2.ZERO
	_update_visual(delta, true)


func _pick_panic_goal() -> void:
	var best := Vector2.INF
	var candidates: Array = waypoints.duplicate()
	candidates.shuffle()
	for point in candidates:
		var wp: Vector2 = point
		var far_enough: bool = wp.distance_to(global_position) >= 300.0
		var new_place: bool = panic_goal == Vector2.INF or wp.distance_to(panic_goal) >= 150.0
		if far_enough and new_place:
			best = wp
			break
	if best == Vector2.INF and not candidates.is_empty():
		best = candidates[0]
	if best == Vector2.INF:
		best = global_position + Vector2.from_angle(randf() * TAU) * 300.0
	panic_goal = best
	path_goal = Vector2.INF  # заставит пересчитать путь


func _gather_step(delta: float) -> void:
	if react_delay > 0.0:
		react_delay -= delta
		velocity = Vector2.ZERO
		_update_visual(delta, false)
		return
	var arrived: bool = _walk_to(gather_slot, GATHER_SPEED, delta, 0.8)
	if arrived:
		velocity = Vector2.ZERO
		# Смотрят наружу от кучки — туда, откуда придут охотники.
		var outward: Vector2 = global_position - gather_center
		if outward.length_squared() > 4.0:
			facing = outward.normalized()
	_update_visual(delta, false)


func _flee_monster_step(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var to_player: Vector2 = player.global_position - global_position
	fleeing = to_player.length() < SEE_RADIUS
	flee_goal_timer -= delta
	if flee_goal_timer <= 0.0:
		flee_goal_timer = 0.5 if fleeing else 1.0
		_choose_flee_goal()
	_walk_to(flee_goal, FLEE_SPEED if fleeing else WALK_SPEED, delta, 0.5 if fleeing else 1.0)
	_update_visual(delta, fleeing)
	if player.active and to_player.length() < CATCH_RADIUS:
		set_physics_process(false)
		caught.emit(self)
		queue_free()


func _choose_flee_goal() -> void:
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
		flee_goal = best
	elif global_position.distance_to(flee_goal) < 40.0 or flee_goal == Vector2.ZERO:
		flee_goal = waypoints.pick_random()


# Идёт к точке по сетке навигации. Возвращает true, когда дошёл
# (или застрял в стене дольше 1.2 с — тогда цель считается достигнутой).
func _walk_to(destination: Vector2, speed: float, delta: float, repath_interval: float) -> bool:
	if global_position.distance_to(destination) < ARRIVE_DISTANCE:
		velocity = Vector2.ZERO
		return true
	repath_timer -= delta
	if repath_timer <= 0.0 or destination.distance_to(path_goal) > 24.0:
		repath_timer = repath_interval
		path_goal = destination
		path = map.path_to(global_position, destination) if is_instance_valid(map) else PackedVector2Array()
		path_cursor = 1
	var target: Vector2 = destination
	var final_point: Vector2 = destination
	if path.size() > 1:
		while path_cursor < path.size() - 1 and global_position.distance_to(path[path_cursor]) < 15.0:
			path_cursor += 1
		target = path[path_cursor]
		final_point = path[path.size() - 1]
	if path_cursor >= path.size() - 1 and global_position.distance_to(final_point) < ARRIVE_DISTANCE:
		velocity = Vector2.ZERO
		return true
	var vector: Vector2 = target - global_position
	if vector.length() > 8.0:
		velocity = vector.normalized() * speed
		facing = velocity.normalized()
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if velocity.length_squared() > 1.0 and get_real_velocity().length() < speed * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.2:
		_stuck_time = 0.0
		return true
	return false


func _hunter_nearby() -> bool:
	for hunter in get_tree().get_nodes_in_group("anomalies"):
		var body: Node2D = hunter as Node2D
		if body != null and body.global_position.distance_to(global_position) < FEAR_RADIUS:
			return true
	return false


# ---------------------------------------------------------------------------
# Смерть и внешний вид
# ---------------------------------------------------------------------------

func _die(from_direction: Vector2) -> void:
	mode = Mode.DEAD
	velocity = Vector2.ZERO
	remove_from_group("scientists")
	add_to_group("scientists_dead")
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	z_index = 1
	shadow.visible = false
	# Лежит на полу на месте гибели.
	sprite.region_rect = Rect2(0, 0, 32, 64)
	sprite.rotation = (PI * 0.5) * (1.0 if from_direction.x >= 0.0 else -1.0)
	sprite.position = Vector2(0, -16)
	sprite.modulate = Color(0.62, 0.55, 0.55)
	var pool := Polygon2D.new()
	pool.color = Color(0.40, 0.04, 0.06, 0.75)
	pool.z_index = -1
	var outline := PackedVector2Array()
	for i in 12:
		var angle: float = TAU * float(i) / 12.0
		outline.append(Vector2(cos(angle) * randf_range(16.0, 26.0), sin(angle) * randf_range(8.0, 13.0)))
	pool.polygon = outline
	add_child(pool)
	move_child(pool, 0)
	died.emit(self)


func _update_visual(delta: float, running: bool) -> void:
	var moving: bool = velocity.length_squared() > 100.0
	var angle_from_south: float = wrapf(facing.angle() - PI * 0.5, 0.0, TAU)
	var direction_index: int = int(floor(angle_from_south / (PI / 4.0) + 0.5)) % 8
	var direction_group := 0
	match direction_index:
		1, 2, 3:
			direction_group = 3  # влево
		4:
			direction_group = 1  # вверх
		5, 6, 7:
			direction_group = 2  # вправо
	var row: int = direction_group * 3
	var frames := 1
	var fps := 1.0
	if moving:
		row += 2 if running else 1
		fps = 13.0 if running else 9.0
		frames = int(FRAME_COUNTS.get(row, 1))
	if row != _last_row:
		walk_time = 0.0
		_last_row = row
	var frame := 0
	if moving:
		walk_time += delta
		frame = int(walk_time * fps) % frames
	else:
		walk_time = 0.0
	sprite.region_rect = Rect2(frame * 32, row * 64, 32, 64)
	sprite.modulate = Color(1.0, 0.65, 0.65) if hurt_timer > 0.0 else Color.WHITE
	# Дрожат от страха, когда охотник близко и они стоят на месте.
	sprite.position.x = randf_range(-1.2, 1.2) if (_afraid and not moving) else 0.0

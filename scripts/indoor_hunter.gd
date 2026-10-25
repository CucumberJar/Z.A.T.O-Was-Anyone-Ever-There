extends CharacterBody2D

signal touched_player

const WALK_SPEED := 130.0
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

func _ready() -> void:
	add_to_group("anomalies")

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(player):
		velocity = Vector2.ZERO
		return
	pace_timer -= delta
	attack_timer = maxf(0.0, attack_timer - delta)
	stunned = maxf(0.0, stunned - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	$Visual.modulate = Color(1.0, 0.65, 0.75, 1.0) if flash_timer > 0.0 else Color.WHITE
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
	$Visual.rotation = sin(Time.get_ticks_msec() * .004) * 0.05
	if player.active and global_position.distance_to(player.global_position) < 35.0 and attack_timer == 0.0:
		attack_timer = 1.2
		touched_player.emit()

func take_damage(_amount: int, _from_direction: Vector2 = Vector2.ZERO) -> void:
	# The experiment is dangerous: bullets stun but cannot kill the threat.
	stunned = 0.75
	flash_timer = 0.18

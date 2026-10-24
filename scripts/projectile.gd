
extends Area2D

const IMPACT_EFFECT: PackedScene = preload("res://scenes/impact_effect.tscn")

var direction: Vector2 = Vector2.RIGHT
var speed := 485.0
var damage := 1
var lifetime := 1.25
var hit_registered := false

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    area_entered.connect(_on_area_entered)
    rotation = direction.angle()
    if has_node("ShotLight"):
        $ShotLight.enabled = true
        $ShotLight.energy = 0.52

func _physics_process(delta: float) -> void:
    global_position += direction * speed * delta
    lifetime -= delta
    if has_node("ShotLight"):
        var life_ratio := clampf(lifetime / 1.25, 0.0, 1.0)
        $ShotLight.energy = 0.2 + 0.5 * life_ratio
        $ShotLight.texture_scale = 0.17 + 0.08 * life_ratio
    if lifetime <= 0.0:
        _spawn_impact(false)
        queue_free()

func _on_body_entered(body) -> void:
    if hit_registered:
        return
    hit_registered = true
    if body.is_in_group("anomalies"):
        if body.has_method("take_damage"):
            body.take_damage(damage, direction)
    elif body.is_in_group("barricades"):
        if body.has_method("take_damage"):
            body.take_damage(damage)
    _spawn_impact(true)
    queue_free()

func _on_area_entered(_area) -> void:
    # Reserved for future hitboxes; keep bullet from silently passing through monitor areas.
    if hit_registered:
        return
    hit_registered = true
    _spawn_impact(false)
    queue_free()

func _spawn_impact(strong: bool) -> void:
    if not is_inside_tree():
        return
    var effect = IMPACT_EFFECT.instantiate()
    effect.global_position = global_position
    effect.direction = direction
    if strong:
        effect.hit_color = Color("ffd9aa")
    else:
        effect.hit_color = Color("b2c7d6")
    get_tree().current_scene.add_child(effect)

func _draw() -> void:
    draw_line(Vector2(-6, 0), Vector2(4, 0), Color("fff5cc"), 2.0)
    draw_line(Vector2(-9, 0), Vector2(-2, 0), Color(1.0, 0.74, 0.4, 0.58), 1.0)
    draw_circle(Vector2(4, 0), 1.6, Color("ffd7a4"))

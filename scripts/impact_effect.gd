
extends Node2D

var lifetime := 0.18
var max_lifetime := 0.18
var direction: Vector2 = Vector2.RIGHT
var hit_color: Color = Color("ffd7a0")

func _ready() -> void:
	if has_node("Flash"):
		$Flash.modulate = hit_color
	if has_node("Light"):
		$Light.color = Color(1.0, 0.82, 0.58, 1.0)
		$Light.energy = 0.95

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var t := lifetime / max_lifetime
	if has_node("Light"):
		$Light.energy = 0.95 * t
		$Light.texture_scale = lerpf(0.48, 0.22, 1.0 - t)
	if has_node("Flash"):
		$Flash.scale = Vector2.ONE * lerpf(1.15, 0.6, 1.0 - t)
		$Flash.modulate.a = t
	queue_redraw()

func _draw() -> void:
	var t := lifetime / max_lifetime
	var forward := direction.normalized()
	var side := Vector2(-forward.y, forward.x)
	draw_line(Vector2.ZERO, -forward * lerpf(16.0, 8.0, 1.0 - t), Color(1.0, 0.92, 0.72, 0.95 * t), 2.0)
	draw_line(Vector2.ZERO, side * 6.0 * t, Color(1.0, 0.76, 0.35, 0.82 * t), 1.0)
	draw_line(Vector2.ZERO, -side * 6.0 * t, Color(1.0, 0.76, 0.35, 0.82 * t), 1.0)
	draw_circle(Vector2.ZERO, 1.5 + 2.5 * t, Color(1.0, 0.9, 0.65, 0.9 * t))

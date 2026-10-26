extends Area2D

@export var action: String = ""
@export var label: String = "Объект"
@export_multiline var text: String = ""
@export var duration: float = 6.0

var player_inside := false

func _ready() -> void:
	add_to_group("interactables")

func _process(_delta: float) -> void:
	player_inside = false
	var guard: Node2D = get_tree().current_scene.get_node_or_null("Guard") as Node2D
	if guard == null:
		return
	for child in get_children():
		if child is CollisionShape2D and not child.disabled and child.shape != null:
			var local: Vector2 = child.to_local(guard.global_position)
			var shape: Shape2D = child.shape
			if shape is RectangleShape2D:
				var half: Vector2 = shape.size / 2.0
				if absf(local.x) <= half.x and absf(local.y) <= half.y:
					player_inside = true
			elif shape is CircleShape2D:
				if local.length() <= shape.radius:
					player_inside = true

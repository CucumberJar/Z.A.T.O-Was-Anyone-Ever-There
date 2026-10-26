extends Area2D

@export var action: String = ""      
@export var label: String = "Объект"   
@export_multiline var text: String = "" 
@export var duration: float = 6.0

var player_inside := false

func _ready() -> void:
	add_to_group("interactables")
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _on_enter(body: Node) -> void:
	if body.has_method("travel_to"):
		player_inside = true

func _on_exit(body: Node) -> void:
	if body.has_method("travel_to"):
		player_inside = false

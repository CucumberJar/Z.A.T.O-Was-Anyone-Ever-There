extends Area2D

@export var speaker: String = "Сотрудник"
@export_multiline var text: String = "Привет! Ты новенький?"
@export var duration: float = 6.0
@export var once: bool = true

var used := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if used and once:
		return
	if not body.has_method("travel_to"):
		return
	used = true
	var line: String = "%s: %s" % [speaker, text]
	get_tree().current_scene._say(line, duration)

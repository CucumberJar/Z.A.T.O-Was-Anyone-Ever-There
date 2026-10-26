extends Area2D

@export var quest_id: String = ""
@export_multiline var text: String = "Задание выполнено"

var player_inside := false

func _ready() -> void:
	body_entered.connect(func(b): player_inside = player_inside or b.has_method("travel_to"))
	body_exited.connect(func(b): player_inside = player_inside and not b.has_method("travel_to"))

func _unhandled_input(event: InputEvent) -> void:
	if player_inside and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if Quests.complete(quest_id):
			get_tree().current_scene._say(text, 5.0)

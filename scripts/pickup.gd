@tool
extends Sprite2D

const TEXTURES := {
	"medkit": preload("res://assets/indoor/medkit.png"),
	"ammo": preload("res://assets/indoor/ammo.png"),
	"metal": preload("res://assets/indoor/metal.png"),
	"battery": preload("res://assets/indoor/battery.png"),
	"coffee": preload("res://assets/indoor/coffee.png"),
}

@export_enum("medkit", "ammo", "metal", "battery", "coffee") var kind: String = "medkit":
	set(value):
		kind = value
		_update_texture()

func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update_texture()

func _update_texture() -> void:
	texture = TEXTURES.get(kind)

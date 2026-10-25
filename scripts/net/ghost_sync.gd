extends Node2D
# Добавляется в сцену main_indoor. Шлёт позицию своего охранника
# и рисует "призраков" остальных игроков.

var guard: CharacterBody2D
var ghosts: Dictionary = {}  # peer_id -> {"node": Node2D, "target": Vector2}
var timer := 0.0
var net: Node

func _ready() -> void:
	add_to_group("net_ghosts")
	guard = get_parent().get_node("Guard")
	net = get_node_or_null("/root/Net")
	if net == null:
		push_warning("Автозагрузка Net не найдена, сеть отключена")
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	timer += delta
	if timer < 0.05:
		return
	timer = 0.0
	var visual: Sprite2D = guard.get_node("Visual")
	net.send_state(guard.global_position, visual.region_rect, visual.visible)

func _process(delta: float) -> void:
	# плавное движение к последней полученной позиции
	for id in ghosts:
		var g: Dictionary = ghosts[id]
		var node: Node2D = g["node"]
		node.global_position = node.global_position.lerp(g["target"], minf(1.0, delta * 15.0))

func apply_state(id: int, pos: Vector2, region: Rect2, is_visible: bool) -> void:
	if not ghosts.has(id):
		_make_ghost(id, pos)
	var g: Dictionary = ghosts[id]
	g["target"] = pos
	var node: Node2D = g["node"]
	node.visible = is_visible
	(node.get_node("Sprite") as Sprite2D).region_rect = region

func remove_ghost(id: int) -> void:
	if ghosts.has(id):
		(ghosts[id]["node"] as Node2D).queue_free()
		ghosts.erase(id)

func _make_ghost(id: int, pos: Vector2) -> void:
	var src: Sprite2D = guard.get_node("Visual")
	var root := Node2D.new()
	var s := Sprite2D.new()
	s.name = "Sprite"
	s.texture = src.texture
	s.region_enabled = true
	s.region_rect = src.region_rect
	s.position = src.position
	s.scale = src.scale
	s.texture_filter = src.texture_filter
	s.modulate = Color(0.6, 0.9, 1.0)  # голубоватый оттенок, чтобы отличать от своего
	root.add_child(s)
	add_child(root)
	root.global_position = pos
	ghosts[id] = {"node": root, "target": pos}

extends "res://scripts/interactable.gd"

# Телепорт работает через существующие _closest_action() и _interact() игры.
# Наследуем player_inside, action и label из interactable.gd.

@export_group("Связь телепортов")
@export var linked_teleporter: NodePath
@export var exit_offset: Vector2 = Vector2.ZERO
@export_range(0.1, 1.0, 0.05) var fade_seconds: float = 0.3

@export_group("Случайная концовка")
# Проверяется только при реальном запуске телепорта, не при чтении первого диалога.
@export_range(0.0, 100.0, 0.01) var escape_chance_percent: float = 3.14
@export_range(10.0, 100.0, 1.0) var ending_text_speed: float = 42.0

@export_group("Первое использование")
@export_multiline var introduction: String = "СУПЕРКОМПЬЮТЕР: Межкомнатный перенос невозможен по инструкции.\nНажмите [E] повторно — мы сделаем вид, что ничего не произошло."

var introduced: bool = false
var awaiting_confirmation: bool = false
var transfer_busy: bool = false
var _normal_label: String = ""
var _clock: float = 0.0

var _ending_active: bool = false
var _ending_page: int = 0
var _ending_label: Label
var _ending_arrow: Label
var _ending_typing: Tween
const LUCKY_ENDING_PAGES: Array[String] = [
	"СЛУЧАЙНАЯ КОНЦОВКА: ВАС ПРОНЕСЛО.\nТелепорт отправил вас не в ту комнату...",
	"Вы стоите на улице. Вокруг снег и тишина.\nВорота комплекса остались позади.",
    "В системе вы всё ещё числитесь на смене.\nНе спорьте. Просто идите домой.\n[R] — начать заново."
]


func _ready() -> void:
	super._ready()
	_normal_label = label
	if linked_teleporter.is_empty():
		push_warning("Телепорт %s: не указан Linked Teleporter." % name)


func _process(delta: float) -> void:
	super._process(delta)
	_clock += delta
	if awaiting_confirmation and not player_inside:
		awaiting_confirmation = false
		label = _normal_label
	queue_redraw()


func use(game: Node) -> void:
	if transfer_busy or str(game.get("phase")) in ["ELEVATOR", "RESULT"]:
		return

	var guard: Node2D = game.get_node_or_null("Guard") as Node2D
	var partner: Node2D = get_node_or_null(linked_teleporter) as Node2D
	if guard == null or not bool(guard.get("active")):
		return
	if partner == null or not partner.has_method("use"):
		game.call("_say", "СИСТЕМА: Второй телепорт не найден. Проверьте Linked Teleporter.", 5.0)
		return

	# Диалог с подтверждением показываем единожды для ОБОИХ телепортов.
	if not introduced:
		introduced = true
		partner.set("introduced", true)
		awaiting_confirmation = true
		label = "Подтвердить перемещение"
		var hud: Node = game.get_node_or_null("HUD")
		if hud != null and hud.has_method("set_next_dialogue_source"):
			hud.call("set_next_dialogue_source", "computer")
		game.call("_say", introduction, 9.0)
		return

	var first_confirmation: bool = awaiting_confirmation
	awaiting_confirmation = false
	label = _normal_label
	if first_confirmation:
		game.call("_say", "СУПЕРКОМПЬЮТЕР: Передача подтверждена. Не смотрите на стены.", 3.0)
	if randf() < escape_chance_percent / 100.0:
		_begin_lucky_ending(game, guard, partner)
	else:
		_begin_transfer(game, guard, partner)


# Редкая альтернативная концовка. Используем уже созданный экран затемнения
# и визуальное оформление существующей диалоговой панели HUD.
func _begin_lucky_ending(game: Node, guard: Node2D, partner: Node2D) -> void:
	var veil: ColorRect = game.get("transition_veil") as ColorRect
	if veil == null:
		push_error("Телепорт: не найден transition_veil в main_indoor.gd")
		return

	transfer_busy = true
	partner.set("transfer_busy", true)
	guard.set("active", false)

	var fade: Tween = create_tween()
	fade.tween_property(veil, "modulate:a", 1.0, fade_seconds)
	fade.tween_callback(Callable(self, "_show_lucky_ending").bind(game))


func _show_lucky_ending(game: Node) -> void:
	if not is_instance_valid(game):
		return

	var hud: CanvasLayer = game.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		push_error("Телепорт: не найден HUD для случайной концовки")
		return
	var source_panel: Control = hud.get_node_or_null("RadioPanel") as Control
	if source_panel == null:
		push_error("Телепорт: не найден HUD/RadioPanel")
		return

	# Черный экран выше игрового мира, стандартного HUD и лифтового затемнения.
	var ending_layer := CanvasLayer.new()
	ending_layer.name = "LuckyEndingScreen"
	ending_layer.layer = 95
	game.add_child(ending_layer)

	var background := ColorRect.new()
	background.name = "BlackBackground"
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Дублируем оформление оригинального диалога: его текстуры, шрифты и цвета.
	var dialogue: Control = source_panel.duplicate() as Control
	dialogue.name = "EndingDialogue"
	ending_layer.add_child(dialogue)
	dialogue.visible = true
	dialogue.modulate = Color.WHITE
	dialogue.position = source_panel.position
	_ending_label = dialogue.get_node_or_null("Radio") as Label
	var title: Label = dialogue.get_node_or_null("RadioTitle") as Label
	_ending_arrow = dialogue.get_node_or_null("Arrow") as Label
	if title != null:
		title.text = "ВАС ПРОНЕСЛО"
	if _ending_arrow != null:
		_ending_arrow.visible = true

	game.set("phase", "RESULT")
	game.call("_clear_hunters")
	hud.visible = false
	hud.set_process_unhandled_key_input(false)
	_ending_active = true
	_ending_page = 0
	_show_lucky_page()


func _show_lucky_page() -> void:
	if _ending_label == null:
		return
	if _ending_typing != null and _ending_typing.is_running():
		_ending_typing.kill()

	var content: String = LUCKY_ENDING_PAGES[_ending_page]
	_ending_label.text = content
	_ending_label.visible_characters = 0
	if _ending_arrow != null:
		_ending_arrow.text = "[E] ДАЛЕЕ" if _ending_page < LUCKY_ENDING_PAGES.size() - 1 else "[R] ЗАНОВО"

	_ending_typing = create_tween()
	_ending_typing.tween_property(
		_ending_label, "visible_characters", content.length(),
		maxf(0.1, float(content.length()) / ending_text_speed)
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _ending_active or not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_E:
		return
	get_viewport().set_input_as_handled()

	if _ending_label != null and _ending_label.visible_characters >= 0 and _ending_label.visible_characters < _ending_label.text.length():
		if _ending_typing != null and _ending_typing.is_running():
			_ending_typing.kill()
		_ending_label.visible_characters = -1
		return

	if _ending_page < LUCKY_ENDING_PAGES.size() - 1:
		_ending_page += 1
		_show_lucky_page()


func _begin_transfer(game: Node, guard: Node2D, partner: Node2D) -> void:
	var veil: ColorRect = game.get("transition_veil") as ColorRect
	if veil == null:
		push_error("Телепорт: не найден transition_veil из main_indoor.gd")
		return

	transfer_busy = true
	partner.set("transfer_busy", true)
	guard.set("active", false)

	var transition: Tween = create_tween()
	transition.tween_property(veil, "modulate:a", 1.0, fade_seconds)
	transition.tween_callback(Callable(self, "_move_guard").bind(game, guard, partner))
	transition.tween_property(veil, "modulate:a", 0.0, fade_seconds)
	transition.tween_callback(Callable(self, "_finish_transfer").bind(guard, partner))


func _move_guard(game: Node, guard: Node2D, partner: Node2D) -> void:
	if not is_instance_valid(guard) or not is_instance_valid(partner):
		return
	var target_position: Vector2 = partner.global_position + partner.get("exit_offset")
	var indoor: Node2D = game.get_node_or_null("Indoor") as Node2D
	if indoor != null and indoor.has_method("nearest_walkable_point"):
		# Навигация карты работает в локальных координатах Indoor.
		var local_target: Vector2 = indoor.to_local(target_position)
		var safe_local: Vector2 = indoor.call("nearest_walkable_point", local_target)
		target_position = indoor.to_global(safe_local)

	guard.global_position = target_position
	var camera: Camera2D = guard.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()


func _finish_transfer(guard: Node2D, partner: Node2D) -> void:
	if is_instance_valid(guard):
		guard.set("active", true)
	transfer_busy = false
	if is_instance_valid(partner):
		partner.set("transfer_busy", false)


func _draw() -> void:
	# Простая пиксельная визуализация без внешних ассетов.
	var pulse: float = 0.5 + 0.5 * sin(_clock * 2.8)
	var active_color := Color(0.38, 0.94, 0.83) if player_inside else Color(0.27, 0.66, 0.69)
	draw_rect(Rect2(-19, -19, 38, 38), Color(0.04, 0.07, 0.12, 0.9), true)
	draw_rect(Rect2(-19, -19, 38, 38), active_color, false, 2.0)
	draw_arc(Vector2.ZERO, 13.0 + pulse * 2.0, 0.0, TAU, 32, active_color, 2.0, false)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(0.35, 0.73, 0.98, 0.65 + pulse * 0.3), 1.0, false)
	draw_line(Vector2(-6, 0), Vector2(6, 0), active_color, 1.0)
	draw_line(Vector2(0, -6), Vector2(0, 6), active_color, 1.0)

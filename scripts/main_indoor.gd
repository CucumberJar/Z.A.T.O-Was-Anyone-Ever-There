extends Node2D

const HUNTER_SCENE: PackedScene = preload("res://scenes/indoor_hunter.tscn")
const SUPERCOMPUTER_SCENE: PackedScene = preload("res://scenes/minigames/supercomputer.tscn")
const SCIENTIST_SCRIPT: GDScript = preload("res://scripts/scientist.gd")
const SCIENTIST_COUNT := 5
const SCIENTIST_NAMES := ["Игорь из бухгалтерии", "Стажёр Паша", "Тамара Ивановна", "Лаборантка Вера", "Охранник Лёха", "Сергей из отдела закупок", "Доктор Белов"]
const ITEM_FILES := {
	"metal": "res://assets/indoor/metal.png",
	"battery": "res://assets/indoor/battery.png",
	"coffee": "res://assets/indoor/coffee.png",
	"medkit": "res://assets/indoor/medkit.png",
	"ammo": "res://assets/indoor/ammo.png"
}
const NIGHT_DURATION := 40.0
const DAY_DURATION := 60.0
const SORTIE_DURATION := 12.0
const DAY3_QUESTS := ["power", "fort", "terminal"]
const QUESTS_TO_STAY_HUMAN := 2
const NIGHT_PHASES := ["NIGHT1", "NIGHT2", "NIGHT3"]
const TIMED_PHASES := ["PANIC", "NIGHT1", "DAY2", "SORTIE", "NIGHT2", "DAY3", "NIGHT3"]


@export_group("Катсцена / Позиции")
@export var cabin_spawn_position: Vector2 = Vector2(3000.0, 1008.0)
@export var institute_arrival_position: Vector2 = Vector2(340.0, 1270.0)
@export var cabin_camera_bounds: Rect2 = Rect2(-256.0, -256.0, 4096.0, 2304.0)
@export var institute_camera_bounds: Rect2 = Rect2(0.0, 0.0, 2304.0, 1440.0)
@export_group("Катсцена / Выход")
@export var open_institute_elevator_door: bool = true

@export_group("Катсцена / Освещение")
@export var elevator_ambient_color: Color = Color(0.80, 0.84, 0.88, 1.0)
@export var hide_main_lights_in_elevator: bool = false

@export_group("Совместимость")
@export var movement_limits: Rect2 = Rect2(0.0, 0.0, 2304.0, 1440.0)

@export_group("Катсцена / Поездка")
@export_range(2.0, 90.0, 0.5) var elevator_ride_duration: float = 20.0
@export_range(0.0, 8.0, 0.1) var elevator_camera_shake: float = 2.6
@export var allow_elevator_skip: bool = false
@export_range(0.1, 2.0, 0.05) var elevator_fade_duration: float = 0.55
@export_multiline var elevator_arrival_message: String = "ЛИФТ ПРИБЫЛ. ЭТАЖ -9: ОТДЕЛ «КОНТУР».\nПодойдите к двери и нажмите [E]."

@export_group("Катсцена / Реплики")
@export_range(0.0, 90.0, 0.1) var line_1_at: float = 3.5
@export_range(0.0, 90.0, 0.1) var line_2_at: float = 13.0
@export_range(0.0, 90.0, 0.1) var line_3_at: float = 24.5

@onready var guard = $Guard
@onready var map = $Indoor
@onready var ambient: CanvasModulate = $Ambient
@onready var status_label: Label = $HUD/Info/Summary
@onready var objective_label: Label = $HUD/Target
@onready var radio_label: Label = $HUD/RadioPanel/Radio
@onready var message_label: Label = $HUD/Message
@onready var vitals_label: Label = $HUD/VitalPanel/Vitals
@onready var phase_label: Label = $HUD/PhasePanel/Phase
@onready var fog_of_war: Node = get_node_or_null("FogOfWar")

var transition_layer: CanvasLayer
var transition_veil: ColorRect
var phase := "ELEVATOR"
var elevator_arrived := false
var elevator_ride_time := 0.0
var elevator_floor := 1
var elevator_line_index := 0
var elevator_leaving := false
var phase_timer := 0.0
var fade_timer := 0.0
var radio_timer := 0.0
var intro_step := 0
var health := 3
var is_hiding := false
var has_manual := false
var reset_used := false
var pc_uses := 0
var fixed_issues := 0
var built_barricades := 0
var scrap := 0
var batteries := 0
var coffee := 0
var medicine := 0
var read_hr := false
var damaged := 0
var pickups: Dictionary = {}
var night_number := 0
var alarm_flash := 0.0
var ventilation_fault := false
var malfunction_hint := false
var teleported := false
var computer_open := false
var quests: Dictionary = {"power": false, "fort": false, "terminal": false}
var stayed_human := true
var monster_mode := false
var monster_sprite: Sprite2D
var scientists_caught := 0
var scientists_total := 0

# Чёрная заливка экрана создаётся кодом, никакие узлы в сцене не нужны.
func _create_transition_overlay() -> void:
	transition_layer = CanvasLayer.new()
	transition_layer.name = "ElevatorFade"
	transition_layer.layer = 90
	add_child(transition_layer)
	transition_veil = ColorRect.new()
	transition_veil.name = "Fade"
	transition_veil.color = Color.BLACK
	transition_veil.modulate.a = 0.0
	transition_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_layer.add_child(transition_veil)
	transition_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _elevator_script_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = [
		{"at": line_1_at, "id": "intro"},
		{"at": line_2_at, "id": "intro1"},
		{"at": line_3_at, "id": "intro2"},
	]
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
	return lines

func _ready() -> void:
	randomize()
	guard.died.connect(_death)
	guard.health = 3
	guard.ammo = 0
	guard.weapon_enabled = false
	_create_transition_overlay()
	Quests.reset()
	Quests.completed.connect(_on_quest_completed)
	Quests.start("elevator")
	_update_hunting_fog()
	guard.travel_to(cabin_spawn_position, cabin_camera_bounds)
	guard.get_node("Camera2D").zoom = Vector2(1, 1)
	guard.active = false 
	_say("ЛИФТ / СЕКРЕТНЫЙ ИНСТИТУТ / 1987\nСпуск на рабочий уровень...", 3.0)
	$Collectibles.visible = false
	_refresh()
	
func _spawn_pickups() -> void:
	$Collectibles.visible = true
	for node in $Collectibles.get_children():
		pickups[str(node.name)] = node

func _update_hunting_fog() -> void:
	if fog_of_war == null:
		return
	fog_of_war.set("fog_enabled", phase == "NIGHT1" or phase == "NIGHT3")

func _process(delta: float) -> void:
	_update_hunting_fog()
	if computer_open:
		return
	radio_timer = maxf(radio_timer - delta, 0.0)
	if radio_timer <= 0.0 and phase != "RESULT":
		radio_label.text = ""
	alarm_flash = maxf(0.0, alarm_flash - delta)
	if phase == "RESULT":
		return
	if phase == "ELEVATOR" and not elevator_arrived:
		_update_elevator_ride(delta)
	if phase in TIMED_PHASES:
		phase_timer -= delta
		if phase_timer <= 0.0:
			Quests.complete_timed()
	if phase == "DAY2" and ventilation_fault and Rect2(1392, 768, 384, 288).has_point(guard.global_position):
		if not is_hiding:
			fade_timer -= delta
			if fade_timer < -1.0:
				fade_timer = 3.5
				guard.take_damage(1)
				_say("Воздух слишком сладкий. Фильтры на складе работают странно.", 3.0)
	if phase in NIGHT_PHASES and is_hiding:
	
		pass
	if phase == "DAY2" and not teleported and phase_timer <= 9.0:
		teleported = true
		guard.travel_to(Vector2(1944, 408), Rect2(0, 0, 2304, 1440))
		_say("[ТЕЛЕПОРТАЦИЯ НЕ СУЩЕСТВУЕТ]\nПредставитель администрации сообщает, что это ошибка навигации.", 7.0)
	if phase == "PANIC" and not reset_used and phase_timer <= 28.0 and radio_timer <= 0.0:
		_say("HR: Выходы аннулированы. Соберите всё полезное. Кого съедят — тот будет уволен. ♥", 8.0)
	if monster_mode:
		# Баррикады замедляют и ОНО: чем больше построил днём, тем медленнее у кабинета.
		var near_office: bool = guard.global_position.distance_to(Vector2(984, 1008)) < 150.0
		guard.move_multiplier = 1.0 / (1.0 + float(built_barricades) * 0.36) if near_office else 1.0
	_update_visuals(delta)
	_refresh()

func _update_visuals(_delta: float) -> void:
	var at_night: bool = phase in NIGHT_PHASES
	var map_lights: CanvasItem = map.get_node_or_null("Lights") as CanvasItem
	if map_lights != null:
		map_lights.visible = phase != "ELEVATOR" or not hide_main_lights_in_elevator
	if at_night:
		ambient.color = Color(0.19, 0.27, 0.40, 1.0)
		if phase == "NIGHT2":
			ambient.color = Color(0.17, 0.34, 0.22, 1.0)  # зеленоватый «терминальный» оттенок
		guard.get_node("Flashlight").energy = 1.25 if not is_hiding else 0.0
		map.get_node("Lights").modulate = Color(0.48, 0.55, 0.62, 1)
	elif phase == "SORTIE":
		ambient.color = Color(0.35, 0.12, 0.12, 1.0)
		guard.get_node("Flashlight").energy = 1.25
		map.get_node("Lights").modulate = Color(0.55, 0.45, 0.45, 1)
	elif phase == "ELEVATOR":
		var flicker: float = 0.03 if not elevator_arrived and int(Time.get_ticks_msec() / 90) % 11 == 0 else 0.0
		ambient.color = elevator_ambient_color.lightened(flicker)
		guard.get_node("Flashlight").energy = 0.0
	elif phase == "PANIC":
		ambient.color = Color(0.74, 0.47, 0.47, 1) if int(Time.get_ticks_msec() / 550) % 2 == 0 else Color(0.73, 0.77, 0.73, 1)
		guard.get_node("Flashlight").energy = 0.0
	elif phase == "DAY2" or phase == "DAY3":
		ambient.color = Color(0.77, 0.82, 0.77, 1.0)
		guard.get_node("Flashlight").energy = 0.0
		map.get_node("Lights").modulate = Color.WHITE
	else:
		ambient.color = Color(0.89, 0.90, 0.84, 1.0)
		guard.get_node("Flashlight").energy = 0.0
		map.get_node("Lights").modulate = Color.WHITE

func _update_elevator_ride(delta: float) -> void:
	elevator_ride_time += delta
	var t: float = elevator_ride_time
	var progress: float = clampf(t / elevator_ride_duration, 0.0, 1.0)
	var camera: Camera2D = guard.get_node("Camera2D")
	var shake: float = lerpf(elevator_camera_shake, 0.0, smoothstep(0.65, 1.0, progress))
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	elevator_floor = 1 + mini(8, int(progress * 9.0))
	var lines: Array[Dictionary] = _elevator_script_lines()
	while elevator_line_index < lines.size() and t >= float(lines[elevator_line_index]["at"]):
		var start_at: float = float(lines[elevator_line_index]["at"])
		var next_at: float = float(lines[elevator_line_index + 1]["at"]) if elevator_line_index + 1 < lines.size() else elevator_ride_duration
		_say(Dialogies.t(str(lines[elevator_line_index]["id"])), maxf(2.0, next_at - start_at))
		elevator_line_index += 1
	if t >= elevator_ride_duration:
		elevator_arrived = true
		camera.offset = Vector2.ZERO
		guard.active = true
		_say(elevator_arrival_message, 7.0)

func _open_elevator_door() -> void:
	if elevator_leaving or not elevator_arrived:
		return
	elevator_leaving = true
	guard.active = false
	# Затемнение создано программно в _ready().
	var transition: Tween = create_tween()
	transition.tween_property(transition_veil, "modulate:a", 1.0, elevator_fade_duration)
	transition.tween_callback(_transfer_from_cabin)
	transition.tween_property(transition_veil, "modulate:a", 0.0, elevator_fade_duration)
	transition.tween_callback(_finish_elevator_exit)

func _transfer_from_cabin() -> void:
	phase = "INTRO"
	guard.travel_to(institute_arrival_position, institute_camera_bounds)
	guard.get_node("Camera2D").offset = Vector2.ZERO
	# Дверь на карте необязательна: отсутствующий узел больше не вызывает ошибки.
	if open_institute_elevator_door:
		var door_collision: CollisionShape2D = get_node_or_null("ElevatorDoor/Collision") as CollisionShape2D
		if door_collision != null:
			door_collision.set_deferred("disabled", true)
		var door_visual: CanvasItem = get_node_or_null("ElevatorDoor/Visual") as CanvasItem
		if door_visual != null:
			door_visual.visible = false

func _finish_elevator_exit() -> void:
	guard.active = true
	elevator_leaving = false

func _say(text: String, duration: float = 6.0) -> void:
	radio_label.text = text
	radio_timer = duration

func _unhandled_input(event: InputEvent) -> void:
	if computer_open:
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.physical_keycode == KEY_E:
			_interact()
		elif ke.physical_keycode == KEY_R and phase == "RESULT":
			get_tree().reload_current_scene()

func _closest_action() -> Dictionary:
	if is_hiding:
		return {"name":"locker", "pos":guard.global_position, "label":"Выйти из шкафа"}
	var in_cabin: bool = phase == "ELEVATOR"
	if in_cabin and (not elevator_arrived or elevator_leaving):
		return {}
	var entry: Dictionary = {}
	if not in_cabin:
		var best_pickup := 82.0
		for k in pickups.keys():
			var node: Sprite2D = pickups[k]
			var dist: float = guard.global_position.distance_to(node.global_position)
			if dist < best_pickup:
				best_pickup = dist
				entry = {"name":"pickup", "key":k, "pos":node.global_position, "label":"Подобрать предмет"}
	if entry.is_empty():
		var best_zone := INF
		for zone in get_tree().get_nodes_in_group("interactables"):
			if not zone.player_inside:
				continue
			if (zone.action == "elevator") != in_cabin:
				continue
			var zone_dist: float = guard.global_position.distance_to(zone.global_position)
			if zone_dist < best_zone:
				best_zone = zone_dist
				entry = {"name": zone.action, "pos": zone.global_position, "label": zone.label, "node": zone}
	return entry

func _interact() -> void:
	if phase == "RESULT":
		return
	if phase == "ELEVATOR" and not elevator_arrived:
		if allow_elevator_skip:
			elevator_ride_time = elevator_ride_duration
		return
	var entry := _closest_action()
	if entry.is_empty():
		return
	var key: String = str(entry["name"])
	print("E: ", key, " | manual активно: ", "manual" in Quests.active)
	match key:
		"elevator":
			_open_elevator_door()
			Quests.complete("elevator")
		"storage_door":
			_say(Dialogies.t("storage"),5.0)
			Quests.complete("manual")
		"storage_table":
			_say(Dialogies.t("storage_door"),5.0)	
		"termenal":
			_open_supercomputer()
			Quests.complete("computer")
			var zone = entry.get("node")
			if zone != null and zone.text != "":
				_say(zone.text, zone.duration)
		"reset":
			reset_used = true
			Quests.complete("reset")
		"pickup":
			var item_id: String = str(entry["key"])
			var item: Sprite2D = pickups[item_id]
			var item_kind: String = item.kind
			item.queue_free()
			pickups.erase(item_id)
			match item_kind:
				"metal": scrap += 1
				"battery": batteries += 1
				"coffee": coffee += 1
				"medkit":
					medicine += 1
					guard.health = mini(3, guard.health + 1)
				"ammo": guard.ammo += 6
			_say("Получено: %s." % item_kind.to_upper(), 3.5)
  

func _open_supercomputer() -> void:
	if computer_open:
		return
	computer_open = true
	guard.active = false
	$HUD.visible = false
	$HUD.set_process_unhandled_key_input(false)
	var terminal: Node = SUPERCOMPUTER_SCENE.instantiate()
	add_child(terminal)
	terminal.connect("experiment_failed", Callable(self, "_on_computer_failed"))
	terminal.connect("cancelled", Callable(self, "_on_computer_cancelled"))
	terminal.call("open", has_manual)

func _close_computer_interface() -> void:
	computer_open = false
	guard.active = true
	$HUD.visible = true
	$HUD.set_process_unhandled_key_input(true)

func _on_computer_cancelled() -> void:
	_close_computer_interface()
	_say("ПРОТОКОЛ ЗАПУСКА ОТМЕНЁН. ВЕДОМСТВО НИЧЕГО НЕ ЗАМЕТИЛО.", 4.0)

func _start_panic() -> void:
	phase = "PANIC"
	guard.weapon_enabled = false
	_say("СУПЕРКОМПЬЮТЕР: 99.99% ... BSOD.\nТРЕВОГА! ВОЗМОЖНО САМОУНИЧТОЖЕНИЕ КОМПЛЕКСА", 11.0)

func _start_first_night() -> void:
	phase_timer = NIGHT_DURATION
	phase = "PANIC"
	guard.weapon_enabled = true
	_say("ИНТЕРКОМ:\n ВНИМАНИЕ!!! ВКЛЮЧЕН РЕЖИМ ЧС, в соответствии с ГОСТ1487, электричество будет отключено для нагнетания атмосферы", 12.0)
	if guard.ammo < 4:
		guard.ammo = 4
		
	else:
		_spawn_hunter()
		_say("HR: В целях экологии свет выключен.\nКого съедят — тот будет уволен. Ваш HR ♥", 10.0)

func _spawn_hunter() -> void:
	var hunter = HUNTER_SCENE.instantiate()
	hunter.player = guard
	hunter.map = map
	hunter.fortification_level = built_barricades
	hunter.touched_player.connect(_hunter_hit)
	$Hunters.add_child(hunter)
	hunter.global_position = Vector2(1944, 840) if night_number == 1 else Vector2(1944, 408)

func _hunter_hit() -> void:
	if is_hiding or phase == "RESULT":
		return
	guard.take_damage(1)
	if not guard.active or guard.health == 0:
		_death()

func _start_day2() -> void:
	_clear_hunters()
	if is_hiding:
		is_hiding = false
		guard.active = true
		guard.get_node("Visual").visible = true
		guard.get_node("Shadow").visible = true
	phase = "DAY2"
	phase_timer = DAY_DURATION
	ventilation_fault = true
	malfunction_hint = false
	fade_timer = 3.5
	guard.weapon_enabled = false
	_say("УТРО. Монстр ушёл в вентиляцию. Теперь дефицит опаснее монстра.\nВозьмите ресурсы у выживших и укрепите кабинет. Законы физики изменились без объявления.", 10.0)

func _become_monster() -> void:
	monster_mode = true
	scientists_caught = 0
	guard.weapon_enabled = false
	guard.get_node("Visual").visible = false
	if monster_sprite == null:
		monster_sprite = Sprite2D.new()
		monster_sprite.texture = load("res://assets/characters/anomaly_32_sheet.png")
		monster_sprite.region_enabled = true
		monster_sprite.region_rect = Rect2(0, 0, 32, 32)
		monster_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		monster_sprite.scale = Vector2(1.7, 1.7)
		monster_sprite.position = Vector2(0, -14)
		guard.add_child(monster_sprite)
	monster_sprite.visible = true

func _become_human() -> void:
	monster_mode = false
	guard.move_multiplier = 1.0
	guard.get_node("Visual").visible = true
	if monster_sprite != null:
		monster_sprite.visible = false


func _start_sortie() -> void:
	_clear_hunters()
	phase = "SORTIE"
	phase_timer = SORTIE_DURATION
	guard.weapon_enabled = false
	_say("[ЗАГЛУШКА: ВЫЛАЗКА]\nЗадание: восстановить питание. Свет гаснет, за вами гонится шиза.\nЗдесь будет погоня и починка щитка.", 10.0)

func _start_day3() -> void:
	_clear_hunters()
	_become_human()
	if is_hiding:
		is_hiding = false
		guard.active = true
		guard.get_node("Visual").visible = true
		guard.get_node("Shadow").visible = true
	phase = "DAY3"
	phase_timer = DAY_DURATION
	quests = {"power": false, "fort": false, "terminal": false}
	guard.weapon_enabled = false
	_say("ДЕНЬ 3.\nЗадания: питание (щиток), укрепить кабинет, сохранить данные (терминал).\nУспейте как можно больше.", 10.0)

func _ending_hero() -> void:
	phase = "RESULT"
	guard.active = false
	_clear_hunters()
	message_label.visible = true
	message_label.text = "СПАСЁННЫЙ ГЕРОЙ\nУтром выживших выводят из комплекса. Тебя называют героем.\nНа улице твоя тень движется не так, как ты.\n\nR — заново"

func _ending_vr() -> void:
	phase = "RESULT"
	guard.active = false
	_clear_hunters()
	message_label.visible = true
	message_label.text = "VR-ПРОВЕРКА\nМир рассыпается на пиксели. Ты снимаешь шлем в лифте.\nРезультат теста: непригоден. Вы уволены.\n\nR — заново"

func _build_barrier() -> void:
	var marker := Polygon2D.new()
	marker.color = Color(0.70, 0.56, 0.34, 1)
	marker.polygon = PackedVector2Array([Vector2(-29, -7), Vector2(29, -7), Vector2(29, 7), Vector2(-29, 7)])
	marker.position = Vector2(912 + built_barricades * 36, 1020)
	$Barricades.add_child(marker)
	# Gameplay advantage: barricades slow hunters within the office entry zone.
	for hunter in $Hunters.get_children():
		hunter.fortification_level = built_barricades

func _clear_hunters() -> void:
	for h in $Hunters.get_children():
		h.queue_free()

func _death() -> void:
	if phase == "RESULT":
		return
	phase = "RESULT"
	guard.active = false
	_clear_hunters()
	message_label.visible = true
	message_label.text = "ДОСТУП АННУЛИРОВАН\nСОТРУДНИК НЕ ЧИСЛИТСЯ\n\nR — начать заново"

func _on_quest_completed(id: String) -> void:
	match id:
		"elevator":
			Quests.start("manual")
		"manual":
			Quests.start("computer")
		"computer":
			Quests.start("reset")
			_start_panic()
		"reset":
			Quests.start("gather")
			_spawn_pickups()
			_start_first_night()
		"gather":
			Quests.start("night")	
		"night":
			Quests.start("sortie")
			_start_day2()
		"sortie":
			Quests.start("fort")
			_start_sortie()
		"fort":
			Quests.start("hunt")
		"hunt":
			Quests.start("final")
			_start_day3()
		"final":
			_ending_hero()

func _finish() -> void:
	phase = "RESULT"
	guard.active = false
	_clear_hunters()
	message_label.visible = true
	if fixed_issues >= 2:
		message_label.text = "КОРПОРАТИВНЫЙ ДЗЕН\nТы слился с суперкомпьютером.\nСледующий сотрудник уже едет в лифте.\n\nR — заново"
	elif pc_uses >= 3:
		message_label.text = "VR СТРЕСС-ТЕСТ\nСимуляция окончена. На двери лифта твой номер.\n\nR — заново"
	else:
		message_label.text = "НЕЙРОСЛОП И ДОГОВОР\nПод маской биооружия — блогер с кольцевой лампой.\nВ отчёте сказано, что это был тимбилдинг.\n\nR — заново"

func _current_quest_title() -> String:
	for id in Quests.active:
		if not Quests.is_done(id):
			return str(Quests.quests[id]["title"])
	return ""
	
func _refresh() -> void:
	status_label.text = ""
	vitals_label.text = ("ПОЙМАНО %d/%d" % [scientists_caught, scientists_total]) if monster_mode else ("ПАТР %02d" % guard.ammo)
	var remaining: int = maxi(0, ceili(phase_timer))
	phase_label.text = "%02d:%02d" % [floori(float(remaining) / 60.0), remaining % 60] if phase in TIMED_PHASES else "1987"
	var entry: Dictionary = _closest_action()
	if not entry.is_empty():
		objective_label.text = "[E] " + str(entry["label"])
	elif phase == "ELEVATOR" and not elevator_arrived:
		objective_label.text = ("Спуск: этаж -%d  ([E] — пропустить)" if allow_elevator_skip else "Спуск: этаж -%d") % elevator_floor
	elif phase == "RESULT":
		objective_label.text = "Итоги смены"
	else:
		var title: String = _current_quest_title()
		objective_label.text = title if title != "" else "Исследовать комплекс"

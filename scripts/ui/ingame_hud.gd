extends CanvasLayer

const SKIN = preload("res://scripts/ui/ui_skin.gd")
const SAVE_PATH := "user://zato_slot1.json"

# Источник определяется автоматически по тексту. Для нестандартных реплик:
# HUD.set_next_dialogue_source("computer") перед game._say(...).
@export_group("Диалоги / Анимация")
@export_range(0.0, 0.8, 0.01) var appear_seconds: float = 0.24
@export_range(0.0, 0.8, 0.01) var disappear_seconds: float = 0.20
@export_range(5.0, 100.0, 1.0) var characters_per_second: float = 42.0
@export_range(0.0, 32.0, 1.0) var slide_distance: float = 10.0

@export_group("Диалоги / Фильтры")
@export_range(0.0, 0.35, 0.01) var scanline_intensity: float = 0.10
@export_range(0.0, 1.0, 0.05) var dialogue_filter_strength: float = 0.85
@export_range(0.0, 1.0, 0.05) var name_filter_strength: float = 1.0

@onready var radio_label: Label = $RadioPanel/Radio
@onready var radio_panel: Control = $RadioPanel
@onready var radio_title: Label = $RadioPanel/RadioTitle
@onready var radio_paper: TextureRect = $RadioPanel/Paper
@onready var radio_arrow: Label = $RadioPanel/Arrow
@onready var final_message: Label = $Message
@onready var pause_root: Control = $PauseRoot
@onready var settings_page: Control = $PauseRoot/SettingsPage
@onready var dossier_page: Control = $PauseRoot/DossierPage
@onready var hp_bar: TextureProgressBar = get_node_or_null("Health") as TextureProgressBar

# Фильтр применяется отдельно к текстуре реплики и табличке имени.
# Без случайного шума и TIME: никакого мерцания на каждом кадре.
const FILTER_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 tone : source_color = vec4(1.0);
uniform float monochrome : hint_range(0.0, 1.0) = 0.0;
uniform float lines : hint_range(0.0, 0.35) = 0.0;

void fragment() {
    vec4 pixel = COLOR;
    float gray = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    pixel.rgb = mix(pixel.rgb, vec3(gray), monochrome);
    pixel.rgb *= tone.rgb;
    // Статичные экранные строки — только для электронных сообщений.
    float stripe = step(1.0, mod(floor(FRAGCOORD.y), 3.0));
    pixel.rgb *= 1.0 - lines * (1.0 - stripe);
    pixel.a *= tone.a;
    COLOR = pixel;
}
"""

var _paper_material: ShaderMaterial
var _title_material: ShaderMaterial
var _base_panel_position: Vector2
var _panel_tween: Tween
var _observed_text: String = ""
var _printing_time: float = 0.0
var _dialogue_open: bool = false
var _typing_finished: bool = true
var _source_for_next_line: String = ""
var last_hp: int = -1
var hp_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SKIN.game_panel($TargetPanel)
	SKIN.game_panel($MessagePanel)
	SKIN.label($VitalPanel/Vitals, 13, SKIN.LIGHT)
	if has_node("PhasePanel/Phase"):
		SKIN.label($PhasePanel/Phase, 11, SKIN.MUTED)
	SKIN.label($TargetTitle, 9, SKIN.MUTED)
	SKIN.label($Target, 11, SKIN.LIGHT)
	SKIN.label(radio_label, 12, SKIN.LIGHT)
	SKIN.label(radio_title, 11, SKIN.LIGHT)
	SKIN.label(radio_arrow, 9, SKIN.MUTED)
	SKIN.label(final_message, 18, SKIN.LIGHT)
	SKIN.label($PauseRoot/DossierPage/BadgeHeader, 10, SKIN.LIGHT)
	SKIN.label($PauseRoot/DossierPage/BadgeDetails, 11, SKIN.INK)
	SKIN.label($PauseRoot/PauseHint, 11, SKIN.INK)
	SKIN.label($PauseRoot/SettingsPage/SettingsTitle, 13, SKIN.LIGHT)
	SKIN.label($PauseRoot/SettingsPage/VolumeTitle, 11, SKIN.INK)
	for button in [$PauseRoot/Resume, $PauseRoot/Save, $PauseRoot/Load, $PauseRoot/Settings, $PauseRoot/ToMenu]:
		SKIN.paper_button(button)
	var fullscreen: CheckButton = $PauseRoot/SettingsPage/Fullscreen
	fullscreen.add_theme_color_override("font_color", SKIN.INK)
	fullscreen.add_theme_font_size_override("font_size", 11)
	$PauseRoot/SettingsPage/Volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	$PauseRoot/SettingsPage/Volume.value_changed.connect(_change_volume)
	fullscreen.toggled.connect(_toggle_fullscreen)
	$PauseRoot/Resume.pressed.connect(_resume_game)
	$PauseRoot/Save.pressed.connect(_save_game)
	$PauseRoot/Load.pressed.connect(_load_game)
	$PauseRoot/Settings.pressed.connect(_open_settings)
	$PauseRoot/ToMenu.pressed.connect(_main_menu)
	pause_root.visible = false
	final_message.visible = false

	var filter_shader := Shader.new()
	filter_shader.code = FILTER_SHADER_CODE
	_paper_material = ShaderMaterial.new()
	_paper_material.shader = filter_shader
	_title_material = ShaderMaterial.new()
	_title_material.shader = filter_shader
	radio_paper.material = _paper_material
	radio_title.material = _title_material
	_base_panel_position = radio_panel.position
	radio_panel.visible = false
	radio_panel.modulate.a = 0.0
	radio_arrow.visible = false
	radio_label.visible_characters = -1
	if not radio_label.text.is_empty():
		_start_dialogue(radio_label.text)

func _process(delta: float) -> void:
	var content: String = radio_label.text
	if content != _observed_text:
		if content.is_empty():
			_end_dialogue()
		else:
			_start_dialogue(content)

	radio_panel.visible = _dialogue_open and not pause_root.visible
	$MessagePanel.visible = final_message.visible

	if not get_tree().paused and not _typing_finished and not _observed_text.is_empty():
		_printing_time += delta
		# get_total_character_count() omits spaces/newlines; use codepoint count.
		var total: int = radio_label.text.length()
		radio_label.visible_characters = mini(total, int(_printing_time * characters_per_second))
		if radio_label.visible_characters >= total:
			radio_label.visible_characters = -1
			_typing_finished = true
			radio_arrow.visible = true

	var game: Variant = get_parent()
	if game != null and is_instance_valid(game.guard):
		var hp: int = clampi(game.guard.health, 0, 3)
		if hp != last_hp:
			animate_health(hp)

func animate_health(new_hp: int) -> void:
	if last_hp == -1:
		last_hp = new_hp
		hp_bar.value = new_hp
		return

	var damaged := new_hp < last_hp
	last_hp = new_hp

	if hp_tween and hp_tween.is_running():
		hp_tween.kill()

	hp_tween = create_tween()
	hp_tween.tween_property(
		hp_bar, "value", float(new_hp), 0.35
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if damaged:
		hp_bar.modulate = Color(1.0, 0.0, 0.0, 1.0)
		hp_tween.parallel().tween_property(
			hp_bar, "modulate", Color.WHITE, 0.4
		)
# Вызывай перед _say(), если строку невозможно распознать по префиксу.
# Допустимые значения: service, officer, hr, computer, archive, alert.
func set_next_dialogue_source(source: String) -> void:
	_source_for_next_line = source.to_lower()

func _start_dialogue(content: String) -> void:
	_observed_text = content
	_printing_time = 0.0
	_typing_finished = false
	radio_label.visible_characters = 0
	radio_arrow.visible = false

	var source: String = _detect_source(content)
	if not _source_for_next_line.is_empty():
		source = _source_for_next_line
		_source_for_next_line = ""
	_apply_dialogue_style(source)

	if _panel_tween != null and _panel_tween.is_running():
		_panel_tween.kill()
	_dialogue_open = true
	radio_panel.visible = not pause_root.visible
	radio_panel.position = _base_panel_position + Vector2(0.0, slide_distance)
	radio_panel.modulate.a = 0.0
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(radio_panel, "position", _base_panel_position, appear_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(radio_panel, "modulate:a", 1.0, appear_seconds)

func _end_dialogue() -> void:
	_observed_text = ""
	_typing_finished = true
	radio_arrow.visible = false
	radio_label.visible_characters = -1
	if not _dialogue_open:
		return
	if _panel_tween != null and _panel_tween.is_running():
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(radio_panel, "position", _base_panel_position + Vector2(0.0, slide_distance), disappear_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(radio_panel, "modulate:a", 0.0, disappear_seconds)
	_panel_tween.finished.connect(_finish_dialogue_hide)

func _finish_dialogue_hide() -> void:
	if _observed_text.is_empty():
		_dialogue_open = false
		radio_panel.visible = false

func _detect_source(content: String) -> String:
	var line: String = content.strip_edges().to_upper()
	if line.begins_with("HR:") or line.begins_with("ОТДЕЛ КАДРОВ"):
		return "hr"
	if line.begins_with("СУПЕРКОМПЬЮТЕР") or line.begins_with("СИСТЕМА КОД") or line.begins_with("RESET") or line.begins_with("99.99%"):
		return "computer"
	if line.begins_with("ЛИФТ") or line.begins_with("—") or line.begins_with("ДВЕРИ ЛИФТА"):
		return "officer"
	if line.begins_with("АРХИВ") or line.begins_with("СЛУЖЕБНЫЙ АРХИВ") or line.begins_with("ИНСТРУКЦИЯ"):
		return "archive"
	if line.begins_with("ТРЕВОГА") or line.begins_with("ПРОТОКОЛ") or line.begins_with("[ТЕЛЕПОРТАЦИЯ"):
		return "alert"
	return "service"

func _apply_dialogue_style(source: String) -> void:
	# Параметры: имя, цвет бумаги, цвет имени, цвет реплики, цвет подписи,
	# насыщенность бумаги, насыщенность имени, полосы бумаги, полосы имени.
	var title: String = "СЛУЖЕБНОЕ СООБЩЕНИЕ"
	var paper_tint := Color(0.92, 0.92, 0.91)
	var name_tint := Color(0.95, 0.87, 0.74)
	var text_color := Color(0.92, 0.90, 0.84)
	var name_color := Color(0.92, 0.88, 0.77)
	var paper_mono: float = 0.25
	var name_mono: float = 0.10
	var paper_lines: float = 0.0
	var name_lines: float = 0.0

	match source:
		"officer":
			title = "СТАРШИЙ СОТРУДНИК"
			paper_tint = Color(0.93, 0.87, 0.72)
			name_tint = Color(1.0, 0.76, 0.45)
			text_color = Color(1.0, 0.93, 0.79)
			name_color = Color(1.0, 0.93, 0.78)
			paper_mono = 0.35
			name_mono = 0.10
		"hr":
			title = "ОТДЕЛ КАДРОВ"
			paper_tint = Color(0.97, 0.78, 0.79)
			name_tint = Color(0.94, 0.49, 0.57)
			text_color = Color(1.0, 0.88, 0.87)
			name_color = Color(1.0, 0.93, 0.93)
			paper_mono = 0.16
			name_mono = 0.05
		"computer":
			title = "ВЫЧИСЛИТЕЛЬНЫЙ ЦЕНТР"
			paper_tint = Color(0.64, 0.92, 0.84)
			name_tint = Color(0.38, 0.78, 0.68)
			text_color = Color(0.77, 1.0, 0.91)
			name_color = Color(0.91, 1.0, 0.96)
			paper_mono = 0.65
			name_mono = 0.45
			paper_lines = scanline_intensity
			name_lines = scanline_intensity * 0.7
		"archive":
			title = "СЕКРЕТНЫЙ АРХИВ"
			paper_tint = Color(0.94, 0.85, 0.69)
			name_tint = Color(0.69, 0.55, 0.39)
			text_color = Color(0.99, 0.92, 0.76)
			name_color = Color(1.0, 0.95, 0.84)
			paper_mono = 0.60
			name_mono = 0.35
		"alert":
			title = "АВАРИЙНЫЙ ПРОТОКОЛ"
			paper_tint = Color(0.93, 0.49, 0.47)
			name_tint = Color(0.75, 0.23, 0.27)
			text_color = Color(1.0, 0.87, 0.83)
			name_color = Color(1.0, 0.95, 0.88)
			paper_mono = 0.18
			name_mono = 0.05
			paper_lines = scanline_intensity * 0.45
		_:
			title = "СЛУЖЕБНОЕ СООБЩЕНИЕ"

	radio_title.text = title
	radio_label.add_theme_color_override("font_color", text_color)
	radio_title.add_theme_color_override("font_color", name_color)
	radio_arrow.add_theme_color_override("font_color", text_color)
	_paper_material.set_shader_parameter("tone", Color.WHITE.lerp(paper_tint, dialogue_filter_strength))
	_paper_material.set_shader_parameter("monochrome", paper_mono * dialogue_filter_strength)
	_paper_material.set_shader_parameter("lines", paper_lines)
	_title_material.set_shader_parameter("tone", Color.WHITE.lerp(name_tint, name_filter_strength))
	_title_material.set_shader_parameter("monochrome", name_mono * name_filter_strength)
	_title_material.set_shader_parameter("lines", name_lines)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_set_paused(not get_tree().paused)
			get_viewport().set_input_as_handled()

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	pause_root.visible = value
	if value:
		_show_dossier()
		$PauseRoot/Resume.grab_focus()

func _resume_game() -> void:
	_set_paused(false)

func _show_dossier() -> void:
	dossier_page.visible = true
	settings_page.visible = false

func _open_settings() -> void:
	dossier_page.visible = false
	settings_page.visible = true
	$PauseRoot/SettingsPage/Volume.grab_focus()

func _change_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, value)))
	AudioServer.set_bus_mute(0, value <= 0.001)

func _toggle_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/start_menu.tscn")

func _save_game() -> void:
	var game: Variant = get_parent()
	var pos: Vector2 = game.guard.global_position
	var keys: Array = game.pickups.keys()
	var state: Dictionary = {
		"version": 1, "phase": game.phase, "phase_timer": game.phase_timer,
		"guard_position": [pos.x, pos.y], "health": game.guard.health,
		"ammo": game.guard.ammo, "weapon_enabled": game.guard.weapon_enabled,
		"pickups_left": keys, "scrap": game.scrap, "batteries": game.batteries,
		"coffee": game.coffee, "medicine": game.medicine,
		"built_barricades": game.built_barricades,
		"has_manual": game.has_manual, "reset_used": game.reset_used,
		"pc_uses": game.pc_uses, "fixed_issues": game.fixed_issues,
		"read_hr": game.read_hr, "night_number": game.night_number,
		"ventilation_fault": game.ventilation_fault,
		"malfunction_hint": game.malfunction_hint, "teleported": game.teleported,
		"is_hiding": game.is_hiding
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		$PauseRoot/PauseHint.text = "ОШИБКА СОХРАНЕНИЯ"
		return
	file.store_string(JSON.stringify(state))
	file.close()
	$PauseRoot/PauseHint.text = "ДЕЛО СОХРАНЕНО / СЛОТ 01"

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		$PauseRoot/PauseHint.text = "НЕТ СОХРАНЁННОГО ДЕЛА"
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		$PauseRoot/PauseHint.text = "НЕТ ДОСТУПА К ДЕЛУ"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		$PauseRoot/PauseHint.text = "ДЕЛО ПОВРЕЖДЕНО"
		return
	var data: Dictionary = parsed as Dictionary
	if int(data.get("version", 0)) != 1:
		$PauseRoot/PauseHint.text = "НЕИЗВЕСТНЫЙ ФОРМАТ"
		return
	var game: Variant = get_parent()
	game._clear_hunters()
	game.phase = str(data.get("phase", "INTRO"))
	game.phase_timer = float(data.get("phase_timer", 0.0))
	var position_data: Array = data.get("guard_position", [360.0, 1176.0])
	game.guard.travel_to(Vector2(float(position_data[0]), float(position_data[1])), Rect2(0, 0, 2304, 1440))
	game.guard.health = int(data.get("health", 3))
	game.guard.ammo = int(data.get("ammo", 0))
	game.guard.weapon_enabled = bool(data.get("weapon_enabled", false))
	game.guard.active = true
	game.scrap = int(data.get("scrap", 0))
	game.batteries = int(data.get("batteries", 0))
	game.coffee = int(data.get("coffee", 0))
	game.medicine = int(data.get("medicine", 0))
	game.has_manual = bool(data.get("has_manual", false))
	game.reset_used = bool(data.get("reset_used", false))
	game.pc_uses = int(data.get("pc_uses", 0))
	game.fixed_issues = int(data.get("fixed_issues", 0))
	game.read_hr = bool(data.get("read_hr", false))
	game.night_number = int(data.get("night_number", 0))
	game.ventilation_fault = bool(data.get("ventilation_fault", false))
	game.malfunction_hint = bool(data.get("malfunction_hint", false))
	game.teleported = bool(data.get("teleported", false))
	game.is_hiding = bool(data.get("is_hiding", false))
	game.guard.active = not game.is_hiding
	game.guard.get_node("Visual").visible = not game.is_hiding
	game.guard.get_node("Shadow").visible = not game.is_hiding
	var left: Array = data.get("pickups_left", [])
	for key in game.pickups.keys():
		if not left.has(key):
			game.pickups[key].queue_free()
			game.pickups.erase(key)
	for barrier in game.get_node("Barricades").get_children():
		barrier.queue_free()
	game.built_barricades = 0
	for i in range(maxi(0, int(data.get("built_barricades", 0)))):
		game.built_barricades += 1
		game._build_barrier()
	var elevator_open: bool = game.phase != "ELEVATOR"
	game.get_node("ElevatorDoor/Collision").set_deferred("disabled", elevator_open)
	game.get_node("ElevatorDoor/Visual").visible = not elevator_open
	if game.phase == "NIGHT1" or game.phase == "NIGHT2":
		game._spawn_hunter()
	game._say("СЛУЖЕБНЫЙ АРХИВ: данные смены восстановлены.", 3.0)
	_set_paused(false)
	game._refresh()

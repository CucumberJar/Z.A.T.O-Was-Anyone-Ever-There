extends CanvasLayer

const SKIN = preload("res://scripts/ui/ui_skin.gd")
const SAVE_PATH := "user://zato_slot1.json"

@onready var radio_label: Label = $RadioPanel/Radio
@onready var radio_panel: Control = $RadioPanel
@onready var final_message: Label = $Message
@onready var pause_root: Control = $PauseRoot
@onready var settings_page: Control = $PauseRoot/SettingsPage
@onready var dossier_page: Control = $PauseRoot/DossierPage
@onready var hp_bar: TextureProgressBar = $Health

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SKIN.game_panel($TargetPanel)
	SKIN.game_panel($MessagePanel)
	SKIN.label($VitalPanel/Vitals, 13, SKIN.LIGHT)
	SKIN.label($PhasePanel/Phase, 11, SKIN.MUTED)
	SKIN.label($TargetTitle, 9, SKIN.MUTED)
	SKIN.label($Target, 11, SKIN.LIGHT)
	SKIN.label(radio_label, 12, SKIN.LIGHT)
	SKIN.label($RadioPanel/RadioTitle, 11, SKIN.LIGHT)
	SKIN.label($RadioPanel/Arrow, 9, SKIN.MUTED)
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

func _process(_delta: float) -> void:
	var message_active: bool = not radio_label.text.is_empty()
	radio_panel.visible = message_active and not pause_root.visible
	$MessagePanel.visible = final_message.visible
	if message_active:
		_update_dialogue_speaker()
	var game: Variant = get_parent()
	if game != null and is_instance_valid(game.guard):
		var hp: int = clampi(game.guard.health, 0, 3)
		if has_node("Health"):
			$Health.value = hp

func _update_dialogue_speaker() -> void:
	var content: String = radio_label.text
	var title: String = "СЛУЖЕБНОЕ СООБЩЕНИЕ"
	if content.begins_with("ЛИФТ") or content.begins_with("—"):
		title = "СТАРШИЙ СОТРУДНИК"
	elif content.begins_with("HR:"):
		title = "ОТДЕЛ КАДРОВ"
	elif content.begins_with("СУПЕРКОМПЬЮТЕР"):
		title = "ВЫЧИСЛИТЕЛЬНЫЙ ЦЕНТР"
	$RadioPanel/RadioTitle.text = title

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

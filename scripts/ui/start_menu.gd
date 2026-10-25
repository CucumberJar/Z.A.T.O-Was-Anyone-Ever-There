extends Control

const SKIN = preload("res://scripts/ui/ui_skin.gd")
const GAME_SCENE := "res://scenes/main_indoor.tscn"

@onready var start_button: Button = $StartButton
@onready var settings_button: Button = $SettingsButton
@onready var exit_button: Button = $ExitButton
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var volume_slider: HSlider = $SettingsPanel/Settings/VolumeSlider
@onready var fullscreen_button: CheckButton = $SettingsPanel/Settings/Fullscreen
@onready var back_button: Button = $SettingsPanel/Settings/Back
@onready var note: Label = $StatusNote

func _ready() -> void:
	get_tree().paused = false
	# Softly sampled document, crisp nearest-neighbour world sprites.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for button in [start_button, settings_button, exit_button]:
		SKIN.dossier_button(button)
	SKIN.paper_panel(settings_panel)
	SKIN.label($SettingsPanel/Settings/Heading, 17, SKIN.INK)
	SKIN.label($SettingsPanel/Settings/VolumeText, 12, SKIN.INK)
	SKIN.label($SettingsPanel/Settings/Hint, 11, SKIN.INK)
	SKIN.label(note, 11, SKIN.LIGHT)
	SKIN.paper_button(back_button)
	fullscreen_button.add_theme_color_override("font_color", SKIN.INK)
	fullscreen_button.add_theme_font_size_override("font_size", 12)
	settings_panel.visible = false
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	fullscreen_button.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	start_button.pressed.connect(_start_game)
	settings_button.pressed.connect(_open_settings)
	exit_button.pressed.connect(_exit_game)
	back_button.pressed.connect(_close_settings)
	volume_slider.value_changed.connect(_set_volume)
	fullscreen_button.toggled.connect(_toggle_fullscreen)
	start_button.grab_focus()

func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _open_settings() -> void:
	settings_panel.visible = true
	back_button.grab_focus()

func _close_settings() -> void:
	settings_panel.visible = false
	start_button.grab_focus()

func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, value)))
	AudioServer.set_bus_mute(0, value <= 0.001)

func _toggle_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _exit_game() -> void:
	if OS.has_feature("web"):
		note.text = "Для завершения смены закройте вкладку."
	else:
		get_tree().quit()

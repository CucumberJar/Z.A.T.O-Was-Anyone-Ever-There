extends Node
## Z.A.T.O. sound director. Autoload: AudioDirector.
## Detects the current game phase and pause menu automatically.
## No changes to the game scene, pause HUD or dialogue are needed.

@export_group("Музыка")
@export_range(-40.0, 0.0, 1.0) var music_volume_db: float = -14.0
@export_range(0.1, 5.0, 0.1) var music_fade_seconds: float = 1.4
@export_group("Окружение")
@export_range(-45.0, 0.0, 1.0) var ambience_volume_db: float = -22.0
@export_range(0.1, 5.0, 0.1) var ambience_fade_seconds: float = 1.2
@export_group("Интерфейс")
@export_range(-35.0, 0.0, 1.0) var ui_volume_db: float = -17.0

# Music files supplied for this project. Edit these mappings to change the soundtrack.
const TRACKS := {
	"menu": "res://assets/audio/music/32_menu.ogg",
	"pause": "res://assets/audio/music/32_menu.ogg",
	"elevator": "res://assets/audio/music/27_concerto.mp3",
	"institute": "res://assets/audio/music/30_nii.ogg",
	"terminal": "res://assets/audio/music/29_light.ogg",
	"panic": "res://assets/audio/ambience/sirena.mp3",
	"hunt": "res://assets/audio/music/31_above_the_mountains.mp3",
	"monster": "res://assets/audio/music/29_light.ogg",
	"result": "res://assets/audio/music/29_light.ogg"
}

const AMBIENCES := {
	"building": "res://assets/audio/ambience/facility_hum.ogg",
	"alarm": "res://assets/audio/ambience/alarm_bed.ogg"
}

const UI_CLICK := "res://assets/audio/ui/ui_click.ogg"
const UI_HOVER := "res://assets/audio/ui/ui_hover.ogg"

var _music_players: Array[AudioStreamPlayer] = []
var _active_music: int = -1
var _music_key: String = ""
var _music_fade: float = 1.0
var _ambience_player: AudioStreamPlayer
var _ambience_key: String = ""
var _ambience_volume: float = 0.0
var _ambience_target: float = 0.0
var _pending_ambience: String = ""
var _ui_click: AudioStreamPlayer
var _ui_hover: AudioStreamPlayer
var _ui_scan_timer: float = 0.0
var _last_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = -80.0
		add_child(player)
		_music_players.append(player)

	_ambience_player = _new_player("Ambience")
	_ui_click = _new_player("UIClick")
	_ui_hover = _new_player("UIHover")
	_ui_click.stream = load(UI_CLICK) as AudioStream
	_ui_hover.stream = load(UI_HOVER) as AudioStream
	_ui_click.volume_db = ui_volume_db
	_ui_hover.volume_db = ui_volume_db - 7.0
	_last_paused = get_tree().paused


func _new_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _process(delta: float) -> void:
	var requested_music: String = _select_music()
	if requested_music != _music_key:
		_change_music(requested_music)
	_update_music_fade(delta)

	var requested_ambience: String = _select_ambience()
	if requested_ambience != _ambience_key and requested_ambience != _pending_ambience:
		_pending_ambience = requested_ambience
	_update_ambience(delta)

	# UI sounds still work while the SceneTree is paused.
	var paused_now: bool = get_tree().paused
	if paused_now != _last_paused:
		_last_paused = paused_now
		_play_ui(_ui_click)

	_ui_scan_timer -= delta
	if _ui_scan_timer <= 0.0:
		_ui_scan_timer = 0.65
		var scene: Node = get_tree().current_scene
		if scene != null:
			_connect_ui_buttons(scene)


func _select_music() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return ""
	if get_tree().paused:
		return "pause"
	if not scene.has_method("_start_night"):
		return "menu"
	if bool(scene.get("computer_open")):
		return "terminal"
	var phase: String = str(scene.get("phase"))
	match phase:
		"ELEVATOR": return "elevator"
		"INTRO", "DAY2", "DAY3": return "institute"
		"PANIC", "SORTIE": return "panic"
		"NIGHT1", "NIGHT3": return "hunt"
		"NIGHT2": return "monster"
		"RESULT": return "result"
		_: return "institute"


func _select_ambience() -> String:
	var scene: Node = get_tree().current_scene
	if scene == null or get_tree().paused or not scene.has_method("_start_night"):
		return ""
	if bool(scene.get("computer_open")):
		return "building"
	var phase: String = str(scene.get("phase"))
	if phase == "PANIC" or phase == "SORTIE":
		return "alarm"
	if phase == "ELEVATOR" or phase == "RESULT":
		return ""
	return "building"


func _load_looping(path: String) -> AudioStream:
	var audio: AudioStream = load(path) as AudioStream
	if audio == null:
		push_warning("AudioDirector: отсутствует файл " + path)
		return null
	if audio is AudioStreamOggVorbis:
		(audio as AudioStreamOggVorbis).loop = true
	elif audio is AudioStreamMP3:
		(audio as AudioStreamMP3).loop = true
	return audio


func _change_music(key: String) -> void:
	_music_key = key
	_music_fade = 0.0
	if key.is_empty() or not TRACKS.has(key):
		return

	var new_index: int = 1 if _active_music != 1 else 0
	var incoming: AudioStreamPlayer = _music_players[new_index]
	var target_path: String = TRACKS[key]
	# When menu and pause use the same track, retain the current playback position.
	if _active_music >= 0 and _music_players[_active_music].stream != null:
		var old_path: String = str(_music_players[_active_music].get_meta("asset_path", ""))
		if old_path == target_path:
			_music_fade = 1.0
			return

	incoming.stop()
	incoming.stream = _load_looping(target_path)
	if incoming.stream == null:
		return
	incoming.set_meta("asset_path", target_path)
	incoming.volume_db = -80.0
	incoming.play()
	_active_music = new_index


func _update_music_fade(delta: float) -> void:
	if _active_music < 0:
		return
	_music_fade = minf(1.0, _music_fade + delta / maxf(0.1, music_fade_seconds))
	var blend: float = _music_fade * _music_fade * (3.0 - 2.0 * _music_fade)
	for i in range(2):
		var player: AudioStreamPlayer = _music_players[i]
		if not player.playing:
			continue
		var gain: float = blend if i == _active_music else (1.0 - blend)
		player.volume_db = music_volume_db + linear_to_db(maxf(0.001, gain))
		if i != _active_music and _music_fade >= 1.0:
			player.stop()


func _update_ambience(delta: float) -> void:
	# Fade the old bed to silence before starting a different one.
	if _pending_ambience != _ambience_key:
		_ambience_target = 0.0
		_ambience_volume = move_toward(_ambience_volume, 0.0, delta / maxf(0.1, ambience_fade_seconds))
		if _ambience_volume <= 0.001:
			_ambience_player.stop()
			_ambience_key = _pending_ambience
			if not _ambience_key.is_empty() and AMBIENCES.has(_ambience_key):
				_ambience_player.stream = _load_looping(AMBIENCES[_ambience_key])
				if _ambience_player.stream != null:
					_ambience_player.play()
	else:
		_ambience_target = 1.0 if not _ambience_key.is_empty() else 0.0
		_ambience_volume = move_toward(_ambience_volume, _ambience_target, delta / maxf(0.1, ambience_fade_seconds))
	if _ambience_player.playing:
		_ambience_player.volume_db = ambience_volume_db + linear_to_db(maxf(0.001, _ambience_volume))


func _connect_ui_buttons(node: Node) -> void:
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		if not button.pressed.is_connected(_on_button_pressed):
			button.pressed.connect(_on_button_pressed)
		if not button.mouse_entered.is_connected(_on_button_hover):
			button.mouse_entered.connect(_on_button_hover)
	for child in node.get_children():
		_connect_ui_buttons(child)


func _on_button_pressed() -> void:
	_play_ui(_ui_click)


func _on_button_hover() -> void:
	if get_tree().paused or _select_music() == "menu":
		_play_ui(_ui_hover)


func _play_ui(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()

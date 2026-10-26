extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST FAILED: " + message)


func _run() -> void:
	for path in [
		"res://scenes/ui/start_menu.tscn",
		"res://scenes/main_indoor.tscn",
		"res://scenes/ui/ingame_hud.tscn",
		"res://scenes/minigames/supercomputer.tscn",
		"res://scenes/indoor_hunter.tscn"
	]:
		var resource: Resource = load(path)
		_expect(resource != null, "Ресурс не загружается: " + path)
		if resource is PackedScene:
			var probe: Node = (resource as PackedScene).instantiate()
			_expect(probe != null, "Сцену нельзя инстанцировать: " + path)
			if probe != null:
				probe.free()

	var menu_error: Error = change_scene_to_file("res://scenes/ui/start_menu.tscn")
	_expect(menu_error == OK, "Не удалось открыть стартовое меню")
	await process_frame
	await process_frame
	_expect(current_scene != null, "Стартовое меню не стало текущей сценой")
	var audio: Node = root.get_node_or_null("AudioDirector")
	var quests: Node = root.get_node_or_null("Quests")
	_expect(audio != null, "Autoload AudioDirector отсутствует")
	_expect(quests != null, "Autoload Quests отсутствует")

	var game_error: Error = change_scene_to_file("res://scenes/main_indoor.tscn")
	_expect(game_error == OK, "Не удалось открыть игровую сцену")
	await process_frame
	await process_frame
	var game: Node = current_scene
	if game == null:
		_expect(false, "Игровая сцена не стала текущей сценой")
		_finish()
		return

	for node_path in ["Guard", "HUD", "Indoor", "Computer", "Electro"]:
		_expect(game.get_node_or_null(node_path) != null, "Нет обязательного узла: " + node_path)

	if audio != null:
		_expect(audio.call("_select_music") == "elevator", "Неверная тема на старте игры")
		game.set("phase", "NIGHT1")
		_expect(audio.call("_select_music") == "hunt", "Нет музыкальной темы NIGHT1")
		game.set("phase", "NIGHT2")
		_expect(audio.call("_select_music") == "monster", "Нет музыкальной темы NIGHT2")
		game.set("phase", "PANIC")
		_expect(audio.call("_select_music") == "panic", "Нет музыкальной темы PANIC")
		game.set("computer_open", true)
		_expect(audio.call("_select_music") == "terminal", "Открытый терминал не меняет музыку")
		game.set("computer_open", false)
		game.set("phase", "RESULT")
		_expect(audio.call("_select_music") == "result", "Нет музыкальной темы концовки")

	game.call("_start_first_night")
	_expect(str(game.get("phase")) == "NIGHT1", "Первая ночь не запускается")
	_expect(is_equal_approx(float(game.get("phase_timer")), 60.0), "Первая ночь должна длиться 60 секунд")

	# Regression test: the level uses action="electro", not the old "energo" typo.
	if quests != null:
		quests.call("reset")
		quests.call("start", "sortie")
	game.set("phase", "SORTIE")
	game.set("phase_timer", 25.0)
	game.set("computer_open", false)
	var player: Node2D = game.get_node("Guard")
	var electro: Area2D = game.get_node("Electro")
	var collision: CollisionShape2D = electro.get_node("CollisionShape2D")
	player.global_position = collision.global_position
	electro.call("_process", 0.0)
	game.call("_interact")
	_expect(str(game.get("phase")) == "DAY2", "Щиток electro не завершает вылазку и не запускает DAY2")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Z.A.T.O. SMOKE TESTS PASSED")
		quit(0)
	else:
		push_error("Z.A.T.O. SMOKE TESTS FAILED: %d failure(s)" % failures.size())
		quit(1)

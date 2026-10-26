extends Node
# Задания игры. Фазы запускает main_indoor.gd по сигналу completed:
# выполнено задание -> начинается следующая фаза. Здесь про фазы ничего нет.
signal changed
signal completed(id: String)

# Все задания. Добавить новое = добавить строку.
# "needs": ["id"]  — нельзя выполнить, пока не выполнено другое задание.
# "timed": true    — задание закрывается по таймеру фазы (см. complete_timed).
var quests := {
	"elevator": {"title": "Выйти из лифта",              "done": false},
	"manual":   {"title": "Проверить архив",             "done": false},
	"computer": {"title": "Настроить суперкомпьютер",     "done": false, "needs": ["manual"]},
	"reset": {"title": "Перезапустить компьютер",     "done": false, "needs": ["computer"]},
	"gather":   {"title": "Собрать припасы",              "done": false, "timed": true},
	"night":   {"title": "Пережить ночь",                "done": false, "timed": true},
	"sortie":   {"title": "Добраться до щитка",           "done": false, "timed": true},
	"fort":   {"title": "Укрепиться",           "done": false, "timed": true},
	"hunt":     {"title": "Поймать монстра", "done": false, "timed": true},
	"power":    {"title": "Помочь ученым или построить баррикады","done": false},
	"final":     {"title": "Победить монстра",              "done": false},
}
var active: Array = []

func start(id: String) -> void:
	if not quests.has(id) or id in active or quests[id]["done"]:
		return
	active.append(id)
	changed.emit()

func is_done(id: String) -> bool:
	return quests.has(id) and quests[id]["done"]

func complete(id: String) -> bool:
	if not quests.has(id) or not (id in active) or quests[id]["done"]:
		return false
	for need in quests[id].get("needs", []):
		if not is_done(need):
			return false
	quests[id]["done"] = true
	changed.emit()
	completed.emit(id)
	return true

# Вызывается, когда истёк таймер: закрывает активное задание с "timed": true.
func complete_timed() -> void:
	for id in active.duplicate():
		if quests[id].get("timed", false) and not quests[id]["done"]:
			complete(id)
			return

func done_count(ids: Array) -> int:
	var count := 0
	for id in ids:
		if is_done(id):
			count += 1
	return count

func reset() -> void:
	active.clear()
	for id in quests:
		quests[id]["done"] = false
	changed.emit()

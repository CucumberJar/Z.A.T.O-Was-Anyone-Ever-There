extends Node
signal changed

# Все задания игры. Добавить новое = добавить строку.
var quests := {
	"elevanor":   {"title": "Выйти из лифта",         "done": false},
	"manual":   {"title": "Найти инструкцию",         "done": false},
	"computer": {"title": "Настроить суперкомпьютер", "done": false, "needs": ["manual"]},
	"power":    {"title": "Вернуть питание",          "done": false},
	"fort":     {"title": "Укрепить кабинет",         "done": false},
	"terminal": {"title": "Сохранить данные",         "done": false},
}
var active: Array = []

func start(id: String) -> void:
	if id in active or quests[id]["done"]:
		return
	active.append(id)
	changed.emit()

func complete(id: String) -> bool:
	if not (id in active) or quests[id]["done"]:
		return false
	for need in quests[id].get("needs", []):
		if not quests[need]["done"]:
			return false
	quests[id]["done"] = true
	changed.emit()
	return true

func done_count(ids: Array) -> int:
	var count := 0
	for id in ids:
		if quests[id]["done"]:
			count += 1
	return count

func reset() -> void:
	active.clear()
	for id in quests:
		quests[id]["done"] = false
	changed.emit()

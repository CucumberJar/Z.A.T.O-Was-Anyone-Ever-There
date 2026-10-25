extends VBoxContainer
# Мини-интерфейс сети для стартового меню. Всё строится кодом, сцену менять не нужно.

var ip_edit: LineEdit
var status: Label
var net: Node

func _ready() -> void:
	net = get_node_or_null("/root/Net")
	position = Vector2(6, 190)
	custom_minimum_size = Vector2(130, 0)

	var title := Label.new()
	title.text = "СЕТЬ"
	add_child(title)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP хоста"
	ip_edit.text = "127.0.0.1"
	add_child(ip_edit)

	var host_btn := Button.new()
	host_btn.text = "Создать игру"
	host_btn.pressed.connect(func(): net.host())
	add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Подключиться"
	join_btn.pressed.connect(func(): net.join(ip_edit.text))
	add_child(join_btn)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(130, 0)
	status.add_theme_font_size_override("font_size", 10)
	add_child(status)

	if net == null:
		status.text = "Автозагрузка Net не найдена. Project Settings -> Globals -> Autoload"
		host_btn.disabled = true
		join_btn.disabled = true
		return
	net.status_changed.connect(func(t: String): status.text = t)

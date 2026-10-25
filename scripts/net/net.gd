extends Node
# Автозагрузка (autoload) с именем "Net". Отвечает за соединение и пересылку позиций.

signal status_changed(text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const SEND_INTERVAL := 0.05  # 20 раз в секунду

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): status_changed.emit("Подключено к хосту"))
	multiplayer.connection_failed.connect(func(): status_changed.emit("Не удалось подключиться"))
	multiplayer.server_disconnected.connect(func(): status_changed.emit("Хост отключился"))

func host(port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		status_changed.emit("Ошибка создания сервера: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Вы хост. Ждём игроков...")

func join(ip: String, port: int = DEFAULT_PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		status_changed.emit("Ошибка подключения: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Подключаемся...")

func _on_peer_connected(id: int) -> void:
	status_changed.emit("Игроков онлайн: %d" % (multiplayer.get_peers().size() + 1))

func _on_peer_disconnected(id: int) -> void:
	get_tree().call_group("net_ghosts", "remove_ghost", id)
	status_changed.emit("Игроков онлайн: %d" % (multiplayer.get_peers().size() + 1))

# Вызывается из ghost_sync.gd: отправляет свою позицию всем остальным.
func send_state(pos: Vector2, region: Rect2, is_visible: bool) -> void:
	if multiplayer.get_peers().is_empty():
		return
	_state.rpc(pos, region, is_visible)

@rpc("any_peer", "unreliable_ordered")
func _state(pos: Vector2, region: Rect2, is_visible: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	get_tree().call_group("net_ghosts", "apply_state", id, pos, region, is_visible)

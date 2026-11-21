class_name BattleServer
extends Node
## ENet 服务器基础层：接受连接、收发消息。对局权威逻辑由上层 BattleServerSession 接入。
## 当前只提供传输边界，不保存服务器存档/不做断线重连/观战/回放。

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal message_received(peer_id: int, message: Dictionary)
signal started(port: int)
signal stopped()

const DEFAULT_PORT: int = BattleProtocol.DEFAULT_GAME_PORT

var _peer: ENetMultiplayerPeer = null
var _running: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func host(port: int = DEFAULT_PORT, max_clients: int = 8) -> Error:
	stop_server()
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_server(port, max_clients)
	if error != OK:
		_peer = null
		return error
	multiplayer.multiplayer_peer = _peer
	_running = true
	started.emit(port)
	return OK


func stop_server() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _running:
		_running = false
		stopped.emit()


func is_running() -> bool:
	return _running


func send_to_peer(peer_id: int, message: Dictionary) -> void:
	if not _running:
		return
	rpc_id(peer_id, "server_message", message)


func send_to_all(message: Dictionary) -> void:
	if not _running:
		return
	for peer_id: int in multiplayer.get_peers():
		rpc_id(peer_id, "server_message", message)


@rpc("any_peer", "call_remote", "reliable")
func client_message(message: Dictionary) -> void:
	if not message is Dictionary:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	message_received.emit(peer_id, message)


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)

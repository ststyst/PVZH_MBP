class_name BattleClient
extends Node
## ENet 客户端基础层：连接服务器、发送 HELLO/命令、接收服务器消息。
## 对局快照/事件的组织由上层 BattleSession 完成。

signal connected()
signal disconnected()
signal message_received(message: Dictionary)
signal connection_failed()

const DEFAULT_PORT: int = BattleProtocol.DEFAULT_GAME_PORT

var _peer: ENetMultiplayerPeer = null
var _connected: bool = false


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func join_server(address: String, port: int = DEFAULT_PORT) -> Error:
	leave_server()
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(address, port)
	if error != OK:
		_peer = null
		connection_failed.emit()
		return error
	multiplayer.multiplayer_peer = _peer
	return OK


func leave_server() -> void:
	_connected = false
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_connected_to_server() -> bool:
	return _connected


func send_message(message: Dictionary) -> void:
	if not _connected:
		return
	rpc_id(1, "client_message", message)


func send_command(command_payload: Dictionary) -> void:
	send_message(command_payload)


func send_hello(
	account: String,
	card_hash: String,
	mode_hash: String,
	mods_allowed: bool = false,
) -> void:
	send_message(BattleProtocol.hello(account, card_hash, mode_hash, mods_allowed))


@rpc("authority", "call_remote", "reliable")
func server_message(message: Dictionary) -> void:
	message_received.emit(message)


func _on_connected_to_server() -> void:
	_connected = true
	connected.emit()


func _on_connection_failed() -> void:
	_connected = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_connected = false
	disconnected.emit()

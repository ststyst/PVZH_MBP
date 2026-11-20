extends Node
## 网络总线：局域网服务器发现 + 服务器登录请求。
##
## 本里程碑（M0）只实现局域网发现与登录入口信号；
## ENet 对局连接、握手协议、服务器权威逻辑在 M5 实现。

enum LOGIN_RESULT {
	OK,
	UNREACHABLE,
	BAD_CREDENTIALS,
	PROTOCOL_MISMATCH,
	NOT_IMPLEMENTED,
	FEATURE_DISABLED,
}

signal lan_search_started()
signal lan_server_found(server: Dictionary)
signal lan_search_finished(servers: Array)
signal login_finished(result: int, message: String)

const DEFAULT_SERVER_PORT: int = 45770
const DISCOVERY_PORT: int = 45771
const DISCOVERY_MAGIC: String = "CARDARENA_DISCOVERY_V1"
const PROTOCOL_VERSION: int = 1
const CLIENT_VERSION: String = "0.1.0"
const SEARCH_TIMEOUT_SECONDS: float = 3.0

var is_searching: bool = false

var _udp: PacketPeerUDP = null
var _found_servers: Dictionary = {}
var _search_elapsed_seconds: float = 0.0
var _search_timeout_seconds: float = SEARCH_TIMEOUT_SECONDS


func _process(delta: float) -> void:
	if not is_searching or _udp == null:
		return
	_search_elapsed_seconds += delta
	while _udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp.get_packet()
		var from_ip: String = _udp.get_packet_ip()
		_handle_discovery_packet(packet, from_ip)
	if _search_elapsed_seconds >= _search_timeout_seconds:
		_finish_search()


## 发出局域网搜索（UDP 广播）。超时后通过 lan_search_finished 返回结果。
func start_lan_search(timeout_seconds: float = SEARCH_TIMEOUT_SECONDS) -> void:
	stop_lan_search()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var bind_error: Error = _udp.bind(0)
	if bind_error != OK:
		push_warning("局域网搜索初始化失败（错误码 %d）" % bind_error)
		_udp = null
		lan_search_finished.emit([])
		return
	_found_servers.clear()
	_search_timeout_seconds = maxf(timeout_seconds, 0.5)
	_search_elapsed_seconds = 0.0
	is_searching = true
	lan_search_started.emit()
	_send_discovery_request()


func stop_lan_search() -> void:
	is_searching = false
	_search_elapsed_seconds = 0.0
	if _udp != null:
		_udp.close()
		_udp = null


## 服务器登录入口。M5 之前返回明确的「未实现」结果，不做假成功。
func login_to_server(address: String, port: int, account: String, password: String) -> void:
	if address.is_empty() or port <= 0 or port > 65535:
		login_finished.emit(LOGIN_RESULT.UNREACHABLE, "服务器地址或端口不合法。")
		return
	if account.is_empty():
		login_finished.emit(LOGIN_RESULT.BAD_CREDENTIALS, "请填写账号。")
		return
	# M5：ENet 连接 + 协议握手 + 服务器校验账号密码。
	login_finished.emit(
		LOGIN_RESULT.NOT_IMPLEMENTED,
		"服务器登录将在联机里程碑实现；当前请使用本地存档进入单机。",
	)


func _send_discovery_request() -> void:
	if _udp == null:
		return
	var request: Dictionary = {
		"magic": DISCOVERY_MAGIC,
		"client_version": CLIENT_VERSION,
		"protocol": PROTOCOL_VERSION,
	}
	if _udp.set_dest_address("255.255.255.255", DISCOVERY_PORT) == OK:
		_udp.put_packet(JSON.stringify(request).to_utf8_buffer())


func _handle_discovery_packet(packet: PackedByteArray, from_ip: String) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if str(data.get("magic", "")) != DISCOVERY_MAGIC:
		return
	var server_port: int = int(data.get("game_port", DEFAULT_SERVER_PORT))
	var key: String = "%s:%d" % [from_ip, server_port]
	if _found_servers.has(key):
		return
	var server: Dictionary = {
		"key": key,
		"address": from_ip,
		"port": server_port,
		"name": str(data.get("name", "未命名服务器")),
		"players": int(data.get("players", 0)),
		"max_players": int(data.get("max_players", 0)),
		"version": str(data.get("version", "")),
		"motd": str(data.get("motd", "")),
	}
	_found_servers[key] = server
	lan_server_found.emit(server)


func _finish_search() -> void:
	var servers: Array = []
	for key: Variant in _found_servers.keys():
		servers.append(_found_servers[key])
	stop_lan_search()
	lan_search_finished.emit(servers)

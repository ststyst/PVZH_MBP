extends Control
## 登录界面：本地多存档 / 服务器登录 / 局域网服务器搜索。

const STATUS_HINT_DEFAULT: String = "单机存档保存在本机；局域网与服务器功能见「服务器」标签页。"
const STATUS_COLOR_DEFAULT: Color = Color(0.749, 0.780, 0.859)
const STATUS_COLOR_ERROR: Color = Color(0.941, 0.549, 0.549)

@onready var main_tabs: TabContainer = %MainTabs
@onready var slot_list: ItemList = %SlotList
@onready var slot_name_edit: LineEdit = %SlotNameEdit
@onready var create_button: Button = %CreateButton
@onready var delete_button: Button = %DeleteButton
@onready var enter_local_button: Button = %EnterLocalButton
@onready var server_address_edit: LineEdit = %ServerAddress
@onready var server_port_edit: LineEdit = %ServerPort
@onready var server_account_edit: LineEdit = %ServerAccount
@onready var server_password_edit: LineEdit = %ServerPassword
@onready var remember_password_check: CheckBox = %RememberPassword
@onready var login_button: Button = %LoginButton
@onready var lan_scan_button: Button = %LanScanButton
@onready var lan_list: ItemList = %LanList
@onready var status_label: Label = %StatusLabel
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog

var _slots: Array[SaveSlotInfo] = []
var _pending_delete_slot_key: String = ""


func _ready() -> void:
	main_tabs.set_tab_title(0, "本地游戏")
	main_tabs.set_tab_title(1, "服务器")
	server_port_edit.text = str(NetManager.DEFAULT_SERVER_PORT)
	_connect_signals()
	_load_recent_server_defaults()
	_refresh_slots()
	lan_list.clear()
	_set_status(STATUS_HINT_DEFAULT)


func _connect_signals() -> void:
	enter_local_button.pressed.connect(_on_enter_local_pressed)
	create_button.pressed.connect(_on_create_slot_pressed)
	delete_button.pressed.connect(_on_delete_slot_pressed)
	slot_list.item_activated.connect(_on_slot_activated)
	login_button.pressed.connect(_on_login_pressed)
	lan_scan_button.pressed.connect(_on_lan_scan_pressed)
	lan_list.item_activated.connect(_on_lan_server_activated)
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	NetManager.lan_search_started.connect(_on_lan_search_started)
	NetManager.lan_server_found.connect(_on_lan_server_found)
	NetManager.lan_search_finished.connect(_on_lan_search_finished)
	NetManager.login_finished.connect(_on_login_finished)


# ----- 本地存档 -----

func _refresh_slots() -> void:
	slot_list.clear()
	_slots = SaveManager.list_slots()
	for slot: SaveSlotInfo in _slots:
		var index: int = slot_list.add_item(_format_slot_text(slot))
		slot_list.set_item_metadata(index, slot.slot_key)
	var has_slots: bool = not _slots.is_empty()
	enter_local_button.disabled = not has_slots
	delete_button.disabled = not has_slots
	if has_slots:
		slot_list.select(0)


func _format_slot_text(slot: SaveSlotInfo) -> String:
	var played_at: String = "从未游玩"
	if slot.last_played_unix > 0:
		# Time.get_datetime_string_from_unix_time 按 UTC 输出，这里加上系统时区偏移显示本地时间。
		var bias_seconds: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		played_at = Time.get_datetime_string_from_unix_time(slot.last_played_unix + bias_seconds, true)
	return "%s　·　牌组 %d　·　金币 %d　·　%s" % [slot.player_name, slot.deck_count, slot.gold, played_at]


func _selected_slot_key() -> String:
	var selected_indices: PackedInt32Array = slot_list.get_selected_items()
	if selected_indices.is_empty():
		if _slots.is_empty():
			return ""
		slot_list.select(0)
		return _slots[0].slot_key
	var selected_index: int = selected_indices[0]
	if selected_index < 0 or selected_index >= _slots.size():
		return ""
	return str(slot_list.get_item_metadata(selected_index))


func _on_create_slot_pressed() -> void:
	var display_name: String = slot_name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = "本地玩家 %d" % (_slots.size() + 1)
	var slot_key: String = SaveManager.create_slot(display_name)
	if slot_key.is_empty():
		_set_status("创建存档失败，请检查磁盘权限。", true)
		return
	slot_name_edit.text = ""
	_refresh_slots()
	_set_status("已创建存档：%s" % display_name)


func _on_delete_slot_pressed() -> void:
	var slot_key: String = _selected_slot_key()
	if slot_key.is_empty():
		return
	_pending_delete_slot_key = slot_key
	confirm_dialog.dialog_text = "删除后无法恢复，确定要删除这个本地存档吗？"
	confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_slot_key.is_empty():
		return
	if SaveManager.delete_slot(_pending_delete_slot_key):
		_set_status("存档已删除。")
	_pending_delete_slot_key = ""
	_refresh_slots()


func _on_enter_local_pressed() -> void:
	var slot_key: String = _selected_slot_key()
	if slot_key.is_empty():
		_set_status("请先新建一个本地存档。", true)
		return
	enter_local_button.disabled = true
	if not GameState.enter_local_game(slot_key):
		enter_local_button.disabled = false
		_set_status("读取存档失败，存档可能已损坏。", true)


func _on_slot_activated(_index: int) -> void:
	_on_enter_local_pressed()


# ----- 服务器登录 -----

func _load_recent_server_defaults() -> void:
	var recent_servers: Array[Dictionary] = SaveManager.load_recent_servers()
	if recent_servers.is_empty():
		return
	var last_server: Dictionary = recent_servers[0]
	server_address_edit.text = str(last_server.get("address", ""))
	# JSON 里的数字会被解析为 float，这里转成整数再显示，避免出现 "45770.0"
	server_port_edit.text = str(int(last_server.get("port", NetManager.DEFAULT_SERVER_PORT)))
	server_account_edit.text = str(last_server.get("account", ""))
	var saved_password: String = str(last_server.get("password", ""))
	server_password_edit.text = saved_password
	remember_password_check.button_pressed = not saved_password.is_empty()


func _on_login_pressed() -> void:
	var address: String = server_address_edit.text.strip_edges()
	var port_text: String = server_port_edit.text.strip_edges()
	var account: String = server_account_edit.text.strip_edges()
	var password: String = server_password_edit.text
	if address.is_empty():
		_set_status("请填写服务器地址。", true)
		return
	if not port_text.is_valid_int():
		_set_status("端口必须是数字。", true)
		return
	var port: int = int(port_text)
	if port <= 0 or port > 65535:
		_set_status("端口范围应为 1–65535。", true)
		return
	if account.is_empty():
		_set_status("请填写账号。", true)
		return
	login_button.disabled = true
	_set_status("正在连接 %s:%d …" % [address, port])
	NetManager.login_to_server(address, port, account, password)


func _on_login_finished(result: int, message: String) -> void:
	login_button.disabled = false
	if result == NetManager.LOGIN_RESULT.OK:
		var password_to_store: String = ""
		if remember_password_check.button_pressed:
			password_to_store = server_password_edit.text
		SaveManager.remember_server(
			server_address_edit.text.strip_edges(),
			int(server_port_edit.text),
			server_account_edit.text.strip_edges(),
			password_to_store,
		)
		_set_status(message)
		return
	_set_status(message, result != NetManager.LOGIN_RESULT.NOT_IMPLEMENTED)


# ----- 局域网搜索 -----

func _on_lan_scan_pressed() -> void:
	lan_list.clear()
	lan_scan_button.disabled = true
	_set_status("正在搜索局域网服务器…")
	NetManager.start_lan_search(NetManager.SEARCH_TIMEOUT_SECONDS)


func _on_lan_search_started() -> void:
	lan_scan_button.disabled = true


func _on_lan_server_found(server: Dictionary) -> void:
	var index: int = lan_list.add_item(_format_lan_server_text(server))
	lan_list.set_item_metadata(index, server)


func _format_lan_server_text(server: Dictionary) -> String:
	var players_text: String = "%d/%d" % [int(server.get("players", 0)), int(server.get("max_players", 0))]
	return "%s　·　%s:%d　·　玩家 %s　·　版本 %s" % [
		str(server.get("name", "未命名服务器")),
		str(server.get("address", "")),
		int(server.get("port", 0)),
		players_text,
		str(server.get("version", "")),
	]


func _on_lan_search_finished(servers: Array) -> void:
	lan_scan_button.disabled = false
	if servers.is_empty():
		_set_status("未发现局域网服务器（需要局域网内有专用服务端在运行）。", true)
	else:
		_set_status("发现 %d 个局域网服务器，双击可填入地址。" % servers.size())


func _on_lan_server_activated(index: int) -> void:
	var server_data: Variant = lan_list.get_item_metadata(index)
	if not server_data is Dictionary:
		return
	var server: Dictionary = server_data
	server_address_edit.text = str(server.get("address", ""))
	server_port_edit.text = str(server.get("port", NetManager.DEFAULT_SERVER_PORT))
	main_tabs.current_tab = 1
	_set_status("已填入服务器地址，请输入账号后登录。")


# ----- 状态栏 -----

func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", STATUS_COLOR_ERROR if is_error else STATUS_COLOR_DEFAULT)

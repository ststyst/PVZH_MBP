extends Node
## 登录流程 API：模式选择 → 本地（开始游戏 / 选择存档 / 新建存档）或服务器登录。
## 只负责数据与状态，不负责界面表现；界面按钮调用这里的方法，并监听信号驱动显示。

enum MODE { NONE, LOCAL, SERVER }
enum PANEL { MODE_SELECT, LOCAL_MENU, SAVE_SELECT, SAVE_CREATE, SERVER_LOGIN }
enum START_RESULT { STARTED, NEED_CREATE_SAVE, SAVE_NOT_FOUND, LOAD_FAILED }

signal mode_changed(mode: int)
signal panel_changed(panel: int)
signal start_result(result: int, slot_key: String)
signal save_list_changed()
signal save_create_cancelled()
signal server_login_finished(result: int, message: String)

const DEVELOPER_MESSAGE: String = "感谢试玩《卡牌对决》alpha0.1！\n\n当前版本仍在早期开发中：卡牌内容、战斗与联机功能会逐步加入。\n如果你在游戏中遇到问题，欢迎记录下存档名称与操作步骤反馈。\n\n—— 开发者"

var mode: MODE = MODE.NONE
var panel: PANEL = PANEL.MODE_SELECT

var _panel_before_save_create: int = PANEL.LOCAL_MENU


func _ready() -> void:
	NetManager.login_finished.connect(_on_net_login_finished)


# ----- 界面阶段 -----

## 登录界面初始化时调用：回到模式选择、预加载主界面。
func open_login_screen() -> void:
	mode = MODE.NONE
	_open_panel(PANEL.MODE_SELECT)
	mode_changed.emit(mode)
	GameState.preload_main_scene()


func select_mode(new_mode: MODE) -> void:
	mode = new_mode
	mode_changed.emit(mode)
	match new_mode:
		MODE.LOCAL:
			_open_panel(PANEL.LOCAL_MENU)
		MODE.SERVER:
			_open_panel(PANEL.SERVER_LOGIN)
		_:
			_open_panel(PANEL.MODE_SELECT)


## 返回「选择游玩模式」界面（服务器登录页的返回按钮也调它）。
func back_to_mode_select() -> void:
	mode = MODE.NONE
	_open_panel(PANEL.MODE_SELECT)
	mode_changed.emit(mode)


func open_local_menu() -> void:
	mode = MODE.LOCAL
	_open_panel(PANEL.LOCAL_MENU)


func open_save_select() -> void:
	_panel_before_save_create = PANEL.SAVE_SELECT
	_open_panel(PANEL.SAVE_SELECT)


## 打开新建存档页面；记住来源界面，取消时返回。
func open_save_create() -> void:
	_panel_before_save_create = panel
	_open_panel(PANEL.SAVE_CREATE)


## 新建存档页的「返回」：放弃本次创建，关闭新建页面。
func cancel_save_create() -> void:
	save_create_cancelled.emit()
	_open_panel(_panel_before_save_create)


func open_server_login() -> void:
	mode = MODE.SERVER
	_open_panel(PANEL.SERVER_LOGIN)
	mode_changed.emit(mode)


# ----- 本地：开始游戏 / 选档 / 新建 -----

## 「开始游戏」：使用上一次游玩的存档；没有存档时切到新建存档页面。
func request_start_game() -> int:
	var slot_key: String = AppStorage.get_last_slot_key()
	if slot_key.is_empty() or not SaveManager.slot_exists(slot_key):
		_open_panel(PANEL.SAVE_CREATE)
		start_result.emit(START_RESULT.NEED_CREATE_SAVE, "")
		return START_RESULT.NEED_CREATE_SAVE
	var started: bool = GameState.enter_local_game(slot_key)
	var result: int = START_RESULT.STARTED if started else START_RESULT.LOAD_FAILED
	start_result.emit(result, slot_key)
	return result


## 新建存档并立刻用这个存档开始游戏。返回 { ok, message, slot_key }。
func create_save_and_start(display_name: String) -> Dictionary:
	var trimmed: String = display_name.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "message": "存档名称不能为空。", "slot_key": ""}
	var slot_key: String = SaveManager.create_slot(trimmed)
	if slot_key.is_empty():
		return {"ok": false, "message": "创建存档失败，请检查磁盘权限。", "slot_key": ""}
	save_list_changed.emit()
	var started: bool = GameState.enter_local_game(slot_key)
	if not started:
		return {"ok": false, "message": "存档已创建，但载入失败。", "slot_key": slot_key}
	return {"ok": true, "message": "已创建存档：%s" % trimmed, "slot_key": slot_key}


## 用指定存档开始游戏（选择存档界面的「进入」按钮）。
func start_with_save(slot_key: String) -> Dictionary:
	if not SaveManager.slot_exists(slot_key):
		return {"ok": false, "message": "存档不存在或已损坏。", "slot_key": slot_key}
	var started: bool = GameState.enter_local_game(slot_key)
	if not started:
		return {"ok": false, "message": "读取存档失败。", "slot_key": slot_key}
	return {"ok": true, "message": "已进入游戏。", "slot_key": slot_key}


## 删除指定存档（确认框由界面用 ConfirmService.ask_yes_no() 询问后调用）。
func delete_save(slot_key: String) -> Dictionary:
	if not SaveManager.slot_exists(slot_key):
		return {"ok": false, "message": "存档不存在。"}
	if not SaveManager.delete_slot(slot_key):
		return {"ok": false, "message": "删除存档失败。"}
	if AppStorage.get_last_slot_key() == slot_key:
		AppStorage.set_last_slot_key("")
	save_list_changed.emit()
	return {"ok": true, "message": "存档已删除。"}


## 存档列表（按最近游玩倒序），供选择存档界面渲染。
func get_save_slots() -> Array[SaveSlotInfo]:
	return SaveManager.list_slots()


func has_any_save() -> bool:
	return SaveManager.has_any_slot()


# ----- 服务器登录 -----

## 服务器登录页初始化时读取上次保存的 IP 与账号（自动填写）。
func get_server_form_defaults() -> Dictionary:
	return AppStorage.get_server_login()


## 提交服务器登录。登录逻辑尚未实现，会通过 server_login_finished 返回明确结果。
## 勾选「保存登录信息」时只保存 IP 与账号，不保存密码。
func submit_server_login(
	ip: String,
	account: String,
	password: String,
	remember: bool,
	port: int = -1,
) -> void:
	var trimmed_ip: String = ip.strip_edges()
	var trimmed_account: String = account.strip_edges()
	if trimmed_ip.is_empty():
		server_login_finished.emit(NetManager.LOGIN_RESULT.UNREACHABLE, "请填写服务器 IP 地址。")
		return
	if trimmed_account.is_empty():
		server_login_finished.emit(NetManager.LOGIN_RESULT.BAD_CREDENTIALS, "请填写账号。")
		return
	AppStorage.set_server_login(trimmed_ip, trimmed_account, remember)
	var target_port: int = NetManager.DEFAULT_SERVER_PORT if port <= 0 else port
	NetManager.login_to_server(trimmed_ip, target_port, trimmed_account, password)


# ----- 其他 -----

## 退出游戏（会先保存当前存档）。
func quit_game() -> void:
	GameState.save_active_profile()
	AppStorage.save_data()
	get_tree().quit()


func get_developer_message() -> String:
	return DEVELOPER_MESSAGE


func get_panel() -> int:
	return panel


func get_mode() -> int:
	return mode


func _on_net_login_finished(result: int, message: String) -> void:
	server_login_finished.emit(result, message)


func _open_panel(new_panel: int) -> void:
	panel = new_panel
	panel_changed.emit(panel)

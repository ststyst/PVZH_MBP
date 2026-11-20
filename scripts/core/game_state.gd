extends Node
## 全局游戏状态：玩家身份（单机 / 服务器）、当前存档、场景切换。
## 所有界面通过它判断当前身份与玩家资料，不直接持有存档对象。

enum IDENTITY_MODE { NONE, LOCAL, SERVER }
enum SCREEN { LOGIN, MAIN, BATTLE, DECK_BUILDER, COLLECTION, SOCIAL, EVENTS, SETTINGS }

signal identity_changed(mode: int)
signal screen_changed(screen: int)

const SCENE_LOGIN: String = "res://scenes/main/LoginScreen.tscn"
const SCENE_MAIN: String = "res://scenes/main/MainScreen.tscn"
const SCENE_BATTLE: String = "res://scenes/main/Battle.tscn"

var identity_mode: IDENTITY_MODE = IDENTITY_MODE.NONE
var current_screen: SCREEN = SCREEN.LOGIN

## 本地身份：当前存档槽位；服务器身份：空字符串
var active_slot_key: String = ""

## 当前玩家资料（本地身份来自本地存档；服务器身份来自服务器下发的快照）
var profile: PlayerProfile = null

## 服务器身份下的会话信息（地址、端口、账号、令牌等，由 M5 填充）
var server_session: Dictionary = {}


## 进入本地存档开始单机游戏。
func enter_local_game(slot_key: String) -> bool:
	var loaded_profile: PlayerProfile = SaveManager.load_slot(slot_key)
	if loaded_profile == null:
		push_warning("读取本地存档失败：%s" % slot_key)
		return false
	profile = loaded_profile
	profile.touch()
	active_slot_key = slot_key
	identity_mode = IDENTITY_MODE.LOCAL
	identity_changed.emit(identity_mode)
	SaveManager.save_slot(slot_key, profile)
	_change_scene(SCENE_MAIN, SCREEN.MAIN)
	return true


## 服务器登录成功后由网络层调用：切换到服务器身份（M5 接入）。
func enter_server_game(session_info: Dictionary, server_profile: PlayerProfile) -> void:
	server_session = session_info.duplicate()
	profile = server_profile
	active_slot_key = ""
	identity_mode = IDENTITY_MODE.SERVER
	identity_changed.emit(identity_mode)
	_change_scene(SCENE_MAIN, SCREEN.MAIN)


## 退出到登录界面（不删除任何存档）。
func leave_to_login() -> void:
	save_active_profile()
	profile = null
	active_slot_key = ""
	server_session.clear()
	identity_mode = IDENTITY_MODE.NONE
	identity_changed.emit(identity_mode)
	_change_scene(SCENE_LOGIN, SCREEN.LOGIN)


## 把当前本地存档写回磁盘；服务器身份不允许写本地。
func save_active_profile() -> bool:
	if profile == null:
		return false
	if identity_mode != IDENTITY_MODE.LOCAL:
		return false
	if active_slot_key.is_empty():
		return false
	profile.touch()
	return SaveManager.save_slot(active_slot_key, profile)


func go_to_main() -> void:
	_change_scene(SCENE_MAIN, SCREEN.MAIN)


func go_to_battle() -> void:
	_change_scene(SCENE_BATTLE, SCREEN.BATTLE)


func go_to_login() -> void:
	_change_scene(SCENE_LOGIN, SCREEN.LOGIN)


func is_local_mode() -> bool:
	return identity_mode == IDENTITY_MODE.LOCAL


func is_server_mode() -> bool:
	return identity_mode == IDENTITY_MODE.SERVER


func get_identity_text() -> String:
	match identity_mode:
		IDENTITY_MODE.LOCAL:
			return "单机身份"
		IDENTITY_MODE.SERVER:
			return "服务器身份"
		_:
			return "未登录"


func _change_scene(scene_path: String, screen: SCREEN) -> void:
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("切换场景失败：%s（错误码 %d）" % [scene_path, error])
		return
	current_screen = screen
	screen_changed.emit(screen)

extends Node
## 全局游戏状态：身份、当前存档、货币、游玩计时、场景切换、退出自动保存。

enum IDENTITY_MODE { NONE, LOCAL, SERVER }
enum SCREEN { LOGIN, MAIN, BATTLE, DECK_BUILDER, COLLECTION, SOCIAL, EVENTS, SETTINGS }
enum CURRENCY { GOLD, DIAMOND }

signal identity_changed(mode: int)
signal screen_changed(screen: int)
signal currency_changed(gold: int, diamond: int)
signal play_time_changed(total_seconds: int)

const GAME_VERSION: String = "alpha0.1"

const SCENE_LOGIN: String = "res://scenes/main/LoginScreen.tscn"
const SCENE_MAIN: String = "res://scenes/main/MainScreen.tscn"
const SCENE_BATTLE_PREP: String = "res://scenes/battle/BattlePrep.tscn"
const SCENE_BATTLE: String = "res://scenes/battle/Battle.tscn"
const SCENE_COLLECTION: String = "res://scenes/collection/CollectionScreen.tscn"
const SCENE_DECK_LIST: String = "res://scenes/deck/DeckList.tscn"
const SCENE_DECK_EDITOR: String = "res://scenes/deck/DeckEditor.tscn"
const SCENE_SETTINGS: String = "res://scenes/settings/SettingsScreen.tscn"
const SCENE_DEVELOPER_PANEL: String = "res://scenes/settings/DeveloperPanel.tscn"

## 本地游玩时每 30 秒自动落盘一次。
const AUTOSAVE_INTERVAL_SECONDS: float = 30.0

var identity_mode: IDENTITY_MODE = IDENTITY_MODE.NONE
var current_screen: SCREEN = SCREEN.LOGIN

## 本地身份：当前存档槽位；服务器身份：空字符串
var active_slot_key: String = ""

## 当前玩家资料（本地来自本地存档；服务器身份来自服务器快照）
var profile: PlayerProfile = null

## 服务器身份下的会话信息（地址、端口、账号等，由服务器登录流程填充）
var server_session: Dictionary = {}

var _pending_play_seconds: float = 0.0
var _autosave_elapsed_seconds: float = 0.0
var _main_preload_requested: bool = false
var _main_scene_loaded: bool = false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if identity_mode != IDENTITY_MODE.LOCAL or profile == null:
		return
	_pending_play_seconds += delta
	var whole_seconds: int = int(_pending_play_seconds)
	if whole_seconds <= 0:
		return
	_pending_play_seconds -= float(whole_seconds)
	profile.play_time_seconds += whole_seconds
	play_time_changed.emit(profile.play_time_seconds)
	_autosave_elapsed_seconds += float(whole_seconds)
	if _autosave_elapsed_seconds >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed_seconds = 0.0
		save_active_profile()


func _notification(what: int) -> void:
	# 关闭窗口 / 安卓返回键：保存后由引擎退出
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_active_profile()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_active_profile()


# ----- 身份与存档 -----

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
	_pending_play_seconds = 0.0
	_autosave_elapsed_seconds = 0.0
	if Engine.get_main_loop() != null:
		AppStorage.set_last_slot_key(slot_key)
	identity_changed.emit(identity_mode)
	currency_changed.emit(profile.gold, profile.diamond)
	save_active_profile()
	go_to_main()
	return true


## 服务器登录成功后由网络层调用：切换到服务器身份。
func enter_server_game(session_info: Dictionary, server_profile: PlayerProfile) -> void:
	server_session = session_info.duplicate()
	profile = server_profile
	active_slot_key = ""
	identity_mode = IDENTITY_MODE.SERVER
	identity_changed.emit(identity_mode)
	if profile != null:
		currency_changed.emit(profile.gold, profile.diamond)
	go_to_main()


## 退出到登录界面（不删除任何存档），会先保存并结算游玩时长。
func leave_to_login() -> void:
	save_active_profile()
	profile = null
	active_slot_key = ""
	server_session.clear()
	identity_mode = IDENTITY_MODE.NONE
	_pending_play_seconds = 0.0
	_autosave_elapsed_seconds = 0.0
	identity_changed.emit(identity_mode)
	_change_scene(SCENE_LOGIN, SCREEN.LOGIN)


## 把当前本地存档写回磁盘（含游玩时长）。服务器身份不允许写本地。
func save_active_profile() -> bool:
	if profile == null:
		return false
	if identity_mode != IDENTITY_MODE.LOCAL:
		return false
	if active_slot_key.is_empty():
		return false
	_flush_pending_play_time()
	profile.touch()
	return SaveManager.save_slot(active_slot_key, profile)


func _flush_pending_play_time() -> void:
	if profile == null:
		return
	var whole_seconds: int = int(_pending_play_seconds)
	if whole_seconds > 0:
		profile.play_time_seconds += whole_seconds
		_pending_play_seconds -= float(whole_seconds)
		play_time_changed.emit(profile.play_time_seconds)


func is_local_mode() -> bool:
	return identity_mode == IDENTITY_MODE.LOCAL


func is_server_mode() -> bool:
	return identity_mode == IDENTITY_MODE.SERVER


func is_developer_save() -> bool:
	return profile != null and profile.is_developer_save


func get_identity_text() -> String:
	match identity_mode:
		IDENTITY_MODE.LOCAL:
			return "单机身份"
		IDENTITY_MODE.SERVER:
			return "服务器身份"
		_:
			return "未登录"


func get_version() -> String:
	return GAME_VERSION


# ----- 货币 -----

func get_gold() -> int:
	return profile.gold if profile != null else 0


func get_diamond() -> int:
	return profile.diamond if profile != null else 0


func get_currency(currency: CURRENCY) -> int:
	match currency:
		CURRENCY.GOLD:
			return get_gold()
		CURRENCY.DIAMOND:
			return get_diamond()
		_:
			return 0


## 增加货币；amount <= 0 或没有存档时返回 false。
func add_currency(currency: CURRENCY, amount: int) -> bool:
	if profile == null or amount <= 0:
		return false
	match currency:
		CURRENCY.GOLD:
			profile.add_gold(amount)
		CURRENCY.DIAMOND:
			profile.add_diamond(amount)
		_:
			return false
	_emit_currency()
	return true


## 消耗货币；余额不足返回 false 且不扣除。
func spend_currency(currency: CURRENCY, amount: int) -> bool:
	if profile == null or amount <= 0:
		return false
	var spent: bool = false
	match currency:
		CURRENCY.GOLD:
			spent = profile.spend_gold(amount)
		CURRENCY.DIAMOND:
			spent = profile.spend_diamond(amount)
	if spent:
		_emit_currency()
	return spent


func add_gold(amount: int) -> bool:
	return add_currency(CURRENCY.GOLD, amount)


func spend_gold(amount: int) -> bool:
	return spend_currency(CURRENCY.GOLD, amount)


func add_diamond(amount: int) -> bool:
	return add_currency(CURRENCY.DIAMOND, amount)


func spend_diamond(amount: int) -> bool:
	return spend_currency(CURRENCY.DIAMOND, amount)


## 供 UI 主动同步货币显示（例如刚加载存档后）。
func emit_currency() -> void:
	_emit_currency()


func _emit_currency() -> void:
	if profile == null:
		currency_changed.emit(0, 0)
	else:
		currency_changed.emit(profile.gold, profile.diamond)


# ----- 场景切换 -----

## 预加载主界面（登录界面停留时调用），进入游戏时秒开。
func preload_main_scene() -> void:
	if _main_preload_requested or _main_scene_loaded:
		return
	_main_preload_requested = true
	ResourceLoader.load_threaded_request(SCENE_MAIN)


func is_main_scene_preloaded() -> bool:
	if _main_scene_loaded:
		return true
	if not _main_preload_requested:
		return false
	var status: int = ResourceLoader.load_threaded_get_status(SCENE_MAIN)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_main_scene_loaded = true
		return true
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_main_preload_requested = false
	return false


func go_to_main() -> void:
	if is_main_scene_preloaded():
		var scene: PackedScene = ResourceLoader.load_threaded_get(SCENE_MAIN) as PackedScene
		if scene != null:
			var packed_error: Error = get_tree().change_scene_to_packed(scene)
			if packed_error == OK:
				current_screen = SCREEN.MAIN
				screen_changed.emit(SCREEN.MAIN)
				return
	_change_scene(SCENE_MAIN, SCREEN.MAIN)


func go_to_battle_prep() -> void:
	_change_scene(SCENE_BATTLE_PREP, SCREEN.BATTLE)


func go_to_battle() -> void:
	_change_scene(SCENE_BATTLE, SCREEN.BATTLE)


func go_to_collection() -> void:
	_change_scene(SCENE_COLLECTION, SCREEN.COLLECTION)


func go_to_deck_list() -> void:
	_change_scene(SCENE_DECK_LIST, SCREEN.DECK_BUILDER)


func go_to_deck_editor() -> void:
	_change_scene(SCENE_DECK_EDITOR, SCREEN.DECK_BUILDER)


func go_to_settings() -> void:
	_change_scene(SCENE_SETTINGS, SCREEN.SETTINGS)


func go_to_developer_panel() -> void:
	_change_scene(SCENE_DEVELOPER_PANEL, SCREEN.SETTINGS)


func go_to_login() -> void:
	_change_scene(SCENE_LOGIN, SCREEN.LOGIN)


func _change_scene(scene_path: String, screen: SCREEN) -> void:
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("切换场景失败：%s（错误码 %d）" % [scene_path, error])
		return
	current_screen = screen
	screen_changed.emit(screen)

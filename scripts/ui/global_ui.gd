extends CanvasLayer
## 全局 UI：金币/钻石 + 设置按钮，跨场景常驻。
##
## 显示模式：
## - ALL：全部显示
## - SETTINGS_ONLY：只显示设置按钮（登录、战斗自动使用）
## - HIDDEN：全部关闭
## 设置界面作为覆盖层打开，不会切换场景，因此战斗内可以安全投降。

enum VISIBILITY { ALL, SETTINGS_ONLY, HIDDEN }

@onready var top_bar: HBoxContainer = %TopBar
@onready var gold_label: Label = %GoldLabel
@onready var diamond_label: Label = %DiamondLabel
@onready var settings_button: Button = %SettingsButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var settings_screen: SettingsScreen = %SettingsScreen

var visibility_mode: int = VISIBILITY.ALL
var _paused_for_settings: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings_button.pressed.connect(_open_settings)
	settings_screen.close_requested.connect(_close_settings)
	settings_screen.surrender_requested.connect(_on_surrender_requested)
	GameState.screen_changed.connect(_on_screen_changed)
	GameState.currency_changed.connect(_on_currency_changed)
	settings_overlay.visible = false
	settings_screen.visible = false
	_refresh_currency(GameState.get_gold(), GameState.get_diamond())
	call_deferred("_apply_screen_defaults", GameState.current_screen)


func show_all() -> void:
	set_visibility(VISIBILITY.ALL)


func hide_all() -> void:
	set_visibility(VISIBILITY.HIDDEN)


func show_settings_only() -> void:
	set_visibility(VISIBILITY.SETTINGS_ONLY)


func set_visibility(mode: int) -> void:
	visibility_mode = clampi(mode, VISIBILITY.ALL, VISIBILITY.HIDDEN)
	if visibility_mode == VISIBILITY.HIDDEN and settings_overlay.visible:
		_close_settings()
	_apply_visibility()


func _apply_visibility() -> void:
	var show_currency: bool = visibility_mode == VISIBILITY.ALL
	gold_label.visible = show_currency
	diamond_label.visible = show_currency
	settings_button.visible = visibility_mode != VISIBILITY.HIDDEN
	top_bar.visible = visibility_mode != VISIBILITY.HIDDEN and not settings_overlay.visible


func _apply_screen_defaults(screen: int) -> void:
	if screen == GameState.SCREEN.LOGIN:
		show_settings_only()
	elif screen == GameState.SCREEN.BATTLE and _is_battle_scene():
		show_settings_only()
	else:
		show_all()


func _on_screen_changed(screen: int) -> void:
	if settings_overlay.visible:
		_close_settings()
	# change_scene_to_file 在帧末才替换 current_scene，等两帧再判断是否为战斗场景。
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_screen_defaults(screen)


func _open_settings() -> void:
	if settings_overlay.visible:
		return
	var in_battle: bool = _is_battle_scene()
	settings_overlay.visible = true
	top_bar.visible = false
	settings_screen.open_as_overlay(in_battle)
	settings_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	if in_battle and not get_tree().paused:
		get_tree().paused = true
		_paused_for_settings = true


func _close_settings() -> void:
	settings_overlay.visible = false
	settings_screen.visible = false
	if _paused_for_settings:
		get_tree().paused = false
		_paused_for_settings = false
	_apply_visibility()


func _on_surrender_requested() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("surrender_player"):
		scene.surrender_player()
	_close_settings()


func _is_battle_scene() -> bool:
	var scene: Node = get_tree().current_scene
	return scene != null and scene.has_method("surrender_player")


func _on_currency_changed(gold: int, diamond: int) -> void:
	_refresh_currency(gold, diamond)


func _refresh_currency(gold: int, diamond: int) -> void:
	gold_label.text = "金币 %d" % gold
	diamond_label.text = "钻石 %d" % diamond

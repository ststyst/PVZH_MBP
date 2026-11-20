extends Control
## 主界面：各模块的中转站。社交 / 活动为服务器身份专属。

const TOOLTIP_SERVER_ONLY: String = "仅服务器身份可用（登录专用服务端后开放）"

@onready var player_label: Label = %PlayerLabel
@onready var gold_label: Label = %GoldLabel
@onready var dust_label: Label = %DustLabel
@onready var identity_label: Label = %IdentityLabel
@onready var battle_button: Button = %BattleButton
@onready var deck_button: Button = %DeckButton
@onready var collection_button: Button = %CollectionButton
@onready var social_button: Button = %SocialButton
@onready var events_button: Button = %EventsButton
@onready var settings_button: Button = %SettingsButton
@onready var dev_button: Button = %DevButton
@onready var logout_button: Button = %LogoutButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_connect_signals()
	_refresh_header()
	_apply_identity_rules()


func _connect_signals() -> void:
	battle_button.pressed.connect(_on_battle_pressed)
	deck_button.pressed.connect(_on_deck_pressed)
	collection_button.pressed.connect(_on_collection_pressed)
	social_button.pressed.connect(_on_social_pressed)
	events_button.pressed.connect(_on_events_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	dev_button.pressed.connect(_on_dev_pressed)
	logout_button.pressed.connect(_on_logout_pressed)


func _refresh_header() -> void:
	var profile: PlayerProfile = GameState.profile
	if profile == null:
		player_label.text = "未登录"
		gold_label.text = ""
		dust_label.text = ""
		identity_label.text = GameState.get_identity_text()
		_set_status("没有玩家资料，请返回登录界面。", true)
		return
	player_label.text = profile.player_name
	gold_label.text = "金币 %d" % profile.gold
	dust_label.text = "钻石 %d" % profile.diamond
	identity_label.text = "%s　·　当前牌组：%s" % [
		GameState.get_identity_text(),
		_get_active_deck_name(profile),
	]


func _get_active_deck_name(profile: PlayerProfile) -> String:
	var active_deck: DeckData = profile.get_active_deck()
	if active_deck == null:
		return "未选择"
	return active_deck.deck_name


func _apply_identity_rules() -> void:
	var server_mode: bool = GameState.is_server_mode()
	social_button.disabled = not server_mode
	events_button.disabled = not server_mode
	social_button.tooltip_text = "" if server_mode else TOOLTIP_SERVER_ONLY
	events_button.tooltip_text = "" if server_mode else TOOLTIP_SERVER_ONLY
	dev_button.visible = GameState.is_developer_save()


func _on_battle_pressed() -> void:
	GameState.go_to_battle_prep()


func _on_deck_pressed() -> void:
	GameState.go_to_deck_editor()


func _on_collection_pressed() -> void:
	_show_placeholder("卡牌收藏", "收藏界面由 UI 实现后接入；数据 API 已就绪（CardDatabase / CollectionManager）。")


func _on_social_pressed() -> void:
	_show_placeholder("社交", "好友、聊天与对战邀请将在服务器身份下开放（M6）。")


func _on_events_pressed() -> void:
	_show_placeholder("活动", "服主配置的玩法与签到奖励将在 M6 实现。")


func _on_settings_pressed() -> void:
	GameState.go_to_settings()


func _on_dev_pressed() -> void:
	GameState.go_to_developer_panel()


func _on_logout_pressed() -> void:
	GameState.leave_to_login()


func _show_placeholder(module_name: String, detail: String) -> void:
	_set_status("%s：%s" % [module_name, detail])


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)

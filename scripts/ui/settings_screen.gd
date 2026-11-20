extends Control
## 设置界面：主音量、显示预设、账号/存档信息、保存存档、开发者调试入口、返回。

@onready var back_button: Button = %BackButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var display_option: OptionButton = %DisplayOption
@onready var display_hint: Label = %DisplayHint
@onready var info_label: Label = %InfoLabel
@onready var save_button: Button = %SaveButton
@onready var developer_button: Button = %DeveloperButton
@onready var status_label: Label = %StatusLabel
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = AppStorage.get_master_volume()
	volume_slider.value_changed.connect(_on_volume_changed)
	_update_volume_label()
	save_button.pressed.connect(_on_save_pressed)
	developer_button.pressed.connect(_on_developer_pressed)
	_setup_display_options()
	_refresh_info()
	version_label.text = "版本 %s · %s" % [GameState.get_version(), GameState.get_identity_text()]
	_set_status("设置会立即生效并保存。")


func _update_volume_label() -> void:
	volume_value.text = "%d%%" % int(round(volume_slider.value * 100.0))


func _on_volume_changed(value: float) -> void:
	AppStorage.set_master_volume(value)
	_update_volume_label()
	_set_status("主音量已保存：%d%%" % int(round(value * 100.0)))


func _setup_display_options() -> void:
	display_option.clear()
	var current_id: String = DisplayService.get_current_preset_id()
	var presets: Array[Dictionary] = DisplayService.get_presets()
	var selected_index: int = 0
	for index: int in range(presets.size()):
		var preset: Dictionary = presets[index]
		var preset_id: String = str(preset.get("id", ""))
		display_option.add_item(str(preset.get("label", preset_id)))
		display_option.set_item_metadata(index, preset_id)
		if preset_id == current_id:
			selected_index = index
	display_option.select(selected_index)
	display_option.item_selected.connect(_on_display_selected)
	display_hint.text = _preset_description(current_id)


func _on_display_selected(index: int) -> void:
	var preset_id: String = str(display_option.get_item_metadata(index))
	if DisplayService.apply_preset(preset_id):
		display_hint.text = _preset_description(preset_id)
		_set_status("显示已切换：%s" % display_option.get_item_text(index))
	else:
		_set_status("显示预设切换失败。", true)


func _preset_description(preset_id: String) -> String:
	for preset: Dictionary in DisplayService.get_presets():
		if str(preset.get("id", "")) == preset_id:
			return str(preset.get("description", ""))
	return ""


func _refresh_info() -> void:
	var profile: PlayerProfile = GameState.profile
	if profile == null:
		info_label.text = "尚未载入玩家存档。"
		save_button.disabled = true
		developer_button.disabled = true
		return
	var lines: Array[String] = [
		"身份：%s" % GameState.get_identity_text(),
		"玩家：%s" % profile.player_name,
		"金币：%d　钻石：%d" % [profile.gold, profile.diamond],
		"开发者存档：%s" % ("是" if profile.is_developer_save else "否"),
	]
	if GameState.is_local_mode():
		lines.append("存档：%s" % GameState.active_slot_key)
	else:
		lines.append("本地存档：由服务器托管")
		var server_login: Dictionary = AppStorage.get_server_login()
		if not str(server_login.get("account", "")).is_empty():
			lines.append("服务器账号：%s" % server_login.get("account", ""))
	info_label.text = "\n".join(lines)
	save_button.disabled = not GameState.is_local_mode()
	developer_button.disabled = not GameState.is_developer_save()
	developer_button.tooltip_text = "" if GameState.is_developer_save() else "仅开发者存档可打开调试界面"


func _on_save_pressed() -> void:
	if not GameState.is_local_mode():
		_set_status("服务器身份由服务器保存，本地无需保存。", true)
		return
	if GameState.save_active_profile():
		_set_status("存档已保存。")
	else:
		_set_status("保存失败：当前没有可保存的本地存档。", true)


func _on_developer_pressed() -> void:
	if not GameState.is_developer_save():
		_set_status("仅开发者存档可打开调试界面。", true)
		return
	GameState.go_to_developer_panel()


func _on_back_pressed() -> void:
	GameState.go_to_main()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)

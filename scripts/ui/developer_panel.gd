extends Control
## 开发者调试界面（仅开发者存档可用）：货币、卡牌、CSV 编译与卡牌数据库重载。

@onready var back_button: Button = %BackButton
@onready var info_label: Label = %InfoLabel
@onready var add_gold_button: Button = %AddGoldButton
@onready var add_diamond_button: Button = %AddDiamondButton
@onready var reset_currency_button: Button = %ResetCurrencyButton
@onready var unlock_cards_button: Button = %UnlockCardsButton
@onready var clear_cards_button: Button = %ClearCardsButton
@onready var compile_official_button: Button = %CompileOfficialButton
@onready var compile_import_button: Button = %CompileImportButton
@onready var reload_cards_button: Button = %ReloadCardsButton
@onready var report_button: Button = %ReportButton
@onready var clear_pack_button: Button = %ClearPackButton
@onready var result_text: TextEdit = %ResultText

var _action_buttons: Array[Button] = []


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	add_gold_button.pressed.connect(_on_add_gold)
	add_diamond_button.pressed.connect(_on_add_diamond)
	reset_currency_button.pressed.connect(_on_reset_currency)
	unlock_cards_button.pressed.connect(_on_unlock_cards)
	clear_cards_button.pressed.connect(_on_clear_cards)
	compile_official_button.pressed.connect(_on_compile_official)
	compile_import_button.pressed.connect(_on_compile_import)
	reload_cards_button.pressed.connect(_on_reload_cards)
	report_button.pressed.connect(_on_show_report)
	clear_pack_button.pressed.connect(_on_clear_pack)
	_action_buttons = [
		add_gold_button, add_diamond_button, reset_currency_button,
		unlock_cards_button, clear_cards_button,
		compile_official_button, compile_import_button, reload_cards_button,
		report_button, clear_pack_button,
	]
	_refresh_info()
	if not DeveloperTools.is_enabled():
		for button: Button in _action_buttons:
			button.disabled = true
		_write_result("仅开发者存档可用。请使用编辑器内创建的存档进入游戏。")
	else:
		_write_result("准备好后点击上方按钮；结果显示在这里。")


func _refresh_info() -> void:
	var profile: PlayerProfile = GameState.profile
	if profile == null:
		info_label.text = "未载入存档。"
		return
	var pack_text: String = "存在" if DeveloperTools.has_compiled_official_pack() else "不存在"
	info_label.text = "开发者存档：%s\n玩家：%s　金币：%d　钻石：%d\n卡牌：%d 张（加载错误 %d 条）\n官方编译包：%s" % [
		"是" if profile.is_developer_save else "否",
		profile.player_name, profile.gold, profile.diamond,
		CardDatabase.card_count(), CardDatabase.load_errors.size(), pack_text,
	]


func _on_add_gold() -> void:
	if DeveloperTools.add_gold(1000):
		_write_result("金币 +1000")
	else:
		_write_result("增加金币失败。")
	_refresh_info()


func _on_add_diamond() -> void:
	if DeveloperTools.add_diamond(100):
		_write_result("钻石 +100")
	else:
		_write_result("增加钻石失败。")
	_refresh_info()


func _on_reset_currency() -> void:
	DeveloperTools.set_currencies(0, 0)
	_write_result("货币已重置为 0 / 0。")
	_refresh_info()


func _on_unlock_cards() -> void:
	var added: int = DeveloperTools.unlock_all_cards()
	_write_result("解锁全部卡牌：新增 %d 张。" % added)
	_refresh_info()


func _on_clear_cards() -> void:
	DeveloperTools.clear_all_cards()
	_write_result("已清空全部卡牌。")
	_refresh_info()


func _on_compile_official() -> void:
	var result: Dictionary = DeveloperTools.compile_official_cards()
	_write_result(_format_compile_result(result))
	_refresh_info()


func _on_compile_import() -> void:
	var result: Dictionary = DeveloperTools.compile_card_set()
	_write_result(_format_compile_result(result))
	_refresh_info()


func _on_reload_cards() -> void:
	var count: int = DeveloperTools.reload_card_database(true)
	var errors: Array[String] = DeveloperTools.get_card_database_errors()
	var lines: Array[String] = ["重新加载卡牌：%d 张。" % count]
	if errors.is_empty():
		lines.append("没有加载错误。")
	else:
		lines.append("加载错误 %d 条：" % errors.size())
		for message: String in errors:
			lines.append("  - " + message)
	_write_result("\n".join(lines))
	_refresh_info()


func _on_show_report() -> void:
	var report: String = DeveloperTools.get_compile_report()
	if report.strip_edges().is_empty():
		_write_result("暂无编译报告（%s）。" % DeveloperTools.get_compile_report_path())
	else:
		_write_result(report)


func _on_clear_pack() -> void:
	if DeveloperTools.clear_compiled_official_pack():
		_write_result("已删除官方编译包，下次加载回退 CSV。")
	else:
		_write_result("没有可删除的官方编译包。")
	_refresh_info()


func _format_compile_result(result: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(str(result.get("summary", "编译结束。")))
	lines.append("卡牌数：%d" % int(result.get("card_count", 0)))
	if not str(result.get("pack_path", "")).is_empty():
		lines.append("编译包：%s" % result.get("pack_path", ""))
	if not str(result.get("report_path", "")).is_empty():
		lines.append("报告：%s" % result.get("report_path", ""))
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])
	if not errors.is_empty():
		lines.append("错误 %d 条：" % errors.size())
		for message: Variant in errors:
			lines.append("  - " + str(message))
	if not warnings.is_empty():
		lines.append("警告 %d 条：" % warnings.size())
		for message: Variant in warnings:
			lines.append("  - " + str(message))
	return "\n".join(lines)


func _write_result(text: String) -> void:
	result_text.text = text


func _on_back_pressed() -> void:
	GameState.go_to_settings()

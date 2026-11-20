extends Node
## 开发者存档专属的测试功能 API。界面上的「测试」按钮打开面板后调用这里的方法。
## 非开发者存档时 is_enabled() 为 false，所有操作都会被拒绝。

signal test_action_done(action: String, detail: String)


func is_enabled() -> bool:
	return GameState.is_developer_save()


## 增加金币（仅开发者存档）。
func add_gold(amount: int = 100) -> bool:
	if not is_enabled() or amount <= 0:
		return false
	var ok: bool = GameState.add_gold(amount)
	if ok:
		test_action_done.emit("add_gold", "+%d" % amount)
	return ok


## 增加钻石（仅开发者存档）。
func add_diamond(amount: int = 100) -> bool:
	if not is_enabled() or amount <= 0:
		return false
	var ok: bool = GameState.add_diamond(amount)
	if ok:
		test_action_done.emit("add_diamond", "+%d" % amount)
	return ok


## 解锁全部卡牌到持有上限（仅开发者存档），返回新增张数。
func unlock_all_cards() -> int:
	if not is_enabled() or GameState.profile == null:
		return 0
	var added: int = 0
	for card_id: String in CardDatabase.all_card_ids():
		var card: CardData = CardDatabase.get_card(card_id)
		if card == null:
			continue
		var max_copies: int = CollectionManager.max_copies_for(card)
		var owned: int = GameState.profile.get_card_count(card_id)
		if owned < max_copies:
			GameState.profile.add_card(card_id, max_copies - owned)
			added += max_copies - owned
	GameState.save_active_profile()
	test_action_done.emit("unlock_all_cards", "+%d" % added)
	return added


## 清空全部卡牌（仅开发者存档），方便测试卡包/合成流程。
func clear_all_cards() -> void:
	if not is_enabled() or GameState.profile == null:
		return
	GameState.profile.owned_cards.clear()
	GameState.save_active_profile()
	test_action_done.emit("clear_all_cards", "0")


## 重设货币为指定数值（仅开发者存档）。
func set_currencies(gold: int, diamond: int) -> void:
	if not is_enabled() or GameState.profile == null:
		return
	GameState.profile.gold = maxi(gold, 0)
	GameState.profile.diamond = maxi(diamond, 0)
	GameState.emit_currency()
	GameState.save_active_profile()
	test_action_done.emit("set_currencies", "金币 %d / 钻石 %d" % [gold, diamond])


# ----- 卡牌 CSV 编译（开发者测试界面） -----

## 编译指定目录下的 config.csv / cards.csv。
## 默认目录：user://card_packs/import（玩家/开发者把 CSV 放这里）。
## 返回 CardSetCompiler 的报告：{ ok, summary, errors, warnings, card_count, pack_path, report_path }
func compile_card_set(
	source_dir: String = "",
	card_namespace: String = "",
	output_pack_path: String = "",
) -> Dictionary:
	if not is_enabled():
		return {"ok": false, "summary": "仅开发者存档可用。", "errors": ["仅开发者存档可用。"], "warnings": [], "card_count": 0, "pack_path": "", "report_path": ""}
	var target_dir: String = source_dir
	if target_dir.is_empty():
		target_dir = CardSetCompiler.DEFAULT_IMPORT_DIR
	var target_namespace: String = card_namespace
	if target_namespace.is_empty():
		target_namespace = CardDatabase.OFFICIAL_NAMESPACE
	var result: Dictionary = CardSetCompiler.compile_pack(
		target_dir,
		target_namespace,
		output_pack_path,
		CardDatabase.config,
	)
	test_action_done.emit("compile_card_set", str(result.get("summary", "")))
	return result


## 直接编译官方 CSV（res://data/cards/official），产物写入官方编译包路径。
func compile_official_cards() -> Dictionary:
	if not is_enabled():
		return {"ok": false, "summary": "仅开发者存档可用。", "errors": ["仅开发者存档可用。"], "warnings": [], "card_count": 0, "pack_path": "", "report_path": ""}
	var result: Dictionary = CardSetCompiler.compile_pack(
		CardDatabase.OFFICIAL_DIR,
		CardDatabase.OFFICIAL_NAMESPACE,
		CardDatabase.COMPILED_OFFICIAL_PACK,
		CardDatabase.config,
	)
	test_action_done.emit("compile_official_cards", str(result.get("summary", "")))
	return result


## 最近一次编译报告文件路径（user:// 下，可直接用文本编辑器查看）。
func get_compile_report_path() -> String:
	return CardSetCompiler.REPORT_PATH


## 读取最近一次编译报告的文本内容。
func get_compile_report() -> String:
	if not FileAccess.file_exists(CardSetCompiler.REPORT_PATH):
		return ""
	return FileAccess.get_file_as_string(CardSetCompiler.REPORT_PATH)


## 重新加载卡牌数据库（默认优先读取编译包），返回卡牌数量。
func reload_card_database(use_compiled_pack: bool = true) -> int:
	CardDatabase.reload(use_compiled_pack)
	test_action_done.emit("reload_card_database", "卡牌 %d 张" % CardDatabase.card_count())
	return CardDatabase.card_count()


func get_card_database_errors() -> Array[String]:
	return CardDatabase.load_errors.duplicate()


func has_compiled_official_pack() -> bool:
	return FileAccess.file_exists(CardDatabase.COMPILED_OFFICIAL_PACK)


## 删除官方编译包（下次启动/重载回退 CSV）。
func clear_compiled_official_pack() -> bool:
	return CardDatabase.clear_compiled_official_pack()

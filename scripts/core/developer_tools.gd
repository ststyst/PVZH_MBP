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

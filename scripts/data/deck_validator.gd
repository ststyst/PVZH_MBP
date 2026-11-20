class_name DeckValidator
extends RefCounted
## 牌组合法性校验（依赖 CardDatabase 的卡牌数据）：
## - 张数固定为 DeckData.MAX_CARD_COUNT
## - 同名卡数量受稀有度限制（传说 1 张，其余 2 张）
## - 职业限制：牌组只能使用 allowed_classes 内的职业；中立牌始终允许
## - 卡牌必须存在于卡牌数据库
## database 只需提供 get_card(card_id) -> CardData。

## 返回错误列表；空数组表示牌组合法。
## database 为卡牌数据库（鸭子类型：只需提供 get_card(card_id)，不写死类型以便测试替换）。
static func validate(deck: DeckData, database) -> Array[String]:
	var errors: Array[String] = []
	if deck == null:
		errors.append("牌组不存在。")
		return errors
	if database == null:
		errors.append("卡牌数据库不可用。")
		return errors
	if deck.card_count() != DeckData.MAX_CARD_COUNT:
		errors.append("牌组需要正好 %d 张卡，当前 %d 张。" % [DeckData.MAX_CARD_COUNT, deck.card_count()])
	if deck.allowed_classes.is_empty():
		errors.append("未设置允许的职业，无法校验牌组。")
	var counts: Dictionary = {}
	for card_id: String in deck.card_ids:
		counts[card_id] = int(counts.get(card_id, 0)) + 1
	for card_id: String in counts.keys():
		var card: CardData = database.get_card(card_id) as CardData
		if card == null:
			errors.append("卡牌不存在：%s" % card_id)
			continue
		var copies: int = int(counts[card_id])
		if copies > card.max_copies():
			errors.append("卡牌 %s 有 %d 张，最多 %d 张。" % [card_id, copies, card.max_copies()])
		if card.card_class != "neutral" and not deck.allowed_classes.has(card.card_class):
			errors.append("卡牌 %s 的职业 %s 不在允许范围内。" % [card_id, card.card_class])
		if not card.deck_includable:
			errors.append("卡牌 %s 不可被编入牌组。" % card_id)
	return errors


## 添加一张牌是否合法（用于牌组编辑器高亮/禁用）。
static func can_add_card(deck: DeckData, card: CardData, database) -> bool:
	if deck == null or card == null or database == null:
		return false
	if not card.deck_includable:
		return false
	if deck.card_count() >= DeckData.MAX_CARD_COUNT:
		return false
	if deck.count_of(card.card_id) >= card.max_copies():
		return false
	if card.card_class != "neutral" and not deck.allowed_classes.has(card.card_class):
		return false
	return true

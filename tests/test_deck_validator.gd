@tool
extends McpTestSuite
## 牌组规则测试：职业限制、稀有度张数、卡牌存在性。suite = "deck_rules"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")

var database: Node = null


func suite_name() -> String:
	return "deck_rules"


func setup() -> void:
	database = CardDatabaseScript.new()
	database.reload()


func teardown() -> void:
	if is_instance_valid(database):
		database.free()
	database = null


func _has_error(errors: Array[String], text: String) -> bool:
	for message: String in errors:
		if message.find(text) != -1:
			return true
	return false


func _make_deck(allowed: Array[String], ids: Array[String]) -> DeckData:
	var deck := DeckData.new()
	deck.hero_id = "test_hero"
	deck.allowed_classes = allowed.duplicate()
	deck.card_ids = ids.duplicate()
	return deck


## 从数据库挑选指定职业（不含传说）的卡牌，重复到 count 张；循环次数保证同名不超过 2 张。
func _valid_ids(classes: Array[String], count: int) -> Array[String]:
	var candidates: Array[String] = []
	for card_id: String in database.all_card_ids():
		var card: CardData = database.get_card(card_id)
		if card == null or card.max_copies() < 2:
			continue
		if card.card_class != "neutral" and not card.card_class in classes:
			continue
		candidates.append(card_id)
	var result: Array[String] = []
	var index: int = 0
	while result.size() < count and not candidates.is_empty():
		result.append(candidates[index % candidates.size()])
		index += 1
	return result


func test_valid_deck() -> void:
	var allowed: Array[String] = ["smarty", "sneaky"]
	var deck: DeckData = _make_deck(allowed, _valid_ids(allowed, DeckData.MAX_CARD_COUNT))
	assert_eq(deck.card_count(), DeckData.MAX_CARD_COUNT)
	var errors: Array[String] = DeckValidator.validate(deck, database)
	assert_eq(errors.size(), 0, "合法牌组不应有错误：%s" % [errors])


func test_class_restriction() -> void:
	var allowed: Array[String] = ["smarty", "sneaky"]
	var ids: Array[String] = _valid_ids(allowed, DeckData.MAX_CARD_COUNT)
	ids[0] = "pvzh:charger"
	var errors: Array[String] = DeckValidator.validate(_make_deck(allowed, ids), database)
	assert_true(_has_error(errors, "职业"), "越界职业应报错：%s" % [errors])


func test_legend_copy_limit() -> void:
	var allowed: Array[String] = ["neutral", "smarty", "sneaky"]
	var ids: Array[String] = _valid_ids(allowed, DeckData.MAX_CARD_COUNT - 2)
	ids.append("pvzh:ancient_dragon")
	ids.append("pvzh:ancient_dragon")
	var errors: Array[String] = DeckValidator.validate(_make_deck(allowed, ids), database)
	assert_true(_has_error(errors, "最多 1 张"), "传说卡超过 1 张应报错：%s" % [errors])


func test_missing_card() -> void:
	var allowed: Array[String] = ["smarty", "sneaky"]
	var ids: Array[String] = _valid_ids(allowed, DeckData.MAX_CARD_COUNT)
	ids[0] = "pvzh:missing_card"
	var errors: Array[String] = DeckValidator.validate(_make_deck(allowed, ids), database)
	assert_true(_has_error(errors, "不存在"), "不存在的卡牌应报错：%s" % [errors])


func test_missing_allowed_classes() -> void:
	var allowed: Array[String] = ["neutral"]
	var ids: Array[String] = _valid_ids(allowed, DeckData.MAX_CARD_COUNT)
	var empty_classes: Array[String] = []
	var deck: DeckData = _make_deck(empty_classes, ids)
	var errors: Array[String] = DeckValidator.validate(deck, database)
	assert_true(_has_error(errors, "未设置允许的职业"), "缺少职业限制应报错：%s" % [errors])


func test_can_add_card() -> void:
	var allowed: Array[String] = ["smarty"]
	var deck: DeckData = _make_deck(allowed, [])
	var fireball: CardData = database.get_card("pvzh:fireball")
	var charger: CardData = database.get_card("pvzh:charger")
	var turtle: CardData = database.get_card("pvzh:turtle")
	assert_true(DeckValidator.can_add_card(deck, fireball, database))
	assert_true(DeckValidator.can_add_card(deck, turtle, database), "中立牌始终允许")
	assert_false(DeckValidator.can_add_card(deck, charger, database), "职业不符不能加入")


class StubDatabase:
	var values: Dictionary = {}

	func get_card(card_id: String):
		return values.get(card_id)


func _make_stub_card(card_id: String, deck_includable: bool) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.card_class = "neutral"
	card.rarity = "normal"
	card.deck_includable = deck_includable
	return card


func test_deck_includable_rule() -> void:
	var stub: StubDatabase = StubDatabase.new()
	var locked: CardData = _make_stub_card("locked_card", false)
	stub.values["locked_card"] = locked
	var allowed: Array[String] = ["neutral"]
	var empty_cards: Array[String] = []
	var deck: DeckData = _make_deck(allowed, empty_cards)
	assert_false(DeckValidator.can_add_card(deck, locked, stub), "不可编入的卡不能加入牌组")
	var ids: Array[String] = []
	for _index: int in range(DeckData.MAX_CARD_COUNT):
		ids.append("locked_card")
	var full_deck: DeckData = _make_deck(allowed, ids)
	var errors: Array[String] = DeckValidator.validate(full_deck, stub)
	assert_true(_has_error(errors, "不可被编入牌组"), "校验应报告不可编入：%s" % [errors])

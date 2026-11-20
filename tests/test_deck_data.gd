@tool
extends McpTestSuite
## 牌组数据规则测试。运行方式：MCP test_run（suite = "deck"）。


func suite_name() -> String:
	return "deck"


func test_add_remove_and_limits() -> void:
	var deck := DeckData.new()
	assert_eq(deck.card_count(), 0)
	assert_true(deck.add_card("alpha"))
	assert_true(deck.add_card("alpha"))
	assert_false(deck.add_card("alpha"), "同名卡超过 2 张应失败")
	assert_eq(deck.count_of("alpha"), 2)
	assert_true(deck.remove_card("alpha"))
	assert_eq(deck.count_of("alpha"), 1)
	assert_false(deck.remove_card("missing"), "移除不存在的卡应返回 false")


func test_full_deck_limit() -> void:
	var deck := DeckData.new()
	for index: int in range(DeckData.MAX_CARD_COUNT):
		assert_true(deck.add_card("card_%d" % index))
	assert_eq(deck.card_count(), DeckData.MAX_CARD_COUNT)
	assert_false(deck.add_card("overflow"), "牌组已满时不能再加牌")


func test_validate() -> void:
	var deck := DeckData.new()
	var errors: Array[String] = deck.validate()
	assert_true(errors.size() >= 2, "空牌组应报出张数不足与缺少英雄")
	deck.hero_id = "hero_mage"
	for index: int in range(DeckData.MIN_CARD_COUNT):
		deck.add_card("card_%d" % index)
	assert_eq(deck.validate().size(), 0, "30 张且选了英雄时应合法")


func test_serialization() -> void:
	var deck := DeckData.new()
	deck.deck_id = "deck_test"
	deck.deck_name = "序列化"
	deck.hero_id = "hero_mage"
	assert_true(deck.add_card("a"))
	assert_true(deck.add_card("b"))
	var restored := DeckData.from_dict(deck.to_dict())
	assert_eq(restored.deck_id, "deck_test")
	assert_eq(restored.deck_name, "序列化")
	assert_eq(restored.hero_id, "hero_mage")
	assert_eq(restored.card_ids.size(), 2)
	assert_eq(restored.card_ids[0], "a")

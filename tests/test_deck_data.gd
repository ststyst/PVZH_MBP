@tool
extends McpTestSuite
## 牌组数据结构测试（张数限制改由 DeckRules 负责）。suite = "deck"。

func suite_name() -> String:
	return "deck"


func test_add_remove_and_counts() -> void:
	var deck := DeckData.new()
	assert_eq(deck.card_count(), 0)
	for _index: int in range(5):
		assert_true(deck.add_card("alpha"))
	assert_eq(deck.card_count(), 5)
	assert_eq(deck.count_of("alpha"), 5, "DeckData 本身不限制张数，由规则层校验")
	assert_eq(int(deck.get_card_counts().get("alpha", 0)), 5)
	assert_true(deck.remove_card("alpha"))
	assert_eq(deck.count_of("alpha"), 4)
	assert_false(deck.remove_card("missing"))


func test_clear_cards() -> void:
	var deck := DeckData.new()
	deck.add_card("a")
	deck.add_card("b")
	assert_eq(deck.card_count(), 2)
	deck.clear_cards()
	assert_eq(deck.card_count(), 0)


func test_tags() -> void:
	var deck := DeckData.new()
	deck.add_tag("default")
	deck.add_tag("default")
	assert_true(deck.has_tag("default"))
	assert_eq(deck.tags.size(), 1)
	deck.remove_tag("default")
	assert_false(deck.has_tag("default"))


func test_serialization() -> void:
	var deck := DeckData.new()
	deck.deck_id = "deck_test"
	deck.deck_name = "序列化"
	deck.hero_id = "green_knight"
	var allowed: Array[String] = ["solar", "guardian"]
	deck.allowed_classes = allowed
	deck.add_tag("default")
	assert_true(deck.add_card("a"))
	assert_true(deck.add_card("b"))
	var restored := DeckData.from_dict(deck.to_dict())
	assert_eq(restored.deck_id, "deck_test")
	assert_eq(restored.deck_name, "序列化")
	assert_eq(restored.hero_id, "green_knight")
	assert_eq(restored.allowed_classes.size(), 2)
	assert_eq(restored.card_ids.size(), 2)
	assert_eq(restored.card_ids[0], "a")
	assert_true(restored.has_tag("default"))

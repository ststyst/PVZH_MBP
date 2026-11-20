@tool
extends McpTestSuite
## 卡牌数据加载测试。运行方式：MCP test_run（suite = "cards"）。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")

var database: Node = null


func suite_name() -> String:
	return "cards"


func setup() -> void:
	database = CardDatabaseScript.new()


func teardown() -> void:
	if is_instance_valid(database):
		database.free()
	database = null


func test_base_set_loaded() -> void:
	database.reload()
	assert_gt(database.card_count(), 20, "基础卡集应已从 data/cards 加载")
	assert_true(database.has_card("mage_fireball"))
	assert_true(database.has_card("neutral_ancient_dragon"))


func test_card_fields() -> void:
	database.reload()
	var fireball: CardData = database.get_card("mage_fireball")
	assert_true(fireball != null, "火球术应存在")
	if fireball == null:
		return
	assert_eq(fireball.cost, 4)
	assert_eq(fireball.card_type, CardData.CARD_TYPE.SPELL)
	assert_eq(fireball.card_class, CardData.CARD_CLASS.MAGE)
	assert_eq(fireball.get_type_text(), "法术")
	assert_eq(fireball.get_class_text(), "法师")
	assert_eq(fireball.get_rarity_text(), "稀有")


func test_keywords_parsed() -> void:
	database.reload()
	var turtle: CardData = database.get_card("neutral_turtle")
	assert_true(turtle != null)
	if turtle == null:
		return
	assert_true(turtle.keywords.has(CardData.KEYWORD.TAUNT))
	assert_eq(turtle.get_keywords_text(), "嘲讽")


func test_art_path_left_empty() -> void:
	database.reload()
	for card_id: String in database.all_card_ids():
		var card: CardData = database.get_card(card_id)
		assert_eq(card.art_path, "", "按需求美术素材应留空：%s" % card_id)

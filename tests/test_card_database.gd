@tool
extends McpTestSuite
## CSV 卡牌数据加载测试。suite = "cards"。

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


func test_csv_set_loaded() -> void:
	database.reload()
	assert_gt(database.card_count(), 20, "官方 CSV 卡牌应已加载")
	assert_true(database.has_card("pvzh:fireball"))
	assert_eq(database.load_errors.size(), 0, "默认卡牌数据不应有加载错误")


func test_card_fields() -> void:
	database.reload()
	var fireball: CardData = database.get_card("pvzh:fireball")
	assert_true(fireball != null, "火球术应存在")
	if fireball == null:
		return
	assert_eq(fireball.chinese_name, "火球术")
	assert_eq(fireball.display_name(), "火球术")
	assert_eq(fireball.kind, "spell")
	assert_eq(fireball.cost, 4)
	assert_eq(fireball.card_class, "smarty")
	assert_eq(fireball.rarity, "rare")
	assert_eq(fireball.class_label, "聪明")
	assert_eq(fireball.rarity_label, "稀有")
	assert_eq(fireball.ability, "deal_damage(chosen, 6)")


func test_namespacing() -> void:
	database.reload()
	var ids: Array[String] = database.all_card_ids()
	assert_true(ids.size() > 0)
	for card_id: String in ids:
		assert_true(card_id.begins_with("pvzh:"), "官方卡牌应带游戏名前缀：%s" % card_id)
		var card: CardData = database.get_card(card_id)
		assert_eq(card.card_namespace, "pvzh")


func test_keywords_and_tribes_are_valid() -> void:
	database.reload()
	var ids: Array[String] = database.all_card_ids()
	for card_id: String in ids:
		var card: CardData = database.get_card(card_id)
		for keyword_id: String in card.keywords:
			assert_true(CardKeywords.has(keyword_id), "词缀必须在注册表内：%s" % keyword_id)
		for tribe_id: String in card.tribes:
			assert_true(database.config.has_tribe(tribe_id), "流派必须在配置内：%s" % tribe_id)
	var turtle: CardData = database.get_card("pvzh:turtle")
	assert_true(turtle != null)
	if turtle == null:
		return
	assert_true(turtle.has_keyword("taunt"))
	assert_eq(turtle.get_keywords_text(), "嘲讽")
	assert_false(turtle.has_keyword("not_a_keyword"))


func test_entities_and_spells() -> void:
	database.reload()
	var entity: CardData = database.get_card("pvzh:turtle")
	assert_true(entity.is_entity())
	assert_eq(entity.get_type_text(), "实体")
	var spell: CardData = database.get_card("pvzh:fireball")
	assert_false(spell.is_entity())
	assert_eq(spell.get_type_text(), "锦囊")


func test_rarity_economy() -> void:
	database.reload()
	var legend: CardData = database.get_card("pvzh:ancient_dragon")
	assert_true(legend != null)
	if legend != null:
		assert_eq(legend.rarity, "legend")
		assert_eq(legend.max_copies(), 1)
		assert_eq(legend.craft_cost(), 1600)
		assert_eq(legend.disenchant_value(), 400)
	var normal: CardData = database.get_card("pvzh:gnoll")
	assert_true(normal != null)
	if normal != null:
		assert_eq(normal.max_copies(), 2)
		assert_eq(normal.craft_cost(), 40)
		assert_eq(normal.disenchant_value(), 5)


func test_find_by_english() -> void:
	database.reload()
	var card: CardData = database.find_by_english("Fireball")
	assert_true(card != null, "英文名查找应忽略大小写")
	if card != null:
		assert_eq(card.card_id, "pvzh:fireball")

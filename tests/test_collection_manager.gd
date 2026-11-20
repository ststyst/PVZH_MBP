@tool
extends McpTestSuite
## 收藏合成 / 分解规则测试。运行方式：MCP test_run（suite = "collection"）。
## 费用/分解值由稀有度决定：normal 40/5、rare 100/20、super rare 400/100、legend 1600/400。

const CollectionManagerScript := preload("res://scripts/core/collection_manager.gd")

var manager: Node = null


func suite_name() -> String:
	return "collection"


func setup() -> void:
	manager = CollectionManagerScript.new()


func teardown() -> void:
	if is_instance_valid(manager):
		manager.free()
	manager = null


func _make_card(card_id: String, rarity: String) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.english_name = card_id
	card.chinese_name = card_id
	card.rarity = rarity
	return card


func test_craft_and_disenchant_roundtrip() -> void:
	var profile := PlayerProfile.create_default("测试")
	profile.diamond = 100
	var card: CardData = _make_card("c1", "normal")
	var craft_result: Dictionary = manager.craft_card(profile, card)
	assert_true(bool(craft_result.get("ok", false)), "钻石足够时应合成成功")
	assert_eq(profile.diamond, 60)
	assert_eq(profile.get_card_count("c1"), 1)
	var disenchant_result: Dictionary = manager.disenchant_card(profile, card)
	assert_true(bool(disenchant_result.get("ok", false)), "拥有卡牌时应分解成功")
	assert_eq(profile.diamond, 65)
	assert_eq(profile.get_card_count("c1"), 0)


func test_insufficient_diamond() -> void:
	var profile := PlayerProfile.create_default("穷")
	profile.diamond = 10
	var card: CardData = _make_card("c2", "rare")
	assert_false(manager.can_craft(profile, card))
	var result: Dictionary = manager.craft_card(profile, card)
	assert_false(bool(result.get("ok", true)), "钻石不足时合成应失败")
	assert_eq(profile.get_card_count("c2"), 0)
	assert_eq(profile.diamond, 10)


func test_unlimited_collection() -> void:
	var profile := PlayerProfile.create_default("无上限")
	profile.diamond = 10000
	var common: CardData = _make_card("c3", "normal")
	for _index: int in range(5):
		assert_true(bool(manager.craft_card(profile, common).get("ok", false)), "收藏无上限，应能继续合成")
	assert_eq(profile.get_card_count("c3"), 5)
	assert_true(manager.can_craft(profile, common), "收藏取消上限后仍可合成")
	assert_eq(manager.max_copies_for(common), 0, "0 表示不限张数")
	var legend: CardData = _make_card("c4", "legend")
	assert_true(bool(manager.craft_card(profile, legend).get("ok", false)))
	assert_true(bool(manager.craft_card(profile, legend).get("ok", false)))
	assert_eq(profile.get_card_count("c4"), 2)


func test_disenchant_without_copy() -> void:
	var profile := PlayerProfile.create_default("空")
	var card: CardData = _make_card("c5", "normal")
	var result: Dictionary = manager.disenchant_card(profile, card)
	assert_false(bool(result.get("ok", true)), "没有卡牌时分解应失败")
	assert_eq(profile.diamond, 0)


func test_unknown_rarity_has_no_value() -> void:
	var card: CardData = _make_card("c6", "unknown")
	assert_eq(card.craft_cost(), 0)
	assert_eq(card.disenchant_value(), 0)
	assert_eq(card.max_copies(), 2)

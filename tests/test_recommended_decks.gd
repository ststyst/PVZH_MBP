@tool
extends McpTestSuite
## 推荐卡组 CSV 测试。suite = "recommended"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const HeroDatabaseScript := preload("res://scripts/core/hero_database.gd")
const RECOMMENDED_FILE: String = "res://data/battle/recommended_decks.csv"
const HERO_FILE: String = "res://data/cards/official/heroes.csv"

var cards: Node = null
var heroes: Node = null
var recommended: RecommendedDecks = null


func suite_name() -> String:
	return "recommended"


func setup() -> void:
	cards = CardDatabaseScript.new()
	cards.reload(false)
	heroes = HeroDatabaseScript.new()
	heroes.reload_from(HERO_FILE, cards)
	recommended = RecommendedDecks.new()
	recommended.load_file(RECOMMENDED_FILE, cards, heroes)


func teardown() -> void:
	if is_instance_valid(cards):
		cards.free()
	cards = null
	if is_instance_valid(heroes):
		heroes.free()
	heroes = null


func test_recommended_decks_loaded() -> void:
	assert_eq(recommended.load_errors.size(), 0, "推荐卡组不应有错误：%s" % [recommended.load_errors])
	assert_eq(recommended.decks.size(), 4, "应载入 4 套推荐卡组")
	for deck: Dictionary in recommended.decks:
		assert_true(not str(deck.get("deck_name", "")).is_empty())
		assert_true(not str(deck.get("hero_id", "")).is_empty())
		assert_true(int(deck.get("card_ids", []).size()) > 0)


func test_enemy_faction_filter() -> void:
	var p_enemy_options: Array[Dictionary] = recommended.decks_for_enemy("p")
	var z_enemy_options: Array[Dictionary] = recommended.decks_for_enemy("z")
	assert_true(p_enemy_options.size() > 0)
	assert_true(z_enemy_options.size() > 0)
	for deck: Dictionary in p_enemy_options:
		assert_eq(str(deck.get("hero_faction", "")), "z", "玩家 p 时电脑必须是 z")
	for deck: Dictionary in z_enemy_options:
		assert_eq(str(deck.get("hero_faction", "")), "p", "玩家 z 时电脑必须是 p")

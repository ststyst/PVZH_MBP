@tool
extends McpTestSuite
## 牌组规则测试：张数、满编、职业/中立/专属、稀有度张数、可编入标记、default 标签。
## suite = "deck_rules"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const HeroDatabaseScript := preload("res://scripts/core/hero_database.gd")
const HERO_FILE: String = "res://data/cards/official/heroes.csv"

var cards: Node = null
var heroes: Node = null
var mode: GameModeConfig = null


func suite_name() -> String:
	return "deck_rules"


func setup() -> void:
	cards = CardDatabaseScript.new()
	cards.reload(false)
	heroes = HeroDatabaseScript.new()
	heroes.reload_from(HERO_FILE, cards)
	mode = GameModeConfig.default_config()


func teardown() -> void:
	if is_instance_valid(cards):
		cards.free()
	cards = null
	if is_instance_valid(heroes):
		heroes.free()
	heroes = null
	mode = null


func _has_error(errors: Array[String], text: String) -> bool:
	for message: String in errors:
		if message.find(text) != -1:
			return true
	return false


func _empty_deck(hero_id: String = "green_knight") -> DeckData:
	var deck := DeckData.new()
	deck.hero_id = hero_id
	var hero: HeroData = heroes.get_hero(hero_id)
	if hero != null:
		deck.allowed_classes = hero.classes.duplicate()
	return deck


func _fill(deck: DeckData, target: int, active_mode: GameModeConfig) -> void:
	var progress: bool = true
	while deck.card_count() < target and progress:
		progress = false
		for card_id: String in cards.all_card_ids():
			if deck.card_count() >= target:
				break
			var card: CardData = cards.get_card(card_id)
			if DeckRules.can_add_card(deck, card, cards, heroes, active_mode):
				deck.add_card(card_id)
				progress = true


func _inject_card(card_id: String, rarity: String, deck_includable: bool) -> CardData:
	var card := CardData.new()
	card.card_id = card_id
	card.english_name = card_id
	card.chinese_name = card_id
	card.kind = "entity"
	card.cost = 1
	card.attack = 1
	card.health = 1
	card.card_class = "neutral"
	card.rarity = rarity
	card.deck_includable = deck_includable
	cards.cards[card_id] = card
	return card


func test_valid_deck_gets_default_tag() -> void:
	var deck: DeckData = _empty_deck()
	_fill(deck, mode.deck_max_size, mode)
	assert_eq(deck.card_count(), mode.deck_max_size)
	var errors: Array[String] = DeckRules.validate(deck, cards, heroes, mode)
	assert_eq(errors.size(), 0, "合法牌组不应有错误：%s" % [errors])
	DeckRules.refresh_tags(deck, cards, heroes, mode)
	assert_true(deck.has_tag(DeckRules.TAG_DEFAULT), "合法牌组应打上 default 标签")


func test_size_rules() -> void:
	var deck: DeckData = _empty_deck()
	_fill(deck, mode.deck_max_size - 1, mode)
	var errors: Array[String] = DeckRules.validate(deck, cards, heroes, mode)
	assert_true(_has_error(errors, "必须正好"), "未满编应报错：%s" % [errors])

	var overflow_deck: DeckData = _empty_deck()
	_fill(overflow_deck, mode.deck_max_size, mode)
	overflow_deck.add_card(overflow_deck.card_ids[0])
	var overflow_errors: Array[String] = DeckRules.validate(overflow_deck, cards, heroes, mode)
	assert_true(_has_error(overflow_errors, "最多"), "超过上限应报错：%s" % [overflow_errors])

	var soft_mode: GameModeConfig = GameModeConfig.default_config()
	soft_mode.enforce_full_deck = false
	var soft_deck: DeckData = _empty_deck()
	_fill(soft_deck, 30, soft_mode)
	assert_eq(DeckRules.validate(soft_deck, cards, heroes, soft_mode).size(), 0, "允许不满编时应通过")


func test_class_neutral_and_special_cards() -> void:
	var deck: DeckData = _empty_deck()
	var turtle: CardData = cards.get_card("pvzh:turtle")
	var hound: CardData = cards.get_card("pvzh:hound")
	var fireball: CardData = cards.get_card("pvzh:fireball")
	var frostbolt: CardData = cards.get_card("pvzh:frostbolt")
	assert_true(DeckRules.can_add_card(deck, turtle, cards, heroes, mode), "中立职业应无视英雄限制")
	assert_false(DeckRules.can_add_card(deck, hound, cards, heroes, mode), "职业不符不能加入")
	assert_true(DeckRules.can_add_card(deck, fireball, cards, heroes, mode), "英雄专属卡牌应允许")
	assert_false(DeckRules.can_add_card(deck, frostbolt, cards, heroes, mode), "非专属且职业不符不能加入")


func test_copies_by_rarity() -> void:
	assert_eq(DeckRules.max_copies_for(cards.get_card("pvzh:gnoll"), cards, mode), 4, "normal 上限 4")
	assert_eq(DeckRules.max_copies_for(cards.get_card("pvzh:giant"), cards, mode), 4, "rare 上限 4")
	assert_eq(DeckRules.max_copies_for(cards.get_card("pvzh:nova"), cards, mode), 4, "super rare 上限 4")
	assert_eq(DeckRules.max_copies_for(cards.get_card("pvzh:ancient_dragon"), cards, mode), 4, "legend 按数组为 4")
	var unknown_card: CardData = _inject_card("pvzh:test_unknown", "unknown", true)
	assert_eq(DeckRules.max_copies_for(unknown_card, cards, mode), 1, "unknown 上限 1")
	var deck: DeckData = _empty_deck()
	var gnoll: CardData = cards.get_card("pvzh:gnoll")
	for _index: int in range(4):
		assert_true(DeckRules.can_add_card(deck, gnoll, cards, heroes, mode))
		deck.add_card(gnoll.card_id)
	assert_false(DeckRules.can_add_card(deck, gnoll, cards, heroes, mode), "超过张数上限不能再加")


func test_deck_includable_flag() -> void:
	var locked: CardData = _inject_card("pvzh:test_locked", "normal", false)
	var deck: DeckData = _empty_deck()
	assert_false(DeckRules.can_add_card(deck, locked, cards, heroes, mode), "不可编入的卡不能加入")
	var soft_mode: GameModeConfig = GameModeConfig.default_config()
	soft_mode.enforce_full_deck = false
	deck.add_card(locked.card_id)
	var errors: Array[String] = DeckRules.validate(deck, cards, heroes, soft_mode)
	assert_true(_has_error(errors, "不可被编入"), "校验应报告不可编入：%s" % [errors])


func test_default_tag_removed_when_invalid() -> void:
	var deck: DeckData = _empty_deck()
	_fill(deck, mode.deck_max_size, mode)
	DeckRules.refresh_tags(deck, cards, heroes, mode)
	assert_true(deck.has_tag(DeckRules.TAG_DEFAULT))
	deck.remove_card(deck.card_ids[0])
	DeckRules.refresh_tags(deck, cards, heroes, mode)
	assert_false(deck.has_tag(DeckRules.TAG_DEFAULT), "不符合要求时应移除 default 标签")


func test_hero_required() -> void:
	var no_hero: DeckData = _empty_deck()
	no_hero.hero_id = ""
	var errors: Array[String] = DeckRules.validate(no_hero, cards, heroes, mode)
	assert_true(_has_error(errors, "尚未选择英雄"), "未选英雄应报错：%s" % [errors])
	var bad_hero: DeckData = _empty_deck()
	bad_hero.hero_id = "not_a_hero"
	var bad_errors: Array[String] = DeckRules.validate(bad_hero, cards, heroes, mode)
	assert_true(_has_error(bad_errors, "英雄不存在"), "英雄不存在应报错：%s" % [bad_errors])

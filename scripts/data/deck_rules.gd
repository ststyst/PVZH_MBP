class_name DeckRules
extends RefCounted
## 牌组规则：依赖卡牌数据库、英雄数据库与玩法配置。
## - 张数上限 / 是否强制满编：来自 GameModeConfig
## - 单卡张数：按稀有度取 GameModeConfig.max_copies_by_rarity（数组按全局配置稀有度顺序；超出默认 1）
## - 职业限制：卡牌职业必须属于英雄的两个职业；中立职业无视限制；英雄专属卡牌无视限制

const TAG_DEFAULT: String = "default"


## 返回错误列表；空数组表示牌组完全符合当前玩法要求。
static func validate(
	deck: DeckData,
	card_database,
	hero_database,
	mode: GameModeConfig = null,
	profile: PlayerProfile = null,
) -> Array[String]:
	var errors: Array[String] = []
	if deck == null:
		return ["牌组不存在。"]
	if card_database == null:
		return ["卡牌数据库不可用。"]
	if hero_database == null:
		return ["英雄数据库不可用。"]
	var active_mode: GameModeConfig = mode if mode != null else GameModeConfig.default_config()
	var hero: HeroData = hero_database.get_hero(deck.hero_id)
	if deck.hero_id.is_empty():
		errors.append("尚未选择英雄。")
	elif hero == null:
		errors.append("英雄不存在：%s" % deck.hero_id)
	var total: int = deck.card_count()
	if total > active_mode.deck_max_size:
		errors.append("牌组最多 %d 张卡（当前 %d 张）。" % [active_mode.deck_max_size, total])
	elif active_mode.enforce_full_deck and total != active_mode.deck_max_size:
		errors.append("牌组必须正好 %d 张卡才能使用（当前 %d 张）。" % [active_mode.deck_max_size, total])
	var neutral_classes: Array[String] = card_database.get_neutral_classes()
	var counts: Dictionary = deck.get_card_counts()
	for card_id: String in counts.keys():
		var card: CardData = card_database.get_card(card_id)
		if card == null:
			errors.append("卡牌不存在：%s" % card_id)
			continue
		if not card.deck_includable:
			errors.append("卡牌 %s 不可被编入牌组。" % card_id)
			continue
		if profile != null:
			var owned: int = profile.get_card_count(card_id)
			if int(counts[card_id]) > owned:
				errors.append(
					"卡牌 %s 在存档中只有 %d 张，牌组中却有 %d 张。" % [
						card_id, owned, int(counts[card_id])
					]
				)
		if hero != null and not class_allowed(card, hero, neutral_classes):
			errors.append("卡牌 %s 的职业 %s 不在英雄允许范围内。" % [card_id, card.card_class])
		var max_copies: int = max_copies_for(card, card_database, active_mode)
		if int(counts[card_id]) > max_copies:
			errors.append("卡牌 %s 有 %d 张，最多 %d 张。" % [card_id, int(counts[card_id]), max_copies])
	return errors


## 能否再往牌组加入一张该卡（不考虑“是否满编”，只看上限与合法性）。
static func can_add_card(
	deck: DeckData,
	card: CardData,
	card_database,
	hero_database,
	mode: GameModeConfig = null,
	profile: PlayerProfile = null,
) -> bool:
	if deck == null or card == null or card_database == null or hero_database == null:
		return false
	var active_mode: GameModeConfig = mode if mode != null else GameModeConfig.default_config()
	if not card.deck_includable:
		return false
	if deck.card_count() >= active_mode.deck_max_size:
		return false
	if profile != null and deck.count_of(card.card_id) >= profile.get_card_count(card.card_id):
		return false
	var hero: HeroData = hero_database.get_hero(deck.hero_id)
	if hero == null:
		return false
	if not class_allowed(card, hero, card_database.get_neutral_classes()):
		return false
	if deck.count_of(card.card_id) >= max_copies_for(card, card_database, active_mode):
		return false
	return true


static func class_allowed(card: CardData, hero: HeroData, neutral_classes: Array[String]) -> bool:
	if neutral_classes.has(card.card_class):
		return true
	if hero.has_class(card.card_class):
		return true
	if hero.is_special_card(card.card_id):
		return true
	return false


## 该卡在当前玩法下允许的最大张数。
static func max_copies_for(card: CardData, card_database, mode: GameModeConfig) -> int:
	if card == null or card_database == null or mode == null:
		return 1
	var rarities: Array[String] = card_database.get_rarities()
	var index: int = rarities.find(card.rarity)
	return mode.max_copies_for_rarity_index(index)


## 校验并刷新 default 标签；返回错误列表。
static func refresh_tags(
	deck: DeckData,
	card_database,
	hero_database,
	mode: GameModeConfig = null,
	profile: PlayerProfile = null,
) -> Array[String]:
	var errors: Array[String] = validate(deck, card_database, hero_database, mode, profile)
	if deck != null:
		if errors.is_empty():
			deck.add_tag(TAG_DEFAULT)
		else:
			deck.remove_tag(TAG_DEFAULT)
	return errors


## 当前牌组可选择的卡牌列表（供牌组编辑器展示）。
## - 只包含玩家背包中拥有的卡（owned_cards 数量 > 0）且 deck_includable 的卡
## - 牌组已选英雄时：只保留英雄两个职业 + 中立职业 + 英雄专属卡牌（与编入规则一致）
## - 未选英雄时：不按职业过滤，展示全部拥有且可编入的卡
## 每项为 Dictionary：card / card_id / english_name / display_name / owned / in_deck /
##   max_copies / remaining / can_add / is_hero_special
static func selectable_cards(
	profile: PlayerProfile,
	deck: DeckData,
	card_database,
	hero_database,
	mode: GameModeConfig = null,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or deck == null or card_database == null or hero_database == null:
		return result
	var active_mode: GameModeConfig = mode if mode != null else GameModeConfig.default_config()
	var hero: HeroData = hero_database.get_hero(deck.hero_id)
	var neutral_classes: Array[String] = card_database.get_neutral_classes()
	var deck_full: bool = deck.card_count() >= active_mode.deck_max_size
	for card_id: Variant in profile.owned_cards.keys():
		var owned_count: int = profile.get_card_count(str(card_id))
		if owned_count <= 0:
			continue
		var card: CardData = card_database.get_card(str(card_id))
		if card == null or not card.deck_includable:
			continue
		if hero != null and not class_allowed(card, hero, neutral_classes):
			continue
		var in_deck: int = deck.count_of(card.card_id)
		var max_copies: int = max_copies_for(card, card_database, active_mode)
		var effective_limit: int = mini(max_copies, owned_count)
		result.append({
			"card": card,
			"card_id": card.card_id,
			"english_name": card.english_name,
			"display_name": card.display_name(),
			"owned": owned_count,
			"in_deck": in_deck,
			"max_copies": max_copies,
			"remaining": maxi(effective_limit - in_deck, 0),
			"can_add": (not deck_full) and in_deck < effective_limit,
			"is_hero_special": hero != null and hero.is_special_card(card.card_id),
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_card: CardData = first.get("card")
		var second_card: CardData = second.get("card")
		if first_card.cost != second_card.cost:
			return first_card.cost < second_card.cost
		return first_card.display_name() < second_card.display_name()
	)
	return result

class_name DeckData
extends Resource
## 一套牌组。牌组只保存卡牌 ID 列表，不拥有卡牌（同一张卡可编入多个牌组）。
## 张数上限、同名张数上限、职业限制由 DeckRules + 玩法配置校验，不写死在牌组里。

## 参考值（默认玩法上限）；实际以 GameModeConfig.deck_max_size 为准
const DEFAULT_MAX_CARD_COUNT: int = 40
const TAG_DEFAULT: String = "default"

var deck_id: String = ""
var deck_name: String = "新牌组"
var hero_id: String = ""
## 英雄允许职业的快照（实际校验以 HeroDatabase 的英雄数据为准）
var allowed_classes: Array[String] = []
var card_ids: Array[String] = []
## 标签：default = 完全符合默认玩法要求
var tags: Array[String] = []
var updated_at_unix: int = 0


func card_count() -> int:
	return card_ids.size()


func count_of(card_id: String) -> int:
	var total: int = 0
	for existing_id: String in card_ids:
		if existing_id == card_id:
			total += 1
	return total


## card_id -> 张数
func get_card_counts() -> Dictionary:
	var counts: Dictionary = {}
	for card_id: String in card_ids:
		counts[card_id] = int(counts.get(card_id, 0)) + 1
	return counts


func add_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	card_ids.append(card_id)
	_touch()
	return true


func remove_card(card_id: String) -> bool:
	var index: int = card_ids.find(card_id)
	if index == -1:
		return false
	card_ids.remove_at(index)
	_touch()
	return true


func clear_cards() -> void:
	card_ids.clear()
	_touch()


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func add_tag(tag: String) -> void:
	if tag.is_empty() or tags.has(tag):
		return
	tags.append(tag)
	_touch()


func remove_tag(tag: String) -> void:
	var index: int = tags.find(tag)
	if index == -1:
		return
	tags.remove_at(index)
	_touch()


func to_dict() -> Dictionary:
	return {
		"deck_id": deck_id,
		"deck_name": deck_name,
		"hero_id": hero_id,
		"allowed_classes": allowed_classes.duplicate(),
		"card_ids": card_ids.duplicate(),
		"tags": tags.duplicate(),
		"updated_at_unix": updated_at_unix,
	}


static func from_dict(data: Dictionary) -> DeckData:
	var deck := DeckData.new()
	deck.deck_id = str(data.get("deck_id", ""))
	deck.deck_name = str(data.get("deck_name", "新牌组"))
	deck.hero_id = str(data.get("hero_id", ""))
	deck.updated_at_unix = int(data.get("updated_at_unix", 0))
	var raw_classes: Variant = data.get("allowed_classes", [])
	if raw_classes is Array:
		for raw_class: Variant in raw_classes:
			deck.allowed_classes.append(str(raw_class))
	var raw_card_ids: Variant = data.get("card_ids", [])
	if raw_card_ids is Array:
		for raw_card_id: Variant in raw_card_ids:
			deck.card_ids.append(str(raw_card_id))
	var raw_tags: Variant = data.get("tags", [])
	if raw_tags is Array:
		for raw_tag: Variant in raw_tags:
			deck.tags.append(str(raw_tag))
	return deck


func _touch() -> void:
	updated_at_unix = int(Time.get_unix_time_from_system())

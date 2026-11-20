class_name DeckData
extends Resource
## 一套牌组。牌组只保存卡牌 ID 列表，**不拥有**卡牌：
## 同一张卡可以同时编入多个牌组（收藏是全局的，牌组只是引用）。

const MIN_CARD_COUNT: int = 30
const MAX_CARD_COUNT: int = 30
const MAX_SAME_CARD_COUNT: int = 2

var deck_id: String = ""
var deck_name: String = "新牌组"
var hero_id: String = ""
## 这套牌组允许使用的职业（由英雄/规则决定）；中立牌始终允许。
var allowed_classes: Array[String] = []
var card_ids: Array[String] = []
var updated_at_unix: int = 0


func card_count() -> int:
	return card_ids.size()


func count_of(card_id: String) -> int:
	var total: int = 0
	for existing_id: String in card_ids:
		if existing_id == card_id:
			total += 1
	return total


func can_add_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	if card_count() >= MAX_CARD_COUNT:
		return false
	return count_of(card_id) < MAX_SAME_CARD_COUNT


func add_card(card_id: String) -> bool:
	if not can_add_card(card_id):
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


## 返回构成不合法的原因列表；空数组表示合法。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if card_count() < MIN_CARD_COUNT:
		errors.append("牌组只有 %d 张，至少需要 %d 张。" % [card_count(), MIN_CARD_COUNT])
	if card_count() > MAX_CARD_COUNT:
		errors.append("牌组有 %d 张，最多允许 %d 张。" % [card_count(), MAX_CARD_COUNT])
	var seen_counts: Dictionary = {}
	for card_id: String in card_ids:
		seen_counts[card_id] = int(seen_counts.get(card_id, 0)) + 1
	for card_id: String in seen_counts.keys():
		var copies: int = int(seen_counts[card_id])
		if copies > MAX_SAME_CARD_COUNT:
			errors.append("卡牌 %s 有 %d 张，最多 %d 张。" % [card_id, copies, MAX_SAME_CARD_COUNT])
	if hero_id.is_empty():
		errors.append("尚未选择英雄。")
	return errors


func to_dict() -> Dictionary:
	return {
		"deck_id": deck_id,
		"deck_name": deck_name,
		"hero_id": hero_id,
		"allowed_classes": allowed_classes.duplicate(),
		"card_ids": card_ids.duplicate(),
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
		for raw_class in raw_classes:
			deck.allowed_classes.append(str(raw_class))
	var raw_card_ids: Variant = data.get("card_ids", [])
	if raw_card_ids is Array:
		for raw_card_id in raw_card_ids:
			deck.card_ids.append(str(raw_card_id))
	return deck


func _touch() -> void:
	updated_at_unix = int(Time.get_unix_time_from_system())

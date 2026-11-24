class_name BattleCardInstance
extends RefCounted
## 战斗中的一张卡牌实例（同名卡的不同副本拥有独立 instance_id）。
## 牌库/手牌里的攻击、费用修正直接挂在实例上，跟随时移动，打出时转为实体属性。

signal keyword_changed(keyword: String, old_value: int, new_value: int)

var instance_id: int = 0
var card_id: String = ""
var owner_side: String = ""
var zone: String = "deck"
var attack_bonus: int = 0
var health_bonus: int = 0
var shield_bonus: int = 0
var cost_delta: int = 0
## 这张牌实例被额外赋予的词缀（无论是否带数值）
var keywords: Array[String] = []
## 这张牌实例被额外赋予的词缀数值（同名卡的其他副本不受影响）。
var keyword_values: Dictionary = {}


static func create(
	id_value: int,
	card_id_value: String,
	side: String,
	zone_value: String,
) -> BattleCardInstance:
	var instance := BattleCardInstance.new()
	instance.instance_id = id_value
	instance.card_id = card_id_value
	instance.owner_side = side
	instance.zone = zone_value
	return instance


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"owner_side": owner_side,
		"zone": zone,
		"attack_bonus": attack_bonus,
		"health_bonus": health_bonus,
		"shield_bonus": shield_bonus,
		"cost_delta": cost_delta,
		"keywords": keywords.duplicate(),
		"keyword_values": keyword_values.duplicate(true),
	}


static func from_dict(data: Dictionary) -> BattleCardInstance:
	var instance := BattleCardInstance.new()
	instance.instance_id = int(data.get("instance_id", 0))
	instance.card_id = str(data.get("card_id", ""))
	instance.owner_side = str(data.get("owner_side", ""))
	instance.zone = str(data.get("zone", "deck"))
	instance.attack_bonus = int(data.get("attack_bonus", 0))
	instance.health_bonus = int(data.get("health_bonus", 0))
	instance.shield_bonus = int(data.get("shield_bonus", 0))
	instance.cost_delta = int(data.get("cost_delta", 0))
	var raw_owned_keywords: Variant = data.get("keywords", [])
	if raw_owned_keywords is Array:
		for entry: Variant in raw_owned_keywords:
			instance.keywords.append(str(entry))
	var raw_keywords: Variant = data.get("keyword_values", {})
	if raw_keywords is Dictionary:
		for key: Variant in (raw_keywords as Dictionary).keys():
			instance.keyword_values[str(key)] = int((raw_keywords as Dictionary)[key])
	return instance


func has_keyword(keyword: String) -> bool:
	var normalized: String = CardKeywords.normalize(keyword)
	return keywords.has(normalized) or keyword_values.has(normalized)


func grant_keyword(keyword: String, value: int = 0) -> void:
	var normalized: String = CardKeywords.normalize(keyword)
	if normalized.is_empty() or not CardKeywords.has(normalized):
		return
	if not keywords.has(normalized):
		keywords.append(normalized)
	keyword_values[normalized] = value

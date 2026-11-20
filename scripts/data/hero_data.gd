class_name HeroData
extends RefCounted
## 英雄数据（来自 heroes.csv）。英雄不是卡牌，拥有两个职业，并可携带若干专属卡牌。

var hero_id: String = ""
var english_name: String = ""
var chinese_name: String = ""
## 阵营：p 或 z
var faction: String = ""
## 两个职业 id
var classes: Array[String] = []
var class_labels: Array[String] = []
## 专属卡牌（英文名 -> 已解析的内部卡牌 ID）
var special_card_names: Array[String] = []
var special_card_ids: Array[String] = []


func display_name() -> String:
	return chinese_name if not chinese_name.is_empty() else english_name


func is_p() -> bool:
	return faction == "p"


func is_z() -> bool:
	return faction == "z"


func has_class(class_id: String) -> bool:
	return classes.has(class_id)


func is_special_card(card_id: String) -> bool:
	return special_card_ids.has(card_id)

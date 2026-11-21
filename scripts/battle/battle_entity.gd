class_name BattleEntity
extends RefCounted
## 战斗中的一个实体（由实体牌召唤）。

var entity_id: int = 0
var card: CardData = null
var side: String = "p"
var column: int = 0
## 0 = 普通位；1 = 组队位
var slot: int = 0
var attack: int = 0
var health: int = 0
var max_health: int = 0
var shield: int = 0
var keywords: Array[String] = []
var keyword_values: Dictionary = {}
## 内置 Buff/Debuff：buff_id -> 层数（默认 1）
var buffs: Dictionary = {}
var team_up: bool = false
var alive: bool = true
## 克制英雄词缀提供的临时攻击力
var counter_bonus: int = 0


func setup(source_card: CardData, owner_side: String, target_column: int, target_slot: int) -> void:
	card = source_card
	side = owner_side
	column = target_column
	slot = target_slot
	attack = source_card.attack
	health = source_card.health
	max_health = source_card.health
	shield = source_card.shield
	keywords = source_card.keywords.duplicate()
	keyword_values = source_card.keyword_values.duplicate(true)
	team_up = source_card.has_keyword("team_up")


func display_name() -> String:
	return card.display_name() if card != null else "实体"


func has_keyword(keyword: String) -> bool:
	return keywords.has(CardKeywords.normalize(keyword))


func keyword_value(keyword: String) -> int:
	return int(keyword_values.get(CardKeywords.normalize(keyword), 0))


## 赋予/叠加词缀数值；返回是否成功（受卡牌种类白名单限制）。
func add_keyword(keyword: String, value: int = 0) -> bool:
	var normalized: String = CardKeywords.normalize(keyword)
	if normalized.is_empty() or not CardKeywords.has(normalized):
		return false
	var card_kind: String = card.kind if card != null else "entity"
	if not CardKeywords.can_receive(normalized, card_kind):
		return false
	if not keywords.has(normalized):
		keywords.append(normalized)
	if CardKeywords.has_value(normalized):
		keyword_values[normalized] = int(keyword_values.get(normalized, 0)) + value
	return true


func apply_instance_keywords(instance: BattleCardInstance) -> void:
	if instance == null:
		return
	for keyword: Variant in instance.keyword_values.keys():
		add_keyword(str(keyword), int(instance.keyword_values[keyword]))


func is_team_up() -> bool:
	return team_up


func is_alive() -> bool:
	return alive and health > 0


func add_buff(buff_id: String) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	if not CardBuffs.has(normalized):
		return false
	if has_keyword("debuff_immune") and CardBuffs.kind(normalized) == "debuff":
		return false
	buffs[normalized] = int(buffs.get(normalized, 0)) + 1
	return true


func remove_buff(buff_id: String) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	if not buffs.has(normalized):
		return false
	buffs.erase(normalized)
	return true


func has_buff(buff_id: String) -> bool:
	return buffs.has(buff_id.strip_edges().to_lower())


func is_frozen() -> bool:
	return has_buff("frozen")


func is_invincible() -> bool:
	return has_buff("invincible") or has_keyword("invincible")


func is_spell_immune() -> bool:
	return has_buff("spell_immune") or has_keyword("spell_immune") or has_keyword("untrickable")

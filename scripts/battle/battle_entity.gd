class_name BattleEntity
extends RefCounted
## 战斗中的一个实体（由实体牌召唤）。

## 词缀新增或数值变化：keyword, old_value, new_value
signal keyword_changed(keyword: String, old_value: int, new_value: int)

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
## 场上实体的费用始终使用卡牌数据库中的原始费用，不随手牌减费变化
var cost: int = 0
## 入场回合（用于“仅入场当回合”能力）
var entered_turn: int = 0
var keywords: Array[String] = []
var keyword_values: Dictionary = {}
## 内置 Buff/Debuff：buff_id -> 层数（默认 1）
var buffs: Dictionary = {}
## buff_id -> 提供该 Buff 的来源实体 id 数组（用于光环来源追踪）
var buff_sources: Dictionary = {}
## 临时词缀加成：keyword -> 额外数值（不影响原始 keywords/keyword_values）
var temporary_keyword_bonus: Dictionary = {}
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
	cost = maxi(source_card.cost, 0)
	keywords = source_card.keywords.duplicate()
	keyword_values = source_card.keyword_values.duplicate(true)
	team_up = source_card.has_keyword("team_up")


func display_name() -> String:
	return card.display_name() if card != null else "实体"


func has_keyword(keyword: String) -> bool:
	var normalized: String = CardKeywords.normalize(keyword)
	return keywords.has(normalized) or int(temporary_keyword_bonus.get(normalized, 0)) > 0


func keyword_value(keyword: String) -> int:
	return keyword_value_for(keyword)


## 赋予/叠加词缀数值；返回是否成功（受卡牌种类白名单限制）。
func add_keyword(keyword: String, value: int = 0) -> bool:
	var normalized: String = CardKeywords.normalize(keyword)
	if normalized.is_empty() or not CardKeywords.has(normalized):
		return false
	var card_kind: String = card.kind if card != null else "entity"
	if not CardKeywords.can_receive(normalized, card_kind):
		return false
	var old_value: int = keyword_value_for(normalized)
	if not keywords.has(normalized):
		keywords.append(normalized)
	if normalized == "team_up":
		# 组队是放置规则用的缓存字段，赋予词缀后必须同步，否则仍会被当成非组队。
		team_up = true
	if CardKeywords.has_value(normalized):
		keyword_values[normalized] = int(keyword_values.get(normalized, 0)) + value
	var new_value: int = keyword_value_for(normalized)
	if new_value != old_value:
		keyword_changed.emit(normalized, old_value, new_value)
	return true


func keyword_value_for(keyword: String) -> int:
	var normalized: String = CardKeywords.normalize(keyword)
	var base_value: int = 0
	if keywords.has(normalized):
		base_value = int(keyword_values.get(normalized, 0)) if CardKeywords.has_value(normalized) else 1
	return base_value + int(temporary_keyword_bonus.get(normalized, 0))


func set_keyword_value(keyword: String, value: int) -> void:
	var normalized: String = CardKeywords.normalize(keyword)
	if not keywords.has(normalized):
		return
	var old_value: int = keyword_value_for(normalized)
	keyword_values[normalized] = maxi(value, 0)
	var new_value: int = keyword_value_for(normalized)
	if new_value != old_value:
		keyword_changed.emit(normalized, old_value, new_value)


func apply_instance_keywords(instance: BattleCardInstance) -> void:
	if instance == null:
		return
	for keyword: Variant in instance.keywords:
		add_keyword(str(keyword), int(instance.keyword_values.get(str(keyword), 0)))
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
	var temp_keyword: String = CardBuffs.temporary_keyword(normalized)
	if not temp_keyword.is_empty():
		temporary_keyword_bonus[temp_keyword] = int(temporary_keyword_bonus.get(temp_keyword, 0)) + 1
	return true


func remove_buff(buff_id: String) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	if not buffs.has(normalized):
		return false
	var stacks: int = int(buffs.get(normalized, 1))
	if stacks > 1:
		buffs[normalized] = stacks - 1
	else:
		buffs.erase(normalized)
		buff_sources.erase(normalized)
	var temp_keyword: String = CardBuffs.temporary_keyword(normalized)
	if not temp_keyword.is_empty():
		temporary_keyword_bonus[temp_keyword] = maxi(int(temporary_keyword_bonus.get(temp_keyword, 1)) - 1, 0)
		if int(temporary_keyword_bonus[temp_keyword]) <= 0:
			temporary_keyword_bonus.erase(temp_keyword)
	return true


func add_buff_from_source(buff_id: String, source_id: int) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	if not CardBuffs.has(normalized):
		return false
	if has_keyword("debuff_immune") and CardBuffs.kind(normalized) == "debuff":
		return false
	var sources: Array = buff_sources.get(normalized, [])
	if sources.has(source_id):
		return false
	sources.append(source_id)
	buff_sources[normalized] = sources
	buffs[normalized] = int(buffs.get(normalized, 0)) + 1
	var temp_keyword: String = CardBuffs.temporary_keyword(normalized)
	if not temp_keyword.is_empty():
		temporary_keyword_bonus[temp_keyword] = int(temporary_keyword_bonus.get(temp_keyword, 0)) + 1
	return true


func remove_buff_from_source(buff_id: String, source_id: int) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	var sources: Array = buff_sources.get(normalized, [])
	if not sources.has(source_id):
		return false
	sources.erase(source_id)
	if sources.is_empty():
		buff_sources.erase(normalized)
		buffs.erase(normalized)
		var temp_keyword: String = CardBuffs.temporary_keyword(normalized)
		if not temp_keyword.is_empty():
			temporary_keyword_bonus[temp_keyword] = maxi(int(temporary_keyword_bonus.get(temp_keyword, 1)) - 1, 0)
			if int(temporary_keyword_bonus[temp_keyword]) <= 0:
				temporary_keyword_bonus.erase(temp_keyword)
	else:
		buff_sources[normalized] = sources
		buffs[normalized] = maxi(int(buffs.get(normalized, 1)) - 1, 1)
	return true


func has_buff(buff_id: String) -> bool:
	return buffs.has(buff_id.strip_edges().to_lower())


func is_frozen() -> bool:
	return has_buff("frozen")


func is_invincible() -> bool:
	# 词缀本身不参与结算：无敌词缀只在入场时给一层无敌 Buff，免伤完全由 Buff 决定。
	return has_buff("invincible")


func is_spell_immune() -> bool:
	return has_buff("spell_immune") or has_keyword("spell_immune") or has_keyword("untrickable")


func is_buried() -> bool:
	return has_buff("buried")

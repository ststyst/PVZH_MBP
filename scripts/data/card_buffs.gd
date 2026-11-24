class_name CardBuffs
extends RefCounted
## 内置 Buff / Debuff 定义。与词缀不同，Buff 只存在于战场实体上，可被施加/解除。

const DEFINITIONS: Dictionary = {
	"frozen": {
		"label": "冰冻",
		"kind": "debuff",
		"description": "无法进行攻击；战斗回合中该列结算完成后解除。",
		"clear_after_combat": true,
	},
	"invincible": {
		"label": "无敌",
		"kind": "buff",
		"description": "不会受到伤害；仍可被消灭效果选中并正常消灭。战斗回合中该列结算完成后解除。",
		"clear_after_combat": true,
	},
	"spell_immune": {
		"label": "临时锦囊免疫",
		"kind": "buff",
		"description": "不会成为锦囊目标，锦囊效果和伤害无法影响它。",
		"clear_after_combat": false,
	},
	"hatred": {
		"label": "仇恨",
		"kind": "buff",
		"description": "受到实体伤害时，消灭伤害来源。",
		"clear_after_combat": false,
	},
	"life_force": {
		"label": "生命力量",
		"kind": "buff",
		"description": "攻击时使用当前生命值作为伤害数值，而不是攻击力。",
		"clear_after_combat": false,
	},
	"buried": {
		"label": "埋入墓碑",
		"kind": "buff",
		"description": "处于墓碑内；信息与费用对敌方隐匿，Z 方锦囊阶段结束时揭示。",
		"clear_after_combat": false,
	},
	"bounce": {
		"label": "弹回",
		"kind": "debuff",
		"description": "先进行死亡判定；存活则移回手牌，手牌满时放到牌库顶。",
		"clear_after_combat": false,
	},
	"frozen_tombstone": {
		"label": "冻结墓碑",
		"kind": "debuff",
		"description": "墓碑揭示时先获得冻结，再移除该 Debuff。",
		"clear_after_combat": false,
	},
}


static func has(buff_id: String) -> bool:
	var normalized: String = buff_id.strip_edges().to_lower()
	return DEFINITIONS.has(normalized) or _temporary_keyword(normalized) != ""


static func definition(buff_id: String) -> Dictionary:
	var normalized: String = buff_id.strip_edges().to_lower()
	if DEFINITIONS.has(normalized):
		return DEFINITIONS[normalized]
	var keyword: String = _temporary_keyword(normalized)
	if keyword.is_empty():
		return {}
	return {
		"label": "临时%s" % CardKeywords.label(keyword),
		"kind": "buff",
		"description": "临时获得%s词缀，离开来源后移除。" % CardKeywords.label(keyword),
		"keyword": keyword,
		"temporary_keyword": true,
		"clear_after_combat": false,
	}


## buff_id = temp_<keyword>；返回对应词缀，否则空字符串。
static func temporary_keyword(buff_id: String) -> String:
	return _temporary_keyword(buff_id.strip_edges().to_lower())


static func _temporary_keyword(normalized: String) -> String:
	if not normalized.begins_with("temp_"):
		return ""
	var keyword: String = normalized.substr(5)
	return keyword if CardKeywords.has(keyword) else ""


static func kind(buff_id: String) -> String:
	return str(definition(buff_id).get("kind", ""))


static func label(buff_id: String) -> String:
	return str(definition(buff_id).get("label", buff_id))


static func description(buff_id: String) -> String:
	return str(definition(buff_id).get("description", ""))


static func clear_after_combat(buff_id: String) -> bool:
	return bool(definition(buff_id).get("clear_after_combat", false))


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for buff_id: Variant in DEFINITIONS.keys():
		result.append(str(buff_id))
	for keyword: Variant in CardKeywords.DEFINITIONS.keys():
		result.append("temp_%s" % str(keyword))
	result.sort()
	return result

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
		"description": "不会受到伤害，也不会被直接消灭；战斗回合中该列结算完成后解除。",
		"clear_after_combat": true,
	},
	"spell_immune": {
		"label": "临时锦囊免疫",
		"kind": "buff",
		"description": "不会成为锦囊目标，锦囊效果和伤害无法影响它。",
		"clear_after_combat": false,
	},
}


static func has(buff_id: String) -> bool:
	return DEFINITIONS.has(buff_id.strip_edges().to_lower())


static func definition(buff_id: String) -> Dictionary:
	return DEFINITIONS.get(buff_id.strip_edges().to_lower(), {})


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
	result.sort()
	return result

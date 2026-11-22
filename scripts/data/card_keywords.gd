class_name CardKeywords
extends RefCounted
## 词缀（关键词）注册表：由游戏内代码决定有哪些词缀。
## CSV 中出现的未知词缀会被忽略（并记录加载警告），不会让整张卡失效。

const DEFINITIONS: Dictionary = {
	"first_strike": {
		"label": "先攻",
		"description": "攻击时先对敌方英雄造成对应数值的伤害，再执行正常攻击。",
		"value": true,
		"allowed_kinds": ["entity"],
	},
	"charge": {
		"label": "冲锋",
		"description": "打出后召唤的实体可以立刻发起一次攻击。",
	},
	"taunt": {
		"label": "嘲讽",
		"description": "敌方必须先攻击它，才能攻击其他目标。",
	},
	"deadly": {
		"label": "致命",
		"description": "伤害类型增加致命；命中没有无敌的实体时直接消灭。",
		"allowed_kinds": ["entity"],
	},
	"armored": {
		"label": "护甲",
		"description": "受到的伤害减少 1 点。",
	},
	"strikethrough": {
		"label": "穿透",
		"description": "攻击时对其所在列的所有敌方实体以及敌方英雄造成伤害。",
		"allowed_kinds": ["entity"],
	},
	"bullseye": {
		"label": "必中",
		"description": "持有该词缀的实体造成的伤害类型增加必中；必中伤害不会增加充能护盾充能。",
		"allowed_kinds": ["entity"],
	},
	"double_strike": {
		"label": "双重打击",
		"description": "战斗回合中会攻击两次；第一次攻击与效果、死亡结算完成后仍存活才攻击第二次。",
		"allowed_kinds": ["entity"],
	},
	"overshoot": {
		"label": "溅射",
		"description": "攻击时同时对其所在列相邻两列上的所有实体造成对应数值的伤害。",
		"value": true,
		"allowed_kinds": ["entity"],
	},
	"frenzy": {
		"label": "狂热",
		"description": "攻击击杀被命中的敌方实体后，再攻击一次。",
		"allowed_kinds": ["entity"],
	},
	"untrickable": {
		"label": "免疫锦囊",
		"description": "不能被锦囊牌指定。",
		"allowed_kinds": ["entity"],
	},
	"spell_immune": {
		"label": "锦囊免疫",
		"description": "不会成为锦囊目标，锦囊效果和伤害无法影响它。",
		"allowed_kinds": ["entity"],
	},
	"hero_counter": {
		"label": "克制英雄",
		"description": "所在列没有敌方实体时，攻击力获得对应数值的临时加成；有敌方实体时移除。",
		"value": true,
		"allowed_kinds": ["entity"],
	},
	"invincible": {
		"label": "无敌",
		"description": "入场时获得无敌 Buff。",
		"allowed_kinds": ["entity"],
	},
	"hunt": {
		"label": "捕猎",
		"description": "敌方实体入场时，尝试移动到该实体所在列。",
		"allowed_kinds": ["entity"],
	},
	"amphibious": {
		"label": "两栖",
		"description": "可以在水池等要求两栖的环境位置打出或移动。",
		"allowed_kinds": ["entity"],
	},
	"debuff_immune": {
		"label": "免疫负面",
		"description": "不会获得 Debuff。",
		"allowed_kinds": ["entity"],
	},
	"tombstone": {
		"label": "墓碑",
		"description": "入场时埋入墓碑；Z 方锦囊阶段结束时按列揭示并结算入场。",
		"allowed_kinds": ["entity"],
	},
	"invisible": {
		"label": "隐形",
		"description": "数值大于 0 时免疫不带必中的伤害；仍可被消灭/移除；回合结束数值 -1。",
		"value": true,
		"allowed_kinds": ["entity"],
	},
	"triple_strike": {
		"label": "三连打",
		"description": "攻击时依次攻击左侧列、自身列、右侧列；不合法列跳过。",
		"allowed_kinds": ["entity"],
	},
	"frost": {
		"label": "寒霜",
		"description": "伤害类型增加冰冻攻击；被命中的实体获得冰冻 Debuff。",
		"allowed_kinds": ["entity"],
	},
	"thorns": {
		"label": "反伤",
		"description": "受到实体攻击时，对攻击来源造成对应数值的伤害。",
		"value": true,
		"allowed_kinds": ["entity"],
	},
	"team_up": {
		"label": "组队",
		"description": "可与已有友方实体同列；打出时可挤开原实体放入已有格子。",
	},
}


## 规范化词缀写法：去空格、转小写、空格换下划线（"Double Strike" -> "double_strike"）。
static func normalize(keyword: String) -> String:
	return keyword.strip_edges().to_lower().replace(" ", "_")


static func has(keyword: String) -> bool:
	return DEFINITIONS.has(normalize(keyword))


static func label(keyword: String) -> String:
	var definition: Dictionary = DEFINITIONS.get(normalize(keyword), {})
	return str(definition.get("label", keyword))


static func description(keyword: String) -> String:
	var definition: Dictionary = DEFINITIONS.get(normalize(keyword), {})
	return str(definition.get("description", ""))


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for keyword_id: Variant in DEFINITIONS.keys():
		ids.append(str(keyword_id))
	ids.sort()
	return ids


## 该词缀是否带数值（如 first_strike:2）。
static func has_value(keyword: String) -> bool:
	var definition: Dictionary = DEFINITIONS.get(normalize(keyword), {})
	return bool(definition.get("value", false))


## 卡牌种类白名单：未声明 allowed_kinds 视为所有种类可用。
static func can_receive(keyword: String, card_kind: String) -> bool:
	var definition: Dictionary = DEFINITIONS.get(normalize(keyword), {})
	if definition.is_empty():
		return false
	var allowed: Variant = definition.get("allowed_kinds", null)
	if allowed is Array:
		return (allowed as Array).has(card_kind)
	return true


## 带数值词缀的显示文本：先攻 2；无数值词缀只显示名字。
static func label_with_value(keyword: String, value: int) -> String:
	var base_label: String = label(keyword)
	if has_value(keyword):
		return "%s %d" % [base_label, value]
	return base_label

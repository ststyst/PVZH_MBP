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
		"label": "剧毒",
		"description": "对随从造成伤害时直接消灭它。",
	},
	"armored": {
		"label": "护甲",
		"description": "受到的伤害减少 1 点。",
	},
	"strikethrough": {
		"label": "穿透",
		"description": "攻击随从时，同时命中敌方英雄。",
	},
	"bullseye": {
		"label": "必中",
		"description": "该实体或法术造成的伤害类型为必中；必中伤害不会增加充能护盾充能。",
	},
	"double_strike": {
		"label": "双击",
		"description": "每次攻击会打两下。",
	},
	"overshoot": {
		"label": "溅射",
		"description": "攻击时对相邻目标造成溅射伤害。",
	},
	"frenzy": {
		"label": "狂怒",
		"description": "受到伤害后攻击力提升。",
	},
	"untrickable": {
		"label": "免疫锦囊",
		"description": "不能被锦囊牌指定。",
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

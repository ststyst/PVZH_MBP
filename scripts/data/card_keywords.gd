class_name CardKeywords
extends RefCounted
## 词缀（关键词）注册表：由游戏内代码决定有哪些词缀。
## CSV 中出现的未知词缀会被忽略（并记录加载警告），不会让整张卡失效。

const DEFINITIONS: Dictionary = {
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
		"description": "攻击不会被闪避。",
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
		"description": "只能放在同列的“组队位”；点击可与同列、同阵营的另一个实体交换位置。",
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

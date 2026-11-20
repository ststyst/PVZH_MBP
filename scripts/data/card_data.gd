class_name CardData
extends Resource
## 一张卡牌的静态定义（由 CSV 载入，数据驱动）。
## 内部唯一标识 card_id 带命名空间前缀：官方 "pvzh:<英文名>"，模组 "<作者.模组>:<英文名>"。
## 具体能力写在 ability 字段（伪代码），由战斗层解释执行。

const RARITY_CRAFT_COST: Dictionary = {
	"normal": 40,
	"rare": 100,
	"super rare": 400,
	"legend": 1600,
}
const RARITY_DISENCHANT_VALUE: Dictionary = {
	"normal": 5,
	"rare": 20,
	"super rare": 100,
	"legend": 400,
}

var card_id: String = ""
var card_namespace: String = ""
var english_name: String = ""

var chinese_name: String = ""
var description: String = ""

## 卡牌种类："entity"（打出后召唤实体）或 "spell"（锦囊牌）
var kind: String = ""

var cost: int = 0
var attack: int = 0
var health: int = 0
var shield: int = 0

var card_class: String = ""
var rarity: String = ""

## 已通过校验的词缀 id（未知词缀在加载时被忽略）
var keywords: Array[String] = []
## 已通过校验的流派 id
var tribes: Array[String] = []

## 伪代码形式的具体能力（由解释器执行）
var ability: String = ""
## 编译后的能力脚本（CSV 载入时解析；语法错误见 CardDatabase.load_errors）
var ability_script: CardEffectScript = null

## 展示用中文名（加载时由全局配置解析）
var class_label: String = ""
var rarity_label: String = ""
var keyword_labels: Array[String] = []
var tribe_labels: Array[String] = []


func display_name() -> String:
	return chinese_name if not chinese_name.is_empty() else english_name


func is_entity() -> bool:
	return kind == "entity"


func get_type_text() -> String:
	return "实体" if is_entity() else "锦囊"


func get_class_text() -> String:
	return class_label


func get_rarity_text() -> String:
	return rarity_label


func get_keywords_text() -> String:
	return "、".join(keyword_labels)


func get_tribes_text() -> String:
	return "、".join(tribe_labels)


func has_keyword(keyword: String) -> bool:
	return keywords.has(CardKeywords.normalize(keyword))


## 是否写有可执行的能力（非空且编译无语法错误）。
func has_ability() -> bool:
	return ability_script != null and ability_script.has_effect() and not ability_script.has_errors()


## 该稀有度允许持有的最大张数：传说 1 张，其余 2 张。
func max_copies() -> int:
	if rarity == "legend":
		return 1
	return 2


## 合成花费（钻石）；未知稀有度为 0。
func craft_cost() -> int:
	return int(RARITY_CRAFT_COST.get(rarity, 0))


## 分解获得（钻石）；未知稀有度为 0。
func disenchant_value() -> int:
	return int(RARITY_DISENCHANT_VALUE.get(rarity, 0))

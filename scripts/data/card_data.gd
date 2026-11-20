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

## 是否可被牌组编入（CSV 列 deck_includable：0 不可、1 可；省略视为 1）
var deck_includable: bool = true

## 伪代码形式的具体能力（由解释器执行）
var ability: String = ""
## 卡面贴图路径（res:// 或 user://）；空 = 纯色占位外观
var art_path: String = ""
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


func is_spell() -> bool:
	return kind == "spell"


func is_environment() -> bool:
	return kind == "environment"


func get_type_text() -> String:
	match kind:
		"entity":
			return "实体"
		"spell":
			return "锦囊"
		"environment":
			return "环境"
		_:
			return "未知"


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


## 是否可以被牌组编入（牌组规则使用）。
func is_deck_includable() -> bool:
	return deck_includable


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


## 序列化为编译包中的卡牌条目（含已编译的能力程序）。
func to_pack_dict() -> Dictionary:
	var program: Dictionary = {}
	var ability_errors: Array = []
	if ability_script != null:
		program = ability_script.to_program()
		ability_errors = ability_script.errors.duplicate()
	return {
		"card_id": card_id,
		"english_name": english_name,
		"chinese_name": chinese_name,
		"description": description,
		"kind": kind,
		"cost": cost,
		"attack": attack,
		"health": health,
		"shield": shield,
		"card_class": card_class,
		"rarity": rarity,
		"keywords": keywords.duplicate(),
		"tribes": tribes.duplicate(),
		"ability": ability,
		"art_path": art_path,
		"class_label": class_label,
		"rarity_label": rarity_label,
		"keyword_labels": keyword_labels.duplicate(),
		"tribe_labels": tribe_labels.duplicate(),
		"ability_program": program,
		"ability_errors": ability_errors,
		"deck_includable": deck_includable,
	}


## 从编译包条目恢复卡牌（跳过解析）。
static func from_pack_dict(data: Dictionary, card_namespace: String = "") -> CardData:
	var card := CardData.new()
	card.card_id = str(data.get("card_id", ""))
	card.card_namespace = card_namespace if not card_namespace.is_empty() else str(data.get("card_namespace", ""))
	card.english_name = str(data.get("english_name", ""))
	card.chinese_name = str(data.get("chinese_name", ""))
	card.description = str(data.get("description", ""))
	card.kind = str(data.get("kind", "spell"))
	card.cost = int(data.get("cost", 0))
	card.attack = int(data.get("attack", 0))
	card.health = int(data.get("health", 0))
	card.shield = int(data.get("shield", 0))
	card.card_class = str(data.get("card_class", "neutral"))
	card.rarity = str(data.get("rarity", "unknown"))
	card.deck_includable = bool(data.get("deck_includable", true))
	card.ability = str(data.get("ability", ""))
	card.art_path = str(data.get("art_path", ""))
	card.class_label = str(data.get("class_label", ""))
	card.rarity_label = str(data.get("rarity_label", ""))
	var raw_keywords: Variant = data.get("keywords", [])
	if raw_keywords is Array:
		for entry: Variant in raw_keywords:
			card.keywords.append(str(entry))
	var raw_tribes: Variant = data.get("tribes", [])
	if raw_tribes is Array:
		for entry: Variant in raw_tribes:
			card.tribes.append(str(entry))
	var raw_keyword_labels: Variant = data.get("keyword_labels", [])
	if raw_keyword_labels is Array:
		for entry: Variant in raw_keyword_labels:
			card.keyword_labels.append(str(entry))
	var raw_tribe_labels: Variant = data.get("tribe_labels", [])
	if raw_tribe_labels is Array:
		for entry: Variant in raw_tribe_labels:
			card.tribe_labels.append(str(entry))
	var program: Variant = data.get("ability_program", {})
	var parse_errors: Variant = data.get("ability_errors", [])
	card.ability_script = CardEffectScript.from_program(
		program if program is Dictionary else {},
		parse_errors if parse_errors is Array else [],
	)
	return card

class_name CardData
extends Resource
## 单张卡牌的**静态定义**（数据驱动，来自 res://data/cards/*.json）。
## 战斗中的运行时状态（当前血量、是否已攻击等）由战斗层持有，不放这里。

enum CARD_TYPE { MINION, SPELL, WEAPON, HERO_POWER, LOCATION }
enum RARITY { FREE, COMMON, RARE, EPIC, LEGENDARY }
enum CARD_CLASS { NEUTRAL, WARRIOR, MAGE, HUNTER, PRIEST, ROGUE, DRUID, PALADIN, SHAMAN, WARLOCK }
enum KEYWORD {
	TAUNT,
	CHARGE,
	RUSH,
	DIVINE_SHIELD,
	LIFESTEAL,
	POISONOUS,
	WINDFURY,
	SPELL_DAMAGE,
	BATTLE_CRY,
	DEATH_RATTLE,
}

var card_id: String = ""
var display_name: String = ""
var description: String = ""
var card_type: CARD_TYPE = CARD_TYPE.MINION
var rarity: RARITY = RARITY.COMMON
var card_class: CARD_CLASS = CARD_CLASS.NEUTRAL
var cost: int = 0
var attack: int = 0
var health: int = 0
var keywords: Array[int] = []
var art_path: String = ""
var craft_cost: int = 0
var disenchant_value: int = 0


## 从 JSON/字典构造卡牌。缺失字段使用安全默认值，非法枚举回退到 fallback。
static func from_dict(data: Dictionary) -> CardData:
	var card := CardData.new()
	card.card_id = str(data.get("card_id", ""))
	card.display_name = str(data.get("display_name", card.card_id))
	card.description = str(data.get("description", ""))
	card.card_type = _parse_enum(CARD_TYPE, data.get("card_type", "MINION"), CARD_TYPE.MINION)
	card.rarity = _parse_enum(RARITY, data.get("rarity", "COMMON"), RARITY.COMMON)
	card.card_class = _parse_enum(CARD_CLASS, data.get("card_class", "NEUTRAL"), CARD_CLASS.NEUTRAL)
	card.cost = int(data.get("cost", 0))
	card.attack = int(data.get("attack", 0))
	card.health = int(data.get("health", 0))
	card.art_path = str(data.get("art_path", ""))
	card.craft_cost = int(data.get("craft_cost", 0))
	card.disenchant_value = int(data.get("disenchant_value", 0))
	var raw_keywords: Variant = data.get("keywords", [])
	if raw_keywords is Array:
		for raw_keyword in raw_keywords:
			var keyword_id: int = _parse_enum(KEYWORD, raw_keyword, -1)
			if keyword_id >= 0 and not card.keywords.has(keyword_id):
				card.keywords.append(keyword_id)
	return card


static func _parse_enum(enum_map: Dictionary, raw_value: Variant, fallback: int) -> int:
	if raw_value is int:
		return int(raw_value)
	if raw_value is String:
		var key: String = String(raw_value).to_upper()
		if enum_map.has(key):
			return int(enum_map[key])
	return fallback

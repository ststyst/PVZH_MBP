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
var team_up: bool = false
var alive: bool = true


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
	team_up = source_card.has_keyword("team_up")


func display_name() -> String:
	return card.display_name() if card != null else "实体"


func has_keyword(keyword: String) -> bool:
	return keywords.has(CardKeywords.normalize(keyword))


func is_team_up() -> bool:
	return team_up


func is_alive() -> bool:
	return alive and health > 0

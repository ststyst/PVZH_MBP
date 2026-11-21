class_name ZoneCardEffectContext
extends BattleEffectContext
## 牌库/手牌中卡牌的区域被动上下文。
## 只支持修改自身卡牌实例（gain_attack / reduce_cost）以及标志物等通用操作；
## zone 供 when ally_die(zone == 'deck'/'hand') 过滤使用。

var zone_name: String = "hand"
var card_modifier: Dictionary = {}


func _init(engine_ref: BattleEngine, side: String, zone: String, modifier: Dictionary) -> void:
	super(engine_ref, side)
	zone_name = zone
	card_modifier = modifier


func get_zone() -> String:
	return zone_name


func gain_attack(amount: int) -> void:
	card_modifier["attack"] = int(card_modifier.get("attack", 0)) + amount


func reduce_cost(amount: int) -> void:
	card_modifier["cost"] = int(card_modifier.get("cost", 0)) - amount

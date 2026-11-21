class_name BattleCardInstance
extends RefCounted
## 战斗中的一张卡牌实例（同名卡的不同副本拥有独立 instance_id）。
## 牌库/手牌里的攻击、费用修正直接挂在实例上，跟随时移动，打出时转为实体属性。

var instance_id: int = 0
var card_id: String = ""
var owner_side: String = ""
var zone: String = "deck"
var attack_bonus: int = 0
var cost_delta: int = 0


static func create(
	id_value: int,
	card_id_value: String,
	side: String,
	zone_value: String,
) -> BattleCardInstance:
	var instance := BattleCardInstance.new()
	instance.instance_id = id_value
	instance.card_id = card_id_value
	instance.owner_side = side
	instance.zone = zone_value
	return instance


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"owner_side": owner_side,
		"zone": zone,
		"attack_bonus": attack_bonus,
		"cost_delta": cost_delta,
	}


static func from_dict(data: Dictionary) -> BattleCardInstance:
	var instance := BattleCardInstance.new()
	instance.instance_id = int(data.get("instance_id", 0))
	instance.card_id = str(data.get("card_id", ""))
	instance.owner_side = str(data.get("owner_side", ""))
	instance.zone = str(data.get("zone", "deck"))
	instance.attack_bonus = int(data.get("attack_bonus", 0))
	instance.cost_delta = int(data.get("cost_delta", 0))
	return instance

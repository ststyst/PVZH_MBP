class_name BattlePlayerState
extends RefCounted
## 一方的战斗状态：英雄、生命、费用、手牌、牌库、特殊标志物。

var side: String = "p"
var hero: HeroData = null
var hero_max_health: int = 20
var hero_health: int = 20
## 英雄护盾：先吸收伤害，再扣生命。
var hero_shield: int = 0
## 英雄伤害免疫（预留；为 true 时不受到任何伤害）。
var hero_damage_immune: bool = false
## 充能护盾当前充能 / 耐久 / 致命保护剩余次数
var charge_shield: int = 0
var charge_shield_durability: int = 3
var charge_shield_emergency_uses: int = 1
## 墓碑打出时对敌方隐藏的费用支出（仅网络可见性使用）
var hidden_energy_spent: int = 0
## 本局该英雄的超能力牌池（尚未发放的卡牌 ID）
var superpower_pool: Array[String] = []
## 当前特殊回合提供给该玩家的超能力牌实例 ID（0 表示无）
var special_offer_id: int = 0
## 特殊回合选择：空 / "play" / "hand"
var special_choice: String = ""
var energy: int = 0
var energy_cap: int = 99
## 本回合累计实际获得的费用（含回合开始发放 + 本回合卡牌能力获取），每回合开始清零。
var energy_gained_this_turn: int = 0
var hand: Array[BattleCardInstance] = []
var deck: Array[BattleCardInstance] = []
var discard: Array[BattleCardInstance] = []
## 玩家特殊标志物：名字 -> 数量（允许负数，不注册种类）
var markers: Dictionary = {}


func hand_count() -> int:
	return hand.size()


func deck_count() -> int:
	return deck.size()


func hero_alive() -> bool:
	return hero_health > 0


func add_to_hand(instance: BattleCardInstance) -> void:
	instance.zone = "hand"
	instance.owner_side = side
	hand.append(instance)


func add_to_deck(instance: BattleCardInstance) -> void:
	instance.zone = "deck"
	instance.owner_side = side
	deck.append(instance)


func take_hand_at(index: int) -> BattleCardInstance:
	if index < 0 or index >= hand.size():
		return null
	return hand.pop_at(index)


func take_top_deck() -> BattleCardInstance:
	if deck.is_empty():
		return null
	return deck.pop_back()


func find_hand_index(instance_id: int) -> int:
	for index: int in range(hand.size()):
		if hand[index].instance_id == instance_id:
			return index
	return -1


func hand_ids() -> Array[String]:
	var result: Array[String] = []
	for instance: BattleCardInstance in hand:
		result.append(instance.card_id)
	return result


func deck_ids() -> Array[String]:
	var result: Array[String] = []
	for instance: BattleCardInstance in deck:
		result.append(instance.card_id)
	return result


func add_marker(marker_name: String, amount: int) -> void:
	if marker_name.is_empty():
		return
	markers[marker_name] = int(markers.get(marker_name, 0)) + amount


func marker_count(marker_name: String) -> int:
	return int(markers.get(marker_name, 0))

class_name BattlePlayerState
extends RefCounted
## 一方的战斗状态：英雄、生命、费用、手牌、牌库。

var side: String = "p"
var hero: HeroData = null
var hero_max_health: int = 20
var hero_health: int = 20
var energy: int = 0
var energy_cap: int = 99
var hand: Array[String] = []
var deck: Array[String] = []
var discard: Array[String] = []
## 与 hand/deck 一一对应的卡牌实例修正：{ "attack": int, "cost": int }
var hand_modifiers: Array[Dictionary] = []
var deck_modifiers: Array[Dictionary] = []
## 玩家特殊标志物：名字 -> 数量（允许负数，不注册种类）
var markers: Dictionary = {}


func hand_modifier(index: int) -> Dictionary:
	if index < 0 or index >= hand.size():
		return {}
	while hand_modifiers.size() <= index:
		hand_modifiers.append({})
	return hand_modifiers[index]


func deck_modifier(index: int) -> Dictionary:
	if index < 0 or index >= deck.size():
		return {}
	while deck_modifiers.size() <= index:
		deck_modifiers.append({})
	return deck_modifiers[index]


func take_hand_modifier(index: int) -> Dictionary:
	var modifier: Dictionary = hand_modifier(index)
	if index >= 0 and index < hand_modifiers.size():
		hand_modifiers.remove_at(index)
	return modifier


func take_deck_modifier(index: int) -> Dictionary:
	var modifier: Dictionary = deck_modifier(index)
	if index >= 0 and index < deck_modifiers.size():
		deck_modifiers.remove_at(index)
	return modifier


func add_to_hand(card_id: String, modifier: Dictionary = {}) -> void:
	hand.append(card_id)
	while hand_modifiers.size() < hand.size() - 1:
		hand_modifiers.append({})
	hand_modifiers.append(modifier.duplicate(true))


func add_to_deck(card_id: String, modifier: Dictionary = {}) -> void:
	deck.append(card_id)
	while deck_modifiers.size() < deck.size() - 1:
		deck_modifiers.append({})
	deck_modifiers.append(modifier.duplicate(true))


func add_marker(marker_name: String, amount: int) -> void:
	if marker_name.is_empty():
		return
	markers[marker_name] = int(markers.get(marker_name, 0)) + amount


func marker_count(marker_name: String) -> int:
	return int(markers.get(marker_name, 0))


func hand_count() -> int:
	return hand.size()


func deck_count() -> int:
	return deck.size()


func hero_alive() -> bool:
	return hero_health > 0

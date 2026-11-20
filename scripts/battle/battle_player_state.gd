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


func hand_count() -> int:
	return hand.size()


func deck_count() -> int:
	return deck.size()


func hero_alive() -> bool:
	return hero_health > 0

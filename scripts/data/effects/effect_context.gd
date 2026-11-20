class_name EffectContext
extends RefCounted
## 卡牌效果执行上下文（抽象操作层）。
##
## 设计目的：卡牌 CSV 的“特殊能力”列写伪代码，解释器只调用这里定义的原语；
## 真正的战斗逻辑（场上单位、手牌、英雄、目标选择）由战斗层实现本类后传入。
## 目标统一用字符串选择器表示：self / chosen / chosen_enemy / hero / enemy_hero /
##   all_enemies / random_enemy / all_allies / random_ally。
## 这样伪代码与战斗实现解耦，未来模组卡牌也能复用同一套原语。

## 召唤（打出实体牌）或生成指定英文名的实体，返回生成的实体句柄列表。
func summon(_card_name: String, _count: int = 1) -> Array:
	push_warning("EffectContext.summon 未实现：需要战斗层提供")
	return []


## 抽牌，返回实际抽到的张数。
func draw_cards(_count: int) -> int:
	push_warning("EffectContext.draw_cards 未实现：需要战斗层提供")
	return 0


func deal_damage(_target: String, _amount: int) -> void:
	push_warning("EffectContext.deal_damage 未实现：需要战斗层提供")


func heal(_target: String, _amount: int) -> void:
	push_warning("EffectContext.heal 未实现：需要战斗层提供")


func gain_shield(_target: String, _amount: int) -> void:
	push_warning("EffectContext.gain_shield 未实现：需要战斗层提供")


func buff_stats(_target: String, _attack_delta: int, _health_delta: int) -> void:
	push_warning("EffectContext.buff_stats 未实现：需要战斗层提供")


func gain_energy(_amount: int) -> void:
	push_warning("EffectContext.gain_energy 未实现：需要战斗层提供")


func give_keyword(_target: String, _keyword: String) -> void:
	push_warning("EffectContext.give_keyword 未实现：需要战斗层提供")


func destroy(_target: String) -> void:
	push_warning("EffectContext.destroy 未实现：需要战斗层提供")


## 查询目标的护甲值（供“造成等同于护甲值的伤害”这类效果使用）。
func get_shield(_target: String) -> int:
	return 0


## 查询目标的攻击力（供条件判断使用）。
func get_attack(_target: String) -> int:
	return 0


## 查询目标的生命值（供条件判断使用）。
func get_health(_target: String) -> int:
	return 0

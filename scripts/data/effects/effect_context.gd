class_name EffectContext
extends RefCounted
## 卡牌效果执行上下文（抽象操作层）。
##
## 设计目的：CSV 的 ability 列（伪代码）由 EffectRunner 解释，只调用这里定义的原语；
## 真正的战斗逻辑（场上实体、手牌、英雄、目标选择）由战斗层实现本类后传入。
##
## 目标/实体用“句柄”（Variant，可为字符串/对象）表示：
## - 选择器：self（技能拥有者）/ event（触发事件的实体）/ chosen（玩家选中的目标）/
##   hero / enemy_hero / all_enemies / random_enemy / all_allies / random_ally
## - resolve_selector() 返回句柄数组；多目标原语由 EffectRunner 逐个调用。
## - describe_entity() 返回 { side, class, tribes, attack, health, shield }，供事件过滤与条件目标使用。
##   其中 side 对技能拥有者返回 "self"，友方 "ally"，敌方 "enemy"。

## 战斗层在设置好 self / event 句柄后再执行脚本。
func set_self_target(_handle) -> void:
	pass


func set_event_target(_handle) -> void:
	pass


## 解析选择器，返回实体句柄数组（空数组表示没有目标）。
func resolve_selector(_selector: String) -> Array:
	push_warning("EffectContext.resolve_selector 未实现：需要战斗层提供")
	return []


## 返回实体事实（side/class/tribes/attack/health/shield），供条件判断。
func describe_entity(_handle) -> Dictionary:
	push_warning("EffectContext.describe_entity 未实现：需要战斗层提供")
	return {}


# ----- 原语（以单个实体句柄为参数） -----

func summon(_card_name: String, _count: int = 1) -> Array:
	push_warning("EffectContext.summon 未实现：需要战斗层提供")
	return []


func draw_cards(_count: int) -> int:
	push_warning("EffectContext.draw_cards 未实现：需要战斗层提供")
	return 0


func deal_damage(_target, _amount: int) -> void:
	push_warning("EffectContext.deal_damage 未实现：需要战斗层提供")


func heal(_target, _amount: int) -> void:
	push_warning("EffectContext.heal 未实现：需要战斗层提供")


func gain_shield(_target, _amount: int) -> void:
	push_warning("EffectContext.gain_shield 未实现：需要战斗层提供")


func buff_stats(_target, _attack_delta: int, _health_delta: int) -> void:
	push_warning("EffectContext.buff_stats 未实现：需要战斗层提供")


func gain_energy(_amount: int) -> void:
	push_warning("EffectContext.gain_energy 未实现：需要战斗层提供")


func give_keyword(_target, _keyword: String) -> void:
	push_warning("EffectContext.give_keyword 未实现：需要战斗层提供")


func destroy(_target) -> void:
	push_warning("EffectContext.destroy 未实现：需要战斗层提供")

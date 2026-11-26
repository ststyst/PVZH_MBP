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


## 玩家/UI 选择的目标列表（支持多选；旧接口 set_chosen_target 仍可用）。
func set_chosen_targets(_handles: Array) -> void:
	pass


func set_chosen_target(handle) -> void:
	set_chosen_targets([] if handle == null else [handle])


## 当前卡牌所在的区域：deck / hand / board / discard；用于 when 过滤中的 zone 变量。
func get_zone() -> String:
	return ""


## 解析选择器，返回实体句柄数组（空数组表示没有目标）。
func resolve_selector(_selector: String) -> Array:
	push_warning("EffectContext.resolve_selector 未实现：需要战斗层提供")
	return []


## 返回实体事实，供事件过滤、条件目标与 for_each 循环体使用。
## 至少应包含：side / class / tribes / keywords / keyword_values / buffs /
## attack / health / max_health / shield（defense 为 shield 别名）/ cost /
## column / column_abs / turn / entered_this_turn。
func describe_entity(_handle) -> Dictionary:
	push_warning("EffectContext.describe_entity 未实现：需要战斗层提供")
	return {}


## 返回用于卡牌筛选表达式（CardFilter.matches_values）判定的字段快照：
## name / kind / rarity / class / category / keywords / tribes / deck_includable / cost。
## 战斗层应返回该句柄的**当前状态**；无法判定的句柄返回空字典。
func filter_values(_handle) -> Dictionary:
	return {}


# ----- 伤害类事件的上下文事实 -----
# damaged / hero_damaged 事件派发期间，战斗层会临时写入伤害来源与数值；
# 事件结束后恢复。没有来源（锦囊/环境/无来源效果伤害）时来源为 null。

func set_damage_source(_handle) -> void:
	pass


func get_damage_source() -> Variant:
	return null


func set_damage_amount(_amount: int) -> void:
	pass


func get_damage_amount() -> int:
	return 0


## 句柄是否指向一个“实体”（战斗层的 BattleEntity）；
## 英雄句柄、卡牌实例与 null 都返回 false。
func is_entity_handle(_handle) -> bool:
	return false


## 目标所在列的环境种类（环境 id，如 highground / water / default / sunny_field）。
## 目标不是实体、或实体不在场时返回空字符串。
func environment_kind(_target: Variant = null) -> String:
	return ""


## 目标所在列的环境归属方，相对技能拥有者：ally / enemy / neutral（初始环境无主）。
## 目标不是实体、或实体不在场时返回空字符串。
func environment_owner(_target: Variant = null) -> String:
	return ""


# ----- 原语（以单个实体句柄为参数） -----

func summon(_card_name: String, _column: Variant = null, _max_column: Variant = null) -> Array:
	push_warning("EffectContext.summon 未实现：需要战斗层提供")
	return []


func draw_cards(_count: int, _cost_delta: int = 0) -> int:
	push_warning("EffectContext.draw_cards 未实现：需要战斗层提供")
	return 0


func draw_matching_cards(_target, _count: int, _filter_text: String, _cost_delta: int = 0) -> int:
	push_warning("EffectContext.draw_matching_cards 未实现：需要战斗层提供")
	return 0


func deal_damage(_target, _amount: int) -> void:
	push_warning("EffectContext.deal_damage 未实现：需要战斗层提供")


func damage_column_relative(_amount: int, _direction: String, _column_offset: int = 0) -> void:
	push_warning("EffectContext.damage_column_relative 未实现：需要战斗层提供")


func heal(_target, _amount: int) -> void:
	push_warning("EffectContext.heal 未实现：需要战斗层提供")


func gain_shield(_target, _amount: int) -> void:
	push_warning("EffectContext.gain_shield 未实现：需要战斗层提供")


func buff_stats(_target, _attack_delta: int, _health_delta: int) -> void:
	push_warning("EffectContext.buff_stats 未实现：需要战斗层提供")


func gain_energy(_amount: int) -> void:
	push_warning("EffectContext.gain_energy 未实现：需要战斗层提供")


func give_keyword(_target, _keyword: String, _value: int = 0) -> void:
	push_warning("EffectContext.give_keyword 未实现：需要战斗层提供")


func environment_grant_keyword(_keyword: String, _value: int, _side_filter: String) -> void:
	push_warning("EffectContext.environment_grant_keyword 未实现：需要战斗层提供")


func environment_grant_keyword_persistent(_keyword: String, _value: int, _side_filter: String) -> void:
	push_warning("EffectContext.environment_grant_keyword_persistent 未实现：需要战斗层提供")


func transform_targets(_targets: Array, _filter_text: String) -> void:
	push_warning("EffectContext.transform_targets 未实现：需要战斗层提供")


func transform_hand(_side_filter: String, _old_filter: String, _new_filter: String) -> void:
	push_warning("EffectContext.transform_hand 未实现：需要战斗层提供")


func environment_grant_stats(_attack: int, _health: int, _shield: int, _side_filter: String) -> void:
	push_warning("EffectContext.environment_grant_stats 未实现：需要战斗层提供")


## 消灭目标。from_spell 表示效果来源是锦囊牌——锦囊免疫只针对锦囊来源，
## 实体/环境等来源的消灭应当正常生效。
func destroy(_target, _from_spell: bool = false) -> void:
	push_warning("EffectContext.destroy 未实现：需要战斗层提供")


## 当前效果来源是否为锦囊（用于判断“锦囊免疫”是否生效）。
func is_spell_effect_source() -> bool:
	return false


## 把实体移动到指定列/位置（0=普通，1=组队）；成功会触发 position_changed。
func move_entity(_target, _column: int, _slot: int) -> bool:
	push_warning("EffectContext.move_entity 未实现：需要战斗层提供")
	return false


## 把实体移动到玩家在出牌时选择的列/位置；成功会触发 position_changed。
func move_entity_to_chosen_position(_target) -> bool:
	push_warning("EffectContext.move_entity_to_chosen_position 未实现：需要战斗层提供")
	return false


## 从卡牌数据库按筛选条件随机塞入牌库/手牌；target 为英雄或实体句柄。
func add_random_cards(
	_zone: String, _target, _count: int, _filter_text: String, _cost_delta: int = 0,
	_keyword: String = "", _attack_bonus: int = 0, _health_bonus: int = 0, _shield_bonus: int = 0,
	_keyword_value: int = 0
) -> int:
	push_warning("EffectContext.add_random_cards 未实现：需要战斗层提供")
	return 0


## 返回相对基准列偏移范围内的实体；side_filter 为 ally / enemy / both。
func entities_in_column(_min_offset: int, _max_offset: int, _side_filter: String, _min_attack: int = 0) -> Array:
	push_warning("EffectContext.entities_in_column 未实现：需要战斗层提供")
	return []


## 在基准列（实体列/环境列/锦囊选择列）加上偏移的位置尝试放置环境。
func place_environment(_column_offset: int, _card_name: String) -> bool:
	push_warning("EffectContext.place_environment 未实现：需要战斗层提供")
	return false


func apply_buff(_target, _buff_id: String, _amount: int = 1) -> bool:
	push_warning("EffectContext.apply_buff 未实现：需要战斗层提供")
	return false


func remove_buff(_target, _buff_id: String) -> bool:
	push_warning("EffectContext.remove_buff 未实现：需要战斗层提供")
	return false


func force_attack(_target) -> bool:
	push_warning("EffectContext.force_attack 未实现：需要战斗层提供")
	return false


func remove_entity(_target) -> bool:
	push_warning("EffectContext.remove_entity 未实现：需要战斗层提供")
	return false


func gain_max_health(_target, _delta: int) -> void:
	push_warning("EffectContext.gain_max_health 未实现：需要战斗层提供")


func put_random_card_on_deck_top(
	_target, _filter_text: String, _keyword: String = "",
	_attack_bonus: int = 0, _health_bonus: int = 0, _shield_bonus: int = 0, _keyword_value: int = 0
) -> bool:
	push_warning("EffectContext.put_random_card_on_deck_top 未实现：需要战斗层提供")
	return false


func put_hand_card_on_deck_top(_target, _filter_text: String) -> bool:
	push_warning("EffectContext.put_hand_card_on_deck_top 未实现：需要战斗层提供")
	return false


func shuffle_buried_positions(_target) -> bool:
	push_warning("EffectContext.shuffle_buried_positions 未实现：需要战斗层提供")
	return false


## 当前效果来源是否可以作用于该目标；锦囊来源会过滤锦囊免疫。
func can_target(_target) -> bool:
	return true


## 多目标选择声明：从 selector 候选中校验最多 count 个已选目标。
func choose_targets(_count: int, _selector: String) -> bool:
	push_warning("EffectContext.choose_targets 未实现：需要战斗层提供")
	return false


## 区域卡牌被动：修改自身卡牌实例的攻击/费用。
func gain_attack(_amount: int) -> void:
	pass


func reduce_cost(_amount: int) -> void:
	pass


# ----- 玩家特殊标志物（字符串名字，数量允许负数） -----

func add_marker(_marker_name: String, _amount: int) -> void:
	push_warning("EffectContext.add_marker 未实现：需要战斗层提供")


func remove_marker(_marker_name: String, _amount: int) -> void:
	push_warning("EffectContext.remove_marker 未实现：需要战斗层提供")


func marker_count(_marker_name: String) -> int:
	return 0

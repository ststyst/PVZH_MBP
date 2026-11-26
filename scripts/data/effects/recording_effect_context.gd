class_name RecordingEffectContext
extends EffectContext
## 测试/调试用上下文：记录原语调用，不改变任何游戏状态。
##
## 用法示例：
##   var ctx := RecordingEffectContext.new()
##   ctx.selector_results["chosen"] = ["chosen_handle"]
##   ctx.entity_facts["chosen_handle"] = {"attack": 2, "health": 3, "side": "enemy"}
##   ctx.set_self_target("self_handle")
##   script.run_on_play(ctx)
##   ctx.calls  # [{"op": "deal_damage", "target": "chosen_handle", "amount": 3}]
##
## 维护须知：这里的每个覆盖方法都必须与 EffectContext 的参数表**完全一致**。
## 参数不一致会让本脚本编译失败 → `RecordingEffectContext.new()` 报
## 「Nonexistent function 'new' in base 'GDScript'」→ 整个 effect_runner 套件静默空跑。
## 2026-11-24 就因 `add_random_cards` 扩参未同步，空跑了约 26 小时；
## tests/run_tests.gd 现已加「0 断言即失败」的空跑守卫，但仍要在这里保持同步。

var calls: Array[Dictionary] = []
## 查询函数调用（entities_in_column 等）单独记录，避免污染“原语调用”断言。
var query_calls: Array[Dictionary] = []

## 选择器 -> 句柄数组（例如 {"chosen": ["h1"], "all_enemies": ["e1", "e2"]}）
var selector_results: Dictionary = {}
## 查询函数结果（例如 {"entities_in_column": [...], "random_targets": [...]}）
var query_results: Dictionary = {}
## 句柄 -> 事实（side/class/tribes/keywords/attack/health/shield/cost/…）
var entity_facts: Dictionary = {}
## 句柄 -> 卡牌筛选字段快照（name/kind/rarity/class/category/keywords/tribes/deck_includable/cost）
var filter_facts: Dictionary = {}

var self_target: Variant = null
var event_target: Variant = null
var chosen_targets: Array = []
var zone: String = ""

## damaged / hero_damaged 事件作用域里的伤害来源与数值。
var damage_source: Variant = null
var damage_amount: int = 0
## is_entity(damage_source) 判定用：哪些句柄算“实体”。
var entity_handles: Array = []

## 原语成功/失败开关，供用例断言失败分支。
var move_succeeds: bool = true
var choose_succeeds: bool = true
var buff_succeeds: bool = true
var force_attack_succeeds: bool = true
var remove_entity_succeeds: bool = true
var deck_top_succeeds: bool = true
var shuffle_succeeds: bool = true
var place_environment_succeeds: bool = true
var clear_environment_succeeds: bool = true
## environment_kind / environment_owner 查询的返回值，供用例切换分支。
var environment_kind_result: String = ""
var environment_owner_result: String = "neutral"

## can_target() 返回 false 的目标句柄。
var blocked_targets: Array = []
## 标志物数量。
var markers: Dictionary = {}


func reset() -> void:
	calls.clear()
	query_calls.clear()
	selector_results.clear()
	query_results.clear()
	entity_facts.clear()
	filter_facts.clear()
	self_target = null
	event_target = null
	chosen_targets.clear()
	zone = ""
	damage_source = null
	damage_amount = 0
	entity_handles.clear()
	markers.clear()
	blocked_targets.clear()
	move_succeeds = true
	choose_succeeds = true
	buff_succeeds = true
	force_attack_succeeds = true
	remove_entity_succeeds = true
	deck_top_succeeds = true
	shuffle_succeeds = true
	place_environment_succeeds = true
	clear_environment_succeeds = true
	environment_kind_result = ""
	environment_owner_result = "neutral"


func _record(op: String, data: Dictionary = {}) -> void:
	var entry: Dictionary = {"op": op}
	entry.merge(data)
	calls.append(entry)


func _record_query(op: String, data: Dictionary = {}) -> void:
	var entry: Dictionary = {"op": op}
	entry.merge(data)
	query_calls.append(entry)


# ----- 基础 -----

func set_self_target(handle) -> void:
	self_target = handle


func set_event_target(handle) -> void:
	event_target = handle


func set_chosen_targets(handles: Array) -> void:
	chosen_targets = handles.duplicate()


func get_zone() -> String:
	return zone


func set_damage_source(handle) -> void:
	damage_source = handle


func get_damage_source() -> Variant:
	return damage_source


func set_damage_amount(amount: int) -> void:
	damage_amount = amount


func get_damage_amount() -> int:
	return damage_amount


func is_entity_handle(handle) -> bool:
	return entity_handles.has(handle)


func resolve_selector(selector: String) -> Array:
	if selector == "self":
		return [] if self_target == null else [self_target]
	if selector == "event":
		return [] if event_target == null else [event_target]
	if selector == "chosen" and not selector_results.has("chosen") and not chosen_targets.is_empty():
		return chosen_targets.duplicate()
	if selector == "damage_source":
		return [] if damage_source == null else [damage_source]
	var handles: Variant = selector_results.get(selector, [])
	return handles if handles is Array else []


func describe_entity(handle) -> Dictionary:
	return entity_facts.get(handle, {})


func filter_values(handle) -> Dictionary:
	return filter_facts.get(handle, {})


func can_target(target) -> bool:
	return not blocked_targets.has(target)


func choose_targets(count: int, selector: String) -> bool:
	_record("choose_targets", {"count": count, "selector": selector})
	return choose_succeeds


# ----- 原语 -----

func summon(card_name: String, column: Variant = null, max_column: Variant = null) -> Array:
	_record("summon", {"card": card_name, "column": column, "max_column": max_column})
	return []


func draw_cards(count: int, cost_delta: int = 0, target: Variant = null) -> int:
	_record("draw_cards", {"count": count, "cost_delta": cost_delta, "target": target})
	return count


func draw_matching_cards(target, count: int, filter_text: String, cost_delta: int = 0) -> int:
	_record("draw_matching_cards", {
		"target": target, "count": count, "filter": filter_text, "cost_delta": cost_delta,
	})
	return count


func deal_damage(target, amount: int) -> void:
	_record("deal_damage", {"target": target, "amount": amount})


func damage_column_relative(amount: int, direction: String, column_offset: int = 0) -> void:
	_record("damage_column_relative", {
		"amount": amount, "direction": direction, "column_offset": column_offset,
	})


func heal(target, amount: int) -> void:
	_record("heal", {"target": target, "amount": amount})


func gain_shield(target, amount: int) -> void:
	_record("gain_shield", {"target": target, "amount": amount})


func buff_stats(target, attack_delta: int, health_delta: int) -> void:
	_record("buff_stats", {"target": target, "attack": attack_delta, "health": health_delta})


func gain_energy(amount: int) -> void:
	_record("gain_energy", {"amount": amount})


func give_keyword(target, keyword: String, value: int = 0) -> void:
	_record("give_keyword", {"target": target, "keyword": keyword, "value": value})


func environment_grant_keyword(keyword: String, value: int, side_filter: String) -> void:
	_record("environment_grant_keyword", {"keyword": keyword, "value": value, "side": side_filter})


func environment_grant_keyword_persistent(keyword: String, value: int, side_filter: String) -> void:
	_record("environment_grant_keyword_persistent", {
		"keyword": keyword, "value": value, "side": side_filter,
	})


func environment_grant_stats(attack: int, health: int, shield: int, side_filter: String) -> void:
	_record("environment_grant_stats", {
		"attack": attack, "health": health, "shield": shield, "side": side_filter,
	})


func transform_targets(targets: Array, filter_text: String) -> void:
	_record("transform_targets", {"targets": targets, "filter": filter_text})


func transform_hand(side_filter: String, old_filter: String, new_filter: String) -> void:
	_record("transform_hand", {
		"side": side_filter, "old_filter": old_filter, "new_filter": new_filter,
	})


func destroy(target, from_spell: bool = false) -> void:
	_record("destroy", {"target": target, "from_spell": from_spell})


## 测试里可切换“效果来源是锦囊”，用于断言消灭的来源判定。
var spell_source: bool = false


func is_spell_effect_source() -> bool:
	return spell_source


func move_entity(target, column: int, slot: int) -> bool:
	_record("move_entity", {"target": target, "column": column, "slot": slot})
	return move_succeeds


func move_entity_to_chosen_position(target) -> bool:
	_record("move_entity_to_chosen_position", {"target": target})
	return move_succeeds


func add_random_cards(
	zone_name: String, target, count: int, filter_text: String, cost_delta: int = 0,
	keyword: String = "", attack_bonus: int = 0, health_bonus: int = 0, shield_bonus: int = 0,
	keyword_value: int = 0
) -> int:
	_record("add_random_cards", {
		"zone": zone_name,
		"target": target,
		"count": count,
		"filter": filter_text,
		"cost_delta": cost_delta,
		"keyword": keyword,
		"attack_bonus": attack_bonus,
		"health_bonus": health_bonus,
		"shield_bonus": shield_bonus,
		"keyword_value": keyword_value,
	})
	return count


func entities_in_column(min_offset: int, max_offset: int, side_filter: String, min_attack: int = 0) -> Array:
	_record_query("entities_in_column", {
		"min_offset": min_offset, "max_offset": max_offset,
		"side": side_filter, "min_attack": min_attack,
	})
	var result: Variant = query_results.get("entities_in_column", [])
	return result if result is Array else []


func place_environment(column_offset: int, card_name: String) -> bool:
	_record("place_environment", {"column_offset": column_offset, "card": card_name})
	return place_environment_succeeds


func clear_environment(column_offset: int = 0) -> bool:
	_record("clear_environment", {"column_offset": column_offset})
	return clear_environment_succeeds


func summon_matching(
	filter_text: String,
	column: Variant = null,
	max_column: Variant = null,
	keyword_text: String = "",
) -> void:
	_record("summon_matching", {
		"filter": filter_text,
		"column": column,
		"max_column": max_column,
		"keyword": keyword_text,
	})


func environment_kind(target: Variant = null) -> String:
	_record_query("environment_kind", {"target": target})
	return environment_kind_result


func environment_owner(target: Variant = null) -> String:
	_record_query("environment_owner", {"target": target})
	return environment_owner_result


func apply_buff(target, buff_id: String, amount: int = 1) -> bool:
	_record("apply_buff", {"target": target, "buff": buff_id, "amount": amount})
	return buff_succeeds


func remove_buff(target, buff_id: String) -> bool:
	_record("remove_buff", {"target": target, "buff": buff_id})
	return buff_succeeds


func force_attack(target) -> bool:
	_record("force_attack", {"target": target})
	return force_attack_succeeds


func remove_entity(target) -> bool:
	_record("remove_entity", {"target": target})
	return remove_entity_succeeds


func gain_max_health(target, delta: int) -> void:
	_record("gain_max_health", {"target": target, "delta": delta})


func put_random_card_on_deck_top(
	target, filter_text: String, keyword: String = "",
	attack_bonus: int = 0, health_bonus: int = 0, shield_bonus: int = 0, keyword_value: int = 0
) -> bool:
	_record("put_card_on_deck_top", {
		"target": target,
		"filter": filter_text,
		"keyword": keyword,
		"attack_bonus": attack_bonus,
		"health_bonus": health_bonus,
		"shield_bonus": shield_bonus,
		"keyword_value": keyword_value,
	})
	return deck_top_succeeds


func put_hand_card_on_deck_top(target, filter_text: String) -> bool:
	_record("put_hand_card_on_deck_top", {"target": target, "filter": filter_text})
	return deck_top_succeeds


func shuffle_buried_positions(target) -> bool:
	_record("shuffle_buried_positions", {"target": target})
	return shuffle_succeeds


func gain_attack(amount: int) -> void:
	_record("gain_attack", {"amount": amount})


func reduce_cost(amount: int) -> void:
	_record("reduce_cost", {"amount": amount})


# ----- 标志物 -----

func add_marker(marker_name: String, amount: int, target: Variant = null) -> void:
	_record("add_marker", {"name": marker_name, "amount": amount, "target": target})
	markers[marker_name] = int(markers.get(marker_name, 0)) + amount


func remove_marker(marker_name: String, amount: int, target: Variant = null) -> void:
	_record("remove_marker", {"name": marker_name, "amount": amount, "target": target})
	markers[marker_name] = int(markers.get(marker_name, 0)) - amount


func marker_count(marker_name: String, target: Variant = null) -> int:
	_record_query("marker_count", {"name": marker_name, "target": target})
	return int(markers.get(marker_name, 0))


# ----- 查询原语 -----

func random_targets(count: int, selector: String) -> Array:
	_record_query("random_targets", {"count": count, "selector": selector})
	var result: Variant = query_results.get("random_targets", [])
	return result if result is Array else []


func count_buff_in_columns(side: String, min_column: int, max_column: int, buff_id: String) -> int:
	_record_query("count_buff_in_columns", {
		"side": side, "min_column": min_column, "max_column": max_column, "buff": buff_id,
	})
	return int(query_results.get("count_buff_in_columns", 0))


func buried_in_columns(side: String, min_column: int, max_column: int) -> Array:
	_record_query("buried_in_columns", {
		"side": side, "min_column": min_column, "max_column": max_column,
	})
	var result: Variant = query_results.get("buried_in_columns", [])
	return result if result is Array else []

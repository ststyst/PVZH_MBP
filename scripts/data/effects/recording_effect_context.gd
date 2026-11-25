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

var calls: Array[Dictionary] = []

## 选择器 -> 句柄数组（例如 {"chosen": ["h1"], "all_enemies": ["e1", "e2"]}）
var selector_results: Dictionary = {}
## 句柄 -> 事实（side/class/tribes/attack/health/shield）
var entity_facts: Dictionary = {}

var self_target: Variant = null
var event_target: Variant = null


func reset() -> void:
	calls.clear()
	selector_results.clear()
	entity_facts.clear()
	self_target = null
	event_target = null


func set_self_target(handle) -> void:
	self_target = handle


func set_event_target(handle) -> void:
	event_target = handle


func resolve_selector(selector: String) -> Array:
	if selector == "self":
		return [] if self_target == null else [self_target]
	if selector == "event":
		return [] if event_target == null else [event_target]
	var handles: Variant = selector_results.get(selector, [])
	return handles if handles is Array else []


func describe_entity(handle) -> Dictionary:
	return entity_facts.get(handle, {})


func summon(card_name: String, column: Variant = null, max_column: Variant = null) -> Array:
	calls.append({
		"op": "summon",
		"card": card_name,
		"column": column,
		"max_column": max_column,
	})
	return []


func draw_cards(count: int, cost_delta: int = 0) -> int:
	calls.append({"op": "draw_cards", "count": count, "cost_delta": cost_delta})
	return count


func deal_damage(target, amount: int) -> void:
	calls.append({"op": "deal_damage", "target": target, "amount": amount})


func heal(target, amount: int) -> void:
	calls.append({"op": "heal", "target": target, "amount": amount})


func gain_shield(target, amount: int) -> void:
	calls.append({"op": "gain_shield", "target": target, "amount": amount})


func buff_stats(target, attack_delta: int, health_delta: int) -> void:
	calls.append({
		"op": "buff_stats",
		"target": target,
		"attack": attack_delta,
		"health": health_delta,
	})


func gain_energy(amount: int) -> void:
	calls.append({"op": "gain_energy", "amount": amount})


func give_keyword(target, keyword: String, value: int = 0) -> void:
	calls.append({"op": "give_keyword", "target": target, "keyword": keyword, "value": value})


func destroy(target) -> void:
	calls.append({"op": "destroy", "target": target})


func add_random_cards(
	zone: String, target, count: int, filter_text: String, cost_delta: int = 0,
	keyword: String = "", attack_bonus: int = 0, health_bonus: int = 0, shield_bonus: int = 0,
	keyword_value: int = 0
) -> int:
	calls.append({
		"op": "add_random_cards",
		"zone": zone,
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

@tool
extends McpTestSuite
## 能力 DSL 运行测试：用 RecordingEffectContext 断言原语调用。suite = "effect_runner"。

var context: RecordingEffectContext = null


func suite_name() -> String:
	return "effect_runner"


func setup() -> void:
	context = RecordingEffectContext.new()
	context.set_self_target("self_handle")


func teardown() -> void:
	context = null


func _run(source: String) -> Array[String]:
	var script: CardEffectScript = CardEffectScript.parse(source)
	assert_false(script.has_errors(), "脚本应可解析：%s" % [script.errors])
	return script.run_on_play(context)


func test_damage_chosen() -> void:
	context.selector_results["chosen"] = ["enemy_1"]
	var errors: Array[String] = _run("deal_damage(chosen, 3)")
	assert_eq(errors.size(), 0, "不应有运行错误：%s" % [errors])
	assert_eq(context.calls.size(), 1)
	if context.calls.is_empty():
		return
	assert_eq(str(context.calls[0].get("op", "")), "deal_damage")
	assert_eq(str(context.calls[0].get("target", "")), "enemy_1")
	assert_eq(int(context.calls[0].get("amount", 0)), 3)


func test_variable_and_arithmetic() -> void:
	context.selector_results["chosen"] = ["enemy_1"]
	_run("x = 2 + 3 * 2\ndeal_damage(chosen, x)")
	assert_eq(context.calls.size(), 1)
	assert_eq(int(context.calls[0].get("amount", 0)), 8, "2 + 3 * 2 应为 8")


func test_repeat() -> void:
	context.selector_results["random_enemy"] = ["enemy_1"]
	_run("repeat(3): deal_damage(random_enemy, 1)")
	assert_eq(context.calls.size(), 3)


func test_if_condition() -> void:
	context.selector_results["chosen"] = ["enemy_1"]
	context.entity_facts["enemy_1"] = {"attack": 5, "health": 4, "side": "enemy"}
	_run("if attack(chosen) > 3:\n    destroy(chosen)")
	assert_eq(context.calls.size(), 1)
	assert_eq(str(context.calls[0].get("op", "")), "destroy")


func test_conditional_target_filters() -> void:
	context.selector_results["chosen"] = ["small", "big"]
	context.entity_facts["small"] = {"attack": 2}
	context.entity_facts["big"] = {"attack": 6}
	_run("deal_damage(chosen_if(attack <= 3), 4)")
	assert_eq(context.calls.size(), 1, "只有攻击力 <= 3 的目标应被命中")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "small")


func test_multi_target_loops() -> void:
	context.selector_results["all_enemies"] = ["e1", "e2"]
	_run("deal_damage(all_enemies, 2)")
	assert_eq(context.calls.size(), 2)


func test_event_self_default() -> void:
	var script: CardEffectScript = CardEffectScript.parse("when enter: gain_energy(2)")
	assert_false(script.has_errors())
	script.run_event(context, "enter", "self_handle")
	assert_eq(context.calls.size(), 1, "无过滤时只响应自己")
	context.calls.clear()
	script.run_event(context, "enter", "other_handle")
	assert_eq(context.calls.size(), 0, "其他实体的事件不应触发")


func test_event_filter_side_and_stat() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"when enter(side == 'enemy' and attack > 3): deal_damage(event, 2)"
	)
	assert_false(script.has_errors())
	context.entity_facts["enemy_big"] = {"side": "enemy", "attack": 5}
	context.entity_facts["enemy_small"] = {"side": "enemy", "attack": 1}
	context.entity_facts["ally_big"] = {"side": "ally", "attack": 5}
	script.run_event(context, "enter", "enemy_big")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "enemy_big")
	context.calls.clear()
	script.run_event(context, "enter", "enemy_small")
	script.run_event(context, "enter", "ally_big")
	assert_eq(context.calls.size(), 0)


func test_event_filter_tribe() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"when enter(has_tribe('pea') and side == 'enemy'): draw_cards(1)"
	)
	assert_false(script.has_errors())
	context.entity_facts["pea_enemy"] = {"side": "enemy", "tribes": ["pea"]}
	context.entity_facts["robot_enemy"] = {"side": "enemy", "tribes": ["robot"]}
	script.run_event(context, "enter", "pea_enemy")
	assert_eq(context.calls.size(), 1)
	context.calls.clear()
	script.run_event(context, "enter", "robot_enemy")
	assert_eq(context.calls.size(), 0)


func test_event_stats_change() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"when attack_changed(side == 'self'): draw_cards(1)"
	)
	assert_false(script.has_errors())
	context.entity_facts["self_handle"] = {"side": "self", "attack": 4}
	script.run_event(context, "attack_changed", "self_handle")
	assert_eq(context.calls.size(), 1)


func test_runtime_error_is_recorded() -> void:
	var errors: Array[String] = _run("x = 1 / 0\ndeal_damage(chosen, x)")
	assert_gt(errors.size(), 0, "除以 0 应记录运行错误")


func test_unassigned_variable_is_recorded() -> void:
	context.selector_results["chosen"] = ["enemy_1"]
	var errors: Array[String] = _run("deal_damage(chosen, missing)")
	assert_gt(errors.size(), 0, "未定义变量应记录错误")

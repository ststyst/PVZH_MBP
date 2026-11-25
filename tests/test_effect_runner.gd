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


func test_multi_ability_entity() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"when die: gain_energy(2); when enter: buff_stats(self, 2, 0)"
	)
	assert_false(script.has_errors(), "双异能实体应可解析：%s" % [script.errors])
	script.run_event(context, "enter", "self_handle")
	assert_eq(context.calls.size(), 1, "入场应触发第一条能力")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "buff_stats")
		assert_eq(int(context.calls[0].get("attack", 0)), 2)
	context.calls.clear()
	script.run_event(context, "die", "self_handle")
	assert_eq(context.calls.size(), 1, "死亡应触发第二条能力")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "gain_energy")
		assert_eq(int(context.calls[0].get("amount", 0)), 2)
	context.calls.clear()
	script.run_event(context, "attack", "self_handle")
	assert_eq(context.calls.size(), 0, "未声明的事件不应触发")


func test_for_each_runs_block_for_each_target() -> void:
	context.selector_results["all_enemies"] = ["e1", "e2"]
	context.entity_facts["e1"] = {"attack": 1, "health": 2, "cost": 1}
	context.entity_facts["e2"] = {"attack": 2, "health": 3, "cost": 2}
	_run("for_each(all_enemies) as e: deal_damage(e, 4)")
	assert_eq(context.calls.size(), 2, "每个目标各执行一次块")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("target", "")), "e1")
		assert_eq(str(context.calls[1].get("target", "")), "e2")
		assert_eq(int(context.calls[0].get("amount", 0)), 4)


func test_for_each_branches_per_target_facts() -> void:
	context.selector_results["all_enemies"] = ["weak", "tough"]
	context.entity_facts["weak"] = {"attack": 1, "health": 2, "cost": 1}
	context.entity_facts["tough"] = {"attack": 5, "health": 8, "cost": 6}
	_run(
		"for_each(all_enemies) as e:\n"
		+ "    if health <= 3:\n"
		+ "        destroy(e)\n"
		+ "    elif cost >= 5:\n"
		+ "        buff_stats(e, 0, 2)\n"
		+ "    else:\n"
		+ "        heal(e, 1)"
	)
	assert_eq(context.calls.size(), 2, "两个目标应各命中一个分支")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("op", "")), "destroy")
		assert_eq(str(context.calls[1].get("op", "")), "buff_stats")


func test_for_each_reads_tribe_and_keyword_of_target() -> void:
	context.selector_results["all_allies"] = ["ally_taunt", "ally_plain"]
	context.entity_facts["ally_taunt"] = {"tribes": ["pea"], "keywords": ["taunt"]}
	context.entity_facts["ally_plain"] = {"tribes": ["zombie"], "keywords": []}
	_run(
		"for_each(all_allies) as a:\n"
		+ "    if has_tribe('pea') and has_keyword('taunt'):\n"
		+ "        give_keyword(a, 'armored')"
	)
	assert_eq(context.calls.size(), 1, "只有豆族嘲讽友方获得护甲")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "ally_taunt")


func test_for_each_loop_index_and_count() -> void:
	context.selector_results["all_enemies"] = ["e1", "e2", "e3"]
	_run("for_each(all_enemies) as e: deal_damage(e, loop_index + loop_count)")
	assert_eq(context.calls.size(), 3)
	if context.calls.size() == 3:
		assert_eq(int(context.calls[0].get("amount", 0)), 3)
		assert_eq(int(context.calls[1].get("amount", 0)), 4)
		assert_eq(int(context.calls[2].get("amount", 0)), 5)


func test_for_each_nested_loops_keep_outer_handle() -> void:
	context.selector_results["all_enemies"] = ["e1", "e2"]
	context.selector_results["all_allies"] = ["a1"]
	context.entity_facts["e1"] = {"attack": 1}
	context.entity_facts["e2"] = {"attack": 2}
	context.entity_facts["a1"] = {"attack": 0}
	_run("for_each(all_enemies) as e:\n    for_each(all_allies) as a: deal_damage(e, attack(e))")
	assert_eq(context.calls.size(), 2, "内层循环每轮都应拿到外层目标 e")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("target", "")), "e1")
		assert_eq(int(context.calls[0].get("amount", 0)), 1)
		assert_eq(str(context.calls[1].get("target", "")), "e2")
		assert_eq(int(context.calls[1].get("amount", 0)), 2)


func test_for_each_over_variable_array() -> void:
	context.selector_results["all_enemies"] = ["e1", "e2"]
	_run("group = all_enemies\nfor_each(group) as e: heal(e, 2)")
	assert_eq(context.calls.size(), 2, "变量里保存的目标数组也应可循环")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("op", "")), "heal")


func test_event_filter_can_read_cost_and_keywords() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"when enter(cost >= 5 and has_keyword('taunt')): gain_energy(1)"
	)
	assert_false(script.has_errors(), "事件过滤应可读费用与词缀：%s" % [script.errors])
	context.entity_facts["pending"] = {"cost": 6, "keywords": ["taunt"]}
	script.run_event(context, "enter", "pending")
	assert_eq(context.calls.size(), 1, "满足费用与词缀条件的入场应触发")


func test_conditional_target_uses_cost() -> void:
	context.selector_results["chosen"] = ["cheap", "pricey"]
	context.entity_facts["cheap"] = {"cost": 1}
	context.entity_facts["pricey"] = {"cost": 5}
	_run("destroy(chosen_if(cost >= 3))")
	assert_eq(context.calls.size(), 1, "只有费用 >= 3 的目标被选中")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "pricey")

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


# ===== 盲区补测：此前没有任何单元测试的原语 =====


func test_transform_targets_records_filter() -> void:
	context.selector_results["chosen"] = ["e1", "e2"]
	_run("transform(chosen, \"kind == 'entity' and cost <= 3\")")
	assert_eq(context.calls.size(), 1)
	if context.calls.is_empty():
		return
	assert_eq(str(context.calls[0].get("op", "")), "transform_targets")
	assert_eq(str(context.calls[0].get("filter", "")), "kind == 'entity' and cost <= 3")
	assert_eq((context.calls[0].get("targets", []) as Array).size(), 2, "变形目标是数组")


func test_transform_hand_records_three_filters() -> void:
	_run("transform_hand('enemy', \"kind == 'entity'\", \"kind == 'spell'\")")
	assert_eq(context.calls.size(), 1)
	if context.calls.is_empty():
		return
	assert_eq(str(context.calls[0].get("op", "")), "transform_hand")
	assert_eq(str(context.calls[0].get("side", "")), "enemy")
	assert_eq(str(context.calls[0].get("old_filter", "")), "kind == 'entity'")
	assert_eq(str(context.calls[0].get("new_filter", "")), "kind == 'spell'")


func test_gain_shield_records_amount() -> void:
	context.selector_results["chosen"] = ["e1"]
	_run("gain_shield(chosen, 3)")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "gain_shield")
		assert_eq(int(context.calls[0].get("amount", 0)), 3)


func test_force_attack_and_remove_entity() -> void:
	context.selector_results["chosen"] = ["e1"]
	_run("force_attack(chosen)\nremove_entity(chosen)")
	assert_eq(context.calls.size(), 2)
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("op", "")), "force_attack")
		assert_eq(str(context.calls[1].get("op", "")), "remove_entity")


func test_apply_and_remove_buff() -> void:
	context.selector_results["chosen"] = ["e1"]
	_run(
		"apply_buff(chosen, 'frozen')\n"
		+ "apply_buff(chosen, 'invincible', 2)\n"
		+ "remove_buff(chosen, 'frozen')"
	)
	assert_eq(context.calls.size(), 3)
	if context.calls.size() == 3:
		assert_eq(str(context.calls[0].get("buff", "")), "frozen")
		assert_eq(int(context.calls[0].get("amount", 0)), 1, "省略层数默认 1")
		assert_eq(int(context.calls[1].get("amount", 0)), 2)
		assert_eq(str(context.calls[2].get("op", "")), "remove_buff")


func test_markers_add_remove_and_query() -> void:
	_run("add_marker('fatigue', 2)\nremove_marker('fatigue', 1)")
	assert_eq(context.calls.size(), 2)
	assert_eq(int(context.markers.get("fatigue", 0)), 1, "标志物数量应可增减")
	context.calls.clear()
	_run("if marker_count('fatigue') >= 1:\n    gain_energy(1)")
	assert_eq(context.calls.size(), 1, "标志物数量应能驱动条件分支")


func test_gain_max_health_per_target() -> void:
	context.selector_results["all_allies"] = ["a1", "a2"]
	_run("gain_max_health(all_allies, 2)")
	assert_eq(context.calls.size(), 2, "多目标逐个加生命上限")
	if context.calls.size() == 2:
		assert_eq(int(context.calls[0].get("delta", 0)), 2)
		assert_eq(str(context.calls[1].get("target", "")), "a2")


func test_put_card_on_deck_top_full_args() -> void:
	context.selector_results["hero"] = ["hero:p"]
	_run("put_card_on_deck_top(hero, \"kind == 'entity'\", 'taunt', 1, 2, 1, 3)")
	assert_eq(context.calls.size(), 1)
	if context.calls.is_empty():
		return
	var call: Dictionary = context.calls[0]
	assert_eq(str(call.get("op", "")), "put_card_on_deck_top")
	assert_eq(str(call.get("filter", "")), "kind == 'entity'")
	assert_eq(str(call.get("keyword", "")), "taunt")
	assert_eq(int(call.get("attack_bonus", 0)), 1)
	assert_eq(int(call.get("health_bonus", 0)), 2)
	assert_eq(int(call.get("shield_bonus", 0)), 1)
	assert_eq(int(call.get("keyword_value", 0)), 3)


func test_put_hand_card_on_deck_top() -> void:
	context.selector_results["hero"] = ["hero:p"]
	_run("put_hand_card_on_deck_top(hero, \"cost <= 2\")")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "put_hand_card_on_deck_top")
		assert_eq(str(context.calls[0].get("filter", "")), "cost <= 2")


func test_shuffle_buried_positions() -> void:
	context.selector_results["hero"] = ["hero:z"]
	_run("shuffle_buried_positions(hero)")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "shuffle_buried_positions")
		assert_eq(str(context.calls[0].get("target", "")), "hero:z")


func test_environment_grant_keyword_persistent() -> void:
	_run("environment_grant_keyword_persistent('amphibious', 0, 'ally')")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "environment_grant_keyword_persistent")
		assert_eq(str(context.calls[0].get("keyword", "")), "amphibious")
		assert_eq(str(context.calls[0].get("side", "")), "ally")


func test_environment_grant_keyword_and_stats() -> void:
	_run("environment_grant_keyword('taunt', 0, 'enemy')\nenvironment_grant_stats(1, 0, 0, 'ally')")
	assert_eq(context.calls.size(), 2)
	if context.calls.size() == 2:
		assert_eq(str(context.calls[0].get("op", "")), "environment_grant_keyword")
		assert_eq(str(context.calls[0].get("side", "")), "enemy")
		assert_eq(int(context.calls[1].get("attack", 0)), 1)
		assert_eq(str(context.calls[1].get("side", "")), "ally")


func test_summon_variants() -> void:
	_run("summon('snowpea')\nsummon('snowpea', 2)\nsummon('snowpea', -1, 1)")
	assert_eq(context.calls.size(), 3)
	if context.calls.size() == 3:
		assert_true(context.calls[0].get("column") == null, "单参数召唤不指定列")
		assert_eq(int(context.calls[1].get("column", 0)), 2)
		assert_eq(int(context.calls[2].get("max_column", 0)), 1)


func test_draw_matching_cards() -> void:
	context.selector_results["hero"] = ["hero:p"]
	_run("draw_matching_cards(hero, 2, \"kind == 'spell'\", -1)")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		var call: Dictionary = context.calls[0]
		assert_eq(str(call.get("op", "")), "draw_matching_cards")
		assert_eq(int(call.get("count", 0)), 2)
		assert_eq(str(call.get("filter", "")), "kind == 'spell'")
		assert_eq(int(call.get("cost_delta", 0)), -1)


func test_damage_column_relative_variants() -> void:
	context.entity_facts["self_handle"] = {"column": 2}
	_run("damage_column_relative(2, 'front')\ndamage_column_relative(3, 'back', 1)")
	assert_eq(context.calls.size(), 2)
	if context.calls.size() == 2:
		assert_eq(int(context.calls[0].get("amount", 0)), 2)
		assert_eq(str(context.calls[0].get("direction", "")), "front")
		assert_eq(int(context.calls[0].get("column_offset", -1)), 0, "省略偏移默认 0")
		assert_eq(int(context.calls[1].get("column_offset", 0)), 1)


func test_add_random_cards_inline_bonuses() -> void:
	context.selector_results["hero"] = ["hero:p"]
	_run(
		"add_random_cards_to_deck(hero, 2, \"kind == 'entity'\", -1, 'taunt', 1, 2, 1, 3)\n"
		+ "add_random_cards_to_hand(hero, 1, \"kind == 'spell'\")"
	)
	assert_eq(context.calls.size(), 2)
	if context.calls.size() < 2:
		return
	var deck_call: Dictionary = context.calls[0]
	assert_eq(str(deck_call.get("zone", "")), "deck")
	assert_eq(str(deck_call.get("keyword", "")), "taunt")
	assert_eq(int(deck_call.get("attack_bonus", 0)), 1)
	assert_eq(int(deck_call.get("health_bonus", 0)), 2)
	assert_eq(int(deck_call.get("shield_bonus", 0)), 1)
	assert_eq(int(deck_call.get("keyword_value", 0)), 3)
	assert_eq(str(context.calls[1].get("zone", "")), "hand", "第二个原语进手牌")


func test_damage_targets_array_callback() -> void:
	context.selector_results["damage_targets"] = ["hurt_1", "hero:z"]
	_run("deal_damage_each(damage_targets, 1, 2)")
	assert_eq(context.calls.size(), 2, "数组回调按目标个数逐个结算")
	if context.calls.size() == 2:
		assert_eq(int(context.calls[0].get("amount", 0)), 1)
		assert_eq(int(context.calls[1].get("amount", 0)), 2)
	context.calls.clear()
	_run("for_each(damage_targets) as hurt: deal_damage(hurt, 1)")
	assert_eq(context.calls.size(), 2, "for_each 也应能遍历伤害目标数组")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[1].get("target", "")), "hero:z")


func test_after_attack_and_damage_dealt_events() -> void:
	var attack_done: CardEffectScript = CardEffectScript.parse("when after_attack: gain_energy(1)")
	assert_false(attack_done.has_errors(), "after_attack 事件应可解析：%s" % [attack_done.errors])
	attack_done.run_event(context, "after_attack", "self_handle")
	assert_eq(context.calls.size(), 1, "攻击完成事件应触发")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "gain_energy")

	context.calls.clear()
	var dealt: CardEffectScript = CardEffectScript.parse("when damage_dealt: draw_cards(1)")
	assert_false(dealt.has_errors(), "damage_dealt 事件应可解析：%s" % [dealt.errors])
	dealt.run_event(context, "damage_dealt", "self_handle")
	assert_eq(context.calls.size(), 1, "造成有效伤害事件应触发")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "draw_cards")


func test_move_entity_variants() -> void:
	context.selector_results["chosen"] = ["e1"]
	_run("move_entity(chosen)")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "move_entity_to_chosen_position")
	context.calls.clear()
	_run("move_entity(chosen, 2, 1)")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(int(context.calls[0].get("column", 0)), 2)
		assert_eq(int(context.calls[0].get("slot", 0)), 1)


func test_move_entity_failure_is_recorded() -> void:
	context.selector_results["chosen"] = ["e1"]
	context.move_succeeds = false
	var errors: Array[String] = _run("move_entity(chosen)")
	assert_gt(errors.size(), 0, "移动失败应记录运行错误")


func test_gain_attack_and_reduce_cost() -> void:
	_run("gain_attack(2)\nreduce_cost(1)")
	assert_eq(context.calls.size(), 2)
	if context.calls.size() == 2:
		assert_eq(int(context.calls[0].get("amount", 0)), 2)
		assert_eq(int(context.calls[1].get("amount", 0)), 1)


func test_place_environment() -> void:
	_run("place_environment(0, 'water')")
	assert_eq(context.calls.size(), 1)
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("op", "")), "place_environment")
		assert_eq(str(context.calls[0].get("card", "")), "water")


func test_choose_column_is_declaration_only() -> void:
	var script: CardEffectScript = CardEffectScript.parse(
		"choose_column()\nplace_environment(0, 'water')"
	)
	assert_false(script.has_errors(), "choose_column 应可解析：%s" % [script.errors])
	assert_true(script.column_requirement(), "choose_column 应被识别为需要选列")
	script.run_on_play(context)
	assert_eq(context.calls.size(), 1, "choose_column 本身不产生原语调用")


func test_untargetable_target_is_skipped() -> void:
	context.selector_results["all_enemies"] = ["hidden", "visible"]
	context.blocked_targets = ["hidden"]
	_run("deal_damage(all_enemies, 2)")
	assert_eq(context.calls.size(), 1, "can_target 为 false 的目标应被跳过")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "visible")


func test_destroy_bypasses_can_target() -> void:
	context.selector_results["all_enemies"] = ["hidden"]
	context.blocked_targets = ["hidden"]
	_run("destroy(all_enemies)")
	assert_eq(context.calls.size(), 1, "消灭不检查 can_target")


func test_declaration_primitives_are_noop_at_runtime() -> void:
	var errors: Array[String] = _run(
		"evolve(\"name == 'gnoll'\")\n"
		+ "base()\n"
		+ "aura_buff(self, 'taunt', 0, 0, false)\n"
		+ "aura_hand_cost('ally', \"kind == 'spell'\", -1)\n"
		+ "aura_spell_cost('enemy', 1)\n"
		+ "double_death_effects()\n"
		+ "in_hand()\n"
		+ "in_deck()"
	)
	assert_eq(errors.size(), 0, "声明类原语不应产生运行错误：%s" % [errors])
	assert_eq(context.calls.size(), 0, "声明类原语在运行时是空操作")


func test_query_functions_delegate_to_context() -> void:
	context.query_results["entities_in_column"] = ["e1", "e2"]
	context.query_results["random_targets"] = ["r1"]
	context.query_results["count_buff_in_columns"] = 2
	context.query_results["buried_in_columns"] = ["b1"]
	_run("for_each(entities_in_column(-1, 1, 'enemy', 2)) as e: deal_damage(e, 1)")
	assert_eq(context.calls.size(), 2, "entities_in_column 结果应可循环")
	if context.calls.size() == 2:
		assert_eq(str(context.calls[1].get("target", "")), "e2")

	context.calls.clear()
	_run("for_each(random_targets(2, 'all_enemies')) as r: heal(r, 1)")
	assert_eq(context.calls.size(), 1, "random_targets 结果应可循环")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "r1")

	context.calls.clear()
	_run("if count_buff_in_columns('ally', 0, 4, 'frozen') == 2:\n    gain_energy(1)")
	assert_eq(context.calls.size(), 1, "count_buff_in_columns 应可驱动条件")

	context.calls.clear()
	_run("for_each(buried_in_columns('ally', 0, 4)) as b: destroy(b)")
	assert_eq(context.calls.size(), 1, "buried_in_columns 结果应可循环")
	if not context.calls.is_empty():
		assert_eq(str(context.calls[0].get("target", "")), "b1")

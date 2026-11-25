@tool
extends McpTestSuite
## 能力 DSL 解析测试。suite = "effect_parser"。

func suite_name() -> String:
	return "effect_parser"


func _parse(source: String) -> CardEffectScript:
	return CardEffectScript.parse(source)


func test_simple_call() -> void:
	var script: CardEffectScript = _parse("deal_damage(chosen, 3)")
	assert_false(script.has_errors(), "简单调用应无错误：%s" % [script.errors])
	assert_eq(script.on_play.size(), 1)
	assert_eq(script.events.size(), 0)


func test_semicolon_separator() -> void:
	var script: CardEffectScript = _parse("deal_damage(all_enemies, 2); heal(all_allies, 2)")
	assert_false(script.has_errors())
	assert_eq(script.on_play.size(), 2)


func test_indented_block() -> void:
	var source: String = "if attack(chosen) > 3:\n    destroy(chosen)\n    heal(hero, 2)"
	var script: CardEffectScript = _parse(source)
	assert_false(script.has_errors(), "缩进块应解析成功：%s" % [script.errors])
	assert_eq(script.on_play.size(), 1)
	assert_eq(str(script.on_play[0].get("type", "")), "if")


func test_single_line_block() -> void:
	var script: CardEffectScript = _parse("repeat(3): deal_damage(random_enemy, 1)")
	assert_false(script.has_errors())
	assert_eq(str(script.on_play[0].get("type", "")), "repeat")


func test_when_with_filter() -> void:
	var script: CardEffectScript = _parse("when enter(side == 'enemy' and attack > 3): deal_damage(event, 2)")
	assert_false(script.has_errors(), "事件块应解析成功：%s" % [script.errors])
	assert_eq(script.events.size(), 1)
	var trigger: Dictionary = script.events[0]
	assert_eq(str(trigger.get("event", "")), "enter")
	assert_true(trigger.get("predicate") != null, "应记录过滤条件")


func test_assignment_and_arithmetic() -> void:
	var script: CardEffectScript = _parse("x = 2 + 3 * 2\ndeal_damage(chosen, x)")
	assert_false(script.has_errors(), "赋值与运算应解析成功：%s" % [script.errors])
	assert_eq(script.on_play.size(), 2)
	assert_eq(str(script.on_play[0].get("type", "")), "assign")


func test_conditional_target() -> void:
	var script: CardEffectScript = _parse("destroy(chosen_if(attack <= 3))")
	assert_false(script.has_errors())
	var call: Dictionary = script.on_play[0]
	var target: Dictionary = call.get("args", [])[0]
	assert_eq(str(target.get("selector", "")), "chosen_if")
	assert_true(target.get("predicate") != null)


func test_unknown_function_reports_error() -> void:
	var script: CardEffectScript = _parse("boom(chosen)")
	assert_true(script.has_errors(), "未知函数应报错")


func test_unknown_event_reports_error() -> void:
	var script: CardEffectScript = _parse("when fly: draw_cards(1)")
	assert_true(script.has_errors(), "未知事件应报错")


func test_entity_requires_event_blocks() -> void:
	var effect: CardEffectScript = _parse("gain_energy(2)")
	assert_true(effect.validate_for_kind("entity").size() > 0, "实体牌顶层语句应被拒绝")
	var enter_effect: CardEffectScript = _parse("when enter: gain_energy(2)")
	assert_eq(enter_effect.validate_for_kind("entity").size(), 0)
	assert_true(enter_effect.validate_for_kind("spell").size() > 0, "锦囊牌不应有事件块")


func test_empty_ability() -> void:
	var script: CardEffectScript = _parse("")
	assert_false(script.has_errors())
	assert_false(script.has_effect())


func test_bad_indentation_reports_error() -> void:
	var script: CardEffectScript = _parse("if attack(chosen) > 3:\ndeal_damage(chosen, 1)")
	assert_true(script.has_errors(), "缺少缩进应报错")


func test_multiple_when_blocks_semicolon() -> void:
	var script: CardEffectScript = _parse("when die: gain_energy(2); when enter: buff_stats(self, 2, 0)")
	assert_false(script.has_errors(), "多事件块应可解析：%s" % [script.errors])
	assert_eq(script.events.size(), 2)
	if script.events.size() == 2:
		assert_eq(str(script.events[0].get("event", "")), "die")
		assert_eq(str(script.events[1].get("event", "")), "enter")


func test_multiple_when_blocks_newline() -> void:
	var script: CardEffectScript = _parse(
		"when die: gain_energy(2)\nwhen enter: buff_stats(self, 2, 0)"
	)
	assert_false(script.has_errors(), "多事件块（换行）应可解析：%s" % [script.errors])
	assert_eq(script.events.size(), 2)

func test_entity_chosen_requires_choose() -> void:
	var bad: CardEffectScript = CardEffectScript.parse(
		"when enter:\n    deal_damage(chosen, 2)"
	)
	assert_false(bad.validate_for_kind("entity").is_empty(), "实体 chosen 没有 choose 应报错")
	var good: CardEffectScript = CardEffectScript.parse(
		"when enter:\n    choose(1, \"all_enemies\")\n    deal_damage(chosen, 2)"
	)
	assert_true(good.validate_for_kind("entity").is_empty(), "实体 choose+chosen 应合法")


func test_evolve_and_base_are_entity_only() -> void:
	var evolve: CardEffectScript = CardEffectScript.parse("evolve(\"name == 'gnoll'\")\nwhen evolved: add_marker(\"x\", 1)")
	assert_true(evolve.validate_for_kind("entity").is_empty())
	assert_false(evolve.validate_for_kind("spell").is_empty(), "锦囊不能声明进化")
	assert_true(evolve.is_evolve_ability)
	var base: CardEffectScript = CardEffectScript.parse("base()\nwhen mounted: add_marker(\"x\", 1)")
	assert_true(base.validate_for_kind("entity").is_empty())
	assert_false(base.validate_for_kind("environment").is_empty(), "环境不能声明底座")
	assert_true(base.is_base_ability)


func test_for_each_parses_target_and_variable() -> void:
	var script: CardEffectScript = _parse("for_each(all_enemies) as e:\n    deal_damage(e, 1)")
	assert_false(script.has_errors(), "for_each 应可解析：%s" % [script.errors])
	assert_eq(script.on_play.size(), 1)
	if script.on_play.is_empty():
		return
	var statement: Dictionary = script.on_play[0]
	assert_eq(str(statement.get("type", "")), "for_each")
	assert_eq(str(statement.get("var", "")), "e")
	assert_eq((statement.get("body", []) as Array).size(), 1)


func test_for_each_default_variable_name() -> void:
	var script: CardEffectScript = _parse("for_each(all_allies): heal(it, 2)")
	assert_false(script.has_errors(), "省略 as 时应默认使用 it：%s" % [script.errors])
	assert_eq(script.on_play.size(), 1)
	if script.on_play.is_empty():
		return
	assert_eq(str(script.on_play[0].get("var", "")), "it")


func test_for_each_body_allows_if_elif_else() -> void:
	var source: String = (
		"for_each(all_enemies) as e:\n"
		+ "    if health <= 3:\n"
		+ "        destroy(e)\n"
		+ "    elif cost >= 5:\n"
		+ "        deal_damage(e, 2)\n"
		+ "    else:\n"
		+ "        deal_damage(e, 1)"
	)
	var script: CardEffectScript = _parse(source)
	assert_false(script.has_errors(), "循环内 if/elif/else 应可解析：%s" % [script.errors])
	if script.on_play.is_empty():
		return
	var body: Array = script.on_play[0].get("body", [])
	assert_eq(body.size(), 1)
	if body.is_empty():
		return
	var if_statement: Dictionary = body[0]
	assert_eq(str(if_statement.get("type", "")), "if")
	var elif_branch: Array = if_statement.get("else", [])
	assert_eq(elif_branch.size(), 1, "elif 应折叠成 else 里的 if")
	if not elif_branch.is_empty():
		assert_eq(str((elif_branch[0] as Dictionary).get("type", "")), "if")


func test_for_each_supports_cost_and_keyword_queries() -> void:
	var source: String = (
		"for_each(all_enemies) as e:\n"
		+ "    if cost(e) >= 4 and has_keyword('taunt', e):\n"
		+ "        give_keyword(e, 'armored')\n"
		+ "    elif keyword_value('first_strike', e) > 0:\n"
		+ "        heal(e, 1)"
	)
	var script: CardEffectScript = _parse(source)
	assert_false(script.has_errors(), "费用/词缀查询应可解析：%s" % [script.errors])


func test_for_each_rejects_fact_variable_name() -> void:
	var script: CardEffectScript = _parse("for_each(all_enemies) as attack: deal_damage(attack, 1)")
	assert_true(script.has_errors(), "循环变量名不能与事实变量重名")


func test_for_each_rejects_selector_name() -> void:
	var script: CardEffectScript = _parse("for_each(all_enemies) as chosen: deal_damage(chosen, 1)")
	assert_true(script.has_errors(), "循环变量名不能与选择器重名")


func test_for_each_requires_parentheses() -> void:
	var script: CardEffectScript = _parse("for_each all_enemies: deal_damage(it, 1)")
	assert_true(script.has_errors(), "for_each 的目标必须写在括号里")
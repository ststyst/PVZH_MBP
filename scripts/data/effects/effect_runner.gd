class_name EffectRunner
extends RefCounted
## 能力脚本运行时：解释 AST，调用 EffectContext 的抽象原语。
## 所有运行期错误记录在 errors 里，不抛异常（避免一张卡写错导致整场战斗崩溃）。

const MAX_REPEAT: int = 100

var context: EffectContext
var errors: Array[String] = []

var _variables: Dictionary = {}


func _init(effect_context: EffectContext) -> void:
	context = effect_context


func run_program_on_play(program: Dictionary) -> Array[String]:
	errors.clear()
	_variables.clear()
	_exec_block(program.get("on_play", []))
	return errors


func run_program_event(program: Dictionary, event_name: String, event_handle) -> Array[String]:
	errors.clear()
	_variables.clear()
	var triggers: Array = program.get("events", [])
	for trigger: Dictionary in triggers:
		if str(trigger.get("event", "")) != event_name:
			continue
		if not _matches_trigger(trigger, event_handle):
			continue
		context.set_event_target(event_handle)
		_exec_block(trigger.get("body", []))
		context.set_event_target(null)
	return errors


# ----- 语句 -----

func _exec_block(block: Array) -> void:
	for statement: Dictionary in block:
		_exec_statement(statement)


func _exec_statement(statement: Dictionary) -> void:
	var statement_type: String = str(statement.get("type", ""))
	match statement_type:
		"assign":
			var variable_name: String = str(statement.get("name", ""))
			_variables[variable_name] = _eval(statement.get("value", {}), {})
		"if":
			var condition: bool = _truthy(_eval(statement.get("cond", {}), {}))
			if condition:
				_exec_block(statement.get("body", []))
			else:
				_exec_block(statement.get("else", []))
		"repeat":
			var repeat_count: int = int(_eval(statement.get("count", {}), {}))
			repeat_count = clampi(repeat_count, 0, MAX_REPEAT)
			for _iteration: int in range(repeat_count):
				_exec_block(statement.get("body", []))
		"call":
			_exec_primitive(statement)
		_:
			_error("未知语句类型：%s" % statement_type, _line_of(statement))


func _exec_primitive(statement: Dictionary) -> void:
	var primitive_name: String = str(statement.get("name", ""))
	var arguments: Array = statement.get("args", [])
	var line: int = _line_of(statement)
	match primitive_name:
		"summon":
			var card_name: String = _as_string(_eval(arguments[0], {}))
			var summon_column: Variant = null
			var summon_max_column: Variant = null
			if arguments.size() > 1:
				summon_column = _eval(arguments[1], {})
			if arguments.size() > 2:
				summon_max_column = _eval(arguments[2], {})
			context.summon(card_name, summon_column, summon_max_column)
		"draw_cards":
			var draw_count: int = _as_int(_eval(arguments[0], {}))
			var draw_cost_delta: int = 0
			if arguments.size() > 1:
				draw_cost_delta = _as_int(_eval(arguments[1], {}))
			context.draw_cards(draw_count, draw_cost_delta)
		"gain_energy":
			context.gain_energy(_as_int(_eval(arguments[0], {})))
		"deal_damage", "heal", "gain_shield", "buff_stats", "give_keyword", "destroy":
			_exec_target_primitive(primitive_name, arguments, line)
		"choose":
			var choose_count: int = maxi(_as_int(_eval(arguments[0], {})), 0)
			var choose_selector: String = _as_string(_eval(arguments[1], {}))
			if not context.choose_targets(choose_count, choose_selector):
				_error("选择目标无效（最多 %d 个，选择器 %s）" % [choose_count, choose_selector], line)
		"gain_attack":
			context.gain_attack(_as_int(_eval(arguments[0], {})))
		"reduce_cost":
			context.reduce_cost(_as_int(_eval(arguments[0], {})))
		"add_marker":
			var marker_name: String = _as_string(_eval(arguments[0], {}))
			var marker_amount: int = _as_int(_eval(arguments[1], {}))
			if marker_name.is_empty():
				_error("特殊标志物名字不能为空", line)
			else:
				context.add_marker(marker_name, marker_amount)
		"remove_marker":
			var remove_name: String = _as_string(_eval(arguments[0], {}))
			var remove_amount: int = _as_int(_eval(arguments[1], {}))
			if remove_name.is_empty():
				_error("特殊标志物名字不能为空", line)
			else:
				context.remove_marker(remove_name, remove_amount)
		"move_entity":
			var move_targets: Array = _resolve_argument_target(arguments[0])
			if move_targets.size() != 1:
				_error("move_entity 需要单个实体目标", line)
			elif arguments.size() == 1:
				if not context.move_entity_to_chosen_position(move_targets[0]):
					_error("移动实体失败（未选择位置或位置无效）", line)
			else:
				var move_column: int = _as_int(_eval(arguments[1], {}))
				var move_slot: int = _as_int(_eval(arguments[2], {}))
				if not context.move_entity(move_targets[0], move_column, move_slot):
					_error("移动实体失败（位置无效或目标格不可用）", line)
		"choose_column":
			pass
		"place_environment":
			context.place_environment(
				_as_int(_eval(arguments[0], {})),
				_as_string(_eval(arguments[1], {})),
			)
		"apply_buff", "remove_buff":
			var buff_targets: Array = _resolve_argument_target(arguments[0])
			if buff_targets.size() != 1:
				_error("%s 需要单个实体目标" % primitive_name, line)
			else:
				var buff_id: String = _as_string(_eval(arguments[1], {}))
				if primitive_name == "apply_buff":
					var buff_amount: int = 1
					if arguments.size() > 2:
						buff_amount = maxi(_as_int(_eval(arguments[2], {})), 1)
					context.apply_buff(buff_targets[0], buff_id, buff_amount)
				else:
					context.remove_buff(buff_targets[0], buff_id)
		"force_attack":
			var attack_targets: Array = _resolve_argument_target(arguments[0])
			if attack_targets.size() != 1:
				_error("force_attack 需要单个实体目标", line)
			else:
				context.force_attack(attack_targets[0])
		"remove_entity":
			var remove_targets: Array = _resolve_argument_target(arguments[0])
			if remove_targets.size() != 1:
				_error("remove_entity 需要单个实体目标", line)
			else:
				context.remove_entity(remove_targets[0])
		"evolve", "base", "aura_buff", "aura_hand_cost", "aura_spell_cost", "double_death_effects":
			pass
		"put_card_on_deck_top", "put_hand_card_on_deck_top":
			var deck_targets: Array = _resolve_argument_target(arguments[0])
			var deck_filter: String = _as_string(_eval(arguments[1], {}))
			if deck_targets.size() != 1:
				_error("%s 需要单个英雄/阵营目标" % primitive_name, line)
			elif primitive_name == "put_card_on_deck_top":
				context.put_random_card_on_deck_top(deck_targets[0], deck_filter)
			else:
				context.put_hand_card_on_deck_top(deck_targets[0], deck_filter)
		"gain_max_health":
			var max_health_targets: Array = _resolve_argument_target(arguments[0])
			var max_health_delta: int = _as_int(_eval(arguments[1], {}))
			for target: Variant in max_health_targets:
				context.gain_max_health(target, max_health_delta)
		"deal_damage_each":
			var spread_targets: Array = _resolve_argument_target(arguments[0])
			var spread_amounts: Array = []
			for amount_index: int in range(1, arguments.size()):
				spread_amounts.append(_as_int(_eval(arguments[amount_index], {})))
			for target_index: int in range(spread_targets.size()):
				if spread_amounts.is_empty():
					break
				var amount_value: int = int(spread_amounts[mini(target_index, spread_amounts.size() - 1)])
				context.deal_damage(spread_targets[target_index], amount_value)
		"add_random_cards_to_deck", "add_random_cards_to_hand":
			var card_targets: Array = _resolve_argument_target(arguments[0])
			if card_targets.size() != 1:
				_error("%s 需要单个英雄/阵营目标" % primitive_name, line)
			else:
				var card_count: int = maxi(_as_int(_eval(arguments[1], {})), 0)
				var filter_text: String = _as_string(_eval(arguments[2], {}))
				var cost_delta: int = 0
				if arguments.size() > 3:
					cost_delta = _as_int(_eval(arguments[3], {}))
				var zone: String = "deck" if primitive_name == "add_random_cards_to_deck" else "hand"
				context.add_random_cards(zone, card_targets[0], card_count, filter_text, cost_delta)
		_:
			_error("未知原语：%s" % primitive_name, line)


func _exec_target_primitive(primitive_name: String, arguments: Array, line: int) -> void:
	var handles: Array = _resolve_argument_target(arguments[0])
	if handles.is_empty():
		return
	var extra_values: Array = []
	for argument_index: int in range(1, arguments.size()):
		extra_values.append(_eval(arguments[argument_index], {}))
	for handle: Variant in handles:
		if handle == null or not context.can_target(handle):
			continue
		match primitive_name:
			"deal_damage":
				context.deal_damage(handle, _as_int(extra_values[0]))
			"heal":
				context.heal(handle, _as_int(extra_values[0]))
			"gain_shield":
				context.gain_shield(handle, _as_int(extra_values[0]))
			"buff_stats":
				context.buff_stats(handle, _as_int(extra_values[0]), _as_int(extra_values[1]))
			"give_keyword":
				var keyword_value: int = 0
				if extra_values.size() > 1:
					keyword_value = _as_int(extra_values[1])
				context.give_keyword(handle, _as_string(extra_values[0]), keyword_value)
			"destroy":
				context.destroy(handle)
			_:
				_error("未知原语：%s" % primitive_name, line)


# ----- 事件 -----

func _matches_trigger(trigger: Dictionary, event_handle) -> bool:
	var predicate: Variant = trigger.get("predicate")
	if predicate == null:
		# 无过滤条件：普通实体默认只响应自己；环境/底座监听其所在列/挂载。
		return _is_self(event_handle) or (context != null and context.get_zone() in ["environment", "base"])
	if context == null:
		return false
	var facts: Dictionary = context.describe_entity(event_handle)
	facts["zone"] = context.get_zone()
	return _truthy(_eval(predicate, facts))


func _is_self(event_handle) -> bool:
	var selves: Array = context.resolve_selector("self")
	return not selves.is_empty() and selves[0] == event_handle


# ----- 表达式 -----

func _eval(expression: Variant, facts: Dictionary) -> Variant:
	if not expression is Dictionary:
		_error("表达式节点无效")
		return null
	var expression_type: String = str(expression.get("type", ""))
	match expression_type:
		"num":
			return int(expression.get("value", 0))
		"str":
			return str(expression.get("value", ""))
		"bool":
			return bool(expression.get("value", false))
		"var":
			var variable_name: String = str(expression.get("name", ""))
			if facts.has(variable_name):
				return facts[variable_name]
			if _variables.has(variable_name):
				return _variables[variable_name]
			_error("变量未定义：%s" % variable_name, _line_of(expression))
			return null
		"target":
			return _resolve_target(expression)
		"call":
			return _eval_call(expression, facts)
		"un":
			if str(expression.get("op", "")) == "not":
				return not _truthy(_eval(expression.get("value", {}), facts))
			return -_as_int(_eval(expression.get("value", {}), facts))
		"bin":
			return _eval_binary(expression, facts)
		_:
			_error("未知表达式类型：%s" % expression_type, _line_of(expression))
			return null


func _eval_call(expression: Dictionary, facts: Dictionary) -> Variant:
	var function_name: String = str(expression.get("name", ""))
	var arguments: Array = expression.get("args", [])
	match function_name:
		"attack", "health", "shield":
			var handles: Array = _resolve_argument_target(arguments[0])
			if handles.size() != 1:
				_error("查询函数 %s 需要单个目标" % function_name, _line_of(expression))
				return 0
			var entity_facts: Dictionary = context.describe_entity(handles[0])
			return _as_int(entity_facts.get(function_name, 0))
		"min":
			return mini(_as_int(_eval(arguments[0], facts)), _as_int(_eval(arguments[1], facts)))
		"max":
			return maxi(_as_int(_eval(arguments[0], facts)), _as_int(_eval(arguments[1], facts)))
		"has_tribe":
			var tribe_name: String = _as_string(_eval(arguments[0], facts))
			var tribes: Variant = facts.get("tribes", [])
			return tribes is Array and tribes.has(tribe_name)
		"marker_count":
			return context.marker_count(_as_string(_eval(arguments[0], facts)))
		"entities_in_column":
			var first_offset: int = _as_int(_eval(arguments[0], facts))
			var last_offset: int = _as_int(_eval(arguments[1], facts))
			var side_filter: String = _as_string(_eval(arguments[2], facts))
			var min_attack: int = 0
			if arguments.size() > 3:
				min_attack = _as_int(_eval(arguments[3], facts))
			return context.entities_in_column(first_offset, last_offset, side_filter, min_attack)
		"random_targets":
			var random_count: int = _as_int(_eval(arguments[0], facts))
			var random_selector: String = _as_string(_eval(arguments[1], facts))
			return context.random_targets(random_count, random_selector)
		"count_buff_in_columns":
			var count_side: String = _as_string(_eval(arguments[0], facts))
			var count_min: int = _as_int(_eval(arguments[1], facts))
			var count_max: int = _as_int(_eval(arguments[2], facts))
			var count_buff: String = _as_string(_eval(arguments[3], facts))
			return context.count_buff_in_columns(count_side, count_min, count_max, count_buff)
		_:
			_error("原语只能作为语句调用：%s" % function_name, _line_of(expression))
			return null


func _eval_binary(expression: Dictionary, facts: Dictionary) -> Variant:
	var operator: String = str(expression.get("op", ""))
	var left_expression: Variant = expression.get("left", {})
	var right_expression: Variant = expression.get("right", {})
	if operator == "and":
		return _truthy(_eval(left_expression, facts)) and _truthy(_eval(right_expression, facts))
	if operator == "or":
		return _truthy(_eval(left_expression, facts)) or _truthy(_eval(right_expression, facts))
	var left_value: Variant = _eval(left_expression, facts)
	var right_value: Variant = _eval(right_expression, facts)
	match operator:
		"+":
			if left_value is String or right_value is String:
				return _as_string(left_value) + _as_string(right_value)
			return _as_int(left_value) + _as_int(right_value)
		"-":
			return _as_int(left_value) - _as_int(right_value)
		"*":
			return _as_int(left_value) * _as_int(right_value)
		"/":
			if _as_int(right_value) == 0:
				_error("除以 0", _line_of(expression))
				return 0
			return _as_int(left_value) / _as_int(right_value)
		"==":
			return left_value == right_value
		"!=":
			return left_value != right_value
		"<", "<=", ">", ">=":
			return _compare(operator, left_value, right_value, _line_of(expression))
		_:
			_error("未知运算符：%s" % operator, _line_of(expression))
			return null


func _compare(operator: String, left_value: Variant, right_value: Variant, line: int) -> bool:
	if left_value is String and right_value is String:
		match operator:
			"<":
				return left_value < right_value
			"<=":
				return left_value <= right_value
			">":
				return left_value > right_value
			_:
				return left_value >= right_value
	if left_value is int or left_value is float or right_value is int or right_value is float:
		var left_number: float = _as_number(left_value)
		var right_number: float = _as_number(right_value)
		match operator:
			"<":
				return left_number < right_number
			"<=":
				return left_number <= right_number
			">":
				return left_number > right_number
			_:
				return left_number >= right_number
	_error("无法比较的类型", line)
	return false


func _as_int(value: Variant) -> int:
	if value == null:
		return 0
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String:
		if value.is_valid_int():
			return int(value)
		if value.is_valid_float():
			return int(float(value))
	_error("需要数字：%s" % str(value))
	return 0


func _as_number(value: Variant) -> float:
	if value == null:
		return 0.0
	if value is int or value is float:
		return float(value)
	if value is String:
		if value.is_valid_int() or value.is_valid_float():
			return float(value)
	_error("需要数字：%s" % str(value))
	return 0.0


func _as_string(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)


# ----- 目标 -----

func _resolve_argument_target(expression: Variant) -> Array:
	if expression is Dictionary and str(expression.get("type", "")) == "target":
		return _resolve_target(expression)
	var value: Variant = _eval(expression, {})
	if value == null:
		return []
	if value is Array:
		return value
	return [value]


func _resolve_target(expression: Dictionary) -> Array:
	var selector: String = str(expression.get("selector", ""))
	if selector == "chosen_if":
		var candidates: Array = context.resolve_selector("chosen")
		var predicate: Variant = expression.get("predicate")
		var filtered: Array = []
		for handle: Variant in candidates:
			var facts: Dictionary = context.describe_entity(handle)
			if _truthy(_eval(predicate, facts)):
				filtered.append(handle)
		return filtered
	return context.resolve_selector(selector)


# ----- 工具 -----

func _truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return not value.is_empty()
	if value is Array:
		return not value.is_empty()
	return value != null


func _line_of(node: Variant) -> int:
	if node is Dictionary:
		return int(node.get("line", 0))
	return 0


func _error(message: String, line: int = 0) -> void:
	if line > 0:
		errors.append("第 %d 行：%s" % [line, message])
	else:
		errors.append(message)

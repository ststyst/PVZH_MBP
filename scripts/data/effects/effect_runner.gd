class_name EffectRunner
extends RefCounted
## 能力脚本运行时：解释 AST，调用 EffectContext 的抽象原语。
## 所有运行期错误记录在 errors 里，不抛异常（避免一张卡写错导致整场战斗崩溃）。

const MAX_REPEAT: int = 100

## 目标事实的缺省值：循环里即使上下文给不出 describe_entity，条件判断也不会炸。
const DEFAULT_FACTS: Dictionary = {
	"side": "",
	"class": "",
	"tribes": [],
	"keywords": [],
	"keyword_values": {},
	"buffs": [],
	"attack": 0,
	"health": 0,
	"max_health": 0,
	"shield": 0,
	"defense": 0,
	"cost": 0,
	"column": 0,
	"column_abs": 0,
	"turn": 0,
	"entered_this_turn": false,
}

var context: EffectContext
var errors: Array[String] = []

var _variables: Dictionary = {}
## 当前表达式作用域（for_each 循环事实 / 事件过滤事实）；_eval 未显式传 facts 时使用。
var _facts: Dictionary = {}


func _init(effect_context: EffectContext) -> void:
	context = effect_context


func run_program_on_play(program: Dictionary) -> Array[String]:
	errors.clear()
	_variables.clear()
	_facts.clear()
	_exec_block(program.get("on_play", []))
	return errors


func run_program_event(program: Dictionary, event_name: String, event_handle) -> Array[String]:
	errors.clear()
	_variables.clear()
	_facts.clear()
	var triggers: Array = program.get("events", [])
	var event_facts: Dictionary = _event_facts(event_handle)
	for trigger: Dictionary in triggers:
		if str(trigger.get("event", "")) != event_name:
			continue
		if not _matches_trigger(trigger, event_handle, event_facts):
			continue
		context.set_event_target(event_handle)
		_exec_block(trigger.get("body", []), event_facts)
		context.set_event_target(null)
	return errors


## 事件作用域事实：事件目标的事实 + zone + 伤害事件相关字段。
## 这些变量在事件过滤条件和事件块里都可直接读取。
func _event_facts(event_handle) -> Dictionary:
	var facts: Dictionary = _default_facts()
	if context != null:
		var described: Dictionary = context.describe_entity(event_handle) if event_handle != null else {}
		for key: Variant in described.keys():
			facts[str(key)] = described[key]
		if not described.has("defense"):
			facts["defense"] = int(facts.get("shield", 0))
		facts["zone"] = context.get_zone()
		facts["damage_amount"] = context.get_damage_amount()
		facts["damage_source_is_entity"] = context.is_entity_handle(context.get_damage_source())
	return facts


# ----- 语句 -----

func _exec_block(block: Array, facts: Dictionary = {}) -> void:
	var previous_facts: Dictionary = _facts
	if not facts.is_empty():
		_facts = facts
	for statement: Dictionary in block:
		_exec_statement(statement)
	_facts = previous_facts


func _exec_statement(statement: Dictionary) -> void:
	var statement_type: String = str(statement.get("type", ""))
	match statement_type:
		"assign":
			var variable_name: String = str(statement.get("name", ""))
			_variables[variable_name] = _eval(statement.get("value", {}))
		"if":
			var condition: bool = _truthy(_eval(statement.get("cond", {})))
			if condition:
				_exec_block(statement.get("body", []))
			else:
				_exec_block(statement.get("else", []))
		"repeat":
			var repeat_count: int = int(_eval(statement.get("count", {})))
			repeat_count = clampi(repeat_count, 0, MAX_REPEAT)
			for _iteration: int in range(repeat_count):
				_exec_block(statement.get("body", []))
		"for_each":
			_exec_for_each(statement)
		"call":
			_exec_primitive(statement)
		_:
			_error("未知语句类型：%s" % statement_type, _line_of(statement))


## for_each：对目标数组逐个执行整个块；块内可读该目标的事实变量。
func _exec_for_each(statement: Dictionary) -> void:
	var handles: Array = _resolve_argument_target(statement.get("targets", {}))
	var loop_name: String = str(statement.get("var", "it"))
	var body: Array = statement.get("body", [])
	var had_binding: bool = _variables.has(loop_name)
	var previous_binding: Variant = _variables.get(loop_name)
	var total: int = handles.size()
	for loop_position: int in range(total):
		var handle: Variant = handles[loop_position]
		if handle == null:
			continue
		_variables[loop_name] = handle
		_exec_block(body, _loop_facts(handle, loop_position, total))
	if had_binding:
		_variables[loop_name] = previous_binding
	else:
		_variables.erase(loop_name)


## 事实缺省值（深拷贝，避免循环之间互相污染）。
func _default_facts() -> Dictionary:
	return DEFAULT_FACTS.duplicate(true)


## 目标事实 = 缺省值 + 战斗层 describe_entity 的结果；defense 是 shield 的别名。
func _entity_facts(handle) -> Dictionary:
	var facts: Dictionary = _default_facts()
	var described: Dictionary = {}
	if context != null:
		described = context.describe_entity(handle)
	for key: Variant in described.keys():
		facts[str(key)] = described[key]
	if not described.has("defense"):
		facts["defense"] = int(facts.get("shield", 0))
	return facts


## 循环事实：目标事实 + 循环位置信息。
func _loop_facts(handle, loop_position: int, total: int) -> Dictionary:
	var facts: Dictionary = _entity_facts(handle)
	facts["loop_index"] = loop_position
	facts["loop_count"] = total
	facts["loop_target"] = handle
	return facts


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
		"draw_matching_cards":
			var search_targets: Array = _resolve_argument_target(arguments[0])
			if search_targets.size() != 1:
				_error("draw_matching_cards 需要单个英雄/阵营目标", line)
			else:
				var search_count: int = maxi(_as_int(_eval(arguments[1], {})), 0)
				var search_filter: String = _as_string(_eval(arguments[2], {}))
				var search_cost: int = 0
				if arguments.size() > 3:
					search_cost = _as_int(_eval(arguments[3], {}))
				context.draw_matching_cards(search_targets[0], search_count, search_filter, search_cost)
		"gain_energy":
			context.gain_energy(_as_int(_eval(arguments[0], {})))
		"deal_damage", "heal", "gain_shield", "buff_stats", "give_keyword", "destroy":
			_exec_target_primitive(primitive_name, arguments, line)
		"environment_grant_keyword":
			context.environment_grant_keyword(
				_as_string(_eval(arguments[0], {})),
				_as_int(_eval(arguments[1], {})),
				_as_string(_eval(arguments[2], {}))
			)
		"environment_grant_keyword_persistent":
			context.environment_grant_keyword_persistent(
				_as_string(_eval(arguments[0], {})),
				_as_int(_eval(arguments[1], {})),
				_as_string(_eval(arguments[2], {}))
			)
		"transform":
			context.transform_targets(
				_resolve_argument_target(arguments[0]),
				_as_string(_eval(arguments[1], {}))
			)
		"transform_hand":
			context.transform_hand(
				_as_string(_eval(arguments[0], {})),
				_as_string(_eval(arguments[1], {})),
				_as_string(_eval(arguments[2], {}))
			)
		"environment_grant_stats":
			context.environment_grant_stats(
				_as_int(_eval(arguments[0], {})),
				_as_int(_eval(arguments[1], {})),
				_as_int(_eval(arguments[2], {})),
				_as_string(_eval(arguments[3], {}))
			)
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
		"evolve", "base", "aura_buff", "aura_hand_cost", "aura_spell_cost", "double_death_effects", "in_hand", "in_deck":
			pass
		"put_card_on_deck_top", "put_hand_card_on_deck_top":
			var deck_targets: Array = _resolve_argument_target(arguments[0])
			var deck_filter: String = _as_string(_eval(arguments[1], {}))
			if deck_targets.size() != 1:
				_error("%s 需要单个英雄/阵营目标" % primitive_name, line)
			elif primitive_name == "put_card_on_deck_top":
				var put_keyword: String = ""
				var put_attack: int = 0
				var put_health: int = 0
				var put_shield: int = 0
				if arguments.size() > 2:
					put_keyword = _as_string(_eval(arguments[2], {}))
				if arguments.size() > 3:
					put_attack = _as_int(_eval(arguments[3], {}))
				if arguments.size() > 4:
					put_health = _as_int(_eval(arguments[4], {}))
				if arguments.size() > 5:
					put_shield = _as_int(_eval(arguments[5], {}))
				var put_keyword_value: int = 0
				if arguments.size() > 6:
					put_keyword_value = _as_int(_eval(arguments[6], {}))
				context.put_random_card_on_deck_top(
					deck_targets[0], deck_filter, put_keyword, put_attack, put_health, put_shield, put_keyword_value
				)
			else:
				context.put_hand_card_on_deck_top(deck_targets[0], deck_filter)
		"shuffle_buried_positions":
			var shuffle_targets: Array = _resolve_argument_target(arguments[0])
			if shuffle_targets.size() == 1:
				context.shuffle_buried_positions(shuffle_targets[0])
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
		"damage_column_relative":
			var relative_offset: int = 0
			if arguments.size() > 2:
				relative_offset = _as_int(_eval(arguments[2], {}))
			context.damage_column_relative(
				_as_int(_eval(arguments[0], {})),
				_as_string(_eval(arguments[1], {})),
				relative_offset
			)
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
				var keyword: String = ""
				if arguments.size() > 4:
					keyword = _as_string(_eval(arguments[4], {}))
				var attack_bonus: int = 0
				var health_bonus: int = 0
				var shield_bonus: int = 0
				if arguments.size() > 5:
					attack_bonus = _as_int(_eval(arguments[5], {}))
				if arguments.size() > 6:
					health_bonus = _as_int(_eval(arguments[6], {}))
				if arguments.size() > 7:
					shield_bonus = _as_int(_eval(arguments[7], {}))
				var keyword_value: int = 0
				if arguments.size() > 8:
					keyword_value = _as_int(_eval(arguments[8], {}))
				var zone: String = "deck" if primitive_name == "add_random_cards_to_deck" else "hand"
				context.add_random_cards(
					zone, card_targets[0], card_count, filter_text, cost_delta,
					keyword, attack_bonus, health_bonus, shield_bonus, keyword_value
				)
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
		if handle == null:
			continue
		var bypass_target_check: bool = primitive_name in ["destroy", "remove_entity"]
		if primitive_name == "apply_buff" and not extra_values.is_empty():
			bypass_target_check = str(extra_values[0]) in ["bounce", "frozen_tombstone"]
		if not bypass_target_check and not context.can_target(handle):
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
			"environment_grant_keyword":
				context.environment_grant_keyword(
					_as_string(extra_values[0]),
					_as_int(extra_values[1]),
					_as_string(extra_values[2])
				)
			"destroy":
				context.destroy(handle)
			_:
				_error("未知原语：%s" % primitive_name, line)


# ----- 事件 -----

func _matches_trigger(trigger: Dictionary, event_handle, facts: Dictionary) -> bool:
	var predicate: Variant = trigger.get("predicate")
	if predicate == null:
		# 无过滤条件：普通实体默认只响应自己；环境/底座监听其所在列/挂载。
		if event_handle == null:
			return true
		return _is_self(event_handle) or (context != null and context.get_zone() in ["environment", "base", "hand", "deck"])
	if context == null:
		return false
	return _truthy(_eval(predicate, facts))


func _is_self(event_handle) -> bool:
	var selves: Array = context.resolve_selector("self")
	return not selves.is_empty() and selves[0] == event_handle


# ----- 表达式 -----

func _eval(expression: Variant, facts: Dictionary = {}) -> Variant:
	if facts.is_empty():
		facts = _facts
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
		"attack", "health", "max_health", "shield", "defense", "cost":
			var handles: Array = _resolve_argument_target(arguments[0], facts)
			if handles.size() != 1:
				_error("查询函数 %s 需要单个目标" % function_name, _line_of(expression))
				return 0
			var entity_facts: Dictionary = _entity_facts(handles[0])
			var stat_key: String = "shield" if function_name == "defense" else function_name
			return _as_int(entity_facts.get(stat_key, 0))
		"has_tribe", "has_keyword", "has_buff":
			return _eval_membership(function_name, arguments, facts, expression)
		"is_entity":
			var entity_candidates: Array = _resolve_argument_target(arguments[0], facts)
			if entity_candidates.size() != 1:
				return false
			return context != null and context.is_entity_handle(entity_candidates[0])
		"keyword_value":
			return _eval_keyword_value(arguments, facts, expression)
		"highest", "lowest":
			return _eval_extreme_targets(function_name, arguments, facts, expression)
		"entities_matching":
			return _eval_entities_matching(arguments, facts, expression)
		"min":
			return mini(_as_int(_eval(arguments[0], facts)), _as_int(_eval(arguments[1], facts)))
		"max":
			return maxi(_as_int(_eval(arguments[0], facts)), _as_int(_eval(arguments[1], facts)))
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
		"buried_in_columns":
			return context.buried_in_columns(
				_as_string(_eval(arguments[0], facts)),
				_as_int(_eval(arguments[1], facts)),
				_as_int(_eval(arguments[2], facts)),
			)
		_:
			_error("原语只能作为语句调用：%s" % function_name, _line_of(expression))
			return null


## has_tribe / has_keyword / has_buff：
## - 1 个参数：检查当前作用域目标（事件触发者 / for_each 当前目标）；
## - 2 个参数：第二个参数指定要查询的实体（可传循环变量、选择器或查询结果）。
func _eval_membership(function_name: String, arguments: Array, facts: Dictionary, expression: Dictionary) -> bool:
	var wanted: String = _as_string(_eval(arguments[0], facts))
	var probe_facts: Dictionary = facts
	if arguments.size() > 1:
		var probe_handles: Array = _resolve_argument_target(arguments[1], facts)
		if probe_handles.size() != 1:
			_error("%s 的实体参数需要单个目标" % function_name, _line_of(expression))
			return false
		probe_facts = _entity_facts(probe_handles[0])
	var list_key: String = "tribes"
	if function_name == "has_keyword":
		list_key = "keywords"
	elif function_name == "has_buff":
		list_key = "buffs"
	var values: Variant = probe_facts.get(list_key, [])
	if values is Dictionary:
		return values.has(wanted)
	return values is Array and values.has(wanted)


## keyword_value(keyword[, 实体])：读取带数值词缀的当前数值，没有该词缀返回 0。
func _eval_keyword_value(arguments: Array, facts: Dictionary, expression: Dictionary) -> int:
	var keyword_name: String = _as_string(_eval(arguments[0], facts))
	var keyword_facts: Dictionary = facts
	if arguments.size() > 1:
		var keyword_handles: Array = _resolve_argument_target(arguments[1], facts)
		if keyword_handles.size() != 1:
			_error("keyword_value 的实体参数需要单个目标", _line_of(expression))
			return 0
		keyword_facts = _entity_facts(keyword_handles[0])
	var keyword_values: Variant = keyword_facts.get("keyword_values", {})
	if keyword_values is Dictionary:
		return _as_int(keyword_values.get(keyword_name, 0))
	return 0


## entities_matching(筛选)          → 在全部在场实体里筛
## entities_matching(范围, 筛选)    → 在指定范围（选择器 / 查询结果 / 数组 / 循环变量）里筛
## 筛选语法与卡牌数据库一致（CardFilter：name/kind/rarity/class/category/
## keyword/tribe/deck_includable/cost，支持 and/or/not 与括号），
## 但判定用的是在场实体的**当前状态**（含 Buff 临时词缀、当前费用）。
func _eval_entities_matching(arguments: Array, facts: Dictionary, expression: Dictionary) -> Array:
	var line: int = _line_of(expression)
	var scope: Array = []
	var filter_text: String = ""
	if arguments.size() == 1:
		scope = context.resolve_selector("all_entities") if context != null else []
		filter_text = _as_string(_eval(arguments[0], facts))
	else:
		scope = _resolve_argument_target(arguments[0], facts)
		filter_text = _as_string(_eval(arguments[1], facts))
	filter_text = filter_text.strip_edges()
	if filter_text.is_empty():
		_error("entities_matching 需要非空的筛选条件", line)
		return []
	var filter := CardFilter.new()
	if not filter.parse(filter_text):
		_error("entities_matching 筛选条件错误：%s" % "；".join(filter.errors), line)
		return []
	var matched: Array = []
	for handle: Variant in scope:
		if handle == null:
			continue
		var values: Dictionary = context.filter_values(handle) if context != null else {}
		if values.is_empty():
			continue
		if filter.matches_values(values):
			matched.append(handle)
	return matched


## highest / lowest：在一个目标集合里按某个数值挑出最高/最低的实体。
## 可选第三个参数是**逐目标条件**：只有满足条件的候选才参与比较
## （条件里可读该目标自己的 attack/health/defense/cost/side/class/tribes/keywords 等事实）。
## 并列极值的实体会**全部**返回（结果是数组，可直接传给任何目标原语）。
## 只按数值挑选，不检查锦囊免疫等目标限制；具体原语仍会按自身规则过滤。
func _eval_extreme_targets(
	function_name: String, arguments: Array, facts: Dictionary, expression: Dictionary
) -> Array:
	var line: int = _line_of(expression)
	var handles: Array = _resolve_argument_target(arguments[0], facts)
	var stat_text: String = _as_string(_eval(arguments[1], facts))
	var stat_key: String = _normalize_stat_key(stat_text)
	if stat_key.is_empty():
		_error(
			"%s 不支持的数值：%s（可用 attack / health / max_health / defense / shield / cost）"
			% [function_name, stat_text],
			line
		)
		return []
	var predicate: Variant = null
	if arguments.size() > 2:
		predicate = arguments[2]
	var wants_lowest: bool = function_name == "lowest"
	var best_value: int = 0
	var best_handles: Array = []
	for handle: Variant in handles:
		if handle == null:
			continue
		var handle_facts: Dictionary = _entity_facts(handle)
		if predicate != null and not _truthy(_eval(predicate, handle_facts)):
			continue
		var value: int = _as_int(handle_facts.get(stat_key, 0))
		if best_handles.is_empty():
			best_value = value
			best_handles.append(handle)
			continue
		if value == best_value:
			best_handles.append(handle)
			continue
		var should_replace: bool = value < best_value if wants_lowest else value > best_value
		if should_replace:
			best_value = value
			best_handles = [handle]
	return best_handles


func _normalize_stat_key(stat_text: String) -> String:
	var key: String = stat_text.strip_edges().to_lower()
	match key:
		"attack", "atk", "攻击", "攻击力":
			return "attack"
		"health", "hp", "生命", "生命值", "当前生命":
			return "health"
		"max_health", "maxhp", "生命上限":
			return "max_health"
		"shield", "defense", "defence", "防御", "防御力", "护盾", "护甲":
			return "shield"
		"cost", "费用":
			return "cost"
	return ""


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

func _resolve_argument_target(expression: Variant, facts: Dictionary = {}) -> Array:
	if expression is Dictionary and str(expression.get("type", "")) == "target":
		return _resolve_target(expression)
	var value: Variant = _eval(expression, facts)
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
			var facts: Dictionary = _entity_facts(handle)
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

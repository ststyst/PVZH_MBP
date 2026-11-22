class_name CardEffectScript
extends RefCounted
## 一张卡牌编译后的能力脚本（语法见 docs/EffectDsl.md，采用候选 D）。
## CSV 载入时由 EffectParser 解析；语法错误记录在 errors，不阻断其他卡牌加载。
##
## 语义：
## - 锦囊（spell）：顶层语句在打出时执行一次；不允许 when 事件块。
## - 实体（entity）：能力属于召唤出来的实体，必须写在 when 事件块中（如 when enter: ...），
##   顶层语句会被判定为非法；由战斗层在该实体触发对应事件时调用 run_event()。

var on_play: Array = []
var events: Array = []
var errors: Array[String] = []
var evolve_filter_text: String = ""
var is_evolve_ability: bool = false
var is_base_ability: bool = false
var aura_buffs: Array[Dictionary] = []
var aura_hand_costs: Array[Dictionary] = []
var aura_spell_costs: Array[Dictionary] = []
var doubles_death_effects: bool = false


static func parse(source: String) -> CardEffectScript:
	var script := CardEffectScript.new()
	if source.strip_edges().is_empty():
		return script
	var parser := EffectParser.new()
	var program: Dictionary = parser.parse_program(source)
	script.on_play = program.get("on_play", [])
	script.events = program.get("events", [])
	script.errors = parser.errors
	script._extract_declarations()
	return script


## 从已编译的程序（例如编译包）直接构造，跳过解析。
static func from_program(program: Dictionary, parse_errors: Array = []) -> CardEffectScript:
	var script := CardEffectScript.new()
	script.on_play = program.get("on_play", [])
	script.events = program.get("events", [])
	for error_message: Variant in parse_errors:
		script.errors.append(str(error_message))
	script._extract_declarations()
	return script


## 供编译包序列化。
func to_program() -> Dictionary:
	return {"on_play": on_play, "events": events}


func has_errors() -> bool:
	return not errors.is_empty()


func has_effect() -> bool:
	return not on_play.is_empty() or not events.is_empty()


func _arg_value(arg: Variant) -> Variant:
	if not arg is Dictionary:
		return null
	var data: Dictionary = arg
	var arg_type: String = str(data.get("type", ""))
	if arg_type == "str" or arg_type == "num" or arg_type == "bool":
		return data.get("value", null)
	if arg_type == "var":
		return str(data.get("name", ""))
	return null


func _int_arg(arg: Variant) -> int:
	var value: Variant = _arg_value(arg)
	if value is int or value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String and value.is_valid_int():
		return int(value)
	return 0


func _bool_arg(arg: Variant) -> bool:
	var value: Variant = _arg_value(arg)
	if value is bool:
		return value
	if value is int or value is float:
		return int(value) != 0
	if value is String:
		return value.to_lower() == "true" or value == "1"
	return false


func has_event(event_name: String) -> bool:
	for trigger: Dictionary in events:
		if str(trigger.get("event", "")) == event_name:
			return true
	return false


## 检查入场事件是否声明了多目标选择（choose），供 UI/服务器生成目标需求。
## 返回 {} 或 {"count": int, "selector": String}。
func target_requirement() -> Dictionary:
	# 锦囊的多目标 choose 写在顶层；实体入场 choose 写在 when enter 内。
	var found: Dictionary = _find_choose(on_play)
	if not found.is_empty():
		return found
	for trigger: Dictionary in events:
		if str(trigger.get("event", "")) != "enter":
			continue
		found = _find_choose(trigger.get("body", []))
		if not found.is_empty():
			return found
	return {}


## 该卡是否要求玩家在打出时选择移动位置（顶层 move_entity(target) 单参数形式）。
func move_requires_position() -> bool:
	return _find_move_to_chosen_position(on_play)


## 该卡是否要求玩家在打出时选择一列。
func column_requirement() -> bool:
	return _find_call(on_play, "choose_column")


func _find_call(block: Variant, call_name: String) -> bool:
	if not block is Array:
		return false
	for statement: Variant in block:
		if not statement is Dictionary:
			continue
		var data: Dictionary = statement
		if str(data.get("type", "")) == "call" and str(data.get("name", "")) == call_name:
			return true
		for key: String in ["body", "else"]:
			if _find_call(data.get(key, []), call_name):
				return true
	return false


func _find_move_to_chosen_position(block: Variant) -> bool:
	if not block is Array:
		return false
	for statement: Variant in block:
		if not statement is Dictionary:
			continue
		var data: Dictionary = statement
		if (
			str(data.get("type", "")) == "call"
			and str(data.get("name", "")) == "move_entity"
			and (data.get("args", []) as Array).size() == 1
		):
			return true
		for key: String in ["body", "else"]:
			if _find_move_to_chosen_position(data.get(key, [])):
				return true
	return false


func _find_choose(block: Variant) -> Dictionary:
	if not block is Array:
		return {}
	for statement: Variant in block:
		if not statement is Dictionary:
			continue
		var data: Dictionary = statement
		if str(data.get("type", "")) == "call" and str(data.get("name", "")) == "choose":
			var args: Array = data.get("args", [])
			if args.size() >= 2:
				var count: int = int((args[0] as Dictionary).get("value", 0))
				var selector: String = str((args[1] as Dictionary).get("value", ""))
				return {"count": count, "selector": selector}
		for key: String in ["body", "else"]:
			var found: Dictionary = _find_choose(data.get(key, []))
			if not found.is_empty():
				return found
	return {}


## 按卡牌种类校验语义；返回错误列表。
func validate_for_kind(kind: String) -> Array[String]:
	var problems: Array[String] = []
	if kind == "entity":
		for statement: Variant in on_play:
			if not statement is Dictionary:
				continue
			var data: Dictionary = statement
			var call_name: String = str(data.get("name", ""))
			if str(data.get("type", "")) != "call" or call_name not in ["evolve", "base", "aura_buff", "aura_hand_cost", "aura_spell_cost", "double_death_effects"]:
				problems.append("实体牌顶层只允许 evolve/base/aura/double_death_effects 声明；其他能力必须写在 when 事件块中。")
				break
	elif kind == "spell" or kind == "environment":
		if is_base_ability or is_evolve_ability or not aura_buffs.is_empty() or not aura_hand_costs.is_empty() or not aura_spell_costs.is_empty() or doubles_death_effects:
			problems.append("evolve / base / aura / 双亡语只能用于实体牌，不能用于锦囊或环境牌。")
		if kind == "spell" and not events.is_empty():
			problems.append("锦囊牌不能使用 when 事件块；锦囊能力在打出时直接执行。")
		if kind == "environment" and not events.is_empty():
			problems.append("环境牌不能使用 when 事件块；环境牌能力在打出时直接执行。")
	return problems


func _extract_declarations() -> void:
	evolve_filter_text = ""
	is_evolve_ability = false
	is_base_ability = false
	aura_buffs.clear()
	aura_hand_costs.clear()
	aura_spell_costs.clear()
	doubles_death_effects = false
	for statement: Variant in on_play:
		if not statement is Dictionary:
			continue
		var data: Dictionary = statement
		if str(data.get("type", "")) != "call":
			continue
		var call_name: String = str(data.get("name", ""))
		var args: Array = data.get("args", [])
		if call_name == "base":
			is_base_ability = true
		elif call_name == "double_death_effects":
			doubles_death_effects = true
		elif call_name == "aura_buff" and args.size() >= 5:
			aura_buffs.append({
				"selector": str(_arg_value(args[0])),
				"buff": str(_arg_value(args[1])),
				"min_column": _int_arg(args[2]),
				"max_column": _int_arg(args[3]),
				"exclude_self": _bool_arg(args[4]),
			})
		elif call_name == "aura_hand_cost" and args.size() >= 3:
			aura_hand_costs.append({
				"side": str(_arg_value(args[0])),
				"filter": str(_arg_value(args[1])),
				"delta": _int_arg(args[2]),
			})
		elif call_name == "aura_spell_cost" and args.size() >= 2:
			aura_spell_costs.append({
				"side": str(_arg_value(args[0])),
				"delta": _int_arg(args[1]),
			})
		elif call_name == "evolve" and args.size() >= 1:
			is_evolve_ability = true
			var filter_node: Variant = args[0]
			if filter_node is Dictionary and str(filter_node.get("type", "")) == "str":
				evolve_filter_text = str(filter_node.get("value", ""))
			elif filter_node is Dictionary and str(filter_node.get("type", "")) == "var":
				evolve_filter_text = str(filter_node.get("name", ""))
	if not evolve_filter_text.is_empty():
		var filter := CardFilter.new()
		if not filter.parse(evolve_filter_text):
			for message: String in filter.errors:
				errors.append("进化筛选条件错误：%s" % message)


## 实体触发事件时调用；event_handle 为触发事件的实体句柄。
func run_on_play(context: EffectContext) -> Array[String]:
	if has_errors():
		return ["能力脚本存在语法错误，未执行。"]
	var runner := EffectRunner.new(context)
	return runner.run_program_on_play(_program())


## 实体触发事件时调用；event_handle 为触发事件的实体句柄。
func run_event(context: EffectContext, event_name: String, event_handle) -> Array[String]:
	if has_errors():
		return ["能力脚本存在语法错误，未执行。"]
	var runner := EffectRunner.new(context)
	return runner.run_program_event(_program(), event_name, event_handle)


func _program() -> Dictionary:
	return {"on_play": on_play, "events": events}

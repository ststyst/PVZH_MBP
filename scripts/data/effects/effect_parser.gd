class_name EffectParser
extends RefCounted
## DSL（候选 D）解析器：函数调用 + 缩进块 + 变量 + 四则运算 + 条件目标 + 事件块。
##
## 语法要点：
##   x = 2 + 3 * 2
##   deal_damage(chosen, x)
##   if attack(chosen) <= 3:
##       destroy(chosen)
##   repeat(3): deal_damage(random_enemy, 1)        # 单行块
##   when enter: gain_energy(2)                     # 单行块
##   when enter(side == 'enemy' and attack > 3):    # 事件过滤
##       deal_damage(event, 2)
##   deal_damage(chosen_if(attack <= 3), 5)
##
## 块可以用缩进（多行）或冒号后的单个语句（单行）；`;` 等价换行。

const EVENTS: Array[String] = [
	"enter",
	"die",
	"attack",
	"attacked",
	"healed",
	"attack_changed",
	"health_changed",
	"damaged",
	"turn_start",
	"turn_end",
	"ally_die",
	"position_changed",
	"buff_applied",
	"buff_removed",
	"evolved",
	"mounted",
	"extra_attack",
	"tombstone_enter",
	"tombstone_reveal",
	"hand_played",
	"ally_attack_gained",
	"transformed",
	"hand_transformed",
]
const SELECTORS: Array[String] = [
	"self",
	"event",
	"chosen",
	"hero",
	"enemy_hero",
	"all_enemies",
	"random_enemy",
	"all_allies",
	"other_allies",
	"random_ally",
	"mounted",
	"all_allies_and_hero",
	"all_entities",
	"all_heroes_and_entities",
	"enemy_entities",
	"enemy_hero_or_entities",
	"frozen_enemies",
	"injured_allies",
	"buried_entities",
	"buried_in_column",
	"all_buried",
	"random_enemy_in_column_or_hero",
]

## 原语（只能作为语句调用）
const PRIMITIVES: Dictionary = {
	"summon": {"min": 1, "max": 3},
	"draw_cards": {"min": 1, "max": 2},
	"deal_damage": {"min": 2, "max": 2},
	"heal": {"min": 2, "max": 2},
	"gain_shield": {"min": 2, "max": 2},
	"buff_stats": {"min": 3, "max": 3},
	"gain_energy": {"min": 1, "max": 1},
	"give_keyword": {"min": 2, "max": 3},
	"environment_grant_keyword": {"min": 3, "max": 3},
	"environment_grant_keyword_persistent": {"min": 3, "max": 3},
	"environment_grant_stats": {"min": 4, "max": 4},
	"transform": {"min": 2, "max": 2},
	"transform_hand": {"min": 3, "max": 3},
	"destroy": {"min": 1, "max": 1},
	"choose": {"min": 2, "max": 2},
	"gain_attack": {"min": 1, "max": 1},
	"reduce_cost": {"min": 1, "max": 1},
	"add_marker": {"min": 2, "max": 2},
	"remove_marker": {"min": 2, "max": 2},
	"move_entity": {"min": 1, "max": 3},
	"add_random_cards_to_deck": {"min": 3, "max": 9},
	"add_random_cards_to_hand": {"min": 3, "max": 9},
	"choose_column": {"min": 0, "max": 0},
	"place_environment": {"min": 2, "max": 2},
	"apply_buff": {"min": 2, "max": 3},
	"remove_buff": {"min": 2, "max": 2},
	"force_attack": {"min": 1, "max": 1},
	"remove_entity": {"min": 1, "max": 1},
	"evolve": {"min": 1, "max": 1},
	"base": {"min": 0, "max": 0},
	"gain_max_health": {"min": 2, "max": 2},
	"deal_damage_each": {"min": 2, "max": 8},
	"aura_buff": {"min": 5, "max": 5},
	"aura_hand_cost": {"min": 3, "max": 3},
	"aura_spell_cost": {"min": 2, "max": 2},
	"double_death_effects": {"min": 0, "max": 0},
	"put_card_on_deck_top": {"min": 2, "max": 7},
	"put_hand_card_on_deck_top": {"min": 2, "max": 2},
	"shuffle_buried_positions": {"min": 1, "max": 1},
	"in_hand": {"min": 0, "max": 0},
	"in_deck": {"min": 0, "max": 0},
}

## 查询函数（可以出现在表达式里）
const QUERIES: Dictionary = {
	"attack": {"min": 1, "max": 1},
	"health": {"min": 1, "max": 1},
	"shield": {"min": 1, "max": 1},
	"has_tribe": {"min": 1, "max": 1},
	"min": {"min": 2, "max": 2},
	"max": {"min": 2, "max": 2},
	"marker_count": {"min": 1, "max": 1},
	"entities_in_column": {"min": 3, "max": 4},
	"random_targets": {"min": 2, "max": 2},
	"count_buff_in_columns": {"min": 4, "max": 4},
	"buried_in_columns": {"min": 3, "max": 3},
}

var tokens: Array[Dictionary] = []
var index: int = 0
var errors: Array[String] = []


## 解析源码，返回 { "on_play": Array, "events": Array }；语法错误记录在 errors。
func parse_program(source: String) -> Dictionary:
	tokens = _tokenize(source)
	index = 0
	var on_play: Array = []
	var events: Array = []
	while not _check("EOF"):
		if _check("NEWLINE") or _check("DEDENT") or _check("INDENT"):
			_advance()
			continue
		var before: int = index
		var statement: Dictionary = _parse_statement()
		if not statement.is_empty():
			if str(statement.get("type", "")) == "event":
				events.append(statement.get("trigger", {}))
			else:
				on_play.append(statement)
		if index == before:
			_advance()
		while _check("NEWLINE"):
			_advance()
	return {"on_play": on_play, "events": events}


# ----- 语句 -----

func _parse_statement() -> Dictionary:
	var line: int = _peek_line()
	if _check_ident("if"):
		return _parse_if()
	if _check_ident("repeat"):
		return _parse_repeat()
	if _check_ident("when"):
		return _parse_when()
	# 赋值：IDENT "="
	if _check("IDENT") and _peek(1).get("type", "") == "OP" and str(_peek(1).get("value", "")) == "=":
		var variable_name: String = str(_advance().get("value", ""))
		_advance()  # =
		var value_expression: Dictionary = _parse_expression()
		return {"type": "assign", "name": variable_name, "value": value_expression, "line": line}
	var expression: Dictionary = _parse_expression()
	if str(expression.get("type", "")) != "call":
		_error("顶层语句必须是原语调用或赋值", line)
		return {}
	var call_name: String = str(expression.get("name", ""))
	if not PRIMITIVES.has(call_name):
		_error("未知原语或原语不能用作表达式：%s" % call_name, line)
		return {}
	return expression


func _parse_if() -> Dictionary:
	var line: int = _peek_line()
	_advance()  # if
	var condition: Dictionary = _parse_expression()
	_expect_op(":", line)
	var body: Array = _parse_block()
	var else_body: Array = []
	while _check("NEWLINE"):
		_advance()
	if _check_ident("else"):
		_advance()
		_expect_op(":", line)
		else_body = _parse_block()
	return {"type": "if", "cond": condition, "body": body, "else": else_body, "line": line}


func _parse_repeat() -> Dictionary:
	var line: int = _peek_line()
	_advance()  # repeat
	var count_expression: Dictionary = _parse_expression()
	_expect_op(":", line)
	var body: Array = _parse_block()
	return {"type": "repeat", "count": count_expression, "body": body, "line": line}


func _parse_when() -> Dictionary:
	var line: int = _peek_line()
	_advance()  # when
	if not _check("IDENT"):
		_error("when 后需要事件名", line)
		return {}
	var event_name: String = str(_advance().get("value", ""))
	if not EVENTS.has(event_name):
		_error("未知事件：%s（可用：%s）" % [event_name, ", ".join(EVENTS)], line)
	var predicate: Variant = null
	if _check_op("("):
		_advance()
		predicate = _parse_expression()
		_expect_op(")", line)
	_expect_op(":", line)
	var body: Array = _parse_block()
	return {
		"type": "event",
		"trigger": {"event": event_name, "predicate": predicate, "body": body, "line": line},
		"line": line,
	}


## 块：换行 + 缩进的多行块，或冒号后的单个语句。
func _parse_block() -> Array:
	if _check("NEWLINE"):
		_advance()
		if not _check("INDENT"):
			_error("冒号后需要换行缩进，或写一个单行语句", _peek_line())
			return []
		_advance()
		var body: Array = []
		while not _is_eof() and not _check("DEDENT"):
			if _check("NEWLINE"):
				_advance()
				continue
			var before: int = index
			var statement: Dictionary = _parse_statement()
			if not statement.is_empty():
				body.append(statement)
			if index == before:
				_advance()
			while _check("NEWLINE"):
				_advance()
		if _check("DEDENT"):
			_advance()
		return body
	var single: Dictionary = _parse_statement()
	if single.is_empty():
		_error("冒号后需要一个语句", _peek_line())
		return []
	return [single]


# ----- 表达式（按优先级递归下降） -----

func _parse_expression() -> Dictionary:
	return _parse_or()


func _parse_or() -> Dictionary:
	var left: Dictionary = _parse_and()
	while _check_ident("or"):
		_advance()
		var right: Dictionary = _parse_and()
		left = {"type": "bin", "op": "or", "left": left, "right": right}
	return left


func _parse_and() -> Dictionary:
	var left: Dictionary = _parse_comparison()
	while _check_ident("and"):
		_advance()
		var right: Dictionary = _parse_comparison()
		left = {"type": "bin", "op": "and", "left": left, "right": right}
	return left


func _parse_comparison() -> Dictionary:
	var left: Dictionary = _parse_additive()
	while _check("OP") and str(_peek().get("value", "")) in ["==", "!=", "<", "<=", ">", ">="]:
		var operator: String = str(_advance().get("value", ""))
		var right: Dictionary = _parse_additive()
		left = {"type": "bin", "op": operator, "left": left, "right": right}
	return left


func _parse_additive() -> Dictionary:
	var left: Dictionary = _parse_multiplicative()
	while _check("OP") and str(_peek().get("value", "")) in ["+", "-"]:
		var operator: String = str(_advance().get("value", ""))
		var right: Dictionary = _parse_multiplicative()
		left = {"type": "bin", "op": operator, "left": left, "right": right}
	return left


func _parse_multiplicative() -> Dictionary:
	var left: Dictionary = _parse_unary()
	while _check("OP") and str(_peek().get("value", "")) in ["*", "/"]:
		var operator: String = str(_advance().get("value", ""))
		var right: Dictionary = _parse_unary()
		left = {"type": "bin", "op": operator, "left": left, "right": right}
	return left


func _parse_unary() -> Dictionary:
	if _check_ident("not"):
		var line: int = _peek_line()
		_advance()
		return {"type": "un", "op": "not", "value": _parse_unary(), "line": line}
	if _check_op("-"):
		var line: int = _peek_line()
		_advance()
		return {"type": "un", "op": "neg", "value": _parse_unary(), "line": line}
	return _parse_primary()


func _parse_primary() -> Dictionary:
	var token: Dictionary = _peek()
	var line: int = int(token.get("line", 0))
	if _check("NUMBER"):
		_advance()
		return {"type": "num", "value": int(token.get("value", 0))}
	if _check("STRING"):
		_advance()
		return {"type": "str", "value": str(token.get("value", ""))}
	if _check_op("("):
		_advance()
		var inner: Dictionary = _parse_expression()
		_expect_op(")", line)
		return inner
	if _check("IDENT"):
		var name: String = str(token.get("value", ""))
		if name == "true" or name == "false":
			_advance()
			return {"type": "bool", "value": name == "true"}
		if _peek(1).get("type", "") == "OP" and str(_peek(1).get("value", "")) == "(":
			return _parse_call()
		if name == "chosen_if":
			_error("chosen_if 需要括号与条件", line)
			_advance()
			return {"type": "var", "name": name}
		if SELECTORS.has(name):
			_advance()
			return {"type": "target", "selector": name}
		_advance()
		return {"type": "var", "name": name}
	_error("无法解析的表达式", line)
	_advance()
	return {"type": "num", "value": 0}


func _parse_call() -> Dictionary:
	var line: int = _peek_line()
	var name: String = str(_advance().get("value", ""))
	_expect_op("(", line)
	var arguments: Array = []
	if not _check_op(")"):
		arguments.append(_parse_expression())
		while _check_op(","):
			_advance()
			arguments.append(_parse_expression())
	_expect_op(")", line)
	if name == "chosen_if":
		if arguments.size() != 1:
			_error("chosen_if 需要正好一个条件", line)
			return {"type": "target", "selector": "chosen", "predicate": null}
		return {"type": "target", "selector": "chosen_if", "predicate": arguments[0]}
	if not PRIMITIVES.has(name) and not QUERIES.has(name):
		_error("未知函数：%s" % name, line)
		return {"type": "call", "name": name, "args": arguments, "line": line}
	var arity: Dictionary = PRIMITIVES.get(name, QUERIES.get(name, {}))
	var minimum: int = int(arity.get("min", 0))
	var maximum: int = int(arity.get("max", 0))
	if arguments.size() < minimum or arguments.size() > maximum:
		_error("函数 %s 参数数量应为 %d–%d，实际 %d" % [name, minimum, maximum, arguments.size()], line)
	return {"type": "call", "name": name, "args": arguments, "line": line}


# ----- 词法 -----

func _tokenize(source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var indent_stack: Array[int] = [0]
	var i: int = 0
	var line: int = 1
	var text_length: int = source.length()
	var at_line_start: bool = true
	while i < text_length:
		if at_line_start:
			var indent: int = 0
			while i < text_length:
				var indent_char: String = source[i]
				if indent_char == " ":
					indent += 1
					i += 1
				elif indent_char == "\t":
					indent += 4
					i += 1
				else:
					break
			if i >= text_length:
				break
			var first_char: String = source[i]
			if first_char == "\n":
				i += 1
				line += 1
				continue
			if first_char == "#":
				while i < text_length and source[i] != "\n":
					i += 1
				continue
			if indent > indent_stack[-1]:
				indent_stack.append(indent)
				result.append({"type": "INDENT", "value": "", "line": line})
			elif indent < indent_stack[-1]:
				while indent < indent_stack[-1]:
					indent_stack.pop_back()
					result.append({"type": "DEDENT", "value": "", "line": line})
				if indent != indent_stack[-1]:
					errors.append("第 %d 行缩进不一致" % line)
			at_line_start = false
			continue
		var current_char: String = source[i]
		if current_char == " " or current_char == "\t":
			i += 1
			continue
		if current_char == "\n":
			result.append({"type": "NEWLINE", "value": "", "line": line})
			i += 1
			line += 1
			at_line_start = true
			continue
		if current_char == "#":
			while i < text_length and source[i] != "\n":
				i += 1
			continue
		if current_char == "\"" or current_char == "'":
			var quote: String = current_char
			i += 1
			var value: String = ""
			var closed: bool = false
			while i < text_length:
				var string_char: String = source[i]
				if string_char == "\\" and i + 1 < text_length:
					var escape_char: String = source[i + 1]
					match escape_char:
						"n":
							value += "\n"
						"t":
							value += "\t"
						"\\":
							value += "\\"
						"\"":
							value += "\""
						"'":
							value += "'"
						_:
							value += escape_char
					i += 2
					continue
				if string_char == quote:
					closed = true
					i += 1
					break
				value += string_char
				i += 1
			if not closed:
				errors.append("第 %d 行字符串未闭合" % line)
			result.append({"type": "STRING", "value": value, "line": line})
			continue
		if current_char >= "0" and current_char <= "9":
			var number_text: String = ""
			while i < text_length and source[i] >= "0" and source[i] <= "9":
				number_text += source[i]
				i += 1
			result.append({"type": "NUMBER", "value": int(number_text), "line": line})
			continue
		if _is_identifier_start(current_char):
			var identifier: String = ""
			while i < text_length and _is_identifier_part(source[i]):
				identifier += source[i]
				i += 1
			result.append({"type": "IDENT", "value": identifier, "line": line})
			continue
		var two_char: String = ""
		if i + 1 < text_length:
			two_char = source.substr(i, 2)
		if two_char in ["==", "!=", "<=", ">="]:
			result.append({"type": "OP", "value": two_char, "line": line})
			i += 2
			continue
		if current_char in ["+", "-", "*", "/", "(", ")", ",", ":", "=", "<", ">"]:
			result.append({"type": "OP", "value": current_char, "line": line})
			i += 1
			continue
		if current_char == ";":
			result.append({"type": "NEWLINE", "value": "", "line": line})
			i += 1
			continue
		errors.append("第 %d 行无法识别的字符：%s" % [line, current_char])
		i += 1
	if not result.is_empty() and str(result[-1].get("type", "")) != "NEWLINE":
		result.append({"type": "NEWLINE", "value": "", "line": line})
	while indent_stack.size() > 1:
		indent_stack.pop_back()
		result.append({"type": "DEDENT", "value": "", "line": line})
	result.append({"type": "EOF", "value": "", "line": line})
	return result


# ----- 工具 -----

func _token_at(offset: int) -> Dictionary:
	var target_index: int = index + offset
	if target_index < 0 or target_index >= tokens.size():
		return {"type": "EOF", "value": "", "line": 0}
	return tokens[target_index]


func _peek(offset: int = 0) -> Dictionary:
	return _token_at(offset)


func _peek_line() -> int:
	return int(_peek().get("line", 0))


func _peek_ident() -> String:
	if not _check("IDENT"):
		return ""
	return str(_peek().get("value", ""))


func _check(token_type: String) -> bool:
	return str(_peek().get("type", "")) == token_type


func _check_ident(value: String) -> bool:
	return _check("IDENT") and str(_peek().get("value", "")) == value


func _check_op(value: String) -> bool:
	return _check("OP") and str(_peek().get("value", "")) == value


func _advance() -> Dictionary:
	var token: Dictionary = _peek()
	if not _check("EOF"):
		index += 1
	return token


func _expect_op(value: String, line: int) -> void:
	if _check_op(value):
		_advance()
		return
	_error("需要 '%s'" % value, line)


func _expect_ident(value: String, line: int) -> void:
	if _check_ident(value):
		_advance()
		return
	_error("需要 '%s'" % value, line)


func _error(message: String, line: int) -> void:
	errors.append("第 %d 行：%s" % [line, message])


func _is_eof() -> bool:
	return _check("EOF")


func _is_identifier_start(character: String) -> bool:
	return (
		(character >= "a" and character <= "z")
		or (character >= "A" and character <= "Z")
		or character == "_"
	)


func _is_identifier_part(character: String) -> bool:
	return _is_identifier_start(character) or (character >= "0" and character <= "9")

class_name CardFilter
extends RefCounted
## 卡牌筛选表达式：支持 and / or / not 与括号。
##
## 示例：
##   kind == 'spell' and rarity == 'rare'
##   class == 'smarty' or class == 'guardian'
##   keyword == 'team_up' and not tribe == 'pet'
##   name == 'fireball'
##   deck_includable == false
##
## 如果没有显式写出 deck_includable 条件，匹配时自动要求卡牌可被组入牌组。

var source: String = ""
var errors: Array[String] = []
var ast: Dictionary = {}
var has_deck_includable_condition: bool = false
var name_only: String = ""

var _tokens: Array[Dictionary] = []
var _index: int = 0


func parse(text: String) -> bool:
	source = text.strip_edges()
	errors.clear()
	ast = {}
	has_deck_includable_condition = false
	name_only = ""
	_tokens = _tokenize(source)
	_index = 0
	if _tokens.is_empty():
		return true
	ast = _parse_or()
	if not errors.is_empty():
		return false
	if not _check("EOF"):
		errors.append("筛选条件末尾有多余内容：%s" % _peek().get("value", ""))
		return false
	_mark_fields(ast)
	return errors.is_empty()


func matches(card: CardData) -> bool:
	if card == null:
		return false
	return matches_values(_values_of_card(card))


## 用“卡牌字段快照”判定。战斗层借此按在场实体的**当前状态**筛选
## （例如被 Buff 临时赋予的词缀、结算后的当前费用），而不只是数据库原值。
func matches_values(values: Dictionary) -> bool:
	if not errors.is_empty():
		return false
	if not ast.is_empty() and not _eval_values(ast, values):
		return false
	if not has_deck_includable_condition and not bool(values.get("deck_includable", false)):
		return false
	return true


## 把卡牌对象转成筛选用的字段快照。
static func _values_of_card(card: CardData) -> Dictionary:
	return {
		"name": card.english_name,
		"kind": card.kind,
		"rarity": card.rarity,
		"class": card.card_class,
		"category": card.class_category,
		"keywords": card.keywords,
		"tribes": card.tribes,
		"deck_includable": card.deck_includable,
		"cost": card.cost,
	}


func _mark_fields(node: Dictionary) -> void:
	match str(node.get("type", "")):
		"and", "or":
			_mark_fields(node.get("left", {}))
			_mark_fields(node.get("right", {}))
		"not":
			_mark_fields(node.get("body", {}))
		"cond":
			var field: String = str(node.get("field", ""))
			if field == "deck_includable":
				has_deck_includable_condition = true
			if field == "name":
				name_only = str(node.get("value", ""))


func _eval_values(node: Dictionary, values: Dictionary) -> bool:
	match str(node.get("type", "")):
		"and":
			return _eval_values(node.get("left", {}), values) and _eval_values(node.get("right", {}), values)
		"or":
			return _eval_values(node.get("left", {}), values) or _eval_values(node.get("right", {}), values)
		"not":
			return not _eval_values(node.get("body", {}), values)
		"cond":
			return _match_condition_values(node, values)
	return false


func _match_condition_values(node: Dictionary, values: Dictionary) -> bool:
	var field: String = str(node.get("field", ""))
	var op: String = str(node.get("op", "=="))
	var value: String = str(node.get("value", "")).to_lower()
	var equal_op: bool = op == "==" or op == "="
	match field:
		"name":
			var actual_name: String = str(values.get("name", "")).to_lower()
			return actual_name == value if equal_op else actual_name != value
		"kind":
			var kind_match: bool = str(values.get("kind", "")).to_lower() == value
			var english_match: bool = str(values.get("name", "")).to_lower() == value
			if equal_op:
				return kind_match or english_match
			return not kind_match and not english_match
		"rarity":
			var actual_rarity: String = str(values.get("rarity", "")).to_lower()
			return actual_rarity == value if equal_op else actual_rarity != value
		"class":
			var actual_class: String = str(values.get("class", "")).to_lower()
			return actual_class == value if equal_op else actual_class != value
		"category", "class_category":
			var actual_category: String = str(values.get("category", "")).to_lower()
			return actual_category == value if equal_op else actual_category != value
		"keyword":
			var keyword_list: Array = values.get("keywords", [])
			var has_keyword: bool = keyword_list.has(value)
			return has_keyword if equal_op else not has_keyword
		"tribe":
			var tribe_list: Array = values.get("tribes", [])
			var has_tribe: bool = tribe_list.has(value)
			return has_tribe if equal_op else not has_tribe
		"deck_includable":
			var wanted: bool = value == "true" or value == "1"
			var actual_includable: bool = bool(values.get("deck_includable", false))
			if equal_op:
				return actual_includable == wanted
			return actual_includable != wanted
		"cost":
			var actual_cost: int = int(values.get("cost", 0))
			var wanted_cost: int = int(value)
			match op:
				"<":
					return actual_cost < wanted_cost
				"<=":
					return actual_cost <= wanted_cost
				">":
					return actual_cost > wanted_cost
				">=":
					return actual_cost >= wanted_cost
				"!=":
					return actual_cost != wanted_cost
				_:
					return actual_cost == wanted_cost
		_:
			return false
	return false


# ----- 词法/语法 -----

func _tokenize(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var i: int = 0
	var length: int = text.length()
	while i < length:
		var character: String = text[i]
		if character.strip_edges().is_empty():
			i += 1
			continue
		if character == "(" or character == ")":
			result.append({"type": character, "value": character})
			i += 1
			continue
		if character == "=" or character == "!" or character == "&" or character == "|" or character == "<" or character == ">":
			var two: String = text.substr(i, 2)
			if two == "==" or two == "!=" or two == "&&" or two == "||" or two == "<=" or two == ">=":
				var op: String = two
				if op == "&&":
					result.append({"type": "IDENT", "value": "and"})
					i += 2
					continue
				if op == "||":
					result.append({"type": "IDENT", "value": "or"})
					i += 2
					continue
				if op == "!=":
					op = "!="
				elif op == "<=" or op == ">=":
					op = op
				else:
					op = "=="
				result.append({"type": "OP", "value": op})
				i += 2
				continue
			if character == "<" or character == ">":
				result.append({"type": "OP", "value": character})
				i += 1
				continue
			if character == "=":
				result.append({"type": "OP", "value": "=="})
				i += 1
				continue
			if character == "!":
				result.append({"type": "IDENT", "value": "not"})
				i += 1
				continue
		if character == "\"" or character == "'":
			var quote: String = character
			i += 1
			var value: String = ""
			while i < length and text[i] != quote:
				value += text[i]
				i += 1
			i += 1
			result.append({"type": "VALUE", "value": value})
			continue
		var start: int = i
		while i < length:
			var current: String = text[i]
			if current.strip_edges().is_empty() or current in ["(", ")", "=", "!", "&", "|", "\"", "'"]:
				break
			i += 1
		var word: String = text.substr(start, i - start)
		if not word.is_empty():
			var lowered: String = word.to_lower()
			if lowered in ["and", "or", "not"]:
				result.append({"type": "IDENT", "value": lowered})
			elif lowered in ["true", "false"]:
				result.append({"type": "VALUE", "value": lowered})
			else:
				result.append({"type": "IDENT", "value": word})
	result.append({"type": "EOF", "value": ""})
	return result


func _parse_or() -> Dictionary:
	var left: Dictionary = _parse_and()
	while _check_ident("or"):
		_advance()
		var right: Dictionary = _parse_and()
		left = {"type": "or", "left": left, "right": right}
	return left


func _parse_and() -> Dictionary:
	var left: Dictionary = _parse_not()
	while _check_ident("and"):
		_advance()
		var right: Dictionary = _parse_not()
		left = {"type": "and", "left": left, "right": right}
	return left


func _parse_not() -> Dictionary:
	if _check_ident("not"):
		_advance()
		return {"type": "not", "body": _parse_not()}
	return _parse_primary()


func _parse_primary() -> Dictionary:
	if _check_type("("):
		_advance()
		var inner: Dictionary = _parse_or()
		_expect_type(")")
		return inner
	if not _check_type("IDENT"):
		errors.append("筛选条件需要字段名。")
		_advance()
		return {"type": "cond", "field": "", "op": "==", "value": ""}
	var field_token: Dictionary = _advance()
	var field: String = _normalize_field(str(field_token.get("value", "")))
	if field.is_empty():
		errors.append("未知筛选字段：%s" % field_token.get("value", ""))
	if not _check_type("OP"):
		errors.append("筛选字段后需要 == 或 !=。")
		return {"type": "cond", "field": field, "op": "==", "value": ""}
	var operator: String = str(_advance().get("value", "=="))
	if operator not in ["==", "!=", "<", "<=", ">", ">="]:
		operator = "=="
	if not _check_type("VALUE") and not _check_type("IDENT"):
		errors.append("筛选条件需要比较值。")
		return {"type": "cond", "field": field, "op": operator, "value": ""}
	var value: String = str(_advance().get("value", ""))
	return {"type": "cond", "field": field, "op": operator, "value": value}


func _normalize_field(field: String) -> String:
	match field.to_lower():
		"name", "english", "english_name", "card", "card_name":
			return "name"
		"kind", "type":
			return "kind"
		"rarity":
			return "rarity"
		"class", "class_name":
			return "class"
		"category", "class_category", "职业类别":
			return "category"
		"keyword", "keywords", "trait":
			return "keyword"
		"tribe", "tribes":
			return "tribe"
		"deck_includable", "includable":
			return "deck_includable"
		"cost", "费用":
			return "cost"
	return ""


func _check_type(type_name: String) -> bool:
	return str(_peek().get("type", "")) == type_name


func _check_ident(value: String) -> bool:
	return _check_type("IDENT") and str(_peek().get("value", "")).to_lower() == value


func _expect_type(type_name: String) -> void:
	if _check_type(type_name):
		_advance()
	else:
		errors.append("筛选条件需要 '%s'。" % type_name)


func _peek() -> Dictionary:
	if _index < 0 or _index >= _tokens.size():
		return {"type": "EOF", "value": ""}
	return _tokens[_index]


func _advance() -> Dictionary:
	var token: Dictionary = _peek()
	if _index < _tokens.size():
		_index += 1
	return token


func _check(type_name: String) -> bool:
	return _check_type(type_name)

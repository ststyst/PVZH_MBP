class_name KeywordFilter
extends RefCounted
## 环境位置词缀限制：支持 and / or / not 与括号。
## 示例：amphibious / amphibious and not frozen / (amphibious or flying) and not demon

var errors: Array[String] = []
var ast: Dictionary = {}
var _tokens: Array[String] = []
var _index: int = 0


func parse(source: String) -> bool:
	errors.clear()
	ast = {}
	_tokens = _tokenize(source)
	_index = 0
	if _tokens.is_empty():
		return true
	ast = _parse_or()
	if _index < _tokens.size():
		errors.append("词缀限制末尾有多余内容：%s" % _tokens[_index])
	return errors.is_empty()


func matches(keywords: Array) -> bool:
	if not errors.is_empty():
		return false
	if ast.is_empty():
		return true
	return _eval(ast, keywords)


func _eval(node: Dictionary, keywords: Array) -> bool:
	match str(node.get("type", "")):
		"and":
			return _eval(node.get("left", {}), keywords) and _eval(node.get("right", {}), keywords)
		"or":
			return _eval(node.get("left", {}), keywords) or _eval(node.get("right", {}), keywords)
		"not":
			return not _eval(node.get("body", {}), keywords)
		"keyword":
			return keywords.has(str(node.get("value", "")))
	return false


func _tokenize(source: String) -> Array[String]:
	var result: Array[String] = []
	var i: int = 0
	var length: int = source.length()
	while i < length:
		var character: String = source[i]
		if character.strip_edges().is_empty():
			i += 1
			continue
		if character in ["(", ")"]:
			result.append(character)
			i += 1
			continue
		var start: int = i
		while i < length:
			var current: String = source[i]
			if current.strip_edges().is_empty() or current in ["(", ")"]:
				break
			i += 1
		var word: String = source.substr(start, i - start).to_lower()
		if not word.is_empty():
			result.append(word)
	return result


func _parse_or() -> Dictionary:
	var left: Dictionary = _parse_and()
	while _peek() == "or":
		_advance()
		left = {"type": "or", "left": left, "right": _parse_and()}
	return left


func _parse_and() -> Dictionary:
	var left: Dictionary = _parse_not()
	while _peek() == "and":
		_advance()
		left = {"type": "and", "left": left, "right": _parse_not()}
	return left


func _parse_not() -> Dictionary:
	if _peek() == "not":
		_advance()
		return {"type": "not", "body": _parse_not()}
	return _parse_primary()


func _parse_primary() -> Dictionary:
	if _peek() == "(":
		_advance()
		var inner: Dictionary = _parse_or()
		if _peek() == ")":
			_advance()
		else:
			errors.append("词缀限制缺少右括号。")
		return inner
	var word: String = _peek()
	if word.is_empty():
		errors.append("词缀限制不完整。")
		return {}
	_advance()
	return {"type": "keyword", "value": word}


func _peek() -> String:
	return "" if _index >= _tokens.size() else _tokens[_index]


func _advance() -> void:
	if _index < _tokens.size():
		_index += 1

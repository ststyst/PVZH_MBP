class_name CardAnimationScript
extends RefCounted
## 卡牌动画伪代码（与能力 DSL 同样采用 when 块 + 函数调用风格）：
##
## when attack:
##     play_animation(self, "slash", "whole")
##     wait(0.3)
##     play_animation(target, "hit", "art")
## when ability:
##     play_animation(self, "skill", "whole")
## when die:
##     play_animation(self, "death", "background")
##
## 模式：whole（背景+外观+数值整体）/ background（仅背景）/ art（仅外观）。
## 动画名对应 assets/animations/<mode>.tres 中的 AnimationLibrary 动画名。

const TRIGGERS: Array[String] = ["attack", "ability", "die", "cast"]
const SELECTORS: Array[String] = ["self", "target", "global"]
const MODES: Array[String] = ["whole", "background", "art"]

var blocks: Dictionary = {}
var errors: Array[String] = []


static func parse(source: String) -> CardAnimationScript:
	var script := CardAnimationScript.new()
	if source.strip_edges().is_empty():
		return script
	var lines: PackedStringArray = source.split("\n")
	var current_trigger: String = ""
	for index: int in range(lines.size()):
		var raw_line: String = lines[index]
		var line: String = raw_line.split("#")[0].rstrip(" \t")
		if line.strip_edges().is_empty():
			continue
		var stripped: String = line.strip_edges()
		var indent: int = line.length() - line.lstrip(" \t").length()
		if stripped.begins_with("when "):
			var header: String = stripped.substr(5).strip_edges()
			var colon_index: int = header.find(":")
			var inline_text: String = ""
			if colon_index >= 0:
				inline_text = header.substr(colon_index + 1).strip_edges()
				header = header.substr(0, colon_index).strip_edges()
			if not TRIGGERS.has(header):
				script._error("未知动画触发事件：%s（可用：%s）" % [header, ", ".join(TRIGGERS)], index + 1)
				current_trigger = ""
				continue
			if script.blocks.has(header):
				script._error("重复的 when 块：%s" % header, index + 1)
			else:
				script.blocks[header] = []
			current_trigger = header
			if not inline_text.is_empty():
				for statement: String in inline_text.split(";"):
					script._parse_statement(statement.strip_edges(), header, index + 1)
			continue
		if current_trigger.is_empty():
			script._error("语句必须写在 when attack/ability/die 块内", index + 1)
			continue
		if indent <= 0:
			script._error("when 块内的语句需要缩进", index + 1)
			continue
		for statement: String in stripped.split(";"):
			script._parse_statement(statement.strip_edges(), current_trigger, index + 1)
	return script


static func from_program(program: Dictionary, parse_errors: Array = []) -> CardAnimationScript:
	var script := CardAnimationScript.new()
	var raw_blocks: Variant = program.get("blocks", {})
	if raw_blocks is Dictionary:
		for trigger: Variant in raw_blocks.keys():
			var instructions: Variant = raw_blocks[trigger]
			if instructions is Array:
				script.blocks[str(trigger)] = instructions.duplicate(true)
	for message: Variant in parse_errors:
		script.errors.append(str(message))
	return script


func to_program() -> Dictionary:
	return {"blocks": blocks.duplicate(true)}


func has_trigger(trigger: String) -> bool:
	return not instructions_for(trigger).is_empty()


func instructions_for(trigger: String) -> Array:
	var result: Array = blocks.get(trigger, [])
	return result


func has_errors() -> bool:
	return not errors.is_empty()


func is_empty() -> bool:
	for trigger: String in blocks.keys():
		if not (blocks[trigger] as Array).is_empty():
			return false
	return true


func _parse_statement(text: String, trigger: String, line: int) -> void:
	if text.is_empty():
		return
	var open_index: int = text.find("(")
	if open_index <= 0 or not text.ends_with(")"):
		_error("动画语句格式错误：%s" % text, line)
		return
	var function_name: String = text.substr(0, open_index).strip_edges()
	var args_text: String = text.substr(open_index + 1, text.length() - open_index - 2)
	var args: Array[String] = _split_args(args_text)
	match function_name:
		"play_animation":
			if args.size() < 2 or args.size() > 3:
				_error("play_animation 需要 2~3 个参数：目标、动画名、模式（可选）", line)
				return
			var selector: String = _unquote(args[0])
			if not SELECTORS.has(selector) or selector == "global":
				_error("play_animation 的目标只能是 self 或 target（global 仅用于 play_fx）", line)
				return
			var animation_name: String = _unquote(args[1])
			if animation_name.is_empty():
				_error("动画名不能为空", line)
				return
			var mode: String = _unquote(args[2]) if args.size() == 3 else "whole"
			if not MODES.has(mode):
				_error("未知动画模式：%s（可用：whole, background, art）" % mode, line)
				return
			(blocks[trigger] as Array).append({
				"type": "play_animation",
				"target": selector,
				"animation": animation_name,
				"mode": mode,
				"line": line,
			})
		"wait":
			if args.size() != 1:
				_error("wait 需要 1 个参数（秒）", line)
				return
			var seconds_text: String = _unquote(args[0])
			if not seconds_text.is_valid_float():
				_error("wait 参数必须是数字", line)
				return
			(blocks[trigger] as Array).append({
				"type": "wait",
				"seconds": maxf(float(seconds_text), 0.0),
				"line": line,
			})
		"play_fx":
			if args.size() != 2:
				_error("play_fx 需要 2 个参数：目标、特效名", line)
				return
			var selector: String = _unquote(args[0])
			if not SELECTORS.has(selector):
				_error("未知特效目标：%s（可用：self, target, global）" % selector, line)
				return
			var fx_name: String = _unquote(args[1])
			if fx_name.is_empty():
				_error("特效名不能为空", line)
				return
			(blocks[trigger] as Array).append({
				"type": "play_fx",
				"target": selector,
				"fx": fx_name,
				"line": line,
			})
		_:
			_error("未知动画函数：%s" % function_name, line)


static func _split_args(text: String) -> Array[String]:
	var result: Array[String] = []
	var current: String = ""
	var quote: String = ""
	for character: String in text:
		if not quote.is_empty():
			if character == quote:
				quote = ""
			current += character
			continue
		if character == "\"" or character == "'":
			quote = character
			current += character
		elif character == ",":
			result.append(current.strip_edges())
			current = ""
		else:
			current += character
	if not current.strip_edges().is_empty() or not result.is_empty():
		result.append(current.strip_edges())
	return result


static func _unquote(text: String) -> String:
	var value: String = text.strip_edges()
	if value.length() >= 2:
		if (value.begins_with("\"") and value.ends_with("\"")) or (value.begins_with("'") and value.ends_with("'")):
			return value.substr(1, value.length() - 2)
	return value


func _error(message: String, line: int) -> void:
	errors.append("第 %d 行：%s" % [line, message])

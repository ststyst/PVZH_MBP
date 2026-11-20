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


static func parse(source: String) -> CardEffectScript:
	var script := CardEffectScript.new()
	if source.strip_edges().is_empty():
		return script
	var parser := EffectParser.new()
	var program: Dictionary = parser.parse_program(source)
	script.on_play = program.get("on_play", [])
	script.events = program.get("events", [])
	script.errors = parser.errors
	return script


## 从已编译的程序（例如编译包）直接构造，跳过解析。
static func from_program(program: Dictionary, parse_errors: Array = []) -> CardEffectScript:
	var script := CardEffectScript.new()
	script.on_play = program.get("on_play", [])
	script.events = program.get("events", [])
	for error_message: Variant in parse_errors:
		script.errors.append(str(error_message))
	return script


## 供编译包序列化。
func to_program() -> Dictionary:
	return {"on_play": on_play, "events": events}


func has_errors() -> bool:
	return not errors.is_empty()


func has_effect() -> bool:
	return not on_play.is_empty() or not events.is_empty()


## 按卡牌种类校验语义；返回错误列表。
func validate_for_kind(kind: String) -> Array[String]:
	var problems: Array[String] = []
	if kind == "entity" and not on_play.is_empty():
		problems.append("实体牌的能力必须写在 when 事件块中（例如 when enter: ...），不能有打出时直接执行的语句。")
	if kind == "spell" and not events.is_empty():
		problems.append("锦囊牌不能使用 when 事件块；锦囊能力在打出时直接执行。")
	return problems


## 打出锦囊时执行顶层语句；返回运行期错误。
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

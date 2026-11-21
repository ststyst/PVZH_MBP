@tool
extends McpTestSuite
## 卡牌动画伪代码解析测试。suite = "animation"。

func suite_name() -> String:
	return "animation"


func test_parse_triggers_and_modes() -> void:
	var source: String = """
when attack:
    play_animation(self, "slash", "whole")
    wait(0.3)
    play_animation(target, "hit", "art")
when ability:
    play_animation(self, "skill", "background")
when die:
    play_animation(self, "death")
"""
	var script: CardAnimationScript = CardAnimationScript.parse(source)
	assert_eq(script.errors.size(), 0, "动画语法应通过：%s" % [script.errors])
	assert_true(script.has_trigger("attack"))
	assert_true(script.has_trigger("ability"))
	assert_true(script.has_trigger("die"))
	var attack: Array = script.instructions_for("attack")
	assert_eq(attack.size(), 3)
	assert_eq(str(attack[0].get("type", "")), "play_animation")
	assert_eq(str(attack[0].get("target", "")), "self")
	assert_eq(str(attack[0].get("animation", "")), "slash")
	assert_eq(str(attack[0].get("mode", "")), "whole")
	assert_eq(str(attack[1].get("type", "")), "wait")
	assert_eq(float(attack[1].get("seconds", 0.0)), 0.3)
	assert_eq(str(attack[2].get("target", "")), "target")
	assert_eq(str(attack[2].get("mode", "")), "art")
	var die: Array = script.instructions_for("die")
	assert_eq(str(die[0].get("mode", "")), "whole", "省略模式默认 whole")


func test_inline_blocks() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when attack: play_animation(self, \"a\"); wait(0.1)\nwhen die: play_animation(self, \"b\", \"background\")"
	)
	assert_eq(script.errors.size(), 0, "单行块应通过：%s" % [script.errors])
	assert_eq(script.instructions_for("attack").size(), 2)
	assert_eq(script.instructions_for("die").size(), 1)


func test_invalid_animation_reports_errors() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when nope:\n    play_animation(self, \"a\")\nwhen attack:\n    play_animation(enemy, \"a\", \"whole\")\n    play_animation(self, \"a\", \"sprite\")\n    wait(\"x\")"
	)
	assert_true(script.errors.size() >= 3, "应报告事件/目标/模式/等待参数错误：%s" % [script.errors])


func test_program_roundtrip() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when attack:\n    play_animation(self, \"slash\", \"whole\")"
	)
	var restored: CardAnimationScript = CardAnimationScript.from_program(script.to_program())
	assert_true(restored.has_trigger("attack"))
	assert_eq(str(restored.instructions_for("attack")[0].get("animation", "")), "slash")

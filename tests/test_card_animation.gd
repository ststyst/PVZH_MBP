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


func test_cast_and_global_fx() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when cast:\n    play_animation(self, \"cast\", \"whole\")\n    play_fx(global, \"explosion\")"
	)
	assert_eq(script.errors.size(), 0, "cast/global 应通过：%s" % [script.errors])
	assert_true(script.has_trigger("cast"))
	var instructions: Array = script.instructions_for("cast")
	assert_eq(str(instructions[1].get("type", "")), "play_fx")
	assert_eq(str(instructions[1].get("target", "")), "global")


func test_global_is_rejected_for_entity_animation() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when attack:\n    play_animation(global, \"a\", \"whole\")"
	)
	assert_true(script.errors.size() >= 1, "play_animation(global) 应报错")


func test_move_primitives() -> void:
	# 攻击时扑到目标身上再回来：位置由播放时解析，动画资源里不烘焙坐标。
	var source: String = """
when attack:
    move_to(target, 0.12)
    play_animation(self, "slash", "art")
    play_animation(target, "hit", "art")
    wait(0.18)
    move_back(0.12)
"""
	var script: CardAnimationScript = CardAnimationScript.parse(source)
	assert_eq(script.errors.size(), 0, "move_to/move_back 应通过：%s" % [script.errors])
	var attack: Array = script.instructions_for("attack")
	assert_eq(attack.size(), 5)
	assert_eq(str(attack[0].get("type", "")), "move_to")
	assert_eq(str(attack[0].get("target", "")), "target")
	assert_eq(float(attack[0].get("seconds", 0.0)), 0.12)
	assert_eq(float(attack[0].get("offset_x", 1.0)), 0.0, "省略偏移时为 0")
	assert_eq(float(attack[0].get("offset_y", 1.0)), 0.0, "省略偏移时为 0")
	assert_eq(
		str(attack[0].get("easing", "")),
		CardAnimationScript.MOVE_TO_DEFAULT_EASING,
		"move_to 默认缓动 ease_in"
	)
	assert_eq(str(attack[1].get("type", "")), "play_animation")
	assert_eq(str(attack[4].get("type", "")), "move_back")
	assert_eq(float(attack[4].get("seconds", 0.0)), 0.12)
	assert_eq(
		str(attack[4].get("easing", "")),
		CardAnimationScript.MOVE_BACK_DEFAULT_EASING,
		"move_back 默认缓动 ease_out"
	)
	# 存取往返后位移指令仍然保留（编译器会写进 .cardpack）。
	var restored: CardAnimationScript = CardAnimationScript.from_program(script.to_program())
	var restored_attack: Array = restored.instructions_for("attack")
	assert_eq(str(restored_attack[0].get("type", "")), "move_to")
	assert_eq(str(restored_attack[4].get("type", "")), "move_back")


func test_move_offset_and_easing() -> void:
	# 偏移 + 缓动：扑过去但不糊住目标，用缓动制造冲击力。
	var source: String = """
when attack:
    move_to(target, 0.12, -18, -10, "back_out")
    wait(0.1)
    move_back(0.12, "bounce_out")
"""
	var script: CardAnimationScript = CardAnimationScript.parse(source)
	assert_eq(script.errors.size(), 0, "偏移/缓动应通过：%s" % [script.errors])
	var attack: Array = script.instructions_for("attack")
	assert_eq(float(attack[0].get("offset_x", 0.0)), -18.0)
	assert_eq(float(attack[0].get("offset_y", 0.0)), -10.0)
	assert_eq(str(attack[0].get("easing", "")), "back_out")
	assert_eq(float(attack[2].get("seconds", 0.0)), 0.12)
	assert_eq(str(attack[2].get("easing", "")), "bounce_out")
	# 只给缓动、不给偏移也允许。
	var only_easing: CardAnimationScript = CardAnimationScript.parse(
		"when attack:\n    move_to(target, 0.1, \"linear\")"
	)
	assert_eq(only_easing.errors.size(), 0, "第三参给缓动应通过：%s" % [only_easing.errors])
	var instruction: Dictionary = only_easing.instructions_for("attack")[0]
	assert_eq(str(instruction.get("easing", "")), "linear")
	assert_eq(float(instruction.get("offset_x", 1.0)), 0.0)


func test_move_errors() -> void:
	var script: CardAnimationScript = CardAnimationScript.parse(
		"when attack:\n"
		+ "    move_to(self, 0.1)\n"
		+ "    move_to(target)\n"
		+ "    move_to(target, \"快的\")\n"
		+ "    move_to(target, 0.1, 5)\n"
		+ "    move_to(target, 0.1, 5, \"x\")\n"
		+ "    move_to(target, 0.1, 5, 5, \"teleport\")\n"
		+ "    move_back(0.1, 0.2)\n"
		+ "    move_back()\n"
		+ "    move_back(0.1, \"teleport\")"
	)
	assert_eq(script.errors.size(), 9, "九个非法位移语句都应报错：%s" % [script.errors])
	assert_true(script.instructions_for("attack").is_empty(), "报错的语句不应进入指令表")

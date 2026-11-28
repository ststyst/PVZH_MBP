@tool
extends McpTestSuite
## 数值涨跌配色规则测试（StatColors）。suite = "stat_colors"。

func suite_name() -> String:
	return "stat_colors"


func test_compare_higher_is_better() -> void:
	# 攻击 / 生命：越高越好。
	assert_true(StatColors.compare(3, 2, true) == StatColors.BUFFED, "更高应显示绿色")
	assert_true(StatColors.compare(2, 2, true) == StatColors.NORMAL, "相等应显示白色")
	assert_true(StatColors.compare(1, 2, true) == StatColors.DEBUFFED, "更低应显示红色")


func test_compare_lower_is_better() -> void:
	# 费用：越低越好。
	assert_true(StatColors.compare(1, 2, false) == StatColors.BUFFED, "费用更低应显示绿色")
	assert_true(StatColors.compare(2, 2, false) == StatColors.NORMAL, "费用相等应显示白色")
	assert_true(StatColors.compare(3, 2, false) == StatColors.DEBUFFED, "费用更高应显示红色")


func test_entity_health_rule() -> void:
	# 受伤（低于当前生命上限）优先红。
	assert_true(StatColors.health(7, 10, 5) == StatColors.DEBUFFED, "已受伤应显示红色")
	# 满血且高于数据库初始生命 → 绿。
	assert_true(StatColors.health(10, 10, 5) == StatColors.BUFFED, "满血且高于初始生命应显示绿色")
	# 满血且等于数据库初始生命 → 白。
	assert_true(StatColors.health(5, 5, 5) == StatColors.NORMAL, "满血且等于初始生命应显示白色")
	# 上限被削到与生命相等（3/3）→ 按数据库比较（3 < 5）→ 白。
	assert_true(StatColors.health(3, 3, 5) == StatColors.NORMAL, "未受伤但上限被削时按数据库比较")
	# 上限被削但仍有伤 → 红。
	assert_true(StatColors.health(2, 3, 5) == StatColors.DEBUFFED, "上限被削且受伤仍是红色")


func test_colors_are_distinct() -> void:
	assert_true(StatColors.BUFFED != StatColors.NORMAL, "绿色与白色不能相同")
	assert_true(StatColors.DEBUFFED != StatColors.NORMAL, "红色与白色不能相同")
	assert_true(StatColors.BUFFED != StatColors.DEBUFFED, "绿色与红色不能相同")

extends SceneTree
## 无编辑器测试入口：不打开编辑器也能跑 res://tests/test_*.gd 里的 McpTestSuite。
##
## 用法：
##   godot --headless --path <工程目录> --script res://tests/run_tests.gd
##
## 退出码：0 全部通过；1 有失败。

const TEST_SCRIPTS: Array[String] = [
	"res://tests/test_deck_data.gd",
	"res://tests/test_player_profile.gd",
	"res://tests/test_save_manager.gd",
	"res://tests/test_app_storage.gd",
	"res://tests/test_card_database.gd",
	"res://tests/test_hero_database.gd",
	"res://tests/test_mode_config.gd",
	"res://tests/test_server_config.gd",
	"res://tests/test_collection_manager.gd",
	"res://tests/test_deck_rules.gd",
	"res://tests/test_battle_engine.gd",
	"res://tests/test_combat_stepping.gd",
	"res://tests/test_recommended_decks.gd",
	"res://tests/test_effect_parser.gd",
	"res://tests/test_effect_runner.gd",
	"res://tests/test_card_animation.gd",
	"res://tests/test_battle_net.gd",
	"res://tests/test_card_set_compiler.gd",
	"res://tests/test_display_service.gd",
]


func _initialize() -> void:
	var total_tests: int = 0
	var failed_tests: int = 0
	var empty_tests: int = 0
	var total_assertions: int = 0
	for script_path: String in TEST_SCRIPTS:
		var script: GDScript = load(script_path) as GDScript
		if script == null:
			printerr("无法加载测试脚本：%s" % script_path)
			failed_tests += 1
			continue
		var suite: McpTestSuite = script.new() as McpTestSuite
		if suite == null:
			printerr("无法实例化测试套件：%s" % script_path)
			failed_tests += 1
			continue
		var current_suite_name: String = suite.suite_name()
		suite.suite_setup({})
		if suite._suite_failed:
			printerr("[%s] 套件初始化失败：%s" % [current_suite_name, suite._suite_failed_message])
			failed_tests += 1
			continue
		for method_info: Dictionary in suite.get_method_list():
			var method_name: String = str(method_info.get("name", ""))
			if not method_name.begins_with("test_"):
				continue
			suite._reset()
			suite.setup()
			suite.call(method_name)
			suite.teardown()
			total_tests += 1
			total_assertions += suite._assertion_count
			if suite._failed:
				failed_tests += 1
				printerr("[%s] %s 失败：%s" % [current_suite_name, method_name, suite._message])
			elif suite._assertion_count == 0:
				# 空跑守卫：一条断言都没执行，通常意味着 setup() 里 new()/初始化报错后
				# 用例静默中断（历史上因此让整个 effect_runner 套件空跑过 26 小时）。
				empty_tests += 1
				failed_tests += 1
				printerr(
					"[%s] %s 空跑：0 条断言（检查 setup() 是否报错、或用例是否漏写断言）"
					% [current_suite_name, method_name]
				)
			else:
				print("[%s] %s 通过（%d 断言）" % [current_suite_name, method_name, suite._assertion_count])
		suite.suite_teardown()
	print(
		"测试完成：%d 个用例，%d 个断言，%d 个失败（其中空跑 %d）"
		% [total_tests, total_assertions, failed_tests, empty_tests]
	)
	quit(1 if failed_tests > 0 else 0)

extends SceneTree
## 开发辅助脚本：在游戏/编辑器之外预置一个演示用本地存档，便于手动与自动化走查。
##
## 用法（不进入游戏，直接跑完退出）：
##   godot --headless --path <工程目录> --script res://tests/prepare_demo_save.gd -- 测试玩家
##
## 注意：这不是测试用例（不会被 MCP test_run 收录），只创建存档、不删除。

const SaveManagerScript := preload("res://scripts/core/save_manager.gd")


func _initialize() -> void:
	var display_name: String = "测试玩家"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		display_name = args[0]
	var manager: Node = SaveManagerScript.new()
	var slot_key: String = manager.create_slot(display_name)
	manager.free()
	if slot_key.is_empty():
		printerr("创建演示存档失败")
		quit(1)
		return
	print("已创建演示存档：%s（%s）" % [slot_key, display_name])
	quit(0)

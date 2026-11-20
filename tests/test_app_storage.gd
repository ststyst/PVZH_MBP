@tool
extends McpTestSuite
## 全局本地数据（最近存档 / 服务器登录信息 / 主音量）测试。suite = "storage"。
## 测试会临时改写 user://global.json，结束时会还原。

const AppStorageScript := preload("res://scripts/core/app_storage.gd")

var storage: Node = null
var cache_path: String = ""
var original_text: String = ""
var existed_before: bool = false


func suite_name() -> String:
	return "storage"


func setup() -> void:
	cache_path = AppStorageScript.FILE_PATH
	existed_before = FileAccess.file_exists(cache_path)
	original_text = ""
	if existed_before:
		original_text = FileAccess.get_file_as_string(cache_path)
	storage = AppStorageScript.new()
	storage.load_data()


func teardown() -> void:
	if is_instance_valid(storage):
		storage.free()
	storage = null
	if existed_before:
		var file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
		if file != null:
			file.store_string(original_text)
			file.close()
	elif FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, false)
		AudioServer.set_bus_volume_db(bus_index, 0.0)


func test_last_slot_key_roundtrip() -> void:
	storage.set_last_slot_key("slot_test_1")
	assert_eq(storage.get_last_slot_key(), "slot_test_1")
	storage.load_data()
	assert_eq(storage.get_last_slot_key(), "slot_test_1", "重新加载后应保持最近存档")


func test_server_login_roundtrip() -> void:
	storage.set_server_login("10.0.0.9", "acc1", true)
	var info: Dictionary = storage.get_server_login()
	assert_eq(str(info.get("ip", "")), "10.0.0.9")
	assert_eq(str(info.get("account", "")), "acc1")
	assert_true(bool(info.get("remember", false)))
	storage.set_server_login("", "", false)
	var cleared: Dictionary = storage.get_server_login()
	assert_eq(str(cleared.get("ip", "")), "")
	assert_false(bool(cleared.get("remember", false)))


func test_master_volume_clamped() -> void:
	storage.set_master_volume(1.7)
	assert_eq(storage.get_master_volume(), 1.0)
	storage.set_master_volume(-0.5)
	assert_eq(storage.get_master_volume(), 0.0)
	storage.set_master_volume(0.5)
	assert_eq(storage.get_master_volume(), 0.5)

@tool
extends McpTestSuite
## 本地存档与服务器缓存测试。运行方式：MCP test_run（suite = "save"）或 tests/run_tests.gd。

const SaveManagerScript := preload("res://scripts/core/save_manager.gd")

var manager: Node = null
var created_slots: Array[String] = []
var original_server_cache: String = ""
var server_cache_existed: bool = false


func suite_name() -> String:
	return "save"


func setup() -> void:
	manager = SaveManagerScript.new()
	_cleanup_slots()
	server_cache_existed = FileAccess.file_exists(SaveManagerScript.SERVER_CACHE_FILE)
	original_server_cache = ""
	if server_cache_existed:
		original_server_cache = FileAccess.get_file_as_string(SaveManagerScript.SERVER_CACHE_FILE)


func teardown() -> void:
	_cleanup_slots()
	_restore_server_cache()
	if is_instance_valid(manager):
		manager.free()
	manager = null


## 测试会写 user://server_cache.json，结束时要还原，避免污染真实游戏数据。
func _restore_server_cache() -> void:
	var cache_path: String = SaveManagerScript.SERVER_CACHE_FILE
	if server_cache_existed:
		var file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
		if file != null:
			file.store_string(original_server_cache)
			file.close()
	elif FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)


func _cleanup_slots() -> void:
	for slot_key: String in created_slots:
		manager.delete_slot(slot_key)
	created_slots.clear()


func test_create_and_load_slot() -> void:
	var slot_key: String = manager.create_slot("测试玩家")
	assert_ne(slot_key, "", "create_slot 应返回非空 slot_key")
	if slot_key.is_empty():
		return
	created_slots.append(slot_key)
	var profile: PlayerProfile = manager.load_slot(slot_key)
	assert_true(profile != null, "load_slot 应能读回刚创建的存档")
	if profile == null:
		return
	assert_eq(profile.player_name, "测试玩家")
	assert_true(profile.created_at_unix > 0, "created_at_unix 应写入")
	assert_true(profile.schema_version > 0, "schema_version 应写入")


func test_list_slots_contains_created_slot() -> void:
	var slot_key: String = manager.create_slot("列表测试")
	assert_ne(slot_key, "", "create_slot 应成功")
	if slot_key.is_empty():
		return
	created_slots.append(slot_key)
	var slots: Array[SaveSlotInfo] = manager.list_slots()
	var found: bool = false
	for slot: SaveSlotInfo in slots:
		if slot.slot_key == slot_key:
			found = true
			assert_eq(slot.player_name, "列表测试")
	assert_true(found, "list_slots 应包含新建存档")


func test_profile_roundtrip() -> void:
	var slot_key: String = manager.create_slot("往返测试")
	assert_ne(slot_key, "", "create_slot 应成功")
	if slot_key.is_empty():
		return
	created_slots.append(slot_key)
	var profile: PlayerProfile = manager.load_slot(slot_key)
	assert_true(profile != null, "load_slot 应成功")
	if profile == null:
		return
	profile.gold = 777
	profile.arcane_dust = 55
	profile.add_card("test_card", 3)
	var deck: DeckData = profile.create_deck("测试牌组")
	assert_true(deck.add_card("test_card"))
	assert_true(deck.add_card("test_card"))
	assert_true(manager.save_slot(slot_key, profile), "save_slot 应成功")
	var reloaded: PlayerProfile = manager.load_slot(slot_key)
	assert_true(reloaded != null, "重新读取应成功")
	if reloaded == null:
		return
	assert_eq(reloaded.gold, 777)
	assert_eq(reloaded.arcane_dust, 55)
	assert_eq(reloaded.get_card_count("test_card"), 3)
	assert_eq(reloaded.decks.size(), 1)
	assert_eq(reloaded.decks[0].card_ids.size(), 2)
	assert_eq(reloaded.decks[0].deck_name, "测试牌组")


func test_delete_slot() -> void:
	var slot_key: String = manager.create_slot("待删除")
	assert_ne(slot_key, "", "create_slot 应成功")
	if slot_key.is_empty():
		return
	assert_true(manager.delete_slot(slot_key), "delete_slot 应成功")
	assert_true(manager.load_slot(slot_key) == null, "删除后不应再读到存档")


func test_recent_server_cache() -> void:
	manager.remember_server("192.168.1.10", 45770, "tester", "")
	var servers: Array[Dictionary] = manager.load_recent_servers()
	assert_true(servers.size() >= 1, "应能在服务器缓存中读到条目")
	if servers.is_empty():
		return
	var newest: Dictionary = servers[0]
	assert_eq(str(newest.get("address", "")), "192.168.1.10")
	assert_eq(int(newest.get("port", 0)), 45770)
	assert_eq(str(newest.get("password", "")), "", "未勾选记住密码时不应落盘密码")

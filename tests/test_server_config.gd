@tool
extends McpTestSuite
## 服务器/运行优化配置测试。suite = "server_config"。

const TEMP_PATH: String = "user://test_server_config.json"


func suite_name() -> String:
	return "server_config"


func teardown() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_default_server_config() -> void:
	var data: Dictionary = ServerConfig.load_config()
	assert_true(not data.is_empty(), "应能读取 data/server/server_config.json")
	var match_config: Dictionary = data.get("match", {})
	assert_eq(float(match_config.get("team_up_swap_cooldown_seconds", 0.0)), 0.35)
	var protocol: Dictionary = data.get("protocol", {})
	assert_false(bool(protocol.get("allow_mods", true)))
	assert_true(data.has("network") and data.has("security") and data.has("logging"))


func test_swap_cooldown_reads_match_section() -> void:
	var file: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	assert_true(file != null)
	if file != null:
		file.store_string(JSON.stringify({
			"match": {"team_up_swap_cooldown_seconds": 1.2},
		}))
		file.close()
	assert_eq(ServerConfig.swap_cooldown_seconds(TEMP_PATH), 1.2)
	assert_eq(ServerConfig.swap_cooldown_seconds("user://missing_server_config.json"), 0.35)

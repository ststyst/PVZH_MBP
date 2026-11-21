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
	assert_true(match_config.has("command_rate_limit_per_second"))
	assert_true(match_config.has("effect_resolution_limit"))
	var protocol: Dictionary = data.get("protocol", {})
	assert_false(bool(protocol.get("allow_mods", true)))
	assert_true(data.has("network") and data.has("security") and data.has("logging"))


func test_config_file_missing_falls_back_to_empty() -> void:
	assert_true(ServerConfig.load_config("user://missing_server_config.json").is_empty())

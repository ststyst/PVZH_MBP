class_name ServerConfig
extends RefCounted
## 服务器/运行优化配置（data/server/server_config.json）。
##
## 当前所有字段均为预留；换位相关冷却已随手动换位功能移除。

const DEFAULT_PATH: String = "res://data/server/server_config.json"


## 读取原始配置字典；文件不存在/解析失败时返回空字典。
static func load_config(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var error: Error = json.parse(FileAccess.get_file_as_string(path))
	if error != OK or not json.data is Dictionary:
		return {}
	return json.data

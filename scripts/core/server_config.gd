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


## 单次出牌/战斗行为允许连锁结算的最大事件数；超限后强制结束本次连锁。
static func effect_resolution_limit(path: String = DEFAULT_PATH) -> int:
	var data: Dictionary = load_config(path)
	var match_config: Variant = data.get("match", {})
	if match_config is Dictionary:
		var raw: Variant = (match_config as Dictionary).get("effect_resolution_limit", 100)
		if raw is int or raw is float:
			return maxi(int(raw), 1)
		if raw is String and raw.is_valid_int():
			return maxi(int(raw), 1)
	return 100


## 不能被环境牌覆盖的环境 id；默认高地和水池。
static func protected_environments(path: String = DEFAULT_PATH) -> Array[String]:
	var data: Dictionary = load_config(path)
	var result: Array[String] = ["highground", "water"]
	var match_config: Variant = data.get("match", {})
	if match_config is Dictionary:
		var raw: Variant = (match_config as Dictionary).get("protected_environments", null)
		if raw is Array:
			result.clear()
			for item: Variant in raw:
				result.append(str(item))
	return result


## 环境 id -> 词缀限制表达式。默认水池要求两栖。
static func environment_keyword_filters(path: String = DEFAULT_PATH) -> Dictionary:
	var result: Dictionary = {"water": "amphibious"}
	var data: Dictionary = load_config(path)
	var match_config: Variant = data.get("match", {})
	if match_config is Dictionary:
		var raw: Variant = (match_config as Dictionary).get("environment_keyword_filters", null)
		if raw is Dictionary:
			result.clear()
			for environment_id: Variant in raw.keys():
				var value: Variant = (raw as Dictionary)[environment_id]
				if value is Array:
					var parts: Array[String] = []
					for keyword_id: Variant in value:
						parts.append(str(keyword_id))
					result[str(environment_id)] = " and ".join(parts)
				else:
					result[str(environment_id)] = str(value)
	return result

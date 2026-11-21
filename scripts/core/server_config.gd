class_name ServerConfig
extends RefCounted
## 服务器/运行优化配置（data/server/server_config.json）。
##
## 目前只实现 `match.team_up_swap_cooldown_seconds` 的读取；
## 其余字段是预留配置项，暂不提供代码接口，避免过早固化联机协议。

const DEFAULT_PATH: String = "res://data/server/server_config.json"
const DEFAULT_SWAP_COOLDOWN_SECONDS: float = 0.35


## 读取原始配置字典；文件不存在/解析失败时返回空字典。
static func load_config(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var error: Error = json.parse(FileAccess.get_file_as_string(path))
	if error != OK or not json.data is Dictionary:
		return {}
	return json.data


static func swap_cooldown_seconds(path: String = DEFAULT_PATH) -> float:
	var data: Dictionary = load_config(path)
	var match_config: Variant = data.get("match", {})
	if match_config is Dictionary:
		var raw: Variant = (match_config as Dictionary).get("team_up_swap_cooldown_seconds", null)
		if raw is float or raw is int:
			return maxf(float(raw), 0.0)
		if raw is String and (raw.is_valid_float() or raw.is_valid_int()):
			return maxf(float(raw), 0.0)
	return DEFAULT_SWAP_COOLDOWN_SECONDS

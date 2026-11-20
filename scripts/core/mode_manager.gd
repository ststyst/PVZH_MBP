extends Node
## 当前玩法配置：默认读取 res://data/modes/default_mode.json。
## 服务器/单机可在 user://modes/default_mode.json 放一份覆盖；也支持运行时加载任意玩法文件。
## 未配置任何玩法文件时全部使用 GameModeConfig 的内置默认值。

signal mode_changed(mode: GameModeConfig)

const DEFAULT_MODE_RES: String = "res://data/modes/default_mode.json"
const DEFAULT_MODE_USER: String = "user://modes/default_mode.json"

var current_mode: GameModeConfig = null
var load_errors: Array[String] = []


func _ready() -> void:
	load_default()


## 载入默认玩法：优先 user:// 覆盖，其次 res:// 默认文件；都不可用时使用内置默认值。
func load_default() -> void:
	var path: String = DEFAULT_MODE_RES
	if FileAccess.file_exists(DEFAULT_MODE_USER):
		path = DEFAULT_MODE_USER
	current_mode = GameModeConfig.from_file(path)
	load_errors = current_mode.load_errors.duplicate()
	if not load_errors.is_empty():
		push_warning("玩法配置：%s" % ", ".join(load_errors))
	mode_changed.emit(current_mode)


## 运行时加载指定玩法文件（服务器管理员可传自己的 JSON 路径）。
func load_mode_file(path: String) -> bool:
	var loaded: GameModeConfig = GameModeConfig.from_file(path)
	current_mode = loaded
	load_errors = loaded.load_errors.duplicate()
	mode_changed.emit(current_mode)
	return FileAccess.file_exists(path) and load_errors.is_empty()


func reset_to_default() -> void:
	load_default()


func get_mode() -> GameModeConfig:
	if current_mode == null:
		current_mode = GameModeConfig.default_config()
	return current_mode


# ----- 便捷读取（战斗模块使用） -----

func get_hero_max_health(faction: String) -> int:
	return get_mode().hero_max_health_for_faction(faction)


func get_initial_energy(faction: String) -> int:
	return get_mode().initial_energy_for_faction(faction)


func get_initial_draw(faction: String) -> int:
	return get_mode().initial_draw_for_faction(faction)

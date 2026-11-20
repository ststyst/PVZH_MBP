extends Node
## 全局本地数据（不属于任何存档）：最近游玩的存档、服务器登录信息、主音量、版本显示等。
## 存储位置：user://global.json。与存档数据完全分离，切换/删除存档不影响这里。

const FILE_PATH: String = "user://global.json"
const SETTINGS_DEFAULT_VOLUME: float = 1.0

var data: Dictionary = {}


func _ready() -> void:
	load_data()
	_apply_master_volume()


# ----- 读写 -----

func load_data() -> void:
	data = {
		"last_slot_key": "",
		"server_ip": "",
		"server_account": "",
		"remember_server": false,
		"master_volume": SETTINGS_DEFAULT_VOLUME,
	}
	if not FileAccess.file_exists(FILE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE_PATH))
	if not parsed is Dictionary:
		push_warning("全局数据解析失败：%s" % FILE_PATH)
		return
	var parsed_data: Dictionary = parsed
	for key: Variant in parsed_data.keys():
		data[str(key)] = parsed_data[key]


func save_data() -> bool:
	var file: FileAccess = FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入全局数据：%s" % FILE_PATH)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


# ----- 最近游玩存档 -----

## 上一次使用的本地存档 slot_key；没有则为空字符串。
func get_last_slot_key() -> String:
	return str(data.get("last_slot_key", ""))


func set_last_slot_key(slot_key: String) -> void:
	data["last_slot_key"] = slot_key
	save_data()


# ----- 服务器登录信息（只保存 IP 与账号，不保存密码） -----

## 返回 { ip: String, account: String, remember: bool }。
func get_server_login() -> Dictionary:
	return {
		"ip": str(data.get("server_ip", "")),
		"account": str(data.get("server_account", "")),
		"remember": bool(data.get("remember_server", false)),
	}


func set_server_login(ip: String, account: String, remember: bool) -> void:
	if remember:
		data["server_ip"] = ip
		data["server_account"] = account
		data["remember_server"] = true
	else:
		data["server_ip"] = ""
		data["server_account"] = ""
		data["remember_server"] = false
	save_data()


# ----- 主音量（设置界面滑块） -----

func get_master_volume() -> float:
	return float(data.get("master_volume", SETTINGS_DEFAULT_VOLUME))


## 设置主音量（0.0–1.0），立即生效并持久化。
func set_master_volume(volume: float) -> void:
	data["master_volume"] = clampf(volume, 0.0, 1.0)
	_apply_master_volume()
	save_data()


func _apply_master_volume() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var volume: float = clampf(get_master_volume(), 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.001)))

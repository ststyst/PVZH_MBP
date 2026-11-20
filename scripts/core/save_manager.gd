extends Node
## 本地存档管理 + 服务器地址缓存。
##
## 单机身份：user://saves/<slot_key>/profile.json（多存档，可切换）
## 服务器身份：存档由服务器托管，本地仅缓存最近服务器地址与账号信息。

const SAVE_ROOT: String = "user://saves"
const PROFILE_FILE: String = "profile.json"
const TEMP_SUFFIX: String = ".tmp"
const SERVER_CACHE_FILE: String = "user://server_cache.json"
const SERVER_CACHE_LIMIT: int = 8


## 列出所有本地存档摘要，按最近游玩时间倒序。
func list_slots() -> Array[SaveSlotInfo]:
	var slots: Array[SaveSlotInfo] = []
	var dir: DirAccess = DirAccess.open(SAVE_ROOT)
	if dir == null:
		return slots
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var slot_info: SaveSlotInfo = _read_slot_info(entry_name)
			if slot_info != null:
				slots.append(slot_info)
		entry_name = dir.get_next()
	dir.list_dir_end()
	slots.sort_custom(_sort_slots_desc)
	return slots


func has_any_slot() -> bool:
	return not list_slots().is_empty()


## 新建一个本地存档，返回 slot_key；失败返回空字符串。
func create_slot(display_name: String) -> String:
	var profile := PlayerProfile.create_default(display_name)
	profile.last_played_unix = int(Time.get_unix_time_from_system())
	var slot_key: String = _generate_slot_key()
	if not save_slot(slot_key, profile):
		return ""
	return slot_key


## 读取存档；文件缺失或损坏返回 null。
func load_slot(slot_key: String) -> PlayerProfile:
	var path: String = _profile_path(slot_key)
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("存档解析失败：%s" % path)
		return null
	return PlayerProfile.from_dict(parsed)


## 写入存档（原子写：先写 .tmp 再替换）。
func save_slot(slot_key: String, profile: PlayerProfile) -> bool:
	if slot_key.is_empty() or profile == null:
		return false
	profile.schema_version = PlayerProfile.SCHEMA_VERSION
	return _write_json(_slot_dir(slot_key), PROFILE_FILE, profile.to_dict())


func delete_slot(slot_key: String) -> bool:
	var slot_dir: String = _slot_dir(slot_key)
	if not DirAccess.dir_exists_absolute(slot_dir):
		return false
	var dir: DirAccess = DirAccess.open(slot_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if not dir.current_is_dir():
			dir.remove(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(slot_dir) == OK


## 读取最近登录过 / 使用过的服务器列表（最新在前）。
func load_recent_servers() -> Array[Dictionary]:
	var servers: Array[Dictionary] = []
	if not FileAccess.file_exists(SERVER_CACHE_FILE):
		return servers
	var text: String = FileAccess.get_file_as_string(SERVER_CACHE_FILE)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		for entry: Variant in parsed:
			if entry is Dictionary:
				servers.append(entry)
	return servers


## 记住一个服务器条目。password 由调用方决定是否传空（未勾选「记住密码」时传空）。
func remember_server(address: String, port: int, account: String, password: String) -> void:
	if address.is_empty():
		return
	var new_entry: Dictionary = {
		"address": address,
		"port": port,
		"account": account,
		"password": password,
		"last_login_unix": int(Time.get_unix_time_from_system()),
	}
	var next_list: Array[Dictionary] = [new_entry]
	for existing: Dictionary in load_recent_servers():
		var same_server: bool = (
			str(existing.get("address", "")) == address
			and int(existing.get("port", 0)) == port
			and str(existing.get("account", "")) == account
		)
		if not same_server:
			next_list.append(existing)
	while next_list.size() > SERVER_CACHE_LIMIT:
		next_list.pop_back()
	_write_server_cache(next_list)


func _write_server_cache(servers: Array[Dictionary]) -> void:
	var file: FileAccess = FileAccess.open(SERVER_CACHE_FILE, FileAccess.WRITE)
	if file == null:
		push_error("无法写入服务器缓存：%s" % SERVER_CACHE_FILE)
		return
	file.store_string(JSON.stringify(servers, "\t"))
	file.close()


func _read_slot_info(slot_key: String) -> SaveSlotInfo:
	var path: String = _profile_path(slot_key)
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return null
	var data: Dictionary = parsed
	var info := SaveSlotInfo.new()
	info.slot_key = slot_key
	info.player_name = str(data.get("player_name", "未命名"))
	info.last_played_unix = int(data.get("last_played_unix", 0))
	info.gold = int(data.get("gold", 0))
	info.schema_version = int(data.get("schema_version", 0))
	info.active_deck_id = str(data.get("active_deck_id", ""))
	var raw_decks: Variant = data.get("decks", [])
	if raw_decks is Array:
		info.deck_count = raw_decks.size()
	return info


func _sort_slots_desc(a: SaveSlotInfo, b: SaveSlotInfo) -> bool:
	return a.last_played_unix > b.last_played_unix


func _generate_slot_key() -> String:
	var base: String = "slot_%d" % int(Time.get_unix_time_from_system())
	var candidate: String = base
	var suffix: int = 1
	while FileAccess.file_exists(_profile_path(candidate)):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _slot_dir(slot_key: String) -> String:
	return SAVE_ROOT.path_join(slot_key)


func _profile_path(slot_key: String) -> String:
	return _slot_dir(slot_key).path_join(PROFILE_FILE)


func _write_json(dir_path: String, file_name: String, payload: Variant) -> bool:
	var make_error: Error = DirAccess.make_dir_recursive_absolute(dir_path)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		push_error("创建存档目录失败：%s（错误码 %d）" % [dir_path, make_error])
		return false
	var temp_path: String = dir_path.path_join(file_name + TEMP_SUFFIX)
	var final_path: String = dir_path.path_join(file_name)
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档临时文件：%s" % temp_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("无法打开存档目录：%s" % dir_path)
		return false
	var rename_error: Error = dir.rename(file_name + TEMP_SUFFIX, file_name)
	if rename_error != OK:
		push_error("存档替换失败：%s（错误码 %d）" % [final_path, rename_error])
		return false
	return true

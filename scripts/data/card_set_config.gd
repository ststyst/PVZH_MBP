class_name CardSetConfig
extends RefCounted
## 卡牌系列的全局配置：稀有度 / 职业 / 流派。
## 来自 config.csv（type,name,label_zh），模组可以继续追加条目（load 以后调用 add_entry）。

var rarities: Array[String] = []
var classes: Array[String] = []
var tribes: Array[String] = []

var rarity_labels: Dictionary = {}
var class_labels: Dictionary = {}
var tribe_labels: Dictionary = {}

const REQUIRED_COLUMNS: Array[String] = ["type", "name"]


## 读取配置文件；返回错误/警告列表（空数组表示完全正常）。
func load_file(path: String) -> Array[String]:
	var problems: Array[String] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("配置文件不存在：%s" % path)
		return problems
	var rows: Array[PackedStringArray] = []
	# 用 position/length 判断结束，避免 eof_reached() 边界情况导致死循环
	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty():
			break
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue
		rows.append(row)
	file.close()
	if rows.is_empty():
		problems.append("配置文件为空：%s" % path)
		return problems
	var header: Dictionary = _map_header(rows[0])
	for column: String in REQUIRED_COLUMNS:
		if not header.has(column):
			problems.append("配置缺少列：%s（%s）" % [column, path])
			return problems
	for row_index: int in range(1, rows.size()):
		var row: PackedStringArray = rows[row_index]
		var entry_type: String = _cell(row, header, "type").to_lower()
		var entry_name: String = _cell(row, header, "name").strip_edges().to_lower()
		var entry_label: String = _cell(row, header, "label_zh").strip_edges()
		if entry_name.is_empty():
			problems.append("配置第 %d 行缺少名称，已跳过。" % (row_index + 1))
			continue
		if entry_label.is_empty():
			entry_label = entry_name
		match entry_type:
			"rarity":
				_add_entry(rarities, rarity_labels, entry_name, entry_label)
			"class":
				_add_entry(classes, class_labels, entry_name, entry_label)
			"tribe":
				_add_entry(tribes, tribe_labels, entry_name, entry_label)
			_:
				problems.append("配置第 %d 行类型未知：%s" % [row_index + 1, entry_type])
	return problems


## 供模组等扩展配置使用。
func add_entry(entry_type: String, entry_name: String, entry_label: String = "") -> bool:
	var name: String = entry_name.strip_edges().to_lower()
	if name.is_empty():
		return false
	var label: String = entry_label.strip_edges()
	if label.is_empty():
		label = name
	match entry_type:
		"rarity":
			_add_entry(rarities, rarity_labels, name, label)
		"class":
			_add_entry(classes, class_labels, name, label)
		"tribe":
			_add_entry(tribes, tribe_labels, name, label)
		_:
			return false
	return true


func has_rarity(rarity_id: String) -> bool:
	return rarities.has(rarity_id.strip_edges().to_lower())


func has_class(class_id: String) -> bool:
	return classes.has(class_id.strip_edges().to_lower())


func has_tribe(tribe_id: String) -> bool:
	return tribes.has(tribe_id.strip_edges().to_lower())


func rarity_label(rarity_id: String) -> String:
	return str(rarity_labels.get(rarity_id.strip_edges().to_lower(), rarity_id))


func class_label(class_id: String) -> String:
	return str(class_labels.get(class_id.strip_edges().to_lower(), class_id))


func tribe_label(tribe_id: String) -> String:
	return str(tribe_labels.get(tribe_id.strip_edges().to_lower(), tribe_id))


func _add_entry(target: Array[String], labels: Dictionary, name: String, label: String) -> void:
	if not target.has(name):
		target.append(name)
	if not labels.has(name):
		labels[name] = label


func _map_header(row: PackedStringArray) -> Dictionary:
	var header: Dictionary = {}
	for index: int in range(row.size()):
		header[row[index].strip_edges().to_lower()] = index
	return header


func _cell(row: PackedStringArray, header: Dictionary, column: String) -> String:
	var index: int = int(header.get(column, -1))
	if index < 0 or index >= row.size():
		return ""
	return row[index]

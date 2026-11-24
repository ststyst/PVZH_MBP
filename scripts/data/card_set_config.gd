class_name CardSetConfig
extends RefCounted
## 卡牌系列的全局配置：稀有度 / 职业 / 流派。
## 来自 config.csv（type,name,label_zh），模组可以继续追加条目（load 以后调用 add_entry）。

var rarities: Array[String] = []
var classes: Array[String] = []
var tribes: Array[String] = []
## 职业类别：category_id -> [class_id...]；一个职业只能属于一个类别
var class_categories: Dictionary = {}
var class_category_labels: Dictionary = {}
## class_id -> category_id
var class_to_category: Dictionary = {}
## 被视为“中立”的职业：牌组中不受英雄职业限制
var neutral_classes: Array[String] = []

var rarity_labels: Dictionary = {}
var class_labels: Dictionary = {}
var tribe_labels: Dictionary = {}
var neutral_class_labels: Dictionary = {}

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
			"class_category":
				var raw_members: String = _cell(row, header, "members")
				_add_class_category(entry_name, entry_label, raw_members, problems)
			"tribe":
				_add_entry(tribes, tribe_labels, entry_name, entry_label)
			"neutral_class":
				_add_entry(neutral_classes, neutral_class_labels, entry_name, entry_label)
			_:
				problems.append("配置第 %d 行类型未知：%s" % [row_index + 1, entry_type])
	# 中立职业必须来自已有职业
	for neutral_id: String in neutral_classes:
		if not classes.has(neutral_id):
			problems.append("中立职业不在职业列表中：%s" % neutral_id)
	# 每个职业必须且只能属于一个职业类别；未知类别归入“未分类”
	var uncategorized: Array[String] = []
	for class_id: String in classes:
		if not class_to_category.has(class_id):
			uncategorized.append(class_id)
	if not uncategorized.is_empty():
		var fallback: String = "uncategorized"
		if not class_categories.has(fallback):
			class_categories[fallback] = []
			class_category_labels[fallback] = "未分类"
		for class_id: String in uncategorized:
			(class_categories[fallback] as Array).append(class_id)
			class_to_category[class_id] = fallback
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
		"neutral_class":
			_add_entry(neutral_classes, neutral_class_labels, name, label)
		_:
			return false
	return true


func has_neutral_class(class_id: String) -> bool:
	return neutral_classes.has(class_id.strip_edges().to_lower())


func has_rarity(rarity_id: String) -> bool:
	return rarities.has(rarity_id.strip_edges().to_lower())


func has_class(class_id: String) -> bool:
	return classes.has(class_id.strip_edges().to_lower())


func has_class_category(category_id: String) -> bool:
	return class_categories.has(category_id.strip_edges().to_lower())


func class_category_for(class_id: String) -> String:
	return str(class_to_category.get(class_id.strip_edges().to_lower(), ""))


func class_category_label(category_id: String) -> String:
	return str(class_category_labels.get(category_id.strip_edges().to_lower(), category_id))


func _add_class_category(
	category_id: String,
	label: String,
	members_text: String,
	problems: Array[String],
) -> void:
	var category: String = category_id.strip_edges().to_lower()
	if category.is_empty():
		return
	if class_categories.has(category):
		problems.append("职业类别重复：%s" % category)
		return
	var members: Array[String] = []
	for raw_member: String in members_text.split(","):
		var member: String = raw_member.strip_edges().to_lower()
		if member.is_empty():
			continue
		if not classes.has(member):
			problems.append("职业类别 %s 包含未注册职业：%s" % [category, member])
			continue
		var existing: String = str(class_to_category.get(member, ""))
		if not existing.is_empty() and existing != category:
			problems.append("职业同时属于多个类别：%s（%s / %s）" % [member, existing, category])
			continue
		if not members.has(member):
			members.append(member)
			class_to_category[member] = category
	class_categories[category] = members
	class_category_labels[category] = label.strip_edges() if not label.strip_edges().is_empty() else category


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


## 序列化（供编译包使用）。
func to_dict() -> Dictionary:
	return {
		"rarities": rarities.duplicate(),
		"classes": classes.duplicate(),
		"class_categories": class_categories.duplicate(true),
		"class_category_labels": class_category_labels.duplicate(),
		"class_to_category": class_to_category.duplicate(),
		"tribes": tribes.duplicate(),
		"neutral_classes": neutral_classes.duplicate(),
		"rarity_labels": rarity_labels.duplicate(),
		"class_labels": class_labels.duplicate(),
		"tribe_labels": tribe_labels.duplicate(),
		"neutral_class_labels": neutral_class_labels.duplicate(),
	}


static func from_dict(data: Dictionary) -> CardSetConfig:
	var config := CardSetConfig.new()
	var raw_rarities: Variant = data.get("rarities", [])
	if raw_rarities is Array:
		for entry: Variant in raw_rarities:
			config.rarities.append(str(entry))
	var raw_classes: Variant = data.get("classes", [])
	if raw_classes is Array:
		for entry: Variant in raw_classes:
			config.classes.append(str(entry))
	var raw_tribes: Variant = data.get("tribes", [])
	if raw_tribes is Array:
		for entry: Variant in raw_tribes:
			config.tribes.append(str(entry))
	config.class_categories = data.get("class_categories", {}).duplicate(true)
	config.class_category_labels = data.get("class_category_labels", {}).duplicate()
	config.class_to_category = data.get("class_to_category", {}).duplicate()
	var raw_neutral_classes: Variant = data.get("neutral_classes", [])
	if raw_neutral_classes is Array:
		for entry: Variant in raw_neutral_classes:
			config.neutral_classes.append(str(entry))
	config.rarity_labels = data.get("rarity_labels", {}).duplicate()
	config.class_labels = data.get("class_labels", {}).duplicate()
	config.tribe_labels = data.get("tribe_labels", {}).duplicate()
	config.neutral_class_labels = data.get("neutral_class_labels", {}).duplicate()
	return config


## 复制一份配置（编译时可在副本上合并，不影响运行时数据库）。
func copy_config() -> CardSetConfig:
	return CardSetConfig.from_dict(to_dict())


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

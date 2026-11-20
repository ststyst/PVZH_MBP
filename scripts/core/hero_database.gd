extends Node
## 英雄数据库：从 res://data/cards/official/heroes.csv 载入英雄。
## 英雄拥有两个职业（职业必须在全局配置中），并可携带专属卡牌（英文名，逗号分隔）。
## 模组英雄后续可用同样格式追加（reload_from 传入路径与卡牌数据库即可）。

signal heroes_reloaded(hero_count: int)

const HEROES_FILE: String = "res://data/cards/official/heroes.csv"
const REQUIRED_COLUMNS: Array[String] = [
	"english_name",
	"chinese_name",
	"faction",
	"classes",
	"special_cards",
]
const FACTIONS: Array[String] = ["p", "z"]

var heroes: Dictionary = {}
var load_errors: Array[String] = []


func _ready() -> void:
	reload()


func reload() -> void:
	reload_from(HEROES_FILE, CardDatabase)


## 从指定 CSV 载入；card_database 需要提供 config 与 find_by_english()。
func reload_from(path: String, card_database) -> void:
	heroes.clear()
	load_errors.clear()
	var rows: Array[PackedStringArray] = _read_csv(path)
	if rows.is_empty():
		load_errors.append("英雄文件为空或不存在：%s" % path)
		heroes_reloaded.emit(0)
		return
	var header: Dictionary = _map_header(rows[0])
	for column: String in REQUIRED_COLUMNS:
		if not header.has(column):
			load_errors.append("英雄文件缺少列：%s（%s）" % [column, path])
			heroes_reloaded.emit(0)
			return
	for row_index: int in range(1, rows.size()):
		_load_row(rows[row_index], header, card_database, row_index + 1)
	heroes_reloaded.emit(heroes.size())


func get_hero(hero_id: String) -> HeroData:
	return heroes.get(hero_id, null) as HeroData


func has_hero(hero_id: String) -> bool:
	return heroes.has(hero_id)


func all_hero_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in heroes.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func heroes_by_faction(faction: String) -> Array[HeroData]:
	var result: Array[HeroData] = []
	for hero: HeroData in heroes.values():
		if hero.faction == faction:
			result.append(hero)
	return result


func _load_row(row: PackedStringArray, header: Dictionary, card_database, row_number: int) -> void:
	var english_name: String = _cell(row, header, "english_name").strip_edges()
	var row_label: String = "heroes.csv 第 %d 行" % row_number
	if english_name.is_empty():
		load_errors.append("%s：英文名不能为空。" % row_label)
		return
	row_label = "%s（%s）" % [row_label, english_name]
	var faction: String = _cell(row, header, "faction").strip_edges().to_lower()
	if not FACTIONS.has(faction):
		load_errors.append("%s：阵营必须是 p 或 z（当前 %s）。" % [row_label, faction])
		return
	var hero := HeroData.new()
	hero.hero_id = _slugify(english_name)
	hero.english_name = english_name
	hero.chinese_name = _cell(row, header, "chinese_name").strip_edges()
	hero.faction = faction
	var classes: Array[String] = []
	var config: CardSetConfig = null
	if card_database != null:
		config = card_database.config
	for part: String in _cell(row, header, "classes").split(","):
		var class_id: String = part.strip_edges().to_lower()
		if class_id.is_empty():
			continue
		if config == null or not config.has_class(class_id):
			load_errors.append("%s：职业不在全局配置中（%s）。" % [row_label, class_id])
			continue
		if not classes.has(class_id):
			classes.append(class_id)
	if classes.size() != 2:
		load_errors.append("%s：英雄必须正好拥有两个职业（当前 %d 个）。" % [row_label, classes.size()])
		return
	hero.classes = classes
	if config != null:
		for class_id: String in classes:
			hero.class_labels.append(config.class_label(class_id))
	for part: String in _cell(row, header, "special_cards").split(","):
		var card_name: String = part.strip_edges()
		if card_name.is_empty():
			continue
		var card: CardData = null
		if card_database != null:
			card = card_database.find_by_english(card_name)
		if card == null:
			load_errors.append("%s：专属卡牌不存在（%s）。" % [row_label, card_name])
			continue
		if not hero.special_card_names.has(card_name):
			hero.special_card_names.append(card_name)
		if not hero.special_card_ids.has(card.card_id):
			hero.special_card_ids.append(card.card_id)
	if heroes.has(hero.hero_id):
		load_errors.append("%s：英雄 ID 重复（%s）。" % [row_label, hero.hero_id])
		return
	heroes[hero.hero_id] = hero


static func _slugify(english_name: String) -> String:
	var lowered: String = english_name.strip_edges().to_lower().replace(" ", "_")
	var slug: String = ""
	for character: String in lowered:
		if character == "_" or (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
	return slug


func _read_csv(path: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return rows
	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty():
			break
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue
		rows.append(row)
	file.close()
	return rows


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

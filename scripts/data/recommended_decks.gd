class_name RecommendedDecks
extends RefCounted
## 推荐卡组（外部 CSV）：每行 牌组名称、英雄英文名、卡牌英文名、组入数量。
## 相同（牌组名称 + 英雄）的行归为一套；推荐卡组只用于展示与“电脑随机卡组”对战。

const REQUIRED_COLUMNS: Array[String] = ["deck_name", "hero_name", "card_name", "count"]

var decks: Array[Dictionary] = []
var load_errors: Array[String] = []


func load_file(path: String, card_database, hero_database) -> void:
	decks.clear()
	load_errors.clear()
	var rows: Array[PackedStringArray] = _read_csv(path)
	if rows.is_empty():
		load_errors.append("推荐卡组文件为空或不存在：%s" % path)
		return
	var header: Dictionary = _map_header(rows[0])
	for column: String in REQUIRED_COLUMNS:
		if not header.has(column):
			load_errors.append("推荐卡组文件缺少列：%s（%s）" % [column, path])
			return
	var groups: Dictionary = {}
	var order: Array[String] = []
	for row_index: int in range(1, rows.size()):
		var row: PackedStringArray = rows[row_index]
		var deck_name: String = _cell(row, header, "deck_name").strip_edges()
		var hero_name: String = _cell(row, header, "hero_name").strip_edges()
		var card_name: String = _cell(row, header, "card_name").strip_edges()
		var count_raw: String = _cell(row, header, "count").strip_edges()
		var row_label: String = "recommended_decks.csv 第 %d 行" % (row_index + 1)
		if deck_name.is_empty() or hero_name.is_empty():
			load_errors.append("%s：牌组名称与英雄名称不能为空。" % row_label)
			continue
		var count: int = int(count_raw) if count_raw.is_valid_int() else 0
		if count <= 0:
			load_errors.append("%s：张数必须是正整数（当前 %s）。" % [row_label, count_raw])
			continue
		var card: CardData = card_database.find_by_english(card_name) if card_database != null else null
		if card == null:
			load_errors.append("%s：卡牌不存在（%s）。" % [row_label, card_name])
			continue
		var key: String = "%s\u0000%s" % [deck_name, hero_name]
		if not groups.has(key):
			groups[key] = {"deck_name": deck_name, "hero_name": hero_name, "card_ids": []}
			order.append(key)
		for _copy: int in range(count):
			groups[key].card_ids.append(card.card_id)
	for key: String in order:
		var group: Dictionary = groups[key]
		var hero: HeroData = hero_database.find_by_english(str(group.hero_name)) if hero_database != null else null
		if hero == null:
			load_errors.append("推荐卡组 %s：英雄不存在（%s）。" % [group.deck_name, group.hero_name])
			continue
		var card_ids: Array = group.card_ids
		if card_ids.is_empty():
			load_errors.append("推荐卡组 %s：没有任何卡牌。" % group.deck_name)
			continue
		decks.append({
			"deck_id": "rec_%d" % decks.size(),
			"deck_name": str(group.deck_name),
			"hero_id": hero.hero_id,
			"hero_faction": hero.faction,
			"card_ids": card_ids,
		})


func get_deck(deck_id: String) -> Dictionary:
	for deck: Dictionary in decks:
		if str(deck.get("deck_id", "")) == deck_id:
			return deck
	return {}


## 供电脑选牌组：排除与玩家英雄同阵营的推荐卡组。
func decks_for_enemy(player_faction: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for deck: Dictionary in decks:
		if str(deck.get("hero_faction", "")) != player_faction:
			result.append(deck)
	return result


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

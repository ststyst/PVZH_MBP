extends Node
## 卡牌数据库：从 CSV 载入全局配置与卡牌数据（数据驱动）。
##
## 官方卡牌目录：res://data/cards/official/
##   config.csv  全局配置（type,name,label_zh：rarity / class / tribe）
##   cards.csv   每行一张卡（列名见文件头）
##
## 命名空间：官方卡牌内部 ID 为 "pvzh:<英文名>"；未来模组用 "<作者.模组>:<英文名>"，
## 因此官方与模组的卡牌不会重名。模组目录（user://mods/...）暂未接入，接口已预留。

signal cards_reloaded(card_count: int)

const OFFICIAL_NAMESPACE: String = "pvzh"
const OFFICIAL_DIR: String = "res://data/cards/official"
const CARDS_FILE_NAME: String = "cards.csv"
const CONFIG_FILE_NAME: String = "config.csv"

const REQUIRED_COLUMNS: Array[String] = [
	"english_name",
	"chinese_name",
	"kind",
	"cost",
	"attack",
	"health",
	"shield",
	"class",
	"rarity",
	"keywords",
	"tribes",
	"ability",
	"description",
]

const VALID_KINDS: Array[String] = ["entity", "spell", "environment"]

## 编译包格式版本（与 CardSetCompiler 保持一致）
const PACK_FORMAT_VERSION: int = 1
## 官方卡牌的编译包（由开发者测试界面编译生成；存在时启动优先读取）
const COMPILED_OFFICIAL_PACK: String = "user://card_packs/compiled/official.cardpack"

## card_id（含命名空间）-> CardData
var cards: Dictionary = {}
var config: CardSetConfig = null
## 加载过程中的错误/警告（不阻断其余卡牌加载）
var load_errors: Array[String] = []


func _ready() -> void:
	reload()


func reload(use_compiled_pack: bool = true) -> void:
	cards.clear()
	load_errors.clear()
	config = CardSetConfig.new()
	if use_compiled_pack and FileAccess.file_exists(COMPILED_OFFICIAL_PACK):
		var loaded: int = load_pack_file(COMPILED_OFFICIAL_PACK, OFFICIAL_NAMESPACE, true)
		if loaded > 0:
			cards_reloaded.emit(cards.size())
			return
		load_errors.append("编译包加载失败，已回退 CSV：%s" % COMPILED_OFFICIAL_PACK)
		cards.clear()
		config = CardSetConfig.new()
	load_errors.append_array(config.load_file(OFFICIAL_DIR.path_join(CONFIG_FILE_NAME)))
	load_card_set(OFFICIAL_DIR, OFFICIAL_NAMESPACE, true)
	cards_reloaded.emit(cards.size())


## 载入一个卡牌目录（官方或未来的模组）。
## card_namespace 为空时无法生成内部 ID，直接返回 0。
func load_card_set(dir_path: String, card_namespace: String, is_official: bool = false) -> int:
	if card_namespace.strip_edges().is_empty():
		load_errors.append("卡牌命名空间为空：%s" % dir_path)
		return 0
	var cards_path: String = dir_path.path_join(CARDS_FILE_NAME)
	var rows: Array[PackedStringArray] = _read_csv(cards_path)
	if rows.is_empty():
		load_errors.append("卡牌文件为空或不存在：%s" % cards_path)
		return 0
	var header: Dictionary = _map_header(rows[0])
	for column: String in REQUIRED_COLUMNS:
		if not header.has(column):
			load_errors.append("卡牌文件缺少列：%s（%s）" % [column, cards_path])
			return 0
	var loaded: int = 0
	for row_index: int in range(1, rows.size()):
		if _load_row(rows[row_index], header, card_namespace, is_official, row_index + 1):
			loaded += 1
	return loaded


## 模组接口预留：载入模组卡牌（未来使用 user://mods/<作者.模组>/cards.csv）。
func load_mod_card_set(card_namespace: String, dir_path: String) -> int:
	return load_card_set(dir_path, card_namespace, false)


## 读取编译包（.cardpack），跳过 CSV 与伪代码解析，直接恢复卡牌与能力程序。
func load_pack_file(path: String, namespace_override: String = "", reset_first: bool = false) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("无法读取编译包：%s" % path)
		return 0
	var payload: Variant = file.get_var()
	file.close()
	if not payload is Dictionary:
		load_errors.append("编译包内容无效：%s" % path)
		return 0
	var data: Dictionary = payload
	if int(data.get("format_version", 0)) != PACK_FORMAT_VERSION:
		load_errors.append("编译包版本不匹配（需要 %d）：%s" % [PACK_FORMAT_VERSION, path])
		return 0
	var pack_config: Variant = data.get("config", {})
	if not pack_config is Dictionary:
		load_errors.append("编译包缺少配置：%s" % path)
		return 0
	if reset_first or config == null or config.rarities.is_empty():
		config = CardSetConfig.from_dict(pack_config)
	var card_namespace: String = namespace_override
	if card_namespace.is_empty():
		card_namespace = str(data.get("card_namespace", ""))
	var raw_cards: Variant = data.get("cards", [])
	if not raw_cards is Array:
		load_errors.append("编译包缺少卡牌列表：%s" % path)
		return 0
	var loaded: int = 0
	for entry: Variant in raw_cards:
		if not entry is Dictionary:
			continue
		var card: CardData = CardData.from_pack_dict(entry, card_namespace)
		if card.card_id.is_empty():
			continue
		if cards.has(card.card_id):
			load_errors.append("编译包卡牌 ID 重复：%s" % card.card_id)
			continue
		cards[card.card_id] = card
		loaded += 1
	return loaded


func has_compiled_official_pack() -> bool:
	return FileAccess.file_exists(COMPILED_OFFICIAL_PACK)


## 删除官方编译包（下次启动回退 CSV）。
func clear_compiled_official_pack() -> bool:
	if not FileAccess.file_exists(COMPILED_OFFICIAL_PACK):
		return false
	return DirAccess.remove_absolute(COMPILED_OFFICIAL_PACK) == OK


func get_card(card_id: String) -> CardData:
	return cards.get(card_id, null) as CardData


func has_card(card_id: String) -> bool:
	return cards.has(card_id)


func card_count() -> int:
	return cards.size()


func all_card_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in cards.keys():
		ids.append(str(key))
	ids.sort()
	return ids


## 按英文名（大小写不敏感）查找卡牌，供伪代码引用。
func find_by_english(english_name: String) -> CardData:
	var target: String = slugify(english_name)
	for card: CardData in cards.values():
		if slugify(card.english_name) == target:
			return card
	return null


func get_classes() -> Array[String]:
	if config == null:
		return []
	return config.classes.duplicate()


func get_rarities() -> Array[String]:
	if config == null:
		return []
	return config.rarities.duplicate()


func get_tribes() -> Array[String]:
	if config == null:
		return []
	return config.tribes.duplicate()


## 被视为中立的职业（不受英雄职业限制）。
func get_neutral_classes() -> Array[String]:
	if config == null:
		return []
	return config.neutral_classes.duplicate()


func is_neutral_class(class_id: String) -> bool:
	if config == null:
		return false
	return config.has_neutral_class(class_id)


## 生成内部 ID 用的规范化英文名：小写、空格转下划线、只保留字母数字下划线。
static func slugify(english_name: String) -> String:
	var lowered: String = english_name.strip_edges().to_lower().replace(" ", "_")
	var slug: String = ""
	for character: String in lowered:
		if character == "_" or (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
	return slug


func _load_row(
	row: PackedStringArray,
	header: Dictionary,
	card_namespace: String,
	is_official: bool,
	row_number: int,
) -> bool:
	var english_name: String = _cell(row, header, "english_name").strip_edges()
	if english_name.is_empty():
		load_errors.append("第 %d 行缺少英文名，已跳过。" % row_number)
		return false
	var kind: String = _cell(row, header, "kind").strip_edges().to_lower()
	if not VALID_KINDS.has(kind):
		load_errors.append("第 %d 行卡牌种类非法：%s（%s）" % [row_number, kind, english_name])
		return false
	var card_class: String = _cell(row, header, "class").strip_edges().to_lower()
	if config == null or not config.has_class(card_class):
		load_errors.append("第 %d 行职业不在配置中：%s（%s）" % [row_number, card_class, english_name])
		return false
	var rarity: String = _cell(row, header, "rarity").strip_edges().to_lower()
	if config == null or not config.has_rarity(rarity):
		load_errors.append("第 %d 行稀有度不在配置中：%s（%s）" % [row_number, rarity, english_name])
		return false
	var card_id: String = "%s:%s" % [card_namespace, slugify(english_name)]
	if cards.has(card_id):
		load_errors.append("第 %d 行卡牌 ID 重复：%s" % [row_number, card_id])
		return false
	var card := CardData.new()
	card.card_id = card_id
	card.card_namespace = card_namespace
	card.english_name = english_name
	card.chinese_name = _cell(row, header, "chinese_name").strip_edges()
	card.description = _cell(row, header, "description").strip_edges()
	card.kind = kind
	card.cost = _parse_int(row, header, "cost", english_name)
	card.attack = _parse_int(row, header, "attack", english_name)
	card.health = _parse_int(row, header, "health", english_name)
	card.shield = _parse_int(row, header, "shield", english_name)
	card.card_class = card_class
	card.rarity = rarity
	card.deck_includable = _parse_deck_includable(row, header, english_name, row_number)
	card.ability = _cell(row, header, "ability").strip_edges()
	card.art_path = _cell(row, header, "art_path").strip_edges()
	card.ability_script = CardEffectScript.parse(card.ability)
	for problem: String in card.ability_script.errors:
		load_errors.append("卡牌 %s 能力语法错误：%s" % [english_name, problem])
	for problem: String in card.ability_script.validate_for_kind(kind):
		load_errors.append("卡牌 %s 能力语义错误：%s" % [english_name, problem])
	card.class_label = config.class_label(card_class)
	card.rarity_label = config.rarity_label(rarity)
	_parse_keywords(card, row, header, english_name, row_number)
	_parse_tribes(card, row, header, english_name, row_number)
	if is_official and card_namespace != OFFICIAL_NAMESPACE:
		load_errors.append("官方卡牌命名空间异常：%s（应为 %s）" % [card_namespace, OFFICIAL_NAMESPACE])
	cards[card_id] = card
	return true


func _parse_keywords(
	card: CardData,
	row: PackedStringArray,
	header: Dictionary,
	english_name: String,
	row_number: int,
) -> void:
	var raw: String = _cell(row, header, "keywords")
	for part: String in raw.split(","):
		var keyword_id: String = CardKeywords.normalize(part)
		if keyword_id.is_empty():
			continue
		if not CardKeywords.has(keyword_id):
			load_errors.append("第 %d 行未知词缀已忽略：%s（%s）" % [row_number, part.strip_edges(), english_name])
			continue
		if not card.keywords.has(keyword_id):
			card.keywords.append(keyword_id)
			card.keyword_labels.append(CardKeywords.label(keyword_id))


func _parse_tribes(
	card: CardData,
	row: PackedStringArray,
	header: Dictionary,
	english_name: String,
	row_number: int,
) -> void:
	var raw: String = _cell(row, header, "tribes")
	for part: String in raw.split(","):
		var tribe_id: String = part.strip_edges().to_lower()
		if tribe_id.is_empty():
			continue
		if config == null or not config.has_tribe(tribe_id):
			load_errors.append("第 %d 行未知流派已忽略：%s（%s）" % [row_number, part.strip_edges(), english_name])
			continue
		if not card.tribes.has(tribe_id):
			card.tribes.append(tribe_id)
			card.tribe_labels.append(config.tribe_label(tribe_id))


func _parse_int(row: PackedStringArray, header: Dictionary, column: String, english_name: String) -> int:
	var raw: String = _cell(row, header, column).strip_edges()
	if raw.is_empty():
		return 0
	if not raw.is_valid_int():
		load_errors.append("卡牌 %s 的 %s 不是整数：%s（按 0 处理）" % [english_name, column, raw])
		return 0
	return int(raw)


## deck_includable：0 不可编入、1 可编入；缺省/空值按 1 处理。
func _parse_deck_includable(
	row: PackedStringArray,
	header: Dictionary,
	english_name: String,
	row_number: int,
) -> bool:
	var raw: String = _cell(row, header, "deck_includable").strip_edges()
	if raw.is_empty() or raw == "1":
		return true
	if raw == "0":
		return false
	load_errors.append(
		"第 %d 行 deck_includable 必须为 0 或 1（%s，当前 %s），按 1 处理。" % [row_number, english_name, raw]
	)
	return true


func _read_csv(path: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return rows
	# 用 position/length 判断结束，避免某些平台 eof_reached() 在最后一行不翻转为 true 导致死循环
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

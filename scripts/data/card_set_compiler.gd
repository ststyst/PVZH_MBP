class_name CardSetCompiler
extends RefCounted
## 卡牌 CSV 编译器（开发者测试界面调用）：
## - 读取指定目录下的 config.csv / cards.csv
## - 校验全局配置、职业/稀有度/词缀/流派、数值规则与伪代码
## - 输出简单报错文件（哪一行、哪一项出错）
## - 全部通过时打包为 .cardpack（跳过运行时解析，加快加载；未来模组同用）
##
## 目录约定：
##   user://card_packs/import/            默认待编译目录（玩家/开发者放置 CSV）
##   user://card_packs/compiled/*.cardpack 编译产物
##   user://card_packs/compile_report.txt  最近一次编译报告

const FORMAT_VERSION: int = 1
## 官方命名空间（与 CardDatabase 保持一致；这里独立定义以便编辑器测试不依赖 autoload）
const OFFICIAL_NAMESPACE: String = "pvzh"
const DEFAULT_IMPORT_DIR: String = "user://card_packs/import"
const COMPILED_DIR: String = "user://card_packs/compiled"
const REPORT_PATH: String = "user://card_packs/compile_report.txt"

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


## 编译一个卡牌目录。
## base_config 为官方全局配置（可传 CardDatabase.config），编译时在其副本上合并该目录的 config.csv。
## 返回 { ok, summary, errors, warnings, card_count, pack_path, report_path }。
static func compile_pack(
	source_dir: String,
	card_namespace: String,
	output_pack_path: String = "",
	base_config: CardSetConfig = null,
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var config: CardSetConfig = base_config.copy_config() if base_config != null else CardSetConfig.new()
	if card_namespace.strip_edges().is_empty():
		errors.append("命名空间不能为空。")
	# 合并该目录自己的 config.csv（如果存在）
	var config_path: String = source_dir.path_join("config.csv")
	if FileAccess.file_exists(config_path):
		for problem: String in config.load_file(config_path):
			errors.append("config.csv：%s" % problem)
	elif base_config == null:
		errors.append("缺少 config.csv（且未提供官方全局配置作为基础）。")
	# 读取卡牌表
	var cards_path: String = source_dir.path_join("cards.csv")
	var rows: Array[PackedStringArray] = _read_csv(cards_path)
	if rows.is_empty():
		errors.append("缺少或无法读取 cards.csv：%s" % cards_path)
		return _finish(errors, warnings, 0, output_pack_path, source_dir, card_namespace)
	var header: Dictionary = _map_header(rows[0])
	var missing: Array[String] = []
	for column: String in REQUIRED_COLUMNS:
		if not header.has(column):
			missing.append(column)
	if not missing.is_empty():
		errors.append("cards.csv 缺少列：%s" % ", ".join(missing))
		return _finish(errors, warnings, 0, output_pack_path, source_dir, card_namespace)
	var pack_cards: Array = []
	var seen_ids: Dictionary = {}
	for row_index: int in range(1, rows.size()):
		var row: PackedStringArray = rows[row_index]
		var row_number: int = row_index + 1
		var english_name: String = _cell(row, header, "english_name").strip_edges()
		var row_label: String = "cards.csv 第 %d 行" % row_number
		if english_name.is_empty():
			errors.append("%s：英文名不能为空。" % row_label)
			continue
		row_label = "%s（%s）" % [row_label, english_name]
		var errors_before: int = errors.size()
		var kind: String = _cell(row, header, "kind").strip_edges().to_lower()
		if kind != "entity" and kind != "spell":
			errors.append("%s：卡牌种类必须是 entity 或 spell（当前 %s）。" % [row_label, kind])
		var card_class: String = _cell(row, header, "class").strip_edges().to_lower()
		if not config.has_class(card_class):
			errors.append("%s：职业不在全局配置中（%s）。" % [row_label, card_class])
		var rarity: String = _cell(row, header, "rarity").strip_edges().to_lower()
		if not config.has_rarity(rarity):
			errors.append("%s：稀有度不在全局配置中（%s）。" % [row_label, rarity])
		var cost: int = _int_cell(row, header, "cost", "费用", row_label, errors)
		if cost <= 0:
			errors.append("%s：费用必须为正数（当前 %d）。" % [row_label, cost])
		var attack: int = _int_cell(row, header, "attack", "攻击力", row_label, errors)
		if attack < 0:
			errors.append("%s：攻击力不能为负数（当前 %d）。" % [row_label, attack])
		var health: int = _int_cell(row, header, "health", "生命值", row_label, errors)
		var shield: int = _int_cell(row, header, "shield", "防御力", row_label, errors)
		if shield < 0:
			errors.append("%s：防御力不能为负数（当前 %d）。" % [row_label, shield])
		if kind == "entity" and health < 1:
			errors.append("%s：实体牌的生命值不能小于 1（当前 %d）。" % [row_label, health])
		if kind == "spell" and (attack != 0 or health != 0 or shield != 0):
			warnings.append("%s：锦囊牌的攻/血/防应为 0（当前 %d/%d/%d）。" % [row_label, attack, health, shield])
		var keywords: Array[String] = _parse_keywords(row, header, row_label, errors)
		var tribes: Array[String] = _parse_tribes(row, header, config, row_label, errors)
		var deck_includable: bool = _flag_cell(
			row, header, "deck_includable", "deck_includable（是否可编入牌组）", row_label, errors
		)
		var ability: String = _cell(row, header, "ability").strip_edges()
		var art_path: String = _cell(row, header, "art_path").strip_edges()
		if not art_path.is_empty() and not FileAccess.file_exists(art_path):
			errors.append("%s：美术素材不存在（%s）。" % [row_label, art_path])
		var ability_script: CardEffectScript = CardEffectScript.parse(ability)
		for problem: String in ability_script.errors:
			errors.append("%s：能力语法错误：%s" % [row_label, problem])
		for problem: String in ability_script.validate_for_kind(kind):
			errors.append("%s：能力语义错误：%s" % [row_label, problem])
		var chinese_name: String = _cell(row, header, "chinese_name").strip_edges()
		if chinese_name.is_empty():
			warnings.append("%s：中文名称为空。" % row_label)
		if errors.size() > errors_before:
			continue
		var card_id: String = "%s:%s" % [card_namespace.strip_edges(), _slugify(english_name)]
		if seen_ids.has(card_id):
			errors.append("%s：卡牌 ID 重复（%s）。" % [row_label, card_id])
			continue
		seen_ids[card_id] = true
		var card := CardData.new()
		card.card_id = card_id
		card.card_namespace = card_namespace
		card.english_name = english_name
		card.chinese_name = chinese_name
		card.description = _cell(row, header, "description").strip_edges()
		card.kind = kind
		card.cost = cost
		card.attack = attack
		card.health = health
		card.shield = shield
		card.card_class = card_class
		card.rarity = rarity
		card.keywords = keywords
		card.tribes = tribes
		card.deck_includable = deck_includable
		card.ability = ability
		card.art_path = art_path
		card.ability_script = ability_script
		card.class_label = config.class_label(card_class)
		card.rarity_label = config.rarity_label(rarity)
		for keyword_id: String in keywords:
			card.keyword_labels.append(CardKeywords.label(keyword_id))
		for tribe_id: String in tribes:
			card.tribe_labels.append(config.tribe_label(tribe_id))
		pack_cards.append(card.to_pack_dict())
	return _finish(errors, warnings, pack_cards.size(), output_pack_path, source_dir, card_namespace, config, pack_cards)


# ----- 内部 -----

static func _finish(
	errors: Array[String],
	warnings: Array[String],
	card_count: int,
	output_pack_path: String,
	source_dir: String,
	card_namespace: String,
	config: CardSetConfig = null,
	pack_cards: Array = [],
) -> Dictionary:
	var ok: bool = errors.is_empty()
	var pack_path: String = ""
	if ok and config != null:
		var target: String = output_pack_path
		if target.is_empty():
			target = default_pack_path(card_namespace)
		if _write_pack(target, card_namespace, config, pack_cards, source_dir):
			pack_path = target
		else:
			errors.append("无法写入编译包：%s" % target)
			ok = false
	var summary: String = ""
	if ok:
		summary = "编译成功：%d 张卡牌，%d 个警告。" % [card_count, warnings.size()]
	else:
		summary = "编译失败：%d 个错误，%d 个警告。" % [errors.size(), warnings.size()]
	var report_path: String = _write_report(source_dir, summary, errors, warnings)
	return {
		"ok": ok,
		"summary": summary,
		"errors": errors,
		"warnings": warnings,
		"card_count": card_count,
		"pack_path": pack_path,
		"report_path": report_path,
	}


static func _write_pack(path: String, card_namespace: String, config: CardSetConfig, cards: Array, source_dir: String) -> bool:
	var make_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return false
	var payload: Dictionary = {
		"format_version": FORMAT_VERSION,
		"card_namespace": card_namespace,
		"source_dir": source_dir,
		"created_unix": int(Time.get_unix_time_from_system()),
		"config": config.to_dict(),
		"cards": cards,
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(payload, true)
	file.close()
	return true


static func _write_report(
	source_dir: String,
	summary: String,
	errors: Array[String],
	warnings: Array[String],
) -> String:
	DirAccess.make_dir_recursive_absolute(REPORT_PATH.get_base_dir())
	var lines: Array[String] = []
	lines.append("卡牌 CSV 编译报告")
	lines.append("目录：%s" % source_dir)
	lines.append("时间：%s" % Time.get_datetime_string_from_system(true))
	lines.append("结果：%s" % summary)
	lines.append("")
	if not errors.is_empty():
		lines.append("错误：")
		for message: String in errors:
			lines.append("  - %s" % message)
		lines.append("")
	if not warnings.is_empty():
		lines.append("警告：")
		for message: String in warnings:
			lines.append("  - %s" % message)
		lines.append("")
	if errors.is_empty() and warnings.is_empty():
		lines.append("没有发现错误或警告。")
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("\n".join(lines))
	file.close()
	return REPORT_PATH


static func default_pack_path(card_namespace: String) -> String:
	var safe_name: String = "official" if card_namespace == OFFICIAL_NAMESPACE else _safe_file_name(card_namespace)
	return COMPILED_DIR.path_join(safe_name + ".cardpack")


## 与 CardDatabase.slugify 等价的本地实现（编译 CSV 与加载保持一致）。
static func _slugify(english_name: String) -> String:
	var lowered: String = english_name.strip_edges().to_lower().replace(" ", "_")
	var slug: String = ""
	for character: String in lowered:
		if character == "_" or (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
	return slug


static func _safe_file_name(text: String) -> String:
	var result: String = ""
	for character: String in text.strip_edges().to_lower():
		if (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character == "_"
			or character == "-"
		):
			result += character
		elif character == ".":
			result += "_"
	if result.is_empty():
		result = "cardpack"
	return result


static func _int_cell(
	row: PackedStringArray,
	header: Dictionary,
	column: String,
	column_label: String,
	row_label: String,
	errors: Array[String],
) -> int:
	var raw: String = _cell(row, header, column).strip_edges()
	if raw.is_empty():
		errors.append("%s：%s不能为空。" % [row_label, column_label])
		return 0
	if not raw.is_valid_int():
		errors.append("%s：%s必须是整数（当前 %s）。" % [row_label, column_label, raw])
		return 0
	return int(raw)


static func _parse_keywords(
	row: PackedStringArray,
	header: Dictionary,
	row_label: String,
	errors: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	for part: String in _cell(row, header, "keywords").split(","):
		var keyword_id: String = CardKeywords.normalize(part)
		if keyword_id.is_empty():
			continue
		if not CardKeywords.has(keyword_id):
			errors.append("%s：未知词缀（%s）。" % [row_label, part.strip_edges()])
			continue
		if not result.has(keyword_id):
			result.append(keyword_id)
	return result


static func _parse_tribes(
	row: PackedStringArray,
	header: Dictionary,
	config: CardSetConfig,
	row_label: String,
	errors: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	for part: String in _cell(row, header, "tribes").split(","):
		var tribe_id: String = part.strip_edges().to_lower()
		if tribe_id.is_empty():
			continue
		if not config.has_tribe(tribe_id):
			errors.append("%s：未知流派（%s）。" % [row_label, part.strip_edges()])
			continue
		if not result.has(tribe_id):
			result.append(tribe_id)
	return result


## 读取 0/1 布尔列；缺省/空值视为 1（true）。
static func _flag_cell(
	row: PackedStringArray,
	header: Dictionary,
	column: String,
	column_label: String,
	row_label: String,
	errors: Array[String],
) -> bool:
	if not header.has(column):
		return true
	var raw: String = _cell(row, header, column).strip_edges()
	if raw.is_empty() or raw == "1":
		return true
	if raw == "0":
		return false
	errors.append("%s：%s必须是 0 或 1（当前 %s）。" % [row_label, column_label, raw])
	return true


static func _read_csv(path: String) -> Array[PackedStringArray]:
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


static func _map_header(row: PackedStringArray) -> Dictionary:
	var header: Dictionary = {}
	for index: int in range(row.size()):
		header[row[index].strip_edges().to_lower()] = index
	return header


static func _cell(row: PackedStringArray, header: Dictionary, column: String) -> String:
	var index: int = int(header.get(column, -1))
	if index < 0 or index >= row.size():
		return ""
	return row[index]

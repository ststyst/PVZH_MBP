extends Node
## 卡牌数据库：扫描 res://data/cards/*.json 构建卡表。
## 数据驱动，便于后续模组从 user://mods 追加卡牌（本里程碑只预留入口）。

signal cards_reloaded(card_count: int)

const CARDS_DIR: String = "res://data/cards"
const MODS_DIR: String = "user://mods"

## card_id -> CardData
var cards: Dictionary = {}


func _ready() -> void:
	reload()


## 重新加载全部卡牌定义。
func reload() -> void:
	cards.clear()
	_load_directory(CARDS_DIR)
	cards_reloaded.emit(cards.size())


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


func _load_directory(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_file(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_file(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_warning("卡牌文件解析失败：%s" % path)
		return
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary and parsed.has("cards"):
		var raw_cards: Variant = parsed["cards"]
		if raw_cards is Array:
			entries = raw_cards
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var card: CardData = CardData.from_dict(entry)
		if card.card_id.is_empty():
			push_warning("卡牌缺少 card_id：%s" % path)
			continue
		if cards.has(card.card_id):
			push_warning("重复的卡牌 ID：%s（%s）" % [card.card_id, path])
			continue
		cards[card.card_id] = card

extends Control
## 牌组编辑界面：可选卡牌列表（get_available_cards）+ 当前牌组列表。
##
## 点击“可选卡牌”中的卡牌 → 下拉菜单：选中 / 信息
## 点击“当前牌组”中的卡牌 → 下拉菜单：移除 / 信息
## “信息”会弹出 CardInfoDialog（外形、名称、数值、简介、关闭按钮）。

const CARD_TILE_SCENE: PackedScene = preload("res://scenes/cards/CardTile.tscn")

const MENU_ACTION_PRIMARY: int = 0
const MENU_ACTION_INFO: int = 1

@onready var back_button: Button = %BackButton
@onready var deck_name_label: Label = %DeckNameLabel
@onready var hero_label: Label = %HeroLabel
@onready var count_label: Label = %CountLabel
@onready var tag_label: Label = %TagLabel
@onready var save_button: Button = %SaveButton
@onready var tabs: TabContainer = %Tabs
@onready var available_hint: Label = %AvailableHint
@onready var available_grid: GridContainer = %AvailableGrid
@onready var deck_grid: GridContainer = %DeckGrid
@onready var status_label: Label = %StatusLabel
@onready var card_menu: PopupMenu = %CardMenu
@onready var info_dialog: CardInfoDialog = %CardInfoDialog

var _deck: DeckData = null
var _menu_card_id: String = ""
var _menu_from_deck: bool = false


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)
	card_menu.id_pressed.connect(_on_menu_id_pressed)
	tabs.set_tab_title(0, "可选卡牌")
	tabs.set_tab_title(1, "当前牌组")
	_load_deck()


func _load_deck() -> void:
	_deck = DeckManager.get_editing_deck()
	if _deck == null:
		var decks: Array[DeckData] = DeckManager.get_decks()
		if not decks.is_empty():
			_deck = DeckManager.begin_edit(decks[0].deck_id)
	if _deck == null:
		_set_status("没有可编辑的牌组，请先在牌组列表创建牌组。", true)
		_refresh_header()
		return
	_refresh_all()


func _refresh_all() -> void:
	_refresh_header()
	_rebuild_available_grid()
	_rebuild_deck_grid()


func _refresh_header() -> void:
	if _deck == null:
		deck_name_label.text = "未选择牌组"
		hero_label.text = ""
		count_label.text = ""
		tag_label.text = ""
		return
	deck_name_label.text = _deck.deck_name
	var hero: HeroData = HeroDatabase.get_hero(_deck.hero_id)
	hero_label.text = hero.display_name() if hero != null else "无英雄"
	var mode: GameModeConfig = ModeManager.get_mode()
	count_label.text = "%d/%d" % [_deck.card_count(), mode.deck_max_size]
	tag_label.text = "默认牌组" if _deck.has_tag(DeckRules.TAG_DEFAULT) else ""


func _rebuild_available_grid() -> void:
	_clear_grid(available_grid)
	if _deck == null:
		return
	var entries: Array[Dictionary] = DeckManager.get_available_cards(_deck.deck_id)
	available_hint.text = "点击卡牌可选择“选中”或查看“信息”（共 %d 张可选）" % entries.size()
	for entry: Dictionary in entries:
		var card: CardData = entry.get("card")
		if card == null:
			continue
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		available_grid.add_child(tile)
		var owned: int = int(entry.get("owned", 0))
		var in_deck: int = int(entry.get("in_deck", 0))
		tile.setup(card, owned, "拥有 %d · 编入 %d" % [owned, in_deck])
		tile.pressed.connect(_open_available_menu.bind(entry, tile))


func _rebuild_deck_grid() -> void:
	_clear_grid(deck_grid)
	if _deck == null:
		return
	var counts: Dictionary = _deck.get_card_counts()
	var cards: Array[CardData] = []
	for card_id: Variant in counts.keys():
		var card: CardData = CardDatabase.get_card(str(card_id))
		if card != null:
			cards.append(card)
	cards.sort_custom(_sort_cards)
	for card: CardData in cards:
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		deck_grid.add_child(tile)
		var copies: int = int(counts.get(card.card_id, 0))
		tile.setup(card, 0, "编入 %d 张" % copies)
		tile.pressed.connect(_open_deck_menu.bind(card.card_id, tile))


func _sort_cards(first: CardData, second: CardData) -> bool:
	if first.cost != second.cost:
		return first.cost < second.cost
	return first.display_name() < second.display_name()


func _open_available_menu(entry: Dictionary, tile: CardTile) -> void:
	_menu_card_id = str(entry.get("card_id", ""))
	_menu_from_deck = false
	card_menu.clear()
	card_menu.add_item("选中", MENU_ACTION_PRIMARY)
	card_menu.set_item_disabled(0, not bool(entry.get("can_add", false)))
	card_menu.add_item("信息", MENU_ACTION_INFO)
	_popup_menu_at(tile)


func _open_deck_menu(card_id: String, tile: CardTile) -> void:
	_menu_card_id = card_id
	_menu_from_deck = true
	card_menu.clear()
	card_menu.add_item("移除", MENU_ACTION_PRIMARY)
	card_menu.add_item("信息", MENU_ACTION_INFO)
	_popup_menu_at(tile)


func _popup_menu_at(tile: CardTile) -> void:
	card_menu.reset_size()
	card_menu.position = Vector2i(
		int(tile.global_position.x),
		int(tile.global_position.y + tile.size.y),
	)
	card_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	if _deck == null or _menu_card_id.is_empty():
		return
	if id == MENU_ACTION_INFO:
		var card: CardData = CardDatabase.get_card(_menu_card_id)
		if card != null:
			info_dialog.show_card(card)
		return
	if id != MENU_ACTION_PRIMARY:
		return
	var result: Dictionary
	if _menu_from_deck:
		result = DeckManager.remove_card(_deck.deck_id, _menu_card_id)
	else:
		result = DeckManager.add_card(_deck.deck_id, _menu_card_id)
	_set_status(str(result.get("message", "")), not bool(result.get("ok", false)))
	_refresh_all()


func _on_save_pressed() -> void:
	if _deck == null:
		return
	var result: Dictionary = DeckManager.save_deck(_deck.deck_id)
	_set_status(str(result.get("message", "")), false)
	_refresh_header()


func _on_back_pressed() -> void:
	GameState.go_to_main()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)


func _clear_grid(grid: GridContainer) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

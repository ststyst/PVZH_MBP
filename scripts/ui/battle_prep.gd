extends Control
## 战斗准备：选择出战牌组（只显示带 default 标签的牌组）与电脑难度，开始“电脑随机卡组对战”。

@onready var back_button: Button = %BackButton
@onready var deck_button: Button = %DeckButton
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var hint_label: Label = %HintLabel
@onready var start_button: Button = %StartButton
@onready var status_label: Label = %StatusLabel
@onready var deck_popup: PanelContainer = %DeckPopup
@onready var popup_backdrop: ColorRect = %PopupBackdrop
@onready var deck_list: VBoxContainer = %DeckList
@onready var popup_close_button: Button = %PopupCloseButton

var _selected_deck: DeckData = null


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	deck_button.pressed.connect(_on_deck_button_pressed)
	popup_close_button.pressed.connect(_close_popup)
	popup_backdrop.gui_input.connect(_on_backdrop_input)
	start_button.pressed.connect(_on_start_pressed)
	difficulty_option.clear()
	difficulty_option.add_item("简单（easy）")
	_set_status("请选择一套满足默认规则的牌组。")
	_refresh_all()


func _refresh_all() -> void:
	var decks: Array[DeckData] = BattleManager.get_available_player_decks()
	if _selected_deck != null and not decks.has(_selected_deck):
		_selected_deck = null
	if _selected_deck == null and not decks.is_empty():
		_selected_deck = decks[0]
	_update_deck_button()
	start_button.disabled = _selected_deck == null or _selected_deck.card_count() == 0
	if decks.is_empty():
		hint_label.text = "没有带 default 标签的牌组。请先在牌组编辑器中配好 40 张满编牌组并保存。"
	else:
		hint_label.text = "只显示带 default 标签的牌组；空牌组无法开始。"


func _update_deck_button() -> void:
	if _selected_deck == null:
		deck_button.text = "选择牌组"
		return
	var hero: HeroData = HeroDatabase.get_hero(_selected_deck.hero_id)
	var hero_name: String = hero.display_name() if hero != null else "无英雄"
	deck_button.text = "%s — %s（%d 张）" % [_selected_deck.deck_name, hero_name, _selected_deck.card_count()]


func _on_deck_button_pressed() -> void:
	_rebuild_deck_list()
	deck_popup.visible = true
	popup_backdrop.visible = true


func _rebuild_deck_list() -> void:
	for child: Node in deck_list.get_children():
		deck_list.remove_child(child)
		child.queue_free()
	var decks: Array[DeckData] = BattleManager.get_available_player_decks()
	if decks.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无可用牌组（需要 default 标签）。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deck_list.add_child(empty_label)
		return
	for deck: DeckData in decks:
		var button := Button.new()
		var hero: HeroData = HeroDatabase.get_hero(deck.hero_id)
		var hero_name: String = hero.display_name() if hero != null else "无英雄"
		button.text = "%s — %s（%d 张）" % [deck.deck_name, hero_name, deck.card_count()]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(_on_deck_selected.bind(deck))
		deck_list.add_child(button)


func _on_deck_selected(deck: DeckData) -> void:
	_selected_deck = deck
	_close_popup()
	_update_deck_button()
	start_button.disabled = deck.card_count() == 0
	_set_status("已选择：%s" % deck.deck_name)


func _on_start_pressed() -> void:
	if _selected_deck == null:
		_set_status("请先选择牌组。", true)
		return
	if _selected_deck.card_count() == 0:
		_set_status("该牌组为空，不能开始战斗。", true)
		return
	var difficulty: String = "easy" if difficulty_option.selected == 0 else "easy"
	var result: Dictionary = BattleManager.start_vs_ai(_selected_deck.deck_id, difficulty)
	if bool(result.get("ok", false)):
		GameState.go_to_battle()
	else:
		_set_status(str(result.get("message", "开始战斗失败。")), true)


func _on_back_pressed() -> void:
	GameState.go_to_main()


func _close_popup() -> void:
	deck_popup.visible = false
	popup_backdrop.visible = false


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_popup()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)

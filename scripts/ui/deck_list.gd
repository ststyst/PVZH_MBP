extends Control
## 牌组列表：展示玩家全部牌组与数量，选择后进入牌组编辑；新建牌组入口也在这里。

@onready var back_button: Button = %BackButton
@onready var deck_count_label: Label = %DeckCountLabel
@onready var new_deck_button: Button = %NewDeckButton
@onready var deck_list_container: VBoxContainer = %DeckListContainer
@onready var empty_hint: Label = %EmptyHint
@onready var status_label: Label = %StatusLabel
@onready var create_deck_backdrop: ColorRect = %CreateDeckBackdrop
@onready var create_deck_popup: PanelContainer = %CreateDeckPopup
@onready var deck_name_input: LineEdit = %DeckNameInput
@onready var hero_option: OptionButton = %HeroOption
@onready var popup_status_label: Label = %PopupStatusLabel
@onready var create_cancel_button: Button = %CreateCancelButton
@onready var create_confirm_button: Button = %CreateConfirmButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	new_deck_button.pressed.connect(_open_create_deck_popup)
	create_cancel_button.pressed.connect(_close_create_deck_popup)
	create_confirm_button.pressed.connect(_on_create_deck_confirmed)
	create_deck_backdrop.gui_input.connect(_on_create_backdrop_input)
	_refresh_list()
	_set_status("选择一套牌组开始编辑。")


func _refresh_list() -> void:
	for child: Node in deck_list_container.get_children():
		deck_list_container.remove_child(child)
		child.queue_free()
	var decks: Array[DeckData] = DeckManager.get_decks()
	deck_count_label.text = "共 %d 个牌组" % decks.size()
	empty_hint.visible = decks.is_empty()
	if decks.is_empty():
		empty_hint.text = "还没有牌组，点击右上角「新建牌组」开始。"
		return
	for deck: DeckData in decks:
		var hero: HeroData = HeroDatabase.get_hero(deck.hero_id)
		var hero_name: String = hero.display_name() if hero != null else "无英雄"
		var tag: String = " · 默认" if deck.has_tag(DeckRules.TAG_DEFAULT) else ""
		var button := Button.new()
		button.text = "%s — %s（%d/40%s）" % [deck.deck_name, hero_name, deck.card_count(), tag]
		button.custom_minimum_size = Vector2(0, 56)
		button.pressed.connect(_on_deck_selected.bind(deck.deck_id))
		deck_list_container.add_child(button)


func _on_deck_selected(deck_id: String) -> void:
	if DeckManager.begin_edit(deck_id) == null:
		_set_status("无法打开该牌组。", true)
		return
	GameState.go_to_deck_editor()


func _on_back_pressed() -> void:
	GameState.go_to_main()


# ----- 新建牌组 -----

func _open_create_deck_popup() -> void:
	if GameState.profile == null:
		_set_status("当前没有玩家存档，无法新建牌组。", true)
		return
	deck_name_input.text = ""
	_populate_hero_options()
	popup_status_label.text = ""
	create_confirm_button.disabled = hero_option.item_count == 0
	if hero_option.item_count == 0:
		popup_status_label.text = "没有可用英雄（请检查 heroes.csv）。"
	create_deck_popup.visible = true
	create_deck_backdrop.visible = true
	deck_name_input.grab_focus()


func _populate_hero_options() -> void:
	hero_option.clear()
	for hero_id: String in HeroDatabase.all_hero_ids():
		var hero: HeroData = HeroDatabase.get_hero(hero_id)
		if hero == null:
			continue
		var faction: String = "P" if hero.faction == "p" else "Z"
		var classes: String = "、".join(hero.class_labels)
		if classes.is_empty():
			classes = "未知职业"
		hero_option.add_item("%s（%s · %s）" % [hero.display_name(), faction, classes])
		hero_option.set_item_metadata(hero_option.item_count - 1, hero.hero_id)


func _on_create_deck_confirmed() -> void:
	if hero_option.item_count == 0:
		popup_status_label.text = "没有可用英雄。"
		return
	var index: int = maxi(hero_option.selected, 0)
	var hero_id: String = str(hero_option.get_item_metadata(index))
	var result: Dictionary = DeckManager.create_deck(hero_id, deck_name_input.text.strip_edges())
	if not bool(result.get("ok", false)):
		popup_status_label.text = str(result.get("message", "新建牌组失败。"))
		return
	var deck: DeckData = DeckManager.get_deck(str(result.get("deck_id", "")))
	_close_create_deck_popup()
	_refresh_list()
	_set_status("已新建牌组：%s" % (deck.deck_name if deck != null else ""))


func _close_create_deck_popup() -> void:
	create_deck_popup.visible = false
	create_deck_backdrop.visible = false


func _on_create_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_create_deck_popup()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)

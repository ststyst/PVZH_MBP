class_name CardInfoDialog
extends AcceptDialog
## 卡牌信息弹窗：外形（无美术素材时用稀有度边框卡片 + 费用/名称/数值布局）、名称、数据、简介，
## 底部“关闭”按钮（AcceptDialog 默认按钮）关闭弹窗。

const RARITY_COLORS: Dictionary = {
	"unknown": Color(0.62, 0.64, 0.70),
	"normal": Color(0.92, 0.93, 0.95),
	"rare": Color(0.45, 0.68, 1.00),
	"super rare": Color(0.78, 0.55, 1.00),
	"legend": Color(1.00, 0.72, 0.32),
}

@onready var card_frame: PanelContainer = %CardFrame
@onready var cost_label: Label = %CostLabel
@onready var name_label: Label = %NameLabel
@onready var meta_label: Label = %MetaLabel
@onready var stats_label: Label = %StatsLabel
@onready var keywords_label: Label = %KeywordsLabel
@onready var tribes_label: Label = %TribesLabel
@onready var description_label: Label = %DescriptionLabel


func _ready() -> void:
	ok_button_text = "关闭"


## 显示一张卡牌的信息。
func show_card(card: CardData) -> void:
	if card == null:
		return
	cost_label.text = str(card.cost)
	name_label.text = card.display_name()
	name_label.add_theme_color_override("font_color", _rarity_color(card.rarity))
	meta_label.text = "%s · %s · %s" % [card.get_type_text(), card.get_class_text(), card.get_rarity_text()]
	if card.is_entity():
		stats_label.text = "攻击 %d　生命 %d　防御 %d" % [card.attack, card.health, card.shield]
	else:
		stats_label.text = "锦囊牌（打出时生效）"
	stats_label.visible = true
	keywords_label.text = card.get_keywords_text()
	keywords_label.visible = not keywords_label.text.is_empty()
	tribes_label.text = card.get_tribes_text()
	tribes_label.visible = not tribes_label.text.is_empty()
	description_label.text = card.description
	_apply_rarity_style(card.rarity)
	popup_centered()


func _apply_rarity_style(rarity: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.15)
	box.border_color = _rarity_color(rarity)
	box.set_border_width_all(3)
	box.set_corner_radius_all(12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	card_frame.add_theme_stylebox_override("panel", box)


func _rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, Color(0.92, 0.93, 0.95))

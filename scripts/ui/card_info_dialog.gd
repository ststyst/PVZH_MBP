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
@onready var preview_frame: Control = %PreviewFrame
@onready var entity_preview: BattleEntityView = %EntityPreview
@onready var art_texture: TextureRect = %CardArt
@onready var cost_label: Label = %CostLabel
@onready var name_label: Label = %NameLabel
@onready var meta_label: Label = %MetaLabel
@onready var stats_label: Label = %StatsLabel
@onready var keywords_label: Label = %KeywordsLabel
@onready var tribes_label: Label = %TribesLabel
@onready var description_label: Label = %DescriptionLabel


func _ready() -> void:
	ok_button_text = "关闭"
	_apply_white_text_style()


func _apply_white_text_style() -> void:
	for label: Label in [cost_label, name_label, meta_label, stats_label, keywords_label, tribes_label, description_label]:
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	cost_label.add_theme_font_size_override("font_size", 42)
	name_label.add_theme_font_size_override("font_size", 30)
	meta_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_font_size_override("font_size", 21)
	keywords_label.add_theme_font_size_override("font_size", 17)
	tribes_label.add_theme_font_size_override("font_size", 16)
	description_label.add_theme_font_size_override("font_size", 17)


## 显示一张卡牌的信息。
func show_card(card: CardData) -> void:
	if card == null:
		return
	cost_label.text = str(card.cost)
	name_label.text = card.display_name()
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
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
	_apply_art(card)
	_apply_preview(card)
	_apply_rarity_style(card.rarity)
	popup_centered()


func _apply_preview(card: CardData) -> void:
	preview_frame.visible = card.is_entity()
	entity_preview.visible = false
	if not card.is_entity():
		return
	var preview_entity := BattleEntity.new()
	preview_entity.setup(card, "p", 0, 0)
	entity_preview.setup(preview_entity)
	entity_preview.visible = true


func _apply_art(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_texture.visible = false
	art_texture.texture = texture


func _apply_rarity_style(_rarity: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 1)
	box.border_color = Color(0, 0, 0, 1)
	box.set_border_width_all(0)
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	card_frame.add_theme_stylebox_override("panel", box)


func _rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, Color(0.92, 0.93, 0.95))

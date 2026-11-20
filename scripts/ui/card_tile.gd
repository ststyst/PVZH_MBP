class_name CardTile
extends Button
## 收藏界面的单张卡牌格子。数据通过 setup() 注入，点击由父界面处理。

const RARITY_COLORS: Dictionary = {
	CardData.RARITY.FREE: Color(0.62, 0.64, 0.70),
	CardData.RARITY.COMMON: Color(0.92, 0.93, 0.95),
	CardData.RARITY.RARE: Color(0.45, 0.68, 1.00),
	CardData.RARITY.EPIC: Color(0.78, 0.55, 1.00),
	CardData.RARITY.LEGENDARY: Color(1.00, 0.72, 0.32),
}

var card_id: String = ""

@onready var name_label: Label = %CardName
@onready var meta_label: Label = %CardMeta
@onready var desc_label: Label = %CardDesc
@onready var owned_label: Label = %CardOwned


## 注入卡牌数据与拥有数量。必须在 add_child 之后调用（依赖 @onready 节点）。
func setup(card: CardData, owned_count: int) -> void:
	card_id = card.card_id
	name_label.text = card.display_name
	name_label.add_theme_color_override("font_color", _rarity_color(card.rarity))
	meta_label.text = _build_meta_text(card)
	desc_label.text = card.description
	_update_owned_text(owned_count)
	tooltip_text = "%s\n%s" % [card.display_name, card.description]


func _build_meta_text(card: CardData) -> String:
	var parts: Array[String] = [
		card.get_rarity_text(),
		card.get_class_text(),
		"费用 %d" % card.cost,
	]
	if card.card_type == CardData.CARD_TYPE.MINION or card.card_type == CardData.CARD_TYPE.WEAPON:
		parts.append("%d/%d" % [card.attack, card.health])
	return " · ".join(parts)


func _update_owned_text(owned_count: int) -> void:
	if owned_count > 0:
		owned_label.text = "已拥有 %d" % owned_count
		owned_label.add_theme_color_override("font_color", Color(0.62, 0.85, 0.65))
	else:
		owned_label.text = "未拥有"
		owned_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.63))


func _rarity_color(rarity: int) -> Color:
	var color: Color = RARITY_COLORS.get(rarity, Color(0.92, 0.93, 0.95))
	return color

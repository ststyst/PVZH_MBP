class_name CardTile
extends Button
## 收藏界面的单张卡牌格子。数据通过 setup() 注入，点击由父界面处理。

const RARITY_COLORS: Dictionary = {
	"unknown": Color(0.62, 0.64, 0.70),
	"normal": Color(0.92, 0.93, 0.95),
	"rare": Color(0.45, 0.68, 1.00),
	"super rare": Color(0.78, 0.55, 1.00),
	"legend": Color(1.00, 0.72, 0.32),
}

var card_id: String = ""

@onready var name_label: Label = %CardName
@onready var meta_label: Label = %CardMeta
@onready var desc_label: Label = %CardDesc
@onready var owned_label: Label = %CardOwned
@onready var art_texture: TextureRect = %CardArt


## 注入卡牌数据与拥有数量。必须在 add_child 之后调用（依赖 @onready 节点）。
## status_text 非空时替换左下角状态文字（例如“拥有 2 · 编入 1”）。
func setup(card: CardData, owned_count: int, status_text: String = "") -> void:
	card_id = card.card_id
	name_label.text = card.display_name()
	name_label.add_theme_color_override("font_color", _rarity_color(card.rarity))
	meta_label.text = _build_meta_text(card)
	desc_label.text = card.description
	_apply_art(card)
	if status_text.is_empty():
		_update_owned_text(owned_count)
	else:
		owned_label.text = status_text
		owned_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	tooltip_text = "%s\n%s" % [card.display_name(), card.description]


func _build_meta_text(card: CardData) -> String:
	var parts: Array[String] = [
		card.get_rarity_text(),
		card.get_class_text(),
		"费用 %d" % card.cost,
	]
	if card.is_entity():
		var stats: String = "%d/%d" % [card.attack, card.health]
		if card.shield > 0:
			stats += " 盾%d" % card.shield
		parts.append(stats)
	return " · ".join(parts)


func _apply_art(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_texture.visible = texture != null
	art_texture.texture = texture


func _update_owned_text(owned_count: int) -> void:
	if owned_count > 0:
		owned_label.text = "已拥有 %d" % owned_count
		owned_label.add_theme_color_override("font_color", Color(0.62, 0.85, 0.65))
	else:
		owned_label.text = "未拥有"
		owned_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.63))


func _rarity_color(rarity: String) -> Color:
	var color: Color = RARITY_COLORS.get(rarity, Color(0.92, 0.93, 0.95))
	return color

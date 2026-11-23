class_name CardTile
extends Button
## 单张卡牌显示（牌组编辑、手牌、起手调度共用）。
## 背景/外观由空 Sprite2D 节点承载；攻击/生命/费用只显示数字，图标由 Sprite2D 素材提供。

const RARITY_COLORS: Dictionary = {
	"unknown": Color(0.62, 0.64, 0.70),
	"normal": Color(0.92, 0.93, 0.95),
	"rare": Color(0.45, 0.68, 1.00),
	"super rare": Color(0.78, 0.55, 1.00),
	"legend": Color(1.00, 0.72, 0.32),
}
const CARD_SIZE: Vector2 = Vector2(126, 104)
const ART_BOX: Vector2 = Vector2(110, 48)
const ART_CENTER: Vector2 = Vector2(63, 28)

var card_id: String = ""

@onready var background_sprite: Sprite2D = %BackgroundSprite
@onready var border_sprite: Sprite2D = %BorderSprite
@onready var art_sprite: Sprite2D = %ArtSprite
@onready var cost_label: Label = %CostLabel
@onready var attack_icon_sprite: Sprite2D = %AttackIconSprite
@onready var health_icon_sprite: Sprite2D = %HealthIconSprite
@onready var attack_label: Label = %AttackLabel
@onready var health_label: Label = %HealthLabel
@onready var name_label: Label = %CardName
@onready var meta_label: Label = %CardMeta
@onready var desc_label: Label = %CardDesc
@onready var owned_label: Label = %CardOwned


## 注入卡牌数据与拥有数量。必须在 add_child 之后调用（依赖 @onready 节点）。
## status_text 非空时替换左下角状态文字（例如“拥有 2 · 编入 1”）。
func setup(card: CardData, owned_count: int, status_text: String = "", show_owned: bool = true) -> void:
	card_id = card.card_id
	_apply_background_sprite(card.rarity)
	_apply_border_sprite(card.rarity)
	_apply_art_sprite(card)
	_apply_stats(card)
	cost_label.text = str(card.cost)
	name_label.text = card.display_name()
	name_label.add_theme_color_override("font_color", _rarity_color(card.rarity))
	meta_label.text = _build_meta_text(card)
	desc_label.text = card.description
	if status_text.is_empty():
		owned_label.visible = show_owned
		if show_owned:
			_update_owned_text(owned_count)
		else:
			owned_label.text = ""
	else:
		owned_label.visible = true
		owned_label.text = status_text
		owned_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	tooltip_text = "%s\n%s" % [card.display_name(), card.description]


func _build_meta_text(card: CardData) -> String:
	return "%s · %s" % [card.get_rarity_text(), card.get_class_text()]


func _apply_background_sprite(rarity: String) -> void:
	var texture: Texture2D = CardArt.get_card_background(rarity)
	background_sprite.visible = texture != null
	background_sprite.texture = texture
	if texture == null:
		return
	background_sprite.position = CARD_SIZE * 0.5
	var cover_scale: float = maxf(
		CARD_SIZE.x / float(texture.get_width()),
		CARD_SIZE.y / float(texture.get_height()),
	)
	background_sprite.scale = Vector2(cover_scale, cover_scale)


func _apply_border_sprite(rarity: String) -> void:
	var texture: Texture2D = CardArt.get_card_border(rarity)
	set_border_texture(texture)


func set_border_texture(texture: Texture2D) -> void:
	border_sprite.texture = texture
	border_sprite.visible = texture != null
	if texture == null:
		return
	border_sprite.position = CARD_SIZE * 0.5
	var cover_scale: float = maxf(
		CARD_SIZE.x / float(texture.get_width()),
		CARD_SIZE.y / float(texture.get_height()),
	)
	border_sprite.scale = Vector2(cover_scale, cover_scale)


func set_border_path(path: String) -> void:
	if path.is_empty():
		set_border_texture(null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_border_texture(texture)


func _apply_art_sprite(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_sprite.visible = texture != null
	art_sprite.texture = texture
	if texture == null:
		return
	art_sprite.position = ART_CENTER
	var contain_scale: float = minf(
		ART_BOX.x / float(texture.get_width()),
		ART_BOX.y / float(texture.get_height()),
	)
	art_sprite.scale = Vector2(contain_scale, contain_scale)


func _apply_stats(card: CardData) -> void:
	var is_entity: bool = card.is_entity()
	attack_label.visible = is_entity
	health_label.visible = is_entity
	attack_icon_sprite.visible = is_entity
	health_icon_sprite.visible = is_entity
	if is_entity:
		attack_label.text = str(card.attack)
		health_label.text = str(card.health)


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

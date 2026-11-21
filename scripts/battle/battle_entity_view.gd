class_name BattleEntityView
extends Control
## 战斗中的场上实体显示（所有实体共用此场景，数据/图片由 setup 注入）。
## 空 Sprite2D：背景、外观、攻击图标、生命图标；数值文本显示在图标上方。

const DESIGN_SIZE: Vector2 = Vector2(136, 84)
const ART_BOX: Vector2 = Vector2(124, 58)
const ART_CENTER: Vector2 = Vector2(68, 34)

@onready var background_sprite: Sprite2D = %BackgroundSprite
@onready var art_sprite: Sprite2D = %ArtSprite
@onready var attack_icon_sprite: Sprite2D = %AttackIconSprite
@onready var health_icon_sprite: Sprite2D = %HealthIconSprite
@onready var name_label: Label = %NameLabel
@onready var attack_label: Label = %AttackLabel
@onready var health_label: Label = %HealthLabel
@onready var border_panel: Panel = %Border


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func setup(entity: BattleEntity) -> void:
	if entity == null or entity.card == null:
		visible = false
		return
	visible = true
	name_label.text = entity.display_name()
	_apply_background(entity.card.rarity)
	_apply_art(entity.card)
	attack_label.text = str(entity.attack)
	health_label.text = str(entity.health)
	attack_label.visible = true
	health_label.visible = true


func set_highlight(enabled: bool) -> void:
	border_panel.visible = enabled


func _apply_background(rarity: String) -> void:
	var texture: Texture2D = CardArt.get_entity_background(rarity)
	background_sprite.visible = texture != null
	background_sprite.texture = texture
	if texture == null:
		return
	background_sprite.position = DESIGN_SIZE * 0.5
	var cover_scale: float = maxf(
		DESIGN_SIZE.x / float(texture.get_width()),
		DESIGN_SIZE.y / float(texture.get_height()),
	)
	background_sprite.scale = Vector2(cover_scale, cover_scale)


func _apply_art(card: CardData) -> void:
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

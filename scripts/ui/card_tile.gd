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
## 边框素材内部透明窗口的缺省矩形（126×104 边框：x5..120, y19..85）。
const DEFAULT_ART_WINDOW: Rect2 = Rect2(5, 19, 116, 67)

var card_id: String = ""

@onready var background_sprite: Sprite2D = %BackgroundSprite
@onready var border_sprite: Sprite2D = %BorderSprite
@onready var art_clip: Control = %ArtClip
@onready var art_texture: TextureRect = %ArtTexture
@onready var cost_label: Label = %CostLabel
@onready var attack_icon_sprite: Sprite2D = %AttackIconSprite
@onready var health_icon_sprite: Sprite2D = %HealthIconSprite
@onready var attack_label: Label = %AttackLabel
@onready var health_label: Label = %HealthLabel
@onready var name_label: Label = %CardName
@onready var meta_label: Label = %CardMeta
@onready var desc_label: Label = %CardDesc
@onready var owned_label: Label = %CardOwned
@onready var content: Control = $Content


## 注入卡牌数据与拥有数量。必须在 add_child 之后调用（依赖 @onready 节点）。
## status_text 非空时替换左下角状态文字（例如“拥有 2 · 编入 1”）。
func setup(card: CardData, owned_count: int, status_text: String = "", show_owned: bool = true, compact: bool = false) -> void:
	card_id = card.card_id
	content.visible = not compact
	_apply_background_sprite(card.rarity)
	_apply_border_sprite(card.rarity)
	_apply_art_sprite(card)
	_apply_stats(card)
	cost_label.text = str(maxi(card.cost, 0))
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


func set_cost(value: int) -> void:
	cost_label.text = str(maxi(value, 0))


## 让按钮本体彻底隐形：清空所有状态的按钮样式盒（含焦点框），
## 只留下素材 Sprite / 插画 / 文字，避免素材没遮住的灰色底板露出来。
func set_chrome_hidden(hidden: bool = true) -> void:
	const STATES: Array[String] = ["normal", "hover", "pressed", "focus", "disabled"]
	flat = hidden
	for state: String in STATES:
		if hidden:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		else:
			remove_theme_stylebox_override(state)


## 覆盖攻击/生命显示（用于手牌实例加成，如“军阀点数”）。
func set_stats(attack: int, health: int) -> void:
	attack_label.text = str(maxi(attack, 0))
	health_label.text = str(maxi(health, 1))


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
	_update_art_window(texture)
	if texture == null:
		return
	border_sprite.position = CARD_SIZE * 0.5
	var cover_scale: float = maxf(
		CARD_SIZE.x / float(texture.get_width()),
		CARD_SIZE.y / float(texture.get_height()),
	)
	border_sprite.scale = Vector2(cover_scale, cover_scale)


## 边框素材内部透明窗口的缓存（同一张边框只扫描一次像素）。
static var _art_window_cache: Dictionary = {}


## 用边框素材的透明内窗作为插画遮罩：只允许内窗区域的插画显示。
func _update_art_window(texture: Texture2D) -> void:
	var cache_key: int = texture.get_instance_id() if texture != null else 0
	if _art_window_cache.has(cache_key):
		var cached: Rect2 = _art_window_cache[cache_key]
		art_clip.position = cached.position
		art_clip.size = cached.size
		return
	var window: Rect2 = DEFAULT_ART_WINDOW
	if texture != null:
		var image: Image = texture.get_image()
		if image != null and image.get_width() > 2 and image.get_height() > 2:
			var width: int = image.get_width()
			var height: int = image.get_height()
			var center_x: int = width / 2
			var center_y: int = height / 2
			var left: int = center_x
			while left > 0 and image.get_pixel(left - 1, center_y).a <= 0.01:
				left -= 1
			var right: int = center_x
			while right < width - 1 and image.get_pixel(right + 1, center_y).a <= 0.01:
				right += 1
			var top: int = center_y
			while top > 0 and image.get_pixel(center_x, top - 1).a <= 0.01:
				top -= 1
			var bottom: int = center_y
			while bottom < height - 1 and image.get_pixel(center_x, bottom + 1).a <= 0.01:
				bottom += 1
			if right > left and bottom > top:
				window = Rect2(left, top, right - left + 1, bottom - top + 1)
				if (
					width != int(CARD_SIZE.x) or height != int(CARD_SIZE.y)
				):
					var scale_ratio: Vector2 = Vector2(
						CARD_SIZE.x / float(width), CARD_SIZE.y / float(height)
					)
					window = Rect2(window.position * scale_ratio, window.size * scale_ratio)
	_art_window_cache[cache_key] = window
	art_clip.position = window.position
	art_clip.size = window.size


func set_border_path(path: String) -> void:
	if path.is_empty():
		set_border_texture(null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_border_texture(texture)


func _apply_art_sprite(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_texture.visible = texture != null
	art_texture.texture = texture


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

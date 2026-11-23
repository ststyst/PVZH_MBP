class_name BattleEntityView
extends Control
## 战斗中的场上实体显示（所有实体共用此场景，数据/图片由 setup 注入）。
## 空 Sprite2D：背景、外观、攻击图标、生命图标；数值文本显示在图标上方。
##
## 动画分三种模式：
## - whole：动画作用在 WholeRoot（背景 + 外观 + 数值整体，像一张图片）
## - background：只作用在 BackgroundRoot
## - art：只作用在 ArtRoot
## 动画素材放在 assets/animations/<mode>.tres（AnimationLibrary，动画名唯一）。

const DESIGN_SIZE: Vector2 = Vector2(136, 84)
const VIEW_MARGIN: float = 2.0
const ART_BOX: Vector2 = Vector2(124, 58)
const ART_CENTER: Vector2 = Vector2(68, 34)
const MODE_WHOLE: String = "whole"
const MODE_BACKGROUND: String = "background"
const MODE_ART: String = "art"
const ANIMATION_LIBRARIES: Dictionary = {
	MODE_WHOLE: "res://assets/animations/whole.tres",
	MODE_BACKGROUND: "res://assets/animations/background.tres",
	MODE_ART: "res://assets/animations/art.tres",
}
const FX_DIR: String = "res://assets/battle/fx/"

@onready var whole_root: Control = %WholeRoot
@onready var background_root: Control = %BackgroundRoot
@onready var art_root: Control = %ArtRoot
@onready var background_sprite: Sprite2D = %BackgroundSprite
@onready var border_sprite: Sprite2D = %BorderSprite
@onready var art_sprite: Sprite2D = %ArtSprite
@onready var attack_icon_sprite: Sprite2D = %AttackIconSprite
@onready var health_icon_sprite: Sprite2D = %HealthIconSprite
@onready var name_label: Label = %NameLabel
@onready var attack_label: Label = %AttackLabel
@onready var health_label: Label = %HealthLabel
@onready var border_panel: Panel = %Border
@onready var whole_player: AnimationPlayer = %WholePlayer
@onready var background_player: AnimationPlayer = %BackgroundPlayer
@onready var art_player: AnimationPlayer = %ArtPlayer


var _last_card: CardData = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = VIEW_MARGIN
	offset_top = VIEW_MARGIN
	offset_right = -VIEW_MARGIN
	offset_bottom = -VIEW_MARGIN
	resized.connect(_on_view_resized)
	_configure_animation_layers()


func _on_view_resized() -> void:
	if _last_card == null:
		return
	_layout_runtime()
	_apply_background(_last_card.rarity)
	_apply_border(_last_card.rarity)
	_apply_art(_last_card)


func _configure_animation_layers() -> void:
	var pivot: Vector2 = DESIGN_SIZE * 0.5
	whole_root.pivot_offset = pivot
	background_root.pivot_offset = pivot
	art_root.pivot_offset = pivot
	for mode: String in ANIMATION_LIBRARIES.keys():
		var path: String = str(ANIMATION_LIBRARIES[mode])
		if not ResourceLoader.exists(path):
			continue
		var library: AnimationLibrary = load(path) as AnimationLibrary
		if library == null:
			continue
		var player: AnimationPlayer = _player_for_mode(mode)
		if player != null and not player.has_animation_library(""):
			player.add_animation_library("", library)


func setup(entity: BattleEntity) -> void:
	if entity == null or entity.card == null:
		visible = false
		return
	visible = true
	_last_card = entity.card
	name_label.text = entity.display_name()
	_layout_runtime()
	_apply_background(entity.card.rarity)
	_apply_border(entity.card.rarity)
	_apply_art(entity.card)
	attack_label.text = str(entity.attack)
	health_label.text = str(entity.health)
	attack_label.visible = true
	health_label.visible = true


func set_highlight(enabled: bool) -> void:
	border_panel.visible = enabled


## 手动替换场上的实体边框；传 null 隐藏。
func set_border_texture(texture: Texture2D) -> void:
	if border_sprite == null:
		return
	border_sprite.texture = texture
	border_sprite.visible = texture != null
	if texture == null:
		return
	border_sprite.position = _view_size() * 0.5
	var cover_scale: float = maxf(
		_view_size().x / float(texture.get_width()),
		_view_size().y / float(texture.get_height()),
	)
	border_sprite.scale = Vector2(cover_scale, cover_scale)


func set_border_path(path: String) -> void:
	if path.is_empty():
		set_border_texture(null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_border_texture(texture)


func _apply_border(rarity: String) -> void:
	set_border_texture(CardArt.get_entity_border(rarity))


func _view_size() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return DESIGN_SIZE


func _layout_runtime() -> void:
	var view: Vector2 = _view_size()
	whole_root.pivot_offset = view * 0.5
	background_root.pivot_offset = view * 0.5
	art_root.pivot_offset = view * 0.5
	name_label.offset_left = 2.0
	name_label.offset_top = 0.0
	name_label.offset_right = view.x - 2.0
	name_label.offset_bottom = 16.0


## 播放指定模式的具名动画，返回动画时长（找不到/无动画时返回 0）。
func play_animation(animation_name: String, mode: String = MODE_WHOLE) -> float:
	var player: AnimationPlayer = _player_for_mode(mode)
	if player == null or animation_name.is_empty() or not player.has_animation(animation_name):
		return 0.0
	player.play(animation_name)
	return player.get_animation(animation_name).length


func stop_animation(mode: String = MODE_WHOLE) -> void:
	var player: AnimationPlayer = _player_for_mode(mode)
	if player != null:
		player.stop()


## 播放通用特效场景（assets/battle/fx/<name>.tscn）。
func play_fx(fx_name: String) -> Node:
	if fx_name.is_empty():
		return null
	var path: String = FX_DIR + fx_name + ".tscn"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var effect: Node = scene.instantiate()
	whole_root.add_child(effect)
	return effect


func _player_for_mode(mode: String) -> AnimationPlayer:
	match mode:
		MODE_BACKGROUND:
			return background_player
		MODE_ART:
			return art_player
		_:
			return whole_player


func _apply_background(rarity: String) -> void:
	var texture: Texture2D = CardArt.get_entity_background(rarity)
	background_sprite.visible = texture != null
	background_sprite.texture = texture
	if texture == null:
		return
	background_sprite.position = _view_size() * 0.5
	var cover_scale: float = maxf(
		_view_size().x / float(texture.get_width()),
		_view_size().y / float(texture.get_height()),
	)
	background_sprite.scale = Vector2(cover_scale, cover_scale)


func _apply_art(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_sprite.visible = texture != null
	art_sprite.texture = texture
	if texture == null:
		return
	var view: Vector2 = _view_size()
	var art_box: Vector2 = Vector2(view.x * 0.96, view.y * 0.70)
	var art_center: Vector2 = Vector2(view.x * 0.5, view.y * 0.33)
	art_sprite.position = art_center
	var contain_scale: float = minf(
		art_box.x / float(texture.get_width()),
		art_box.y / float(texture.get_height()),
	)
	art_sprite.scale = Vector2(contain_scale, contain_scale)

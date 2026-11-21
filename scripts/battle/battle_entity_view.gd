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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_configure_animation_layers()


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
	name_label.text = entity.display_name()
	_apply_background(entity.card.rarity)
	_apply_art(entity.card)
	attack_label.text = str(entity.attack)
	health_label.text = str(entity.health)
	attack_label.visible = true
	health_label.visible = true


func set_highlight(enabled: bool) -> void:
	border_panel.visible = enabled


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

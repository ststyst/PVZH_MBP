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
## 实体显示占可放置按钮的比例；0.95 表示四周各留 2.5% 空隙
const DISPLAY_SIZE_RATIO: float = 0.95
## 实体插画额外放大倍数
const ART_SCALE_MULTIPLIER: float = 1.22
## 实体背景向下显示偏移（像素，正数向下；想改位置只改这里）。
const BACKGROUND_OFFSET_Y: float = 8.0
## 实体背景额外放大倍数；>1 时背景允许超出实体放置格。
const BACKGROUND_SCALE_MULTIPLIER: float = 1.0
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
## 位移期间的临时 z_index：保证扑向目标时不会被同格/相邻格的视图压住。
const MOTION_Z_INDEX: int = 40
## 缓动 token → [Tween.TransitionType, Tween.EaseType]。
## token 白名单在 CardAnimationScript.EASINGS，决定伪代码里能写什么。
const MOTION_EASINGS: Dictionary = {
	"linear": [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT],
	"ease_in": [Tween.TRANS_QUAD, Tween.EASE_IN],
	"ease_out": [Tween.TRANS_QUAD, Tween.EASE_OUT],
	"ease_in_out": [Tween.TRANS_QUAD, Tween.EASE_IN_OUT],
	"back_out": [Tween.TRANS_BACK, Tween.EASE_OUT],
	"bounce_out": [Tween.TRANS_BOUNCE, Tween.EASE_OUT],
}

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
## 位移状态：首次 move_by 时记住原位的四个 offset，
## 之后一律用「锚点 + 这些 offset」推导原位，避免棋盘重排后累积偏移。
var _motion_active: bool = false
var _motion_home_offsets: Vector4 = Vector4.ZERO
var _motion_saved_z: int = 0
var _motion_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var inset: float = (1.0 - DISPLAY_SIZE_RATIO) * 0.5
	anchor_left = inset
	anchor_top = inset
	anchor_right = 1.0 - inset
	anchor_bottom = 1.0 - inset
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
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


## 把整个视图平移到「原位 + offset」，返回时长（秒）。
## 用于「攻击者扑到受击者身上」这类运行时才知道坐标的位移：
## 目标坐标由 UI 在播放动画时用两个视图的 global_position 相减得到。
## easing 见 MOTION_EASINGS（默认 ease_in：加速撞过去，收尾干脆有冲击力）。
func move_by(offset: Vector2, seconds: float, easing: String = "ease_in") -> float:
	var duration: float = maxf(seconds, 0.01)
	if not _motion_active:
		_motion_home_offsets = Vector4(offset_left, offset_top, offset_right, offset_bottom)
		_motion_saved_z = z_index
		_motion_active = true
	z_index = maxi(z_index, MOTION_Z_INDEX)
	_start_motion_tween(_home_position() + offset, duration, easing)
	return duration


## 回到原位，返回时长（秒）；没移动过则返回 0。
func move_home(seconds: float, easing: String = "ease_out") -> float:
	if not _motion_active:
		return 0.0
	var duration: float = maxf(seconds, 0.01)
	_start_motion_tween(_home_position(), duration, easing)
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.finished.connect(_on_motion_finished, CONNECT_ONE_SHOT)
	return duration


## 立即复位（动画脚本没写 move_back、或视图被复用/打断时兜底）。
## 直接还原四个 offset，而不是写回缓存的 position：这样布局尺寸变化后依然贴合格子。
func reset_motion() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null
	if not _motion_active:
		return
	offset_left = _motion_home_offsets.x
	offset_top = _motion_home_offsets.y
	offset_right = _motion_home_offsets.z
	offset_bottom = _motion_home_offsets.w
	z_index = _motion_saved_z
	_motion_active = false


func is_moving() -> bool:
	return _motion_active


## 原位（未位移时）的 position：锚点 × 父容器尺寸 + 记下的 offset。
## 不用缓存的 position，避免棋盘/手牌重排导致基准漂移。
func _home_position() -> Vector2:
	var parent_control: Control = get_parent() as Control
	if parent_control == null:
		return position
	return Vector2(
		parent_control.size.x * anchor_left + _motion_home_offsets.x,
		parent_control.size.y * anchor_top + _motion_home_offsets.y,
	)


func _start_motion_tween(target_position: Vector2, duration: float, easing: String) -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween()
	var preset: Array = MOTION_EASINGS.get(easing, MOTION_EASINGS["ease_out"])
	_motion_tween.set_trans(int(preset[0])).set_ease(int(preset[1]))
	_motion_tween.tween_property(self, "position", target_position, duration)


func _on_motion_finished() -> void:
	_motion_tween = null
	if not _motion_active:
		return
	# 回到原位时也走 offset 还原，布局中途变化也不会残留偏移。
	reset_motion()


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
	background_sprite.position = _view_size() * 0.5 + Vector2(0.0, BACKGROUND_OFFSET_Y)
	var cover_scale: float = maxf(
		_view_size().x / float(texture.get_width()),
		_view_size().y / float(texture.get_height()),
	) * BACKGROUND_SCALE_MULTIPLIER
	background_sprite.scale = Vector2(cover_scale, cover_scale)


func _apply_art(card: CardData) -> void:
	var texture: Texture2D = CardArt.get_texture(card.art_path)
	art_sprite.visible = texture != null
	art_sprite.texture = texture
	if texture == null:
		return
	if texture == null or texture.get_width() <= 0:
		return
	var view: Vector2 = _view_size()
	art_sprite.position = Vector2(view.x * 0.5, view.y * 0.5)
	var width_scale: float = view.x / float(texture.get_width())
	art_sprite.scale = Vector2(
		width_scale * ART_SCALE_MULTIPLIER,
		width_scale * ART_SCALE_MULTIPLIER,
	)

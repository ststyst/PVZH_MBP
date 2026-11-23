class_name CardArt
extends RefCounted
## 卡牌美术加载：
## - 卡面外观：按 CardData.art_path 载入 Texture2D
## - 卡牌背景：按稀有度载入 assets/cards/backgrounds/<rarity>.png（9 宫格拉伸）
## 空路径/加载失败返回 null（回退纯色外观）。

const CARD_BACKGROUND_DIR: String = "res://assets/cards/backgrounds/"
const DEFAULT_CARD_ART: String = "res://assets/cards/art/XXXdefault.png"
const CARD_BORDER_DIR: String = "res://assets/cards/borders/"
const ENTITY_BACKGROUND_DIR: String = "res://assets/battle/entities/"
const ENTITY_BORDER_DIR: String = "res://assets/battle/entities/borders/"
const ENTITY_BACKGROUND_UNIVERSAL: String = "res://assets/battle/entities/background.png"
const ENTITY_BORDER_UNIVERSAL: String = "res://assets/battle/entities/borders/border.png"
## 背景图 9 宫格边距（建议素材按 512×640、边框 32px 制作）
const CARD_BACKGROUND_SLICE: int = 32

static var _cache: Dictionary = {}
static var _background_cache: Dictionary = {}
static var _background_style_cache: Dictionary = {}
static var _entity_background_cache: Dictionary = {}
static var _border_cache: Dictionary = {}
static var _entity_border_cache: Dictionary = {}


static func get_texture(art_path: String) -> Texture2D:
	var path: String = art_path.strip_edges()
	if path.is_empty():
		path = DEFAULT_CARD_ART
	if _cache.has(path):
		return _cache[path] as Texture2D
	var texture: Texture2D = _load_valid_texture(path)
	if texture == null and path != DEFAULT_CARD_ART:
		texture = _load_valid_texture(DEFAULT_CARD_ART)
	_cache[path] = texture
	return texture


static func _load_valid_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	var texture: Texture2D = resource as Texture2D
	if texture == null:
		return null
	if texture.get_width() <= 0 or texture.get_height() <= 0:
		return null
	return texture


## 稀有度对应的背景文件名（"super rare" -> "super_rare"）。
static func rarity_slug(rarity: String) -> String:
	return rarity.strip_edges().to_lower().replace(" ", "_")


## 按稀有度取卡牌背景图；没有素材时返回 null。
static func get_card_background(rarity: String) -> Texture2D:
	var slug: String = rarity_slug(rarity)
	if _background_cache.has(slug):
		return _background_cache[slug] as Texture2D
	var path: String = CARD_BACKGROUND_DIR + slug + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_background_cache[slug] = texture
	return texture


## 按稀有度取卡牌背景 StyleBoxTexture（9 宫格）；没有素材时返回 null。
static func get_card_background_style(rarity: String) -> StyleBoxTexture:
	var slug: String = rarity_slug(rarity)
	if _background_style_cache.has(slug):
		return _background_style_cache[slug] as StyleBoxTexture
	var texture: Texture2D = get_card_background(rarity)
	if texture == null:
		_background_style_cache[slug] = null
		return null
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = CARD_BACKGROUND_SLICE
	style.texture_margin_top = CARD_BACKGROUND_SLICE
	style.texture_margin_right = CARD_BACKGROUND_SLICE
	style.texture_margin_bottom = CARD_BACKGROUND_SLICE
	_background_style_cache[slug] = style
	return style


## 场上实体背景：优先 <稀有度>.png，其次通用 background.png，最后回退卡牌稀有度背景。
static func get_card_border(rarity: String) -> Texture2D:
	var slug: String = rarity_slug(rarity)
	if _border_cache.has(slug):
		return _border_cache[slug] as Texture2D
	var path: String = CARD_BORDER_DIR + slug + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_border_cache[slug] = texture
	return texture


static func get_entity_border(rarity: String) -> Texture2D:
	var slug: String = rarity_slug(rarity)
	if _entity_border_cache.has(slug):
		return _entity_border_cache[slug] as Texture2D
	var texture: Texture2D = null
	var specific_path: String = ENTITY_BORDER_DIR + slug + ".png"
	if ResourceLoader.exists(specific_path):
		texture = load(specific_path) as Texture2D
	elif ResourceLoader.exists(ENTITY_BORDER_UNIVERSAL):
		texture = load(ENTITY_BORDER_UNIVERSAL) as Texture2D
	_entity_border_cache[slug] = texture
	return texture


static func get_entity_background(rarity: String) -> Texture2D:
	var slug: String = rarity_slug(rarity)
	if _entity_background_cache.has(slug):
		return _entity_background_cache[slug] as Texture2D
	var texture: Texture2D = null
	var specific_path: String = ENTITY_BACKGROUND_DIR + slug + ".png"
	if ResourceLoader.exists(specific_path):
		texture = load(specific_path) as Texture2D
	elif ResourceLoader.exists(ENTITY_BACKGROUND_UNIVERSAL):
		texture = load(ENTITY_BACKGROUND_UNIVERSAL) as Texture2D
	else:
		texture = get_card_background(rarity)
	_entity_background_cache[slug] = texture
	return texture


static func clear_cache() -> void:
	_cache.clear()
	_background_cache.clear()
	_background_style_cache.clear()
	_entity_background_cache.clear()
	_border_cache.clear()
	_entity_border_cache.clear()

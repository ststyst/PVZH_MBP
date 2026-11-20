class_name CardArt
extends RefCounted
## 卡牌美术加载：
## - 卡面外观：按 CardData.art_path 载入 Texture2D
## - 卡牌背景：按稀有度载入 assets/cards/backgrounds/<rarity>.png（9 宫格拉伸）
## 空路径/加载失败返回 null（回退纯色外观）。

const CARD_BACKGROUND_DIR: String = "res://assets/cards/backgrounds/"
## 背景图 9 宫格边距（建议素材按 512×640、边框 32px 制作）
const CARD_BACKGROUND_SLICE: int = 32

static var _cache: Dictionary = {}
static var _background_cache: Dictionary = {}
static var _background_style_cache: Dictionary = {}


static func get_texture(art_path: String) -> Texture2D:
	var path: String = art_path.strip_edges()
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_cache[path] = texture
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


static func clear_cache() -> void:
	_cache.clear()
	_background_cache.clear()
	_background_style_cache.clear()

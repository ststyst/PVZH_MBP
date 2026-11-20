class_name CardArt
extends RefCounted
## 卡牌美术加载：按 art_path 载入 Texture2D 并缓存；空路径/加载失败返回 null（回退纯色外观）。

static var _cache: Dictionary = {}


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


static func clear_cache() -> void:
	_cache.clear()

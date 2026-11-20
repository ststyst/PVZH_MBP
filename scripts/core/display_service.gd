extends Node
## 显示适配服务：竖屏 9:16。
## - 电脑：按屏幕可用高度自适应窗口大小，窗口可自由拉伸（等比缩放 + 黑边，画面不裁切）；
## - 手机：跟随设备屏幕，只调整逻辑分辨率（content_scale_size）。
## 设置界面用 get_presets() 渲染选项、apply_preset(id) 应用，选择会持久化。

signal display_changed(preset_id: String, width: int, height: int)

const BASE_WIDTH: int = 720
const BASE_HEIGHT: int = 1280
const ASPECT_WIDTH: int = 9
const ASPECT_HEIGHT: int = 16
## 桌面窗口最多占屏幕可用高度的比例，确保窗口完整可见
const DESKTOP_SCREEN_RATIO: float = 0.92
const MIN_WINDOW_WIDTH: int = 270
const MIN_WINDOW_HEIGHT: int = 480
const PRESET_AUTO: String = "auto"

enum DEVICE { DESKTOP, MOBILE }


func _ready() -> void:
	_configure_window_defaults()
	var saved_preset: String = AppStorage.get_display_preset()
	if not apply_preset(saved_preset):
		apply_preset(PRESET_AUTO)


# ----- 设备与预设 -----

## 当前设备类型（有 mobile 特性标签即视为手机/平板）。
func get_device_type() -> int:
	if OS.has_feature("mobile"):
		return DEVICE.MOBILE
	return DEVICE.DESKTOP


func get_device_label() -> String:
	return "手机屏幕" if get_device_type() == DEVICE.MOBILE else "电脑窗口"


## 当前设备可选的显示预设。设置界面把它渲染成下拉框/列表即可。
func get_presets() -> Array[Dictionary]:
	return presets_for_device(get_device_type())


func get_current_preset_id() -> String:
	var preset_id: String = AppStorage.get_display_preset()
	if preset_id.is_empty():
		return PRESET_AUTO
	return preset_id


## 应用预设并持久化；未知预设返回 false。
func apply_preset(preset_id: String) -> bool:
	if not is_inside_tree():
		return false
	var target_id: String = preset_id if not preset_id.is_empty() else PRESET_AUTO
	var presets: Array[Dictionary] = get_presets()
	for preset: Dictionary in presets:
		if str(preset.get("id", "")) != target_id:
			continue
		if get_device_type() == DEVICE.DESKTOP:
			if bool(preset.get("auto", false)):
				_apply_desktop_auto()
			else:
				set_window_size(int(preset.get("width", 540)), int(preset.get("height", 960)))
		else:
			_apply_mobile_preset(preset)
		AppStorage.set_display_preset(target_id)
		_emit_current(target_id)
		return true
	return false


## 重新按当前设备应用「自动」预设。
func apply_device_default() -> bool:
	return apply_preset(PRESET_AUTO)


# ----- 桌面：窗口大小 -----

## 设置窗口像素大小；自动限制在屏幕可用区域内并保持 9:16 比例。
func set_window_size(width: int, height: int) -> void:
	if not is_inside_tree():
		return
	var window: Window = get_window()
	if window == null:
		return
	var fitted: Vector2i = fit_window_size(Vector2i(width, height), _usable_screen_size())
	window.size = fitted


## 当前窗口像素大小。
func get_window_size() -> Vector2i:
	var window: Window = get_window() if is_inside_tree() else null
	if window == null:
		return Vector2i.ZERO
	return window.size


# ----- 手机：逻辑分辨率 -----

## 设置逻辑分辨率（影响 UI 缩放与渲染清晰度；窗口大小由系统决定）。
func set_content_resolution(width: int, height: int) -> void:
	if not is_inside_tree():
		return
	var window: Window = get_window()
	if window == null:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(
		maxi(width, MIN_WINDOW_WIDTH),
		maxi(height, MIN_WINDOW_HEIGHT),
	)


func get_content_resolution() -> Vector2i:
	var window: Window = get_window() if is_inside_tree() else null
	if window == null:
		return Vector2i.ZERO
	return window.content_scale_size


# ----- 静态工具（可单独测试） -----

## 某设备类型的预设列表：id / label / description / width / height / auto。
static func presets_for_device(device: int) -> Array[Dictionary]:
	var presets: Array[Dictionary] = []
	if device == DEVICE.DESKTOP:
		presets.append({
			"id": PRESET_AUTO,
			"label": "自动适配窗口",
			"description": "按屏幕可用高度自动缩放，保持 9:16 竖屏",
			"width": 0,
			"height": 0,
			"auto": true,
		})
		presets.append({
			"id": "540x960",
			"label": "标准窗口 540×960",
			"description": "适合多数 1080p / 2K 显示器",
			"width": 540,
			"height": 960,
			"auto": false,
		})
		presets.append({
			"id": "720x1280",
			"label": "竖屏高清 720×1280",
			"description": "屏幕不够高时会自动等比缩小，保证窗口完整",
			"width": 720,
			"height": 1280,
			"auto": false,
		})
		presets.append({
			"id": "405x720",
			"label": "小巧窗口 405×720",
			"description": "适合小屏或分屏使用",
			"width": 405,
			"height": 720,
			"auto": false,
		})
	else:
		presets.append({
			"id": PRESET_AUTO,
			"label": "跟随设备屏幕",
			"description": "铺满屏幕，按 9:16 等比缩放，多余部分留黑边",
			"width": BASE_WIDTH,
			"height": BASE_HEIGHT,
			"auto": true,
		})
		presets.append({
			"id": "720x1280",
			"label": "逻辑分辨率 720×1280",
			"description": "省电、性能友好",
			"width": 720,
			"height": 1280,
			"auto": false,
		})
		presets.append({
			"id": "1080x1920",
			"label": "逻辑分辨率 1080×1920",
			"description": "画面更细腻，中高端手机推荐",
			"width": 1080,
			"height": 1920,
			"auto": false,
		})
		presets.append({
			"id": "1440x2560",
			"label": "逻辑分辨率 1440×2560",
			"description": "旗舰机 2K，更耗性能",
			"width": 1440,
			"height": 2560,
			"auto": false,
		})
	return presets


## 把请求的窗口大小限制到屏幕可用区域，并保持 9:16 比例。
static func fit_window_size(requested: Vector2i, usable: Vector2i) -> Vector2i:
	var max_height: int = requested.y
	if usable.y > 0:
		max_height = int(float(usable.y) * DESKTOP_SCREEN_RATIO)
	max_height = maxi(max_height, MIN_WINDOW_HEIGHT)
	var max_width: int = requested.x
	if usable.x > 0:
		max_width = int(float(usable.x) * DESKTOP_SCREEN_RATIO)
	max_width = maxi(max_width, MIN_WINDOW_WIDTH)
	var height: int = clampi(requested.y, MIN_WINDOW_HEIGHT, max_height)
	var width: int = int(round(float(height) * float(ASPECT_WIDTH) / float(ASPECT_HEIGHT)))
	if width > max_width:
		width = max_width
		height = int(round(float(width) * float(ASPECT_HEIGHT) / float(ASPECT_WIDTH)))
		height = maxi(height, MIN_WINDOW_HEIGHT)
	return Vector2i(maxi(width, MIN_WINDOW_WIDTH), maxi(height, MIN_WINDOW_HEIGHT))


# ----- 内部 -----

func _configure_window_defaults() -> void:
	var window: Window = get_window() if is_inside_tree() else null
	if window == null:
		return
	window.min_size = Vector2i(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(BASE_WIDTH, BASE_HEIGHT)


func _apply_desktop_auto() -> void:
	var usable: Vector2i = _usable_screen_size()
	var target_height: int = BASE_HEIGHT
	if usable.y > 0:
		target_height = mini(BASE_HEIGHT, int(float(usable.y) * DESKTOP_SCREEN_RATIO))
	target_height = maxi(target_height, MIN_WINDOW_HEIGHT)
	var target_width: int = int(round(float(target_height) * float(ASPECT_WIDTH) / float(ASPECT_HEIGHT)))
	set_window_size(target_width, target_height)


func _apply_mobile_preset(preset: Dictionary) -> void:
	set_content_resolution(int(preset.get("width", BASE_WIDTH)), int(preset.get("height", BASE_HEIGHT)))


func _usable_screen_size() -> Vector2i:
	var screen: int = DisplayServer.window_get_current_screen()
	var rect: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if rect.size.x > 0 and rect.size.y > 0:
		return rect.size
	var full_size: Vector2i = DisplayServer.screen_get_size(screen)
	if full_size.x > 0 and full_size.y > 0:
		return full_size
	return Vector2i(BASE_WIDTH * 2, BASE_HEIGHT * 2)


func _emit_current(preset_id: String) -> void:
	var size: Vector2i = Vector2i.ZERO
	if get_device_type() == DEVICE.DESKTOP:
		size = get_window_size()
	else:
		size = get_content_resolution()
	display_changed.emit(preset_id, size.x, size.y)

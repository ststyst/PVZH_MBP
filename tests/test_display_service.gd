@tool
extends McpTestSuite
## 竖屏显示适配测试（预设表与窗口适配计算）。suite = "display"。

const DisplayServiceScript := preload("res://scripts/core/display_service.gd")

var service: Node = null


func suite_name() -> String:
	return "display"


func setup() -> void:
	service = DisplayServiceScript.new()


func teardown() -> void:
	if is_instance_valid(service):
		service.free()
	service = null


func test_base_resolution_is_portrait() -> void:
	assert_eq(DisplayServiceScript.BASE_WIDTH, 720)
	assert_eq(DisplayServiceScript.BASE_HEIGHT, 1280)
	assert_eq(DisplayServiceScript.PRESET_AUTO, "auto")


func test_desktop_presets() -> void:
	var presets: Array[Dictionary] = service.presets_for_device(0)
	assert_true(presets.size() >= 3, "电脑端应提供至少 3 个窗口预设")
	var ids: Array[String] = []
	for preset: Dictionary in presets:
		ids.append(str(preset.get("id", "")))
	assert_true(ids.has("auto"), "应包含自动适配")
	assert_true(ids.has("540x960"))
	assert_true(ids.has("720x1280"))
	for preset: Dictionary in presets:
		assert_true(not str(preset.get("label", "")).is_empty(), "每个预设应有显示名称")


func test_mobile_presets() -> void:
	var presets: Array[Dictionary] = service.presets_for_device(1)
	assert_true(presets.size() >= 3, "手机端应提供至少 3 个分辨率预设")
	var ids: Array[String] = []
	for preset: Dictionary in presets:
		ids.append(str(preset.get("id", "")))
	assert_true(ids.has("auto"))
	assert_true(ids.has("1080x1920"))
	assert_true(ids.has("1440x2560"))


func test_fit_window_size_on_1080p() -> void:
	var fitted: Vector2i = service.fit_window_size(Vector2i(720, 1280), Vector2i(1920, 1040))
	assert_true(fitted.y <= int(1040 * 0.92) + 1, "窗口高度不能超过屏幕可用高度")
	assert_true(fitted.x <= 1920, "窗口宽度不能超过屏幕宽度")
	assert_true(fitted.y >= 480, "窗口不能小到无法操作")
	var ratio: float = float(fitted.x) / float(fitted.y)
	assert_true(absf(ratio - 9.0 / 16.0) < 0.02, "窗口应保持 9:16 竖屏比例")


func test_fit_window_size_on_small_screen() -> void:
	var fitted: Vector2i = service.fit_window_size(Vector2i(720, 1280), Vector2i(1366, 728))
	assert_true(fitted.y <= 728, "小屏幕上窗口必须完整可见")
	assert_true(fitted.x <= 1366)
	assert_true(fitted.y >= 480)


func test_device_detection() -> void:
	if OS.has_feature("mobile"):
		assert_eq(service.get_device_type(), 1)
	else:
		assert_eq(service.get_device_type(), 0, "桌面环境应识别为电脑窗口")
	assert_false(service.get_device_label().is_empty())

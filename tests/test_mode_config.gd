@tool
extends McpTestSuite
## 玩法配置测试。suite = "mode"。

const MODE_FILE: String = "res://data/modes/default_mode.json"
const TEMP_FILE: String = "user://test_mode_config.json"


func suite_name() -> String:
	return "mode"


func setup() -> void:
	_cleanup()


func teardown() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEMP_FILE):
		DirAccess.remove_absolute(TEMP_FILE)


func test_defaults() -> void:
	var config: GameModeConfig = GameModeConfig.default_config()
	assert_eq(config.deck_max_size, 40)
	assert_true(config.enforce_full_deck)
	assert_eq(config.max_copies_by_rarity.size(), 8)
	assert_eq(config.max_copies_for_rarity_index(0), 4, "normal 应为 4")
	assert_eq(config.max_copies_for_rarity_index(3), 4, "legend 按默认数组为 4")
	assert_eq(config.max_copies_for_rarity_index(4), 1, "unknown 应为 1")
	assert_eq(config.max_copies_for_rarity_index(9), 1, "超出数组默认 1")
	assert_eq(config.player_hero_max_health, 20)
	assert_eq(config.enemy_hero_max_health, 20)
	assert_eq(config.player_initial_energy, 1)
	assert_eq(config.enemy_initial_energy, 1)
	assert_eq(config.player_initial_draw, 4)
	assert_eq(config.enemy_initial_draw, 4)
	assert_eq(config.hand_limit, 10)
	assert_eq(config.energy_cap, 99)
	assert_eq(config.phase_time_limit_seconds, 40)
	assert_eq(config.player_draw_per_turn, 1)
	assert_eq(config.enemy_draw_per_turn, 1)
	assert_eq(config.team_up_swap_cooldown_seconds, 0.35)


func test_from_dict_overrides() -> void:
	var config: GameModeConfig = GameModeConfig.from_dict({
		"deck_max_size": 30,
		"enforce_full_deck": false,
		"max_copies_by_rarity": [2, 2],
		"player_hero_max_health": 25,
		"enemy_hero_max_health": 30,
		"player_initial_energy": 2,
		"enemy_initial_energy": 3,
		"player_initial_draw": 5,
		"enemy_initial_draw": 6,
		"hand_limit": 8,
		"energy_cap": 12,
		"phase_time_limit_seconds": 15,
		"player_draw_per_turn": 2,
		"enemy_draw_per_turn": 0,
		"team_up_swap_cooldown_seconds": 0.8,
	})
	assert_eq(config.deck_max_size, 30)
	assert_false(config.enforce_full_deck)
	assert_eq(config.max_copies_for_rarity_index(0), 2)
	assert_eq(config.max_copies_for_rarity_index(1), 2)
	assert_eq(config.max_copies_for_rarity_index(2), 1, "超出数组的稀有度默认 1")
	assert_eq(config.hero_max_health_for_faction("p"), 25)
	assert_eq(config.hero_max_health_for_faction("z"), 30)
	assert_eq(config.initial_energy_for_faction("p"), 2)
	assert_eq(config.initial_energy_for_faction("z"), 3)
	assert_eq(config.initial_draw_for_faction("p"), 5)
	assert_eq(config.initial_draw_for_faction("z"), 6)
	assert_eq(config.hand_limit, 8)
	assert_eq(config.energy_cap, 12)
	assert_eq(config.phase_time_limit_seconds, 15)
	assert_eq(config.player_draw_per_turn, 2)
	assert_eq(config.enemy_draw_per_turn, 0)
	assert_eq(config.team_up_swap_cooldown_seconds, 0.8)


func test_from_default_file() -> void:
	var config: GameModeConfig = GameModeConfig.from_file(MODE_FILE)
	assert_eq(config.load_errors.size(), 0, "默认玩法文件应无错误：%s" % [config.load_errors])
	assert_eq(config.deck_max_size, 40)
	assert_true(config.enforce_full_deck)
	assert_eq(config.max_copies_for_rarity_index(0), 4)
	assert_eq(config.max_copies_for_rarity_index(4), 1)


func test_missing_file_uses_defaults() -> void:
	var config: GameModeConfig = GameModeConfig.from_file("user://definitely_missing_mode.json")
	assert_true(config.load_errors.size() > 0, "缺少文件应记录错误")
	assert_eq(config.deck_max_size, 40)
	assert_true(config.enforce_full_deck)


func test_custom_file() -> void:
	var file: FileAccess = FileAccess.open(TEMP_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"deck_max_size": 24,
		"enforce_full_deck": false,
		"player_hero_max_health": 15,
		"enemy_hero_max_health": 25,
	}))
	file.close()
	var config: GameModeConfig = GameModeConfig.from_file(TEMP_FILE)
	assert_eq(config.load_errors.size(), 0)
	assert_eq(config.deck_max_size, 24)
	assert_false(config.enforce_full_deck)
	assert_eq(config.hero_max_health_for_faction("p"), 15)
	assert_eq(config.hero_max_health_for_faction("z"), 25)
	assert_eq(config.max_copies_for_rarity_index(0), 4, "未配置的字段应保持默认")

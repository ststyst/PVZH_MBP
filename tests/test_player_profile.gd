@tool
extends McpTestSuite
## 玩家数据模型测试：货币、时长、序列化与旧存档迁移。suite = "profile"。

func suite_name() -> String:
	return "profile"


func test_currency_add_spend() -> void:
	var profile := PlayerProfile.create_default("货币")
	profile.gold = 100
	profile.diamond = 0
	profile.add_gold(50)
	assert_eq(profile.gold, 150)
	assert_true(profile.spend_gold(100))
	assert_eq(profile.gold, 50)
	assert_false(profile.spend_gold(999), "余额不足时应拒绝扣除")
	assert_eq(profile.gold, 50)
	profile.add_diamond(30)
	assert_eq(profile.diamond, 30)
	assert_true(profile.spend_diamond(10))
	assert_eq(profile.diamond, 20)
	assert_false(profile.spend_diamond(100))
	assert_eq(profile.diamond, 20)


func test_serialization_new_fields() -> void:
	var profile := PlayerProfile.create_default("序列化", true)
	profile.gold = 7
	profile.diamond = 3
	profile.play_time_seconds = 3661
	var restored := PlayerProfile.from_dict(profile.to_dict())
	assert_eq(restored.gold, 7)
	assert_eq(restored.diamond, 3)
	assert_eq(restored.play_time_seconds, 3661)
	assert_true(restored.is_developer_save)
	assert_eq(restored.get_play_time_text(), "01:01:01")


func test_legacy_arcane_dust_migration() -> void:
	var legacy: Dictionary = {
		"player_name": "老存档",
		"gold": 5,
		"arcane_dust": 42,
	}
	var profile := PlayerProfile.from_dict(legacy)
	assert_eq(profile.gold, 5)
	assert_eq(profile.diamond, 42, "旧字段 arcane_dust 应迁移为 diamond")
	assert_eq(profile.play_time_seconds, 0)
	assert_false(profile.is_developer_save)


func test_play_time_text() -> void:
	var profile := PlayerProfile.create_default("时长")
	assert_eq(profile.get_play_time_text(), "00:00:00")
	profile.play_time_seconds = 59
	assert_eq(profile.get_play_time_text(), "00:00:59")
	profile.play_time_seconds = 3600
	assert_eq(profile.get_play_time_text(), "01:00:00")
	profile.play_time_seconds = 90061
	assert_eq(profile.get_play_time_text(), "25:01:01")

class_name SaveSlotInfo
extends RefCounted
## 存档列表项摘要：只含登录/选档界面展示需要的字段，避免为列表加载整份存档。

var slot_key: String = ""
var player_name: String = ""
var last_played_unix: int = 0
var play_time_seconds: int = 0
var deck_count: int = 0
var gold: int = 0
var diamond: int = 0
var schema_version: int = 0
var active_deck_id: String = ""
var is_developer_save: bool = false


## 游玩时长的 HH:MM:SS 文本，供列表直接显示。
func get_play_time_text() -> String:
	var total: int = maxi(play_time_seconds, 0)
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]

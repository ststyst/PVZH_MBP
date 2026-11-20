class_name SaveSlotInfo
extends RefCounted
## 存档列表项摘要：只含登录界面展示需要的字段，避免为列表加载整份存档。

var slot_key: String = ""
var player_name: String = ""
var last_played_unix: int = 0
var deck_count: int = 0
var gold: int = 0
var schema_version: int = 0
var active_deck_id: String = ""

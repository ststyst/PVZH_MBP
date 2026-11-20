class_name PlayerProfile
extends Resource
## 单个存档的玩家数据（单机身份）。服务器身份下同类数据由服务器托管，本地不保存。

const SCHEMA_VERSION: int = 2
const STARTING_GOLD: int = 100
const STARTING_DIAMOND: int = 0

var schema_version: int = SCHEMA_VERSION
var profile_id: String = ""
var player_name: String = ""
var created_at_unix: int = 0
var last_played_unix: int = 0

## 累计游玩时长（秒）。由 GameState 计时写入，退出/定期自动保存。
var play_time_seconds: int = 0
## 开发者存档标记：在编辑器内运行时创建的存档为 true。
var is_developer_save: bool = false

## 两种货币：gold = 金币（通用），diamond = 钻石（稀有，用于合成等）
var gold: int = STARTING_GOLD
var diamond: int = STARTING_DIAMOND

## 收藏：card_id -> 拥有数量
var owned_cards: Dictionary[String, int] = {}

## 牌组列表与当前启用牌组
var decks: Array[DeckData] = []
var active_deck_id: String = ""

## 主线进度：level_id -> 是否通关
var campaign_progress: Dictionary[String, bool] = {}

## 统计：wins / losses / matches 等
var stats: Dictionary[String, int] = {}


## 创建全新存档数据。
static func create_default(profile_name: String, is_developer: bool = false) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.schema_version = SCHEMA_VERSION
	profile.profile_id = "profile_%d" % int(Time.get_unix_time_from_system())
	profile.player_name = profile_name
	profile.created_at_unix = int(Time.get_unix_time_from_system())
	profile.last_played_unix = profile.created_at_unix
	profile.is_developer_save = is_developer
	return profile


func touch() -> void:
	last_played_unix = int(Time.get_unix_time_from_system())


# ----- 货币 -----

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	touch()


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	touch()
	return true


func add_diamond(amount: int) -> void:
	if amount <= 0:
		return
	diamond += amount
	touch()


func spend_diamond(amount: int) -> bool:
	if amount <= 0 or diamond < amount:
		return false
	diamond -= amount
	touch()
	return true


# ----- 游玩时长 -----

## 把秒数格式化成 HH:MM:SS，供存档列表等 UI 展示。
func get_play_time_text() -> String:
	var total: int = maxi(play_time_seconds, 0)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


# ----- 收藏 -----

func get_card_count(card_id: String) -> int:
	return int(owned_cards.get(card_id, 0))


func has_card(card_id: String) -> bool:
	return get_card_count(card_id) > 0


func add_card(card_id: String, count: int = 1) -> void:
	if card_id.is_empty() or count <= 0:
		return
	owned_cards[card_id] = get_card_count(card_id) + count
	touch()


## 移除卡牌；数量不足时返回 false 且不修改。
func remove_card(card_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var current: int = get_card_count(card_id)
	if current < count:
		return false
	if current == count:
		owned_cards.erase(card_id)
	else:
		owned_cards[card_id] = current - count
	touch()
	return true


func total_card_count() -> int:
	var total: int = 0
	for card_count_value: int in owned_cards.values():
		total += card_count_value
	return total


# ----- 牌组 -----

func find_deck(deck_id: String) -> DeckData:
	for deck: DeckData in decks:
		if deck.deck_id == deck_id:
			return deck
	return null


func create_deck(deck_name: String) -> DeckData:
	var deck := DeckData.new()
	deck.deck_id = "deck_%d" % int(Time.get_unix_time_from_system())
	deck.deck_name = deck_name
	deck.updated_at_unix = int(Time.get_unix_time_from_system())
	decks.append(deck)
	if active_deck_id.is_empty():
		active_deck_id = deck.deck_id
	touch()
	return deck


func remove_deck(deck_id: String) -> bool:
	for index: int in range(decks.size()):
		if decks[index].deck_id == deck_id:
			decks.remove_at(index)
			if active_deck_id == deck_id:
				active_deck_id = ""
			touch()
			return true
	return false


func get_active_deck() -> DeckData:
	if active_deck_id.is_empty():
		return null
	return find_deck(active_deck_id)


# ----- 序列化 -----

func to_dict() -> Dictionary:
	var deck_dicts: Array = []
	for deck: DeckData in decks:
		deck_dicts.append(deck.to_dict())
	return {
		"schema_version": schema_version,
		"profile_id": profile_id,
		"player_name": player_name,
		"created_at_unix": created_at_unix,
		"last_played_unix": last_played_unix,
		"play_time_seconds": play_time_seconds,
		"is_developer_save": is_developer_save,
		"gold": gold,
		"diamond": diamond,
		"owned_cards": owned_cards.duplicate(),
		"decks": deck_dicts,
		"active_deck_id": active_deck_id,
		"campaign_progress": campaign_progress.duplicate(),
		"stats": stats.duplicate(),
	}


static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.schema_version = int(data.get("schema_version", SCHEMA_VERSION))
	profile.profile_id = str(data.get("profile_id", ""))
	profile.player_name = str(data.get("player_name", "玩家"))
	profile.created_at_unix = int(data.get("created_at_unix", 0))
	profile.last_played_unix = int(data.get("last_played_unix", 0))
	profile.play_time_seconds = int(data.get("play_time_seconds", 0))
	profile.is_developer_save = bool(data.get("is_developer_save", false))
	profile.gold = int(data.get("gold", 0))
	# 旧版存档（schema v1）用 arcane_dust 表示特殊货币，迁移为 diamond
	var diamond_value: int = int(data.get("diamond", -1))
	if diamond_value < 0:
		diamond_value = int(data.get("arcane_dust", 0))
	profile.diamond = diamond_value
	profile.active_deck_id = str(data.get("active_deck_id", ""))
	var raw_owned: Variant = data.get("owned_cards", {})
	if raw_owned is Dictionary:
		for raw_card_id: Variant in raw_owned.keys():
			profile.owned_cards[str(raw_card_id)] = int(raw_owned[raw_card_id])
	var raw_decks: Variant = data.get("decks", [])
	if raw_decks is Array:
		for raw_deck: Variant in raw_decks:
			if raw_deck is Dictionary:
				profile.decks.append(DeckData.from_dict(raw_deck))
	var raw_campaign: Variant = data.get("campaign_progress", {})
	if raw_campaign is Dictionary:
		for raw_level_id: Variant in raw_campaign.keys():
			profile.campaign_progress[str(raw_level_id)] = bool(raw_campaign[raw_level_id])
	var raw_stats: Variant = data.get("stats", {})
	if raw_stats is Dictionary:
		for raw_stat_key: Variant in raw_stats.keys():
			profile.stats[str(raw_stat_key)] = int(raw_stats[raw_stat_key])
	return profile

class_name GameModeConfig
extends RefCounted
## 玩法配置（JSON）。不同对战可使用不同玩法；默认玩法文件作为单机/服务器底层配置。
##
## JSON 字段（全部可省略，省略用默认值）：
##   deck_max_size, enforce_full_deck, max_copies_by_rarity,
##   player_hero_max_health, enemy_hero_max_health,
##   player_initial_energy, enemy_initial_energy,
##   player_initial_draw, enemy_initial_draw

const DEFAULT_DECK_MAX_SIZE: int = 40
const DEFAULT_ENFORCE_FULL_DECK: bool = true
const DEFAULT_MAX_COPIES: Array = [4, 4, 4, 4, 1, 4, 4, 4]
const DEFAULT_HERO_MAX_HEALTH: int = 20
const DEFAULT_INITIAL_ENERGY: int = 1
const DEFAULT_INITIAL_DRAW: int = 4
const DEFAULT_HAND_LIMIT: int = 10
const DEFAULT_ENERGY_CAP: int = 99
const DEFAULT_PHASE_TIME_SECONDS: int = 40
const DEFAULT_TEAM_UP_SWAP_COOLDOWN_SECONDS: float = 0.35
const DEFAULT_TURN_DRAW: int = 1

var deck_max_size: int = DEFAULT_DECK_MAX_SIZE
var enforce_full_deck: bool = DEFAULT_ENFORCE_FULL_DECK
## 按全局配置的稀有度顺序，每种稀有度单卡可编入张数；超出数组长度的稀有度默认 1。
var max_copies_by_rarity: Array[int] = [4, 4, 4, 4, 1, 4, 4, 4]

var player_hero_max_health: int = DEFAULT_HERO_MAX_HEALTH
var enemy_hero_max_health: int = DEFAULT_HERO_MAX_HEALTH
var player_initial_energy: int = DEFAULT_INITIAL_ENERGY
var enemy_initial_energy: int = DEFAULT_INITIAL_ENERGY
var player_initial_draw: int = DEFAULT_INITIAL_DRAW
var enemy_initial_draw: int = DEFAULT_INITIAL_DRAW
## 双方手牌上限；超出时取消抽牌
var hand_limit: int = DEFAULT_HAND_LIMIT
## 费用上限（双方相同）
var energy_cap: int = DEFAULT_ENERGY_CAP
## 单个回合阶段的时间上限（秒）；到点强制结束
var phase_time_limit_seconds: int = DEFAULT_PHASE_TIME_SECONDS
## 从第二回合起，每回合开始时我方/敌方各抽几张（第一回合不触发）
var player_draw_per_turn: int = DEFAULT_TURN_DRAW
var enemy_draw_per_turn: int = DEFAULT_TURN_DRAW
## 组队实体点击换位冷却（秒）；0 表示不限制
var team_up_swap_cooldown_seconds: float = DEFAULT_TEAM_UP_SWAP_COOLDOWN_SECONDS

## 来源文件路径（调试/服务器配置用）
var source_path: String = ""
var load_errors: Array[String] = []


static func default_config() -> GameModeConfig:
	return GameModeConfig.new()


static func from_dict(data: Dictionary) -> GameModeConfig:
	var config := GameModeConfig.new()
	config.deck_max_size = maxi(_int_value(data, "deck_max_size", DEFAULT_DECK_MAX_SIZE), 1)
	config.enforce_full_deck = bool(data.get("enforce_full_deck", DEFAULT_ENFORCE_FULL_DECK))
	config.max_copies_by_rarity = _int_array(data.get("max_copies_by_rarity", DEFAULT_MAX_COPIES))
	config.player_hero_max_health = maxi(_int_value(data, "player_hero_max_health", DEFAULT_HERO_MAX_HEALTH), 1)
	config.enemy_hero_max_health = maxi(_int_value(data, "enemy_hero_max_health", DEFAULT_HERO_MAX_HEALTH), 1)
	config.player_initial_energy = maxi(_int_value(data, "player_initial_energy", DEFAULT_INITIAL_ENERGY), 0)
	config.enemy_initial_energy = maxi(_int_value(data, "enemy_initial_energy", DEFAULT_INITIAL_ENERGY), 0)
	config.player_initial_draw = maxi(_int_value(data, "player_initial_draw", DEFAULT_INITIAL_DRAW), 0)
	config.enemy_initial_draw = maxi(_int_value(data, "enemy_initial_draw", DEFAULT_INITIAL_DRAW), 0)
	config.hand_limit = maxi(_int_value(data, "hand_limit", DEFAULT_HAND_LIMIT), 1)
	config.energy_cap = maxi(_int_value(data, "energy_cap", DEFAULT_ENERGY_CAP), 1)
	config.phase_time_limit_seconds = maxi(
		_int_value(data, "phase_time_limit_seconds", DEFAULT_PHASE_TIME_SECONDS), 1
	)
	config.player_draw_per_turn = maxi(_int_value(data, "player_draw_per_turn", DEFAULT_TURN_DRAW), 0)
	config.enemy_draw_per_turn = maxi(_int_value(data, "enemy_draw_per_turn", DEFAULT_TURN_DRAW), 0)
	config.team_up_swap_cooldown_seconds = maxf(
		_float_value(data, "team_up_swap_cooldown_seconds", DEFAULT_TEAM_UP_SWAP_COOLDOWN_SECONDS),
		0.0
	)
	return config


static func from_file(path: String) -> GameModeConfig:
	var config := default_config()
	config.source_path = path
	if not FileAccess.file_exists(path):
		config.load_errors.append("玩法文件不存在，使用默认值：%s" % path)
		return config
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		config.load_errors.append("玩法文件解析失败，使用默认值：%s" % path)
		return config
	var loaded: GameModeConfig = GameModeConfig.from_dict(parsed)
	loaded.source_path = path
	return loaded


## 指定稀有度序号（对应全局配置 rarities 顺序）的单卡上限。
func max_copies_for_rarity_index(index: int) -> int:
	if index < 0:
		return 1
	if index >= max_copies_by_rarity.size():
		return 1
	return maxi(max_copies_by_rarity[index], 1)


# ----- 阵营（p = 我方数据，z = 敌方数据） -----

func hero_max_health_for_faction(faction: String) -> int:
	return player_hero_max_health if faction == "p" else enemy_hero_max_health


func initial_energy_for_faction(faction: String) -> int:
	return player_initial_energy if faction == "p" else enemy_initial_energy


func initial_draw_for_faction(faction: String) -> int:
	return player_initial_draw if faction == "p" else enemy_initial_draw


## 第二回合起每回合开始时的抽牌数（0 = 不抽）。
func turn_draw_for_faction(faction: String) -> int:
	return player_draw_per_turn if faction == "p" else enemy_draw_per_turn


func to_dict() -> Dictionary:
	return {
		"deck_max_size": deck_max_size,
		"enforce_full_deck": enforce_full_deck,
		"max_copies_by_rarity": max_copies_by_rarity.duplicate(),
		"player_hero_max_health": player_hero_max_health,
		"enemy_hero_max_health": enemy_hero_max_health,
		"player_initial_energy": player_initial_energy,
		"enemy_initial_energy": enemy_initial_energy,
		"player_initial_draw": player_initial_draw,
		"enemy_initial_draw": enemy_initial_draw,
		"hand_limit": hand_limit,
		"energy_cap": energy_cap,
		"phase_time_limit_seconds": phase_time_limit_seconds,
		"player_draw_per_turn": player_draw_per_turn,
		"enemy_draw_per_turn": enemy_draw_per_turn,
		"team_up_swap_cooldown_seconds": team_up_swap_cooldown_seconds,
	}


static func _float_value(data: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = data.get(key, fallback)
	if raw is int or raw is float:
		return float(raw)
	if raw is String and (raw.is_valid_int() or raw.is_valid_float()):
		return float(raw)
	return fallback


static func _int_value(data: Dictionary, key: String, fallback: int) -> int:
	var raw: Variant = data.get(key, fallback)
	if raw is int:
		return int(raw)
	if raw is float:
		return int(raw)
	if raw is String and raw.is_valid_int():
		return int(raw)
	return fallback


static func _int_array(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if not raw is Array or raw.is_empty():
		for value: Variant in DEFAULT_MAX_COPIES:
			result.append(int(value))
		return result
	for value: Variant in raw:
		if value is int or value is float:
			result.append(maxi(int(value), 1))
		elif value is String and value.is_valid_int():
			result.append(maxi(int(value), 1))
		else:
			result.append(1)
	return result

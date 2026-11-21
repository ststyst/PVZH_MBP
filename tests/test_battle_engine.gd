@tool
extends McpTestSuite
## 战斗核心测试。suite = "battle"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const HeroDatabaseScript := preload("res://scripts/core/hero_database.gd")
const HERO_FILE: String = "res://data/cards/official/heroes.csv"

var cards: Node = null
var heroes: Node = null


func suite_name() -> String:
	return "battle"


func setup() -> void:
	cards = CardDatabaseScript.new()
	cards.reload(false)
	heroes = HeroDatabaseScript.new()
	heroes.reload_from(HERO_FILE, cards)


func teardown() -> void:
	if is_instance_valid(cards):
		cards.free()
	cards = null
	if is_instance_valid(heroes):
		heroes.free()
	heroes = null


func _deck(card_id: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for _index: int in range(count):
		ids.append(card_id)
	return ids


func _new_engine(p_card: String = "pvzh:gnoll", z_card: String = "pvzh:hound") -> BattleEngine:
	var engine := BattleEngine.new(cards, 12345)
	engine.setup(
		"p",
		heroes.get_hero("green_knight"),
		_deck(p_card, 12),
		heroes.get_hero("doom_priest"),
		_deck(z_card, 12),
		GameModeConfig.default_config(),
	)
	return engine


func _started_engine(p_card: String = "pvzh:gnoll", z_card: String = "pvzh:hound") -> BattleEngine:
	var engine: BattleEngine = _new_engine(p_card, z_card)
	engine.confirm_mulligan("p")
	engine.confirm_mulligan("z")
	return engine


func test_initial_draw_and_mulligan() -> void:
	var engine: BattleEngine = _new_engine()
	assert_eq(engine.phase, BattleEngine.PHASE_MULLIGAN)
	assert_eq(int(engine.players["p"].hand.size()), 4)
	assert_eq(int(engine.players["z"].hand.size()), 4)
	var before: int = int(engine.players["p"].deck.size())
	assert_eq(before, 8)
	assert_true(engine.replace_mulligan_card("p", 0), "调度应可用")
	assert_eq(int(engine.players["p"].hand.size()), 4)
	assert_eq(int(engine.players["p"].deck.size()), 8)


func test_start_after_mulligan() -> void:
	var engine: BattleEngine = _started_engine()
	assert_eq(engine.phase, BattleEngine.PHASE_HAND)
	assert_eq(engine.active_side, "z")
	assert_eq(engine.turn, 1)
	assert_eq(int(engine.players["p"].energy), 1)
	assert_eq(int(engine.players["z"].energy), 1)


func test_energy_and_turn_progression() -> void:
	var engine: BattleEngine = _started_engine()
	engine.end_phase("z")
	assert_eq(engine.active_side, "p")
	engine.end_phase("p")
	assert_eq(engine.phase, BattleEngine.PHASE_SPELL)
	engine.end_phase("z")
	assert_eq(engine.turn, 2)
	assert_eq(engine.phase, BattleEngine.PHASE_HAND)
	assert_eq(engine.active_side, "z")
	assert_eq(int(engine.players["p"].energy), 2)
	assert_eq(int(engine.players["z"].energy), 2)


func test_energy_cap() -> void:
	var engine: BattleEngine = _started_engine()
	engine.mode.energy_cap = 3
	engine.turn = 6
	engine._grant_energy("p")
	assert_eq(int(engine.players["p"].energy), 3, "费用不能超过上限")


func test_hand_limit_cancels_draw() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	state.hand.clear()
	for _index: int in range(engine.mode.hand_limit):
		state.hand.append("pvzh:gnoll")
	assert_eq(engine.draw_cards("p", 1), 0, "手牌满时取消抽牌")
	assert_eq(state.hand.size(), engine.mode.hand_limit)


func test_place_entity() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	state.hand = ["pvzh:hound"]
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "z"
	var result: Dictionary = engine.play_card("z", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)), "应成功放置实体：%s" % [result.get("message", "")])
	assert_eq(engine.entities.size(), 1)
	assert_eq(state.hand.size(), 0)
	assert_eq(int(engine.entities[0].column), 0)
	assert_eq(int(engine.entities[0].slot), 0)


func test_team_up_swap() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = cards.get_card("pvzh:hound")
	var copy: CardData = team_card.duplicate()
	copy.card_id = "pvzh:test_team"
	copy.keywords.append("team_up")
	cards.cards[copy.card_id] = copy
	var normal: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, BattleEngine.SLOT_NORMAL)
	var team: BattleEntity = engine.summon_card("p", copy, 0, BattleEngine.SLOT_TEAM_UP)
	assert_true(engine.swap_team_up("p", team), "组队实体应能与同列另一实体交换")
	assert_eq(team.slot, BattleEngine.SLOT_NORMAL)
	assert_eq(normal.slot, BattleEngine.SLOT_TEAM_UP)


func test_spell_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	state.hand = ["pvzh:fireball"]
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "z"
	var result: Dictionary = engine.play_card("z", 0, {"handle": engine.hero_handle("p")})
	assert_true(bool(result.get("ok", false)), "火球术应能命中英雄：%s" % [result.get("message", "")])
	assert_eq(int(engine.players["p"].hero_health), 14)


func test_combat_and_death() -> void:
	var engine: BattleEngine = _started_engine()
	engine.summon_card("z", cards.get_card("pvzh:hound"), 0, BattleEngine.SLOT_NORMAL)
	engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(engine.entities.size(), 0, "同列 1 攻 / 1 血实体应互相击杀")
	assert_eq(engine.winner, "")


func test_hero_damage_when_column_empty() -> void:
	var engine: BattleEngine = _started_engine()
	engine.summon_card("z", cards.get_card("pvzh:hound"), 2, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["p"].hero_health), 19)


func test_win_when_hero_dies() -> void:
	var engine: BattleEngine = _started_engine()
	engine.players["p"].hero_health = 1
	engine.summon_card("z", cards.get_card("pvzh:hound"), 0, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(engine.winner, "z")


func test_environment_card() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	state.hand = ["pvzh:sunny_field"]
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	var result: Dictionary = engine.play_card("z", 0, {"column": 2})
	assert_true(bool(result.get("ok", false)), "环境牌应能打出：%s" % [result.get("message", "")])
	assert_eq(engine.environments[2], "sunny_field")
	assert_eq(engine.environment_labels[2], "阳光田野")


func test_easy_ai_plays_highest_cost() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	state.hand = ["pvzh:gnoll", "pvzh:yeti"]
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "z"
	assert_true(EasyBattleAI.take_action(engine, "z"))
	assert_false(state.hand.has("pvzh:yeti"), "应优先打出费用最高的雪原雪怪")
	assert_true(state.hand.has("pvzh:gnoll"))


func test_team_up_placement_rule() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = cards.get_card("pvzh:hound").duplicate()
	team_card.card_id = "pvzh:test_team_placement"
	team_card.keywords.append("team_up")
	cards.cards[team_card.card_id] = team_card
	var state: BattlePlayerState = engine.players["p"]
	state.hand = ["pvzh:gnoll", "pvzh:gnoll", team_card.card_id]
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var first: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(first.get("ok", false)), "第一张普通实体应可放入空列")
	var second_normal: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 1})
	assert_false(bool(second_normal.get("ok", true)), "两个普通实体不能同列")
	var second_team: Dictionary = engine.play_card("p", 1, {"column": 0, "slot": 1})
	assert_true(bool(second_team.get("ok", false)), "组队实体可与普通实体同列")

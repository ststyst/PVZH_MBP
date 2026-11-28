@tool
extends McpTestSuite
## 逐列战斗结算测试（combat_step_mode）。suite = "combat_step"。
##
## 目的：
## - 锁定「一次只结算一列」的推进语义（UI 靠它等每列动画播完再进入下一列）；
## - 锁定「逐列结算」与「一次性结算」的规则结果完全一致（防止两条路径跑偏）。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const HeroDatabaseScript := preload("res://scripts/core/hero_database.gd")
const HERO_FILE: String = "res://data/cards/official/heroes.csv"

var cards: Node = null
var heroes: Node = null


func suite_name() -> String:
	return "combat_step"


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


func _make_test_card(card_id: String, attack: int, health: int) -> CardData:
	var template: CardData = cards.get_card("pvzh:gnoll")
	var card := CardData.new()
	card.card_id = card_id
	card.card_namespace = "pvzh"
	card.english_name = template.english_name
	card.chinese_name = template.chinese_name
	card.description = template.description
	card.kind = "entity"
	card.cost = 1
	card.attack = attack
	card.health = health
	card.shield = 0
	card.card_class = template.card_class
	card.rarity = template.rarity
	card.keywords = []
	card.keyword_values = {}
	card.tribes = []
	card.ability = ""
	card.ability_script = CardEffectScript.parse("")
	cards.cards[card_id] = card
	return card


func _new_engine() -> BattleEngine:
	var engine := BattleEngine.new(cards, 12345)
	engine.setup(
		"p",
		heroes.get_hero("green_knight"),
		_deck("pvzh:gnoll", 12),
		heroes.get_hero("doom_priest"),
		_deck("pvzh:hound", 12),
		GameModeConfig.default_config(),
	)
	engine.confirm_mulligan("p")
	engine.confirm_mulligan("z")
	return engine


## 在两列各放一组互殴的实体，然后进入对战阶段（逐列或一次性）。
func _engine_at_combat(step_mode: bool) -> BattleEngine:
	var engine: BattleEngine = _new_engine()
	engine.combat_step_mode = step_mode
	var p_card: CardData = _make_test_card("pvzh:test_step_p", 2, 6)
	var z_card: CardData = _make_test_card("pvzh:test_step_z", 2, 6)
	engine.summon_card("p", p_card, 0, BattleEngine.SLOT_NORMAL)
	engine.summon_card("z", z_card, 0, BattleEngine.SLOT_NORMAL)
	engine.summon_card("p", p_card, 1, BattleEngine.SLOT_NORMAL)
	engine.summon_card("z", z_card, 1, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	return engine


func test_step_mode_waits_for_external_columns() -> void:
	var engine: BattleEngine = _engine_at_combat(true)
	assert_eq(engine.phase, BattleEngine.PHASE_COMBAT)
	assert_true(engine.has_pending_combat_columns(), "进入对战阶段后应等待逐列推进")
	assert_eq(engine.combat_columns_resolved, 0)
	# 逐列模式下没有任何列被自动结算：实体血量还是初始值。
	for entity: BattleEntity in engine.entities:
		assert_eq(entity.health, 6, "逐列模式不应自动结算")

	var first: int = engine.resolve_next_combat_column()
	assert_eq(first, 0, "第一次推进只结算第 1 列")
	assert_eq(engine.combat_columns_resolved, 1)
	assert_true(engine.has_pending_combat_columns())

	var resolved: Array[int] = [first]
	while engine.has_pending_combat_columns():
		resolved.append(engine.resolve_next_combat_column())
	assert_eq(resolved, [0, 1, 2, 3, 4], "应按 1..5 列顺序推进")
	assert_eq(engine.combat_columns_resolved, 5)
	assert_eq(engine.resolve_next_combat_column(), -1, "列结算完后应返回 -1")
	# 全部列结算完但还没收尾：阶段仍停在 combat。
	assert_eq(engine.phase, BattleEngine.PHASE_COMBAT)
	engine.finish_combat_resolution()
	assert_eq(engine.phase, BattleEngine.PHASE_HAND, "收尾后应进入下一回合的出牌阶段")
	assert_eq(engine.turn, 2)
	assert_false(engine.has_pending_combat_columns())


func test_step_and_bulk_resolution_produce_same_state() -> void:
	var stepped: BattleEngine = _engine_at_combat(true)
	while stepped.has_pending_combat_columns():
		stepped.resolve_next_combat_column()
	stepped.finish_combat_resolution()

	var bulk: BattleEngine = _engine_at_combat(false)

	assert_eq(stepped.phase, bulk.phase)
	assert_eq(stepped.turn, bulk.turn)
	assert_eq(stepped.players["p"].hero_health, bulk.players["p"].hero_health)
	assert_eq(stepped.players["z"].hero_health, bulk.players["z"].hero_health)
	assert_eq(stepped.entities.size(), bulk.entities.size())
	for index: int in range(stepped.entities.size()):
		var a: BattleEntity = stepped.entities[index]
		var b: BattleEntity = bulk.entities[index]
		assert_eq(a.entity_id, b.entity_id)
		assert_eq(a.attack, b.attack, "逐列与一次性结算的攻击力应一致")
		assert_eq(a.health, b.health, "逐列与一次性结算的生命应一致")
		assert_eq(a.alive, b.alive)


func test_step_mode_stops_when_winner_decided() -> void:
	var engine: BattleEngine = _new_engine()
	engine.combat_step_mode = true
	var killer: CardData = _make_test_card("pvzh:test_step_killer", 30, 10)
	engine.summon_card("p", killer, 0, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()

	assert_eq(engine.phase, BattleEngine.PHASE_COMBAT)
	assert_true(engine.has_pending_combat_columns())
	# 第 1 列直接把敌方英雄打死：后续列不再结算。
	assert_eq(engine.resolve_next_combat_column(), 0)
	assert_eq(engine.winner, "p")
	assert_false(engine.has_pending_combat_columns(), "已分胜负后不应继续结算剩余列")
	assert_eq(engine.resolve_next_combat_column(), -1)
	engine.finish_combat_resolution()
	assert_false(engine.has_pending_combat_columns())

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


func _set_hand(engine: BattleEngine, side: String, ids: Array) -> void:
	var state: BattlePlayerState = engine.players[side]
	state.hand.clear()
	for card_id: Variant in ids:
		engine.add_card_to_hand(side, str(card_id))


func _set_deck(engine: BattleEngine, side: String, ids: Array) -> void:
	var state: BattlePlayerState = engine.players[side]
	state.deck.clear()
	for card_id: Variant in ids:
		engine.add_card_to_deck(side, str(card_id))


func _hand_has(state: BattlePlayerState, card_id: String) -> bool:
	return state.hand_ids().has(card_id)


func _make_test_card(card_id: String, ability: String) -> CardData:
	var template: CardData = cards.get_card("pvzh:gnoll")
	var card := CardData.new()
	card.card_id = card_id
	card.card_namespace = "pvzh"
	card.english_name = template.english_name
	card.chinese_name = template.chinese_name
	card.description = template.description
	card.kind = template.kind
	card.cost = template.cost
	card.attack = template.attack
	card.health = template.health
	card.shield = template.shield
	card.card_class = template.card_class
	card.rarity = template.rarity
	card.keywords = template.keywords.duplicate()
	card.keyword_values = template.keyword_values.duplicate(true)
	card.tribes = template.tribes.duplicate()
	card.ability = ability
	card.ability_script = CardEffectScript.parse(ability)
	cards.cards[card_id] = card
	return card


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
	assert_eq(int(engine.players["p"].hand.size()), 4, "起手调度阶段只有四张起手牌")
	assert_eq(int(engine.players["z"].hand.size()), 4, "起手调度阶段只有四张起手牌")
	var before: int = int(engine.players["p"].deck.size())
	assert_eq(before, 8)
	var seen_ids: Dictionary = {}
	for instance: BattleCardInstance in engine.players["p"].hand:
		seen_ids[instance.instance_id] = true
	for instance: BattleCardInstance in engine.players["p"].deck:
		seen_ids[instance.instance_id] = true
	assert_eq(seen_ids.size(), 12, "起手阶段每张卡实例应有唯一 instance_id")
	assert_true(engine.replace_mulligan_card("p", 0), "调度应可用")
	assert_eq(int(engine.players["p"].hand.size()), 4, "起手调度阶段只有四张起手牌")
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
		engine.add_card_to_hand("p", "pvzh:gnoll")
	assert_eq(engine.draw_cards("p", 1), 0, "手牌满时取消抽牌")
	assert_eq(state.hand.size(), engine.mode.hand_limit)


func test_place_entity() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	_set_hand(engine, "z", ["pvzh:hound"])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "z"
	var result: Dictionary = engine.play_card("z", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)), "应成功放置实体：%s" % [result.get("message", "")])
	assert_eq(engine.entities.size(), 1)
	assert_eq(state.hand.size(), 0)
	assert_eq(int(engine.entities[0].column), 0)
	assert_eq(int(engine.entities[0].slot), 0)


func test_first_strike_damages_hero_then_normal_attack() -> void:
	var engine: BattleEngine = _started_engine()
	var striker_card: CardData = _make_test_card("pvzh:test_first_strike", "")
	striker_card.health = 5
	striker_card.keywords.append("first_strike")
	striker_card.keyword_values["first_strike"] = 2
	var striker: BattleEntity = engine.summon_card("p", striker_card, 0, 0)
	var target: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["z"].hero_health), 18, "先攻 2 应先打敌方英雄 2 点")
	assert_true(not target.alive, "正常攻击仍应命中并击杀实体")
	assert_eq(striker.attack, 1)


func test_spell_multi_target_handles() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_multi_spell",
		"choose(2, \"all_enemies\")\ndeal_damage(chosen, 1)"
	)
	spell.kind = "spell"
	spell.cost = 1
	var first: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	var second: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 1, 0)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var requirement: Dictionary = spell.ability_script.target_requirement()
	assert_eq(int(requirement.get("count", 0)), 2)
	assert_eq(str(requirement.get("selector", "")), "all_enemies")
	var result: Dictionary = engine.play_card("p", 0, {"handles": [first, second]})
	assert_true(bool(result.get("ok", false)), "多目标锦囊应接受 handles：%s" % [result.get("message", "")])
	assert_false(first.alive)
	assert_false(second.alive)


func test_effect_chain_resolves_before_play_ends() -> void:
	var engine: BattleEngine = _started_engine()
	var reactor_card: CardData = _make_test_card(
		"pvzh:test_attack_reactor",
		"when attack_changed(side != 'enemy'):\n    heal(self, 1)"
	)
	reactor_card.health = 5
	var reactor: BattleEntity = engine.summon_card("p", reactor_card, 0, 0)
	reactor.health = 3
	var hand_card: CardData = _make_test_card(
		"pvzh:test_health_hand",
		"when health_changed(side == 'ally'):\n    reduce_cost(1)"
	)
	hand_card.cost = 5
	var spell: CardData = _make_test_card(
		"pvzh:test_buff_spell",
		"buff_stats(all_allies, 1, 0)"
	)
	spell.kind = "spell"
	spell.cost = 1
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [hand_card.card_id, spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 1, {})
	assert_true(bool(result.get("ok", false)))
	assert_eq(reactor.attack, reactor_card.attack + 1)
	assert_eq(reactor.health, 4, "攻击力变化应继续触发治疗")
	assert_eq(state.hand[0].cost_delta, -1, "生命变化应触发手牌减费")
	assert_eq(engine.effective_hand_cost("p", 0), 4)


func test_effect_chain_guard_stops_infinite_loop() -> void:
	var engine: BattleEngine = _started_engine()
	engine.effect_resolution_limit = 20
	var loop_card: CardData = _make_test_card(
		"pvzh:test_attack_loop",
		"when attack_changed(side != 'enemy'):\n    buff_stats(self, 1, 0)"
	)
	engine.summon_card("p", loop_card, 0, 0)
	engine.summon_card("p", loop_card, 1, 0)
	var spell: CardData = _make_test_card(
		"pvzh:test_loop_spell",
		"buff_stats(all_allies, 1, 0)"
	)
	spell.kind = "spell"
	spell.cost = 1
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(result.get("ok", false)))
	assert_true(
		str(engine.log_entries).find("连锁上限") != -1,
		"无限连锁应被上限强制截断",
	)


func test_charge_shield_immunity_and_special_offer() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.charge_shield = 7
	p_state.charge_shield_durability = 1
	engine.damage_hero("p", 2, [])
	assert_eq(int(p_state.hero_health), 20, "充能到 8 时应免疫本次伤害")
	assert_eq(int(p_state.charge_shield), 0, "免疫后充能归零")
	assert_eq(int(p_state.charge_shield_durability), 0, "免疫后耐久 -1")
	assert_true(p_state.special_offer_id != 0, "应获得一张超能力牌")
	assert_true(engine._special_pending_sides.has("p"))
	assert_true(engine._maybe_begin_special_turn(BattleEngine.PHASE_HAND))
	assert_eq(engine.phase, BattleEngine.PHASE_SPECIAL)
	var hand_count_before: int = p_state.hand.size()
	var result: Dictionary = engine.special_resolve_hand("p")
	assert_true(bool(result.get("ok", false)))
	assert_eq(engine.phase, BattleEngine.PHASE_HAND)
	assert_eq(p_state.special_offer_id, 0)
	assert_eq(p_state.hand.size(), hand_count_before, "移入手牌后牌仍在手中")


func test_charge_shield_emergency_lethal_protection() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 5
	p_state.charge_shield = 5
	p_state.charge_shield_durability = 3
	p_state.charge_shield_emergency_uses = 1
	engine.damage_hero("p", 10, [])
	assert_eq(p_state.hero_health, 5, "致命伤害应被充能护盾免疫")
	assert_eq(p_state.charge_shield, 0, "免疫后充能归零")
	assert_eq(p_state.charge_shield_durability, 2)
	assert_eq(p_state.charge_shield_emergency_uses, 0, "整局限一次的生命保护应被消耗")


func test_charge_shield_rules_and_bullseye() -> void:
	var engine: BattleEngine = _started_engine()
	var z_state: BattlePlayerState = engine.players["z"]
	engine.damage_hero("z", 4, [])
	assert_eq(z_state.charge_shield, 2, "4~6 伤害应充能 2")
	var before: int = z_state.charge_shield
	engine.damage_hero("z", 3, ["bullseye"])
	assert_eq(z_state.charge_shield, before, "必中伤害不应增加充能")
	assert_eq(z_state.hero_health, 13, "必中伤害仍应正常扣血")


func test_initial_superpower_waits_for_mulligan() -> void:
	var engine: BattleEngine = _new_engine()
	var state: BattlePlayerState = engine.players["p"]
	var pool_before: int = state.superpower_pool.size()
	assert_eq(state.hand.size(), 4)
	assert_false(state.superpower_pool.is_empty())
	engine.confirm_mulligan("p")
	engine.confirm_mulligan("z")
	assert_eq(state.hand.size(), 5, "调度完成后才追加超能力")
	assert_eq(state.superpower_pool.size(), pool_before - 1)


func test_initial_superpower_is_in_hand() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	var hero: HeroData = heroes.get_hero("green_knight")
	var found: bool = false
	for instance: BattleCardInstance in p_state.hand:
		if hero.special_card_ids.has(instance.card_id):
			found = true
			break
	assert_true(found, "初始手牌应包含一张英雄超能力")
	assert_true(p_state.superpower_pool.size() < hero.special_card_ids.size())


func test_hero_shield_cleared_at_turn_end() -> void:
	var engine: BattleEngine = _started_engine()
	engine.players["p"].hero_shield = 3
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["p"].hero_shield), 0, "回合结束应清空英雄护盾")


func test_first_strike_uses_hero_shield_and_damage_event() -> void:
	var engine: BattleEngine = _started_engine()
	var striker_card: CardData = _make_test_card("pvzh:test_first_shield", "")
	striker_card.health = 5
	striker_card.keywords.append("first_strike")
	striker_card.keyword_values["first_strike"] = 2
	engine.summon_card("p", striker_card, 0, 0)
	engine.summon_card("z", cards.get_card("pvzh:hound"), 0, 0)
	engine.players["z"].hero_shield = 1
	var damage_events: Array = []
	engine.hero_damaged.connect(func(side: String, amount: int, _keywords: Array) -> void:
		damage_events.append({"side": side, "amount": amount})
	)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["z"].hero_shield), 0, "先攻伤害应先扣英雄护盾")
	assert_eq(int(engine.players["z"].hero_health), 19, "先攻 2 被护盾挡 1 后应造成 1 点")
	assert_eq(damage_events.size(), 1)
	assert_eq(str(damage_events[0].get("side", "")), "z")
	assert_eq(int(damage_events[0].get("amount", 0)), 1, "事件应报告实际伤害")


func test_first_strike_respects_hero_damage_immunity() -> void:
	var engine: BattleEngine = _started_engine()
	var striker_card: CardData = _make_test_card("pvzh:test_first_immune", "")
	striker_card.health = 5
	striker_card.keywords.append("first_strike")
	striker_card.keyword_values["first_strike"] = 2
	engine.summon_card("p", striker_card, 0, 0)
	engine.summon_card("z", cards.get_card("pvzh:hound"), 0, 0)
	engine.players["z"].hero_shield = 3
	engine.players["z"].hero_damage_immune = true
	var damage_events: Array = []
	engine.hero_damaged.connect(func(_side: String, _amount: int, _keywords: Array) -> void:
		damage_events.append(true)
	)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["z"].hero_health), 20, "免疫时先攻不应造成英雄伤害")
	assert_eq(int(engine.players["z"].hero_shield), 0, "回合结束时英雄护盾应被清空")
	assert_true(damage_events.is_empty(), "完全免疫时不应发伤害事件")


func test_normal_attack_hero_damage_uses_shield() -> void:
	var engine: BattleEngine = _started_engine()
	engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	engine.players["p"].hero_shield = 1
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_eq(int(engine.players["p"].hero_shield), 0, "普通英雄伤害也应先扣护盾")
	assert_eq(int(engine.players["p"].hero_health), 20)


func test_keyword_values_stack_and_respect_whitelist() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card("pvzh:test_keyword_entity", "")
	var entity: BattleEntity = engine.summon_card("p", entity_card, 0, 0)
	assert_true(entity.add_keyword("first_strike", 2))
	assert_true(entity.add_keyword("first_strike", 3))
	assert_eq(entity.keyword_value("first_strike"), 5, "同词缀数值应相加")
	assert_eq(entity.keyword_value("taunt"), 0, "不同词缀数值不互通")

	var spell_card: CardData = _make_test_card("pvzh:test_keyword_spell", "")
	spell_card.kind = "spell"
	cards.cards[spell_card.card_id] = spell_card
	_set_hand(engine, "p", [spell_card.card_id, entity_card.card_id])
	assert_false(
		engine.give_keyword_to_hand_card("p", 0, "first_strike", 2),
		"锦囊牌不能获得先攻",
	)
	assert_true(engine.give_keyword_to_hand_card("p", 1, "first_strike", 2))
	assert_eq(int(engine.players["p"].hand[1].keyword_values.get("first_strike", 0)), 2)
	assert_false(engine.players["p"].hand[0].keyword_values.has("first_strike"))
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	engine.players["p"].energy = 10
	var played: Dictionary = engine.play_card("p", 1, {"column": 1, "slot": 0})
	assert_true(bool(played.get("ok", false)), "带手牌词缀的实体应能打出")
	var played_entity: BattleEntity = engine._entity_at(1, "p", 0)
	assert_true(played_entity != null)
	if played_entity != null:
		assert_eq(played_entity.keyword_value("first_strike"), 2, "手牌词缀应转为实体词缀")


func test_team_up_placement_displaces_existing() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = _make_test_card("pvzh:test_team", "")
	team_card.keywords.append("team_up")
	var floor_card: CardData = _make_test_card(
		"pvzh:test_moved",
		"when position_changed:\n    add_marker(\"moved\", 1)"
	)
	var occupant: BattleEntity = engine.summon_card("p", floor_card, 0, BattleEngine.SLOT_NORMAL)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [team_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {
		"column": 0, "slot": BattleEngine.SLOT_NORMAL,
	})
	assert_true(bool(result.get("ok", false)), "组队实体应能占用已有友方实体的格子")
	assert_eq(occupant.slot, BattleEngine.SLOT_TEAM_UP, "原实体应被移到另一格")
	assert_eq(engine.entities.size(), 2)
	assert_eq(engine._entity_at(0, "p", BattleEngine.SLOT_NORMAL).card.card_id, team_card.card_id)
	assert_eq(state.marker_count("moved"), 0, "放置导致的位置变化不应触发 position_changed")

	_set_hand(engine, "p", [team_card.card_id])
	state.energy = 10
	var full_result: Dictionary = engine.play_card("p", 0, {
		"column": 0, "slot": BattleEngine.SLOT_TEAM_UP,
	})
	assert_false(bool(full_result.get("ok", true)), "满员列不允许再放置组队实体")


func test_move_entity_triggers_position_event() -> void:
	var engine: BattleEngine = _started_engine()
	var mover_card: CardData = _make_test_card(
		"pvzh:test_position_mover",
		"when position_changed:\n    add_marker(\"moved\", 1)"
	)
	var entity: BattleEntity = engine.summon_card("p", mover_card, 0, BattleEngine.SLOT_NORMAL)
	assert_true(engine.move_entity(entity, 2, BattleEngine.SLOT_TEAM_UP))
	assert_eq(entity.column, 2)
	assert_eq(entity.slot, BattleEngine.SLOT_TEAM_UP)
	assert_eq(engine.players["p"].marker_count("moved"), 1, "效果移动应触发 position_changed")


func test_spell_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["z"]
	_set_hand(engine, "z", ["pvzh:fireball"])
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
	_set_hand(engine, "z", ["pvzh:sunny_field"])
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
	_set_hand(engine, "z", ["pvzh:gnoll", "pvzh:yeti"])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "z"
	assert_true(EasyBattleAI.take_action(engine, "z"))
	assert_false(_hand_has(state, "pvzh:yeti"), "应优先打出费用最高的雪原雪怪")
	assert_true(_hand_has(state, "pvzh:gnoll"))


func test_turn_draw_except_first_turn() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	var z_state: BattlePlayerState = engine.players["z"]
	assert_eq(p_state.hand.size(), 5, "第一回合不应额外抽牌（含初始超能力）")
	assert_eq(z_state.hand.size(), 5)
	engine.end_phase("z")
	engine.end_phase("p")
	engine.end_phase("z")
	assert_eq(engine.turn, 2)
	assert_eq(p_state.hand.size(), 6, "第二回合开始双方各抽 1 张")
	assert_eq(z_state.hand.size(), 6)
	assert_eq(p_state.deck.size(), 7)
	assert_eq(z_state.deck.size(), 7)


func test_turn_draw_configurable() -> void:
	var engine: BattleEngine = _started_engine()
	engine.mode.player_draw_per_turn = 2
	engine.mode.enemy_draw_per_turn = 0
	engine.end_phase("z")
	engine.end_phase("p")
	engine.end_phase("z")
	assert_eq(engine.players["p"].hand.size(), 7, "我方每回合抽 2")
	assert_eq(engine.players["z"].hand.size(), 5, "敌方每回合抽 0")


func test_any_empty_slot_allowed() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", ["pvzh:gnoll", "pvzh:gnoll"])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var slots: Array[Dictionary] = engine.valid_slots("p", engine.hand_card("p", 0))
	var column_zero_slots: int = 0
	for slot_info: Dictionary in slots:
		if int(slot_info.get("column", -1)) == 0:
			column_zero_slots += 1
	assert_eq(column_zero_slots, 2, "空列的两个位置都应允许打出实体")
	var result: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": BattleEngine.SLOT_TEAM_UP})
	assert_true(bool(result.get("ok", false)), "普通实体也应能打出到空列的外侧位置")
	assert_eq(engine.entities.size(), 1)
	if not engine.entities.is_empty():
		assert_eq(engine.entities[0].slot, BattleEngine.SLOT_TEAM_UP)


func test_animation_cues_on_attack_and_death() -> void:
	var card: CardData = cards.get_card("pvzh:gnoll").duplicate()
	card.card_id = "pvzh:anim_test_unit"
	card.animation_script = CardAnimationScript.parse(
		"when attack:\n    play_animation(self, \"slash\", \"whole\")\nwhen die:\n    play_animation(self, \"death\", \"art\")"
	)
	cards.cards[card.card_id] = card
	var engine: BattleEngine = _started_engine()
	var cues: Array[String] = []
	engine.animation_cue.connect(func(trigger: String, _actor: BattleEntity, _target: Variant) -> void:
		cues.append(trigger)
	)
	engine.summon_card("p", card, 0, BattleEngine.SLOT_NORMAL)
	engine.summon_card("z", cards.get_card("pvzh:hound"), 0, BattleEngine.SLOT_NORMAL)
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_true(cues.has("attack"), "攻击应触发动画 cue：%s" % [cues])
	assert_true(cues.has("die"), "死亡应触发动画 cue：%s" % [cues])


func test_surrender_sets_opponent_winner() -> void:
	var engine: BattleEngine = _started_engine()
	var finished: Array[String] = []
	engine.game_finished.connect(func(winner: String) -> void: finished.append(winner))
	engine.surrender("p")
	assert_eq(engine.winner, "z", "我方投降应判敌方获胜")
	assert_eq(engine.phase, BattleEngine.PHASE_GAME_OVER)
	assert_true(finished.has("z"))


func test_zone_deck_death_bonus_and_play_attack() -> void:
	var card: CardData = _make_test_card(
		"pvzh:test_deck_bonus",
		"when ally_die(zone == 'deck'):\n    gain_attack(1)"
	)
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [])
	_set_deck(engine, "p", [card.card_id])
	var deck_instance_id: int = state.deck[0].instance_id
	var ally: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, 0)
	engine.damage_handle(ally, 99)
	engine._flush_deaths()
	assert_eq(state.deck[0].attack_bonus, 1, "牌库中的卡应累计攻击加成")
	engine.draw_cards("p", 1)
	assert_eq(state.hand.size(), 1)
	assert_eq(state.hand[0].instance_id, deck_instance_id, "抽牌应保留同一实例")
	assert_eq(state.hand[0].attack_bonus, 1, "抽到后加成应保留")
	var display: CardData = engine.hand_card_display("p", 0)
	assert_true(display != null)
	if display != null:
		assert_eq(display.display_name(), card.display_name(), "手牌显示副本应保留卡名")
		assert_eq(display.attack, card.attack + 1)
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	state.energy = 10
	var result: Dictionary = engine.play_card("p", 0, {"column": 1, "slot": 0})
	assert_true(bool(result.get("ok", false)), "应可打出带有手牌加成的卡")
	var played: BattleEntity = null
	for entity: BattleEntity in engine.entities:
		if entity.card != null and entity.card.card_id == card.card_id:
			played = entity
	assert_true(played != null)
	if played != null:
		assert_eq(played.attack, card.attack + 1, "打出后攻击加成应转为实体属性")


func test_zone_hand_death_bonus_cost_and_play() -> void:
	var card: CardData = _make_test_card(
		"pvzh:test_hand_bonus",
		"when ally_die(zone == 'hand'):\n    gain_attack(1)\n    reduce_cost(1)"
	)
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [card.card_id])
	var ally: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, 0)
	engine.damage_handle(ally, 99)
	engine._flush_deaths()
	assert_eq(state.hand[0].attack_bonus, 1)
	assert_eq(state.hand[0].cost_delta, -1)
	assert_eq(engine.effective_hand_cost("p", 0), maxi(card.cost - 1, 0))
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	state.energy = 10
	var result: Dictionary = engine.play_card("p", 0, {"column": 1, "slot": 0})
	assert_true(bool(result.get("ok", false)), "应可打出减费后的卡")
	var played: BattleEntity = null
	for entity: BattleEntity in engine.entities:
		if entity.card != null and entity.card.card_id == card.card_id:
			played = entity
	assert_true(played != null)
	if played != null:
		assert_eq(played.attack, card.attack + 1)


func test_choose_two_other_allies_buffs_both() -> void:
	var card: CardData = _make_test_card(
		"pvzh:test_choose_allies",
		"when enter:\n    choose(2, \"other_allies\")\n    buff_stats(chosen, 2, 0)"
	)
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var first: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, 0)
	var second: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 1, 0)
	var first_attack: int = first.attack
	var second_attack: int = second.attack
	var requirement: Dictionary = card.ability_script.target_requirement()
	assert_eq(int(requirement.get("count", 0)), 2)
	assert_eq(str(requirement.get("selector", "")), "other_allies")
	var result: Dictionary = engine.play_card(
		"p", 0, {"column": 2, "slot": 0, "handles": [first, second]}
	)
	assert_true(bool(result.get("ok", false)), "选择两个其他友方实体应可打出")
	assert_eq(first.attack, first_attack + 2)
	assert_eq(second.attack, second_attack + 2)


func test_special_markers_are_string_names_with_int_values() -> void:
	var card: CardData = _make_test_card(
		"pvzh:test_markers",
		"when enter:\n    if marker_count(\"special_marker_1\") > 1:\n        add_marker(\"special_marker_2\", 3)\n        add_marker(\"special_marker_3\", -1)"
	)
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	state.markers["special_marker_1"] = 2
	_set_hand(engine, "p", [card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.marker_count("special_marker_2"), 3)
	assert_eq(state.marker_count("special_marker_3"), -1)


func test_team_up_placement_rule() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = cards.get_card("pvzh:hound").duplicate()
	team_card.card_id = "pvzh:test_team_placement"
	team_card.keywords.append("team_up")
	cards.cards[team_card.card_id] = team_card
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", ["pvzh:gnoll", "pvzh:gnoll", team_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var first: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(first.get("ok", false)), "第一张普通实体应可放入空列")
	var second_normal: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 1})
	assert_false(bool(second_normal.get("ok", true)), "两个普通实体不能同列")
	var second_team: Dictionary = engine.play_card("p", 1, {"column": 0, "slot": 1})
	assert_true(bool(second_team.get("ok", false)), "组队实体可与普通实体同列")

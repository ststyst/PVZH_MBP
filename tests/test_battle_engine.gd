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


func test_play_logs_both_sides_and_entity_ability_source() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_log_spell",
		"deal_damage(enemy_hero, 1)"
	)
	spell.kind = "spell"
	spell.cost = 1
	_set_hand(engine, "p", [spell.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(bool(engine.play_card("p", 0, {}).get("ok", false)))
	var has_play_log: bool = false
	var expected_play_log: String = "P 打出 %s" % spell.display_name()
	for entry: String in engine.log_entries:
		if entry == expected_play_log:
			has_play_log = true
	assert_true(has_play_log, "打出锦囊应写入战报")
	var source_card: CardData = _make_test_card(
		"pvzh:test_log_ability_source",
		"when enter:\n    deal_damage(all_enemies, 1)"
	)
	source_card.attack = 1
	source_card.health = 3
	var target_card: CardData = _make_test_card("pvzh:test_log_ability_target", "")
	target_card.health = 3
	engine.summon_card("z", target_card, 1, 0)
	engine.summon_card("p", source_card, 1, 0)
	engine._fire_event("enter", engine._entity_at(1, "p", 0))
	var has_source: bool = false
	for entry: String in engine.log_entries:
		if entry.contains("来源：") and entry.contains(source_card.display_name()):
			has_source = true
	assert_true(has_source, "实体能力伤害应记录来源实体")


func test_environment_temporary_keyword_grants_are_removed_on_replace() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card("pvzh:test_env_keyword_entity", "")
	entity_card.keywords = ["deadly"]
	entity_card.health = 4
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	assert_true(entity.has_keyword("deadly"))
	assert_eq(entity.keyword_value("deadly"), 1)
	var env_card: CardData = _make_test_card(
		"pvzh:test_env_keyword",
		"environment_grant_keyword('deadly', 2, 'ally')"
	)
	env_card.kind = "environment"
	env_card.english_name = "test_env_keyword"
	assert_true(engine._place_environment("p", 1, env_card))
	assert_eq(entity.keyword_value("deadly"), 3, "环境临时致命应与已有致命叠加，实际 %d，buffs=%s" % [entity.keyword_value("deadly"), str(entity.buffs)])
	var other_env: CardData = _make_test_card("pvzh:test_env_other", "")
	other_env.kind = "environment"
	other_env.english_name = "test_env_other"
	assert_true(engine._place_environment("p", 1, other_env))
	assert_eq(entity.keyword_value("deadly"), 1, "环境被覆盖后应只移除环境赋予的临时词缀，实际 %d buffs=%s" % [entity.keyword_value("deadly"), str(entity.buffs)])


func test_transform_entity_and_hand_use_card_filters() -> void:
	var engine: BattleEngine = _started_engine()
	var original_card: CardData = _make_test_card("pvzh:test_transform_original", "")
	original_card.cost = 1
	original_card.class_category = "test_transform_category"
	original_card.health = 3
	var original: BattleEntity = engine.summon_card("p", original_card, 1, 0)
	var target_card: CardData = _make_test_card("pvzh:test_transform_target", "")
	target_card.english_name = "test_transform_target"
	target_card.cost = 2
	target_card.class_category = "test_transform_category"
	target_card.health = 4
	assert_true(engine.transform_entity_handle(original, "cost == 2 and category == 'test_transform_category'"))
	var transformed: BattleEntity = engine._entity_at(1, "p", 0)
	assert_true(transformed != null)
	if transformed != null:
		assert_eq(transformed.card.english_name, "test_transform_target")
	var hand_instance: BattleCardInstance = BattleCardInstance.create(999, original_card.card_id, "p", "hand")
	engine.players["p"].hand.clear()
	engine.players["p"].add_to_hand(hand_instance)
	assert_eq(engine.transform_hand("p", "ally", "cost == 1", "cost == 2 and category == 'test_transform_category'"), 1)
	assert_eq(engine.players["p"].hand[0].card_id, target_card.card_id)


func test_config_class_categories_are_exclusive() -> void:
	var config: CardSetConfig = CardSetConfig.new()
	var problems: Array[String] = config.load_file("res://data/cards/official/config.csv")
	assert_true(problems.is_empty(), "官方配置应有完整职业类别：%s" % [problems])
	assert_eq(config.class_category_for("grow"), "growth")
	assert_eq(config.class_category_for("solar"), "light")
	assert_eq(config.class_category_for("crazy"), "chaos")
	var filter := CardFilter.new()
	assert_true(filter.parse("category == 'neutral'"))
	assert_true(filter.matches(cards.get_card("pvzh:gnoll")))


func test_life_force_uses_health_for_attack_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card("pvzh:test_life_force_attacker", "")
	attacker_card.attack = 1
	attacker_card.health = 6
	var target_card: CardData = _make_test_card("pvzh:test_life_force_target", "")
	target_card.health = 10
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	engine.apply_buff_handle(attacker, "life_force", 1)
	engine._execute_entity_attack(attacker, target, 0)
	assert_eq(target.health, 4, "生命力量应使用当前生命值 6 而不是攻击力 1")


func test_environment_stats_follow_column() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card("pvzh:test_env_stats_entity", "")
	entity_card.attack = 1
	entity_card.health = 3
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	var env_card: CardData = _make_test_card(
		"pvzh:test_env_stats",
		"environment_grant_stats(2, 1, 1, 'ally')"
	)
	env_card.kind = "environment"
	env_card.english_name = "test_env_stats"
	assert_true(engine._place_environment("p", 1, env_card))
	assert_eq(entity.attack, 3)
	assert_eq(entity.max_health, 4)
	assert_eq(entity.health, 4)
	assert_eq(entity.shield, 1)
	assert_true(engine.move_entity(entity, 2, 0))
	assert_eq(entity.attack, 1)
	assert_eq(entity.max_health, 3)
	assert_eq(entity.health, 3)
	assert_eq(entity.shield, 0)


func test_chaos_evolution_and_hand_transform() -> void:
	var engine: BattleEngine = _started_engine()
	var evolution_card: CardData = _make_test_card("pvzh:test_chaos_evolution", "")
	evolution_card.cost = 1
	evolution_card.class_category = "test_chaos_category"
	evolution_card.health = 3
	var evolved_target: CardData = _make_test_card("pvzh:test_chaos_evolved", "")
	evolved_target.english_name = "test_chaos_evolved"
	evolved_target.cost = 2
	evolved_target.class_category = "test_chaos_category"
	evolved_target.health = 4
	var entity: BattleEntity = engine.summon_card("p", evolution_card, 1, 0)
	entity.add_keyword("chaos_evolution")
	engine._resolve_chaos_evolution(1)
	var evolved: BattleEntity = engine._entity_at(1, "p", 0)
	assert_true(evolved != null)
	if evolved != null:
		assert_eq(evolved.card.english_name, "test_chaos_evolved")
		assert_true(evolved.has_keyword("chaos_evolution"))
	var hand_card: CardData = _make_test_card("pvzh:test_chaos_hand", "")
	hand_card.cost = 3
	hand_card.class_category = "test_chaos_hand_category"
	hand_card.kind = "spell"
	var hand_target: CardData = _make_test_card("pvzh:test_chaos_hand_target", "")
	hand_target.cost = 4
	hand_target.class_category = "test_chaos_hand_category"
	hand_target.kind = "spell"
	var instance: BattleCardInstance = BattleCardInstance.create(1000, hand_card.card_id, "p", "hand")
	instance.grant_keyword("chaos_hand", 0)
	engine.players["p"].hand.clear()
	engine.players["p"].add_to_hand(instance)
	engine._resolve_chaos_hand()
	assert_eq(engine.players["p"].hand[0].card_id, hand_target.card_id)
	assert_true(engine.players["p"].hand[0].has_keyword("chaos_hand"))


func test_draw_matching_cards_fatigue_and_draw_event() -> void:
	var engine: BattleEngine = _started_engine()
	var listener_card: CardData = _make_test_card(
		"pvzh:test_draw_listener",
		"when drawn(side == 'ally'):\n    add_marker('drawn_event', 1)"
	)
	listener_card.health = 5
	engine.summon_card("p", listener_card, 0, 0)
	for side: String in ["p", "z"]:
		engine.players[side].hero_health = 30
		engine.players[side].charge_shield_durability = 0
	var state: BattlePlayerState = engine.players["p"]
	state.deck.clear()
	state.hand.clear()
	state.add_to_deck(BattleCardInstance.create(1, "pvzh:gnoll", "p", "deck"))
	state.add_to_deck(BattleCardInstance.create(2, "pvzh:fireball", "p", "deck"))
	assert_eq(engine.draw_matching_cards("p", 1, "kind == 'entity'"), 1)
	assert_eq(state.hand.size(), 1)
	assert_eq(state.hand[0].card_id, "pvzh:gnoll")
	assert_eq(state.marker_count("drawn_event"), 1, "搜寻抽牌应触发 drawn 事件")
	state.deck.clear()
	engine.draw_cards("p", 1)
	assert_eq(state.marker_count(BattleEngine.MARKER_FATIGUE), 1)
	engine._resolve_fatigue()
	assert_eq(state.hero_health, 29, "1 层疲劳应在回合开始造成 1 点伤害")


func test_heal_target_candidates_require_missing_health() -> void:
	var engine: BattleEngine = _started_engine()
	var heal_card: CardData = _make_test_card("pvzh:test_heal_targets", "heal(chosen, 3)")
	heal_card.kind = "spell"
	var full_card: CardData = _make_test_card("pvzh:test_heal_full", "")
	full_card.health = 5
	var injured_card: CardData = _make_test_card("pvzh:test_heal_injured", "")
	injured_card.health = 5
	var full: BattleEntity = engine.summon_card("p", full_card, 0, 0)
	var injured: BattleEntity = engine.summon_card("p", injured_card, 1, 0)
	injured.health = 2
	engine.players["p"].hero_health = 20
	var candidates: Array = engine.target_candidates(heal_card, "p")
	assert_true(candidates.has(injured))
	assert_false(candidates.has(full))
	assert_false(candidates.has(engine.hero_handle("p")), "满血英雄不应成为治疗目标")
	engine.players["p"].hero_health = 18
	candidates = engine.target_candidates(heal_card, "p")
	assert_true(candidates.has(engine.hero_handle("p")), "受伤英雄应成为治疗目标")


func test_keyword_and_tribe_filters_use_membership() -> void:
	var card: CardData = _make_test_card("pvzh:test_filter_membership", "")
	card.keywords = ["frost", "thorns"]
	card.tribes = ["pet", "robot"]
	var filter := CardFilter.new()
	assert_true(filter.parse("keyword == 'frost'"))
	assert_true(filter.matches(card))
	assert_true(filter.parse("tribe == 'pet'"))
	assert_true(filter.matches(card))
	assert_true(filter.parse("keyword != 'deadly'"))
	assert_true(filter.matches(card))


func test_damage_dealt_event_receives_target_array() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card(
		"pvzh:test_damage_dealt_source",
		"when enter:\n    deal_damage(all_enemies, 2)\nwhen damage_dealt:\n    heal(damage_targets, 1)"
	)
	source_card.health = 5
	var source: BattleEntity = engine.summon_card("p", source_card, 2, 0)
	var first_card: CardData = _make_test_card("pvzh:test_damage_dealt_first", "")
	first_card.health = 5
	var second_card: CardData = _make_test_card("pvzh:test_damage_dealt_second", "")
	second_card.health = 5
	var first: BattleEntity = engine.summon_card("z", first_card, 0, 0)
	var second: BattleEntity = engine.summon_card("z", second_card, 1, 0)
	engine._fire_event("enter", source)
	assert_eq(first.health, 4, "复数伤害目标应通过 damage_targets 数组回调")
	assert_eq(second.health, 4)


func test_after_attack_event_fires_after_attack_action() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_after_attack",
		"when after_attack:\n    add_marker('after_attack', 1)"
	)
	attacker_card.attack = 2
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	var target_card: CardData = _make_test_card("pvzh:test_after_attack_target", "")
	target_card.health = 5
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	engine._execute_entity_attack(attacker, target, 0)
	assert_eq(engine.players["p"].marker_count("after_attack"), 1, "攻击动作完成后应触发 after_attack")
	assert_eq(target.health, 3)


func test_damage_column_relative_fallback_and_offsets() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card("pvzh:test_relative_fallback_source", "")
	source_card.health = 5
	var source: BattleEntity = engine.summon_card("p", source_card, 2, 0)
	var only_card: CardData = _make_test_card("pvzh:test_relative_fallback_target", "")
	only_card.health = 5
	var only: BattleEntity = engine.summon_card("z", only_card, 2, BattleEngine.SLOT_TEAM_UP)
	assert_eq(engine.damage_column_relative(source, 2, "front"), 2)
	assert_eq(only.health, 3, "只有一个敌人时前后位置都应命中它")
	assert_eq(engine.damage_column_relative(source, 2, "front", -1), 0)
	only.column = 1
	assert_eq(engine.damage_column_relative(source, 2, "front", -1), 2)
	assert_eq(only.health, 1, "相对列偏移应命中左侧列的唯一敌人")


func test_spell_and_environment_can_use_relative_column_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var enemy_card: CardData = _make_test_card("pvzh:test_relative_spell_enemy", "")
	enemy_card.health = 8
	var enemy: BattleEntity = engine.summon_card("z", enemy_card, 1, 0)
	var spell: CardData = _make_test_card(
		"pvzh:test_relative_spell",
		"choose_column(); damage_column_relative(2, 'front')"
	)
	spell.kind = "spell"
	_set_hand(engine, "p", [spell.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(bool(engine.play_card("p", 0, {"column": 1}).get("ok", false)))
	assert_eq(enemy.health, 6, "选列锦囊应能从所选列释放相对位置伤害")
	var env: CardData = _make_test_card(
		"pvzh:test_relative_env",
		"damage_column_relative(2, 'front')"
	)
	env.kind = "environment"
	env.english_name = "test_relative_env"
	assert_true(engine._place_environment("p", 1, env))
	assert_eq(enemy.health, 4, "环境也应能从自身列释放相对位置伤害")


func test_damage_column_relative_front_and_back() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card("pvzh:test_column_relative_source", "")
	source_card.health = 5
	var source: BattleEntity = engine.summon_card("p", source_card, 2, 0)
	var front_card: CardData = _make_test_card("pvzh:test_column_relative_front", "")
	front_card.health = 5
	var back_card: CardData = _make_test_card("pvzh:test_column_relative_back", "")
	back_card.health = 5
	var front: BattleEntity = engine.summon_card("z", front_card, 2, BattleEngine.SLOT_NORMAL)
	var back: BattleEntity = engine.summon_card("z", back_card, 2, BattleEngine.SLOT_TEAM_UP)
	assert_eq(engine.damage_column_relative(source, 2, "front"), 2)
	assert_eq(front.health, 3)
	assert_eq(back.health, 5)
	assert_eq(engine.damage_column_relative(source, 2, "back"), 2)
	assert_eq(front.health, 3)
	assert_eq(back.health, 3)


func test_deadly_blocked_by_shield_triggers_no_events() -> void:
	var engine: BattleEngine = _started_engine()
	var target_card: CardData = _make_test_card("pvzh:test_deadly_shield_target", "")
	target_card.health = 5
	target_card.shield = 3
	var target: BattleEntity = engine.summon_card("p", target_card, 0, 0)
	var listener_card: CardData = _make_test_card(
		"pvzh:test_deadly_shield_listener",
		"when damaged:\n    gain_attack(1)\nwhen health_changed:\n    gain_attack(1)"
	)
	listener_card.attack = 0
	listener_card.health = 5
	var listener: BattleEntity = engine.summon_card("p", listener_card, 1, 0)
	var effective: int = engine.damage_entity(target, 2, ["deadly"])
	assert_eq(effective, 0, "致命被护盾完全挡下时有效伤害应为 0")
	assert_eq(target.health, 5, "护盾完全挡下时不应扣生命")
	assert_eq(listener.attack, 0, "无效伤害不应触发 damaged / health_changed")


func test_thorns_require_effective_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card("pvzh:test_thorns_zero_attacker", "")
	attacker_card.attack = 1
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	var target_card: CardData = _make_test_card("pvzh:test_thorns_zero_target", "")
	target_card.health = 5
	target_card.shield = 3
	target_card.keywords.append("thorns")
	target_card.keyword_values["thorns"] = 2
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	var attacker_health_before: int = attacker.health
	engine._execute_entity_attack(attacker, target, 0)
	assert_eq(attacker.health, attacker_health_before, "护盾完全挡下时不应触发反伤")
	engine.apply_buff_handle(target, "invincible", 1)
	target.shield = 0
	engine._execute_entity_attack(attacker, target, 0)
	assert_eq(attacker.health, attacker_health_before, "无敌免疫时应不触发反伤")


func test_created_cards_apply_inline_keyword_and_stats() -> void:
	var engine: BattleEngine = _started_engine()
	engine.players["p"].hand.clear()
	var added: int = engine.add_random_cards(
		"p", "hand", 2, "cost == 1", 0, "frost", 2, 3, 1
	)
	assert_eq(added, 2)
	for instance: BattleCardInstance in engine.players["p"].hand:
		assert_true(instance.has_keyword("frost"))
		assert_eq(instance.attack_bonus, 2)
		assert_eq(instance.health_bonus, 3)
		assert_eq(instance.shield_bonus, 1)


func test_created_card_on_deck_top_gets_inline_effects() -> void:
	var engine: BattleEngine = _started_engine()
	assert_true(engine.put_random_card_on_deck_top("p", "cost == 1", "frost", 1, 2, 3))
	var instance: BattleCardInstance = engine.players["p"].deck[0]
	assert_true(instance.has_keyword("frost"))
	assert_eq(instance.attack_bonus, 1)
	assert_eq(instance.health_bonus, 2)
	assert_eq(instance.shield_bonus, 3)


func test_invincible_can_be_destroyed() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_invincible_destroy", "")
	card.health = 5
	var entity: BattleEntity = engine.summon_card("p", card, 1, 0)
	engine.apply_buff_handle(entity, "invincible", 1)
	assert_true(entity.has_buff("invincible"))
	engine.destroy_handle(entity)
	engine._flush_deaths()
	assert_false(entity.is_alive(), "无敌实体应能被消灭效果正常消灭")


func test_entered_this_turn_trigger_only_first_turn() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card(
		"pvzh:test_entered_turn",
		"when turn_end(entered_this_turn):\n    buff_stats(self, -1, 0)"
	)
	card.attack = 3
	card.health = 3
	var entity: BattleEntity = engine.summon_card("p", card, 1, 0)
	engine._resolve_turn_end()
	assert_eq(entity.attack, 2, "入场当回合结束应触发一次")
	engine.turn += 1
	engine._resolve_turn_end()
	assert_eq(entity.attack, 2, "非入场回合不应再次触发")


func test_environment_grants_follow_entity_movement() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card("pvzh:test_env_move_entity", "")
	entity_card.health = 3
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	var env_card: CardData = _make_test_card(
		"pvzh:test_env_move",
		"environment_grant_keyword('deadly', 1, 'ally')"
	)
	env_card.kind = "environment"
	env_card.english_name = "test_env_move"
	assert_true(engine._place_environment("p", 1, env_card))
	assert_true(entity.has_keyword("deadly"))
	assert_true(engine.move_entity(entity, 2, 0))
	assert_false(entity.has_keyword("deadly"), "离开环境列应移除临时词缀")


func test_heal_all_spell_can_play_without_target() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card("pvzh:test_heal_target", "")
	entity_card.health = 5
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	entity.health = 2
	var heal_card: CardData = cards.get_card("pvzh:heal")
	assert_true(heal_card != null)
	if heal_card == null:
		return
	_set_hand(engine, "p", [heal_card.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(result.get("ok", false)), "全体治疗法术不应要求手动目标：%s" % [result])
	assert_eq(entity.health, 5, "全体治疗应恢复到生命上限")


func test_hand_entity_ability_does_not_fire_from_hand() -> void:
	var engine: BattleEngine = _started_engine()
	var hand_card: CardData = _make_test_card(
		"pvzh:test_hand_entity_enter",
		"when enter:\n    deal_damage(all_enemies, 2)"
	)
	hand_card.health = 3
	var target_card: CardData = _make_test_card("pvzh:test_hand_entity_target", "")
	target_card.health = 5
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	_set_hand(engine, "p", [hand_card.card_id])
	var source: BattleEntity = engine.summon_card("p", _make_test_card("pvzh:test_hand_entity_source", ""), 1, 0)
	engine._fire_event("enter", source)
	assert_eq(target.health, 5, "手牌中实体牌的 when enter 不应在场上触发")


func test_damage_log_has_source() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card("pvzh:test_log_source_attacker", "")
	attacker_card.attack = 1
	attacker_card.health = 3
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	var target_card: CardData = _make_test_card("pvzh:test_log_source_target", "")
	target_card.attack = 0
	target_card.health = 3
	engine.summon_card("z", target_card, 0, 0)
	engine._combat_column(0)
	var found: bool = false
	for entry: String in engine.log_entries:
		if entry.contains("来源：") and entry.contains(attacker.display_name()):
			found = true
			break
	assert_true(found, "实体受伤日志应包含伤害来源")


func test_enter_does_not_attack() -> void:
	var engine: BattleEngine = _started_engine()
	var target_card: CardData = _make_test_card("pvzh:test_enter_target", "")
	target_card.health = 5
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	var played_card: CardData = _make_test_card("pvzh:test_enter_unit", "")
	played_card.attack = 3
	played_card.health = 3
	_set_hand(engine, "p", [played_card.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)))
	assert_eq(target.health, 5, "实体入场不应自动攻击")

	var tomb_card: CardData = _make_test_card(
		"pvzh:test_reveal_at_spell_start",
		"when enter:\n    add_marker(\"revealed_at_spell\", 1)"
	)
	tomb_card.keywords.append("tombstone")
	engine.summon_card("p", tomb_card, 1, 0)
	var state: BattlePlayerState = engine.players["p"]
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	engine.advance_phase()
	assert_eq(state.marker_count("revealed_at_spell"), 1, "墓碑应在Z方锦囊阶段开始时揭示")


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
	var hand_ids: Array[String] = []
	var replaced_instance_id: int = 0
	for index: int in range(engine.players["p"].hand.size()):
		hand_ids.append(engine.players["p"].hand[index].card_id)
		if index == 1:
			replaced_instance_id = engine.players["p"].hand[index].instance_id
	engine.replace_mulligan_card("p", 1)
	assert_eq(engine.players["p"].hand[0].card_id, hand_ids[0], "刷新应保持位置不回填前移")
	assert_eq(engine.players["p"].hand[2].card_id, hand_ids[2], "刷新不应移动后续卡牌")
	assert_eq(engine.players["p"].hand[3].card_id, hand_ids[3], "刷新不应移动后续卡牌")


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
		"in_hand()\nwhen health_changed(side == 'ally'):\n    reduce_cost(1)"
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
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	assert_true(entity.add_keyword("first_strike", 2))
	assert_true(entity.add_keyword("first_strike", 3))
	assert_eq(entity.keyword_value("first_strike"), 5, "同词缀数值应相加")
	assert_eq(entity.keyword_value("frost"), 0, "不同词缀数值不互通")

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
	var played: Dictionary = engine.play_card("p", 1, {"column": 2, "slot": 0})
	assert_true(bool(played.get("ok", false)), "带手牌词缀的实体应能打出")
	var played_entity: BattleEntity = engine._entity_at(2, "p", 0)
	assert_true(played_entity != null)
	if played_entity != null:
		assert_eq(played_entity.keyword_value("first_strike"), 2, "手牌词缀应转为实体词缀")


func test_card_filter_and_random_insert() -> void:
	var engine: BattleEngine = _started_engine()
	var filter := CardFilter.new()
	assert_true(filter.parse("kind == 'spell' and rarity == 'rare'"))
	assert_true(filter.matches(cards.get_card("pvzh:fireball")))
	assert_false(filter.matches(cards.get_card("pvzh:gnoll")))
	assert_true(filter.parse("name == 'fireball' or name == 'gnoll'"))
	assert_true(filter.matches(cards.get_card("pvzh:gnoll")))
	assert_true(filter.parse("not name == 'fireball'"))
	assert_false(filter.matches(cards.get_card("pvzh:fireball")))

	var non_includable: CardData = _make_test_card("pvzh:test_non_includable", "")
	non_includable.english_name = "test_non_includable"
	non_includable.deck_includable = false
	assert_true(filter.parse("name == 'test_non_includable'"))
	assert_false(filter.matches(non_includable), "未显式写 deck_includable 时应排除不可组入卡牌")
	assert_true(filter.parse("name == 'test_non_includable' and deck_includable == false"))
	assert_true(filter.matches(non_includable))

	var spell: CardData = _make_test_card(
		"pvzh:test_random_deck_spell",
		"add_random_cards_to_deck(hero, 2, \"kind == 'spell' and rarity == 'normal'\")"
	)
	spell.kind = "spell"
	spell.cost = 1
	var state: BattlePlayerState = engine.players["p"]
	var deck_before: int = state.deck.size()
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.deck.size(), deck_before + 2, "应随机塞入两张牌库牌")

	var hand_spell: CardData = _make_test_card(
		"pvzh:test_random_hand_spell",
		"add_random_cards_to_hand(enemy_hero, 1, \"name == 'gnoll'\")"
	)
	hand_spell.kind = "spell"
	hand_spell.cost = 0
	var enemy_state: BattlePlayerState = engine.players["z"]
	var enemy_hand_before: int = enemy_state.hand.size()
	_set_hand(engine, "p", [hand_spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var hand_result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(hand_result.get("ok", false)))
	assert_eq(enemy_state.hand.size(), enemy_hand_before + 1, "应随机塞入一张敌方手牌")
	var found_gnoll: bool = false
	for card_id: String in enemy_state.hand_ids():
		var inserted: CardData = cards.get_card(card_id)
		if inserted != null and inserted.english_name == "gnoll":
			found_gnoll = true
			break
	assert_true(found_gnoll, "塞入的卡牌英文名应为 gnoll")


func test_keyword_query_and_change_signal() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_keyword_api", "")
	card.keywords.append("triple_strike")
	card.keywords.append("invisible")
	card.keyword_values["invisible"] = 2
	var entity: BattleEntity = engine.summon_card("p", card, 0, 0)
	assert_eq(engine.keyword_value_for(entity, "triple_strike"), 1, "无数值词缀应返回 1")
	assert_eq(engine.keyword_value_for(entity, "invisible"), 2, "有数值词缀应返回数值")
	assert_eq(engine.keyword_value_for(entity, "frenzy"), 0, "不具备词缀应返回 0")
	assert_true(engine.has_keyword_for(entity, "triple_strike"))
	var changes: Array[Dictionary] = []
	engine.keyword_changed.connect(func(handle, keyword, old_value, new_value) -> void:
		changes.append({"handle": handle, "keyword": keyword, "old": old_value, "new": new_value})
	)
	engine.give_keyword_handle(entity, "invisible", 1)
	assert_eq(engine.keyword_value_for(entity, "invisible"), 3)
	assert_eq(changes.size(), 1, "词缀数值变化应发出回调")
	assert_eq(changes[0].get("keyword", ""), "invisible")
	engine.give_keyword_handle(entity, "triple_strike", 0)
	assert_eq(changes.size(), 1, "已有无数值词缀不应重复发回调")


func test_forced_attack_triggers_first_strike_once() -> void:
	var engine: BattleEngine = _started_engine()
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.charge_shield_durability = 0
	z_state.hero_shield = 0
	var before: int = z_state.hero_health
	var card: CardData = _make_test_card("pvzh:test_forced_first_strike", "")
	card.attack = 1
	card.health = 5
	card.keywords.append("first_strike")
	card.keyword_values["first_strike"] = 2
	var attacker: BattleEntity = engine.summon_card("p", card, 2, 0)
	assert_true(engine.force_entity_attack(attacker))
	assert_eq(z_state.hero_health, before - 3, "强制攻击应先触发一次先攻，再造成普通攻击伤害")
	assert_true(engine._first_strike_used_this_round.has(attacker.entity_id), "强制攻击也应写入整轮先攻标记")


func test_first_strike_once_per_round() -> void:
	var engine: BattleEngine = _started_engine()
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.charge_shield_durability = 0
	z_state.hero_shield = 0
	var hero_before: int = z_state.hero_health
	var attacker_card: CardData = _make_test_card("pvzh:test_round_first_strike", "")
	attacker_card.attack = 1
	attacker_card.health = 10
	attacker_card.keywords.append("first_strike")
	attacker_card.keyword_values["first_strike"] = 1
	attacker_card.keywords.append("double_strike")
	attacker_card.keywords.append("triple_strike")
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 2, 0)
	engine._combat_column(2)
	# 1 次先攻 + 双重打击两轮三连打各打英雄一次 = 7
	assert_eq(z_state.hero_health, hero_before - 7, "先攻整轮只应触发一次")


func test_game_over_stops_remaining_effects() -> void:
	var engine: BattleEngine = _started_engine()
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.hero_health = 1
	z_state.charge_shield_durability = 0
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_lethal_first_strike",
		"when attack:\n    add_marker(\"attack_after_win\", 1)"
	)
	attacker_card.attack = 1
	attacker_card.health = 5
	attacker_card.keywords.append("first_strike")
	attacker_card.keyword_values["first_strike"] = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	engine._execute_attack_action(attacker, false)
	assert_eq(engine.winner, "p", "英雄死亡应立即判定胜负")
	assert_eq(engine.players["p"].marker_count("attack_after_win"), 0, "胜负后不应继续触发攻击事件")
	assert_true(z_state.hero_health <= 0)


func test_attack_modifier_fixes() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_modifier_attacker",
		""
	)
	attacker_card.attack = 1
	attacker_card.health = 10
	attacker_card.keywords.append("strikethrough")
	attacker_card.keywords.append("first_strike")
	attacker_card.keywords.append("triple_strike")
	attacker_card.keyword_values["first_strike"] = 2
	attacker_card.keywords.append("overshoot")
	attacker_card.keyword_values["overshoot"] = 2
	engine.summon_card("p", attacker_card, 2, 0)
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.charge_shield_durability = 0
	z_state.hero_shield = 0
	var z_health: int = z_state.hero_health
	for column: int in [1, 2, 3]:
		var enemy_card: CardData = _make_test_card(
			"pvzh:test_struck_%d" % column,
			"when attacked:\n    add_marker(\"attacked\", 1)"
		)
		enemy_card.attack = 0
		enemy_card.health = 5
		engine.summon_card("z", enemy_card, column, 0)
	var ally_card: CardData = _make_test_card("pvzh:test_splash_ally", "")
	ally_card.attack = 0
	ally_card.health = 5
	var ally: BattleEntity = engine.summon_card("p", ally_card, 1, 0)
	engine._execute_attack_action(engine._entity_at(2, "p", 0), false)
	assert_eq(z_state.hero_health, z_health - 2 - 3, "先攻只触发一次，但穿透三列各命中英雄一次")
	assert_eq(z_state.marker_count("attacked"), 3, "穿透命中每个敌人应触发 attacked")
	assert_eq(ally.health, 5, "溅射不应伤害友方实体")


func test_triple_strike_and_aloe_captain() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card("pvzh:test_triple", "")
	attacker_card.attack = 1
	attacker_card.health = 5
	attacker_card.keywords.append("triple_strike")
	engine.summon_card("p", attacker_card, 2, 0)
	var targets: Array[BattleEntity] = []
	for column: int in [1, 2, 3]:
		var target_card: CardData = _make_test_card("pvzh:test_triple_target_%d" % column, "")
		target_card.attack = 0
		target_card.health = 5
		targets.append(engine.summon_card("z", target_card, column, 0))
	engine._combat_column(2)
	assert_eq(targets[0].health, 4, "三连打应先攻击左列")
	assert_eq(targets[1].health, 4, "三连打应攻击自身列")
	assert_eq(targets[2].health, 4, "三连打应攻击右列")

	var state: BattlePlayerState = engine.players["p"]
	var aloe_card: CardData = _make_test_card(
		"pvzh:test_aloe",
		"in_hand()\nwhen hand_played:\n    gain_attack(1)\nwhen ally_attack_gained:\n    buff_stats(self, 0, 1)"
	)
	aloe_card.attack = 2
	aloe_card.health = 3
	state.hand.clear()
	state.hand.append(BattleCardInstance.create(9001, aloe_card.card_id, "p", "hand"))
	state.hand.append(BattleCardInstance.create(9002, "pvzh:gnoll", "p", "hand"))
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var played: Dictionary = engine.play_card("p", 1, {"column": 0, "slot": 0})
	assert_true(bool(played.get("ok", false)))
	assert_eq(state.hand[0].attack_bonus, 1, "芦荟队长在手牌中应因打出牌获得攻击")
	var ally: BattleEntity = engine._entity_at(0, "p", 0)
	engine.buff_handle(ally, 2, 0)
	assert_eq(state.hand[0].health_bonus, 1, "友方实体加攻时芦荟队长应获得生命")
	var aloe_entity: BattleEntity = engine.summon_card("p", aloe_card, 0, 0, state.hand[0].attack_bonus)
	aloe_entity.apply_instance_keywords(state.hand[0])
	engine._apply_instance_stats(aloe_entity, state.hand[0])
	assert_eq(aloe_entity.attack, 3, "入场应保留手牌攻击增益")
	assert_eq(aloe_entity.max_health, 4, "入场应保留手牌生命增益")


func test_display_state_api() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_display_api", "")
	card.attack = 2
	card.health = 3
	card.shield = 1
	card.keywords.append("deadly")
	var entity: BattleEntity = engine.summon_card("p", card, 0, 0)
	assert_eq(engine.get_display_stats(entity).get("attack", 0), 2)
	engine.apply_buff_handle(entity, "frozen", 1)
	var display: Dictionary = engine.get_display_stats(entity)
	assert_eq(display.get("health", 0), 3)
	var entries: Array[Dictionary] = engine.get_display_entries(entity)
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(str(entry.get("id", "")))
	assert_true(ids.has("deadly"), "在场实体应返回词缀")
	assert_true(ids.has("frozen"), "在场实体应返回 Buff")
	assert_eq(str(engine.get_display_icon_styles(entity).get("attack", "")), "deadly")
	assert_eq(str(engine.get_display_icon_styles(entity).get("health", "")), "frozen")
	var changes: Array = []
	engine.display_state_changed.connect(func(_handle) -> void: changes.append(1))
	var hand_instance: BattleCardInstance = BattleCardInstance.create(7001, "pvzh:gnoll", "p", "hand")
	engine.players["p"].hand.append(hand_instance)
	engine.buff_handle(hand_instance, 3, 2)
	assert_eq(engine.get_display_stats(hand_instance).get("attack", 0), 4, "手牌攻击应为最终值")
	assert_false(changes.is_empty(), "手牌数值变化应触发显示刷新")


func test_bounce_and_invisible() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_bounce", "")
	card.cost = 2
	card.health = 3
	var entity: BattleEntity = engine.summon_card("p", card, 0, 0)
	var state: BattlePlayerState = engine.players["p"]
	state.hand.clear()
	assert_true(engine.apply_buff_handle(entity, "bounce"))
	assert_false(entity.alive, "弹回应移除原实体")
	assert_eq(state.hand.size(), 1, "弹回应将原牌加入手牌")
	assert_eq(state.hand[0].card_id, "pvzh:test_bounce")
	state.hand.clear()
	var hand_limit: int = engine.mode.hand_limit
	for _index: int in range(hand_limit):
		state.hand.append(BattleCardInstance.create(100 + _index, "pvzh:gnoll", "p", "hand"))
	var second: BattleEntity = engine.summon_card("p", card, 1, 0)
	assert_true(engine.apply_buff_handle(second, "bounce"))
	assert_eq(state.deck[0].card_id, "pvzh:test_bounce", "手牌满时弹回到牌库顶")
	var invisible_card: CardData = _make_test_card("pvzh:test_invisible", "")
	invisible_card.health = 5
	invisible_card.keyword_values["invisible"] = 1
	invisible_card.keywords.append("invisible")
	var invisible: BattleEntity = engine.summon_card("p", invisible_card, 0, 0)
	var before: int = invisible.health
	engine.damage_entity(invisible, 4, [])
	assert_eq(invisible.health, before, "隐形应免疫无必中伤害")
	engine.damage_entity(invisible, 4, ["bullseye"])
	assert_eq(invisible.health, before - 4, "必中伤害应无视隐形")
	assert_true(engine.remove_entity_handle(invisible), "隐形不能阻止移除")


func test_card_filter_cost_comparison() -> void:
	var filter := CardFilter.new()
	assert_true(filter.parse("cost <= 3"))
	var cheap: CardData = _make_test_card("pvzh:test_cost_filter", "")
	cheap.cost = 3
	assert_true(filter.matches(cheap))
	cheap.cost = 4
	assert_false(filter.matches(cheap))
	filter = CardFilter.new()
	assert_true(filter.parse("cost > 2 and cost < 5"))
	cheap.cost = 3
	assert_true(filter.matches(cheap))


func test_double_death_effects() -> void:
	var engine: BattleEngine = _started_engine()
	var mine_card: CardData = _make_test_card("pvzh:test_double_death_mine", "double_death_effects()")
	mine_card.health = 5
	engine.summon_card("p", mine_card, 0, 0)
	var ally_card: CardData = _make_test_card(
		"pvzh:test_double_death_ally",
		"when die:\n    add_marker(\"death_effect\", 1)"
	)
	ally_card.health = 2
	var ally: BattleEntity = engine.summon_card("p", ally_card, 1, 0)
	engine.damage_entity(ally, 99, [])
	engine._flush_deaths()
	assert_eq(engine.players["p"].marker_count("death_effect"), 2, "终极地雷应让友方亡语触发两次")


func test_tombstone_burial_reveal_and_hidden_energy() -> void:
	var engine: BattleEngine = _started_engine()
	var tomb_card: CardData = _make_test_card(
		"pvzh:test_tombstone",
		"when enter:\n    add_marker(\"revealed\", 1)"
	)
	tomb_card.keywords.append("tombstone")
	tomb_card.cost = 1
	tomb_card.health = 3
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [tomb_card.card_id])
	state.energy = 3
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 2, "slot": 0})
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.energy, 2)
	assert_eq(state.hidden_energy_spent, 1)
	assert_eq(engine.visible_energy_for("p", "z"), 3, "敌方看到的费用应隐藏墓碑支出")
	var buried: BattleEntity = engine._entity_at(2, "p", 0)
	assert_true(buried.has_buff("buried"))
	assert_eq(state.marker_count("revealed"), 0, "埋入墓碑时不应触发入场")
	assert_false(engine.is_entity_visible_to(buried, "z"), "敌方不应看到墓碑内实体信息")
	engine._reveal_tombstones()
	assert_false(buried.has_buff("buried"))
	assert_eq(state.marker_count("revealed"), 1, "揭示时应结算入场效果")
	assert_eq(engine.visible_energy_for("p", "z"), 2, "揭示后费用恢复公开")


func test_tombstone_removal_spells() -> void:
	var engine: BattleEngine = _started_engine()
	var grave_card: CardData = _make_test_card("pvzh:test_grave_target", "")
	grave_card.keywords.append("tombstone")
	grave_card.health = 5
	var first: BattleEntity = engine.summon_card("p", grave_card, 1, 0)
	var second: BattleEntity = engine.summon_card("p", grave_card, 2, 0)
	assert_true(first.has_buff("buried") and second.has_buff("buried"))
	var sweep: CardData = _make_test_card(
		"pvzh:test_grave_sweep",
		"choose_column(); destroy(buried_in_column)"
	)
	sweep.kind = "spell"
	sweep.cost = 1
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [sweep.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 1})
	assert_true(bool(result.get("ok", false)))
	assert_false(first.alive)
	assert_true(second.alive)
	var execute: CardData = _make_test_card(
		"pvzh:test_grave_execute",
		"choose(1, \"all_buried\"); destroy(chosen)"
	)
	execute.kind = "spell"
	execute.cost = 1
	_set_hand(engine, "p", [execute.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var execute_result: Dictionary = engine.play_card("p", 0, {"handles": [second]})
	assert_true(bool(execute_result.get("ok", false)))
	assert_false(second.alive)


func test_buff_and_keyword_combat_features() -> void:
	var engine: BattleEngine = _started_engine()
	var striker_card: CardData = _make_test_card("pvzh:test_buff_striker", "")
	striker_card.health = 5
	striker_card.keywords.append("double_strike")
	var striker: BattleEntity = engine.summon_card("p", striker_card, 0, 0)
	var target: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	target.max_health = 2
	target.health = 2
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "z"
	engine.advance_phase()
	assert_true(striker != null)
	assert_false(target.alive, "双重打击应在第一次攻击和死亡结算后再次攻击")

	var frozen_engine: BattleEngine = _started_engine()
	var frozen_entity: BattleEntity = frozen_engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, 0)
	assert_true(frozen_engine.apply_buff_handle(frozen_entity, "frozen", 1))
	assert_false(frozen_engine.force_entity_attack(frozen_entity), "冰冻实体不能攻击")
	assert_true(frozen_engine.remove_buff_handle(frozen_entity, "frozen"))

	var buff_listener_card: CardData = _make_test_card(
		"pvzh:test_buff_listener",
		"when buff_applied:\n    add_marker(\"buff_applied\", 1)\nwhen buff_removed:\n    add_marker(\"buff_removed\", 1)"
	)
	var buff_listener: BattleEntity = frozen_engine.summon_card_in_column("p", buff_listener_card, 1)
	frozen_engine.apply_buff_handle(buff_listener, "frozen", 1)
	frozen_engine.remove_buff_handle(buff_listener, "frozen")
	assert_eq(frozen_engine.players["p"].marker_count("buff_applied"), 1, "Buff 施加事件应触发")
	assert_eq(frozen_engine.players["p"].marker_count("buff_removed"), 1, "Buff 解除事件应触发")

	var debuff_immune_card: CardData = _make_test_card("pvzh:test_debuff_immune", "")
	debuff_immune_card.keywords.append("debuff_immune")
	var debuff_immune: BattleEntity = frozen_engine.summon_card("p", debuff_immune_card, 2, 0)
	assert_false(frozen_engine.apply_buff_handle(debuff_immune, "frozen", 1), "免疫负面应拒绝冰冻")
	assert_true(frozen_engine.apply_buff_handle(debuff_immune, "invincible", 1), "免疫负面不影响 Buff")

	var invincible_entity: BattleEntity = frozen_engine.summon_card("p", cards.get_card("pvzh:gnoll"), 1, 0)
	assert_true(frozen_engine.apply_buff_handle(invincible_entity, "invincible", 1))
	var health_before: int = invincible_entity.health
	frozen_engine.damage_entity(invincible_entity, 99, [])
	assert_eq(invincible_entity.health, health_before, "无敌 Buff 应免疫伤害")
	frozen_engine.destroy_handle(invincible_entity)
	assert_true(invincible_entity.alive, "无敌 Buff 应免疫直接消灭")


func test_environment_keyword_restriction() -> void:
	var engine: BattleEngine = _started_engine()
	var normal_card: CardData = _make_test_card("pvzh:test_water_normal", "")
	var amphibious_card: CardData = _make_test_card("pvzh:test_water_amphibious", "")
	amphibious_card.keywords.append("amphibious")
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [normal_card.card_id, amphibious_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var normal_slots: Array[Dictionary] = engine.valid_slots("p", normal_card)
	for slot_info: Dictionary in normal_slots:
		assert_true(int(slot_info.get("column", -1)) != 4, "非两栖实体不能进入水池列")
	var amphibious_slots: Array[Dictionary] = engine.valid_slots("p", amphibious_card)
	var water_allowed: bool = false
	for slot_info: Dictionary in amphibious_slots:
		if int(slot_info.get("column", -1)) == 4:
			water_allowed = true
	assert_true(water_allowed, "两栖实体可以进入水池列")
	assert_eq(str(engine.environment_owners[0]), "", "初始环境应为中立")


func test_counter_and_hunt_keywords() -> void:
	var engine: BattleEngine = _started_engine()
	var counter_card: CardData = _make_test_card("pvzh:test_counter", "")
	counter_card.keywords.append("hero_counter")
	counter_card.keyword_values["hero_counter"] = 2
	var counter: BattleEntity = engine.summon_card("p", counter_card, 0, 0)
	assert_eq(counter.attack, counter_card.attack + 2, "无敌方实体时应获得克制英雄攻击")
	var enemy: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	assert_eq(counter.attack, counter_card.attack, "敌方实体在场时应移除克制加成")
	engine.entities.erase(enemy)
	enemy.alive = false
	engine._refresh_all_counter_bonuses()
	assert_eq(counter.attack, counter_card.attack + 2)
	assert_eq(str(engine.environment_owners[0]), "", "初始环境应为中立")

	var hunt_card: CardData = _make_test_card("pvzh:test_hunt", "")
	hunt_card.keywords.append("hunt")
	hunt_card.health = 5
	var hunter: BattleEntity = engine.summon_card("p", hunt_card, 1, 0)
	var entering_card: CardData = _make_test_card("pvzh:test_hunt_target", "")
	entering_card.health = 5
	engine.summon_card_in_column("z", entering_card, 3)
	assert_eq(hunter.column, 3, "捕猎实体应移动到敌方入场列")


func test_frenzy_piercing_and_splash() -> void:
	var frenzy_engine: BattleEngine = _started_engine()
	var frenzy_card: CardData = _make_test_card("pvzh:test_frenzy", "")
	frenzy_card.attack = 5
	frenzy_card.health = 5
	frenzy_card.keywords.append("frenzy")
	var frenzy: BattleEntity = frenzy_engine.summon_card("p", frenzy_card, 0, 0)
	var victim: BattleEntity = frenzy_engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	frenzy_engine._execute_entity_attack(frenzy, victim, 0)
	frenzy_engine._flush_column_deaths(0)
	assert_eq(int(frenzy_engine.players["z"].hero_health), 15, "狂热击杀后应追加一次攻击")

	var pierce_engine: BattleEngine = _started_engine()
	var pierce_card: CardData = _make_test_card("pvzh:test_pierce", "")
	pierce_card.attack = 2
	pierce_card.health = 5
	pierce_card.keywords.append("strikethrough")
	var pierce: BattleEntity = pierce_engine.summon_card("p", pierce_card, 0, 0)
	var z_first: BattleEntity = pierce_engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	var z_second_card: CardData = _make_test_card("pvzh:test_pierce_second", "")
	z_second_card.health = 5
	var z_second: BattleEntity = pierce_engine.summon_card("z", z_second_card, 0, 1)
	pierce_engine._execute_entity_attack(pierce, z_first, 0)
	assert_true(z_first.health <= 0, "穿透应命中列内所有敌方实体")
	assert_eq(z_second.health, 3, "穿透应命中列内所有敌方实体")
	assert_eq(int(pierce_engine.players["z"].hero_health), 18, "穿透还应命中敌方英雄")

	var splash_engine: BattleEngine = _started_engine()
	var splash_card: CardData = _make_test_card("pvzh:test_splash", "")
	splash_card.attack = 1
	splash_card.health = 5
	splash_card.keywords.append("overshoot")
	splash_card.keyword_values["overshoot"] = 2
	splash_engine.summon_card("p", splash_card, 2, 0)
	var side_target: BattleEntity = splash_engine.summon_card("z", cards.get_card("pvzh:gnoll"), 1, 0)
	side_target.max_health = 5
	side_target.health = 5
	var splash_attacker: BattleEntity = splash_engine._entity_at(2, "p", 0)
	var hero_health_before: int = int(splash_engine.players["z"].hero_health)
	splash_engine._execute_entity_attack(splash_attacker, splash_engine.hero_handle("z"), 0)
	assert_eq(side_target.health, 3, "溅射应伤害相邻列的实体")
	assert_eq(int(splash_engine.players["z"].hero_health), hero_health_before - 1, "溅射不应额外伤害英雄")


func test_spell_immune_frost_and_thorns() -> void:
	var engine: BattleEngine = _started_engine()
	var target: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	assert_true(engine.apply_buff_handle(target, "spell_immune", 1))
	var fireball: CardData = cards.get_card("pvzh:fireball")
	var candidates: Array = engine.target_candidates(fireball, "p")
	assert_false(candidates.has(target), "临时锦囊免疫实体不应成为锦囊目标")
	engine.damage_entity(target, 2, [], true)
	assert_eq(target.health, target.max_health, "锦囊伤害不应影响临时锦囊免疫实体")

	var frost_target: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 1, 0)
	engine.damage_entity(frost_target, 1, ["frost"])
	assert_true(frost_target.is_frozen(), "寒霜伤害应施加冰冻 Buff")

	var attacker: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 2, 0)
	var thorn_card: CardData = _make_test_card("pvzh:test_thorns", "")
	thorn_card.health = 5
	thorn_card.keywords.append("thorns")
	thorn_card.keyword_values["thorns"] = 2
	var thorn_target: BattleEntity = engine.summon_card("z", thorn_card, 2, 0)
	var attacker_health: int = attacker.health
	engine._execute_entity_attack(attacker, thorn_target, 0)
	assert_eq(attacker.health, attacker_health - 2, "反伤应对攻击来源造成伤害")


func test_neutral_environment_rejects_side_effects() -> void:
	var engine: BattleEngine = _started_engine()
	var p_entity: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 2, 0)
	var neutral := EnvironmentEffectContext.new(engine, "", 2)
	assert_eq(str(neutral.describe_entity(p_entity).get("side", "")), "neutral")
	assert_true(neutral.entities_in_column(0, 0, "ally").is_empty(), "中立环境拒绝判断我方")
	assert_true(neutral.entities_in_column(0, 0, "enemy").is_empty(), "中立环境拒绝判断敌方")


func test_evolve_play_and_filter() -> void:
	var engine: BattleEngine = _started_engine()
	var old_entity: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 0, 0)
	var evolve_card: CardData = _make_test_card(
		"pvzh:test_evolve",
		"evolve(\"name == 'gnoll'\")\nwhen evolved:\n    add_marker(\"evolved\", 1)"
	)
	evolve_card.health = 3
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [evolve_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var slots: Array[Dictionary] = engine.valid_slots("p", evolve_card)
	var has_evolve_slot: bool = false
	for slot_info: Dictionary in slots:
		if int(slot_info.get("column", -1)) == 0 and int(slot_info.get("slot", -1)) == 0:
			has_evolve_slot = true
	assert_true(has_evolve_slot, "进化实体应能选择已有友方实体位置")
	var result: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)))
	assert_false(old_entity.alive, "进化应移除原实体")
	var evolved: BattleEntity = engine._entity_at(0, "p", 0)
	assert_true(evolved != null and evolved.card.card_id == evolve_card.card_id)
	assert_eq(state.marker_count("evolved"), 1, "进化筛选匹配时应触发后续效果")


func test_base_mount_transfers_stats_and_runs_ability() -> void:
	var engine: BattleEngine = _started_engine()
	var base_card: CardData = _make_test_card(
		"pvzh:test_base",
		"base()\nwhen mounted:\n    apply_buff(mounted, \"frozen\")\n    add_marker(\"mounted\", 1)"
	)
	base_card.attack = 2
	base_card.health = 4
	base_card.shield = 1
	var base_entity: BattleEntity = engine.summon_card("p", base_card, 0, 0)
	var rider: CardData = _make_test_card("pvzh:test_rider", "")
	rider.attack = 1
	rider.health = 2
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [rider.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 0, "slot": 0})
	assert_true(bool(result.get("ok", false)))
	assert_false(base_entity.alive, "放置到基地上时基地应被移除")
	var mounted: BattleEntity = engine._entity_at(0, "p", 0)
	assert_true(mounted != null)
	assert_eq(mounted.attack, 3, "骑乘实体应继承基地攻击")
	assert_eq(mounted.health, 6, "骑乘实体应继承基地生命")
	assert_eq(mounted.shield, 1, "骑乘实体应继承基地防御")
	assert_true(mounted.is_frozen(), "基地的 mounted 能力应能指定新实体")
	assert_eq(state.marker_count("mounted"), 1)


func test_remove_entity_does_not_trigger_death() -> void:
	var engine: BattleEngine = _started_engine()
	var entity_card: CardData = _make_test_card(
		"pvzh:test_remove",
		"when die:\n    add_marker(\"died\", 1)"
	)
	var entity: BattleEntity = engine.summon_card("p", entity_card, 1, 0)
	assert_true(engine.remove_entity_handle(entity))
	assert_false(entity.alive)
	assert_eq(engine.players["p"].marker_count("died"), 0, "移除不应触发死亡事件/亡语")


func test_extra_attack_event() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_extra_attack",
		"when extra_attack:\n    add_marker(\"extra_attack\", 1)"
	)
	attacker_card.attack = 1
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 0, 0)
	engine.summon_card("z", cards.get_card("pvzh:gnoll"), 0, 0)
	assert_true(engine.force_entity_attack(attacker))
	assert_eq(engine.players["p"].marker_count("extra_attack"), 1, "额外攻击应触发事件")


func test_column_event_relative_condition_and_query() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card(
		"pvzh:test_column_listener",
		"when enter(side == 'ally' and column == -1):\n    buff_stats(entities_in_column(1, 1, \"ally\", 4), 1, 0)"
	)
	var strong_card: CardData = _make_test_card("pvzh:test_column_strong", "")
	strong_card.attack = 4
	strong_card.health = 5
	var source: BattleEntity = engine.summon_card_in_column("p", source_card, 2)
	var strong: BattleEntity = engine.summon_card_in_column("p", strong_card, 3)
	assert_true(source != null and strong != null)
	var trigger: BattleEntity = engine.summon_card_in_column("p", cards.get_card("pvzh:gnoll"), 1)
	assert_true(trigger != null)
	assert_eq(strong.attack, 5, "左侧一列友方入场应增强右侧一列攻击 >3 的友方")


func test_spell_choose_column_destroy_both_sides() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_column_spell",
		"choose_column()\ndestroy(entities_in_column(0, 0, \"both\"))"
	)
	spell.kind = "spell"
	spell.cost = 1
	var p_entity: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 2, 0)
	var z_entity: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 2, 0)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(spell.ability_script.column_requirement())
	var result: Dictionary = engine.play_card("p", 0, {"column": 2})
	assert_true(bool(result.get("ok", false)))
	assert_false(p_entity.alive)
	assert_false(z_entity.alive)


func test_spell_choose_column_range() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_column_range_spell",
		"choose_column()\ndestroy(entities_in_column(-1, 1, \"both\"))"
	)
	spell.kind = "spell"
	spell.cost = 1
	var left: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 1, 0)
	var center: BattleEntity = engine.summon_card("z", cards.get_card("pvzh:gnoll"), 2, 0)
	var right: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 3, 0)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {"column": 2})
	assert_true(bool(result.get("ok", false)))
	assert_false(left.alive)
	assert_false(center.alive)
	assert_false(right.alive)


func test_place_environment_in_relative_column() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card(
		"pvzh:test_environment_placer",
		"when enter:\n    place_environment(-1, \"sunny_field\")"
	)
	var source: BattleEntity = engine.summon_card_in_column("p", source_card, 2)
	assert_true(source != null)
	assert_eq(str(engine.environments[1]), "sunny_field")
	assert_eq(str(engine.environment_owners[1]), "p")


func test_protected_environment_cannot_be_replaced() -> void:
	var engine: BattleEngine = _started_engine()
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", ["pvzh:sunny_field"])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var blocked: Dictionary = engine.play_card("p", 0, {"column": 0})
	assert_false(bool(blocked.get("ok", true)), "高地默认不可被环境牌覆盖")
	var allowed: Dictionary = engine.play_card("p", 0, {"column": 2})
	assert_true(bool(allowed.get("ok", false)), "普通环境列可以打出环境牌")
	assert_eq(str(engine.environments[2]), "sunny_field")


func test_environment_events_and_turn_end() -> void:
	var engine: BattleEngine = _started_engine()
	var environment_card: CardData = _make_test_card(
		"pvzh:test_environment_effects",
		"when turn_end:\n    heal(entities_in_column(0, 0, \"ally\"), 1)\nwhen enter(side == 'enemy'):\n    deal_damage(event, 5)"
	)
	environment_card.kind = "environment"
	environment_card.english_name = "test_environment_effects"
	environment_card.chinese_name = "测试环境效果"
	environment_card.cost = 1
	var p_entity: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 2, 0)
	p_entity.max_health = 5
	p_entity.health = 3
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [environment_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var placed: Dictionary = engine.play_card("p", 0, {"column": 2})
	assert_true(bool(placed.get("ok", false)))
	engine._resolve_turn_end()
	assert_eq(p_entity.health, 4, "环境应在回合结束治疗同列友方")
	var enemy_card: CardData = _make_test_card("pvzh:test_environment_enemy", "")
	enemy_card.health = 10
	var enemy: BattleEntity = engine.summon_card_in_column("z", enemy_card, 2)
	assert_true(enemy != null)
	assert_eq(enemy.health, 5, "环境应在敌方实体入场时造成 5 点伤害")


func test_summon_absolute_column_and_range() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_summon_spell",
		"summon(\"gnoll\", 1)"
	)
	spell.kind = "spell"
	spell.cost = 1
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(result.get("ok", false)))
	assert_eq(engine._entity_at(0, "p", BattleEngine.SLOT_NORMAL).card.card_id, "pvzh:gnoll")
	var range_spell: CardData = _make_test_card(
		"pvzh:test_summon_range",
		"summon(\"gnoll\", 2, 4)"
	)
	range_spell.kind = "spell"
	range_spell.cost = 1
	_set_hand(engine, "p", [range_spell.card_id])
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	var before: int = engine.entities.size()
	var range_result: Dictionary = engine.play_card("p", 0, {})
	assert_true(bool(range_result.get("ok", false)))
	assert_eq(engine.entities.size(), before + 1, "一条 summon 语句只召唤一个实体")
	var summoned: BattleEntity = engine.entities[engine.entities.size() - 1]
	assert_true(summoned.column >= 1 and summoned.column <= 3, "范围召唤应落在第 2~4 列")


func test_summon_entity_relative_column() -> void:
	var engine: BattleEngine = _started_engine()
	var source_card: CardData = _make_test_card(
		"pvzh:test_summon_relative",
		"when enter:\n    summon(\"gnoll\", -1)"
	)
	var source: BattleEntity = engine.summon_card_in_column("p", source_card, 2)
	assert_true(source != null)
	var summoned: BattleEntity = engine._entity_at(1, "p", BattleEngine.SLOT_NORMAL)
	assert_true(summoned != null, "实体异能应以自身列为基准相对召唤")
	assert_eq(summoned.card.card_id, "pvzh:gnoll")


func test_non_team_entity_can_displace_team_occupant() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = _make_test_card("pvzh:test_team_occupant", "")
	team_card.keywords.append("team_up")
	var normal_card: CardData = _make_test_card("pvzh:test_normal_new", "")
	var occupant: BattleEntity = engine.summon_card("p", team_card, 0, BattleEngine.SLOT_NORMAL)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [normal_card.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_HAND
	engine.active_side = "p"
	var result: Dictionary = engine.play_card("p", 0, {
		"column": 0, "slot": BattleEngine.SLOT_NORMAL,
	})
	assert_true(bool(result.get("ok", false)), "已占用格有组队实体时，普通实体也可挤压放置")
	assert_eq(occupant.slot, BattleEngine.SLOT_TEAM_UP)


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


func test_move_entity_team_up_displaces_without_displacement_event() -> void:
	var engine: BattleEngine = _started_engine()
	var occupant_card: CardData = _make_test_card(
		"pvzh:test_move_occupant",
		"when position_changed:\n    add_marker(\"moved\", 1)"
	)
	var mover_card: CardData = _make_test_card("pvzh:test_move_mover", "")
	mover_card.keywords.append("team_up")
	var occupant: BattleEntity = engine.summon_card("p", occupant_card, 0, 0)
	var mover: BattleEntity = engine.summon_card("p", mover_card, 1, 0)
	var state: BattlePlayerState = engine.players["p"]
	assert_true(engine.move_entity(mover, 0, 0))
	assert_eq(mover.column, 0)
	assert_eq(mover.slot, 0)
	assert_eq(occupant.slot, 1, "目标格原实体应被挤到同列另一格")
	assert_eq(state.marker_count("moved"), 0, "被挤开的实体不应触发 position_changed")


func test_non_team_entity_can_move_onto_team_occupant() -> void:
	var engine: BattleEngine = _started_engine()
	var team_card: CardData = _make_test_card("pvzh:test_move_team_occupant", "")
	team_card.keywords.append("team_up")
	var normal_card: CardData = _make_test_card("pvzh:test_move_normal_mover", "")
	var occupant: BattleEntity = engine.summon_card("p", team_card, 0, BattleEngine.SLOT_NORMAL)
	var mover: BattleEntity = engine.summon_card("p", normal_card, 1, BattleEngine.SLOT_NORMAL)
	assert_true(engine.move_entity(mover, 0, 0))
	assert_eq(occupant.slot, BattleEngine.SLOT_TEAM_UP)
	assert_eq(mover.slot, BattleEngine.SLOT_NORMAL)


func test_move_entity_chosen_position_dsl() -> void:
	var engine: BattleEngine = _started_engine()
	var spell: CardData = _make_test_card(
		"pvzh:test_move_spell",
		"choose(1, \"all_enemies\")\nmove_entity(chosen)"
	)
	spell.kind = "spell"
	spell.cost = 1
	var target_card: CardData = _make_test_card(
		"pvzh:test_move_target",
		"when position_changed:\n    add_marker(\"moved\", 1)"
	)
	var target: BattleEntity = engine.summon_card("z", target_card, 0, 0)
	var state: BattlePlayerState = engine.players["p"]
	_set_hand(engine, "p", [spell.card_id])
	state.energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(spell.ability_script.move_requires_position())
	var result: Dictionary = engine.play_card("p", 0, {
		"handles": [target], "column": 1, "slot": BattleEngine.SLOT_TEAM_UP,
	})
	assert_true(bool(result.get("ok", false)), "单参数 move_entity 应使用选择的位置：%s" % [result.get("message", "")])
	assert_eq(target.column, 1)
	assert_eq(target.slot, BattleEngine.SLOT_TEAM_UP)
	assert_eq(engine.players["z"].marker_count("moved"), 1, "移动的实体应触发 position_changed")


func test_move_slots_only_own_side_and_exclude_current() -> void:
	var engine: BattleEngine = _started_engine()
	var entity: BattleEntity = engine.summon_card("p", cards.get_card("pvzh:gnoll"), 2, 0)
	var slots: Array[Dictionary] = engine.valid_move_slots(entity)
	assert_true(not slots.is_empty())
	for slot_info: Dictionary in slots:
		assert_eq(engine._entity_at(int(slot_info.column), "p", int(slot_info.slot)), null)
		assert_true(not (int(slot_info.column) == 2 and int(slot_info.slot) == 0), "不能选择当前位置")


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
	engine.phase = BattleEngine.PHASE_SPELL
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
	card.english_name = "anim_test_unit"
	card.chinese_name = "动画测试"
	card.attack = 1
	card.health = 5
	card.animation_script = CardAnimationScript.parse(
		"when attack:\n    play_animation(self, \"slash\", \"whole\")\nwhen die:\n    play_animation(self, \"death\", \"art\")"
	)
	cards.cards[card.card_id] = card
	var engine: BattleEngine = _started_engine()
	var cues: Array[String] = []
	engine.animation_cue.connect(func(trigger: String, _actor: BattleEntity, _target: Variant) -> void:
		cues.append(trigger)
	)
	var z_card: CardData = card.duplicate()
	z_card.card_id = "pvzh:anim_test_target"
	z_card.english_name = "anim_test_target"
	z_card.chinese_name = "动画目标"
	z_card.attack = 0
	z_card.health = 1
	z_card.animation_script = CardAnimationScript.parse("when die:\n    play_animation(self, \"death\", \"art\")")
	cards.cards[z_card.card_id] = z_card
	engine.summon_card("p", card, 0, BattleEngine.SLOT_NORMAL)
	engine.summon_card("z", z_card, 0, BattleEngine.SLOT_NORMAL)
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
		"in_deck()\nwhen ally_die(zone == 'deck'):\n    gain_attack(1)"
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
		"in_hand()\nwhen ally_die(zone == 'hand'):\n    gain_attack(1)\n    reduce_cost(1)"
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


func test_entities_matching_uses_current_board_state() -> void:
	var engine: BattleEngine = _started_engine()
	var soldier_card: CardData = _make_test_card("pvzh:test_match_soldier", "")
	soldier_card.card_class = "soldier"
	soldier_card.cost = 2
	soldier_card.health = 4
	var zombie_card: CardData = _make_test_card("pvzh:test_match_zombie", "")
	zombie_card.card_class = "zombie"
	zombie_card.cost = 5
	zombie_card.health = 4
	var frosted_card: CardData = _make_test_card("pvzh:test_match_frosted", "")
	frosted_card.card_class = "zombie"
	frosted_card.cost = 1
	frosted_card.health = 4
	var soldier: BattleEntity = engine.summon_card("z", soldier_card, 1, 0)
	var zombie: BattleEntity = engine.summon_card("z", zombie_card, 2, 0)
	var frosted: BattleEntity = engine.summon_card("z", frosted_card, 3, 0)
	frosted.add_keyword("frost")
	var spell: CardData = _make_test_card(
		"pvzh:test_match_spell",
		"destroy(entities_matching(\"class == 'soldier' and cost <= 3\"))\n"
		+ "destroy(entities_matching(\"keyword == 'frost'\"))"
	)
	spell.kind = "spell"
	spell.cost = 1
	_set_hand(engine, "p", [spell.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(bool(engine.play_card("p", 0, {}).get("ok", false)))
	engine._flush_deaths()
	assert_false(soldier.is_alive(), "符合 class + cost 的士兵应被消灭")
	assert_false(frosted.is_alive(), "运行期获得的寒霜词缀也应参与筛选")
	assert_true(zombie.is_alive(), "不符合条件的僵尸应存活")


func test_hero_guard_redirects_hero_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var guardian_card: CardData = _make_test_card("pvzh:test_hero_guard", "")
	guardian_card.health = 6
	var guardian: BattleEntity = engine.summon_card("p", guardian_card, 1, 0)
	guardian.add_keyword("hero_guard")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 20
	engine.damage_hero("p", 4)
	assert_eq(p_state.hero_health, 20, "守护实体在场时英雄不掉血")
	assert_eq(guardian.health, 2, "伤害应转由守护实体承受")


func test_hero_guard_picks_highest_health_guardian() -> void:
	var engine: BattleEngine = _started_engine()
	var weak_card: CardData = _make_test_card("pvzh:test_guard_weak", "")
	weak_card.health = 2
	var strong_card: CardData = _make_test_card("pvzh:test_guard_strong", "")
	strong_card.health = 9
	var weak_guard: BattleEntity = engine.summon_card("p", weak_card, 1, 0)
	weak_guard.add_keyword("hero_guard")
	var strong_guard: BattleEntity = engine.summon_card("p", strong_card, 2, 0)
	strong_guard.add_keyword("hero_guard")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 20
	engine.damage_hero("p", 3)
	assert_eq(strong_guard.health, 6, "应由当前生命最高的守护实体承伤")
	assert_eq(weak_guard.health, 2, "另一个守护实体不承伤")
	assert_eq(p_state.hero_health, 20)


func test_hero_guard_applies_entity_mitigation() -> void:
	var engine: BattleEngine = _started_engine()
	var guardian_card: CardData = _make_test_card("pvzh:test_guard_shield", "")
	guardian_card.health = 8
	guardian_card.shield = 2
	var guardian: BattleEntity = engine.summon_card("p", guardian_card, 1, 0)
	guardian.add_keyword("hero_guard")
	engine.damage_hero("p", 5)
	assert_eq(guardian.health, 5, "守护实体按自身防御减伤（5 - 2 = 3 点）")


func test_hero_guard_stops_after_guardian_dies() -> void:
	var engine: BattleEngine = _started_engine()
	var guardian_card: CardData = _make_test_card("pvzh:test_guard_dies", "")
	guardian_card.health = 3
	var guardian: BattleEntity = engine.summon_card("p", guardian_card, 1, 0)
	guardian.add_keyword("hero_guard")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 20
	engine.damage_hero("p", 8)
	engine._flush_deaths()
	assert_false(guardian.is_alive(), "守护实体应被这次伤害打死")
	assert_eq(p_state.hero_health, 20, "守护实体倒下后溢出伤害不会转到英雄")
	engine.damage_hero("p", 2)
	assert_eq(p_state.hero_health, 18, "没有守护实体后英雄正常受击")


func test_hero_guard_intercepts_attack_on_hero() -> void:
	var engine: BattleEngine = _started_engine()
	var guardian_card: CardData = _make_test_card("pvzh:test_guard_attack", "")
	guardian_card.health = 9
	var guardian: BattleEntity = engine.summon_card("p", guardian_card, 1, 0)
	guardian.add_keyword("hero_guard")
	var attacker_card: CardData = _make_test_card("pvzh:test_guard_attacker", "")
	attacker_card.attack = 4
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("z", attacker_card, 2, 0)
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 15
	assert_true(engine.force_entity_attack(attacker))
	assert_eq(p_state.hero_health, 15, "打向英雄的攻击伤害应被守护实体接住")
	assert_eq(guardian.health, 5, "守护实体承受 4 点攻击伤害")


func test_hero_ward_keeps_hero_at_one() -> void:
	var engine: BattleEngine = _started_engine()
	var warder_card: CardData = _make_test_card("pvzh:test_hero_ward", "")
	var warder: BattleEntity = engine.summon_card("p", warder_card, 1, 0)
	warder.add_keyword("hero_ward")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 10
	engine.damage_hero("p", 99)
	assert_eq(p_state.hero_health, 1, "英雄壁垒应把生命值卡在 1")
	assert_eq(engine.winner, "", "不应因这次伤害判负")


func test_hero_ward_blocks_damage_when_already_at_one() -> void:
	var engine: BattleEngine = _started_engine()
	var warder_card: CardData = _make_test_card("pvzh:test_hero_ward_low", "")
	var warder: BattleEntity = engine.summon_card("p", warder_card, 1, 0)
	warder.add_keyword("hero_ward")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 1
	engine.damage_hero("p", 5)
	assert_eq(p_state.hero_health, 1, "已经 1 点时再受伤仍保持 1")
	assert_eq(engine.winner, "", "不应判负")


func test_hero_guard_and_ward_stack() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_guard_and_ward", "")
	card.health = 10
	var guardian: BattleEntity = engine.summon_card("p", card, 1, 0)
	guardian.add_keyword("hero_guard")
	guardian.add_keyword("hero_ward")
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 5
	engine.damage_hero("p", 6)
	assert_eq(p_state.hero_health, 5, "有守护实体时英雄完全不掉血")
	assert_eq(guardian.health, 4, "伤害由守护实体承受")


func test_hero_damage_without_guard_still_hits_hero() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	p_state.hero_health = 20
	engine.damage_hero("p", 6)
	assert_eq(p_state.hero_health, 14, "没有守护词缀时伤害照常落在英雄身上")


func test_after_attack_resolves_before_death_flush() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_after_attack_order",
		"when after_attack: for_each(all_enemies) as e:\n    if health <= 0:\n        add_marker('saw_dead', 1)"
	)
	attacker_card.attack = 5
	attacker_card.health = 6
	attacker_card.keywords = ["frenzy"]
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 1, 0)
	var target_card: CardData = _make_test_card("pvzh:test_after_attack_target", "")
	target_card.health = 3
	var target: BattleEntity = engine.summon_card("z", target_card, 1, 0)
	assert_true(engine.force_entity_attack(attacker), "强制攻击应成功")
	assert_eq(
		engine.players["p"].marker_count("saw_dead"), 1,
		"after_attack 应在死亡判定前结算，此时被击杀的敌方仍在场（生命 <= 0）"
	)
	assert_false(target.is_alive(), "本次攻击仍应正常结算死亡")


func test_damage_dealt_includes_hero_targets() -> void:
	var engine: BattleEngine = _started_engine()
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_damage_dealt_hero",
		"when damage_dealt: for_each(damage_targets) as t: add_marker('dealt', 1)"
	)
	attacker_card.attack = 3
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 1, 0)
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.hero_health = 20
	assert_true(engine.force_entity_attack(attacker), "该列没有敌方实体，应攻击英雄")
	assert_eq(z_state.hero_health, 17, "英雄应受到 3 点伤害")
	assert_eq(
		engine.players["p"].marker_count("dealt"), 1,
		"damage_dealt 的 damage_targets 应包含英雄目标"
	)


func test_multi_target_damage_callbacks_split_by_type() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.hero_health = 20
	var enemy_card: CardData = _make_test_card("pvzh:test_callback_enemy", "")
	enemy_card.health = 10
	var enemy: BattleEntity = engine.summon_card("z", enemy_card, 1, 0)
	var source_card: CardData = _make_test_card(
		"pvzh:test_callback_source",
		"when enter:\n"
		+ "    deal_damage(enemy_hero_or_entities, 2)\n"
		+ "when damage_dealt:\n"
		+ "    for_each(damage_targets) as t:\n"
		+ "        if class == 'hero':\n"
		+ "            add_marker('hero_hit', 1)\n"
		+ "        else:\n"
		+ "            add_marker('entity_hit', 1)"
	)
	var source: BattleEntity = engine.summon_card("p", source_card, 2, 0)
	engine._fire_event("enter", source)
	assert_eq(z_state.hero_health, 18, "英雄应受到 2 点伤害")
	assert_eq(enemy.health, 8, "敌方实体应受到 2 点伤害")
	assert_eq(p_state.marker_count("hero_hit"), 1, "回调里应识别出英雄目标")
	assert_eq(p_state.marker_count("entity_hit"), 1, "回调里应识别出实体目标")


func test_damaged_and_damage_dealt_are_separate_triggers() -> void:
	var engine: BattleEngine = _started_engine()
	var p_state: BattlePlayerState = engine.players["p"]
	var z_state: BattlePlayerState = engine.players["z"]
	z_state.hero_health = 20
	var attacker_card: CardData = _make_test_card(
		"pvzh:test_trigger_source",
		"when damage_dealt: add_marker('source_trigger', 1)"
	)
	attacker_card.attack = 2
	attacker_card.health = 5
	var target_card: CardData = _make_test_card(
		"pvzh:test_trigger_target",
		"when damaged: add_marker('target_trigger', 1)"
	)
	target_card.health = 6
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 1, 0)
	var target: BattleEntity = engine.summon_card("z", target_card, 1, 0)
	assert_true(engine.force_entity_attack(attacker))
	assert_true(target.alive, "目标应存活，便于区分两个触发器的独立生效")
	assert_eq(p_state.marker_count("source_trigger"), 1, "来源侧应触发 damage_dealt")
	assert_eq(z_state.marker_count("target_trigger"), 1, "受伤侧应触发 damaged")
	# 再打英雄（该列没有敌方实体）：damage_dealt 触发，但英雄受伤不触发 damaged
	var attacker2_card: CardData = _make_test_card(
		"pvzh:test_trigger_source2",
		"when damage_dealt: add_marker('source_trigger', 1)"
	)
	attacker2_card.attack = 2
	attacker2_card.health = 5
	var attacker2: BattleEntity = engine.summon_card("p", attacker2_card, 3, 0)
	assert_true(engine.force_entity_attack(attacker2), "该列没有敌方实体，应攻击英雄")
	assert_eq(p_state.marker_count("source_trigger"), 2, "打英雄同样触发 damage_dealt")
	assert_eq(z_state.marker_count("target_trigger"), 1, "英雄受伤不会触发 damaged")


func test_damaged_exposes_entity_source() -> void:
	var engine: BattleEngine = _started_engine()
	var receiver_card: CardData = _make_test_card(
		"pvzh:test_damaged_source_receiver",
		"when damaged:\n    if is_entity(damage_source):\n        apply_buff(damage_source, 'hatred')"
	)
	receiver_card.health = 8
	var receiver: BattleEntity = engine.summon_card("z", receiver_card, 1, 0)
	var attacker_card: CardData = _make_test_card("pvzh:test_damaged_source_dealer", "")
	attacker_card.attack = 2
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 1, 0)
	assert_true(engine.force_entity_attack(attacker))
	assert_true(receiver.alive, "目标应存活以便观察效果")
	assert_true(attacker.has_buff("hatred"), "受伤方应能通过 damage_source 给来源施加 Buff")


func test_damaged_source_is_null_for_spell_damage() -> void:
	var engine: BattleEngine = _started_engine()
	var receiver_card: CardData = _make_test_card(
		"pvzh:test_damaged_null_receiver",
		"when damaged:\n    if is_entity(damage_source):\n        add_marker('got_source', 1)"
	)
	receiver_card.health = 8
	var receiver: BattleEntity = engine.summon_card("z", receiver_card, 1, 0)
	var spell: CardData = _make_test_card("pvzh:test_damaged_null_spell", "deal_damage(enemy_entities, 2)")
	spell.kind = "spell"
	spell.cost = 1
	_set_hand(engine, "p", [spell.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(bool(engine.play_card("p", 0, {}).get("ok", false)))
	assert_eq(receiver.health, 6, "锦囊伤害应正常生效")
	assert_eq(engine.players["p"].marker_count("got_source"), 0, "锦囊伤害没有实体来源")
	var error_count: int = 0
	for entry: String in engine.log_entries:
		if entry.begins_with("效果错误"):
			error_count += 1
	assert_eq(error_count, 0, "来源为 null 时不应产生运行错误")


func test_damaged_can_destroy_entity_source() -> void:
	var engine: BattleEngine = _started_engine()
	var rose_card: CardData = _make_test_card(
		"pvzh:test_thorn_rose_style",
		"when damaged(side == 'ally'):\n    if is_entity(damage_source):\n        destroy(damage_source)"
	)
	rose_card.health = 6
	engine.summon_card("p", rose_card, 1, 0)
	var victim_card: CardData = _make_test_card("pvzh:test_thorn_rose_victim", "")
	victim_card.health = 8
	var victim: BattleEntity = engine.summon_card("p", victim_card, 2, 0)
	var attacker_card: CardData = _make_test_card("pvzh:test_thorn_rose_attacker", "")
	attacker_card.attack = 2
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("z", attacker_card, 2, 0)
	assert_true(engine.force_entity_attack(attacker))
	engine._flush_deaths()
	assert_false(attacker.is_alive(), "友方受伤时，监听者应消灭伤害来源实体")
	assert_true(victim.alive, "受伤的友方应存活（本次伤害不足以致死）")


func test_hero_damaged_event_filters_by_side() -> void:
	var engine: BattleEngine = _started_engine()
	var watcher_card: CardData = _make_test_card(
		"pvzh:test_hero_damaged_watcher",
		"when hero_damaged(side == 'ally'):\n    add_marker('own_hero_hurt', 1)"
	)
	engine.summon_card("p", watcher_card, 1, 0)
	engine.damage_hero("p", 2)
	assert_eq(engine.players["p"].marker_count("own_hero_hurt"), 1, "我方英雄受伤应触发")
	engine.damage_hero("z", 2)
	assert_eq(engine.players["p"].marker_count("own_hero_hurt"), 1, "敌方英雄受伤不应触发")


func test_hero_damaged_exposes_source_and_amount() -> void:
	var engine: BattleEngine = _started_engine()
	var watcher_card: CardData = _make_test_card(
		"pvzh:test_hero_damaged_source",
		"when hero_damaged(side == 'ally' and is_entity(damage_source) and damage_amount >= 3):\n"
		+ "    give_keyword(damage_source, 'deadly')"
	)
	engine.summon_card("p", watcher_card, 1, 0)
	var attacker_card: CardData = _make_test_card("pvzh:test_hero_damaged_attacker", "")
	attacker_card.attack = 3
	attacker_card.health = 5
	var attacker: BattleEntity = engine.summon_card("z", attacker_card, 2, 0)
	assert_true(engine.force_entity_attack(attacker), "该列没有 p 实体，应攻击 p 英雄")
	assert_true(attacker.has_keyword("deadly"), "hero_damaged 应能拿到伤害来源并施加效果")


func test_force_attack_outside_combat_keeps_combat_buffs() -> void:
	var engine: BattleEngine = _started_engine()
	engine.phase = BattleEngine.PHASE_HAND
	var attacker_card: CardData = _make_test_card("pvzh:test_force_keep_attacker", "")
	attacker_card.attack = 2
	attacker_card.health = 8
	var attacker: BattleEntity = engine.summon_card("p", attacker_card, 1, 0)
	var victim_card: CardData = _make_test_card("pvzh:test_force_keep_victim", "")
	victim_card.health = 10
	var victim: BattleEntity = engine.summon_card("z", victim_card, 1, 0)
	engine.apply_buff_handle(victim, "frozen", 1)
	engine.apply_buff_handle(victim, "invincible", 2)
	assert_true(engine.force_entity_attack(attacker), "战斗阶段之外也应允许强制攻击")
	assert_true(victim.has_buff("frozen"), "战斗阶段之外的强制攻击不应解除冰冻")
	assert_true(victim.has_buff("invincible"), "战斗阶段之外的强制攻击不应解除无敌")
	assert_eq(int(victim.buffs.get("invincible", 0)), 2, "无敌层数也不应被清")
	assert_eq(victim.health, 10, "无敌使本次攻击不造成伤害")


func test_column_combat_clear_removes_all_stacks() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_clear_stacks", "")
	card.health = 5
	var entity: BattleEntity = engine.summon_card("p", card, 1, 0)
	engine.apply_buff_handle(entity, "frozen", 2)
	engine.apply_buff_handle(entity, "invincible", 2)
	engine._clear_column_combat_buffs(1)
	assert_false(entity.has_buff("frozen"), "冰冻应被全部清除")
	assert_false(entity.has_buff("invincible"), "无敌的每一层都应被清除")


func test_spell_immunity_only_blocks_spell_sources() -> void:
	var engine: BattleEngine = _started_engine()
	var keyword_card: CardData = _make_test_card("pvzh:test_spell_immune_keyword", "")
	keyword_card.health = 6
	keyword_card.keywords = ["spell_immune"]
	var buffed_card: CardData = _make_test_card("pvzh:test_spell_immune_buff", "")
	buffed_card.health = 6
	var keyword_target: BattleEntity = engine.summon_card("z", keyword_card, 1, 0)
	var buffed_target: BattleEntity = engine.summon_card("z", buffed_card, 2, 0)
	assert_true(engine.apply_buff_handle(buffed_target, "spell_immune", 1))
	# 锦囊来源的消灭：两个目标都应免疫
	var spell: CardData = _make_test_card(
		"pvzh:test_spell_immune_destroy_spell",
		"destroy(enemy_entities)"
	)
	spell.kind = "spell"
	spell.cost = 1
	_set_hand(engine, "p", [spell.card_id])
	engine.players["p"].energy = 10
	engine.phase = BattleEngine.PHASE_SPELL
	engine.active_side = "p"
	assert_true(bool(engine.play_card("p", 0, {}).get("ok", false)))
	engine._flush_deaths()
	assert_true(keyword_target.alive, "锦囊消灭不应影响锦囊免疫词缀实体")
	assert_true(buffed_target.alive, "锦囊消灭不应影响临时锦囊免疫实体")
	# 实体特殊能力的消灭：应正常生效
	var killer_card: CardData = _make_test_card(
		"pvzh:test_spell_immune_killer",
		"when enter: destroy(enemy_entities)"
	)
	var killer: BattleEntity = engine.summon_card("p", killer_card, 3, 0)
	engine._fire_event("enter", killer)
	engine._flush_deaths()
	assert_false(keyword_target.alive, "实体能力消灭应能消灭锦囊免疫词缀实体")
	assert_false(buffed_target.alive, "实体能力消灭应能消灭临时锦囊免疫实体")


func test_invincible_keyword_only_grants_buff() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_invincible_keyword", "")
	card.health = 5
	card.keywords = ["invincible"]
	var entity: BattleEntity = engine.summon_card("p", card, 1, 0)
	assert_true(entity.has_buff("invincible"), "无敌词缀应在入场时给一层无敌 Buff")
	engine.damage_entity(entity, 3, [])
	assert_eq(entity.health, 5, "无敌 Buff 应免疫伤害")
	assert_true(engine.remove_buff_handle(entity, "invincible"))
	assert_false(entity.is_invincible(), "Buff 移除后词缀本身不应继续提供无敌")
	engine.damage_entity(entity, 3, [])
	assert_eq(entity.health, 2, "Buff 移除后应正常受伤")


func test_spell_immunity_ignores_friendly_spells() -> void:
	var engine: BattleEngine = _started_engine()
	var own_card: CardData = _make_test_card("pvzh:test_friendly_immune_own", "")
	own_card.health = 8
	var enemy_card: CardData = _make_test_card("pvzh:test_friendly_immune_enemy", "")
	enemy_card.health = 8
	var own_immune: BattleEntity = engine.summon_card("p", own_card, 1, 0)
	var enemy_immune: BattleEntity = engine.summon_card("z", enemy_card, 2, 0)
	engine.apply_buff_handle(own_immune, "spell_immune", 1)
	engine.apply_buff_handle(enemy_immune, "spell_immune", 1)
	var context := BattleEffectContext.new(engine, "p")
	context.set_spell_source(true)
	# 我方锦囊：伤害 / Buff / 消灭都应作用于我方免疫实体（不判断效果有益或有害）
	context.deal_damage(own_immune, 3)
	assert_eq(own_immune.health, 5, "我方锦囊伤害应命中我方锦囊免疫实体")
	assert_true(context.apply_buff(own_immune, "frozen"), "我方锦囊的 Buff 应生效")
	context.destroy(own_immune)
	assert_eq(own_immune.health, 0, "我方锦囊的消灭应生效")
	# 敌方锦囊：仍然全部被免疫
	context.deal_damage(enemy_immune, 3)
	assert_eq(enemy_immune.health, 8, "敌方锦囊伤害应被免疫")
	assert_false(context.apply_buff(enemy_immune, "frozen"), "敌方锦囊 Buff 应被免疫")
	context.destroy(enemy_immune)
	assert_eq(enemy_immune.health, 8, "敌方锦囊消灭应被免疫")


func test_friendly_spell_targeting_and_choose_include_immune_allies() -> void:
	var engine: BattleEngine = _started_engine()
	var own_card: CardData = _make_test_card("pvzh:test_friendly_target_own", "")
	own_card.health = 5
	var enemy_card: CardData = _make_test_card("pvzh:test_friendly_target_enemy", "")
	enemy_card.health = 5
	var own_immune: BattleEntity = engine.summon_card("p", own_card, 1, 0)
	var enemy_immune: BattleEntity = engine.summon_card("z", enemy_card, 2, 0)
	engine.apply_buff_handle(own_immune, "spell_immune", 1)
	engine.apply_buff_handle(enemy_immune, "spell_immune", 1)
	own_immune.health = 3
	var heal_spell: CardData = _make_test_card("pvzh:test_friendly_heal", "heal(all_allies, 2)")
	heal_spell.kind = "spell"
	var candidates: Array = engine.target_candidates(heal_spell, "p")
	assert_true(candidates.has(own_immune), "我方锦囊应能选中我方锦囊免疫实体")
	var ally_pool: Array = engine.choose_candidates("all_allies", "p", true)
	assert_true(ally_pool.has(own_immune), "我方锦囊 choose 应包含我方免疫实体")
	var enemy_pool: Array = engine.choose_candidates("all_enemies", "p", true)
	assert_false(enemy_pool.has(enemy_immune), "敌方锦囊 choose 应排除敌方免疫实体")


func test_environment_effects_ignore_spell_immunity() -> void:
	var engine: BattleEngine = _started_engine()
	var card: CardData = _make_test_card("pvzh:test_env_immune_target", "")
	card.health = 6
	var target: BattleEntity = engine.summon_card("z", card, 2, 0)
	engine.apply_buff_handle(target, "spell_immune", 1)
	var env := EnvironmentEffectContext.new(engine, "p", 2)
	env.deal_damage(target, 2)
	assert_eq(target.health, 4, "环境效果应正常作用于锦囊免疫实体")
	env.destroy(target)
	assert_eq(target.health, 0, "环境消灭应正常作用于锦囊免疫实体")


func test_bounce_death_check_only_resolves_itself() -> void:
	var engine: BattleEngine = _started_engine()
	var bounced_card: CardData = _make_test_card("pvzh:test_bounce_self_a", "")
	bounced_card.health = 3
	var other_card: CardData = _make_test_card("pvzh:test_bounce_self_b", "")
	other_card.health = 3
	var bounced: BattleEntity = engine.summon_card("p", bounced_card, 1, 0)
	var other: BattleEntity = engine.summon_card("p", other_card, 2, 0)
	bounced.health = 0
	other.health = 0
	engine.apply_buff_handle(bounced, "bounce")
	assert_false(bounced.alive, "被弹回的实体应先结算自身死亡")
	assert_true(other.alive, "其他 0 血实体不应被弹回顺带结算")

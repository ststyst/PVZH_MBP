class_name BattleEngine
extends RefCounted
## 战斗核心（无 UI）：5 列 × 双方各 2 个位置；回合阶段、出牌、战斗结算、死亡与胜负。
## 效果通过 BattleEffectContext 执行（DSL 原语）。所有规则数值来自 GameModeConfig。

signal changed()
signal game_finished(winner_side: String)
## 英雄实际受到伤害（已扣护盾/免疫后）；amount > 0 时才发出。
signal hero_damaged(side: String, amount: int, source_keywords: Array)
## 动画触发：trigger = attack / ability / die；target 为 BattleEntity 或 "hero:x"
signal animation_cue(trigger: String, actor: BattleEntity, target: Variant)

const SIDE_P: String = "p"
const SIDE_Z: String = "z"
const COLUMN_COUNT: int = 5
const SLOT_NORMAL: int = 0
const SLOT_TEAM_UP: int = 1

const PHASE_MULLIGAN: String = "mulligan"
const PHASE_HAND: String = "hand"
const PHASE_SPELL: String = "spell"
const PHASE_COMBAT: String = "combat"
const PHASE_TURN_END: String = "turn_end"
const PHASE_SPECIAL: String = "special"
const PHASE_GAME_OVER: String = "game_over"

const ENV_HIGHGROUND: String = "highground"
const ENV_DEFAULT: String = "default"
const ENV_WATER: String = "water"
const DEFAULT_ENVIRONMENTS: Array = ["highground", "default", "default", "default", "water"]
const DEFAULT_ENVIRONMENT_LABELS: Array = ["高地", "默认", "默认", "默认", "水池"]

var mode: GameModeConfig = null
## 单次出牌/战斗行为允许的连锁事件上限（由服务器配置注入）
var effect_resolution_limit: int = 100
var players: Dictionary = {}
var entities: Array[BattleEntity] = []
var environments: Array[String] = []
var environment_labels: Array[String] = []
var turn: int = 1
var phase: String = PHASE_MULLIGAN
var active_side: String = ""
var winner: String = ""
var log_entries: Array[String] = []
var mulligan_ready: Dictionary = {SIDE_P: false, SIDE_Z: false}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var card_database: Object = null

var _next_entity_id: int = 1
var _next_card_instance_id: int = 1
var _emitting_game_over: bool = false
## 特殊回合（充能护盾免疫触发）待处理阵营
var _special_pending_sides: Array[String] = []
var _special_resume_phase: String = ""
var _special_resume_active_side: String = ""
var _special_turn_end_resolved: bool = false
var _special_resolving: bool = false
var _effect_resolution_count: int = 0
var _effect_limit_hit: bool = false


func _init(database = null, battle_seed: int = 0) -> void:
	card_database = database
	if battle_seed != 0:
		rng.seed = battle_seed
	else:
		rng.randomize()


func setup(
	player_side: String,
	player_hero: HeroData,
	player_deck: Array[String],
	enemy_hero: HeroData,
	enemy_deck: Array[String],
	mode_config: GameModeConfig = null,
) -> void:
	mode = mode_config if mode_config != null else GameModeConfig.default_config()
	players.clear()
	entities.clear()
	log_entries.clear()
	winner = ""
	_emitting_game_over = false
	turn = 1
	phase = PHASE_MULLIGAN
	active_side = ""
	_next_entity_id = 1
	_next_card_instance_id = 1
	_special_pending_sides.clear()
	_special_resume_phase = ""
	_special_resume_active_side = ""
	_special_turn_end_resolved = false
	_special_resolving = false
	environments.clear()
	environment_labels.clear()
	for entry: Variant in DEFAULT_ENVIRONMENTS:
		environments.append(str(entry))
	for entry: Variant in DEFAULT_ENVIRONMENT_LABELS:
		environment_labels.append(str(entry))
	var enemy_side: String = opposite_side(player_side)
	players[player_side] = _create_player(player_side, player_hero, player_deck)
	players[enemy_side] = _create_player(enemy_side, enemy_hero, enemy_deck)
	for side: String in [SIDE_P, SIDE_Z]:
		var initial_draw: int = mode.initial_draw_for_faction(side)
		draw_cards(side, initial_draw)
	_grant_initial_superpowers()
	mulligan_ready = {SIDE_P: false, SIDE_Z: false}
	_log("对局开始：%s vs %s" % [player_hero.display_name(), enemy_hero.display_name()])
	changed.emit()


func opposite_side(side: String) -> String:
	return SIDE_Z if side == SIDE_P else SIDE_P


func _create_player(side: String, hero: HeroData, deck_ids: Array[String]) -> BattlePlayerState:
	var state := BattlePlayerState.new()
	state.side = side
	state.hero = hero
	state.hero_max_health = mode.hero_max_health_for_faction(side)
	state.hero_health = state.hero_max_health
	state.energy = 0
	state.energy_cap = mode.energy_cap
	state.charge_shield = 0
	state.charge_shield_durability = mode.charge_shield_durability
	state.charge_shield_emergency_uses = mode.charge_shield_emergency_uses
	state.superpower_pool.clear()
	if hero != null:
		for card_id: String in hero.special_card_ids:
			var special_card: CardData = get_card(card_id)
			if special_card != null and special_card.is_spell() and not state.superpower_pool.has(card_id):
				state.superpower_pool.append(card_id)
	state.deck.clear()
	for card_id: String in deck_ids:
		state.add_to_deck(_new_card_instance(card_id, side, "deck"))
	_shuffle_zones(state)
	return state


func _new_card_instance(card_id: String, side: String, zone: String) -> BattleCardInstance:
	var instance := BattleCardInstance.create(
		_next_card_instance_id, card_id, side, zone
	)
	_next_card_instance_id += 1
	return instance


## 测试/服务器补牌入口：把一张卡直接放入手牌或牌库。
func add_card_to_hand(side: String, card_id: String) -> BattleCardInstance:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return null
	var instance: BattleCardInstance = _new_card_instance(card_id, side, "hand")
	state.add_to_hand(instance)
	return instance


func add_card_to_deck(side: String, card_id: String) -> BattleCardInstance:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return null
	var instance: BattleCardInstance = _new_card_instance(card_id, side, "deck")
	state.add_to_deck(instance)
	return instance


func _grant_initial_superpowers() -> void:
	for side: String in [SIDE_P, SIDE_Z]:
		_grant_superpower_card(side, false)


## 从该英雄的超能力池随机取一张；as_offer=true 时标记为特殊回合的临时 -1 费牌。
func _grant_superpower_card(side: String, as_offer: bool = true) -> BattleCardInstance:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or state.superpower_pool.is_empty():
		return null
	var index: int = rng.randi_range(0, state.superpower_pool.size() - 1)
	var card_id: String = state.superpower_pool[index]
	state.superpower_pool.remove_at(index)
	var instance: BattleCardInstance = add_card_to_hand(side, card_id)
	if instance == null:
		return null
	if as_offer:
		state.special_offer_id = instance.instance_id
	_log("%s 获得超能力：%s%s" % [
		side.to_upper(), instance.card_id,
		"（特殊回合）" if as_offer else "",
	])
	return instance


func _trigger_superpower_offer(side: String) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or state.special_offer_id != 0:
		return
	var instance: BattleCardInstance = _grant_superpower_card(side, true)
	if instance == null:
		_log("%s 超能力牌池为空，取消本次特殊回合" % side.to_upper())
		return
	state.special_choice = ""
	if not _special_pending_sides.has(side):
		_special_pending_sides.append(side)
	changed.emit()


func _maybe_begin_special_turn(resume_phase: String, turn_end_resolved: bool = false) -> bool:
	if _special_pending_sides.is_empty() or phase == PHASE_SPECIAL:
		return false
	_special_resume_phase = resume_phase
	_special_resume_active_side = active_side
	_special_turn_end_resolved = turn_end_resolved
	phase = PHASE_SPECIAL
	active_side = ""
	_log("特殊回合：等待 %s 选择超能力" % "、".join(_special_pending_sides))
	changed.emit()
	return true


func special_resolve_hand(side: String) -> Dictionary:
	if phase != PHASE_SPECIAL or not _special_pending_sides.has(side):
		return _fail("当前不处于该阵营的特殊回合。")
	if _special_waits_for_priority(side):
		return _fail("请等待优先阵营先结算超能力。")
	var state: BattlePlayerState = players.get(side, null)
	if state == null or state.special_offer_id == 0:
		return _fail("没有可选择的超能力牌。")
	state.special_offer_id = 0
	state.special_choice = "hand"
	_special_pending_sides.erase(side)
	_log("%s 将超能力移入手牌" % side.to_upper())
	if _special_pending_sides.is_empty():
		_finish_special_turn()
	return {"ok": true, "message": "已移入手牌。"}


func special_resolve_play(side: String, target: Dictionary = {}) -> Dictionary:
	if phase != PHASE_SPECIAL or not _special_pending_sides.has(side):
		return _fail("当前不处于该阵营的特殊回合。")
	if _special_waits_for_priority(side):
		return _fail("请等待优先阵营先结算超能力。")
	var state: BattlePlayerState = players.get(side, null)
	if state == null or state.special_offer_id == 0:
		return _fail("没有可选择的超能力牌。")
	var hand_index: int = state.find_hand_index(state.special_offer_id)
	if hand_index < 0:
		return _fail("超能力牌不在手牌中。")
	var instance: BattleCardInstance = state.hand[hand_index]
	var original_delta: int = instance.cost_delta
	var original_phase: String = phase
	var original_active: String = active_side
	instance.cost_delta -= 1
	phase = PHASE_HAND
	active_side = side
	_special_resolving = true
	var result: Dictionary = play_card(side, hand_index, target)
	_special_resolving = false
	if not bool(result.get("ok", false)):
		instance.cost_delta = original_delta
		phase = original_phase
		active_side = original_active
		return result
	state.special_offer_id = 0
	state.special_choice = "play"
	_special_pending_sides.erase(side)
	_log("%s 在特殊回合打出超能力" % side.to_upper())
	if _special_pending_sides.is_empty():
		_finish_special_turn()
	else:
		phase = PHASE_SPECIAL
		active_side = ""
		changed.emit()
	return result


func _special_waits_for_priority(side: String) -> bool:
	if _special_pending_sides.size() <= 1:
		return false
	var other: String = opposite_side(side)
	return _special_pending_sides.has(other) and mode.superpower_priority_side != side


func _finish_special_turn() -> void:
	var resume_phase: String = _special_resume_phase
	var resume_side: String = _special_resume_active_side
	var end_resolved: bool = _special_turn_end_resolved
	_special_resume_phase = ""
	_special_resume_active_side = ""
	_special_turn_end_resolved = false
	phase = resume_phase
	active_side = resume_side
	if phase == PHASE_TURN_END:
		if not end_resolved:
			_clear_hero_shields()
			_resolve_turn_end()
		if winner == "":
			_start_next_turn()
	else:
		changed.emit()


func get_card(card_id: String) -> CardData:
	if card_database == null:
		return null
	return card_database.get_card(card_id)


func get_card_by_english(english_name: String) -> CardData:
	if card_database == null:
		return null
	return card_database.find_by_english(english_name)


func hand_card(side: String, index: int) -> CardData:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or index < 0 or index >= state.hand.size():
		return null
	return get_card(state.hand[index].card_id)


## 当前手牌的有效费用/攻击（手牌实例修正后，最低费用 0）。
func effective_hand_cost(side: String, hand_index: int) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return 0
	var instance: BattleCardInstance = state.hand[hand_index]
	var card: CardData = get_card(instance.card_id)
	if card == null:
		return 0
	var special_discount: int = 1 if (
		phase == PHASE_SPECIAL and state.special_offer_id == instance.instance_id
	) else 0
	return maxi(card.cost + instance.cost_delta - special_discount, 0)


func effective_hand_attack(side: String, hand_index: int) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return 0
	var instance: BattleCardInstance = state.hand[hand_index]
	var card: CardData = get_card(instance.card_id)
	if card == null:
		return 0
	return maxi(card.attack + instance.attack_bonus, 0)


## 给 UI 用的手牌显示卡：费用/攻击已应用手牌实例修正。
func hand_card_display(side: String, hand_index: int) -> CardData:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return null
	var base: CardData = get_card(state.hand[hand_index].card_id)
	if base == null:
		return null
	var display: CardData = base.copy_card()
	display.cost = effective_hand_cost(side, hand_index)
	if display.is_entity():
		display.attack = effective_hand_attack(side, hand_index)
	return display


func get_markers(side: String) -> Dictionary:
	var state: BattlePlayerState = players.get(side, null)
	return state.markers.duplicate() if state != null else {}


# ----- 起手 / 调度 -----

func replace_mulligan_card(side: String, hand_index: int) -> bool:
	if phase != PHASE_MULLIGAN:
		return false
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return false
	var instance: BattleCardInstance = state.hand[hand_index]
	state.hand.remove_at(hand_index)
	state.add_to_deck(instance)
	_shuffle_zones(state)
	if not state.deck.is_empty():
		_move_top_deck_to_hand(state)
	changed.emit()
	return true


func confirm_mulligan(side: String) -> void:
	if phase != PHASE_MULLIGAN:
		return
	mulligan_ready[side] = true
	if bool(mulligan_ready[SIDE_P]) and bool(mulligan_ready[SIDE_Z]):
		_begin_first_turn()


func _begin_first_turn() -> void:
	turn = 1
	_grant_energy(SIDE_P)
	_grant_energy(SIDE_Z)
	_resolve_turn_start()
	if winner != "":
		return
	phase = PHASE_HAND
	active_side = SIDE_Z
	_log("第 1 回合：z 阵营出牌阶段")
	changed.emit()


# ----- 回合 / 阶段 -----

func end_phase(side: String) -> void:
	if winner != "" or phase == PHASE_GAME_OVER:
		return
	if side != active_side:
		return
	if phase == PHASE_HAND or phase == PHASE_SPELL:
		advance_phase()


func advance_phase() -> void:
	if winner != "":
		return
	match phase:
		PHASE_HAND:
			if active_side == SIDE_Z:
				active_side = SIDE_P
				_log("p 阵营出牌阶段")
			else:
				phase = PHASE_SPELL
				active_side = SIDE_Z
				_log("z 阵营锦囊/环境阶段")
		PHASE_SPELL:
			phase = PHASE_COMBAT
			active_side = ""
			_log("对战回合：开始逐列结算")
			_resolve_combat()
			if winner == "" and not _special_pending_sides.is_empty():
				if _maybe_begin_special_turn(PHASE_TURN_END):
					return
			if winner == "":
				phase = PHASE_TURN_END
				_log("回合结束效果结算")
				_resolve_turn_end()
			_clear_hero_shields()
			if winner == "" and not _special_pending_sides.is_empty():
				if _maybe_begin_special_turn(PHASE_TURN_END, true):
					return
			if winner == "":
				_start_next_turn()
		_:
			pass
	changed.emit()


func _clear_hero_shields() -> void:
	for side: String in [SIDE_P, SIDE_Z]:
		var state: BattlePlayerState = players.get(side, null)
		if state != null:
			state.hero_shield = 0


func _start_next_turn() -> void:
	turn += 1
	_grant_energy(SIDE_P)
	_grant_energy(SIDE_Z)
	_resolve_turn_start()
	if winner != "":
		return
	# 第一回合不触发；从第二回合起，在回合开始效果全部结算后、z 出牌阶段前抽牌。
	for side: String in [SIDE_P, SIDE_Z]:
		var draw_count: int = mode.turn_draw_for_faction(side)
		if draw_count > 0:
			draw_cards(side, draw_count)
	phase = PHASE_HAND
	active_side = SIDE_Z
	_log("第 %d 回合：z 阵营出牌阶段" % turn)
	changed.emit()


func _grant_energy(side: String) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return
	var amount: int = mode.initial_energy_for_faction(side) + turn - 1
	state.energy = mini(amount, mode.energy_cap)


# ----- 抽牌 -----

## 返回实际抽到的张数；达到手牌上限或牌库为空时停止。
func draw_cards(side: String, count: int) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or count <= 0:
		return 0
	var drawn: int = 0
	for _index: int in range(count):
		if state.hand.size() >= mode.hand_limit:
			_log("%s 手牌已满（%d），取消抽牌" % [side.to_upper(), mode.hand_limit])
			break
		if state.deck.is_empty():
			_log("%s 牌库已空，无法抽牌" % side.to_upper())
			break
		_move_top_deck_to_hand(state)
		drawn += 1
	return drawn


# ----- 出牌 -----

func valid_slots(side: String, card: CardData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if card == null:
		return result
	var comes_with_team_up: bool = card.has_keyword("team_up")
	for column: int in range(COLUMN_COUNT):
		var existing: Array[BattleEntity] = []
		for entity: BattleEntity in entities:
			if entity.alive and entity.column == column and entity.side == side:
				existing.append(entity)
		if existing.size() >= 2:
			continue
		# 第二张实体需要至少一方有“组队”
		if existing.size() == 1 and not existing[0].team_up and not comes_with_team_up:
			continue
		for candidate_slot: int in [SLOT_NORMAL, SLOT_TEAM_UP]:
			var occupant: BattleEntity = _entity_at(column, side, candidate_slot)
			if occupant == null:
				result.append({"column": column, "slot": candidate_slot})
			elif comes_with_team_up and occupant.side == side:
				# 组队实体可以点已有友方实体所在的格子；该实体被挪到本列另一空格。
				var other_slot: int = SLOT_NORMAL if candidate_slot == SLOT_TEAM_UP else SLOT_TEAM_UP
				if _entity_at(column, side, other_slot) == null:
					result.append({
						"column": column,
						"slot": candidate_slot,
						"displace": occupant.entity_id,
					})
	return result


func card_needs_target(card: CardData) -> bool:
	if card == null or card.ability.is_empty():
		return false
	return card.ability.find("chosen") != -1


func target_mode_for(card: CardData) -> String:
	if card == null or card.ability_script == null:
		return ""
	var program: Dictionary = card.ability_script.to_program()
	return _first_target_mode(program.get("on_play", []))


func _first_target_mode(statements: Array) -> String:
	for raw_statement: Variant in statements:
		if not raw_statement is Dictionary:
			continue
		var statement: Dictionary = raw_statement
		var statement_type: String = str(statement.get("type", ""))
		if statement_type == "call":
			var primitive_name: String = str(statement.get("name", ""))
			if primitive_name == "deal_damage" or primitive_name == "destroy":
				return "enemy"
			if primitive_name == "heal" or primitive_name == "gain_shield":
				return "ally"
			if primitive_name == "buff_stats" or primitive_name == "give_keyword":
				return "ally"
		elif statement_type == "if":
			var found: String = _first_target_mode(statement.get("body", []))
			if not found.is_empty():
				return found
			found = _first_target_mode(statement.get("else", []))
			if not found.is_empty():
				return found
		elif statement_type == "repeat":
			var repeated: String = _first_target_mode(statement.get("body", []))
			if not repeated.is_empty():
				return repeated
	return ""


func target_candidates(card: CardData, caster_side: String) -> Array:
	var target_mode: String = target_mode_for(card)
	if target_mode.is_empty():
		target_mode = "enemy"
	var target_side: String = caster_side if target_mode == "ally" else opposite_side(caster_side)
	var handles: Array = []
	for entity: BattleEntity in entities:
		if entity.is_alive() and entity.side == target_side:
			handles.append(entity)
	handles.append(hero_handle(target_side))
	return handles


## 多目标锦囊 choose(count, selector) 的候选实体。
func choose_candidates(selector: String, caster_side: String) -> Array:
	var wanted_side: String = caster_side
	match selector:
		"all_enemies", "random_enemy":
			wanted_side = opposite_side(caster_side)
		"all_allies", "other_allies", "random_ally":
			wanted_side = caster_side
		_:
			return []
	var handles: Array = []
	for entity: BattleEntity in entities:
		if entity.is_alive() and entity.side == wanted_side:
			handles.append(entity)
	return handles


func play_card(side: String, hand_index: int, target: Dictionary = {}) -> Dictionary:
	_begin_effect_resolution()
	if winner != "":
		return _fail("对局已结束。")
	if active_side != side or (phase != PHASE_HAND and phase != PHASE_SPELL):
		return _fail("当前不是你的出牌阶段。")
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return _fail("手牌索引无效。")
	var instance: BattleCardInstance = state.hand[hand_index]
	var card: CardData = get_card(instance.card_id)
	if card == null:
		return _fail("卡牌不存在。")
	var effective_cost: int = maxi(card.cost + instance.cost_delta, 0)
	if effective_cost > state.energy:
		return _fail("费用不足（需要 %d，当前 %d）。" % [effective_cost, state.energy])
	if phase == PHASE_SPELL and not (card.is_spell() or card.is_environment()):
		return _fail("锦囊/环境阶段只能打出锦囊牌或环境牌。")
	var target_handles: Array = _target_handles(target)
	if card.is_entity():
		if phase != PHASE_HAND:
			return _fail("实体牌只能在出牌阶段打出。")
		var column: int = int(target.get("column", -1))
		var slot: int = int(target.get("slot", -1))
		var valid: bool = false
		for slot_info: Dictionary in valid_slots(side, card):
			if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
				valid = true
				break
		if not valid:
			return _fail("该位置不能放置这张实体。")
		# 组队实体放到已有友方实体所在格：把原实体移到本列另一空格（不触发位置变动事件）。
		var occupant: BattleEntity = _entity_at(column, side, slot)
		if occupant != null:
			if not card.has_keyword("team_up"):
				return _fail("只有组队实体可以占用已有友方实体的格子。")
			var other_slot: int = SLOT_NORMAL if slot == SLOT_TEAM_UP else SLOT_TEAM_UP
			if _entity_at(column, side, other_slot) != null:
				return _fail("这一列已经满员。")
			occupant.slot = other_slot
			_log("%s 被移动到第 %d 列%s位" % [
				occupant.display_name(), column + 1,
				"组队" if other_slot == SLOT_TEAM_UP else "普通",
			])
		_spend_and_remove(state, hand_index, card, effective_cost)
		var entity: BattleEntity = summon_card(
			side, card, column, slot, instance.attack_bonus
		)
		entity.apply_instance_keywords(instance)
		_fire_event("enter", entity, target_handles)
	elif card.is_environment():
		var column: int = int(target.get("column", -1))
		if column < 0 or column >= COLUMN_COUNT:
			return _fail("请选择一列。")
		_spend_and_remove(state, hand_index, card, effective_cost)
		environments[column] = card.english_name.to_lower().replace(" ", "_")
		environment_labels[column] = card.display_name()
		_log("第 %d 列环境变为：%s" % [column + 1, card.display_name()])
		if card.ability_script != null and card.ability_script.has_effect():
			_run_script(card, side, [])
	else:
		var chosen: Array = target_handles
		var requirement: Dictionary = {}
		if card.ability_script != null:
			requirement = card.ability_script.target_requirement()
		var choose_count: int = int(requirement.get("count", 0))
		if choose_count > 0:
			if chosen.size() > choose_count:
				return _fail("最多选择 %d 个目标。" % choose_count)
			var choose_selector: String = str(requirement.get("selector", ""))
			var choose_pool: Array = choose_candidates(choose_selector, side)
			for handle: Variant in chosen:
				if not choose_pool.has(handle):
					return _fail("目标无效。")
		elif card_needs_target(card):
			if chosen.is_empty():
				return _fail("这张牌需要选择目标。")
			var candidates: Array = target_candidates(card, side)
			for handle: Variant in chosen:
				if not candidates.has(handle):
					return _fail("目标无效。")
		_spend_and_remove(state, hand_index, card, effective_cost)
		_run_script(card, side, chosen)
	_flush_deaths()
	_check_game_over()
	changed.emit()
	if not _special_resolving and not _special_pending_sides.is_empty() and phase != PHASE_SPECIAL:
		_maybe_begin_special_turn(phase)
	_end_effect_resolution()
	return {"ok": true, "message": "已打出：%s" % card.display_name()}


func _target_handles(target: Dictionary) -> Array:
	var handles: Array = []
	var raw_handles: Variant = target.get("handles", null)
	if raw_handles is Array:
		for handle: Variant in raw_handles:
			if handle != null:
				handles.append(handle)
	elif raw_handles != null:
		handles.append(raw_handles)
	var single: Variant = target.get("handle", null)
	if single != null and not handles.has(single):
		handles.append(single)
	return handles


func _spend_and_remove(
	state: BattlePlayerState,
	hand_index: int,
	card: CardData,
	effective_cost: int = -1,
) -> void:
	var cost: int = card.cost if effective_cost < 0 else effective_cost
	state.energy = maxi(state.energy - cost, 0)
	var instance: BattleCardInstance = state.hand.pop_at(hand_index)
	if instance != null:
		instance.zone = "discard"
		state.discard.append(instance)


func _run_script(card: CardData, side: String, chosen: Variant) -> void:
	if card.ability_script == null or not card.ability_script.has_effect():
		return
	var context := BattleEffectContext.new(self, side)
	var chosen_handles: Array = []
	if chosen is Array:
		chosen_handles = chosen
	elif chosen != null:
		chosen_handles = [chosen]
	context.set_chosen_targets(chosen_handles)
	context.set_source_keywords(card.keywords)
	var errors: Array[String] = card.ability_script.run_on_play(context)
	for message: String in errors:
		_log("效果错误（%s）：%s" % [card.display_name(), message])


# ----- 场地 -----

func summon_card(side: String, card: CardData, column: int, slot: int, attack_bonus: int = 0) -> BattleEntity:
	var entity := BattleEntity.new()
	entity.entity_id = _next_entity_id
	_next_entity_id += 1
	entity.setup(card, side, column, slot)
	if attack_bonus != 0:
		entity.attack = maxi(entity.attack + attack_bonus, 0)
	entities.append(entity)
	_log("%s 在 %s 第 %d 列（%s位）召唤 %s" % [
		side.to_upper(), "z" if side == SIDE_Z else "p", column + 1,
		"组队" if slot == SLOT_TEAM_UP else "普通", card.display_name(),
	])
	return entity


func summon_card_by_name(side: String, card_name: String, count: int = 1) -> Array:
	var result: Array = []
	var card: CardData = get_card_by_english(card_name)
	if card == null or not card.is_entity():
		return result
	for _index: int in range(count):
		var slot_info: Dictionary = find_free_slot(side, card)
		if slot_info.is_empty():
			break
		var entity: BattleEntity = summon_card(
			side, card, int(slot_info.get("column", 0)), int(slot_info.get("slot", SLOT_NORMAL))
		)
		_fire_event("enter", entity)
		result.append(entity)
	return result


func find_free_slot(side: String, card: CardData, preferred_column: int = -1) -> Dictionary:
	var slots: Array[Dictionary] = valid_slots(side, card)
	for slot_info: Dictionary in slots:
		var column: int = int(slot_info.get("column", -1))
		if preferred_column < 0 or column == preferred_column:
			return slot_info
	return {}


## 位置移动（卡牌效果）：移动到空位；若目标列已有实体，需至少一方带“组队”。
## 成功后会触发 position_changed 事件；打出组队实体导致的位置挪动不会走这里。
func move_entity(entity: BattleEntity, column: int, slot: int, fire_event: bool = true) -> bool:
	if entity == null or not entity.alive:
		return false
	if column < 0 or column >= COLUMN_COUNT or (slot != SLOT_NORMAL and slot != SLOT_TEAM_UP):
		return false
	if entity.column == column and entity.slot == slot:
		return false
	if _entity_at(column, entity.side, slot) != null:
		return false
	var occupants: Array[BattleEntity] = []
	for other: BattleEntity in entities:
		if other == entity or not other.alive:
			continue
		if other.column == column and other.side == entity.side:
			occupants.append(other)
	if occupants.size() >= 2:
		return false
	if occupants.size() == 1 and not occupants[0].team_up and not entity.team_up:
		return false
	entity.column = column
	entity.slot = slot
	_log("%s 移动到第 %d 列%s位" % [
		entity.display_name(), column + 1,
		"组队" if slot == SLOT_TEAM_UP else "普通",
	])
	if fire_event:
		_fire_event("position_changed", entity)
	changed.emit()
	return true


func move_entity_handle(handle: Variant, column: int, slot: int) -> bool:
	if handle is BattleEntity:
		return move_entity(handle, column, slot)
	return false


## 服务器权威命令入口：所有客户端意图都应通过这里校验后执行。
func execute_command(side: String, command: Dictionary) -> Dictionary:
	var command_type: String = str(command.get("type", command.get("command", "")))
	match command_type:
		"play_card":
			var target: Dictionary = command.get("target", {})
			return play_card(side, int(command.get("hand_index", -1)), target)
		"end_phase":
			if active_side != side:
				return _fail("当前不是你的阶段。")
			end_phase(side)
			return {"ok": true, "message": "阶段结束。"}
		"mulligan_replace":
			if replace_mulligan_card(side, int(command.get("hand_index", -1))):
				return {"ok": true, "message": "已换牌。"}
			return _fail("换牌失败。")
		"mulligan_confirm":
			confirm_mulligan(side)
			return {"ok": true, "message": "已确认起手。"}
		"special_play":
			return special_resolve_play(side, command.get("target", {}))
		"special_hand":
			return special_resolve_hand(side)
		_:
			return _fail("未知命令：%s" % command_type)


func _entity_at(column: int, side: String, slot: int) -> BattleEntity:
	for entity: BattleEntity in entities:
		if entity.alive and entity.column == column and entity.side == side and entity.slot == slot:
			return entity
	return null


func alive_entities(column: int, side: String) -> Array[BattleEntity]:
	var result: Array[BattleEntity] = []
	for entity: BattleEntity in entities:
		if entity.alive and entity.column == column and entity.side == side:
			result.append(entity)
	result.sort_custom(func(first: BattleEntity, second: BattleEntity) -> bool:
		return first.slot < second.slot
	)
	return result


func hero_handle(side: String) -> String:
	return "hero:%s" % side


func side_of_handle(handle: Variant) -> String:
	if handle is BattleEntity:
		return handle.side
	if handle is String and handle.begins_with("hero:"):
		return handle.substr(5)
	return ""


# ----- 伤害 / 治疗 / 原语 -----

func damage_handle(handle: Variant, amount: int, source_keywords: Array = []) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		damage_entity(handle, amount, source_keywords)
	elif handle is String and handle.begins_with("hero:"):
		damage_hero(handle.substr(5), amount, source_keywords)


func damage_entity(entity: BattleEntity, amount: int, source_keywords: Array = []) -> void:
	if entity == null or not entity.alive:
		return
	var damage: int = amount
	if entity.has_keyword("armored"):
		damage = maxi(damage - 1, 0)
	var absorbed: int = mini(entity.shield, damage)
	entity.shield -= absorbed
	damage -= absorbed
	if damage > 0:
		entity.health -= damage
	if source_keywords.has("deadly"):
		entity.health = 0
	_log("%s 受到 %d 点伤害（生命 %d，护盾 %d）" % [entity.display_name(), amount, entity.health, entity.shield])
	if damage > 0 or source_keywords.has("deadly"):
		_fire_event("health_changed", entity)


func damage_hero(side: String, amount: int, source_keywords: Array = []) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or amount <= 0:
		return
	if state.hero_damage_immune:
		_log("%s 英雄免疫本次伤害（%d）" % [side.to_upper(), amount])
		return
	var damage: int = amount
	var absorbed: int = mini(state.hero_shield, damage)
	state.hero_shield -= absorbed
	damage -= absorbed
	if damage <= 0:
		_log("%s 英雄护盾吸收本次伤害（剩余护盾 %d）" % [side.to_upper(), state.hero_shield])
		return
	# 真实受击：先结算充能护盾，再决定是否免疫本次伤害。
	var is_bullseye: bool = source_keywords.has("bullseye")
	var lethal: bool = damage >= state.hero_health
	var charge_gain: int = 0
	if not is_bullseye:
		if lethal and state.charge_shield_emergency_uses > 0 and state.charge_shield_durability > 0:
			state.charge_shield_emergency_uses -= 1
			charge_gain = 3
			_log("%s 触发生命保护：本次受击无视数值，充能 +3" % side.to_upper())
		else:
			charge_gain = mode.charge_gain_for_damage(damage)
		var projected_charge: int = state.charge_shield + charge_gain
		state.charge_shield = projected_charge
		if projected_charge >= mode.charge_shield_max and state.charge_shield_durability > 0:
			state.charge_shield = 0
			state.charge_shield_durability -= 1
			_log("%s 充能护盾触发免疫（剩余耐久 %d）" % [side.to_upper(), state.charge_shield_durability])
			_trigger_superpower_offer(side)
			return
	state.hero_health -= damage
	hero_damaged.emit(side, damage, source_keywords.duplicate())
	_log("%s 英雄受到 %d 点伤害（生命 %d，护盾 %d）" % [
		side.to_upper(), damage, state.hero_health, state.hero_shield,
	])
	_check_game_over()


func heal_handle(handle: Variant, amount: int) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		var entity: BattleEntity = handle
		var before: int = entity.health
		entity.health = mini(entity.health + amount, entity.max_health)
		if entity.health != before:
			_fire_event("health_changed", entity)
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_health = mini(state.hero_health + amount, state.hero_max_health)


func gain_shield_handle(handle: Variant, amount: int) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		handle.shield += amount
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_shield += amount


func buff_handle(handle: Variant, attack_delta: int, health_delta: int) -> void:
	if not handle is BattleEntity:
		return
	var entity: BattleEntity = handle
	var old_attack: int = entity.attack
	var old_health: int = entity.health
	entity.attack = maxi(entity.attack + attack_delta, 0)
	entity.health += health_delta
	entity.max_health += maxi(health_delta, 0)
	var did_change_attack: bool = entity.attack != old_attack
	var did_change_health: bool = entity.health != old_health
	if did_change_attack:
		_fire_event("attack_changed", entity)
	if did_change_health:
		_fire_event("health_changed", entity)


func give_keyword_handle(handle: Variant, keyword: String, value: int = 0) -> bool:
	if handle is BattleEntity:
		return handle.add_keyword(keyword, value)
	return false


## 给手牌中的某张牌实例赋予词缀；同名牌的其他副本不受影响。
func give_keyword_to_hand_card(side: String, hand_index: int, keyword: String, value: int = 0) -> bool:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return false
	var instance: BattleCardInstance = state.hand[hand_index]
	var card: CardData = get_card(instance.card_id)
	if card == null:
		return false
	var normalized: String = CardKeywords.normalize(keyword)
	if not CardKeywords.has(normalized) or not CardKeywords.can_receive(normalized, card.kind):
		return false
	if not instance.keyword_values.has(normalized):
		instance.keyword_values[normalized] = 0
	if CardKeywords.has_value(normalized):
		instance.keyword_values[normalized] = int(instance.keyword_values[normalized]) + value
	return true


func destroy_handle(handle: Variant) -> void:
	if handle is BattleEntity:
		handle.health = 0
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_health = 0


func gain_energy(side: String, amount: int) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or amount <= 0:
		return
	state.energy = mini(state.energy + amount, state.energy_cap)


# ----- 事件 -----

func _begin_effect_resolution() -> void:
	_effect_resolution_count = 0
	_effect_limit_hit = false


func _end_effect_resolution() -> void:
	_effect_resolution_count = 0
	_effect_limit_hit = false


func _fire_event(event_name: String, event_entity: BattleEntity, chosen_targets: Array = []) -> void:
	if _effect_limit_hit:
		return
	_effect_resolution_count += 1
	if _effect_resolution_count > effect_resolution_limit:
		_effect_limit_hit = true
		_log("本次结算达到连锁上限（%d），强制结束后续连锁。" % effect_resolution_limit)
		return
	for listener: BattleEntity in entities.duplicate():
		if listener.card == null or listener.card.ability_script == null:
			continue
		if not listener.card.ability_script.has_effect():
			continue
		var context := BattleEffectContext.new(self, listener.side)
		context.set_self_target(listener)
		context.set_event_target(event_entity)
		context.set_source_keywords(listener.keywords)
		if not chosen_targets.is_empty():
			context.set_chosen_targets(chosen_targets)
		var errors: Array[String] = listener.card.ability_script.run_event(context, event_name, event_entity)
		for message: String in errors:
			_log("效果错误（%s）：%s" % [listener.display_name(), message])
		if event_name != "die":
			_emit_animation_cue("ability", listener, event_entity)
	if event_name != "die" and event_entity != null:
		_trigger_zone_effects(event_name, event_entity)


func _emit_animation_cue(trigger: String, actor: BattleEntity, target: Variant = null) -> void:
	if actor == null or actor.card == null or actor.card.animation_script == null:
		return
	if not actor.card.animation_script.has_trigger(trigger):
		return
	animation_cue.emit(trigger, actor, target)


# ----- 战斗 -----

func _resolve_combat() -> void:
	_begin_effect_resolution()
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			_end_effect_resolution()
			return
		_combat_column(column)
	_end_effect_resolution()


func _combat_column(column: int) -> void:
	var z_entities: Array[BattleEntity] = alive_entities(column, SIDE_Z)
	var p_entities: Array[BattleEntity] = alive_entities(column, SIDE_P)
	if z_entities.is_empty() and p_entities.is_empty():
		return
	var attacks: Array[Dictionary] = []
	for attacker: BattleEntity in z_entities:
		if p_entities.is_empty():
			attacks.append({"attacker": attacker, "target": hero_handle(SIDE_P)})
		else:
			attacks.append({"attacker": attacker, "target": p_entities[0]})
	for attacker: BattleEntity in p_entities:
		if z_entities.is_empty():
			attacks.append({"attacker": attacker, "target": hero_handle(SIDE_Z)})
		else:
			attacks.append({"attacker": attacker, "target": z_entities[0]})
	for attack: Dictionary in attacks:
		var attacker: BattleEntity = attack["attacker"]
		var target: Variant = attack["target"]
		if not attacker.alive:
			continue
		# 先攻：先对敌方英雄造成词缀数值的伤害，再执行正常攻击。
		var first_strike: int = attacker.keyword_value("first_strike")
		if first_strike > 0:
			damage_hero(opposite_side(attacker.side), first_strike, attacker.keywords)
			if winner != "":
				break
		if target is BattleEntity:
			damage_entity(target, attacker.attack, attacker.keywords)
		else:
			damage_hero(str(target).substr(5), attacker.attack, attacker.keywords)
	_flush_column_deaths(column)
	if winner != "":
		return
	for attack: Dictionary in attacks:
		if attack["attacker"] is BattleEntity and attack["attacker"].alive:
			_fire_event("attack", attack["attacker"])
		if attack["target"] is BattleEntity and attack["target"].alive:
			_fire_event("attacked", attack["target"])
	for attack: Dictionary in attacks:
		_emit_animation_cue("attack", attack["attacker"] as BattleEntity, attack["target"])


func _resolve_turn_start() -> void:
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			return
		for side: String in [SIDE_Z, SIDE_P]:
			for entity: BattleEntity in alive_entities(column, side).duplicate():
				_fire_event("turn_start", entity)
		_flush_column_deaths(column)
		if winner != "":
			return


func _resolve_turn_end() -> void:
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			return
		for side: String in [SIDE_Z, SIDE_P]:
			for entity: BattleEntity in alive_entities(column, side).duplicate():
				_fire_event("turn_end", entity)
		_flush_column_deaths(column)


func _flush_deaths() -> void:
	for _guard: int in range(10):
		var dead: Array[BattleEntity] = []
		for entity: BattleEntity in entities:
			if entity.alive and entity.health < 1:
				dead.append(entity)
		if dead.is_empty():
			break
		for entity: BattleEntity in dead:
			entity.alive = false
			_log("%s 死亡" % entity.display_name())
			_emit_animation_cue("die", entity, null)
			_fire_event("die", entity)
			_trigger_zone_ally_death(entity)
			entities.erase(entity)
	_check_game_over()


func _flush_column_deaths(column: int) -> void:
	for _guard: int in range(10):
		var dead: Array[BattleEntity] = []
		for entity: BattleEntity in entities:
			if entity.alive and entity.column == column and entity.health < 1:
				dead.append(entity)
		if dead.is_empty():
			break
		for entity: BattleEntity in dead:
			entity.alive = false
			_log("%s 死亡" % entity.display_name())
			_emit_animation_cue("die", entity, null)
			_fire_event("die", entity)
			_trigger_zone_ally_death(entity)
			entities.erase(entity)
	_check_game_over()


func _check_game_over() -> void:
	if winner != "":
		return
	var p_state: BattlePlayerState = players.get(SIDE_P, null)
	var z_state: BattlePlayerState = players.get(SIDE_Z, null)
	if p_state != null and p_state.hero_health <= 0:
		_set_winner(SIDE_Z)
	elif z_state != null and z_state.hero_health <= 0:
		_set_winner(SIDE_P)


func _set_winner(side: String) -> void:
	if winner != "":
		return
	winner = side
	phase = PHASE_GAME_OVER
	active_side = ""
	_log("%s 阵营获胜！" % side.to_upper())
	if not _emitting_game_over:
		_emitting_game_over = true
		game_finished.emit(side)


## 投降：立即判该阵营失败。
func surrender(side: String) -> void:
	if winner != "" or not players.has(side):
		return
	_set_winner(opposite_side(side))
	changed.emit()


func _trigger_zone_effects(event_name: String, event_entity: BattleEntity) -> void:
	if event_entity == null:
		return
	var state: BattlePlayerState = players.get(event_entity.side, null)
	if state == null:
		return
	for zone: String in ["hand", "deck"]:
		var instances: Array[BattleCardInstance] = state.hand if zone == "hand" else state.deck
		for instance: BattleCardInstance in instances:
			var card: CardData = get_card(instance.card_id)
			if card == null or card.ability_script == null:
				continue
			if not card.ability_script.has_event(event_name):
				continue
			var context := ZoneCardEffectContext.new(self, event_entity.side, zone, instance)
			context.set_event_target(event_entity)
			var errors: Array[String] = card.ability_script.run_event(context, event_name, event_entity)
			for message: String in errors:
				_log("区域效果错误（%s·%s）：%s" % [card.display_name(), zone, message])


func _trigger_zone_ally_death(dead_entity: BattleEntity) -> void:
	var state: BattlePlayerState = players.get(dead_entity.side, null)
	if state == null:
		return
	for zone: String in ["hand", "deck"]:
		var instances: Array[BattleCardInstance] = state.hand if zone == "hand" else state.deck
		for instance: BattleCardInstance in instances:
			var card: CardData = get_card(instance.card_id)
			if card == null or card.ability_script == null:
				continue
			if not card.ability_script.has_event("ally_die"):
				continue
			var context := ZoneCardEffectContext.new(self, dead_entity.side, zone, instance)
			context.set_event_target(dead_entity)
			var errors: Array[String] = card.ability_script.run_event(context, "ally_die", dead_entity)
			for message: String in errors:
				_log("区域效果错误（%s·%s）：%s" % [card.display_name(), zone, message])


func _shuffle_zones(state: BattlePlayerState) -> void:
	for index: int in range(state.deck.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: BattleCardInstance = state.deck[index]
		state.deck[index] = state.deck[swap_index]
		state.deck[swap_index] = temp


func _move_top_deck_to_hand(state: BattlePlayerState) -> void:
	var instance: BattleCardInstance = state.take_top_deck()
	if instance == null:
		return
	state.add_to_hand(instance)


func _shuffle(cards: Array[String]) -> void:
	for index: int in range(cards.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: String = cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temp


func _log(message: String) -> void:
	log_entries.append(message)
	if log_entries.size() > 200:
		log_entries.pop_front()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

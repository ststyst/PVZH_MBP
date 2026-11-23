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
## 词缀新增/数值变化（实体或手牌实例），用于 UI 动画与图标刷新
signal keyword_changed(handle: Variant, keyword: String, old_value: int, new_value: int)
## 实体的 Buff/词缀/数值或手牌费用/数值变化，用于统一刷新卡面与图标
signal display_state_changed(handle: Variant)
## 弹射动画：hide_identity 为 true 时不广播实体具体信息
signal bounce_fx(actor: BattleEntity, target: BattleEntity, hide_identity: bool)
## 墓碑离场费用广播（不包含实体具体信息）
signal tombstone_cost_broadcast(side: String, amount: int)

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
## 当前环境牌与所属阵营：column -> card_id / side
var environment_cards: Dictionary = {}
var environment_owners: Dictionary = {}
## 不能被环境牌覆盖的环境 id
var protected_environments: Array[String] = ["highground", "water"]
## 环境 id -> 实体词缀限制表达式
var environment_keyword_filters: Dictionary = {"water": "amphibious"}

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
## 本次战斗轮中已经触发过先攻的实体 id，保证整轮只触发一次
var _first_strike_used_this_round: Dictionary = {}


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
	environment_cards.clear()
	environment_owners.clear()
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
	for column: int in range(COLUMN_COUNT):
		environment_owners[column] = ""
	var enemy_side: String = opposite_side(player_side)
	players[player_side] = _create_player(player_side, player_hero, player_deck)
	players[enemy_side] = _create_player(enemy_side, enemy_hero, enemy_deck)
	for side: String in [SIDE_P, SIDE_Z]:
		var initial_draw: int = mode.initial_draw_for_faction(side)
		draw_cards(side, initial_draw)
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


## 从卡牌数据库筛选卡牌，随机插入牌库或手牌的随机位置。
func put_random_card_on_deck_top(side: String, filter_text: String) -> bool:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or card_database == null:
		return false
	var filter := CardFilter.new()
	if not filter.parse(filter_text):
		return false
	var matches: Array[String] = []
	for card_id: String in card_database.all_card_ids():
		if filter.matches(get_card(card_id)):
			matches.append(card_id)
	if matches.is_empty():
		return false
	var instance: BattleCardInstance = _new_card_instance(matches[rng.randi_range(0, matches.size() - 1)], side, "deck")
	state.deck.insert(0, instance)
	changed.emit()
	return true


func shuffle_buried_positions(side: String) -> bool:
	var buried: Array[BattleEntity] = []
	for entity: BattleEntity in entities:
		if entity.alive and entity.side == side and entity.has_buff("buried"):
			buried.append(entity)
	if buried.size() < 2:
		return false
	var positions: Array[Vector2i] = []
	for entity: BattleEntity in buried:
		positions.append(Vector2i(entity.column, entity.slot))
	for index: int in range(positions.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: Vector2i = positions[index]
		positions[index] = positions[swap_index]
		positions[swap_index] = temp
	for index: int in range(buried.size()):
		buried[index].column = positions[index].x
		buried[index].slot = positions[index].y
	changed.emit()
	return true


func put_hand_card_on_deck_top(side: String, filter_text: String) -> bool:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return false
	var filter := CardFilter.new()
	if not filter.parse(filter_text):
		return false
	for index: int in range(state.hand.size()):
		var card: CardData = get_card(state.hand[index].card_id)
		if filter.matches(card):
			var instance: BattleCardInstance = state.hand[index]
			state.hand.remove_at(index)
			instance.zone = "deck"
			state.deck.insert(0, instance)
			changed.emit()
			return true
	return false


func add_random_cards(side: String, zone: String, count: int, filter_text: String, cost_delta: int = 0) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or count <= 0 or card_database == null:
		return 0
	var filter := CardFilter.new()
	if not filter.parse(filter_text):
		_log("随机塞牌筛选条件错误：%s" % "；".join(filter.errors))
		return 0
	var pool: Array[String] = []
	for card_id: String in card_database.all_card_ids():
		var card: CardData = get_card(card_id)
		if filter.matches(card):
			pool.append(card_id)
	if pool.is_empty():
		_log("随机塞牌没有符合条件的卡牌。")
		return 0
	var added: int = 0
	for _index: int in range(count):
		if zone == "hand" and state.hand.size() >= mode.hand_limit:
			_log("%s 手牌已满，停止塞入。" % side.to_upper())
			break
		var card_id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var instance: BattleCardInstance = _new_card_instance(card_id, side, zone)
		instance.cost_delta += cost_delta
		if zone == "hand":
			state.hand.insert(rng.randi_range(0, state.hand.size()), instance)
		else:
			state.deck.insert(rng.randi_range(0, state.deck.size()), instance)
		added += 1
	if added > 0:
		_log("%s 随机塞入 %d 张卡牌到%s。" % [
			side.to_upper(), added, "手牌" if zone == "hand" else "牌库",
		])
		changed.emit()
	return added


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
		side.to_upper(),
		get_card(instance.card_id).display_name() if get_card(instance.card_id) != null else instance.card_id,
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
	var spell_aura: int = _aura_spell_cost_delta(side, card) if card.is_spell() else 0
	return maxi(card.cost + instance.cost_delta + spell_aura + _aura_hand_cost_delta(side, instance) - special_discount, 0)


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
		var replacement: BattleCardInstance = state.hand.pop_back()
		state.hand.insert(hand_index, replacement)
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
	# 起手调度全部完成、四张起手牌已经确定后，才发放随机超能力。
	_grant_initial_superpowers()
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
	if _battle_over():
		return
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
				_reveal_tombstones()
				if winner != "":
					return
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
func draw_cards(side: String, count: int, cost_delta: int = 0) -> int:
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
		var instance: BattleCardInstance = state.deck.back()
		_move_top_deck_to_hand(state)
		if instance != null:
			instance.cost_delta += cost_delta
		drawn += 1
	return drawn


# ----- 出牌 -----

func valid_slots(side: String, card: CardData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if card == null:
		return result
	var comes_with_team_up: bool = card.has_keyword("team_up")
	var can_evolve: bool = card.ability_script != null and card.ability_script.is_evolve_ability
	var card_is_base: bool = card.ability_script != null and card.ability_script.is_base_ability
	for column: int in range(COLUMN_COUNT):
		var environment_allowed: bool = _keywords_allowed_in_column(card.keywords, column)
		var existing: Array[BattleEntity] = []
		for entity: BattleEntity in entities:
			if entity.alive and entity.column == column and entity.side == side:
				existing.append(entity)
		for candidate_slot: int in [SLOT_NORMAL, SLOT_TEAM_UP]:
			var occupant: BattleEntity = _entity_at(column, side, candidate_slot)
			if occupant == null:
				if not environment_allowed:
					continue
				if existing.size() == 1 and not existing[0].team_up and not comes_with_team_up:
					continue
				result.append({"column": column, "slot": candidate_slot})
			elif occupant != null and occupant.side == side:
				# 进化/底座对“已有友方实体”的优先级高于环境词缀限制。
				if can_evolve:
					result.append({
						"column": column,
						"slot": candidate_slot,
						"evolve": occupant.entity_id,
					})
				elif not card_is_base and _is_base_entity(occupant):
					result.append({
						"column": column,
						"slot": candidate_slot,
						"mount": occupant.entity_id,
					})
				elif environment_allowed and (comes_with_team_up or occupant.team_up):
					var other_slot: int = SLOT_NORMAL if candidate_slot == SLOT_TEAM_UP else SLOT_TEAM_UP
					if _entity_at(column, side, other_slot) == null:
						result.append({
							"column": column,
							"slot": candidate_slot,
							"displace": occupant.entity_id,
						})
	return result


func _is_base_entity(entity: BattleEntity) -> bool:
	return (
		entity != null
		and entity.card != null
		and entity.card.ability_script != null
		and entity.card.ability_script.is_base_ability
	)


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
		if not entity.is_alive() or entity.side != target_side:
			continue
		if card != null and card.is_spell() and entity.is_spell_immune():
			continue
		handles.append(entity)
	handles.append(hero_handle(target_side))
	return handles


## 多目标锦囊 choose(count, selector) 的候选实体。
func choose_candidates(selector: String, caster_side: String, exclude_spell_immune: bool = false) -> Array:
	var wanted_side: String = caster_side
	var include_hero: bool = false
	match selector:
		"all_enemies", "random_enemy":
			wanted_side = opposite_side(caster_side)
		"all_allies", "other_allies", "random_ally":
			wanted_side = caster_side
		"enemy_hero_or_entities":
			wanted_side = opposite_side(caster_side)
			include_hero = true
		"all_allies_and_hero":
			wanted_side = caster_side
			include_hero = true
		"enemy_entities":
			wanted_side = opposite_side(caster_side)
		"frozen_enemies":
			wanted_side = opposite_side(caster_side)
		"injured_allies":
			wanted_side = caster_side
		"all_buried":
			var buried_candidates: Array = []
			for entity: BattleEntity in entities:
				if entity.is_alive() and entity.has_buff("buried"):
					buried_candidates.append(entity)
			return buried_candidates
		"all_heroes_and_entities":
			var everyone: Array = [hero_handle(SIDE_P), hero_handle(SIDE_Z)]
			for entity: BattleEntity in entities:
				if entity.is_alive():
					everyone.append(entity)
			return everyone
		_:
			return []
	var handles: Array = []
	if include_hero:
		handles.append(hero_handle(wanted_side))
	for entity: BattleEntity in entities:
		if not entity.is_alive() or entity.side != wanted_side:
			continue
		if exclude_spell_immune and entity.is_spell_immune():
			continue
		if selector == "frozen_enemies" and not entity.is_frozen():
			continue
		if selector == "injured_allies" and entity.health >= entity.max_health:
			continue
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
	var effective_cost: int = effective_hand_cost(side, hand_index)
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
		var evolved_from: BattleEntity = null
		var mounted_from: BattleEntity = null
		if occupant != null:
			var can_evolve: bool = card.ability_script != null and card.ability_script.is_evolve_ability
			var card_is_base: bool = card.ability_script != null and card.ability_script.is_base_ability
			if can_evolve:
				evolved_from = occupant
			elif not card_is_base and _is_base_entity(occupant):
				mounted_from = occupant
			elif not (card.has_keyword("team_up") or occupant.team_up):
				return _fail("这一列需要至少一个实体拥有组队词缀。")
			else:
				var other_slot: int = SLOT_NORMAL if slot == SLOT_TEAM_UP else SLOT_TEAM_UP
				if _entity_at(column, side, other_slot) != null:
					return _fail("这一列已经满员。")
				occupant.slot = other_slot
				_log("%s 被移动到第 %d 列%s位" % [
					occupant.display_name(), column + 1,
					"组队" if other_slot == SLOT_TEAM_UP else "普通",
				])
		_spend_and_remove(state, hand_index, card, effective_cost)
		if card.has_keyword("tombstone"):
			state.hidden_energy_spent += effective_cost
		if evolved_from != null:
			var evolved_card: CardData = evolved_from.card
			remove_entity_handle(evolved_from)
			var evolved_entity: BattleEntity = summon_card(
				side, card, column, slot, instance.attack_bonus
			)
			evolved_entity.apply_instance_keywords(instance)
			_apply_instance_stats(evolved_entity, instance)
			if not evolved_entity.has_buff("buried"):
				_fire_event("enter", evolved_entity, target_handles)
			_apply_enter_keywords(evolved_entity)
			if evolved_card != null and card.ability_script != null:
				var filter := CardFilter.new()
				if filter.parse(card.ability_script.evolve_filter_text) and filter.matches(evolved_card):
					_fire_event("evolved", evolved_entity)
			return _finish_card_play(card)
		if mounted_from != null:
			var base_attack: int = mounted_from.attack
			var base_health: int = mounted_from.health
			var base_shield: int = mounted_from.shield
			var base_card: CardData = mounted_from.card
			var base_side: String = mounted_from.side
			var base_column: int = mounted_from.column
			remove_entity_handle(mounted_from)
			var mounted_entity: BattleEntity = summon_card(
				side, card, column, slot, instance.attack_bonus
			)
			mounted_entity.attack += base_attack
			mounted_entity.max_health += base_health
			mounted_entity.health += base_health
			mounted_entity.shield += base_shield
			mounted_entity.apply_instance_keywords(instance)
			_apply_instance_stats(mounted_entity, instance)
			if not mounted_entity.has_buff("buried"):
				_fire_event("enter", mounted_entity, target_handles)
			_apply_enter_keywords(mounted_entity)
			if base_card != null and base_card.ability_script != null:
				var context := BaseEffectContext.new(self, base_side)
				context.set_self_target(mounted_from)
				context.set_event_target(mounted_entity)
				context.set_base_column(base_column)
				base_card.ability_script.run_event(context, "mounted", mounted_entity)
			return _finish_card_play(card)
		var entity: BattleEntity = summon_card(
			side, card, column, slot, instance.attack_bonus
		)
		entity.apply_instance_keywords(instance)
		_apply_instance_stats(entity, instance)
		if not entity.has_buff("buried"):
			_fire_event("enter", entity, target_handles)
		_apply_enter_keywords(entity)
	elif card.is_environment():
		var column: int = int(target.get("column", -1))
		if column < 0 or column >= COLUMN_COUNT:
			return _fail("请选择一列。")
		if not can_change_environment(column):
			return _fail("该列环境不可被覆盖。")
		_spend_and_remove(state, hand_index, card, effective_cost)
		_place_environment(side, column, card)
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
				if card.is_spell() and handle is BattleEntity and handle.is_spell_immune():
					return _fail("目标免疫锦囊。")
		elif card_needs_target(card):
			if chosen.is_empty():
				return _fail("这张牌需要选择目标。")
			var candidates: Array = target_candidates(card, side)
			for handle: Variant in chosen:
				if not candidates.has(handle):
					return _fail("目标无效。")
				if card.is_spell() and handle is BattleEntity and handle.is_spell_immune():
					return _fail("目标免疫锦囊。")
		if card.ability_script != null and card.ability_script.move_requires_position():
			if int(target.get("column", -1)) < 0 or int(target.get("slot", -1)) < 0:
				return _fail("这张牌需要选择移动位置。")
		if card.ability_script != null and card.ability_script.column_requirement():
			var chosen_column: int = int(target.get("column", -1))
			if chosen_column < 0 or chosen_column >= COLUMN_COUNT:
				return _fail("这张牌需要选择一列。")
		_spend_and_remove(state, hand_index, card, effective_cost)
		_run_script(card, side, chosen, target)
	_flush_deaths()
	_check_game_over()
	changed.emit()
	if not _special_resolving and not _special_pending_sides.is_empty() and phase != PHASE_SPECIAL:
		_maybe_begin_special_turn(phase)
	_end_effect_resolution()
	return {"ok": true, "message": "已打出：%s" % card.display_name()}


func can_change_environment(column: int) -> bool:
	if column < 0 or column >= COLUMN_COUNT:
		return false
	return not protected_environments.has(str(environments[column]))


func _place_environment(side: String, column: int, card: CardData) -> bool:
	if card == null or not card.is_environment() or not can_change_environment(column):
		return false
	environments[column] = card.english_name.to_lower().replace(" ", "_")
	environment_labels[column] = card.display_name()
	environment_cards[column] = card.card_id
	environment_owners[column] = side
	_log("第 %d 列环境变为：%s（%s）" % [column + 1, card.display_name(), side.to_upper()])
	if card.ability_script != null and card.ability_script.has_effect():
		_run_script(card, side, [], {"column": column})
	return true


func place_environment_by_name(side: String, column: int, card_name: String) -> bool:
	var card: CardData = get_card_by_english(card_name)
	if card == null or not card.is_environment():
		return false
	return _place_environment(side, column, card)


func _keywords_allowed_in_column(keywords: Array, column: int) -> bool:
	if column < 0 or column >= COLUMN_COUNT:
		return false
	var environment_id: String = str(environments[column])
	var filter_text: String = str(environment_keyword_filters.get(environment_id, ""))
	if filter_text.is_empty():
		return true
	var filter := KeywordFilter.new()
	if not filter.parse(filter_text):
		return false
	return filter.matches(keywords)


func _finish_card_play(card: CardData) -> Dictionary:
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
	_log("%s 打出 %s" % [state.side.to_upper(), card.display_name()])
	_fire_zone_event(state.side, "hand_played", null)


func _run_script(card: CardData, side: String, chosen: Variant, position: Dictionary = {}) -> void:
	if _battle_over():
		return
	if card.ability_script == null or not card.ability_script.has_effect():
		return
	var context := BattleEffectContext.new(self, side)
	context.set_source_name(card.display_name())
	context.set_chosen_position(int(position.get("column", -1)), int(position.get("slot", -1)))
	context.set_spell_source(card.is_spell())
	if int(position.get("column", -1)) >= 0:
		context.set_base_column(int(position.get("column", -1)))
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
	_apply_enter_keywords(entity)
	_refresh_all_counter_bonuses()
	_refresh_auras()
	return entity


func summon_card_by_name(side: String, card_name: String) -> Array:
	var result: Array = []
	var card: CardData = get_card_by_english(card_name)
	if card == null or not card.is_entity():
		return result
	var slot_info: Dictionary = find_free_slot(side, card)
	if slot_info.is_empty():
		return result
	var entity: BattleEntity = summon_card(
		side, card, int(slot_info.get("column", 0)), int(slot_info.get("slot", SLOT_NORMAL))
	)
	if not entity.has_buff("buried"):
		_fire_event("enter", entity)
	_apply_enter_keywords(entity)
	result.append(entity)
	return result


## 指定列是否还能召唤（召唤不会挤开已有实体）。
func can_summon_in_column(side: String, card: CardData, column: int) -> bool:
	if card == null or not card.is_entity() or column < 0 or column >= COLUMN_COUNT:
		return false
	if not _keywords_allowed_in_column(card.keywords, column):
		return false
	var occupants: Array[BattleEntity] = []
	for entity: BattleEntity in entities:
		if entity.alive and entity.side == side and entity.column == column:
			occupants.append(entity)
	if occupants.size() >= 2:
		return false
	if occupants.size() == 1:
		var other_slot: int = SLOT_NORMAL if occupants[0].slot == SLOT_TEAM_UP else SLOT_TEAM_UP
		if _entity_at(column, side, other_slot) != null:
			return false
		return card.has_keyword("team_up") or occupants[0].team_up
	return true


## 在指定列召唤一个实体；列已满或组队条件不满足时返回 null。
func summon_card_in_column(side: String, card: CardData, column: int) -> BattleEntity:
	if not can_summon_in_column(side, card, column):
		return null
	var slot: int = SLOT_NORMAL
	var occupants: Array[BattleEntity] = []
	for entity: BattleEntity in entities:
		if entity.alive and entity.side == side and entity.column == column:
			occupants.append(entity)
	if occupants.size() == 1:
		slot = SLOT_NORMAL if occupants[0].slot == SLOT_TEAM_UP else SLOT_TEAM_UP
	var summoned: BattleEntity = summon_card(side, card, column, slot)
	if not summoned.has_buff("buried"):
		_fire_event("enter", summoned)
	_apply_enter_keywords(summoned)
	return summoned


func summon_card_by_name_in_column(side: String, card_name: String, column: int) -> BattleEntity:
	var card: CardData = get_card_by_english(card_name)
	if card == null or not card.is_entity():
		return null
	return summon_card_in_column(side, card, column)


func find_free_slot(side: String, card: CardData, preferred_column: int = -1) -> Dictionary:
	var slots: Array[Dictionary] = valid_slots(side, card)
	for slot_info: Dictionary in slots:
		var column: int = int(slot_info.get("column", -1))
		if preferred_column < 0 or column == preferred_column:
			return slot_info
	return {}


## 移动实体时可选择的合法位置：只能在该实体所属阵营的半场，排除当前位置。
## 目标格已有同阵营实体时，只要移动实体或目标实体至少一个有组队，原实体就会被挤到同列另一格。
func valid_move_slots(entity: BattleEntity) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if entity == null or not entity.alive:
		return result
	var side: String = entity.side
	for column: int in range(COLUMN_COUNT):
		if not _keywords_allowed_in_column(entity.keywords, column):
			continue
		var others: Array[BattleEntity] = []
		for other: BattleEntity in entities:
			if other != entity and other.alive and other.column == column and other.side == side:
				others.append(other)
		for slot: int in [SLOT_NORMAL, SLOT_TEAM_UP]:
			if column == entity.column and slot == entity.slot:
				continue
			var occupant: BattleEntity = _entity_at(column, side, slot)
			if occupant == entity:
				occupant = null
			if occupant == null:
				if others.size() >= 2:
					continue
				if others.size() == 1 and not entity.team_up and not others[0].team_up:
					continue
				result.append({"column": column, "slot": slot})
			else:
				if not (entity.team_up or occupant.team_up):
					continue
				var other_slot: int = SLOT_NORMAL if slot == SLOT_TEAM_UP else SLOT_TEAM_UP
				var displaced_to: BattleEntity = _entity_at(column, side, other_slot)
				if displaced_to != null and displaced_to != entity:
					continue
				result.append({
					"column": column,
					"slot": slot,
					"displace": occupant.entity_id,
				})
	return result


## 位置移动（卡牌效果）：移动到空位；目标格已有同阵营实体时，该列至少一方需有“组队”。
## 成功后会触发 position_changed 事件；被挤开的实体不触发。
func move_entity(entity: BattleEntity, column: int, slot: int, fire_event: bool = true) -> bool:
	if entity == null or not entity.alive:
		return false
	var legal: Array[Dictionary] = valid_move_slots(entity)
	var found: bool = false
	for slot_info: Dictionary in legal:
		if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
			found = true
			break
	if not found:
		return false
	var occupant: BattleEntity = _entity_at(column, entity.side, slot)
	if occupant != null and occupant != entity:
		var other_slot: int = SLOT_NORMAL if slot == SLOT_TEAM_UP else SLOT_TEAM_UP
		occupant.slot = other_slot
		_log("%s 被移动到第 %d 列%s位" % [
			occupant.display_name(), column + 1,
			"组队" if other_slot == SLOT_TEAM_UP else "普通",
		])
	entity.column = column
	entity.slot = slot
	_log("%s 移动到第 %d 列%s位" % [
		entity.display_name(), column + 1,
		"组队" if slot == SLOT_TEAM_UP else "普通",
	])
	if fire_event:
		_fire_event("position_changed", entity)
	_refresh_all_counter_bonuses()
	_refresh_auras()
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

func remove_entity_handle(handle: Variant) -> bool:
	if not handle is BattleEntity:
		return false
	var entity: BattleEntity = handle
	if not entity.alive:
		return false
	entity.alive = false
	entity.buffs.clear()
	entity.buff_sources.clear()
	entities.erase(entity)
	_refresh_all_counter_bonuses()
	_refresh_auras()
	_log("%s 被移除（不触发死亡）" % entity.display_name())
	changed.emit()
	return true


func change_max_health_handle(handle: Variant, delta: int) -> void:
	if delta == 0:
		return
	if handle is BattleEntity:
		var entity: BattleEntity = handle
		if not entity.alive:
			return
		entity.max_health = maxi(entity.max_health + delta, 0)
		entity.health = mini(entity.health, entity.max_health)
		if entity.max_health < 1:
			if entity.has_buff("invincible"):
				entity.remove_buff("invincible")
			else:
				entity.health = 0
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state == null:
			return
		state.hero_max_health = maxi(state.hero_max_health + delta, 1)
		state.hero_health = mini(state.hero_health, state.hero_max_health)
	changed.emit()
	if handle is BattleEntity:
		display_state_changed.emit(handle)


func _battle_over() -> bool:
	return winner != ""


func damage_handle(handle: Variant, amount: int, source_keywords: Array = [], from_spell: bool = false, source_entity: BattleEntity = null, explicit_source: String = "") -> void:
	if _battle_over():
		return
	if amount <= 0:
		return
	if handle is BattleEntity:
		damage_entity(handle, amount, source_keywords, from_spell, source_entity, explicit_source)
	elif handle is String and handle.begins_with("hero:"):
		damage_hero(handle.substr(5), amount, source_keywords, source_entity, explicit_source if not explicit_source.is_empty() else ("锦囊" if from_spell else ""))


func damage_entity(entity: BattleEntity, amount: int, source_keywords: Array = [], from_spell: bool = false, source_entity: BattleEntity = null, explicit_source: String = "") -> void:
	if _battle_over():
		return
	if entity == null or not entity.alive:
		return
	if entity.has_buff("buried"):
		return
	if entity.is_invincible() or (from_spell and entity.is_spell_immune()):
		_log("%s 免疫本次伤害" % entity.display_name())
		return
	if entity.keyword_value("invisible") > 0 and not source_keywords.has("bullseye"):
		_log("%s 的隐形免疫了本次伤害" % entity.display_name())
		return
	var damage: int = amount
	if not source_keywords.has("bullseye"):
		damage = maxi(damage - entity.shield, 0)
	if damage > 0:
		entity.health -= damage
	if source_keywords.has("deadly") and damage > 0:
		entity.health = 0
	_log("%s 受到 %d 点伤害（来源：%s；生命 %d，护盾 %d）" % [
		entity.display_name(), amount,
		_damage_source_label(source_entity, source_keywords, from_spell) if explicit_source.is_empty() else explicit_source,
		entity.health, entity.shield,
	])
	if damage > 0 or source_keywords.has("deadly"):
		_fire_event("damaged", entity)
	if entity.has_buff("hatred") and source_entity != null and source_entity.alive and source_entity.side != entity.side:
		destroy_handle(source_entity)
	if damage > 0 or source_keywords.has("deadly"):
		_fire_event("health_changed", entity)
		display_state_changed.emit(entity)
	if source_keywords.has("frost") and damage > 0:
		apply_buff_handle(entity, "frozen", 1)


func apply_buff_handle(entity: BattleEntity, buff_id: String, amount: int = 1) -> bool:
	if entity == null or not entity.alive or not CardBuffs.has(buff_id):
		return false
	if buff_id == "bounce":
		return _apply_bounce(entity)
	var applied: bool = false
	for _index: int in range(maxi(amount, 1)):
		if entity.add_buff(buff_id):
			applied = true
	if applied:
		_log("%s 获得 %s" % [entity.display_name(), CardBuffs.label(buff_id)])
		display_state_changed.emit(entity)
		_fire_event("buff_applied", entity)
	return applied


func _apply_bounce(entity: BattleEntity) -> bool:
	if entity == null or not entity.alive:
		return false
	if entity.health < 1:
		_flush_deaths()
		return false
	var card_id: String = entity.card.card_id if entity.card != null else ""
	var side: String = entity.side
	var was_buried: bool = entity.has_buff("buried")
	if card_id.is_empty():
		return false
	bounce_fx.emit(null, entity, was_buried)
	if was_buried:
		tombstone_cost_broadcast.emit(side, entity.card.cost if entity.card != null else 0)
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return false
	remove_entity_handle(entity)
	var instance: BattleCardInstance = _new_card_instance(card_id, side, "hand")
	if state.hand.size() < mode.hand_limit:
		state.hand.append(instance)
	else:
		instance.zone = "deck"
		state.deck.insert(0, instance)
	_log("弹回：%s 返回%s" % [card_id, "手牌" if instance.zone == "hand" else "牌库顶"])
	changed.emit()
	return true


func remove_buff_handle(entity: BattleEntity, buff_id: String) -> bool:
	if entity == null or not entity.remove_buff(buff_id):
		return false
	_log("%s 解除 %s" % [entity.display_name(), CardBuffs.label(buff_id)])
	display_state_changed.emit(entity)
	_fire_event("buff_removed", entity)
	return true


func _clear_column_combat_buffs(column: int) -> void:
	for entity: BattleEntity in entities.duplicate():
		if entity.column != column or not entity.alive:
			continue
		for buff_id: Variant in entity.buffs.keys():
			if CardBuffs.clear_after_combat(str(buff_id)):
				remove_buff_handle(entity, str(buff_id))


func _apply_instance_stats(entity: BattleEntity, instance: BattleCardInstance) -> void:
	if entity == null or instance == null:
		return
	entity.max_health = maxi(entity.max_health + instance.health_bonus, 1)
	entity.health = clampi(entity.health + instance.health_bonus, 1, entity.max_health)
	entity.shield = maxi(entity.shield + instance.shield_bonus, 0)



func _apply_enter_keywords(entity: BattleEntity) -> void:
	if entity == null:
		return
	if entity.has_keyword("invincible") and not entity.has_buff("invincible"):
		apply_buff_handle(entity, "invincible", 1)
	_refresh_counter_bonus(entity)
	if entity.has_keyword("tombstone") and not entity.has_buff("buried"):
		apply_buff_handle(entity, "buried", 1)
		_fire_event("tombstone_enter", entity)


func _reveal_tombstones() -> void:
	var buried: Array[BattleEntity] = []
	for entity: BattleEntity in entities:
		if entity.alive and entity.has_buff("buried"):
			buried.append(entity)
	buried.sort_custom(func(a: BattleEntity, b: BattleEntity) -> bool: return a.column < b.column)
	for entity: BattleEntity in buried:
		if not entity.alive:
			continue
		remove_buff_handle(entity, "buried")
		if entity.has_buff("frozen_tombstone"):
			remove_buff_handle(entity, "frozen_tombstone")
			apply_buff_handle(entity, "frozen", 1)
		_fire_event("tombstone_reveal", entity)
		_fire_event("enter", entity)
	for side: String in [SIDE_P, SIDE_Z]:
		var state: BattlePlayerState = players.get(side, null)
		if state != null:
			state.hidden_energy_spent = 0
	_flush_deaths()
	changed.emit()


func visible_energy_for(side: String, viewer_side: String) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return 0
	if side == viewer_side:
		return state.energy
	return state.energy + state.hidden_energy_spent


func is_entity_visible_to(entity: BattleEntity, viewer_side: String) -> bool:
	if entity == null:
		return false
	return not (entity.has_buff("buried") and entity.side != viewer_side)


func public_entity_snapshot(viewer_side: String) -> Array:
	var result: Array = []
	for entity: BattleEntity in entities:
		if not entity.alive:
			continue
		if not is_entity_visible_to(entity, viewer_side):
			result.append({"entity_id": entity.entity_id, "hidden": true})
		else:
			result.append({
				"entity_id": entity.entity_id,
				"card_id": entity.card.card_id if entity.card != null else "",
				"side": entity.side,
				"column": entity.column,
				"slot": entity.slot,
				"attack": entity.attack,
				"health": entity.health,
				"max_health": entity.max_health,
				"shield": entity.shield,
				"hidden": false,
			})
	return result


func _trigger_hunt(entered: BattleEntity) -> void:
	if entered == null:
		return
	for hunter: BattleEntity in entities.duplicate():
		if hunter == entered or not hunter.alive or hunter.side == entered.side:
			continue
		if not hunter.has_keyword("hunt") or hunter.column == entered.column:
			continue
		for slot_info: Dictionary in valid_move_slots(hunter):
			if int(slot_info.get("column", -1)) == entered.column:
				move_entity(hunter, entered.column, int(slot_info.get("slot", SLOT_NORMAL)))
				break


func _refresh_all_counter_bonuses() -> void:
	for entity: BattleEntity in entities:
		_refresh_counter_bonus(entity)


func _refresh_auras() -> void:
	var desired: Dictionary = {}
	for source: BattleEntity in entities:
		if not source.alive or source.card == null or source.card.ability_script == null:
			continue
		for aura: Dictionary in source.card.ability_script.aura_buffs:
			var buff_id: String = str(aura.get("buff", ""))
			var min_column: int = source.column + int(aura.get("min_column", 0))
			var max_column: int = source.column + int(aura.get("max_column", 0))
			for target: BattleEntity in entities:
				if not target.alive:
					continue
				if target == source and bool(aura.get("exclude_self", false)):
					continue
				if target.column < min_column or target.column > max_column:
					continue
				if not _aura_target_matches(str(aura.get("selector", "ally")), source.side, target.side):
					continue
				var key: String = "%d:%s" % [target.entity_id, buff_id]
				var sources: Array = desired.get(key, [])
				sources.append(source.entity_id)
				desired[key] = sources
	for target: BattleEntity in entities:
		for buff_id: Variant in target.buff_sources.keys():
			var active_sources: Array = desired.get("%d:%s" % [target.entity_id, str(buff_id)], [])
			for source_id: Variant in (target.buff_sources[buff_id] as Array).duplicate():
				if not active_sources.has(int(source_id)):
					target.remove_buff_from_source(str(buff_id), int(source_id))
	for key: Variant in desired.keys():
		var parts: PackedStringArray = str(key).split(":")
		if parts.size() != 2:
			continue
		var target_id: int = int(parts[0])
		var buff_id: String = parts[1]
		var target: BattleEntity = _entity_by_id(target_id)
		if target == null:
			continue
		for source_id: Variant in desired[key]:
			target.add_buff_from_source(buff_id, int(source_id))
	for entity: BattleEntity in entities:
		display_state_changed.emit(entity)
	for side: String in [SIDE_P, SIDE_Z]:
		var state: BattlePlayerState = players.get(side, null)
		if state == null:
			continue
		for instance: BattleCardInstance in state.hand:
			display_state_changed.emit(instance)


func _aura_target_matches(selector: String, source_side: String, target_side: String) -> bool:
	match selector:
		"enemy":
			return target_side != source_side
		"all":
			return true
		"self":
			return target_side == source_side
		_:
			return target_side == source_side


func _entity_by_id(entity_id: int) -> BattleEntity:
	for entity: BattleEntity in entities:
		if entity.entity_id == entity_id:
			return entity
	return null


func _aura_spell_cost_delta(player_side: String, card: CardData) -> int:
	if card == null:
		return 0
	var delta_total: int = 0
	for source: BattleEntity in entities:
		if not source.alive or source.card == null or source.card.ability_script == null:
			continue
		for aura: Dictionary in source.card.ability_script.aura_spell_costs:
			var target_side: String = str(aura.get("side", "enemy"))
			var applies: bool = (
				(target_side == "enemy" and player_side != source.side)
				or (target_side == "self" and player_side == source.side)
				or target_side == "all"
			)
			if applies:
				delta_total += int(aura.get("delta", 0))
	return delta_total


func _aura_hand_cost_delta(player_side: String, instance: BattleCardInstance) -> int:
	var card: CardData = get_card(instance.card_id)
	if card == null:
		return 0
	var delta_total: int = 0
	for source: BattleEntity in entities:
		if not source.alive or source.card == null or source.card.ability_script == null:
			continue
		for aura: Dictionary in source.card.ability_script.aura_hand_costs:
			var target_side: String = str(aura.get("side", "self"))
			var applies: bool = (
				(target_side == "enemy" and player_side != source.side)
				or (target_side == "self" and player_side == source.side)
				or target_side == "all"
			)
			if not applies:
				continue
			var filter := CardFilter.new()
			if filter.parse(str(aura.get("filter", ""))) and filter.matches(card):
				delta_total += int(aura.get("delta", 0))
	return delta_total


func _refresh_counter_bonus(entity: BattleEntity) -> void:
	if entity == null or not entity.alive:
		return
	var value: int = entity.keyword_value("hero_counter")
	var has_enemy: bool = false
	for other: BattleEntity in entities:
		if other != entity and other.alive and other.column == entity.column and other.side != entity.side:
			has_enemy = true
			break
	var desired: int = value if (value > 0 and not has_enemy) else 0
	if entity.counter_bonus != desired:
		entity.attack = maxi(entity.attack - entity.counter_bonus + desired, 0)
		entity.counter_bonus = desired



func _damage_source_label(source_entity: BattleEntity, source_keywords: Array, from_spell: bool) -> String:
	if source_entity != null:
		return "%s（%s）" % [source_entity.display_name(), source_entity.side.to_upper()]
	if source_keywords.has("thorns"):
		return "反伤"
	if from_spell:
		return "锦囊"
	if source_keywords.has("frost"):
		return "寒霜"
	if source_keywords.has("overshoot"):
		return "溅射"
	return "未知来源"


func damage_hero(side: String, amount: int, source_keywords: Array = [], source_entity: BattleEntity = null, explicit_source: String = "") -> void:
	if _battle_over():
		return
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
		_log("%s 充能护盾获得 %d 点充能（%d/%d）" % [
			side.to_upper(), charge_gain, state.charge_shield, mode.charge_shield_max,
		])
		if projected_charge >= mode.charge_shield_max and state.charge_shield_durability > 0:
			state.charge_shield = 0
			state.charge_shield_durability -= 1
			_log("%s 充能护盾满充能，触发免伤（剩余耐久 %d）" % [side.to_upper(), state.charge_shield_durability])
			_trigger_superpower_offer(side)
			return
	state.hero_health -= damage
	_check_game_over()
	hero_damaged.emit(side, damage, source_keywords.duplicate())
	_log("%s 英雄受到 %d 点伤害（来源：%s；生命 %d，护盾 %d）" % [
		side.to_upper(), damage,
		explicit_source if not explicit_source.is_empty() else _damage_source_label(source_entity, source_keywords, false),
		state.hero_health, state.hero_shield,
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
			_fire_event("healed", entity)
			display_state_changed.emit(entity)
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_health = mini(state.hero_health + amount, state.hero_max_health)


func gain_shield_handle(handle: Variant, amount: int) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		handle.shield += amount
		display_state_changed.emit(handle)
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_shield += amount


func buff_handle(handle: Variant, attack_delta: int, health_delta: int) -> void:
	if handle is BattleCardInstance:
		var hand_instance: BattleCardInstance = handle
		var hand_card: CardData = get_card(hand_instance.card_id)
		if hand_card == null:
			return
		hand_instance.attack_bonus = maxi(hand_instance.attack_bonus + attack_delta, -hand_card.attack)
		hand_instance.health_bonus = maxi(hand_instance.health_bonus + health_delta, 1 - hand_card.health)
		changed.emit()
		display_state_changed.emit(hand_instance)
		return
	if not handle is BattleEntity:
		return
	var entity: BattleEntity = handle
	var old_attack: int = entity.attack
	var old_health: int = entity.health
	entity.attack = maxi(entity.attack + attack_delta, 0)
	if health_delta != 0:
		entity.max_health += health_delta
		entity.health = maxi(entity.health + health_delta, 0)
	var did_change_attack: bool = entity.attack != old_attack
	var did_change_health: bool = entity.health != old_health
	if did_change_attack:
		_fire_event("attack_changed", entity)
		_fire_zone_event(entity.side, "ally_attack_gained", entity)
	if did_change_health:
		_fire_event("health_changed", entity)
		if health_delta > 0:
			_fire_event("healed", entity)
	if entity.max_health < 1 or (health_delta < 0 and entity.health < 1):
		if entity.has_buff("invincible"):
			entity.remove_buff("invincible")
		entity.health = 0
	display_state_changed.emit(entity)


func keyword_value_for(handle: Variant, keyword: String) -> int:
	var normalized: String = CardKeywords.normalize(keyword)
	if handle is BattleEntity:
		return handle.keyword_value_for(normalized)
	if handle is BattleCardInstance:
		var instance: BattleCardInstance = handle
		var card: CardData = get_card(instance.card_id)
		if not CardKeywords.has_value(normalized):
			if instance.keyword_values.has(normalized):
				return 1
			return 1 if card != null and card.has_keyword(normalized) else 0
		var base_value: int = card.keyword_value(normalized) if card != null else 0
		return base_value + int(instance.keyword_values.get(normalized, 0))
	if handle is CardData:
		if not CardKeywords.has_value(normalized):
			return 1 if handle.has_keyword(normalized) else 0
		return handle.keyword_value(normalized)
	return 0


func has_keyword_for(handle: Variant, keyword: String) -> bool:
	return keyword_value_for(handle, keyword) > 0


## 最终展示数值：攻击/当前生命/生命上限/防御/当前费用。
func get_display_stats(handle: Variant) -> Dictionary:
	if handle is BattleEntity:
		return {
			"zone": "board",
			"side": handle.side,
			"attack": handle.attack,
			"health": handle.health,
			"max_health": handle.max_health,
			"shield": handle.shield,
			"cost": handle.card.cost if handle.card != null else 0,
		}
	if handle is BattleCardInstance:
		var instance: BattleCardInstance = handle
		var card: CardData = get_card(instance.card_id)
		if card == null:
			return {}
		var cost: int = card.cost + instance.cost_delta
		if instance.owner_side in players:
			var hand_index: int = _hand_index(instance.owner_side, instance)
			if hand_index >= 0:
				cost = effective_hand_cost(instance.owner_side, hand_index)
		return {
			"zone": instance.zone,
			"side": instance.owner_side,
			"attack": maxi(card.attack + instance.attack_bonus, 0),
			"health": maxi(card.health + instance.health_bonus, 1),
			"max_health": maxi(card.health + instance.health_bonus, 1),
			"shield": maxi(card.shield + instance.shield_bonus, 0),
			"cost": maxi(cost, 0),
		}
	if handle is CardData:
		return {
			"zone": "card",
			"side": "",
			"attack": handle.attack,
			"health": handle.health,
			"max_health": handle.health,
			"shield": handle.shield,
			"cost": handle.cost,
		}
	return {}


## 展示条目：在场实体返回关键词 + Buff/Debuff；手牌只返回关键词。
func get_display_entries(handle: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var keyword_ids: Array[String] = []
	if handle is BattleEntity:
		if handle.card != null:
			keyword_ids = handle.card.keywords.duplicate()
		for keyword: Variant in handle.keyword_values.keys():
			if not keyword_ids.has(str(keyword)):
				keyword_ids.append(str(keyword))
	else:
		var card: CardData = null
		var instance: BattleCardInstance = null
		if handle is BattleCardInstance:
			instance = handle
			card = get_card(instance.card_id)
		elif handle is CardData:
			card = handle
		if card != null:
			keyword_ids = card.keywords.duplicate()
			for keyword: Variant in card.keyword_values.keys():
				if not keyword_ids.has(str(keyword)):
					keyword_ids.append(str(keyword))
		if instance != null:
			for keyword: Variant in instance.keyword_values.keys():
				if not keyword_ids.has(str(keyword)):
					keyword_ids.append(str(keyword))
	for keyword: String in keyword_ids:
		var value: int = keyword_value_for(handle, keyword)
		if value <= 0:
			continue
		entries.append({
			"kind": "keyword",
			"id": keyword,
			"label": CardKeywords.label(keyword),
			"value": value,
		})
		seen["keyword:%s" % keyword] = true
	if handle is BattleEntity:
		for buff_id: Variant in handle.buffs.keys():
			var id: String = str(buff_id)
			if seen.has("buff:%s" % id):
				continue
			entries.append({
				"kind": "buff",
				"id": id,
				"label": CardBuffs.label(id),
				"value": int(handle.buffs[buff_id]),
				"buff_kind": CardBuffs.kind(id),
			})
	return entries


## 图标换图用的风格 id；Buff 与词缀一起参与判断。
func get_display_icon_styles(handle: Variant) -> Dictionary:
	var styles: Dictionary = {"attack": "normal", "health": "normal", "shield": "normal", "cost": "normal"}
	if handle is BattleEntity:
		if handle.has_buff("buried"):
			return {"attack": "buried", "health": "buried", "shield": "buried", "cost": "buried"}
		if handle.has_buff("invincible"):
			styles["attack"] = "invincible"
			styles["health"] = "invincible"
		if handle.has_buff("frozen"):
			styles["health"] = "frozen"
		if handle.has_buff("hatred"):
			styles["attack"] = "hatred"
	if has_keyword_for(handle, "deadly"):
		styles["attack"] = "deadly"
	elif has_keyword_for(handle, "invisible"):
		styles["attack"] = "invisible"
	elif has_keyword_for(handle, "triple_strike"):
		styles["attack"] = "triple"
	elif has_keyword_for(handle, "frenzy"):
		styles["attack"] = "frenzy"
	if has_keyword_for(handle, "amphibious"):
		styles["health"] = "amphibious"
	return styles


func notify_display_state_changed(handle: Variant) -> void:
	display_state_changed.emit(handle)


func _hand_index(side: String, instance: BattleCardInstance) -> int:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return -1
	for index: int in range(state.hand.size()):
		if state.hand[index] == instance:
			return index
	return -1


func give_keyword_handle(handle: Variant, keyword: String, value: int = 0) -> bool:
	if handle is BattleEntity:
		var old_value: int = handle.keyword_value_for(keyword)
		var applied: bool = handle.add_keyword(keyword, value)
		if applied:
			var new_value: int = handle.keyword_value_for(keyword)
			if new_value != old_value:
				keyword_changed.emit(handle, CardKeywords.normalize(keyword), old_value, new_value)
				display_state_changed.emit(handle)
		if applied and handle.has_keyword("tombstone") and not handle.has_buff("buried"):
			apply_buff_handle(handle, "buried", 1)
			_fire_event("tombstone_enter", handle)
		return applied
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
	var old_value: int = keyword_value_for(instance, normalized)
	if not instance.keyword_values.has(normalized):
		instance.keyword_values[normalized] = 0
	if CardKeywords.has_value(normalized):
		instance.keyword_values[normalized] = int(instance.keyword_values[normalized]) + value
	instance.keyword_changed.emit(normalized, old_value, keyword_value_for(instance, normalized))
	keyword_changed.emit(instance, normalized, old_value, keyword_value_for(instance, normalized))
	display_state_changed.emit(instance)
	return true


func destroy_handle(handle: Variant) -> void:
	if handle is BattleEntity:
		if handle.is_invincible() or handle.is_spell_immune():
			return
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
	if _battle_over():
		return
	if _effect_limit_hit:
		return
	_effect_resolution_count += 1
	if _effect_resolution_count > effect_resolution_limit:
		_effect_limit_hit = true
		_log("本次结算达到连锁上限（%d），强制结束后续连锁。" % effect_resolution_limit)
		return
	if event_name == "enter" and event_entity != null:
		_trigger_hunt(event_entity)
	for listener: BattleEntity in entities.duplicate():
		if listener.card == null or listener.card.ability_script == null:
			continue
		if listener.card.ability_script.in_hand_scope or listener.card.ability_script.in_deck_scope:
			continue
		if not listener.card.ability_script.has_effect():
			continue
		var context := BattleEffectContext.new(self, listener.side)
		context.set_self_target(listener)
		context.set_source_name(listener.card.display_name())
		context.set_event_target(event_entity)
		context.set_source_keywords(listener.keywords)
		context.set_base_column(listener.column)
		if not chosen_targets.is_empty():
			context.set_chosen_targets(chosen_targets)
		var errors: Array[String] = listener.card.ability_script.run_event(context, event_name, event_entity)
		for message: String in errors:
			_log("效果错误（%s）：%s" % [listener.display_name(), message])
		if event_name != "die":
			_emit_animation_cue("ability", listener, event_entity)
	if event_name != "die" and event_entity != null:
		_trigger_scoped_zone_effects(event_name, event_entity)
	if event_name != "turn_start" and event_name != "turn_end":
		_fire_environment_event(event_name, event_entity)
	_refresh_all_counter_bonuses()


func _fire_environment_event(event_name: String, event_entity: BattleEntity, only_column: int = -1) -> void:
	for column: int in range(COLUMN_COUNT):
		if only_column >= 0 and column != only_column:
			continue
		var card_id: String = str(environment_cards.get(column, ""))
		if card_id.is_empty():
			continue
		var card: CardData = get_card(card_id)
		if card == null or card.ability_script == null:
			continue
		if not card.ability_script.has_event(event_name):
			continue
		if event_entity != null and event_entity.column != column:
			continue
		var owner: String = str(environment_owners.get(column, ""))
		var context := EnvironmentEffectContext.new(self, owner, column)
		context.set_source_name(card.display_name())
		if event_entity != null:
			context.set_event_target(event_entity)
		var errors: Array[String] = card.ability_script.run_event(context, event_name, event_entity)
		for message: String in errors:
			_log("环境效果错误（第 %d 列）：%s" % [column + 1, message])


func _fire_environment_turn_event(column: int, event_name: String) -> void:
	_fire_environment_event(event_name, null, column)


func _emit_animation_cue(trigger: String, actor: BattleEntity, target: Variant = null) -> void:
	if actor == null or actor.card == null or actor.card.animation_script == null:
		return
	if not actor.card.animation_script.has_trigger(trigger):
		return
	animation_cue.emit(trigger, actor, target)


# ----- 战斗 -----

func _resolve_combat() -> void:
	_begin_effect_resolution()
	_first_strike_used_this_round.clear()
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			_end_effect_resolution()
			return
		_combat_column(column)
	_end_effect_resolution()


func _combat_column(column: int) -> void:
	var attackers: Array[BattleEntity] = []
	attackers.append_array(alive_entities(column, SIDE_Z))
	attackers.append_array(alive_entities(column, SIDE_P))
	# 先让整列的第一轮攻击都发生，再统一结算死亡；这样普通同列互击仍会同时出手。
	for attacker: BattleEntity in attackers:
		if winner != "":
			return
		if not attacker.alive or attacker.is_frozen() or attacker.attack < 1:
			continue
		_execute_attack_action(attacker, false)
	_flush_column_deaths(column)
	if winner != "":
		return
	# 双重打击：第一轮与死亡结算完成后仍存活，才进行第二次攻击。
	for attacker: BattleEntity in attackers:
		if winner != "":
			return
		if attacker.alive and attacker.has_keyword("double_strike") and not attacker.is_frozen() and attacker.attack >= 1:
			_execute_attack_action(attacker, false)
	_flush_column_deaths(column)
	if winner != "":
		return
	_clear_column_combat_buffs(column)


func _choose_attack_target(attacker: BattleEntity) -> Variant:
	return _choose_attack_target_in_column(attacker, attacker.column)


func _choose_attack_target_in_column(attacker: BattleEntity, column: int) -> Variant:
	for entity: BattleEntity in entities:
		if entity.is_alive() and entity.side != attacker.side and entity.column == column:
			return entity
	return hero_handle(opposite_side(attacker.side))


func _execute_attack_action(attacker: BattleEntity, extra_attack: bool) -> void:
	if _battle_over():
		return
	if attacker == null or not attacker.alive or attacker.is_frozen() or attacker.attack < 1:
		return
	var first_strike: int = attacker.keyword_value("first_strike")
	if first_strike > 0 and not _first_strike_used_this_round.has(attacker.entity_id):
		_first_strike_used_this_round[attacker.entity_id] = true
		damage_hero(opposite_side(attacker.side), first_strike, attacker.keywords, attacker)
		if winner != "":
			return
	if attacker.has_keyword("triple_strike"):
		var columns: Array[int] = [attacker.column - 1, attacker.column, attacker.column + 1]
		for index: int in range(columns.size()):
			var attack_column: int = columns[index]
			if attack_column < 0 or attack_column >= COLUMN_COUNT:
				continue
			if not attacker.alive or attacker.attack < 1 or winner != "":
				break
			_execute_entity_attack(
				attacker,
				_choose_attack_target_in_column(attacker, attack_column),
				0,
				extra_attack and index == 0,
				false,
				attack_column,
			)
		return
	_execute_entity_attack(
		attacker,
		_choose_attack_target(attacker),
		0,
		extra_attack,
		false,
		attacker.column,
	)


func force_entity_attack(attacker: BattleEntity) -> bool:
	if _battle_over() or attacker == null or not attacker.alive or attacker.is_frozen() or attacker.attack < 1:
		return false
	_execute_attack_action(attacker, true)
	_flush_column_deaths(attacker.column)
	_clear_column_combat_buffs(attacker.column)
	return true


func _execute_entity_attack(
	attacker: BattleEntity,
	target: Variant,
	frenzy_depth: int,
	extra_attack: bool = false,
	first_strike_enabled: bool = true,
	attack_column: int = -1,
) -> void:
	if _battle_over() or attacker == null or not attacker.alive or attacker.is_frozen() or attacker.attack < 1:
		return
	if attack_column < 0:
		attack_column = attacker.column
	if extra_attack:
		_fire_event("extra_attack", attacker)
	var first_strike: int = attacker.keyword_value("first_strike")
	if first_strike_enabled and first_strike > 0:
		damage_hero(opposite_side(attacker.side), first_strike, attacker.keywords, attacker)
		if winner != "":
			return
	var killed_enemy: bool = false
	if attacker.has_keyword("strikethrough"):
		for entity: BattleEntity in entities.duplicate():
			if entity.alive and entity.side != attacker.side and entity.column == attack_column:
				damage_entity(entity, attacker.attack, attacker.keywords, false, attacker)
				if entity.alive:
					_fire_event("attacked", entity)
				if not entity.alive or entity.health <= 0:
					killed_enemy = true
		damage_hero(opposite_side(attacker.side), attacker.attack, attacker.keywords, attacker)
		if _battle_over():
			return
	else:
		if target is BattleEntity:
			var target_entity: BattleEntity = target
			if target_entity.alive:
				damage_entity(target_entity, attacker.attack, attacker.keywords, false, attacker)
				if target_entity.health <= 0:
					killed_enemy = true
				_try_thorns(attacker, target_entity)
		elif target is String and target.begins_with("hero:"):
			damage_hero(target.substr(5), attacker.attack, attacker.keywords, attacker)
			if _battle_over():
				return
	var splash: int = attacker.keyword_value("overshoot")
	if splash > 0:
		for column_offset: int in [-1, 1]:
			var splash_column: int = attacker.column + column_offset
			if splash_column < 0 or splash_column >= COLUMN_COUNT:
				continue
			for entity: BattleEntity in entities.duplicate():
				if entity.alive and entity != attacker and entity.side != attacker.side and entity.column == splash_column:
					damage_entity(entity, splash, attacker.keywords, false, attacker)
	_fire_event("attack", attacker)
	if _battle_over():
		return
	if not attacker.has_keyword("strikethrough") and target is BattleEntity and target.alive:
		_fire_event("attacked", target)
	_emit_animation_cue("attack", attacker, target)
	if killed_enemy and attacker.alive and attacker.has_keyword("frenzy") and frenzy_depth < 8:
		_flush_column_deaths(attacker.column)
		if attacker.alive and not _battle_over():
			_execute_attack_action(attacker, true)
		_flush_column_deaths(attacker.column)


func _try_thorns(attacker: BattleEntity, target: BattleEntity) -> void:
	if target == null or not target.alive:
		return
	var thorns: int = target.keyword_value("thorns")
	if thorns <= 0:
		return
	if attacker == null or not attacker.alive or attacker.side == target.side:
		return
	damage_entity(attacker, thorns, ["thorns"], false, target)


func _resolve_turn_start() -> void:
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			return
		for side: String in [SIDE_Z, SIDE_P]:
			for entity: BattleEntity in alive_entities(column, side).duplicate():
				_fire_event("turn_start", entity)
		_fire_environment_turn_event(column, "turn_start")
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
		_fire_environment_turn_event(column, "turn_end")
		_flush_column_deaths(column)
	for entity: BattleEntity in entities:
		var invisible: int = entity.keyword_value("invisible")
		if invisible > 0:
			entity.set_keyword_value("invisible", invisible - 1)
			keyword_changed.emit(entity, "invisible", invisible, entity.keyword_value("invisible"))


func _flush_deaths() -> void:
	if _battle_over():
		return
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
			var repeat_count: int = _death_effect_repeat_count(entity)
			for _repeat: int in range(repeat_count):
				_fire_event("die", entity)
				_trigger_zone_ally_death(entity)
			entities.erase(entity)
	_refresh_all_counter_bonuses()
	_refresh_auras()
	_check_game_over()


func _death_effect_repeat_count(dead: BattleEntity) -> int:
	for source: BattleEntity in entities:
		if source == dead or not source.alive or source.side != dead.side:
			continue
		if source.card != null and source.card.ability_script != null and source.card.ability_script.doubles_death_effects:
			return 2
	return 1


func _flush_column_deaths(column: int) -> void:
	if _battle_over():
		return
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
			var repeat_count: int = _death_effect_repeat_count(entity)
			for _repeat: int in range(repeat_count):
				_fire_event("die", entity)
				_trigger_zone_ally_death(entity)
			entities.erase(entity)
	_refresh_all_counter_bonuses()
	_refresh_auras()
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


func _trigger_scoped_zone_effects(event_name: String, event_entity: BattleEntity) -> void:
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
			if zone == "hand" and not card.ability_script.in_hand_scope:
				continue
			if zone == "deck" and not card.ability_script.in_deck_scope:
				continue
			var context := ZoneCardEffectContext.new(self, event_entity.side, zone, instance)
			context.set_source_name(card.display_name())
			context.set_self_target(instance)
			context.set_event_target(event_entity)
			var errors: Array[String] = card.ability_script.run_event(context, event_name, event_entity)
			for message: String in errors:
				_log("区域效果错误（%s·%s）：%s" % [card.display_name(), zone, message])


func _fire_zone_event(side: String, event_name: String, event_handle) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null:
		return
	for zone: String in ["hand", "deck"]:
		var instances: Array[BattleCardInstance] = state.hand if zone == "hand" else state.deck
		for instance: BattleCardInstance in instances:
			var card: CardData = get_card(instance.card_id)
			if card == null or card.ability_script == null or not card.ability_script.has_event(event_name):
				continue
			if zone == "hand" and not card.ability_script.in_hand_scope:
				continue
			if zone == "deck" and not card.ability_script.in_deck_scope:
				continue
			var context := ZoneCardEffectContext.new(self, side, zone, instance)
			context.set_source_name(card.display_name())
			context.set_self_target(instance)
			context.set_event_target(event_handle)
			var errors: Array[String] = card.ability_script.run_event(context, event_name, event_handle)
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
			if zone == "hand" and not card.ability_script.in_hand_scope:
				continue
			if zone == "deck" and not card.ability_script.in_deck_scope:
				continue
			var context := ZoneCardEffectContext.new(self, dead_entity.side, zone, instance)
			context.set_source_name(card.display_name())
			context.set_self_target(instance)
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

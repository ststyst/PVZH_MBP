class_name BattleEngine
extends RefCounted
## 战斗核心（无 UI）：5 列 × 双方各 2 个位置；回合阶段、出牌、战斗结算、死亡与胜负。
## 效果通过 BattleEffectContext 执行（DSL 原语）。所有规则数值来自 GameModeConfig。

signal changed()
signal game_finished(winner_side: String)
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
const PHASE_GAME_OVER: String = "game_over"

const ENV_HIGHGROUND: String = "highground"
const ENV_DEFAULT: String = "default"
const ENV_WATER: String = "water"
const DEFAULT_ENVIRONMENTS: Array = ["highground", "default", "default", "default", "water"]
const DEFAULT_ENVIRONMENT_LABELS: Array = ["高地", "默认", "默认", "默认", "水池"]

var mode: GameModeConfig = null
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
var _emitting_game_over: bool = false


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
	state.deck = deck_ids.duplicate()
	_shuffle(state.deck)
	return state


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
	return get_card(state.hand[index])


# ----- 起手 / 调度 -----

func replace_mulligan_card(side: String, hand_index: int) -> bool:
	if phase != PHASE_MULLIGAN:
		return false
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return false
	var card_id: String = state.hand[hand_index]
	state.hand.remove_at(hand_index)
	state.deck.append(card_id)
	_shuffle(state.deck)
	if not state.deck.is_empty():
		state.hand.append(state.deck.pop_back())
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
			if winner == "":
				phase = PHASE_TURN_END
				_log("回合结束效果结算")
				_resolve_turn_end()
			if winner == "":
				_start_next_turn()
		_:
			pass
	changed.emit()


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
		state.hand.append(state.deck.pop_back())
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
		# 位置不固定：该列已有实体 + 新实体至少有一个带“组队”才能放入第二张
		if existing.size() == 1 and not existing[0].team_up and not comes_with_team_up:
			continue
		# 空列的两个空位都允许打出；已有 1 个实体时只剩余一个空位
		for candidate_slot: int in [SLOT_NORMAL, SLOT_TEAM_UP]:
			if _entity_at(column, side, candidate_slot) == null:
				result.append({"column": column, "slot": candidate_slot})
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


func play_card(side: String, hand_index: int, target: Dictionary = {}) -> Dictionary:
	if winner != "":
		return _fail("对局已结束。")
	if active_side != side or (phase != PHASE_HAND and phase != PHASE_SPELL):
		return _fail("当前不是你的出牌阶段。")
	var state: BattlePlayerState = players.get(side, null)
	if state == null or hand_index < 0 or hand_index >= state.hand.size():
		return _fail("手牌索引无效。")
	var card: CardData = get_card(state.hand[hand_index])
	if card == null:
		return _fail("卡牌不存在。")
	if card.cost > state.energy:
		return _fail("费用不足（需要 %d，当前 %d）。" % [card.cost, state.energy])
	if phase == PHASE_SPELL and not (card.is_spell() or card.is_environment()):
		return _fail("锦囊/环境阶段只能打出锦囊牌或环境牌。")
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
		_spend_and_remove(state, hand_index, card)
		var entity: BattleEntity = summon_card(side, card, column, slot)
		_fire_event("enter", entity)
	elif card.is_environment():
		var column: int = int(target.get("column", -1))
		if column < 0 or column >= COLUMN_COUNT:
			return _fail("请选择一列。")
		_spend_and_remove(state, hand_index, card)
		environments[column] = card.english_name.to_lower().replace(" ", "_")
		environment_labels[column] = card.display_name()
		_log("第 %d 列环境变为：%s" % [column + 1, card.display_name()])
		if card.ability_script != null and card.ability_script.has_effect():
			_run_script(card, side, null)
	else:
		var chosen: Variant = null
		if card_needs_target(card):
			chosen = target.get("handle", null)
			if chosen == null:
				return _fail("这张牌需要选择目标。")
			var candidates: Array = target_candidates(card, side)
			if not candidates.has(chosen):
				return _fail("目标无效。")
		_spend_and_remove(state, hand_index, card)
		_run_script(card, side, chosen)
	_flush_deaths()
	_check_game_over()
	changed.emit()
	return {"ok": true, "message": "已打出：%s" % card.display_name()}


func _spend_and_remove(state: BattlePlayerState, hand_index: int, card: CardData) -> void:
	state.energy = maxi(state.energy - card.cost, 0)
	state.hand.remove_at(hand_index)
	state.discard.append(card.card_id)


func _run_script(card: CardData, side: String, chosen: Variant) -> void:
	if card.ability_script == null or not card.ability_script.has_effect():
		return
	var context := BattleEffectContext.new(self, side)
	if chosen != null:
		context.set_chosen_target(chosen)
	var errors: Array[String] = card.ability_script.run_on_play(context)
	for message: String in errors:
		_log("效果错误（%s）：%s" % [card.display_name(), message])


# ----- 场地 -----

func summon_card(side: String, card: CardData, column: int, slot: int) -> BattleEntity:
	var entity := BattleEntity.new()
	entity.entity_id = _next_entity_id
	_next_entity_id += 1
	entity.setup(card, side, column, slot)
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


func swap_team_up(side: String, entity: BattleEntity) -> bool:
	if entity == null or not entity.alive or not entity.team_up:
		return false
	var other_slot: int = SLOT_NORMAL if entity.slot == SLOT_TEAM_UP else SLOT_TEAM_UP
	var other: BattleEntity = _entity_at(entity.column, side, other_slot)
	if other == null:
		return false
	var old_slot: int = entity.slot
	entity.slot = other_slot
	other.slot = old_slot
	_log("%s 与 %s 交换位置" % [entity.display_name(), other.display_name()])
	changed.emit()
	return true


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

func damage_handle(handle: Variant, amount: int) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		damage_entity(handle, amount, [])
	elif handle is String and handle.begins_with("hero:"):
		damage_hero(handle.substr(5), amount)


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


func damage_hero(side: String, amount: int) -> void:
	var state: BattlePlayerState = players.get(side, null)
	if state == null or amount <= 0:
		return
	state.hero_health -= amount
	_log("%s 英雄受到 %d 点伤害（生命 %d）" % [side.to_upper(), amount, state.hero_health])
	_check_game_over()


func heal_handle(handle: Variant, amount: int) -> void:
	if amount <= 0:
		return
	if handle is BattleEntity:
		var entity: BattleEntity = handle
		entity.health = mini(entity.health + amount, entity.max_health)
	elif handle is String and handle.begins_with("hero:"):
		var state: BattlePlayerState = players.get(handle.substr(5), null)
		if state != null:
			state.hero_health = mini(state.hero_health + amount, state.hero_max_health)


func gain_shield_handle(handle: Variant, amount: int) -> void:
	if handle is BattleEntity and amount > 0:
		handle.shield += amount


func buff_handle(handle: Variant, attack_delta: int, health_delta: int) -> void:
	if not handle is BattleEntity:
		return
	var entity: BattleEntity = handle
	entity.attack = maxi(entity.attack + attack_delta, 0)
	entity.health += health_delta
	entity.max_health += maxi(health_delta, 0)


func give_keyword_handle(handle: Variant, keyword: String) -> void:
	if not handle is BattleEntity:
		return
	var normalized: String = CardKeywords.normalize(keyword)
	if not handle.keywords.has(normalized):
		handle.keywords.append(normalized)


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

func _fire_event(event_name: String, event_entity: BattleEntity) -> void:
	for listener: BattleEntity in entities.duplicate():
		if listener.card == null or listener.card.ability_script == null:
			continue
		if not listener.card.ability_script.has_effect():
			continue
		var context := BattleEffectContext.new(self, listener.side)
		context.set_self_target(listener)
		context.set_event_target(event_entity)
		var errors: Array[String] = listener.card.ability_script.run_event(context, event_name, event_entity)
		for message: String in errors:
			_log("效果错误（%s）：%s" % [listener.display_name(), message])
		if event_name != "die":
			_emit_animation_cue("ability", listener, event_entity)


func _emit_animation_cue(trigger: String, actor: BattleEntity, target: Variant = null) -> void:
	if actor == null or actor.card == null or actor.card.animation_script == null:
		return
	if not actor.card.animation_script.has_trigger(trigger):
		return
	animation_cue.emit(trigger, actor, target)


# ----- 战斗 -----

func _resolve_combat() -> void:
	for column: int in range(COLUMN_COUNT):
		if winner != "":
			return
		_combat_column(column)


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
		if target is BattleEntity:
			damage_entity(target, attacker.attack, attacker.keywords)
		else:
			damage_hero(str(target).substr(5), attacker.attack)
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

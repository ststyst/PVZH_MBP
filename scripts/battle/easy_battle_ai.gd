class_name EasyBattleAI
extends RefCounted
## 简单 AI：尽可能打出费用最高的可打出手牌；需要目标时在合法目标中随机选择。
## 无牌可出时结束当前阶段。

const PHASE_HAND: String = BattleEngine.PHASE_HAND
const PHASE_SPELL: String = BattleEngine.PHASE_SPELL


## 执行一个动作；返回是否打出了牌（false 表示已结束该阶段）。
static func take_action(engine: BattleEngine, side: String) -> bool:
	if engine == null or engine.winner != "":
		return false
	if engine.active_side != side:
		return false
	if engine.phase != PHASE_HAND and engine.phase != PHASE_SPELL:
		return false
	var state: BattlePlayerState = engine.players.get(side, null)
	if state == null:
		return false
	var best_index: int = -1
	var best_cost: int = -1
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card(side, index)
		if card == null or card.cost > state.energy:
			continue
		if engine.phase == PHASE_SPELL and not (card.is_spell() or card.is_environment()):
			continue
		if card.is_entity() and engine.valid_slots(side, card).is_empty():
			continue
		if card.cost > best_cost:
			best_cost = card.cost
			best_index = index
	if best_index < 0:
		engine.end_phase(side)
		return false
	var card: CardData = engine.hand_card(side, best_index)
	var target: Dictionary = {}
	if card.is_entity():
		var slots: Array[Dictionary] = engine.valid_slots(side, card)
		if slots.is_empty():
			engine.end_phase(side)
			return false
		target = slots[engine.rng.randi_range(0, slots.size() - 1)]
	elif card.is_environment():
		target = {"column": engine.rng.randi_range(0, BattleEngine.COLUMN_COUNT - 1)}
	elif card.is_spell() and engine.card_needs_target(card):
		var candidates: Array = engine.target_candidates(card, side)
		if candidates.is_empty():
			engine.end_phase(side)
			return false
		target = {"handle": candidates[engine.rng.randi_range(0, candidates.size() - 1)]}
	var result: Dictionary = engine.play_card(side, best_index, target)
	if not bool(result.get("ok", false)):
		engine.end_phase(side)
		return false
	return true

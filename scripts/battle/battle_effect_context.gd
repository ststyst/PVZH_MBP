class_name BattleEffectContext
extends EffectContext
## 战斗层效果上下文：把 DSL 原语映射到 BattleEngine 的真实操作。
## 句柄：BattleEntity 或 "hero:p"/"hero:z"。

var engine: BattleEngine = null
var caster_side: String = "p"
var chosen_targets: Array = []
var source_keywords: Array = []
var chosen_column: int = -1
var chosen_slot: int = -1
var _self_handle: Variant = null
var _event_handle: Variant = null


func _init(battle_engine: BattleEngine, side: String) -> void:
	engine = battle_engine
	caster_side = side


func set_self_target(handle) -> void:
	_self_handle = handle


func set_event_target(handle) -> void:
	_event_handle = handle


func set_chosen_target(handle) -> void:
	set_chosen_targets([] if handle == null else [handle])


func set_chosen_targets(handles: Array) -> void:
	chosen_targets = handles.duplicate()


func set_source_keywords(keywords: Array) -> void:
	source_keywords = keywords.duplicate()


func set_chosen_position(column: int, slot: int) -> void:
	chosen_column = column
	chosen_slot = slot


func resolve_selector(selector: String) -> Array:
	match selector:
		"self":
			return [] if _self_handle == null else [_self_handle]
		"event":
			return [] if _event_handle == null else [_event_handle]
		"chosen":
			return chosen_targets.duplicate()
		"hero":
			return [engine.hero_handle(caster_side)]
		"enemy_hero":
			return [engine.hero_handle(engine.opposite_side(caster_side))]
		"all_enemies":
			return _entities_of(engine.opposite_side(caster_side))
		"random_enemy":
			return _random_one(_entities_of(engine.opposite_side(caster_side)))
		"all_allies":
			return _entities_of(caster_side)
		"other_allies":
			return _other_allies()
		"random_ally":
			return _random_one(_entities_of(caster_side))
		_:
			return []


func describe_entity(handle) -> Dictionary:
	if handle is BattleEntity:
		var entity: BattleEntity = handle
		return {
			"side": _relative_side(entity.side),
			"class": entity.card.card_class if entity.card != null else "",
			"tribes": entity.card.tribes if entity.card != null else [],
			"attack": entity.attack,
			"health": entity.health,
			"shield": entity.shield,
		}
	if handle is String and handle.begins_with("hero:"):
		var side: String = handle.substr(5)
		var state: BattlePlayerState = engine.players.get(side, null)
		return {
			"side": _relative_side(side),
			"class": "hero",
			"tribes": [],
			"attack": 0,
			"health": state.hero_health if state != null else 0,
			"shield": 0,
		}
	return {}


func summon(card_name: String, count: int = 1) -> Array:
	return engine.summon_card_by_name(caster_side, card_name, count)


func draw_cards(count: int) -> int:
	return engine.draw_cards(caster_side, count)


func deal_damage(target, amount: int) -> void:
	engine.damage_handle(target, amount, source_keywords)


func heal(target, amount: int) -> void:
	engine.heal_handle(target, amount)


func gain_shield(target, amount: int) -> void:
	engine.gain_shield_handle(target, amount)


func buff_stats(target, attack_delta: int, health_delta: int) -> void:
	engine.buff_handle(target, attack_delta, health_delta)


func gain_energy(amount: int) -> void:
	engine.gain_energy(caster_side, amount)


func give_keyword(target, keyword: String, value: int = 0) -> void:
	engine.give_keyword_handle(target, keyword, value)


func destroy(target) -> void:
	engine.destroy_handle(target)


func move_entity(target, column: int, slot: int) -> bool:
	return engine.move_entity_handle(target, column, slot)


func move_entity_to_chosen_position(target) -> bool:
	if chosen_column < 0 or chosen_slot < 0:
		return false
	return engine.move_entity_handle(target, chosen_column, chosen_slot)


func choose_targets(count: int, selector: String) -> bool:
	if chosen_targets.size() > maxi(count, 0):
		return false
	var candidates: Array = resolve_selector(selector)
	var seen: Dictionary = {}
	for handle: Variant in chosen_targets:
		if not candidates.has(handle):
			return false
		var key: Variant = handle if not handle is BattleEntity else (handle as BattleEntity).entity_id
		if seen.has(key):
			return false
		seen[key] = true
	return true


func gain_attack(amount: int) -> void:
	if _self_handle is BattleEntity:
		engine.buff_handle(_self_handle, amount, 0)


func reduce_cost(_amount: int) -> void:
	pass


func add_marker(marker_name: String, amount: int) -> void:
	if marker_name.is_empty() or amount == 0:
		return
	var state: BattlePlayerState = engine.players.get(caster_side, null)
	if state == null:
		return
	state.add_marker(marker_name, amount)


func remove_marker(marker_name: String, amount: int) -> void:
	add_marker(marker_name, -abs(amount))


func marker_count(marker_name: String) -> int:
	var state: BattlePlayerState = engine.players.get(caster_side, null)
	return state.marker_count(marker_name) if state != null else 0


func _other_allies() -> Array:
	var result: Array = []
	for entity: BattleEntity in _entities_of(caster_side):
		if entity != _self_handle:
			result.append(entity)
	return result


func _entities_of(side: String) -> Array:
	var result: Array = []
	for entity: BattleEntity in engine.entities:
		if entity.alive and entity.side == side:
			result.append(entity)
	return result


func _random_one(handles: Array) -> Array:
	if handles.is_empty():
		return []
	return [handles[engine.rng.randi_range(0, handles.size() - 1)]]


func _relative_side(side: String) -> String:
	if _self_handle is BattleEntity and _self_handle.side == side:
		return "self"
	return "ally" if side == caster_side else "enemy"

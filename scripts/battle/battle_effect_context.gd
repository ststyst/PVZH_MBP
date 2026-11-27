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
var base_column: int = -1
var is_spell_source: bool = false
var _self_handle: Variant = null
var _event_handle: Variant = null
var source_name: String = ""
var damage_targets: Array = []
## damaged / hero_damaged 事件派发期间的伤害来源与有效伤害数值。
var damage_source: Variant = null
var damage_amount: int = 0


func _init(battle_engine: BattleEngine, side: String) -> void:
	engine = battle_engine
	caster_side = side


func set_self_target(handle) -> void:
	_self_handle = handle


func set_event_target(handle) -> void:
	_event_handle = handle


func set_source_name(name: String) -> void:
	source_name = name


func set_damage_targets(targets: Array) -> void:
	damage_targets = targets.duplicate()


func set_damage_source(handle) -> void:
	damage_source = handle


func get_damage_source() -> Variant:
	return damage_source


func set_damage_amount(amount: int) -> void:
	damage_amount = amount


func get_damage_amount() -> int:
	return damage_amount


func is_entity_handle(handle) -> bool:
	return handle is BattleEntity


func set_chosen_target(handle) -> void:
	set_chosen_targets([] if handle == null else [handle])


func set_chosen_targets(handles: Array) -> void:
	chosen_targets = handles.duplicate()


func set_source_keywords(keywords: Array) -> void:
	source_keywords = keywords.duplicate()


func set_chosen_position(column: int, slot: int) -> void:
	chosen_column = column
	chosen_slot = slot


func set_base_column(column: int) -> void:
	base_column = column


func set_spell_source(value: bool) -> void:
	is_spell_source = value


func can_target(handle) -> bool:
	if handle is BattleEntity:
		if handle.has_buff("buried"):
			return false
		if _spell_immunity_applies(handle):
			return false
	return true


## 锦囊免疫只在“敌方施放的锦囊”作用于该实体时生效。
## 我方锦囊照常影响我方实体（不判断效果有益/有害）；环境等非锦囊来源一律不受影响。
func _spell_immunity_applies(target) -> bool:
	if not is_spell_source:
		return false
	if not target is BattleEntity:
		return false
	var entity: BattleEntity = target
	if entity.side == caster_side:
		return false
	return entity.is_spell_immune()


func resolve_selector(selector: String) -> Array:
	match selector:
		"self":
			return [] if _self_handle == null else [_self_handle]
		"event":
			return [] if _event_handle == null else [_event_handle]
		"mounted":
			return [] if _event_handle == null else [_event_handle]
		"chosen":
			return chosen_targets.duplicate()
		"damage_targets":
			return damage_targets.duplicate()
		"damage_source":
			return [] if damage_source == null else [damage_source]
		"hero":
			return [engine.hero_handle(caster_side)]
		"enemy_hero":
			return [engine.hero_handle(engine.opposite_side(caster_side))]
		"all_enemies":
			return _entities_of(engine.opposite_side(caster_side))
		"random_enemy":
			return _random_one(_entities_of(engine.opposite_side(caster_side)))
		"random_enemy_in_column_or_hero":
			var column_enemies: Array = []
			var column_ref: int = base_column
			if column_ref < 0 and _self_handle is BattleEntity:
				column_ref = _self_handle.column
			for entity: BattleEntity in _entities_of(engine.opposite_side(caster_side)):
				if entity.column == column_ref:
					column_enemies.append(entity)
			if column_enemies.is_empty():
				return [engine.hero_handle(engine.opposite_side(caster_side))]
			return _random_one(column_enemies)
		"all_allies":
			return _entities_of(caster_side)
		"all_allies_and_hero":
			var allies_and_hero: Array = [engine.hero_handle(caster_side)]
			allies_and_hero.append_array(_entities_of(caster_side))
			return allies_and_hero
		"all_entities":
			var all_entities: Array = []
			for entity: BattleEntity in engine.entities:
				if entity.alive:
					all_entities.append(entity)
			return all_entities
		"all_heroes_and_entities":
			var everyone: Array = [
				engine.hero_handle(engine.SIDE_P), engine.hero_handle(engine.SIDE_Z),
			]
			for entity: BattleEntity in engine.entities:
				if entity.alive:
					everyone.append(entity)
			return everyone
		"enemy_entities":
			return _entities_of(engine.opposite_side(caster_side))
		"enemy_hero_or_entities":
			var enemy_targets: Array = [engine.hero_handle(engine.opposite_side(caster_side))]
			enemy_targets.append_array(_entities_of(engine.opposite_side(caster_side)))
			return enemy_targets
		"frozen_enemies":
			var frozen: Array = []
			for entity: BattleEntity in _entities_of(engine.opposite_side(caster_side)):
				if entity.is_frozen():
					frozen.append(entity)
			return frozen
		"injured_allies":
			var injured: Array = []
			for entity: BattleEntity in _entities_of(caster_side):
				if entity.health < entity.max_health:
					injured.append(entity)
			return injured
		"buried_entities":
			var buried_all: Array = []
			for entity: BattleEntity in _entities_of(caster_side):
				if entity.has_buff("buried"):
					buried_all.append(entity)
			return buried_all
		"all_buried":
			var any_buried: Array = []
			for entity: BattleEntity in engine.entities:
				if entity.alive and entity.has_buff("buried"):
					any_buried.append(entity)
			return any_buried
		"buried_in_column":
			var buried_column: Array = []
			var reference_column: int = base_column
			if reference_column < 0 and _self_handle is BattleEntity:
				reference_column = _self_handle.column
			for entity: BattleEntity in engine.entities:
				if entity.alive and entity.has_buff("buried") and entity.column == reference_column:
					buried_column.append(entity)
			return buried_column
		"other_allies":
			return _other_allies()
		"random_ally":
			return _random_one(_entities_of(caster_side))
		_:
			return []


func describe_entity(handle) -> Dictionary:
	if handle is BattleEntity:
		var entity: BattleEntity = handle
		var reference_column: int = base_column
		if reference_column < 0 and _self_handle is BattleEntity:
			reference_column = _self_handle.column
		return {
			"side": _side_fact(entity),
			"class": entity.card.card_class if entity.card != null else "",
			"tribes": entity.card.tribes if entity.card != null else [],
			"keywords": entity.keywords.duplicate(),
			"keyword_values": entity.keyword_values.duplicate(),
			"buffs": entity.buffs.keys(),
			"attack": entity.attack,
			"health": entity.health,
			"max_health": entity.max_health,
			"shield": entity.shield,
			"defense": entity.shield,
			"cost": entity.cost,
			"turn": engine.turn,
			"entered_this_turn": entity.entered_turn == engine.turn,
			"column": entity.column - reference_column if reference_column >= 0 else entity.column + 1,
			"column_abs": entity.column + 1,
			"slot": entity.slot,
		}
	if handle is String and handle.begins_with("hero:"):
		var side: String = handle.substr(5)
		var state: BattlePlayerState = engine.players.get(side, null)
		return {
			"side": "neutral" if caster_side.is_empty() else ("ally" if side == caster_side else "enemy"),
			"class": "hero",
			"tribes": [],
			"keywords": [],
			"keyword_values": {},
			"buffs": [],
			"attack": 0,
			"health": state.hero_health if state != null else 0,
			"max_health": state.hero_max_health if state != null else 0,
			"shield": state.hero_shield if state != null else 0,
			"defense": 0,
			"cost": 0,
			"turn": engine.turn,
			"entered_this_turn": false,
			"slot": -1,
		}
	return {}


## 卡牌筛选表达式（CardFilter.matches_values）用的字段快照。
## 按在场实体的**当前状态**取值：词缀含 Buff/环境临时赋予的，费用用 entity.cost。
func filter_values(handle) -> Dictionary:
	if not handle is BattleEntity:
		return {}
	var entity: BattleEntity = handle
	var card: CardData = entity.card
	if card == null:
		return {}
	return {
		"name": card.english_name,
		"kind": card.kind,
		"rarity": card.rarity,
		"class": card.card_class,
		"category": card.class_category,
		"keywords": entity.keywords.duplicate(),
		"tribes": card.tribes.duplicate(),
		"deck_includable": card.deck_includable,
		"cost": entity.cost,
		"attack": entity.attack,
		"health": entity.health,
	}


func summon(card_name: String, column: Variant = null, max_column: Variant = null, preference: String = "") -> Array:
	var card: CardData = engine.get_card_by_english(card_name)
	if card == null or not card.is_entity():
		return []
	var relative: bool = _self_handle is BattleEntity
	var base_column: int = _self_handle.column if relative else 0
	var columns: Array[int] = []
	if column == null:
		for index: int in range(BattleEngine.COLUMN_COUNT):
			columns.append(index)
	elif max_column != null:
		var first: int = int(column)
		var last: int = int(max_column)
		if first > last:
			var swap_value: int = first
			first = last
			last = swap_value
		var limit: int = 4 if relative else BattleEngine.COLUMN_COUNT
		first = clampi(first, -limit if relative else 1, limit)
		last = clampi(last, -limit if relative else 1, limit)
		for value: int in range(first, last + 1):
			var target_column: int = base_column + value if relative else value - 1
			if target_column >= 0 and target_column < BattleEngine.COLUMN_COUNT:
				columns.append(target_column)
	else:
		var value: int = int(column)
		var target_column: int = base_column + value if relative else value - 1
		if target_column >= 0 and target_column < BattleEngine.COLUMN_COUNT:
			columns.append(target_column)
	# 可选列偏好：优先在“没有/有敌方实体”的列里随机尝试；都不满足则回退原本随机逻辑。
	var ordered_groups: Array = []
	if not preference.strip_edges().is_empty():
		var preferred_columns: Array[int] = []
		for candidate: int in columns:
			if _summon_preference_matches(candidate, preference):
				preferred_columns.append(candidate)
		if not preferred_columns.is_empty():
			ordered_groups.append(preferred_columns)
	ordered_groups.append(columns.duplicate())
	for group: Array in ordered_groups:
		var candidates: Array[int] = []
		for column_value: Variant in group:
			candidates.append(int(column_value))
		for index: int in range(candidates.size() - 1, 0, -1):
			var swap_index: int = engine.rng.randi_range(0, index)
			var temp_value: int = candidates[index]
			candidates[index] = candidates[swap_index]
			candidates[swap_index] = temp_value
		for target_column: int in candidates:
			var entity: BattleEntity = engine.summon_card_in_column(caster_side, card, target_column)
			if entity != null:
				return [entity]
	return []


## 随机召唤的可选列偏好：no_enemy = 该列没有敌方实体；has_enemy = 该列有敌方实体。
func _summon_preference_matches(column: int, preference: String) -> bool:
	var has_enemy: bool = not engine.alive_entities(column, engine.opposite_side(caster_side)).is_empty()
	match preference.strip_edges().to_lower():
		"no_enemy", "without_enemy":
			return not has_enemy
		"has_enemy", "with_enemy":
			return has_enemy
		_:
			return false


func draw_cards(count: int, cost_delta: int = 0, target = null) -> int:
	var draw_side: String = _side_of(target) if target != null else caster_side
	if draw_side.is_empty():
		return 0
	return engine.draw_cards(draw_side, count, cost_delta)


func draw_matching_cards(target, count: int, filter_text: String, cost_delta: int = 0) -> int:
	var side: String = _side_of(target)
	if side.is_empty():
		return 0
	return engine.draw_matching_cards(side, count, filter_text, cost_delta)


func deal_damage(target, amount: int) -> void:
	var source_entity: BattleEntity = _self_handle if _self_handle is BattleEntity else null
	var source_label: String = ""
	match get_zone():
		"environment":
			source_label = "环境"
		"hand", "deck":
			if _self_handle is BattleCardInstance:
				var source_card: CardData = engine.get_card(_self_handle.card_id)
				source_label = "%s：%s" % [
					"手牌" if get_zone() == "hand" else "牌库",
					source_card.display_name() if source_card != null else _self_handle.card_id,
				]
	if is_spell_source and not source_name.is_empty():
		source_label = "锦囊：%s" % source_name
	if source_label.is_empty() and source_entity == null and not is_spell_source:
		source_label = "%s（%s）" % [source_name, caster_side.to_upper()] if not source_name.is_empty() else "%s 方效果" % caster_side.to_upper()
	engine.damage_handle(target, amount, source_keywords, _spell_immunity_applies(target), source_entity, source_label)


func damage_column_relative(amount: int, direction: String, column_offset: int = 0) -> void:
	var reference_column: int = base_column
	var source_entity: BattleEntity = null
	if _self_handle is BattleEntity:
		reference_column = _self_handle.column
		source_entity = _self_handle
	if reference_column < 0:
		return
	var explicit_source: String = ""
	if source_entity == null:
		if is_spell_source:
			explicit_source = "锦囊：%s" % source_name if not source_name.is_empty() else "锦囊"
		elif get_zone() == "environment":
			explicit_source = "环境"
	engine.damage_column_relative_at(
		caster_side,
		reference_column,
		amount,
		direction,
		column_offset,
		source_entity,
		source_keywords,
		explicit_source
	)


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


func environment_grant_keyword(keyword: String, value: int, side_filter: String) -> void:
	engine.grant_environment_keyword(base_column, caster_side, keyword, value, side_filter)


func environment_grant_keyword_persistent(keyword: String, value: int, side_filter: String) -> void:
	engine.grant_environment_keyword_persistent(base_column, caster_side, keyword, value, side_filter)


func transform_targets(targets: Array, filter_text: String) -> void:
	for handle: Variant in targets:
		if _spell_immunity_applies(handle):
			continue
		engine.transform_entity_handle(handle, filter_text)


func transform_hand(side_filter: String, old_filter: String, new_filter: String) -> void:
	engine.transform_hand(caster_side, side_filter, old_filter, new_filter)


func environment_grant_stats(attack: int, health: int, shield: int, side_filter: String) -> void:
	engine.grant_environment_stats(base_column, caster_side, attack, health, shield, side_filter)


func destroy(target, from_spell: bool = false) -> void:
	# 只有“敌方锦囊”会被锦囊免疫拦下；from_spell 由调用方按来源计算。
	engine.destroy_handle(target, _spell_immunity_applies(target))


func is_spell_effect_source() -> bool:
	return is_spell_source


func move_entity(target, column: int, slot: int) -> bool:
	if _spell_immunity_applies(target):
		return false
	return engine.move_entity_handle(target, column, slot)


func move_entity_to_chosen_position(target) -> bool:
	if _spell_immunity_applies(target):
		return false
	if chosen_column < 0 or chosen_slot < 0:
		return false
	return engine.move_entity_handle(target, chosen_column, chosen_slot)


func add_random_cards(
	zone: String, target, count: int, filter_text: String, cost_delta: int = 0,
	keyword: String = "", attack_bonus: int = 0, health_bonus: int = 0, shield_bonus: int = 0,
	keyword_value: int = 0
) -> int:
	var target_side: String = ""
	if target is BattleEntity:
		target_side = target.side
	elif target is String and target.begins_with("hero:"):
		target_side = target.substr(5)
	if target_side.is_empty():
		return 0
	return engine.add_random_cards(
		target_side, zone, count, filter_text, cost_delta,
		keyword, attack_bonus, health_bonus, shield_bonus, keyword_value
	)


func entities_in_column(min_offset: int, max_offset: int, side_filter: String, min_attack: int = 0) -> Array:
	if caster_side.is_empty() and side_filter in ["ally", "enemy"]:
		return []
	var reference_column: int = base_column
	if reference_column < 0 and _self_handle is BattleEntity:
		reference_column = _self_handle.column
	if reference_column < 0:
		return []
	var first_column: int = reference_column + mini(min_offset, max_offset)
	var last_column: int = reference_column + maxi(min_offset, max_offset)
	var result: Array = []
	for entity: BattleEntity in engine.entities:
		if not entity.alive:
			continue
		if entity.column < first_column or entity.column > last_column:
			continue
		if min_attack > 0 and entity.attack < min_attack:
			continue
		if side_filter == "ally" and entity.side != caster_side:
			continue
		if side_filter == "enemy" and entity.side == caster_side:
			continue
		result.append(entity)
	return result


func random_targets(count: int, selector: String) -> Array:
	var candidates: Array = resolve_selector(selector)
	for index: int in range(candidates.size() - 1, 0, -1):
		var swap_index: int = engine.rng.randi_range(0, index)
		var temp: Variant = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temp
	return candidates.slice(0, mini(maxi(count, 0), candidates.size()))


func buried_in_columns(side_filter: String, min_offset: int, max_offset: int) -> Array:
	var reference_column: int = base_column
	if reference_column < 0 and _self_handle is BattleEntity:
		reference_column = _self_handle.column
	var result: Array = []
	for entity: BattleEntity in engine.entities:
		if not entity.alive or not entity.has_buff("buried"):
			continue
		if entity.column < reference_column + mini(min_offset, max_offset):
			continue
		if entity.column > reference_column + maxi(min_offset, max_offset):
			continue
		if side_filter == "ally" and entity.side != caster_side:
			continue
		if side_filter == "enemy" and entity.side == caster_side:
			continue
		result.append(entity)
	return result


func count_buff_in_columns(side_filter: String, min_offset: int, max_offset: int, buff_id: String) -> int:
	var reference_column: int = base_column
	if reference_column < 0 and _self_handle is BattleEntity:
		reference_column = _self_handle.column
	if reference_column < 0:
		return 0
	var count: int = 0
	for entity: BattleEntity in engine.entities:
		if not entity.alive or not entity.has_buff(buff_id):
			continue
		if entity.column < reference_column + mini(min_offset, max_offset):
			continue
		if entity.column > reference_column + maxi(min_offset, max_offset):
			continue
		if side_filter == "ally" and entity.side != caster_side:
			continue
		if side_filter == "enemy" and entity.side == caster_side:
			continue
		count += 1
	return count


func place_environment(column_offset: int, card_name: String) -> bool:
	var reference_column: int = base_column
	if reference_column < 0 and _self_handle is BattleEntity:
		reference_column = _self_handle.column
	if reference_column < 0:
		reference_column = chosen_column
	if reference_column < 0:
		return false
	return engine.place_environment_by_name(caster_side, reference_column + column_offset, card_name)


## 清除基准列偏移位置的环境；中立环境保持原样。清除不会触发 environment_played。
func clear_environment(column_offset: int = 0) -> bool:
	var reference_column: int = _base_reference_column()
	if reference_column < 0:
		return false
	return engine.clear_environment_at(reference_column + column_offset)


## 对基准列偏移位置造成伤害：该列没有敌方实体时打敌方英雄，否则打更靠前的敌方实体。
func damage_column(amount: int, column_offset: int = 0) -> void:
	if amount <= 0:
		return
	var reference_column: int = _base_reference_column()
	if reference_column < 0:
		return
	var target_column: int = reference_column + column_offset
	if target_column < 0 or target_column >= BattleEngine.COLUMN_COUNT:
		return
	var source_entity: BattleEntity = _self_handle if _self_handle is BattleEntity else null
	var explicit_source: String = ""
	if source_entity == null:
		if is_spell_source:
			explicit_source = "锦囊：%s" % source_name if not source_name.is_empty() else "锦囊"
		elif get_zone() == "environment":
			explicit_source = "环境"
	engine.damage_column_front(
		caster_side,
		target_column,
		amount,
		source_entity,
		source_keywords,
		is_spell_source,
		explicit_source,
	)


## 基准列：实体/环境为自身列，锦囊为玩家选择（或出牌时指定）的列。
func _base_reference_column() -> int:
	var reference_column: int = base_column
	if reference_column < 0 and _self_handle is BattleEntity:
		reference_column = _self_handle.column
	if reference_column < 0:
		reference_column = chosen_column
	if reference_column < 0 or reference_column >= BattleEngine.COLUMN_COUNT:
		return -1
	return reference_column


## 在自身位置（实体能力：自身列/格；锦囊：选择的列/格）尝试召唤一个符合筛选的实体。
## 不给列参数时默认自身列；实体能力的列参数是相对自身的偏移，锦囊是绝对列 1~5。
## 可选词缀会在入场事件前赋予，并参与该列能否放置的判定。
func summon_matching(
	filter_text: String,
	column: Variant = null,
	max_column: Variant = null,
	keyword_text: String = "",
	preference: String = "",
) -> void:
	var self_entity: BattleEntity = _self_handle if _self_handle is BattleEntity else null
	var preferred_slot: int = BattleEngine.SLOT_NORMAL
	if self_entity != null:
		preferred_slot = self_entity.slot
	elif chosen_slot >= 0:
		preferred_slot = chosen_slot
	var columns: Array[int] = []
	if column == null:
		if self_entity != null:
			columns.append(self_entity.column)
		elif chosen_column >= 0:
			columns.append(chosen_column)
	else:
		var first_value: int = int(column)
		var last_value: int = int(max_column) if max_column != null else first_value
		if self_entity != null:
			var origin: int = self_entity.column
			var low_offset: int = clampi(mini(first_value, last_value), -4, 4)
			var high_offset: int = clampi(maxi(first_value, last_value), -4, 4)
			for offset: int in range(low_offset, high_offset + 1):
				var target_column: int = origin + offset
				if target_column >= 0 and target_column < BattleEngine.COLUMN_COUNT:
					columns.append(target_column)
		else:
			for value: int in range(mini(first_value, last_value), maxi(first_value, last_value) + 1):
				var target_column: int = value - 1
				if target_column >= 0 and target_column < BattleEngine.COLUMN_COUNT:
					columns.append(target_column)
	if columns.is_empty():
		return
	for index: int in range(columns.size() - 1, 0, -1):
		var swap_index: int = engine.rng.randi_range(0, index)
		var swap_value: int = columns[index]
		columns[index] = columns[swap_index]
		columns[swap_index] = swap_value
	engine.summon_matching_in_columns(caster_side, columns, preferred_slot, filter_text, keyword_text, preference)


## 目标所在列的环境种类（环境 id）。不带参数时读当前基准列：
## 实体异能读自身列，锦囊读打出时选择的列。
func environment_kind(target = null) -> String:
	var column: int = _environment_column_of(target)
	if column < 0:
		return ""
	return engine.environment_id_at(column)


## 目标所在列的环境归属方，相对技能拥有者返回 ally / enemy / neutral。
func environment_owner(target = null) -> String:
	var column: int = _environment_column_of(target)
	if column < 0:
		return ""
	var owner: String = engine.environment_owner_at(column)
	if owner.is_empty():
		return "neutral"
	return "ally" if owner == caster_side else "enemy"


## 目标实体所在列；没给目标时回退到基准列（实体自身列 / 锦囊选择列）。
func _environment_column_of(target) -> int:
	if target is BattleEntity:
		var entity: BattleEntity = target
		return entity.column if entity.alive else -1
	var column: int = base_column
	if column < 0 and _self_handle is BattleEntity:
		column = _self_handle.column
	if column < 0:
		column = chosen_column
	if column < 0 or column >= BattleEngine.COLUMN_COUNT:
		return -1
	return column


# ----- 数值查询 -----

func energy_gained() -> int:
	var state: BattlePlayerState = engine.players.get(caster_side, null)
	return state.energy_gained_this_turn if state != null else 0


func hero_health(target = null) -> int:
	var hero_side: String = _side_of(target) if target != null else caster_side
	if hero_side.is_empty():
		hero_side = caster_side
	var state: BattlePlayerState = engine.players.get(hero_side, null)
	return state.hero_health if state != null else 0


func highest_attack(side_filter: String) -> int:
	return _extreme_entity_stat(side_filter, "attack", true)


func lowest_attack(side_filter: String) -> int:
	return _extreme_entity_stat(side_filter, "attack", false)


func highest_health(side_filter: String) -> int:
	return _extreme_entity_stat(side_filter, "health", true)


func lowest_health(side_filter: String) -> int:
	return _extreme_entity_stat(side_filter, "health", false)


## side_filter 支持 ally / enemy / all（both 亦可）；没有匹配实体时返回 0。
func _extreme_entity_stat(side_filter: String, stat_name: String, want_highest: bool) -> int:
	var wanted_sides: Array[String] = []
	match side_filter.strip_edges().to_lower():
		"ally", "self":
			wanted_sides = [caster_side]
		"enemy":
			wanted_sides = [engine.opposite_side(caster_side)]
		"all", "both", "":
			wanted_sides = [BattleEngine.SIDE_P, BattleEngine.SIDE_Z]
		_:
			return 0
	var has_value: bool = false
	var best: int = 0
	for entity: BattleEntity in engine.entities:
		if not entity.alive or not wanted_sides.has(entity.side):
			continue
		var value: int = entity.attack if stat_name == "attack" else entity.health
		if not has_value:
			best = value
			has_value = true
		elif want_highest:
			best = maxi(best, value)
		else:
			best = mini(best, value)
	return best if has_value else 0


func apply_buff(target, buff_id: String, amount: int = 1) -> bool:
	if not target is BattleEntity:
		return false
	if _spell_immunity_applies(target):
		return false
	return engine.apply_buff_handle(target, buff_id, amount)


func temp_buff(
	target,
	attack_delta: int,
	health_delta: int,
	shield_delta: int,
	keyword: String = "",
	keyword_value: int = 0,
) -> bool:
	if not target is BattleEntity:
		return false
	if _spell_immunity_applies(target):
		return false
	return engine.apply_temp_buff_handle(
		target, attack_delta, health_delta, shield_delta, keyword, keyword_value
	)


func remove_buff(target, buff_id: String) -> bool:
	if not target is BattleEntity:
		return false
	if _spell_immunity_applies(target):
		return false
	return engine.remove_buff_handle(target, buff_id)


func force_attack(target) -> bool:
	if not target is BattleEntity:
		return false
	if _spell_immunity_applies(target):
		return false
	return engine.force_entity_attack(target)


func remove_entity(target) -> bool:
	if not target is BattleEntity:
		return false
	if _spell_immunity_applies(target):
		return false
	return engine.remove_entity_handle(target)


func gain_max_health(target, delta: int) -> void:
	if _spell_immunity_applies(target):
		return
	engine.change_max_health_handle(target, delta)


func put_random_card_on_deck_top(
	target, filter_text: String, keyword: String = "",
	attack_bonus: int = 0, health_bonus: int = 0, shield_bonus: int = 0, keyword_value: int = 0
) -> bool:
	var side: String = _side_of(target)
	if side.is_empty():
		return false
	return engine.put_random_card_on_deck_top(
		side, filter_text, keyword, attack_bonus, health_bonus, shield_bonus, keyword_value
	)


func put_hand_card_on_deck_top(target, filter_text: String) -> bool:
	var side: String = _side_of(target)
	return false if side.is_empty() else engine.put_hand_card_on_deck_top(side, filter_text)


func shuffle_buried_positions(target) -> bool:
	var side: String = _side_of(target)
	return false if side.is_empty() else engine.shuffle_buried_positions(side)


func _side_of(target) -> String:
	if target is BattleEntity:
		return target.side
	if target is String and target.begins_with("hero:"):
		return target.substr(5)
	return ""


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


func add_marker(marker_name: String, amount: int, target = null) -> void:
	if marker_name.is_empty() or amount == 0:
		return
	var marker_side: String = _side_of(target) if target != null else caster_side
	if marker_side.is_empty():
		return
	var state: BattlePlayerState = engine.players.get(marker_side, null)
	if state == null:
		return
	state.add_marker(marker_name, amount)
	# 标志物可能影响手牌展示（如“军阀点数”），通知界面刷新。
	engine.changed.emit()


func remove_marker(marker_name: String, amount: int, target = null) -> void:
	add_marker(marker_name, -abs(amount), target)


func marker_count(marker_name: String, target = null) -> int:
	var marker_side: String = _side_of(target) if target != null else caster_side
	if marker_side.is_empty():
		return 0
	var state: BattlePlayerState = engine.players.get(marker_side, null)
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


func _side_fact(entity: BattleEntity) -> String:
	if caster_side.is_empty():
		return "neutral"
	if _self_handle is BattleEntity and _self_handle == entity:
		return "self"
	return "ally" if entity.side == caster_side else "enemy"


func _relative_side(side: String) -> String:
	if caster_side.is_empty():
		return "neutral"
	if _self_handle is BattleEntity and _self_handle.side == side:
		return "self"
	return "ally" if side == caster_side else "enemy"

extends Control
## 战斗界面（电脑随机卡组对战）：
## - 起手调度（每张牌可刷新一次）
## - 5 列 × 双方各 2 位（普通位 / 组队位）；点击组队实体可与同列另一实体换位
## - 阶段：z 出牌 → p 出牌 → z 锦囊/环境 → 逐列战斗 → 回合结束
## - 简单 AI：优先打出费用最高的可打出手牌，目标随机

const CARD_TILE_SCENE: PackedScene = preload("res://scenes/cards/CardTile.tscn")
const ENTITY_VIEW_SCENE: PackedScene = preload("res://scenes/battle/BattleEntityView.tscn")
const AI_INTERVAL: float = 0.7

var engine: BattleEngine = null
var player_side: String = "p"
var enemy_side: String = "z"
var mode: GameModeConfig = null

var _started: bool = false
var _time_limit_enabled: bool = true
var _pending_card_index: int = -1
var _pending_mode: String = ""
var _pending_candidates: Array = []
var _pending_handles: Array = []
var _phase_remaining: float = 0.0
var _last_phase_key: String = ""
var _ai_accum: float = 0.0

@onready var _enemy_hero_button: Button = %EnemyHeroButton
@onready var _player_hero_button: Button = %PlayerHeroButton
@onready var _enemy_info_label: Label = %EnemyInfoLabel
@onready var _player_info_label: Label = %PlayerInfoLabel
@onready var _board: HBoxContainer = %Board
@onready var _phase_label: Label = %PhaseLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _log_label: Label = %LogLabel
@onready var _status_label: Label = %StatusLabel
@onready var _end_phase_button: Button = %EndPhaseButton
@onready var _confirm_targets_button: Button = %ConfirmTargetsButton
@onready var _hand_row: HBoxContainer = %HandRow
@onready var _mulligan_overlay: Control = %MulliganOverlay
@onready var _mulligan_row: HBoxContainer = %MulliganRow
@onready var _mulligan_confirm_button: Button = %MulliganConfirmButton
@onready var _game_over_overlay: Control = %GameOverOverlay
@onready var _game_over_label: Label = %GameOverLabel
@onready var _game_over_back_button: Button = %GameOverBackButton
@onready var _special_overlay: Control = %SpecialOverlay
@onready var _special_hint: Label = %SpecialHint
@onready var _special_card_slot: Control = %SpecialCardSlot
@onready var _special_play_button: Button = %SpecialPlayButton
@onready var _special_hand_button: Button = %SpecialHandButton
@onready var _card_info_dialog: CardInfoDialog = %CardInfoDialog

var _board_columns: Array[Dictionary] = []
var _mulligan_used: Array[bool] = []
var _entity_views: Dictionary = {}
var _views_by_entity_id: Dictionary = {}
var _animation_queue: Array[Dictionary] = []
var _animation_busy: bool = false
var _empty_slot_style: StyleBoxEmpty = null
var _highlight_slot_style: StyleBoxFlat = null
var _special_target_mode: bool = false
var _special_card_tile: CardTile = null
var _pending_move_entity: BattleEntity = null
var _pending_move_base_target: Dictionary = {}
const LONG_PRESS_SECONDS: float = 0.45
var _long_press_entity: BattleEntity = null
var _long_press_elapsed: float = 0.0
var _long_press_fired: bool = false
var _suppress_slot_click: bool = false


func _ready() -> void:
	_init_slot_styles()
	_collect_board_columns()
	_enemy_hero_button.pressed.connect(_on_enemy_hero_pressed)
	_player_hero_button.pressed.connect(_on_player_hero_pressed)
	_end_phase_button.pressed.connect(_on_end_phase_pressed)
	_confirm_targets_button.pressed.connect(_on_confirm_targets_pressed)
	_mulligan_confirm_button.pressed.connect(_on_mulligan_confirm_pressed)
	_game_over_back_button.pressed.connect(_on_return_after_game_pressed)
	_special_play_button.pressed.connect(_on_special_play_pressed)
	_special_hand_button.pressed.connect(_on_special_hand_pressed)
	_card_info_dialog.confirmed.connect(_on_card_info_closed)
	_card_info_dialog.canceled.connect(_on_card_info_closed)
	var setup: Dictionary = BattleManager.current_battle
	if setup.is_empty():
		_show_fatal("没有进行中的对局，请返回准备界面重新开始。")
		return
	player_side = str(setup.get("player_side", "p"))
	enemy_side = "z" if player_side == "p" else "p"
	# 与电脑对战时取消回合阶段时间限制；玩家对玩家仍使用玩法配置。
	_time_limit_enabled = not bool(setup.get("is_ai", false))
	var player_hero: HeroData = HeroDatabase.get_hero(str(setup.get("player_hero_id", "")))
	var enemy_hero: HeroData = HeroDatabase.get_hero(str(setup.get("enemy_hero_id", "")))
	if player_hero == null or enemy_hero == null:
		_show_fatal("英雄数据缺失，无法开始对局。")
		return
	mode = ModeManager.get_mode()
	engine = BattleEngine.new(CardDatabase)
	engine.effect_resolution_limit = ServerConfig.effect_resolution_limit()
	engine.changed.connect(_on_engine_changed)
	engine.game_finished.connect(_on_game_finished)
	engine.animation_cue.connect(_on_animation_cue)
	engine.setup(
		player_side,
		player_hero,
		_to_string_array(setup.get("player_deck_ids", [])),
		enemy_hero,
		_to_string_array(setup.get("enemy_deck_ids", [])),
		mode,
	)
	engine.confirm_mulligan(enemy_side)
	_show_mulligan()


func _to_string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for entry: Variant in raw:
			result.append(str(entry))
	return result

# ----- 场景节点初始化 -----

func _collect_board_columns() -> void:
	_board_columns.clear()
	for index: int in range(_board.get_child_count()):
		var column: VBoxContainer = _board.get_child(index) as VBoxContainer
		if column == null:
			continue
		var environment_label: Label = column.get_node("EnvLabel") as Label
		var z_team: Button = column.get_node("ZTeamButton") as Button
		var z_normal: Button = column.get_node("ZNormalButton") as Button
		var p_normal: Button = column.get_node("PNormalButton") as Button
		var p_team: Button = column.get_node("PTeamButton") as Button
		z_team.pressed.connect(_on_slot_button_pressed.bind("z", index, BattleEngine.SLOT_TEAM_UP))
		z_normal.pressed.connect(_on_slot_button_pressed.bind("z", index, BattleEngine.SLOT_NORMAL))
		p_normal.pressed.connect(_on_slot_button_pressed.bind("p", index, BattleEngine.SLOT_NORMAL))
		p_team.pressed.connect(_on_slot_button_pressed.bind("p", index, BattleEngine.SLOT_TEAM_UP))
		for button: Button in [z_team, z_normal, p_normal, p_team]:
			button.text = ""
			_apply_empty_slot_style(button)
		z_team.button_down.connect(_on_slot_button_down.bind("z", index, BattleEngine.SLOT_TEAM_UP))
		z_normal.button_down.connect(_on_slot_button_down.bind("z", index, BattleEngine.SLOT_NORMAL))
		p_normal.button_down.connect(_on_slot_button_down.bind("p", index, BattleEngine.SLOT_NORMAL))
		p_team.button_down.connect(_on_slot_button_down.bind("p", index, BattleEngine.SLOT_TEAM_UP))
		z_team.button_up.connect(_on_slot_button_up)
		z_normal.button_up.connect(_on_slot_button_up)
		p_normal.button_up.connect(_on_slot_button_up)
		p_team.button_up.connect(_on_slot_button_up)
		_board_columns.append({
			"env": environment_label,
			"z_team": z_team,
			"z_normal": z_normal,
			"p_normal": p_normal,
			"p_team": p_team,
		})


func _init_slot_styles() -> void:
	_empty_slot_style = StyleBoxEmpty.new()
	_highlight_slot_style = StyleBoxFlat.new()
	_highlight_slot_style.bg_color = Color(1.0, 1.0, 1.0, 0.04)
	_highlight_slot_style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	_highlight_slot_style.set_border_width_all(3)
	_highlight_slot_style.set_corner_radius_all(6)


func _apply_empty_slot_style(button: Button) -> void:
	button.flat = true
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _empty_slot_style)


func _apply_highlight_slot_style(button: Button) -> void:
	button.flat = false
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _highlight_slot_style)


func _get_entity_view(button: Button) -> BattleEntityView:
	if _entity_views.has(button):
		var existing: BattleEntityView = _entity_views[button] as BattleEntityView
		if is_instance_valid(existing):
			return existing
	var view: BattleEntityView = ENTITY_VIEW_SCENE.instantiate() as BattleEntityView
	button.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entity_views[button] = view
	return view
# ----- 起手 -----

func _show_mulligan() -> void:
	_started = false
	_mulligan_used.clear()
	var state: BattlePlayerState = engine.players[player_side]
	for _index: int in range(state.hand.size()):
		_mulligan_used.append(false)
	_mulligan_overlay.visible = true
	_rebuild_mulligan_row()
	_refresh_all()


func _rebuild_mulligan_row() -> void:
	for child: Node in _mulligan_row.get_children():
		_mulligan_row.remove_child(child)
		child.queue_free()
	var state: BattlePlayerState = engine.players[player_side]
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card_display(player_side, index)
		if card == null:
			continue
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		_mulligan_row.add_child(column)
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		column.add_child(tile)
		tile.setup(card, 0, "", false)
		var refresh := Button.new()
		refresh.text = "刷新"
		refresh.disabled = index < _mulligan_used.size() and _mulligan_used[index]
		refresh.custom_minimum_size = Vector2(0, 36)
		refresh.pressed.connect(_on_mulligan_refresh_pressed.bind(index))
		column.add_child(refresh)


func _on_mulligan_refresh_pressed(index: int) -> void:
	if index < _mulligan_used.size() and _mulligan_used[index]:
		return
	if engine.replace_mulligan_card(player_side, index):
		if index < _mulligan_used.size():
			_mulligan_used[index] = true
		_rebuild_mulligan_row()


func _on_mulligan_confirm_pressed() -> void:
	engine.confirm_mulligan(player_side)
	_mulligan_overlay.visible = false
	_started = true
	_last_phase_key = ""
	_phase_remaining = mode.phase_time_limit_seconds
	_refresh_all()


# ----- 玩家操作 -----

func _on_hand_pressed(index: int) -> void:
	if not _can_player_act():
		_set_status("现在不是你的出牌阶段。", true)
		return
	var card: CardData = engine.hand_card_display(player_side, index)
	if card == null:
		return
	if engine.phase == BattleEngine.PHASE_SPELL and not (card.is_spell() or card.is_environment()):
		_set_status("锦囊/环境阶段不能打出实体牌。", true)
		return
	if engine.effective_hand_cost(player_side, index) > int(engine.players[player_side].energy):
		_set_status("费用不足。", true)
		return
	if card.is_entity():
		_pending_card_index = index
		_pending_handles.clear()
		_pending_candidates.clear()
		var requirement: Dictionary = (
			card.ability_script.target_requirement()
			if card.ability_script != null else {}
		)
		var required_count: int = int(requirement.get("count", 0))
		if required_count > 0:
			for entity: BattleEntity in engine.entities:
				if entity.alive and entity.side == player_side:
					_pending_candidates.append(entity)
			if not _pending_candidates.is_empty():
				_pending_mode = "choose"
				_set_status("最多选择 %d 个其他友方实体，然后点击空位放置（直接点空位表示少选/不选）。" % required_count)
				_refresh_all()
				return
		_pending_mode = "place"
		_set_status("请选择放置位置。")
		_refresh_all()
	elif card.is_environment():
		_pending_card_index = index
		_pending_mode = "column"
		_pending_candidates.clear()
		_set_status("请选择一列，将其环境变为这张环境牌。")
		_refresh_all()
	elif _card_multi_target_requirement(card).get("count", 0) > 0:
		_pending_card_index = index
		_pending_mode = "choose_spell"
		_pending_handles.clear()
		var requirement: Dictionary = _card_multi_target_requirement(card)
		var selector: String = str(requirement.get("selector", ""))
		_pending_candidates = engine.choose_candidates(selector, player_side)
		_set_status("最多选择 %d 个目标，然后点击“确认目标”。" % int(requirement.get("count", 0)))
		_refresh_all()
	elif engine.card_needs_target(card):
		_pending_card_index = index
		_pending_mode = "target"
		_pending_candidates = engine.target_candidates(card, player_side)
		_set_status("请选择目标。")
		_refresh_all()
	else:
		_play_pending({})


func _on_slot_button_pressed(side: String, column: int, slot: int) -> void:
	if _suppress_slot_click:
		_suppress_slot_click = false
		return
	_on_slot_pressed(side, column, slot)


func _on_slot_button_down(side: String, column: int, slot: int) -> void:
	if not _started or engine == null:
		return
	var entity: BattleEntity = _entity_at(column, side, slot)
	if entity == null:
		_long_press_entity = null
		_long_press_fired = false
		return
	_long_press_entity = entity
	_long_press_elapsed = 0.0
	_long_press_fired = false


func _on_slot_button_up() -> void:
	if _long_press_fired:
		_suppress_slot_click = true
	_long_press_entity = null
	_long_press_fired = false


func _update_long_press(delta: float) -> void:
	if _long_press_entity == null:
		return
	if not is_instance_valid(_long_press_entity) or not _long_press_entity.alive:
		_long_press_entity = null
		_long_press_fired = false
		return
	if _long_press_fired:
		return
	_long_press_elapsed += delta
	if _long_press_elapsed < LONG_PRESS_SECONDS:
		return
	_long_press_fired = true
	var card: CardData = _long_press_entity.card
	_long_press_entity = null
	if card != null:
		_card_info_dialog.show_card(card)


func _on_card_info_closed() -> void:
	_suppress_slot_click = false


func _on_slot_pressed(side: String, column: int, slot: int) -> void:
	if not _started or engine == null:
		return
	if _pending_mode == "move_position":
		if _pending_move_entity == null or side != _pending_move_entity.side:
			_set_status("只能移动到目标实体所属阵营的半场。", true)
			return
		if not _pending_move_candidate(column, slot):
			_set_status("该位置不是合法移动位置。", true)
			return
		var move_target: Dictionary = _pending_move_base_target.duplicate(true)
		move_target["column"] = column
		move_target["slot"] = slot
		if _special_target_mode:
			_resolve_special_target(move_target)
		else:
			_play_pending(move_target)
		return
	if _pending_mode == "choose_spell":
		var target_entity: BattleEntity = _entity_at(column, side, slot)
		if target_entity != null and _pending_candidates.has(target_entity):
			var limit: int = int(_card_multi_target_requirement(
				engine.hand_card(player_side, _pending_card_index)
			).get("count", 0))
			if _pending_handles.has(target_entity):
				_pending_handles.erase(target_entity)
			elif _pending_handles.size() < limit:
				_pending_handles.append(target_entity)
			_set_status("已选择 %d/%d 个目标；点击“确认目标”结算。" % [_pending_handles.size(), limit])
			_refresh_all()
			return
		_set_status("请选择高亮的实体目标。", true)
		return
	if _pending_mode == "choose" and side == player_side:
		var choose_entity: BattleEntity = _entity_at(column, side, slot)
		if choose_entity != null and _pending_candidates.has(choose_entity):
			var required_count: int = _pending_choose_limit()
			if _pending_handles.has(choose_entity):
				_pending_handles.erase(choose_entity)
			elif _pending_handles.size() < required_count:
				_pending_handles.append(choose_entity)
			if required_count > 0 and _pending_handles.size() >= required_count:
				_pending_mode = "place"
				_set_status("已选满 %d 个目标；点击放置位置（可点已有友方实体所在格）。" % required_count)
			else:
				_set_status("已选择 %d/%d；点击空位放置，或继续选择。" % [_pending_handles.size(), required_count])
			_refresh_all()
			return
		if choose_entity == null and _pending_slot_valid(column, slot):
			_play_pending({
				"column": column,
				"slot": slot,
				"handles": _pending_handles.duplicate(),
			})
			return
		_set_status("请选择高亮的友方实体，或点击空位放置。", true)
		return
	if _pending_mode == "place" and side == player_side:
		var place_target: Dictionary = {"column": column, "slot": slot}
		if not _pending_handles.is_empty():
			place_target["handles"] = _pending_handles.duplicate()
		_play_pending(place_target)
		return
	if _pending_mode == "column":
		if side == player_side:
			_play_pending({"column": column})
		return
	if _pending_mode == "target":
		var entity: BattleEntity = _entity_at(column, side, slot)
		if _special_target_mode:
			if entity != null and _pending_candidates.has(entity):
				_resolve_special_target({"handle": entity})
			else:
				_set_status("该位置不是超能力的合法目标。", true)
			return
		if entity != null and _pending_candidates.has(entity):
			_play_pending({"handle": entity})
		else:
			_set_status("该位置不是合法目标。", true)
		return
	# 任何目标选择/放置状态都优先；不再有手动换位。
	if not _pending_mode.is_empty():
		_set_status("请先完成当前目标选择。", true)
		return
	_set_status("先点击手牌选择要打出的牌。")


func _on_enemy_hero_pressed() -> void:
	_on_hero_target(enemy_side)


func _on_player_hero_pressed() -> void:
	_on_hero_target(player_side)


func _on_hero_target(side: String) -> void:
	if _pending_mode == "target" and _pending_candidates.has(engine.hero_handle(side)):
		if _special_target_mode:
			_resolve_special_target({"handle": engine.hero_handle(side)})
		else:
			_play_pending({"handle": engine.hero_handle(side)})
		return
	_set_status("这不是当前可选择的英雄目标。")


func _play_pending(target: Dictionary) -> void:
	if _pending_card_index < 0:
		return
	if _try_begin_move_position(target):
		return
	var result: Dictionary = engine.play_card(player_side, _pending_card_index, target)
	_clear_pending()
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("message", "出牌失败。")), true)
	else:
		_set_status(str(result.get("message", "")), false)
	_refresh_all()


func _on_end_phase_pressed() -> void:
	if not _can_player_act():
		return
	_clear_pending()
	engine.end_phase(player_side)
	_refresh_all()


func _clear_pending() -> void:
	_pending_card_index = -1
	_pending_mode = ""
	_pending_candidates.clear()
	_pending_handles.clear()
	_pending_move_entity = null
	_pending_move_base_target.clear()
	_special_target_mode = false
	_confirm_targets_button.visible = false


func _pending_move_candidate(column: int, slot: int) -> bool:
	for slot_info: Dictionary in _pending_candidates:
		if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
			return true
	return false


func _target_handle_list(target: Dictionary) -> Array:
	var result: Array = []
	var raw: Variant = target.get("handles", null)
	if raw is Array:
		for handle: Variant in raw:
			if handle != null:
				result.append(handle)
	elif raw != null:
		result.append(raw)
	var single: Variant = target.get("handle", null)
	if single != null and not result.has(single):
		result.append(single)
	return result


func _try_begin_move_position(target: Dictionary) -> bool:
	if target.has("column") and target.has("slot"):
		return false
	if _pending_card_index < 0:
		return false
	var card: CardData = engine.hand_card(player_side, _pending_card_index)
	if card == null or card.ability_script == null or not card.ability_script.move_requires_position():
		return false
	var handles: Array = _target_handle_list(target)
	if handles.size() != 1 or not (handles[0] is BattleEntity):
		return false
	var entity: BattleEntity = handles[0]
	_pending_move_entity = entity
	_pending_move_base_target = target.duplicate(true)
	_pending_mode = "move_position"
	_pending_candidates = engine.valid_move_slots(entity)
	_set_status("请选择 %s 要移动到的位置（不能选择当前位置）。" % entity.display_name())
	_refresh_all()
	return true


func _begin_move_position(entity: BattleEntity, base_target: Dictionary) -> void:
	_pending_move_entity = entity
	_pending_move_base_target = base_target.duplicate(true)
	_pending_mode = "move_position"
	_pending_candidates = engine.valid_move_slots(entity)
	_set_status("请选择 %s 要移动到的位置（不能选择当前位置）。" % entity.display_name())
	_refresh_all()


func _card_multi_target_requirement(card: CardData) -> Dictionary:
	if card == null or card.ability_script == null:
		return {}
	return card.ability_script.target_requirement()


func _update_confirm_targets_button() -> void:
	_confirm_targets_button.visible = _pending_mode == "choose_spell"


func _on_confirm_targets_pressed() -> void:
	if _pending_mode != "choose_spell":
		return
	var target: Dictionary = {"handles": _pending_handles.duplicate()}
	if _special_target_mode:
		_resolve_special_target(target)
	else:
		_play_pending(target)


func _pending_choose_limit() -> int:
	var card: CardData = engine.hand_card(player_side, _pending_card_index)
	if card == null or card.ability_script == null:
		return 0
	return int(card.ability_script.target_requirement().get("count", 0))


func _pending_slot_valid(column: int, slot: int) -> bool:
	var card: CardData = engine.hand_card(player_side, _pending_card_index)
	if card == null:
		return false
	for slot_info: Dictionary in engine.valid_slots(player_side, card):
		if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
			return true
	return false


# ----- 状态刷新 -----

func _on_engine_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	if engine == null:
		return
	_update_hero_bars()
	_update_board()
	_rebuild_hand()
	_update_labels()
	_update_log()
	_update_confirm_targets_button()
	_refresh_special_overlay()


func _update_hero_bars() -> void:
	var player_state: BattlePlayerState = engine.players[player_side]
	var enemy_state: BattlePlayerState = engine.players[enemy_side]
	_player_hero_button.text = "%s（%s） 生命 %d/%d · 费用 %d/%d · 充能 %d/%d · 耐久 %d" % [
		player_state.hero.display_name(), player_side.to_upper(),
		player_state.hero_health, player_state.hero_max_health,
		player_state.energy, player_state.energy_cap,
		player_state.charge_shield, mode.charge_shield_max,
		player_state.charge_shield_durability,
	]
	_enemy_hero_button.text = "%s（%s） 生命 %d/%d · 费用 %d/%d · 充能 %d/%d · 耐久 %d" % [
		enemy_state.hero.display_name(), enemy_side.to_upper(),
		enemy_state.hero_health, enemy_state.hero_max_health,
		enemy_state.energy, enemy_state.energy_cap,
		enemy_state.charge_shield, mode.charge_shield_max,
		enemy_state.charge_shield_durability,
	]
	_player_info_label.text = "手牌 %d · 牌库 %d" % [player_state.hand_count(), player_state.deck_count()]
	_enemy_info_label.text = "手牌 %d · 牌库 %d" % [enemy_state.hand_count(), enemy_state.deck_count()]


func _update_board() -> void:
	var valid_slots: Array[Dictionary] = []
	if _pending_mode == "place" and _pending_card_index >= 0:
		var pending_card: CardData = engine.hand_card(player_side, _pending_card_index)
		if pending_card != null:
			valid_slots = engine.valid_slots(player_side, pending_card)
	for column_index: int in range(_board_columns.size()):
		var column_ui: Dictionary = _board_columns[column_index]
		column_ui["env"].text = "第%d列\n%s" % [column_index + 1, engine.environment_labels[column_index]]
		_update_slot_button(column_ui["z_team"], "z", column_index, BattleEngine.SLOT_TEAM_UP, valid_slots)
		_update_slot_button(column_ui["z_normal"], "z", column_index, BattleEngine.SLOT_NORMAL, valid_slots)
		_update_slot_button(column_ui["p_normal"], "p", column_index, BattleEngine.SLOT_NORMAL, valid_slots)
		_update_slot_button(column_ui["p_team"], "p", column_index, BattleEngine.SLOT_TEAM_UP, valid_slots)


func _update_slot_button(
	button: Button,
	side: String,
	column: int,
	slot: int,
	valid_slots: Array[Dictionary],
) -> void:
	var entity: BattleEntity = _entity_at(column, side, slot)
	var actionable: bool = false
	if not _started or engine.winner != "":
		actionable = false
	elif _pending_mode == "place":
		if side == player_side:
			for slot_info: Dictionary in valid_slots:
				if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
					actionable = true
					break
	elif _pending_mode == "column":
		actionable = side == player_side
	elif _pending_mode == "target":
		actionable = entity != null and _pending_candidates.has(entity)
	elif _pending_mode == "choose":
		if side == player_side:
			if entity == null:
				for slot_info: Dictionary in valid_slots:
					if int(slot_info.get("column", -1)) == column and int(slot_info.get("slot", -1)) == slot:
						actionable = true
						break
			else:
				actionable = _pending_candidates.has(entity)
	elif _pending_mode == "move_position":
		actionable = (
			_pending_move_entity != null
			and side == _pending_move_entity.side
			and _pending_move_candidate(column, slot)
		)
	else:
		actionable = false
	if _pending_mode == "choose_spell":
		actionable = entity != null and _pending_candidates.has(entity)
	if entity == null:
		if _entity_views.has(button):
			var hidden_view: BattleEntityView = _entity_views[button] as BattleEntityView
			if is_instance_valid(hidden_view):
				hidden_view.visible = false
		button.text = ""
		if actionable and (
			_pending_mode == "place"
			or _pending_mode == "column"
			or _pending_mode == "choose"
			or _pending_mode == "move_position"
		):
			_apply_highlight_slot_style(button)
			button.disabled = false
		else:
			_apply_empty_slot_style(button)
			button.disabled = true
		return
	var view: BattleEntityView = _get_entity_view(button)
	view.visible = true
	view.setup(entity)
	_views_by_entity_id[entity.entity_id] = view
	view.set_highlight(
		actionable and (
			_pending_mode == "target"
			or _pending_mode == "column"
			or _pending_mode == "place"
			or (_pending_mode == "choose" and _pending_candidates.has(entity))
			or (_pending_mode == "choose_spell" and _pending_candidates.has(entity))
			or (_pending_mode == "move_position" and actionable)
		)
	)
	button.text = ""
	_apply_empty_slot_style(button)
	button.disabled = false


func _rebuild_hand() -> void:
	for child: Node in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	if engine == null:
		return
	var state: BattlePlayerState = engine.players[player_side]
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card_display(player_side, index)
		if card == null:
			continue
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		_hand_row.add_child(tile)
		tile.setup(card, 0, "", false)
		tile.pressed.connect(_on_hand_pressed.bind(index))
		var disabled: bool = not _can_player_act()
		if engine.phase == BattleEngine.PHASE_SPELL and not (card.is_spell() or card.is_environment()):
			disabled = true
		if engine.effective_hand_cost(player_side, index) > int(state.energy):
			disabled = true
		tile.disabled = disabled


func _update_labels() -> void:
	_phase_label.text = _phase_text()
	_turn_label.text = "第 %d 回合" % engine.turn
	_end_phase_button.visible = _can_player_act()
	_update_timer_label()


func _update_timer_label() -> void:
	if not _time_limit_enabled:
		_timer_label.text = "不限时" if _can_player_act() else ""
		return
	if _can_player_act():
		_timer_label.text = "阶段剩余 %d 秒" % maxi(ceili(_phase_remaining), 0)
	else:
		_timer_label.text = ""


func _phase_text() -> String:
	if engine.winner != "":
		return "对局结束"
	match engine.phase:
		BattleEngine.PHASE_MULLIGAN:
			return "起手调度"
		BattleEngine.PHASE_HAND:
			return "z 出牌阶段" if engine.active_side == "z" else "p 出牌阶段"
		BattleEngine.PHASE_SPELL:
			return "z 锦囊/环境阶段"
		BattleEngine.PHASE_COMBAT:
			return "对战结算"
		BattleEngine.PHASE_TURN_END:
			return "回合结束"
		_:
			return ""


func _update_log() -> void:
	if engine.log_entries.is_empty():
		_log_label.text = ""
		return
	var start: int = maxi(engine.log_entries.size() - 2, 0)
	_log_label.text = "\n".join(engine.log_entries.slice(start))


func _can_player_act() -> bool:
	if engine == null or not _started or engine.winner != "":
		return false
	if engine.active_side != player_side:
		return false
	return engine.phase == BattleEngine.PHASE_HAND or engine.phase == BattleEngine.PHASE_SPELL


func _entity_at(column: int, side: String, slot: int) -> BattleEntity:
	for entity: BattleEntity in engine.entities:
		if entity.alive and entity.column == column and entity.side == side and entity.slot == slot:
			return entity
	return null


func _set_status(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.941, 0.549, 0.549) if is_error else Color(0.749, 0.780, 0.859),
	)


# ----- 主循环：计时 / AI -----

func _phase_key() -> String:
	if engine == null:
		return ""
	return "%s_%s_%d_%s" % [engine.phase, engine.active_side, engine.turn, engine.winner]


func _process(delta: float) -> void:
	_update_long_press(delta)
	if engine == null or not _started:
		return
	var key: String = _phase_key()
	if key != _last_phase_key:
		_last_phase_key = key
		_phase_remaining = mode.phase_time_limit_seconds
		_ai_accum = 0.0
		_clear_pending()
		_refresh_all()
		if engine.winner != "":
			return
	if engine.winner != "":
		return
	if engine.phase == BattleEngine.PHASE_SPECIAL:
		var enemy_state: BattlePlayerState = engine.players[enemy_side]
		if enemy_state.special_offer_id != 0:
			engine.special_resolve_hand(enemy_side)
			_refresh_all()
		return
	if _can_player_act():
		if _time_limit_enabled:
			_phase_remaining -= delta
			_update_timer_label()
			if _phase_remaining <= 0.0:
				_set_status("阶段时间到，自动结束。")
				_clear_pending()
				engine.end_phase(player_side)
	else:
		_ai_accum += delta
		if _ai_accum >= AI_INTERVAL and engine.active_side == enemy_side:
			if engine.phase == BattleEngine.PHASE_HAND or engine.phase == BattleEngine.PHASE_SPELL:
				_ai_accum = 0.0
				EasyBattleAI.take_action(engine, enemy_side)


func _on_animation_cue(trigger: String, actor: BattleEntity, target: Variant) -> void:
	if actor == null or actor.card == null or actor.card.animation_script == null:
		return
	if not actor.card.animation_script.has_trigger(trigger):
		return
	_animation_queue.append({"trigger": trigger, "actor": actor, "target": target})
	if not _animation_busy:
		_run_animation_queue()


func _run_animation_queue() -> void:
	_animation_busy = true
	while not _animation_queue.is_empty():
		var cue: Dictionary = _animation_queue.pop_front()
		await _play_animation_cue(cue)
	_animation_busy = false


func _play_animation_cue(cue: Dictionary) -> void:
	var actor: BattleEntity = cue.get("actor") as BattleEntity
	if actor == null or actor.card == null or actor.card.animation_script == null:
		return
	var instructions: Array = actor.card.animation_script.instructions_for(str(cue.get("trigger", "")))
	if instructions.is_empty():
		return
	var is_death: bool = str(cue.get("trigger", "")) == "die"
	var ghosts: Array[BattleEntityView] = []
	var longest_duration: float = 0.0
	for raw_instruction: Variant in instructions:
		if not raw_instruction is Dictionary:
			continue
		var instruction: Dictionary = raw_instruction
		match str(instruction.get("type", "")):
			"wait":
				var seconds: float = maxf(float(instruction.get("seconds", 0.0)), 0.0)
				if seconds > 0.0:
					await get_tree().create_timer(seconds).timeout
			"play_animation":
				var view: BattleEntityView = _resolve_animation_view(
					str(instruction.get("target", "self")), actor, cue.get("target"), ghosts, is_death
				)
				if view != null:
					longest_duration = maxf(
						longest_duration,
						view.play_animation(
							str(instruction.get("animation", "")),
							str(instruction.get("mode", "whole")),
						),
					)
			"play_fx":
				var fx_view: BattleEntityView = _resolve_animation_view(
					str(instruction.get("target", "self")), actor, cue.get("target"), ghosts, is_death
				)
				if fx_view != null:
					fx_view.play_fx(str(instruction.get("fx", "")))
	if longest_duration > 0.0:
		await get_tree().create_timer(longest_duration).timeout
	for ghost: BattleEntityView in ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()


func _resolve_animation_view(
	selector: String,
	actor: BattleEntity,
	target: Variant,
	ghosts: Array[BattleEntityView],
	force_ghost: bool = false,
) -> BattleEntityView:
	var entity: BattleEntity = null
	if selector == "target":
		if target is BattleEntity:
			entity = target
	else:
		entity = actor
	if entity == null:
		return null
	if not force_ghost and _views_by_entity_id.has(entity.entity_id):
		var view: BattleEntityView = _views_by_entity_id[entity.entity_id] as BattleEntityView
		if is_instance_valid(view) and view.is_visible_in_tree():
			return view
	var ghost: BattleEntityView = _create_ghost_view(entity)
	if ghost != null:
		ghosts.append(ghost)
	return ghost


func _create_ghost_view(entity: BattleEntity) -> BattleEntityView:
	var button: Button = _slot_button_for_entity(entity)
	if button == null:
		return null
	var ghost: BattleEntityView = ENTITY_VIEW_SCENE.instantiate() as BattleEntityView
	button.add_child(ghost)
	ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 5
	ghost.setup(entity)
	return ghost


func _slot_button_for_entity(entity: BattleEntity) -> Button:
	if entity.column < 0 or entity.column >= _board_columns.size():
		return null
	var column: Dictionary = _board_columns[entity.column]
	if entity.side == "z":
		return column.get("z_team" if entity.slot == BattleEngine.SLOT_TEAM_UP else "z_normal") as Button
	return column.get("p_team" if entity.slot == BattleEngine.SLOT_TEAM_UP else "p_normal") as Button


func _refresh_special_overlay() -> void:
	if engine == null:
		_special_overlay.visible = false
		return
	if engine.phase != BattleEngine.PHASE_SPECIAL:
		_special_overlay.visible = false
		return
	var state: BattlePlayerState = engine.players[player_side]
	if state.special_offer_id == 0:
		if _special_overlay.visible:
			_special_hint.text = "等待对方完成超能力选择…"
			_special_play_button.visible = false
			_special_hand_button.visible = false
			_special_overlay.visible = true
		return
	if _special_card_tile != null and is_instance_valid(_special_card_tile):
		_special_card_tile.queue_free()
		_special_card_tile = null
	for child: Node in _special_card_slot.get_children():
		child.queue_free()
	var index: int = state.find_hand_index(state.special_offer_id)
	var card: CardData = engine.hand_card_display(player_side, index)
	if card == null:
		_special_overlay.visible = false
		return
	var tile: CardTile = CARD_TILE_SCENE.instantiate()
	_special_card_slot.add_child(tile)
	tile.setup(card, 0, "特殊回合 · 费用 -1")
	tile.disabled = true
	tile.position = Vector2(maxf((_special_card_slot.size.x - 160.0) * 0.5, 0.0), 0.0)
	_special_card_tile = tile
	_special_hint.text = "你获得了一张临时费用 -1 的超能力牌（当前费用 %d）；立刻打出或移入手牌，选择后特殊回合结束。" % engine.effective_hand_cost(player_side, index)
	_special_play_button.visible = true
	_special_hand_button.visible = true
	_special_overlay.visible = not _special_target_mode


func _on_special_play_pressed() -> void:
	var state: BattlePlayerState = engine.players[player_side]
	var index: int = state.find_hand_index(state.special_offer_id)
	var card: CardData = engine.hand_card(player_side, index)
	if card == null:
		return
	_pending_card_index = index
	var requirement: Dictionary = _card_multi_target_requirement(card)
	if int(requirement.get("count", 0)) > 0:
		_special_target_mode = true
		_pending_mode = "choose_spell"
		_pending_handles.clear()
		_pending_candidates = engine.choose_candidates(str(requirement.get("selector", "")), player_side)
		_special_overlay.visible = false
		_set_status("最多选择 %d 个超能力目标，然后点击“确认目标”。" % int(requirement.get("count", 0)))
		_refresh_all()
		return
	if engine.card_needs_target(card):
		_special_target_mode = true
		_pending_mode = "target"
		_pending_candidates = engine.target_candidates(card, player_side)
		_special_overlay.visible = false
		_set_status("请选择超能力目标。")
		_refresh_all()
		return
	_resolve_special_target({})


func _on_special_hand_pressed() -> void:
	var result: Dictionary = engine.special_resolve_hand(player_side)
	_set_status(str(result.get("message", "")), not bool(result.get("ok", false)))
	_clear_pending()
	_refresh_all()


func _resolve_special_target(target: Dictionary) -> void:
	if _try_begin_move_position(target):
		return
	var result: Dictionary = engine.special_resolve_play(player_side, target)
	_set_status(str(result.get("message", "")), not bool(result.get("ok", false)))
	_clear_pending()
	_refresh_all()


func _on_game_finished(winner_side: String) -> void:
	_game_over_overlay.visible = true
	if winner_side == player_side:
		_game_over_label.text = "胜利！"
	else:
		_game_over_label.text = "失败……"


## 设置界面（战斗内）的投降按钮调用。
func surrender_player() -> void:
	if engine == null or engine.winner != "":
		return
	engine.surrender(player_side)
	_refresh_all()


func _on_return_after_game_pressed() -> void:
	BattleManager.clear_current_battle()
	GameState.go_to_battle_prep()


func _show_fatal(message: String) -> void:
	_started = false
	_game_over_overlay.visible = true
	_game_over_label.text = message

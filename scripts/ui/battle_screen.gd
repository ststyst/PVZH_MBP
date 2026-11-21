extends Control
## 战斗界面（电脑随机卡组对战）：
## - 起手调度（每张牌可刷新一次）
## - 5 列 × 双方各 2 位（普通位 / 组队位）；点击组队实体可与同列另一实体换位
## - 阶段：z 出牌 → p 出牌 → z 锦囊/环境 → 逐列战斗 → 回合结束
## - 简单 AI：优先打出费用最高的可打出手牌，目标随机

const CARD_TILE_SCENE: PackedScene = preload("res://scenes/cards/CardTile.tscn")
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
@onready var _hand_row: HBoxContainer = %HandRow
@onready var _mulligan_overlay: Control = %MulliganOverlay
@onready var _mulligan_row: HBoxContainer = %MulliganRow
@onready var _mulligan_confirm_button: Button = %MulliganConfirmButton
@onready var _game_over_overlay: Control = %GameOverOverlay
@onready var _game_over_label: Label = %GameOverLabel
@onready var _game_over_back_button: Button = %GameOverBackButton

var _board_columns: Array[Dictionary] = []
var _mulligan_used: Array[bool] = []
var _empty_slot_style: StyleBoxEmpty = null
var _highlight_slot_style: StyleBoxFlat = null


func _ready() -> void:
	_init_slot_styles()
	_collect_board_columns()
	_enemy_hero_button.pressed.connect(_on_enemy_hero_pressed)
	_player_hero_button.pressed.connect(_on_player_hero_pressed)
	_end_phase_button.pressed.connect(_on_end_phase_pressed)
	_mulligan_confirm_button.pressed.connect(_on_mulligan_confirm_pressed)
	_game_over_back_button.pressed.connect(_on_return_after_game_pressed)
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
	engine.changed.connect(_on_engine_changed)
	engine.game_finished.connect(_on_game_finished)
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
		z_team.pressed.connect(_on_slot_pressed.bind("z", index, BattleEngine.SLOT_TEAM_UP))
		z_normal.pressed.connect(_on_slot_pressed.bind("z", index, BattleEngine.SLOT_NORMAL))
		p_normal.pressed.connect(_on_slot_pressed.bind("p", index, BattleEngine.SLOT_NORMAL))
		p_team.pressed.connect(_on_slot_pressed.bind("p", index, BattleEngine.SLOT_TEAM_UP))
		for button: Button in [z_team, z_normal, p_normal, p_team]:
			button.text = ""
			_apply_empty_slot_style(button)
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


func _clear_slot_style(button: Button) -> void:
	button.flat = false
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.remove_theme_stylebox_override(state)
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
		var card: CardData = engine.hand_card(player_side, index)
		if card == null:
			continue
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		_mulligan_row.add_child(column)
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		column.add_child(tile)
		tile.setup(card, 0, "费用 %d" % card.cost)
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
	var card: CardData = engine.hand_card(player_side, index)
	if card == null:
		return
	if engine.phase == BattleEngine.PHASE_SPELL and not (card.is_spell() or card.is_environment()):
		_set_status("锦囊/环境阶段不能打出实体牌。", true)
		return
	if card.cost > int(engine.players[player_side].energy):
		_set_status("费用不足。", true)
		return
	if card.is_entity():
		_pending_card_index = index
		_pending_mode = "place"
		_pending_candidates.clear()
		_set_status("请选择放置位置（组队牌只能放组队位）。")
		_refresh_all()
	elif card.is_environment():
		_pending_card_index = index
		_pending_mode = "column"
		_pending_candidates.clear()
		_set_status("请选择一列，将其环境变为这张环境牌。")
		_refresh_all()
	elif engine.card_needs_target(card):
		_pending_card_index = index
		_pending_mode = "target"
		_pending_candidates = engine.target_candidates(card, player_side)
		_set_status("请选择目标（★标记）。")
		_refresh_all()
	else:
		_play_pending({})


func _on_slot_pressed(side: String, column: int, slot: int) -> void:
	if not _started or engine == null:
		return
	if _pending_mode == "place" and side == player_side:
		_play_pending({"column": column, "slot": slot})
		return
	if _pending_mode == "column":
		if side == player_side:
			_play_pending({"column": column})
		return
	if _pending_mode == "target":
		var entity: BattleEntity = _entity_at(column, side, slot)
		if entity != null and _pending_candidates.has(entity):
			_play_pending({"handle": entity})
		else:
			_set_status("该位置不是合法目标。", true)
		return
	var own_entity: BattleEntity = _entity_at(column, side, slot)
	if side == player_side and own_entity != null and own_entity.team_up:
		if engine.swap_team_up(player_side, own_entity):
			_set_status("已交换位置。")
			_refresh_all()
		else:
			_set_status("这一列没有可交换的另一实体。", true)
		return
	_set_status("先点击手牌选择要打出的牌。")


func _on_enemy_hero_pressed() -> void:
	_on_hero_target(enemy_side)


func _on_player_hero_pressed() -> void:
	_on_hero_target(player_side)


func _on_hero_target(side: String) -> void:
	if _pending_mode == "target" and _pending_candidates.has(engine.hero_handle(side)):
		_play_pending({"handle": engine.hero_handle(side)})
		return
	_set_status("这不是当前可选择的英雄目标。")


func _play_pending(target: Dictionary) -> void:
	if _pending_card_index < 0:
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


func _update_hero_bars() -> void:
	var player_state: BattlePlayerState = engine.players[player_side]
	var enemy_state: BattlePlayerState = engine.players[enemy_side]
	_player_hero_button.text = "%s（%s） 生命 %d/%d · 费用 %d/%d" % [
		player_state.hero.display_name(), player_side.to_upper(),
		player_state.hero_health, player_state.hero_max_health,
		player_state.energy, player_state.energy_cap,
	]
	_enemy_hero_button.text = "%s（%s） 生命 %d/%d · 费用 %d/%d" % [
		enemy_state.hero.display_name(), enemy_side.to_upper(),
		enemy_state.hero_health, enemy_state.hero_max_health,
		enemy_state.energy, enemy_state.energy_cap,
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
	else:
		actionable = entity != null and entity.side == player_side and entity.team_up
	if entity == null:
		button.text = ""
		if actionable and (_pending_mode == "place" or _pending_mode == "column"):
			_apply_highlight_slot_style(button)
			button.disabled = false
		else:
			_apply_empty_slot_style(button)
			button.disabled = true
		return
	button.text = "%s\n⚔%d ♥%d" % [entity.display_name(), entity.attack, entity.health]
	if entity.shield > 0:
		button.text += " 🛡%d" % entity.shield
	if _pending_mode == "target" and actionable:
		button.text = "★" + button.text
	if actionable and _pending_mode == "column":
		_apply_highlight_slot_style(button)
	else:
		_clear_slot_style(button)
	button.disabled = not actionable


func _rebuild_hand() -> void:
	for child: Node in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	if engine == null:
		return
	var state: BattlePlayerState = engine.players[player_side]
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card(player_side, index)
		if card == null:
			continue
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		_hand_row.add_child(tile)
		tile.setup(card, 0, "费用 %d" % card.cost)
		tile.pressed.connect(_on_hand_pressed.bind(index))
		var disabled: bool = not _can_player_act()
		if engine.phase == BattleEngine.PHASE_SPELL and not (card.is_spell() or card.is_environment()):
			disabled = true
		if card.cost > int(state.energy):
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


func _on_game_finished(winner_side: String) -> void:
	_game_over_overlay.visible = true
	if winner_side == player_side:
		_game_over_label.text = "胜利！"
	else:
		_game_over_label.text = "失败……"


func _on_return_after_game_pressed() -> void:
	BattleManager.clear_current_battle()
	GameState.go_to_battle_prep()


func _show_fatal(message: String) -> void:
	_started = false
	_game_over_overlay.visible = true
	_game_over_label.text = message

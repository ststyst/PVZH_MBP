extends Control
## 战斗界面（电脑随机卡组对战）：
## - 起手调度（每张牌可刷新一次）
## - 5 列 × 双方各 2 位（普通位 / 组队位）；点击组队实体可与同列另一实体换位
## - 阶段：z 出牌 → p 出牌 → z 锦囊/环境 → 逐列战斗 → 回合结束
## - 简单 AI：优先打出费用最高的可打出手牌，目标随机

const CARD_TILE_SCENE: PackedScene = preload("res://scenes/cards/CardTile.tscn")
const ENTITY_VIEW_SCENE: PackedScene = preload("res://scenes/battle/BattleEntityView.tscn")
const AI_INTERVAL: float = 0.7
## 逐列战斗结算时，两列之间的停顿（秒），避免动画一列接一列糊在一起。
const COMBAT_COLUMN_GAP: float = 0.2
## 等待动画队列播完的上限（秒）：动画异常（循环/缺失时长）时兜底，避免战斗卡死。
const ANIMATION_WAIT_TIMEOUT: float = 8.0
## 实体位移动画期间，临时抬高「该实体所在列」的层级（跨列扑击不被相邻列压住）。
const MOTION_COLUMN_Z_INDEX: int = 30
## 攻击动画期间攻击方视图/列/棋盘的临时层级：保证盖住受击方（播完还原）。
const ATTACK_ACTOR_Z_INDEX: int = 40
## 环境 id -> 每列背景图路径（留空 = 不显示）。其它环境仍可用
## set_environment_background_path() 在运行时动态注册。
const ENVIRONMENT_BACKGROUND_PATHS: Dictionary = {
	"highground": "res://assets/battle/backgrounds/columns/high_ground.png",
	"default": "res://assets/battle/backgrounds/columns/default.png",
	"water": "res://assets/battle/backgrounds/columns/pool.png",
	"sunny_field": "",
	"flooded_garden": "",
}

signal battle_background_changed(texture: Texture2D)
## 某列环境变化（被新环境覆盖或被清除），供外部刷新该列环境背景。
signal column_environment_changed(
	column: int, environment_id: String, environment_label: String, owner_side: String
)

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
# 敌我双方英雄数值都拆成独立节点（编辑器里可自由摆放，只显示数字）。
@onready var _enemy_health_label: Label = %EnemyHealthLabel
@onready var _enemy_energy_label: Label = %EnemyEnergyLabel
@onready var _enemy_shield_label: Label = %EnemyShieldLabel
@onready var _enemy_shield_durability_label: Label = %EnemyShieldDurabilityLabel
@onready var _player_health_label: Label = %PlayerHealthLabel
@onready var _player_energy_label: Label = %PlayerEnergyLabel
@onready var _player_shield_label: Label = %PlayerShieldLabel
@onready var _player_shield_durability_label: Label = %PlayerShieldDurabilityLabel
@onready var _board: HBoxContainer = %Board
@onready var _phase_label: Label = %PhaseLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _status_label: Label = %StatusLabel
@onready var _end_phase_button: Button = %EndPhaseButton
@onready var _confirm_targets_button: Button = %ConfirmTargetsButton
@onready var _hand_row: HBoxContainer = %HandRow
@onready var _hand_scroll: ScrollContainer = %HandScroll
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
@onready var _spell_toast: Label = %SpellToast
@onready var _battle_background_image: TextureRect = %BattleBackgroundImage
@onready var _board_art_area: Control = %BoardArtArea
@onready var _enemy_hero_art: TextureRect = %EnemyHeroArtArea
@onready var _player_hero_art: TextureRect = %PlayerHeroArtArea
@onready var _hand_safe_area: Control = %HandSafeArea
@onready var _enemy_hero_target_area: Control = %EnemyHeroTargetArea
@onready var _player_hero_target_area: Control = %PlayerHeroTargetArea

var _board_columns: Array[Dictionary] = []
var _slot_highlights: Dictionary = {}
## 环境 id -> 该列背景图（按需注册，未注册的环境显示为空）。
var _environment_backgrounds: Dictionary = {}
var _mulligan_used: Array[bool] = []
var _hand_drag_index: int = -1
var _hand_drag_active: bool = false
var _hand_drag_started: bool = false
var _hand_drag_start_position: Vector2 = Vector2.ZERO
var _suppress_hand_click: bool = false
var _spell_toast_remaining: float = 0.0
var _entity_views: Dictionary = {}


## 运行时切换战斗背景；传 null 清空背景图。
func set_battle_background(texture: Texture2D) -> void:
	if _battle_background_image == null:
		return
	_battle_background_image.texture = texture
	battle_background_changed.emit(texture)


func set_battle_background_path(path: String) -> void:
	if path.is_empty():
		set_battle_background(null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_battle_background(texture)


func clear_battle_background() -> void:
	set_battle_background(null)


func get_battle_background() -> Texture2D:
	return _battle_background_image.texture if _battle_background_image != null else null


## 替换 90% × 60% 棋盘区域素材。
func set_board_art(texture: Texture2D) -> void:
	if _board_art_area == null:
		return
	var art: TextureRect = _board_art_area.get_node_or_null("BoardArtTexture") as TextureRect
	if art != null:
		art.texture = texture


func set_board_art_path(path: String) -> void:
	if path.is_empty():
		set_board_art(null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_board_art(texture)


func set_hero_art(side: String, texture: Texture2D) -> void:
	var target: TextureRect = _player_hero_art if side == player_side else _enemy_hero_art
	if target != null:
		target.texture = texture


func set_hero_art_path(side: String, path: String) -> void:
	if path.is_empty():
		set_hero_art(side, null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_hero_art(side, texture)
var _views_by_entity_id: Dictionary = {}
var _animation_queue: Array[Dictionary] = []
var _animation_busy: bool = false
## 攻击动画期间临时抬层的实体视图（键 = BattleEntityView）。
## _update_slot_button 刷新时会跳过这些视图的 z_index，否则会盖不住受击方。
var _layer_raised_views: Dictionary = {}
## 手牌实例状态变了（费用/攻击加成），等下一帧统一重建手牌。
var _hand_dirty: bool = false
## 逐列战斗驱动协程是否正在运行（防止重复启动）。
var _combat_sequence_running: bool = false
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
	engine.protected_environments = ServerConfig.protected_environments()
	engine.environment_keyword_filters = ServerConfig.environment_keyword_filters()
	# 逐列结算：每列的战斗结算 + 该列动画全部播完后，才推进下一列。
	engine.combat_step_mode = true
	engine.changed.connect(_on_engine_changed)
	engine.spell_played.connect(_on_spell_played)
	engine.game_finished.connect(_on_game_finished)
	engine.animation_cue.connect(_on_animation_cue)
	engine.combat_phase_started.connect(_on_combat_phase_started)
	engine.environment_changed.connect(_on_engine_environment_changed)
	# 数值变化（掉血/加攻/治疗/词缀）不会发 changed，必须单独监听，否则实体面板上的
	# 生命/攻击要等到下一次阶段或列结算才更新。
	engine.display_state_changed.connect(_on_display_state_changed)
	# 英雄掉血同理不会发 changed（只发 hero_damaged）。
	engine.hero_damaged.connect(_on_hero_damaged)
	engine.setup(
		player_side,
		player_hero,
		_to_string_array(setup.get("player_deck_ids", [])),
		enemy_hero,
		_to_string_array(setup.get("enemy_deck_ids", [])),
		mode,
	)
	engine.confirm_mulligan(enemy_side)
	_register_configured_environment_backgrounds()
	refresh_column_environment_backgrounds()
	_show_mulligan()


func _to_string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for entry: Variant in raw:
			result.append(str(entry))
	return result

# ----- 场景节点初始化 -----

func _build_board_columns() -> void:
	for column_index: int in range(BattleEngine.COLUMN_COUNT):
		var column := Control.new()
		column.name = "Column%d" % (column_index + 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var background := TextureRect.new()
		background.name = "EnvironmentBackground"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		column.add_child(background)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.add_theme_constant_override("separation", 2)
		var env_label := Label.new()
		env_label.name = "EnvLabel"
		env_label.custom_minimum_size = Vector2(0, 16)
		env_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		env_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		env_label.add_theme_font_size_override("font_size", 9)
		env_label.text = "第%d列" % (column_index + 1)
		content.add_child(env_label)
		for side_slot: Array in [
			["z", "ZTeamButton", BattleEngine.SLOT_TEAM_UP],
			["z", "ZNormalButton", BattleEngine.SLOT_NORMAL],
			["p", "PNormalButton", BattleEngine.SLOT_NORMAL],
			["p", "PTeamButton", BattleEngine.SLOT_TEAM_UP],
		]:
			var button := Button.new()
			button.name = str(side_slot[1])
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.size_flags_vertical = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 0)
			button.add_theme_font_size_override("font_size", 10)
			button.clip_text = true
			button.text = ""
			content.add_child(button)
		column.add_child(content)
		_board.add_child(column)


func _collect_board_columns() -> void:
	_board_columns.clear()
	if _board.get_child_count() == 0:
		_build_board_columns()
	for index: int in range(_board.get_child_count()):
		var column: Control = _board.get_child(index) as Control
		if column == null:
			continue
		var content: VBoxContainer = column.get_node_or_null("Content") as VBoxContainer
		if content == null:
			continue
		var background: TextureRect = column.get_node_or_null("EnvironmentBackground") as TextureRect
		var environment_label: Label = content.get_node("EnvLabel") as Label
		var z_team: Button = content.get_node("ZTeamButton") as Button
		var z_normal: Button = content.get_node("ZNormalButton") as Button
		var p_normal: Button = content.get_node("PNormalButton") as Button
		var p_team: Button = content.get_node("PTeamButton") as Button
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
			"background": background,
			"z_team": z_team,
			"z_normal": z_normal,
			"p_normal": p_normal,
			"p_team": p_team,
		})


# ----- 每列环境背景接口 -----

## 注册某个环境 id 的背景图；注册后立即刷新所有列。
func set_environment_background(environment_id: String, texture: Texture2D) -> void:
	if environment_id.is_empty():
		return
	if texture == null:
		_environment_backgrounds.erase(environment_id)
	else:
		_environment_backgrounds[environment_id] = texture
	refresh_column_environment_backgrounds()


## 注册环境背景图（资源路径）；传空路径等同于清除该环境的背景。
func set_environment_background_path(environment_id: String, path: String) -> void:
	if path.is_empty():
		set_environment_background(environment_id, null)
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		set_environment_background(environment_id, texture)


## 清空所有已注册的环境背景图，并刷新所有列。
func clear_environment_backgrounds() -> void:
	_environment_backgrounds.clear()
	refresh_column_environment_backgrounds()


## 取得某一列的环境背景节点（column 从 0 开始）；越界返回 null。
func get_column_environment_background(column: int) -> TextureRect:
	if column < 0 or column >= _board_columns.size():
		return null
	return _board_columns[column].get("background", null) as TextureRect


## 按当前环境刷新所有列背景；通常在外部注册完全部环境图后调用。
func refresh_column_environment_backgrounds() -> void:
	if engine == null:
		return
	for column: int in range(_board_columns.size()):
		_apply_column_environment_background(column, str(engine.environments[column]))


## 读取 ENVIRONMENT_BACKGROUND_PATHS 中的非空路径并注册（启动时调用一次）。
func _register_configured_environment_backgrounds() -> void:
	for environment_id: String in ENVIRONMENT_BACKGROUND_PATHS.keys():
		var path: String = str(ENVIRONMENT_BACKGROUND_PATHS[environment_id])
		if path.is_empty():
			continue
		set_environment_background_path(environment_id, path)


func _apply_column_environment_background(column: int, environment_id: String) -> void:
	var background: TextureRect = get_column_environment_background(column)
	if background == null:
		return
	var texture: Texture2D = _environment_backgrounds.get(environment_id, null) as Texture2D
	background.texture = texture
	background.visible = texture != null


func _on_engine_environment_changed(
	column: int, environment_id: String, environment_label: String, owner_side: String
) -> void:
	_apply_column_environment_background(column, environment_id)
	column_environment_changed.emit(column, environment_id, environment_label, owner_side)


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
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entity_views[button] = view
	return view


## 场上实体显示层级：列越靠右越高；同列内越靠下越高，保证超格背景/插画互相遮挡正确。
func _entity_view_z_index(column: int, side: String, slot: int) -> int:
	var row_from_top: int
	if side == "z":
		row_from_top = 0 if slot == BattleEngine.SLOT_TEAM_UP else 1
	else:
		row_from_top = 2 if slot == BattleEngine.SLOT_NORMAL else 3
	return column * 4 + row_from_top + 1
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
	_mulligan_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mulligan_row.custom_minimum_size = Vector2(600, 0)
	var columns: Array[VBoxContainer] = []
	for _column_index: int in range(2):
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(126, 0)
		column.add_theme_constant_override("separation", 28)
		_mulligan_row.add_child(column)
		columns.append(column)
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card_display(player_side, index)
		if card == null:
			continue
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)
		columns[index % 2].add_child(entry)
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		entry.add_child(tile)
		tile.setup(card, 0, "", false, true, engine.get_card(card.card_id))
		var refresh := Button.new()
		refresh.text = "刷新"
		refresh.disabled = index < _mulligan_used.size() and _mulligan_used[index]
		refresh.custom_minimum_size = Vector2(0, 36)
		refresh.pressed.connect(_on_mulligan_refresh_pressed.bind(index))
		entry.add_child(refresh)


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

func _on_hand_tile_gui_input(event: InputEvent, index: int) -> void:
	if not _can_player_act() or _pending_mode != "":
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_hand_drag_index = index
			_hand_drag_active = true
			_hand_drag_started = false
			_hand_drag_start_position = get_global_mouse_position()
		elif _hand_drag_active:
			_hand_drag_active = false
			if _hand_drag_started:
				_suppress_hand_click = true
				_hand_drag_started = false
				_hand_drag_index = -1
				_on_hand_drag_drop(index, get_global_mouse_position())
			else:
				_hand_drag_index = -1
	elif event is InputEventMouseMotion and _hand_drag_active:
		var distance: float = get_global_mouse_position().distance_to(_hand_drag_start_position)
		if distance >= 12.0:
			_hand_drag_started = true
			_set_status("拖动到合法位置后松开即可打出。")


func _on_hand_drag_drop(index: int, global_position: Vector2) -> void:
	if _hand_safe_area != null and _hand_safe_area.get_global_rect().has_point(global_position):
		_set_status("仍在手牌安全区域，未打出。", true)
		return
	var board_target: Dictionary = _board_drop_target(global_position)
	var hero_side: String = _hero_drop_side(global_position)
	if board_target.is_empty() and hero_side.is_empty():
		_set_status("松手位置不在战斗棋盘内。", true)
		return
	var card: CardData = engine.hand_card_display(player_side, index)
	if card == null:
		return
	if engine.phase == BattleEngine.PHASE_HAND and engine.active_side == "z" and not card.is_entity():
		_set_status("Z 方实体牌阶段只能打出实体牌。", true)
		return
	if engine.phase == BattleEngine.PHASE_SPELL and not (
		card.is_spell() or card.is_environment() or (card.is_entity() and card.has_keyword("spell_phase_entity"))
	):
		_set_status("当前阶段不能打出这张牌。", true)
		return
	if engine.effective_hand_cost(player_side, index) > int(engine.players[player_side].energy):
		_set_status("费用不足。", true)
		return
	if card.is_entity():
		var requirement: Dictionary = card.ability_script.target_requirement() if card.ability_script != null else {}
		if int(requirement.get("count", 0)) > 0:
			_set_status("该实体入场需要先选择能力目标，请点击手牌选择目标。", true)
			return
		if board_target.is_empty():
			_set_status("实体牌需要拖到合法放置位置。", true)
			return
		_pending_card_index = index
		_play_pending({"column": int(board_target.get("column", -1)), "slot": int(board_target.get("slot", -1))})
		return
	if card.is_environment():
		if board_target.is_empty():
			_set_status("环境牌需要拖到某一列。", true)
			return
		_pending_card_index = index
		_play_pending({"column": int(board_target.get("column", -1))})
		return
	if card.ability_script != null and card.ability_script.column_requirement():
		if board_target.is_empty():
			_set_status("这张锦囊需要拖到某一列。", true)
			return
		_pending_card_index = index
		_play_pending({"column": int(board_target.get("column", -1))})
		return
	var requirement: Dictionary = _card_multi_target_requirement(card)
	if int(requirement.get("count", 0)) > 0:
		var first_handle: Variant = board_target.get("entity", null)
		if first_handle == null and not hero_side.is_empty():
			first_handle = engine.hero_handle(hero_side)
		if first_handle == null:
			_set_status("请拖到第一个合法目标上。", true)
			return
		_pending_card_index = index
		_pending_mode = "choose_spell"
		_pending_handles = [first_handle]
		_pending_candidates = engine.choose_candidates(
			str(requirement.get("selector", "")), player_side, true
		)
		if _has_remaining_choose_candidates():
			_set_status("已选择第一个目标，请继续选择或点击确认。")
			_refresh_all()
		else:
			_on_confirm_targets_pressed()
		return
	if engine.card_needs_target(card):
		var handle: Variant = board_target.get("entity", null)
		if handle == null and not hero_side.is_empty():
			handle = engine.hero_handle(hero_side)
		if handle == null:
			_set_status("请拖到合法目标上。", true)
			return
		_pending_card_index = index
		_play_pending({"handle": handle})
		return
	# 无目标、随机目标、全体目标法术：拖到棋盘任意位置即可施放。
	_pending_card_index = index
	_play_pending({})


func _board_drop_target(global_position: Vector2) -> Dictionary:
	for column: int in range(_board_columns.size()):
		var info: Dictionary = _board_columns[column]
		for key: String in ["z_team", "z_normal", "p_normal", "p_team"]:
			var button: Button = info.get(key, null) as Button
			if button == null or not button.get_global_rect().has_point(global_position):
				continue
			var side: String = "z" if key.begins_with("z") else "p"
			var slot: int = BattleEngine.SLOT_TEAM_UP if key.ends_with("team") else BattleEngine.SLOT_NORMAL
			return {
				"column": column,
				"slot": slot,
				"side": side,
				"entity": _entity_at(column, side, slot),
			}
	return {}


func _hero_drop_side(global_position: Vector2) -> String:
	if _enemy_hero_target_area != null and _enemy_hero_target_area.get_global_rect().has_point(global_position):
		return enemy_side
	if _player_hero_target_area != null and _player_hero_target_area.get_global_rect().has_point(global_position):
		return player_side
	if _enemy_hero_button.get_global_rect().has_point(global_position):
		return enemy_side
	if _player_hero_button.get_global_rect().has_point(global_position):
		return player_side
	return ""


func _has_remaining_choose_candidates() -> bool:
	for candidate: Variant in _pending_candidates:
		if _pending_handles.has(candidate):
			continue
		if candidate is BattleEntity and candidate.is_alive():
			return true
		if candidate is String:
			return true
	return false


func _on_hand_pressed(index: int) -> void:
	if _suppress_hand_click:
		_suppress_hand_click = false
		return
	if _pending_mode != "":
		_set_status("请先完成当前目标选择。", true)
		return
	if not _can_player_act():
		_set_status("现在不是你的出牌阶段。", true)
		return
	var card: CardData = engine.hand_card_display(player_side, index)
	if card == null:
		return
	if engine.phase == BattleEngine.PHASE_HAND and engine.active_side == "z" and not card.is_entity():
		_set_status("Z 方实体牌阶段只能打出实体牌。", true)
		return
	if engine.phase == BattleEngine.PHASE_SPELL and not (
		card.is_spell() or card.is_environment() or (card.is_entity() and card.has_keyword("spell_phase_entity"))
	):
		_set_status("当前阶段不能打出这张牌。", true)
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
			var selector: String = str(requirement.get("selector", "other_allies"))
			_pending_candidates = engine.choose_candidates(selector, player_side)
			# 排除当前未入场实体不可能存在的自身引用。
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
	elif card.ability_script != null and card.ability_script.column_requirement():
		_pending_card_index = index
		_pending_mode = "column_spell"
		_pending_handles.clear()
		_pending_candidates.clear()
		_set_status("请选择一列打出这张锦囊。")
		_refresh_all()
	elif _card_multi_target_requirement(card).get("count", 0) > 0:
		_pending_card_index = index
		_pending_mode = "choose_spell"
		_pending_handles.clear()
		var requirement: Dictionary = _card_multi_target_requirement(card)
		var selector: String = str(requirement.get("selector", ""))
		_pending_candidates = engine.choose_candidates(selector, player_side, card.is_spell())
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


func _on_spell_played(side: String, card: CardData) -> void:
	if side == player_side or card == null:
		return
	_spell_toast.text = card.description
	_spell_toast.visible = true
	_spell_toast_remaining = ServerConfig.spell_toast_duration()


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
	if _long_press_entity.has_buff("buried") and _long_press_entity.side != player_side:
		_long_press_entity = null
		_long_press_fired = false
		_set_status("无法查看敌方墓碑内的实体信息。", true)
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
	if _pending_mode == "column_spell":
		var column_target: Dictionary = {"column": column}
		if _special_target_mode:
			_resolve_special_target(column_target)
		else:
			_play_pending(column_target)
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
			if not _has_remaining_choose_candidates():
				_on_confirm_targets_pressed()
				return
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
			if not _has_remaining_choose_candidates():
				_pending_mode = "place"
				_set_status("没有其他合法目标；请点击放置位置。")
			elif required_count > 0 and _pending_handles.size() >= required_count:
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
	if _pending_mode == "choose_spell" and _pending_candidates.has(engine.hero_handle(side)):
		var hero_handle: String = engine.hero_handle(side)
		if _pending_handles.has(hero_handle):
			_pending_handles.erase(hero_handle)
		else:
			var limit: int = int(_card_multi_target_requirement(
				engine.hand_card(player_side, _pending_card_index)
			).get("count", 0))
			if _pending_handles.size() < limit:
				_pending_handles.append(hero_handle)
		_set_status("已选择 %d 个目标；点击“确认目标”结算。" % _pending_handles.size())
		if not _has_remaining_choose_candidates():
			_on_confirm_targets_pressed()
			return
		_refresh_all()
		return
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
	if _pending_mode != "":
		_set_status("请先完成目标选择或取消当前出牌。", true)
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

func _align_layout_to_art() -> void:
	if _board == null:
		return
	# 背景素材区跟随真实 UI 控件，而不是反过来用素材区决定布局。
	_align_control_rect(_board_art_area, _board)
	_align_control_rect(_enemy_hero_art, _enemy_hero_button)
	_align_control_rect(_player_hero_art, _player_hero_button)
	var hand_placeholder: Control = get_node_or_null("Background/ArtPlaceholders/HandScroll") as Control
	_align_control_rect(hand_placeholder, _hand_scroll)
	_align_control_rect(_hand_safe_area, _hand_scroll)
	_align_control_rect(_enemy_hero_target_area, _enemy_hero_button)
	_align_control_rect(_player_hero_target_area, _player_hero_button)


func _align_control_rect(target: Control, source: Control) -> void:
	if target == null or source == null:
		return
	target.global_position = source.global_position
	target.size = source.size


func _on_engine_changed() -> void:
	_refresh_all()


## 某个实体/手牌实例的显示状态变了（掉血、加攻、获得词缀、手牌费用修正…）：
## - 实体：只刷新那一个实体视图，不重建整屏（也不会打断正在播的动画）；
## - 手牌实例：标记脏，由 _process 每帧最多重建一次手牌（费用/攻击加成会变）。
func _on_display_state_changed(handle: Variant) -> void:
	if engine == null:
		return
	if not (handle is BattleEntity):
		_hand_dirty = true
		return
	var entity: BattleEntity = handle
	var view: BattleEntityView = _views_by_entity_id.get(entity.entity_id, null) as BattleEntityView
	if view == null or not is_instance_valid(view):
		return
	view.refresh_stats(entity)


## 英雄受伤不发 changed，这里单独刷新双方英雄行（生命/充能/耐久/费用）。
func _on_hero_damaged(_side: String, _amount: int, _source_keywords: Array) -> void:
	if engine == null:
		return
	_update_hero_bars()


func _refresh_all() -> void:
	if engine == null:
		return
	_update_hero_bars()
	_update_board()
	_rebuild_hand()
	_update_labels()
	_update_confirm_targets_button()
	_refresh_special_overlay()


func _update_hero_bars() -> void:
	var player_state: BattlePlayerState = engine.players[player_side]
	var enemy_state: BattlePlayerState = engine.players[enemy_side]
	_player_hero_button.text = "%s（%s）" % [player_state.hero.display_name(), player_side.to_upper()]
	_enemy_hero_button.text = "%s（%s）" % [enemy_state.hero.display_name(), enemy_side.to_upper()]
	# 双方数值只写数字，位置/字号/颜色全部交给场景里的独立节点。
	_player_health_label.text = str(player_state.hero_health)
	_player_energy_label.text = str(int(player_state.energy))
	_player_shield_label.text = str(player_state.charge_shield)
	_player_shield_durability_label.text = str(player_state.charge_shield_durability)
	_enemy_health_label.text = str(enemy_state.hero_health)
	# 敌方费用按"可见费用"显示（与原先汇总文字口径一致）。
	_enemy_energy_label.text = str(engine.visible_energy_for(enemy_side, player_side))
	_enemy_shield_label.text = str(enemy_state.charge_shield)
	_enemy_shield_durability_label.text = str(enemy_state.charge_shield_durability)
	_player_info_label.text = "手牌 %d · 牌库 %d" % [player_state.hand_count(), player_state.deck_count()]
	_enemy_info_label.text = "手牌 %d · 牌库 %d" % [enemy_state.hand_count(), enemy_state.deck_count()]
	var player_targetable: bool = (
		_pending_mode in ["target", "choose_spell"]
		and _pending_candidates.has(engine.hero_handle(player_side))
	)
	var enemy_targetable: bool = (
		_pending_mode in ["target", "choose_spell"]
		and _pending_candidates.has(engine.hero_handle(enemy_side))
	)
	_player_hero_button.modulate = Color(1.15, 1.08, 0.55, 1) if player_targetable else Color.WHITE
	_enemy_hero_button.modulate = Color(1.15, 1.08, 0.55, 1) if enemy_targetable else Color.WHITE


func _update_board() -> void:
	var valid_slots: Array[Dictionary] = []
	if _pending_mode == "place" and _pending_card_index >= 0:
		var pending_card: CardData = engine.hand_card(player_side, _pending_card_index)
		if pending_card != null:
			valid_slots = engine.valid_slots(player_side, pending_card)
	for column_index: int in range(_board_columns.size()):
		var column_ui: Dictionary = _board_columns[column_index]
		column_ui["env"].text = "第%d列·%s" % [column_index + 1, engine.environment_labels[column_index]]
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
	elif _pending_mode == "column_spell":
		actionable = true
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
	_set_slot_highlight_overlay(button, actionable)
	if entity == null:
		if _entity_views.has(button):
			var hidden_view: BattleEntityView = _entity_views[button] as BattleEntityView
			# 攻击/死亡动画还在播时先不隐藏：否则受击方会在攻击动画播完前凭空消失
			# （等动画队列播空后的下一次刷新再隐藏，观感上就是"被打死"）。
			if is_instance_valid(hidden_view) and not _animation_busy:
				hidden_view.visible = false
		button.text = ""
		if actionable and (
			_pending_mode == "place"
			or _pending_mode == "column"
			or _pending_mode == "choose"
			or _pending_mode == "move_position"
			or _pending_mode == "column_spell"
		):
			_apply_highlight_slot_style(button)
			button.disabled = false
		else:
			_apply_empty_slot_style(button)
			button.disabled = true
		return
	var view: BattleEntityView = _get_entity_view(button)
	# 位移动画/攻击动画期间不改层级（否则扑向目标时会被同格/相邻格压住）。
	if not view.is_moving() and not _layer_raised_views.has(view):
		view.z_index = _entity_view_z_index(column, side, slot)
	if entity.has_buff("buried") and entity.side != player_side:
		view.visible = false
		button.text = "墓碑"
		button.disabled = false
		return
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
			or _pending_mode == "column_spell"
		)
	)
	button.text = ""
	_apply_empty_slot_style(button)
	button.disabled = false


func _set_slot_highlight_overlay(button: Button, visible: bool) -> void:
	var overlay: Panel = _slot_highlights.get(button, null) as Panel
	if overlay == null:
		overlay = Panel.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.z_index = 30
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(1.0, 0.88, 0.35, 1.0)
		style.set_border_width_all(4)
		style.set_corner_radius_all(8)
		overlay.add_theme_stylebox_override("panel", style)
		button.add_child(overlay)
		_slot_highlights[button] = overlay
	overlay.visible = visible


func _rebuild_hand() -> void:
	for child: Node in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	if engine == null:
		return
	var state: BattlePlayerState = engine.players[player_side]
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var current_column: VBoxContainer = null
	for index: int in range(state.hand.size()):
		var card: CardData = engine.hand_card_display(player_side, index)
		if card == null:
			continue
		if index % 2 == 0:
			current_column = VBoxContainer.new()
			current_column.custom_minimum_size = Vector2(126, 212)
			current_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			current_column.add_theme_constant_override("separation", 4)
			_hand_row.add_child(current_column)
		var tile: CardTile = CARD_TILE_SCENE.instantiate()
		tile.custom_minimum_size = Vector2(126, 104)
		tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		# 手牌只显示卡面素材，按钮底板完全隐形（否则会看到未遮挡的灰色底）。
		tile.set_chrome_hidden(true)
		current_column.add_child(tile)
		# 传数据库原卡做配色基准：card 是「有效费用/攻击」的副本。
		tile.setup(card, 0, "", false, true, engine.get_card(card.card_id))
		tile.set_cost(engine.effective_hand_cost(player_side, index))
		# 手牌实例加成（例如“军阀点数”）实时显示在攻击/生命上。
		var instance: BattleCardInstance = state.hand[index]
		var display_stats: Dictionary = engine.get_display_stats(instance)
		if not display_stats.is_empty():
			tile.set_stats(
				int(display_stats.get("attack", card.attack)),
				int(display_stats.get("health", card.health))
			)
		tile.pressed.connect(_on_hand_pressed.bind(index))
		tile.gui_input.connect(_on_hand_tile_gui_input.bind(index))
		var playable: bool = _is_hand_card_playable(card, index)
		tile.disabled = not playable
		# 费用够、阶段也允许的手牌：描一圈高亮，提示“现在可以打出”。
		tile.set_playable_highlight(playable)


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
			return "z 实体牌阶段" if engine.active_side == "z" else "p 出牌阶段"
		BattleEngine.PHASE_SPELL:
			return "z 锦囊与环境阶段"
		BattleEngine.PHASE_COMBAT:
			return "对战结算"
		BattleEngine.PHASE_TURN_END:
			return "回合结束"
		_:
			return ""


func get_full_battle_log() -> String:
	if engine == null:
		return ""
	return "\n".join(engine.log_entries)


func _can_player_act() -> bool:
	if engine == null or not _started or engine.winner != "":
		return false
	if engine.active_side != player_side:
		return false
	return engine.phase == BattleEngine.PHASE_HAND or engine.phase == BattleEngine.PHASE_SPELL


## 这张手牌此刻是否真的能打出（无待选目标 + 轮到我方 + 阶段允许 + 费用够）。
## 与 _on_hand_pressed 的拦截条件保持一致，供按钮可用状态与边缘高亮共用。
func _is_hand_card_playable(card: CardData, index: int) -> bool:
	if _pending_mode != "" or not _can_player_act():
		return false
	if engine.phase == BattleEngine.PHASE_HAND and engine.active_side == "z" and not card.is_entity():
		return false
	if engine.phase == BattleEngine.PHASE_SPELL and not (
		card.is_spell() or card.is_environment() or (card.is_entity() and card.has_keyword("spell_phase_entity"))
	):
		return false
	var state: BattlePlayerState = engine.players[player_side]
	return engine.effective_hand_cost(player_side, index) <= int(state.energy)


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
	if _spell_toast_remaining > 0.0:
		_spell_toast_remaining -= delta
		if _spell_toast_remaining <= 0.0:
			_spell_toast.visible = false
	_align_layout_to_art()
	_update_long_press(delta)
	if engine == null or not _started:
		return
	# 手牌实例（费用/攻击加成）变了：每帧最多重建一次，避免一事件一次重建。
	if _hand_dirty:
		_hand_dirty = false
		_rebuild_hand()
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


# ----- 逐列战斗结算（每列动画播完才推进下一列） -----

func _on_combat_phase_started() -> void:
	_run_stepped_combat()


## 由引擎的 combat_phase_started 触发：逐列结算，每列等动画播完再进入下一列。
## 全部列结算完、动画也播完后，再让引擎收尾（回合结束 → 下一回合），
## 这样"下一列/下一回合"永远不会抢在上一列的动画前面。
func _run_stepped_combat() -> void:
	if engine == null or _combat_sequence_running:
		return
	_combat_sequence_running = true
	# 先让上一个阶段（锦囊/出牌）的动画播完，再开始第一列。
	await _wait_for_animations_idle()
	while engine != null and engine.has_pending_combat_columns():
		var column: int = engine.resolve_next_combat_column()
		if column < 0:
			break
		# 本列的攻击/受击/死亡动画全部播完，才进入下一列。
		await _wait_for_animations_idle()
		if engine == null:
			break
		await get_tree().create_timer(COMBAT_COLUMN_GAP).timeout
	if engine != null:
		# 最后一列的动画也播完，才让引擎收尾（回合结束 → 下一回合）。
		await _wait_for_animations_idle()
		engine.finish_combat_resolution()
	_combat_sequence_running = false


## 等动画队列播空。带超时兜底：动画异常（循环动画、时长异常）时不会把战斗卡死。
func _wait_for_animations_idle() -> void:
	var waited: float = 0.0
	while _animation_busy or not _animation_queue.is_empty():
		if engine == null or not is_inside_tree():
			_animation_queue.clear()
			_animation_busy = false
			return
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited >= ANIMATION_WAIT_TIMEOUT:
			_animation_queue.clear()
			_animation_busy = false
			return


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
	var moved_views: Array[BattleEntityView] = []
	# 跨列扑击（三连打/广域打击）时，需要把整列临时抬到别的列之上。
	var boosted_zones: Array[Dictionary] = []
	# 攻击动画期间临时抬高的图层（视图 / 列 / 棋盘），播完按原值还原。
	var raised_layers: Array[Dictionary] = []
	var longest_duration: float = 0.0
	if str(cue.get("trigger", "")) == "attack":
		_raise_attacker_layers(actor, cue.get("target"), ghosts, raised_layers)
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
			"move_to":
				# 目标坐标运行时才知道：用目标视图（实体或其 ghost）/英雄按钮算相对位移，
				# 再叠加伪代码里写的偏移（避免完全糊住目标）与缓动。
				var mover: BattleEntityView = _resolve_animation_view(
					"self", actor, cue.get("target"), ghosts, is_death
				)
				var extra := Vector2(
					float(instruction.get("offset_x", 0.0)),
					float(instruction.get("offset_y", 0.0)),
				)
				var offset: Vector2 = _animation_move_offset(
					mover, cue.get("target"), ghosts, extra
				)
				if mover != null and offset != Vector2.INF:
					longest_duration = maxf(
						longest_duration,
						mover.move_by(
							offset,
							float(instruction.get("seconds", 0.1)),
							str(instruction.get("easing", "ease_in")),
						),
					)
					if not moved_views.has(mover):
						moved_views.append(mover)
					var zone: Control = _column_zone_for_view(mover)
					if zone != null and not _has_layer_entry(boosted_zones, zone):
						boosted_zones.append({"node": zone, "z": zone.z_index})
						zone.z_index = maxi(zone.z_index, MOTION_COLUMN_Z_INDEX)
			"move_back":
				for mover: BattleEntityView in moved_views:
					if is_instance_valid(mover):
						longest_duration = maxf(
							longest_duration,
							mover.move_home(
								float(instruction.get("seconds", 0.1)),
								str(instruction.get("easing", "ease_out")),
							),
						)
	if longest_duration > 0.0:
		await get_tree().create_timer(longest_duration).timeout
	# 兜底复位：脚本忘了写 move_back 时也不会让实体停在别人格子上。
	for mover: BattleEntityView in moved_views:
		if is_instance_valid(mover):
			mover.reset_motion()
	_restore_layers(boosted_zones)
	_restore_layers(raised_layers)
	for ghost: BattleEntityView in ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()


## 攻击动画期间把攻击方抬到受击方之上：视图本身 → 所在列 →（打我方英雄时）整个棋盘。
## 只记录原值，由 _restore_layers 在动画播完后还原；非攻击动画不受影响。
func _raise_attacker_layers(
	actor: BattleEntity, target: Variant, ghosts: Array[BattleEntityView], raised: Array[Dictionary]
) -> void:
	if actor == null:
		return
	var actor_view: BattleEntityView = _resolve_animation_view("self", actor, target, ghosts, false)
	if actor_view == null:
		return
	raised.append({"node": actor_view, "z": actor_view.z_index})
	actor_view.z_index = maxi(actor_view.z_index, ATTACK_ACTOR_Z_INDEX)
	_layer_raised_views[actor_view] = true
	var actor_zone: Control = _column_zone_for_view(actor_view)
	var target_zone: Control = null
	if target is BattleEntity:
		var target_view: BattleEntityView = _resolve_animation_view(
			"target", null, target, ghosts, false
		)
		if target_view != null:
			target_zone = _column_zone_for_view(target_view)
	# 跨列攻击：整列临时上浮，避免被目标所在列盖住。
	if actor_zone != null and actor_zone != target_zone:
		raised.append({"node": actor_zone, "z": actor_zone.z_index})
		actor_zone.z_index = maxi(actor_zone.z_index, ATTACK_ACTOR_Z_INDEX)
	# 打我方英雄：我方英雄行画在棋盘之后，要把棋盘临时抬到它上面。
	if target is String and str(target).begins_with("hero:"):
		if str(target).substr(5) == player_side and _board != null:
			raised.append({"node": _board, "z": _board.z_index})
			_board.z_index = maxi(_board.z_index, ATTACK_ACTOR_Z_INDEX)


func _has_layer_entry(entries: Array[Dictionary], node: CanvasItem) -> bool:
	for entry: Dictionary in entries:
		if entry.get("node") == node:
			return true
	return false


func _restore_layers(entries: Array[Dictionary]) -> void:
	for entry: Dictionary in entries:
		var node: CanvasItem = entry.get("node") as CanvasItem
		if is_instance_valid(node):
			node.z_index = int(entry.get("z", 0))
			if node is BattleEntityView:
				_layer_raised_views.erase(node)


## 找到实体视图所在的「列容器」（Board 的直接子节点），用于跨列扑击时临时抬升整列层级。
func _column_zone_for_view(view: BattleEntityView) -> Control:
	if view == null or _board == null:
		return null
	var node: Node = view
	while node != null:
		if node.get_parent() == _board:
			return node as Control
		node = node.get_parent()
	return null


## 计算「从 actor_view 位移到本次事件目标」的相对偏移；无可用目标时返回 Vector2.INF。
## 实体目标用视图左上角对齐（同尺寸视图正好重叠）；英雄目标对齐英雄按钮中心。
## extra_offset 是伪代码里写的偏移，叠加在目标位置上（避免完全覆盖目标）。
func _animation_move_offset(
	actor_view: BattleEntityView,
	target: Variant,
	ghosts: Array[BattleEntityView],
	extra_offset: Vector2 = Vector2.ZERO,
) -> Vector2:
	if actor_view == null:
		return Vector2.INF
	if target is BattleEntity:
		var target_view: BattleEntityView = _resolve_animation_view(
			"target", null, target, ghosts, false
		)
		if target_view == null or not is_instance_valid(target_view):
			return Vector2.INF
		return target_view.global_position + extra_offset - actor_view.global_position
	if target is String and str(target).begins_with("hero:"):
		var button: Button = _hero_button_for_side(str(target).substr(5))
		if button == null:
			return Vector2.INF
		var target_center: Vector2 = button.global_position + button.size * 0.5 + extra_offset
		var actor_center: Vector2 = actor_view.global_position + actor_view.size * 0.5
		return target_center - actor_center
	return Vector2.INF


func _hero_button_for_side(side: String) -> Button:
	if side == player_side:
		return _player_hero_button
	if side == enemy_side:
		return _enemy_hero_button
	return null


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
	tile.setup(card, 0, "特殊回合 · 费用 -1", true, false, engine.get_card(card.card_id))
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
	if card.ability_script != null and card.ability_script.column_requirement():
		_special_target_mode = true
		_pending_mode = "column_spell"
		_special_overlay.visible = false
		_set_status("请选择一列打出超能力。")
		_refresh_all()
		return
	if int(requirement.get("count", 0)) > 0:
		_special_target_mode = true
		_pending_mode = "choose_spell"
		_pending_handles.clear()
		_pending_candidates = engine.choose_candidates(str(requirement.get("selector", "")), player_side, card.is_spell())
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

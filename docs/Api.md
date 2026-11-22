# 游戏 API 文档（供 UI 接入）

> 版本：alpha0.1　|　对应 Godot 4.7.2 工程 `PVZH_MBP`
> 本文只描述**接口层**（autoload 单例与数据模型），不包含任何场景/按钮/布局实现——这些由后续 UI 开发完成。
> 代码位置：`scripts/core/`（服务）、`scripts/data/`（数据模型）、`scripts/core/confirm_service.gd`（弹出框）。

---

## 0. 通用约定

- 所有服务都是 **autoload 单例**，直接按名字调用即可（如 `LoginFlow.request_start_game()`）。
- 信号统一用 `服务.信号名.connect(方法)` 订阅。
- 需要「是 / 否」结果的地方用 `await ConfirmService.ask_yes_no(...)`。
- 所有返回 `Dictionary` 的方法统一结构：`{ ok: bool, message: String }`（另有 `slot_key` 等附加字段时会注明）。
- 素材：本工程所有卡牌 `art_path` 均为空字符串，UI 不要依赖图片资源。

---

## 1. 登录流程 `LoginFlow`

| 枚举 | 取值 |
|---|---|
| `MODE` | `NONE=0`, `LOCAL=1`, `SERVER=2` |
| `PANEL` | `MODE_SELECT=0`, `LOCAL_MENU=1`, `SAVE_SELECT=2`, `SAVE_CREATE=3`, `SERVER_LOGIN=4` |
| `START_RESULT` | `STARTED=0`, `NEED_CREATE_SAVE=1`, `SAVE_NOT_FOUND=2`, `LOAD_FAILED=3` |

### 信号

| 信号 | 参数 | 触发时机 |
|---|---|---|
| `mode_changed` | `mode: int` | 游玩模式变化 |
| `panel_changed` | `panel: int` | 登录界面内部面板变化（模式选择/本地菜单/选档/新建/服务器） |
| `start_result` | `result: int`, `slot_key: String` | 「开始游戏」的结果 |
| `save_list_changed` | — | 存档创建/删除后，选档界面应重新拉取列表 |
| `save_create_cancelled` | — | 新建存档页点「返回」放弃 |
| `server_login_finished` | `result: int`, `message: String` | 服务器登录结果（目前固定为未实现） |

### 方法

| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `open_login_screen()` | — | void | LoginScreen 的 `_ready` 调用：重置到模式选择，并**预加载主界面** |
| `select_mode(mode)` | `mode: MODE` | void | 选择单机 / 服务器；自动切到对应面板 |
| `back_to_mode_select()` | — | void | 服务器登录页返回、或从本地菜单返回模式选择 |
| `open_local_menu()` | — | void | 打开单机菜单（开始游戏 / 选择存档） |
| `open_save_select()` | — | void | 打开存档选择列表 |
| `open_save_create()` | — | void | 打开新建存档页（会记住来源面板） |
| `cancel_save_create()` | — | void | 新建存档页「返回」：放弃创建并回到来源面板，发 `save_create_cancelled` |
| `open_server_login()` | — | void | 打开服务器登录页 |
| `request_start_game()` | — | `int` (`START_RESULT`) | **开始游戏**：使用最近游玩的存档；没有则切到新建存档页并返回 `NEED_CREATE_SAVE` |
| `create_save_and_start(display_name)` | `display_name: String` | `Dictionary` {`ok`,`message`,`slot_key`} | 校验名称非空 → 建存档（编辑器内自动标记开发者存档）→ 直接用该存档开始游戏 |
| `start_with_save(slot_key)` | `slot_key: String` | `Dictionary` | 「选择存档」列表的左侧按钮：用该存档开始游戏 |
| `delete_save(slot_key)` | `slot_key: String` | `Dictionary` | 删除存档；右侧按钮先 `await ConfirmService.ask_yes_no()` 再调用 |
| `get_save_slots()` | — | `Array[SaveSlotInfo]` | 存档列表，按最近游玩倒序 |
| `has_any_save()` | — | `bool` | 是否存在任意存档 |
| `get_server_form_defaults()` | — | `Dictionary` {`ip`,`account`,`remember`} | 服务器登录页自动填写（上次勾选保存的信息） |
| `submit_server_login(ip, account, password, remember, port=-1)` | port 缺省用 45770 | void | 校验非空 → 按「记住」保存 IP/账号（**不保存密码**）→ 调起登录。登录逻辑未实现，结果通过 `server_login_finished` 返回 `LOGIN_RESULT.NOT_IMPLEMENTED` |
| `quit_game()` | — | void | 退出游戏：先保存存档再退出 |
| `get_developer_message()` | — | `String` | 「开发者的话」文本（可直接给提示框） |
| `get_panel()` / `get_mode()` | — | `int` | 当前面板 / 模式 |

### 典型接线

```gdscript
func _ready() -> void:
	LoginFlow.open_login_screen()
	LoginFlow.panel_changed.connect(_on_panel_changed)
	LoginFlow.start_result.connect(_on_start_result)
	LoginFlow.server_login_finished.connect(_on_server_login_finished)
	LoginFlow.save_list_changed.connect(_refresh_save_list)

func _on_start_pressed() -> void:
	LoginFlow.request_start_game()

func _on_delete_pressed(slot_key: String) -> void:
	var confirmed: bool = await ConfirmService.ask_yes_no("删除后无法恢复，确定删除该存档吗？")
	if confirmed:
		LoginFlow.delete_save(slot_key)

func _on_create_confirm_pressed() -> void:
	var result: Dictionary = LoginFlow.create_save_and_start(name_edit.text)
	if not bool(result.get("ok", false)):
		status_label.text = str(result.get("message", ""))
```

> 说明：`request_start_game()` 内部会直接切换场景到主界面，无需 UI 再跳转。

---

## 2. 存档 `SaveManager`

存储位置：`user://saves/<slot_key>/profile.json`（`user://` 由 Godot 映射到系统用户目录）。

| 方法 | 返回 | 说明 |
|---|---|---|
| `create_slot(display_name)` | `String` slot_key | 新建存档；**在编辑器内运行时自动标记开发者存档** |
| `create_slot_with_flags(display_name, is_developer)` | `String` | 显式指定开发者标记（测试用） |
| `list_slots()` | `Array[SaveSlotInfo]` | 存档摘要列表（最近游玩倒序） |
| `load_slot(slot_key)` | `PlayerProfile` / `null` | 读取存档，损坏返回 null |
| `save_slot(slot_key, profile)` | `bool` | 原子写（先写 .tmp 再替换） |
| `delete_slot(slot_key)` | `bool` | 删除存档目录 |
| `slot_exists(slot_key)` | `bool` | 存档是否存在 |
| `is_editor_build()` | `bool` | 是否运行在 Godot 编辑器内（`OS.has_feature("editor")`） |
| `remember_server(address, port, account, password)` | void | 旧版最近服务器缓存（登录界面目前使用 `AppStorage`，此接口保留） |
| `load_recent_servers()` | `Array[Dictionary]` | 同上 |

### `SaveSlotInfo`（选档列表项）

`slot_key`、`player_name`、`last_played_unix`、`play_time_seconds`、`play_time_text()`、`deck_count`、`gold`、`diamond`、`schema_version`、`active_deck_id`、`is_developer_save`。

---

## 3. 玩家存档数据 `PlayerProfile`

| 字段 | 类型 | 说明 |
|---|---|---|
| `player_name` | String | 存档名称（创建时输入，不可为空） |
| `gold` | int | 金币 |
| `diamond` | int | 钻石 |
| `play_time_seconds` | int | 累计游玩时长（秒），由 `GameState` 计时 |
| `is_developer_save` | bool | 开发者存档标记 |
| `profile_id` / `created_at_unix` / `last_played_unix` | String/int | 标识与时间戳 |
| `owned_cards` | Dictionary[String,int] | 卡牌收藏 |
| `decks` / `active_deck_id` | Array[DeckData] / String | 牌组 |
| `campaign_progress` / `stats` | Dictionary | 进度 / 统计 |

方法：`add_gold(n)`、`spend_gold(n) -> bool`、`add_diamond(n)`、`spend_diamond(n) -> bool`、`get_play_time_text() -> "HH:MM:SS"`、`add_card/remove_card/get_card_count`、`create_deck/remove_deck/find_deck`、`to_dict/from_dict`。

> 旧版存档（schema 1，字段 `arcane_dust`）读取时会自动迁移为 `diamond`。

---

## 4. 全局状态 `GameState`

| 信号 | 参数 | 用途 |
|---|---|---|
| `currency_changed` | `gold: int`, `diamond: int` | 货币变化时刷新全局 UI 顶部栏 |
| `play_time_changed` | `total_seconds: int` | 游玩时长每秒变化（可选显示） |
| `identity_changed` | `mode: int` | 单机/服务器身份切换（进入游戏后加载全局 UI 可监听它） |
| `screen_changed` | `screen: int` | 场景切换 |

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_gold()` / `get_diamond()` / `get_currency(kind)` | int | 读取货币 |
| `add_gold(n)` / `spend_gold(n)` / `add_diamond(n)` / `spend_diamond(n)` | bool | **添加上限/扣除货币**，自动发 `currency_changed`；余额不足返回 false 且不扣 |
| `add_currency(kind, n)` / `spend_currency(kind, n)` | bool | 通用版本（`CURRENCY.GOLD/DIAMOND`） |
| `emit_currency()` | void | 强制广播当前货币（UI 初始化后同步用） |
| `save_active_profile()` | bool | **保存当前存档**（含游玩时长）；设置页「保存存档」按钮调用它 |
| `enter_local_game(slot_key)` | bool | 底层：读档并进入主界面（一般用 `LoginFlow`） |
| `leave_to_login()` | void | 保存并回到登录界面 |
| `is_developer_save()` | bool | 当前存档是否开发者存档（全局 UI 决定是否显示测试按钮） |
| `get_version()` | String | 当前版本号：`alpha0.1` |
| `preload_main_scene()` | void | 预加载主界面（`LoginFlow.open_login_screen()` 已自动调用） |
| `is_main_scene_preloaded()` | bool | 预加载是否完成 |
| `go_to_main()` / `go_to_battle()` / `go_to_login()` | void | 场景切换（主界面优先用预加载资源，进入更快） |
| `get_identity_text()` | String | 「单机身份 / 服务器身份 / 未登录」 |

计时与自动保存：

- 单机身份下 `GameState._process` 每秒累加 `play_time_seconds`；
- 每 **30 秒**自动落盘一次；
- 关闭窗口（`NOTIFICATION_WM_CLOSE_REQUEST`）、安卓返回键、`LoginFlow.quit_game()` 都会保存。

---

## 5. 全局本地数据 `AppStorage`

文件：`user://global.json`（与任何存档无关，切档/删档不影响）。

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_last_slot_key()` / `set_last_slot_key(key)` | String / void | 「开始游戏」使用的最近存档 |
| `get_server_login()` | `{ip, account, remember}` | 服务器登录页自动填写 |
| `set_server_login(ip, account, remember)` | void | remember=false 时清空已保存信息 |
| `get_master_volume()` / `set_master_volume(v)` | float / void | 主音量 0.0–1.0，立即作用于 Master 总线并持久化 |
| `get_display_preset()` / `set_display_preset(id)` | String / void | 显示预设（由 `DisplayService` 读写） |
| `save_data()` | bool | 手动落盘（一般不需要） |

---

### 设置界面 `SettingsScreen`

场景：`res://scenes/settings/SettingsScreen.tscn`；通常由全局 UI 的「设置」按钮以覆盖层打开（不切换场景）。

| 功能 | 实现 |
|---|---|
| 主音量滑块 | `AppStorage.get/set_master_volume()`，立即作用于 Master 总线并持久化 |
| 显示预设 | `DisplayService.get_presets()` 渲染下拉框，选择后 `apply_preset(id)` 并持久化 |
| 账号/存档信息 | 身份、玩家名、金币/钻石、开发者标记、存档或服务器账号 |
| 保存当前存档 | `GameState.save_active_profile()`（服务器身份下提示由服务器保存） |
| 开发者调试 | 仅开发者存档启用，进入 `DeveloperPanel.tscn` |
| 投降 | 只在战斗覆盖层显示，触发 `surrender_requested`，由全局 UI 让当前战斗我方失败 |
| 返回 | 覆盖层模式发出 `close_requested` 关闭；直接进入场景时返回主界面 |

覆盖层 API：`open_as_overlay(in_battle)`；信号 `close_requested` / `surrender_requested`。

### 全局 UI `GlobalUI`（autoload）

场景：`res://scenes/ui/GlobalUI.tscn`，跨场景常驻。

- 显示金币、钻石、设置按钮（设置按钮为紧凑尺寸）
- 登录界面 / 战斗场景自动切换为 `SETTINGS_ONLY`（只显示设置）
- 其他界面自动 `ALL`
- 设置以覆盖层打开，战斗内打开时暂停战斗树；关闭后恢复

| API | 说明 |
|---|---|
| `show_all()` | 全部显示 |
| `hide_all()` | 全部关闭（含设置按钮） |
| `show_settings_only()` | 除设置按钮外全部关闭 |
| `set_visibility(mode)` | 使用 `GlobalUI.VISIBILITY.ALL / SETTINGS_ONLY / HIDDEN` |
| `_open_settings()` / `_close_settings()` | 内部使用；也可在调试中调用 |

战斗内设置覆盖层的「投降」会调用当前 `BattleScreen.surrender_player()`，直接判我方失败。

## 6. 弹出框 `ConfirmService`
| 方法 | 返回 | 说明 |
|---|---|---|
| `ask_yes_no(message, title="确认", yes_text="是", no_text="否")` | **`await` → bool** | 是=true，否/ESC/关闭=false；同一时间只有一个确认框 |
| `show_message(message, title="提示")` | void | 仅「确定」的提示框（如开发者的话） |

```gdscript
var confirmed: bool = await ConfirmService.ask_yes_no("确定删除？")
ConfirmService.show_message(LoginFlow.get_developer_message(), "开发者的话")
```

---

## 7. 开发者工具 `DeveloperTools`

对应界面：`res://scenes/settings/DeveloperPanel.tscn`（设置页「开发者调试」或主界面「调试」按钮进入；仅开发者存档可用）。

仅当当前存档 `is_developer_save == true` 时可用（否则所有操作返回 false / 0）。

| 方法 | 返回 | 说明 |
|---|---|---|
| `is_enabled()` | bool | 是否开发者存档（全局 UI 的测试按钮据此显示） |
| `add_gold(amount=100)` | bool | 加金币 |
| `add_diamond(amount=100)` | bool | 加钻石 |
| `set_currencies(gold, diamond)` | void | 直接设置两种货币 |
| `unlock_all_cards()` | int | 让每张卡至少拥有 2 张（仅开发者存档），返回新增张数 |
| `add_all_cards(count=10)` | int | 给所有卡牌各增加 `count` 张（不受收藏上限限制），返回新增张数 |
| `clear_all_cards()` | void | 清空卡牌收藏 |
| `test_action_done`（信号） | `action`, `detail` | 每个操作完成后通知面板刷新 |

### 卡牌 CSV 编译（开发者测试界面）

| 方法 | 返回 | 说明 |
|---|---|---|
| `compile_card_set(source_dir="", namespace="", output_pack_path="")` | 报告 Dictionary | 编译 `user://card_packs/import`（可指定）下的 config.csv/cards.csv |
| `compile_official_cards()` | 报告 Dictionary | 编译官方 `res://data/cards/official` 到官方编译包 |
| `get_compile_report_path()` / `get_compile_report()` | String | 最近一次编译报告文件路径 / 文本 |
| `reload_card_database(use_compiled_pack=true)` | int | 重新加载卡牌（优先编译包），返回卡牌数 |
| `get_card_database_errors()` | `Array[String]` | 当前加载错误 |
| `has_compiled_official_pack()` / `clear_compiled_official_pack()` | bool | 查询/删除官方编译包 |

编译成功会生成 `.cardpack`（`user://card_packs/compiled/`），失败会生成
`user://card_packs/compile_report.txt`，逐行指出 CSV 行号与问题（费用、生命、职业、词缀、流派、稀有度、伪代码语法等）。

---

## 8. 卡牌与牌组（CSV 数据驱动）

### 数据文件

- `data/cards/official/config.csv`：全局配置（稀有度 / 职业 / 流派，带中文标签）
- `data/cards/official/cards.csv`：每行一张卡（列名见 `data/cards/README.md`）

官方卡牌内部 ID：`pvzh:<英文名>`；未来模组：`<作者.模组>:<英文名>`，互不冲突。
未知词缀/流派会被忽略并记入 `CardDatabase.load_errors`。

### `CardDatabase`（autoload）

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_card(card_id)` | `CardData` / null | 按内部 ID 取卡 |
| `find_by_english(english_name)` | `CardData` / null | 供伪代码按英文名引用 |
| `has_card(card_id)` | bool | |
| `all_card_ids()` | `Array[String]` | |
| `card_count()` | int | |
| `get_classes()` / `get_rarities()` / `get_tribes()` | `Array[String]` | 全局配置 |
| `load_errors` | `Array[String]` | 加载错误/警告 |
| `reload()` | void | 重新扫描官方 CSV |
| `load_mod_card_set(namespace, dir)` | int | 模组接口预留 |

### `CardData`

字段：`card_id`、`card_namespace`、`english_name`、`chinese_name`、`description`、`kind`（entity/spell/environment）、
`cost`、`attack`、`health`、`shield`、`card_class`、`rarity`、`keywords`、`keyword_values`（带数值词缀，如 `first_strike:2`）、
`tribes`、`ability`（伪代码）、`art_path`（卡面贴图路径，空 = 纯色占位外观）、`animation`（动画伪代码）、
`deck_includable`（是否可被牌组编入，默认 true），
以及加载时解析的 `class_label` / `rarity_label` / `keyword_labels` / `tribe_labels`。

方法：`keyword_value(id)`、`has_keyword()`、`get_keywords_text()`、`get_tribes_text()`、`max_copies()`、`craft_cost()`、`disenchant_value()`。

卡面加载：`CardArt.get_texture(path)`（带缓存；空/缺失返回 null，回退纯色外观），
`CardArt.get_card_background(rarity)` / `get_card_background_style(rarity)`
（按稀有度读取 `assets/cards/backgrounds/<rarity>.png`，9 宫格 32px；缺图返回 null 并回退默认样式）。
列表格子与详情弹窗会先铺稀有度背景，再叠加 `art_path` 外观图。

方法：`display_name()`、`is_entity()`、`get_type_text()`、`get_class_text()`、`get_rarity_text()`、
`get_keywords_text()`、`get_tribes_text()`、`has_keyword()`、`keyword_value()`、`max_copies()`、`craft_cost()`、`disenchant_value()`。

### 能力脚本 `CardEffectScript`

CSV 的 `ability` 列在载入时编译为 `CardData.ability_script`（语法见 `docs/EffectDsl.md`）。

| 方法/属性 | 说明 |
|---|---|
| `CardEffectScript.parse(ability)` | 编译伪代码；语法错误在 `.errors` |
| `script.validate_for_kind(kind)` | 实体/锦囊语义校验（实体必须写 when 块，锦囊不能用 when） |
| `script.run_on_play(context)` | 锦囊打出时执行，返回运行期错误数组 |
| `script.run_event(context, event_name, handle)` | 实体触发事件时执行 |
| `script.has_effect()` / `script.has_errors()` | 是否有能力 / 是否有语法错误 |

战斗层实现 `EffectContext`（`scripts/data/effects/effect_context.gd`）：
`set_self_target / set_event_target / resolve_selector / describe_entity` + 原语；
`RecordingEffectContext` 是现成测试实现。

### 英雄数据 `HeroDatabase`（autoload）

数据文件：`data/cards/official/heroes.csv`
列：`english_name,chinese_name,faction,classes,special_cards`

- `faction`：`p` 或 `z`
- `classes`：正好两个职业（必须在全局配置中，逗号分隔）
- `special_cards`：专属卡牌英文名，逗号分隔（载入时解析为内部卡牌 ID）

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_hero(hero_id)` | `HeroData` / null | hero_id 为英文名规范化（如 `green_knight`） |
| `all_hero_ids()` | `Array[String]` | |
| `heroes_by_faction(faction)` | `Array[HeroData]` | `p` / `z` |
| `load_errors` | `Array[String]` | 职业/专属卡牌等加载问题 |
| `reload()` / `reload_from(path, card_database)` | void | 载入官方 / 指定文件 |

`HeroData` 字段：`hero_id`、`english_name`、`chinese_name`、`faction`、`classes`、`class_labels`、
`special_card_names`、`special_card_ids`；方法：`display_name()`、`has_class()`、`is_special_card()`。
`special_card_ids` 中筛出锦囊牌即为该英雄的超能力牌池来源；超能力牌带 `superpower` 流派。

### 玩法配置 `GameModeConfig` / `ModeManager`

默认文件：`data/modes/default_mode.json`（可由 `user://modes/default_mode.json` 覆盖；服务器可运行时加载任意玩法文件）。

字段（省略则用默认值）：`deck_max_size`(40)、`enforce_full_deck`(true)、
`max_copies_by_rarity`([4,4,4,4,1,4,4,4]，按全局稀有度顺序，超出数组默认 1)、
`player_hero_max_health`(20)、`enemy_hero_max_health`(20)、
`player_initial_energy`(1)、`enemy_initial_energy`(1)、
`player_initial_draw`(4)、`enemy_initial_draw`(4)、
`hand_limit`(10)、`energy_cap`(99)、`phase_time_limit_seconds`(40)、
`player_draw_per_turn`(1)、`enemy_draw_per_turn`(1)、
`charge_shield_max`(8)、`charge_shield_durability`(3)、`charge_shield_emergency_uses`(1)、
`charge_shield_charge_rules`（1~3→1、4~6→2、7+→3）、`superpower_priority_side`("z")。

| API | 说明 |
|---|---|
| `ModeManager.get_mode()` | 当前 `GameModeConfig` |
| `ModeManager.load_mode_file(path)` | 运行时载入玩法文件 |
| `ModeManager.reset_to_default()` | 回到默认玩法 |
| `ModeManager.get_hero_max_health(faction)` / `get_initial_energy` / `get_initial_draw` | 按阵营取我方/敌方数值（p=我方，z=敌方） |
| `GameModeConfig.from_file(path)` / `from_dict(data)` / `default_config()` | 构造与加载 |
| `max_copies_for_rarity_index(index)` | 按稀有度序号取单卡上限 |
| `turn_draw_for_faction(faction)` | 第二回合起每回合开始时的抽牌数（我方/敌方） |

### 服务器/运行优化配置 `ServerConfig`

文件：`data/server/server_config.json`；字段说明见 `data/server/README.md`。
当前所有字段均为预留，不提供业务接口。

| API | 说明 |
|---|---|
| `ServerConfig.load_config(path)` | 读取原始配置字典（失败返回空） |
| `ServerConfig.effect_resolution_limit(path)` | 读取单次出牌/战斗连锁上限（默认 100） |

### 牌组管理 `DeckManager`（autoload）

| API | 返回 | 说明 |
|---|---|---|
| `get_decks()` / `get_deck(deck_id)` | `Array[DeckData]` / DeckData | 当前玩家牌组 |
| `create_deck(hero_id, deck_name="")` | `{ok, message, deck_id, deck}` | 新牌组；空名称自动生成「英雄名#三位数字」并去重 |
| `delete_deck(deck_id)` | `{ok, message}` | 删除牌组 |
| `begin_edit(deck_id)` / `end_edit()` / `get_editing_deck()` / `get_editing_deck_id()` | DeckData / void | 当前编辑的牌组 |
| `rename_deck(deck_id, new_name)` | `{ok, message}` | 自定义名称重名时返回 `{ok:false, message:"牌组重名"}` |
| `set_deck_hero(deck_id, hero_id)` | `{ok, message, errors, tags}` | 切换英雄并刷新标签 |
| `add_card(deck_id, card_id)` | `{ok, message, count}` | 校验张数/稀有度上限/职业/专属/可编入 |
| `remove_card(deck_id, card_id)` | `{ok, message, count}` | 移除一张 |
| `get_available_cards(deck_id)` | `Array[Dictionary]` | 可选卡牌列表：只含背包中拥有、可编入、且符合英雄职业/中立/专属的卡；每项含 `card`、`owned`、`in_deck`、`max_copies`、`remaining`、`can_add`、`is_hero_special` |
| `get_available_card_ids(deck_id)` | `Array[String]` | 可选卡牌 ID 的便捷版 |

> 对应界面：`res://scenes/deck/DeckList.tscn`（牌组数量 / 列表 / 新建牌组）→ `DeckEditor.tscn`（选择后进入编辑；返回按钮回到列表）。
| `save_deck(deck_id)` | `{ok, message, errors, tags}` | 保存必定成功；仅按规则刷新 `default` 标签（不符合时移除标签，`errors` 供 UI 提示） |

`DeckData` 字段：`deck_id`、`deck_name`、`hero_id`、`allowed_classes`、`card_ids`、`tags`、`updated_at_unix`；
方法：`card_count()`、`count_of()`、`get_card_counts()`、`add_card()`、`remove_card()`、`clear_cards()`、
`has_tag()`、`add_tag()`、`remove_tag()`、`to_dict()/from_dict()`。

### 牌组规则 `DeckRules`

| 方法 | 返回 | 说明 |
|---|---|---|
| `validate(deck, card_database, hero_database, mode)` | `Array[String]` | 空数组 = 完全符合要求 |
| `can_add_card(deck, card, card_database, hero_database, mode)` | bool | 牌组编辑器置灰/高亮 |
| `refresh_tags(...)` | `Array[String]` | 合法则打 `default` 标签，否则移除 |

规则：张数 ≤ `deck_max_size`（`enforce_full_deck` 时必须正好等于）；单卡张数按稀有度数组；
牌组中某张卡的数量不能超过存档持有数量；职业必须属于英雄两个职业（中立职业无视限制、英雄专属卡无视限制）；`deck_includable=0` 的卡不可编入。
### 战斗 `BattleManager` / `BattleEngine` / `EasyBattleAI`

场景：`res://scenes/battle/BattlePrep.tscn`（准备）、`res://scenes/battle/Battle.tscn`（对战）。
战斗界面全部由场景节点搭建（`Battle.tscn`），布局、英雄栏、5 列槽位、手牌区、起手/结算遮罩均可在编辑器中直接调整与替换素材；脚本只负责状态刷新与信号绑定。
手牌与牌组编辑共用 `CardTile.tscn`；场上实体使用 `BattleEntityView.tscn`。两者的背景/外观/费用/攻击/生命图标都是空 `Sprite2D` 节点，分别从稀有度背景与 `art_path` 加载；数值显示为图标上方的 Label。
空位槽位默认使用透明样式隐藏；选中实体牌进入放置状态时，合法空位显示白色描边（`StyleBoxFlat`），点击即可放置。

#### `BattleManager`（autoload）

| API | 返回 | 说明 |
|---|---|---|
| `get_available_player_decks()` | `Array[DeckData]` | 只返回带 `default` 标签的牌组 |
| `start_vs_ai(deck_id, difficulty="easy")` | `{ok, message}` | 选择电脑推荐卡组并写入 `current_battle` |
| `current_battle` | Dictionary | 对战双方英雄、阵营、牌库快照 |
| `recommended_decks` | `RecommendedDecks` | 推荐卡组（`data/battle/recommended_decks.csv`） |
| `reload_recommended_decks()` | void | 重新加载推荐卡组 |

#### `BattleEngine`

`BattleEngine.new(card_database, seed)` 后调用
`setup(player_side, player_hero, player_deck_ids, enemy_hero, enemy_deck_ids, mode)`。

| API | 说明 |
|---|---|
| `confirm_mulligan(side)` / `replace_mulligan_card(side, index)` | 起手调度（每张限换一次） |
| `play_card(side, hand_index, target)` | target：实体 `{column,slot}`（目标列至少一方有组队时可挤开原实体）；环境 `{column}`；需要目标 `{handle}`；移动实体牌额外带 `{column,slot}` 作为目标位置 |
| `end_phase(side)` / `advance_phase()` | 结束当前阶段 / 推进阶段 |
| `valid_slots(side, card)` / `target_candidates(card, side)` | UI 高亮与 AI 选目标；`valid_slots` 的 `displace` 字段表示会挤开哪个实体 |
| `summon(card_name, column)` | 召唤一个实体；法术用绝对列 1~5，实体异能用相对列 -4~4 |
| `summon(card_name, min_column, max_column)` | 在范围内随机尝试一个合法列，一条语句只召唤一个 |
| `can_summon_in_column(side, card, column)` | 指定列是否可召唤（不挤压已有实体） |
| `summon_card_in_column(side, card, column)` | 在合法列召唤一个实体 |
| `add_random_cards(side, zone, count, filter_text)` | 从卡牌数据库筛选并随机插入牌库/手牌；返回插入数量 |
| `place_environment_by_name(side, column, card_name)` | 尝试放置环境；受保护环境不可覆盖 |
| `can_change_environment(column)` | 该列环境是否允许被改变 |
| `entities_in_column(min, max, side, min_attack)` | 相对基准列范围查询实体数组 |
| `apply_buff_handle(entity, buff_id, amount)` / `remove_buff_handle` | 施加/解除内置 Buff/Debuff |
| `force_entity_attack(entity)` | 让实体按当前列目标攻击一次；冰冻时失败 |
| `public_entity_snapshot(viewer_side)` | 供网络快照使用；隐藏敌方墓碑实体信息 |
| `visible_energy_for(side, viewer_side)` | 墓碑费用对敌方隐藏后的可见费用 |
| `is_entity_visible_to(entity, viewer_side)` | 实体信息是否对观察方可见 |
| `CardEffectScript.evolve_filter_text` / `is_base_ability` | 进化筛选与底座声明，供 UI/放置逻辑使用 |
| `CardFilter.parse(text)` / `matches(card)` | 支持 and/or/not 的卡牌筛选表达式 |
| `move_entity(entity, column, slot)` | 卡牌效果移动实体；合法位置仅限该实体所属阵营，触发 `position_changed` |
| `valid_move_slots(entity)` | 返回可移动的列/位置；排除当前位置；目标格有友方时该列至少一方需 `team_up` |
| `CardEffectScript.move_requires_position()` | 卡牌顶层是否存在单参数 `move_entity(target)`，供 UI 进入位置选择 |
| `damage_handle / heal_handle / buff_handle / ...` | 效果原语入口 |
| `changed` / `game_finished(winner)` 信号 | 状态变化 / 胜负 |
| `hero_damaged(side, amount, source_keywords)` 信号 | 英雄实际受伤（已扣护盾/免疫后）；amount > 0 时发出 |
| `damage_hero(side, amount, source_keywords)` | 英雄伤害统一结算：免疫 → 护盾 → 生命 |
| `animation_cue(trigger, actor, target)` 信号 | 攻击/能力触发/死亡时发出动画请求（UI 排队播放，不阻塞逻辑） |
| `effective_hand_cost(side, index)` / `effective_hand_attack(side, index)` | 应用手牌实例修正后的有效费用/攻击 |
| `hand_card_display(side, index)` | 给 UI 的手牌显示副本（已带有效费用/攻击） |
| `CardTile.setup(card, owned, status, show_owned)` | 通用卡牌显示；`show_owned=false` 时隐藏“拥有/未拥有”行（战斗手牌用） |
| `play_card(..., target.handles)` | 多目标选择；`handles` 为实体数组；锦囊的 `choose` 也使用该字段 |
| `choose_candidates(selector, side)` | 多目标锦囊的候选实体列表 |
| `execute_command(side, command)` | 服务器权威命令入口：play_card/end_phase/起手/特殊回合 |
| `special_resolve_play(side, target)` / `special_resolve_hand(side)` | 特殊回合：打出临时超能力 / 移入手牌 |
| `give_keyword_handle(handle, keyword, value)` | 给实体叠加词缀数值；受卡牌种类白名单限制 |
| `give_keyword_to_hand_card(side, index, keyword, value)` | 给指定手牌实例赋予词缀；同名牌其他副本不受影响 |
| `get_markers(side)` | 返回玩家特殊标志物 `{名字: 数量}` 副本 |

卡牌动画：`CardData.animation_script`（`CardAnimationScript`）解析 `animation` 列，
支持 `when attack/ability/die`、`play_animation(self|target, name, mode)`、`wait(秒)`、`play_fx`；
详见 `docs/AnimationDsl.md`。

实体显示：`BattleEntityView`（`scenes/battle/BattleEntityView.tscn`）提供
`play_animation(name, mode)`、`play_fx(name)` 与 `set_highlight()`；动画库在
`assets/animations/whole.tres` / `background.tres` / `art.tres`。

区域/多目标/标志物：
- `BattlePlayerState.hand` / `deck` / `discard` 为 `BattleCardInstance` 数组（带 `instance_id`、`card_id`、`zone`、`attack_bonus`、`cost_delta`）
- `BattleCardInstance.to_dict()` / `from_dict()` 供联机快照使用
- `BattlePlayerState.markers` 为 `Dictionary`（字符串名字、整数数量，允许负数）
- `BattlePlayerState.hero_shield` 为英雄护盾；`hero_damage_immune` 为伤害免疫标记（预留）
- `BattlePlayerState.charge_shield` / `charge_shield_durability` / `charge_shield_emergency_uses` 为充能护盾状态
- `BattlePlayerState.superpower_pool` / `special_offer_id` 为超能力牌池与特殊回合临时牌
- 超能力在双方完成起手重选后发放；第一回合不触发每回合固定抽牌，超能力不进入起手重选
- 环境拥有者、环境卡与所在列保存在 `environment_owners` / `environment_cards`；环境事件按列触发
- 初始环境没有打出者，`environment_owners` 为空字符串，视为中立；中立环境拒绝需要判断 ally/enemy 的效果
- 服务器 `match.protected_environments` 默认 `["highground","water"]`，这些环境不可被环境牌覆盖
- 服务器 `match.environment_keyword_filters` 默认水池要求 `amphibious`；实体打出、移动、召唤都走该检查
- Buff/Debuff 定义在 `scripts/data/card_buffs.gd`，词缀定义在 `scripts/data/card_keywords.gd`
- 进化/底座是实体牌顶层声明：`evolve(filter)` / `base()`；锦囊/环境出现会被编译拒绝
- 额外攻击事件为 `extra_attack`；`force_attack` 和狂热追加攻击触发，双重打击第二击不触发
- 战斗棋盘长按任意在场实体，弹出与牌组界面相同的 `CardInfoDialog`
- 战斗手牌调用 `CardTile.setup(..., false)`，不显示收藏拥有状态
- `first_strike` 伤害与普通英雄伤害共用 `damage_hero`，会经过免疫、护盾并触发 `hero_damaged`
- 充能护盾在真实受击后结算；满充能触发免疫、耐久 -1，并给该英雄发放随机超能力进入特殊回合
- 必中（`bullseye`）伤害不增加充能护盾充能
- `CardEffectScript.target_requirement()` 返回入场/锦囊 `choose(count, selector)` 的目标需求
- `CardEffectScript.move_requires_position()` 判断是否需要玩家为 `move_entity(target)` 选择位置
- `add_random_cards_to_deck(target, count, filter)` / `add_random_cards_to_hand(...)`；目标用 `hero` / `enemy_hero`；未写 `deck_includable` 时默认只取可组入牌组的卡牌
- 对战牌库在建立时由具体牌组生成并洗牌；之后按数组顺序从牌库顶抽取（`take_top_deck` 为 `pop_back`），换牌会重新洗牌
- 区域被动用 `when ally_die(zone == 'deck'|'hand')`，原语 `gain_attack` / `reduce_cost`
- 多目标用 `choose(count, "other_allies")` + `buff_stats(chosen, ...)`
- 标志物用 `add_marker("名字", 数量)` / `marker_count("名字")`

规则：5 列 × 双方各 2 位（位置不固定）；同一列最多 2 个实体，且该列已有 1 个实体时，
再放入的实体必须与已有实体至少有一个带「组队」词缀，否则不能放入。
每回合 z 出牌 → p 出牌 → z 锦囊/环境 → 逐列战斗 → 回合结束；
从第二回合起，每个回合在场上实体的回合开始效果结算完成后、进入 z 出牌阶段前，
双方按 `player_draw_per_turn` / `enemy_draw_per_turn` 各抽牌（受手牌上限限制）；第一回合不触发。
英雄生命来自玩法配置；同一列战斗先结算双方攻击再统一死亡判定；出牌阶段伤害立即死亡判定。
**与电脑对战时不启用阶段时间限制**（UI 显示“不限时”）；`phase_time_limit_seconds` 预留给玩家对玩家。

#### `EasyBattleAI`

`EasyBattleAI.take_action(engine, side)`：尽量打出费用最高的可打出手牌，目标随机；无牌可出时结束阶段。

#### `RecommendedDecks`

`RecommendedDecks.load_file(path, card_database, hero_database)`；字段 `decks`（`deck_id/deck_name/hero_id/hero_faction/card_ids`）与 `load_errors`。

### `CollectionManager`（autoload）

| 方法 | 返回 | 说明 |
|---|---|---|
| `max_copies_for(card)` | int | 固定 0，表示收藏**不限持有张数**（UI 可显示为 ∞） |
| `can_craft(profile, card)` / `can_disenchant(profile, card)` | bool | 能否合成（只看钻石） / 分解 |
| `craft_card(profile, card)` | `{ok, message}` | 消耗钻石合成一张，**不设收藏上限** |
| `disenchant_card(profile, card)` | `{ok, message}` | 分解一张获得钻石 |
| `collection_changed`（信号） | — | 收藏变化通知 |

> 合成/分解数值由稀有度决定（normal 40/5、rare 100/20、super rare 400/100、legend 1600/400）。
## 9. 网络 `NetManager`（占位）

| 枚举/常量 | 值 |
|---|---|
| `LOGIN_RESULT` | `OK=0`, `UNREACHABLE=1`, `BAD_CREDENTIALS=2`, `PROTOCOL_MISMATCH=3`, `NOT_IMPLEMENTED=4`, `FEATURE_DISABLED=5` |
| `DEFAULT_SERVER_PORT` | 45770 |
| `DISCOVERY_PORT` | 45771（局域网 UDP 发现） |

| 方法/信号 | 说明 |
|---|---|
| `login_to_server(address, port, account, password)` | 登录入口；**当前未实现**，会立即以 `login_finished(NOT_IMPLEMENTED, ...)` 返回 |
| `login_finished(result, message)`（信号） | 登录结果；`LoginFlow` 会转发为 `server_login_finished` |
| `start_lan_search(timeout)` / `stop_lan_search()` | 局域网服务器搜索 |
| `lan_server_found(server)` / `lan_search_finished(servers)` | 搜索结果回调 |

---

## 10. 显示适配 `DisplayService`

游戏为竖屏 9:16：基准视口 720×1280，拉伸 `canvas_items` + 宽高比 `keep`
（窗口比例不是 9:16 时自动留黑边，画面永不裁切）。

| 枚举 | 取值 |
|---|---|
| `DEVICE` | `DESKTOP=0`, `MOBILE=1` |

| 信号 | 参数 | 说明 |
|---|---|---|
| `display_changed` | `preset_id: String`, `width: int`, `height: int` | 应用预设后通知 UI 刷新 |

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_device_type()` / `get_device_label()` | int / String | 电脑窗口 / 手机屏幕 |
| `get_presets()` | `Array[Dictionary]` | 当前设备可用预设：`id`、`label`、`description`、`width`、`height`、`auto` |
| `apply_preset(preset_id)` | bool | 应用并持久化（桌面改窗口大小；手机改逻辑分辨率） |
| `apply_device_default()` | bool | 重新应用「自动」预设 |
| `get_current_preset_id()` | String | 已保存的预设 id（默认 `auto`） |
| `set_window_size(w, h)` / `get_window_size()` | void / Vector2i | 桌面窗口像素尺寸（自动限制在屏幕可用区域内） |
| `set_content_resolution(w, h)` / `get_content_resolution()` | void / Vector2i | 逻辑分辨率（手机清晰度） |

预设列表：

- **电脑**：`auto`（自动适配窗口）、`540x960`（标准窗口）、`720x1280`（屏幕不够高会自动等比缩小）、`405x720`（小巧窗口）。
- **手机**：`auto`（跟随设备屏幕）、`720x1280`、`1080x1920`、`1440x2560`（逻辑分辨率）。

设置界面接法：

```gdscript
var presets: Array[Dictionary] = DisplayService.get_presets()
for preset in presets:
	display_option.add_item(str(preset["label"]))
# 选项变化时：
DisplayService.apply_preset(str(presets[selected_index]["id"]))
```

> 桌面默认按屏幕可用高度自动缩放（最多占 92%），窗口完整可见；玩家手动拉伸窗口时按 9:16 等比缩放、多余区域留黑边，画面始终完整。

## 11. 需要 UI 侧接入的部分（本次未实现）

1. LoginScreen 的各个面板（模式选择 / 单机菜单 / 新建存档页 / 选档列表 / 服务器表单）的显示与按钮绑定。
2. 全局 UI 层（货币栏、开发者测试按钮、设置按钮、设置面板、版本号文字）。
3. 设置页：音量滑块 → `AppStorage.set_master_volume()`；显示预设下拉框 → `DisplayService.get_presets()/apply_preset()`；保存按钮 → `GameState.save_active_profile()`；退出按钮 → 关闭面板。
4. 选档列表的 ScrollContainer/ScrollBar 布局（数据用 `LoginFlow.get_save_slots()`）。
5. 主界面、牌组、收藏、社交、活动等场景与跳转。

---

## 12. 验证情况

- 自动化测试：`tests/run_tests.gd`，6 个套件 **26 个用例 / 184 条断言**全通过（`godot --headless --script res://tests/run_tests.gd`）。
- 运行时验证（编辑器内跑游戏 + 反射调用）：
  - 模式/面板切换、新建存档页返回；
  - 无最近存档时「开始游戏」→ 新建页；
  - 空名称被拒绝；创建后直接进入 `MainScreen`，并标记开发者存档；
  - 最近存档记录到 `global.json`；「开始游戏」复用最近存档；
  - 选择存档、删除存档、货币增删、退出自动保存（退出后磁盘金币为修改值）；
  - 主界面预加载完成、主音量 0.5 → Master 总线 -6.02 dB；
  - 服务器登录返回未实现并保存 IP/账号（不存密码）；
  - 竖屏窗口（独立进程实测）：默认 533×947（9:16，屏幕可用高度 92% 内）；窗口拉成 722×893 时画面居中、左右黑边、完整可见；持久化预设 `405x720` 启动即生效；逻辑分辨率 720×1280 ↔ 1080×1920 切换正常。

## 13. 词缀显示接口

`BattleEngine` 提供：

```gdscript
signal keyword_changed(handle, keyword, old_value, new_value)

func keyword_value_for(handle, keyword: String) -> int
func has_keyword_for(handle, keyword: String) -> bool
```

- `handle` 可以是 `BattleEntity`、`BattleCardInstance` 或 `CardData`
- 无数值词缀：具备返回 `1`，不具备返回 `0`
- 有数值词缀：返回当前数值，不具备返回 `0`
- 手牌实例会合并数据库基础词缀与实例附加词缀
- `keyword_changed` 适合驱动图标替换、闪光、数字滚动和卡面动画

`BattleEntity` 自身也有：

```gdscript
signal keyword_changed(keyword, old_value, new_value)
func keyword_value_for(keyword: String) -> int
func set_keyword_value(keyword: String, value: int) -> void
```

推荐 UI 侧适配函数：

```gdscript
func refresh_keyword_icon(handle) -> void
func keyword_style_id(handle) -> String
func keyword_badge_list(handle) -> Array[String]
```

### 素材推荐尺寸

| 素材 | 推荐源尺寸 |
|---|---|
| 卡牌完整框 | 720 × 1000 PNG |
| 卡牌插画 | 512 × 512 或 768 × 768，1:1 |
| 手牌缩略图 | 256 × 356 |
| 攻击力图标 | 128 × 128，显示 48–72 px |
| 生命值图标 | 128 × 128，显示 48–72 px |
| 防御值图标 | 128 × 128，显示 40–64 px |
| 词缀徽章 | 128 × 128，显示 40–56 px |
| Buff/Debuff 图标 | 128 × 128 |
| 九宫格卡框边角 | 256 × 256，建议 16–24 px 边距 |

所有图标建议透明通道，并保留 2×/3× 源图以适配 Android 高 DPI。

## 14. 统一显示状态与最终数值

```gdscript
signal display_state_changed(handle)

func get_display_stats(handle) -> Dictionary
func get_display_entries(handle) -> Array[Dictionary]
func get_display_icon_styles(handle) -> Dictionary
func notify_display_state_changed(handle) -> void
```

`get_display_stats` 返回最终显示值：

```gdscript
{
	"zone": "board" | "hand" | "deck" | "card",
	"side": "p" / "z" / "",
	"attack": int,
	"health": int,
	"max_health": int,
	"shield": int,
	"cost": int,
}
```

- 在场实体：攻击、当前生命、生命上限、防御均为已结算后的当前值
- 手牌：攻击/生命/防御合并卡牌基础值与实例修正
- 手牌费用使用 `effective_hand_cost`，包含实例费用、光环费用和特殊回合折扣
- 不在手牌的实例费用只返回基础费用 + 持久费用修正

`get_display_entries`：

- 在场实体返回关键词 + Buff/Debuff
- 手牌只返回关键词
- 每条：`kind`（keyword/buff）、`id`、`label`、`value`、`buff_kind`

`get_display_icon_styles` 返回：

```gdscript
{"attack": "...", "health": "...", "shield": "...", "cost": "..."}
```

当前风格例：

- `normal`
- `deadly`
- `invisible`
- `triple`
- `frenzy`
- `hatred`
- `invincible`
- `frozen`
- `buried`
- `amphibious`

推荐 UI 直接连接：

```gdscript
engine.display_state_changed.connect(_on_display_state_changed)
engine.keyword_changed.connect(_on_keyword_changed)
```

`display_state_changed` 已在 Buff 添加/移除、光环刷新、攻击/生命/防御变化、伤害、治疗、死亡判定、词缀变化、手牌费用变化等路径触发。

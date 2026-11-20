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

仅当当前存档 `is_developer_save == true` 时可用（否则所有操作返回 false / 0）。

| 方法 | 返回 | 说明 |
|---|---|---|
| `is_enabled()` | bool | 是否开发者存档（全局 UI 的测试按钮据此显示） |
| `add_gold(amount=100)` | bool | 加金币 |
| `add_diamond(amount=100)` | bool | 加钻石 |
| `set_currencies(gold, diamond)` | void | 直接设置两种货币 |
| `unlock_all_cards()` | int | 解锁全部卡牌到持有上限，返回新增张数 |
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

字段：`card_id`、`card_namespace`、`english_name`、`chinese_name`、`description`、`kind`（entity/spell）、
`cost`、`attack`、`health`、`shield`、`card_class`、`rarity`、`keywords`、`tribes`、`ability`（伪代码），
`deck_includable`（是否可被牌组编入，默认 true），
以及加载时解析的 `class_label` / `rarity_label` / `keyword_labels` / `tribe_labels`。

方法：`display_name()`、`is_entity()`、`get_type_text()`、`get_class_text()`、`get_rarity_text()`、
`get_keywords_text()`、`get_tribes_text()`、`has_keyword()`、`max_copies()`、`craft_cost()`、`disenchant_value()`。

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

### 玩法配置 `GameModeConfig` / `ModeManager`

默认文件：`data/modes/default_mode.json`（可由 `user://modes/default_mode.json` 覆盖；服务器可运行时加载任意玩法文件）。

字段（省略则用默认值）：`deck_max_size`(40)、`enforce_full_deck`(true)、
`max_copies_by_rarity`([4,4,4,4,1,4,4,4]，按全局稀有度顺序，超出数组默认 1)、
`player_hero_max_health`(20)、`enemy_hero_max_health`(20)、
`player_initial_energy`(1)、`enemy_initial_energy`(1)、
`player_initial_draw`(4)、`enemy_initial_draw`(4)。

| API | 说明 |
|---|---|
| `ModeManager.get_mode()` | 当前 `GameModeConfig` |
| `ModeManager.load_mode_file(path)` | 运行时载入玩法文件 |
| `ModeManager.reset_to_default()` | 回到默认玩法 |
| `ModeManager.get_hero_max_health(faction)` / `get_initial_energy` / `get_initial_draw` | 按阵营取我方/敌方数值（p=我方，z=敌方） |
| `GameModeConfig.from_file(path)` / `from_dict(data)` / `default_config()` | 构造与加载 |
| `max_copies_for_rarity_index(index)` | 按稀有度序号取单卡上限 |

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
职业必须属于英雄两个职业（中立职业无视限制、英雄专属卡无视限制）；`deck_includable=0` 的卡不可编入。
### `CollectionManager`（autoload）

| 方法 | 返回 | 说明 |
|---|---|---|
| `max_copies_for(card)` | int | 传说 1 张，其余 2 张 |
| `can_craft(profile, card)` / `can_disenchant(profile, card)` | bool | 能否合成 / 分解 |
| `craft_card(profile, card)` | `{ok, message}` | 消耗钻石合成一张 |
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

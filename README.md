# 卡牌对决（工程代号 PVZH_MBP）

类《炉石传说》的卡牌回合制对战游戏，Godot 4.7.2 + GDScript，目标平台 Windows / Android。

> 需求、架构、编码规范、里程碑分别见：
> [`docs/Charter.md`](docs/Charter.md)、[`docs/Architecture.md`](docs/Architecture.md)、
> [`docs/Conventions.md`](docs/Conventions.md)、[`docs/Roadmap.md`](docs/Roadmap.md)。
> **接口清单见 [`docs/Api.md`](docs/Api.md)**（供 UI 开发直接接入）。

## 当前状态：M0 工程基座 + 登录/存档/全局 API

已具备：

- 竖屏 720×1280（9:16）+ `canvas_items` + `keep` 拉伸：安卓锁竖屏；桌面窗口按屏幕自动缩放，窗口比例不符时留黑边且画面完整。
- 全局单例：`GameState`（身份/场景切换/货币/计时/自动保存）、`SaveManager`（本地多存档）、
  `AppStorage`（最近存档 / 服务器账号 / 主音量 / 显示预设）、`LoginFlow`（登录流程状态机）、
  `DisplayService`（竖屏显示适配与分辨率预设）、`ConfirmService`（是/否弹窗）、
  `DeveloperTools`（开发者存档测试功能）、`CardDatabase`（卡表）、`HeroDatabase`（英雄）、
  `ModeManager`（玩法配置）、`DeckManager`（牌组管理）、`CollectionManager`（合成/分解）、
  `NetManager`（局域网发现 + 登录占位）。
- 数据模型：`CardData`、`DeckData`（牌组名/英雄/卡牌列表/标签）、`PlayerProfile`、`SaveSlotInfo`、`HeroData`、`GameModeConfig`。
- 英雄数据：`data/cards/official/heroes.csv`（p/z 阵营、双职业、专属卡牌）。
- 玩法配置：`data/modes/default_mode.json`（牌组上限/满编/稀有度张数/英雄生命/初始费用与抽牌；可被 `user://modes/default_mode.json` 覆盖）。
- 牌组管理 API：新建/删除/编辑/加牌/去牌/改名/换英雄、重名规则、`default` 标签。
- 收藏合成/分解：收藏数量无上限（只看钻石），`max_copies_for()` 返回 0 表示不限。
- 牌组列表（`scenes/deck/DeckList.tscn`）：牌组数量、选择进入编辑、新建牌组；编辑页可返回列表。
- 牌组编辑界面（`scenes/deck/DeckEditor.tscn`）：上方「已编入卡牌」、中间「待选择卡牌」分隔、下方可选卡牌；选中/移除/信息下拉菜单、卡牌信息弹窗。
- 主界面 / 牌组列表 / 设置界面均为场景节点搭建（动态牌组行使用 `DeckRow.tscn`），便于直接在编辑器替换 UI 素材。
- 卡牌美术：稀有度卡牌背景（`assets/cards/backgrounds/`）+ CSV `art_path` 外观图；缺图回退纯色外观。
- 单机战斗：`scenes/battle/BattlePrep.tscn` 准备 + `Battle.tscn` 对战；战斗 UI 已全部节点化，可直接在编辑器部署素材；推荐卡组 CSV（`data/battle`）；简单 AI。
- 战斗卡牌/实体：手牌与牌组编辑共用 `CardTile.tscn`，实体使用 `BattleEntityView.tscn`；背景、外观、费用/攻击/生命图标均为空 Sprite2D 挂点。
- 实体动画：整体/背景/外观三种模式，卡牌 `animation` 列用伪代码编排攻击/能力/死亡/法术动画。
- 区域与多目标：手牌/牌库为带 `instance_id` 的 `BattleCardInstance`；`when ally_die(zone == 'deck'|'hand')` 支持区域被动；
  `choose(n, "other_allies")` 多目标；玩家特殊标志物为 `{名字: 数量}` 数据接口。
- 联机基础：`scripts/net` 下已有 ENet 协议/服务器/客户端传输层；权威对局会话与 UI 接入待完成。
- 服务器/运行优化配置：`data/server/server_config.json`（目前仅接入组队换位冷却，其余为预留参数，说明见 `data/server/README.md`）。
- 设置与调试：全局 UI（`scenes/ui/GlobalUI.tscn`）常驻显示金币/钻石/设置；设置以覆盖层打开，战斗内额外提供「投降」；开发者调试面板（货币/卡牌/CSV 编译）。
- 30 张示例卡数据（`data/cards/official/cards.csv`，CSV 数据驱动）+ 能力 DSL
  （`docs/EffectDsl.md`：变量、四则运算、条件目标、实体事件与过滤）。
- 旧版占位界面（LoginScreen / MainScreen / Battle）；正式 UI 由后续开发替换。

尚未实现：完整联机对局会话、社交与活动、正式 UI 素材。

## 运行

1. Godot 4.7.2 打开本目录（`project.godot`），F5 运行。
2. 或命令行：
   ```powershell
   & 'E:\GodotWork\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' --path .
   ```

## 测试

- 编辑器内：MCP `test_run`，套件 `save`（存档）与 `deck`（牌组规则）。
- 无编辑器（headless，退出码 0 表示全部通过）：
  ```powershell
  & 'E:\GodotWork\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
    --headless --path . --script res://tests/run_tests.gd
  ```
- 冒烟（脚本解析 + 主场景启动，无报错即通过）：
  ```powershell
  & 'E:\GodotWork\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
    --headless --path . --quit-after 200
  ```
- 预置演示存档（可选）：
  ```powershell
  & 'E:\GodotWork\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
    --headless --path . --script res://tests/prepare_demo_save.gd -- 测试玩家
  ```

## 目录

```
scenes/main/    LoginScreen / MainScreen / Battle
scripts/core/    autoload 单例
scripts/data/    Resource 数据模型
scripts/ui/      界面逻辑
data/cards/      卡牌 CSV（config.csv + cards.csv，格式见其 README；能力语法见 docs/EffectDsl.md）
tests/           MCP 测试套件 + 开发辅助脚本
docs/            需求章程 / 架构 / 规范 / 路线图
assets/          美术素材（当前留空）
```

## 两条硬性约定

1. **身份与存档分离**：单机存档在 `user://saves/<slot>/profile.json`；服务器身份存档由服务器托管，
   本地只缓存最近服务器地址与账号（可选密码）。
2. **素材留空**：UI 全部使用纯色与内置控件，不引用图片；确需占位时用全透明 PNG。

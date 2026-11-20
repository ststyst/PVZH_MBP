# 架构设计

> 配套文档：`Charter.md`（需求）、`Conventions.md`（代码规范）、`Roadmap.md`（里程碑）。

## 1. 技术基座

- Godot 4.7.2 / GDScript。
- 渲染：`gl_compatibility`（Android 兼容面最大，2D 卡牌游戏足够）。
- 分辨率基准 1280×720 横屏，`window/stretch/mode=canvas_items`、`aspect=expand`。
- Android 方向：`sensor_landscape`；桌面开启 `emulate_touch_from_mouse` 便于触屏交互调试。
- 单工程同时导出 Windows / Android。

## 2. 目录结构

```
scenes/          场景（PascalCase，如 LoginScreen.tscn）
scripts/
  core/          全局单例（autoload：GameState、SaveManager、CardDatabase、NetManager）
  data/          数据模型（Resource：CardData、DeckData、PlayerProfile、SaveSlotInfo）
  ui/            界面逻辑
  net/           网络实现（M5 起）
data/cards/      卡牌 JSON 定义（数据驱动）
assets/          美术 / 音频（当前留空）
tests/           MCP 测试套件（McpTestSuite）
docs/            需求、架构、规范、路线图
addons/          第三方插件（godot_ai 用于编辑器联调）
```

## 3. 分层与依赖方向

```
表现层（scenes + scripts/ui）  ──调用──▶  服务层（scripts/core 单例）  ──调用──▶  数据层（scripts/data）
                                        │
                                        └──▶ 网络层（scripts/net，M5）
```

- 表现层：只读单例状态、发 UI 事件，不直接读写文件、不直接碰 socket。
- 服务层：业务编排（身份切换、存档、卡表、联机）。
- 数据层：纯数据 + 序列化，不依赖节点树。
- 禁止反向依赖（数据层不得引用 UI / 单例）。

## 4. 全局单例职责

| 单例 | 脚本 | 职责 |
|---|---|---|
| `GameState` | scripts/core/game_state.gd | 当前身份（NONE/LOCAL/SERVER）、当前存档、玩家资料、场景切换 |
| `SaveManager` | scripts/core/save_manager.gd | 本地多存档 CRUD、服务器地址/账号缓存 |
| `CardDatabase` | scripts/core/card_database.gd | 扫描 `res://data/cards/*.json` 构建卡表，预留模组路径 |
| `NetManager` | scripts/core/net_manager.gd | 局域网 UDP 发现、登录请求（M5 接 ENet）、网络信号总线 |

## 5. 存档模型（身份分离）

### 单机身份

- 位置：`user://saves/<slot_key>/profile.json`（`user://` 由 Godot 映射到系统用户目录）。
- 内容：`PlayerProfile`（含 `schema_version`、货币、卡牌持有、牌组列表、进度与统计）。
- 写入：原子写（先写 `.tmp` 再替换）；读取失败返回 null 并提示，不静默覆盖。
- 多存档：每个 `slot_key` 独立目录，可切换/删除。

### 服务器身份（M5 实现协议）

- 存档以服务器数据库为准，客户端不保存 `profile.json`。
- 本地仅存 `user://server_cache.json`：最近服务器地址、端口、账号，可选密码（用户勾选「记住账号密码」时）。
- 服务器身份下**禁止**写入本地单机存档；单机存档也不得上传覆盖服务器数据。

### 版本迁移

`PlayerProfile.from_dict()` 按 `schema_version` 容错解析，未知字段忽略，缺失字段用默认值；升级时在 `SaveManager` 内做迁移函数。

## 6. 网络模型

### 局域网发现（M5 前半）

- 传输：UDP 广播。
- 端口：发现服务 `45771`；对局服务 `45770`（ENet，UDP）。
- 请求：客户端向 `255.255.255.255:45771` 广播 `{"magic":"CARDARENA_DISCOVERY_V1","client_version":"..."}`。
- 应答：服务端直接回包（源地址）`{"magic":...,"name":...,"players":n,"max_players":m,"game_port":45770,"version":...,"motd":...}`。
- 客户端超时 3 秒收包，按 `address:port` 去重。

### 专用服务端

- 形态：同一工程以 `--headless` 启动的服务器模式（后续提供独立导出预设）。
- 服主可配置：是否开放主线内容、匹配规则、活动、存档目录、最大人数。
- 对外只需映射 UDP 45770/45771（或 TCP/ENet 实际端口），天然支持内网穿透 / 公网 IP。

### 权威与安全

- 服务器权威：卡组合法性、抽牌随机、回合合法性、结算均由服务端判定；客户端只发意图。
- 账号：服务端校验；密码哈希存储（算法在 M5 决定）。
- 客户端默认不落盘密码；用户显式勾选后才写入本机缓存，并在文档与 UI 上提示风险。

### 单机模式

完全不启动任何监听端口；局域网搜索仅为可选动作。

## 7. 模组预留

- 卡牌、牌组规则、关键词均为数据驱动（JSON + 资源）。
- `CardDatabase` 预留 `user://mods/<mod_id>/cards/*.json` 扫描入口。
- ID 命名空间：`mod_id:card_id`，避免与官方卡牌冲突。
- 模组不得修改核心逻辑脚本（仅数据与资源覆盖）。

## 8. 场景流转

```
LoginScreen ──本地存档/服务器登录──▶ MainScreen
MainScreen ──对战──▶ Battle（M3）
MainScreen ──牌组/收藏/社交/活动/设置──▶ 对应模块（M1/M2/M6）
任意模块 ──返回──▶ MainScreen；退出登录 ──▶ LoginScreen
```

场景路径集中定义在 `GameState` 常量中，禁止在 UI 里散落硬编码路径。

## 9. 测试与验证

- MCP 测试套件：`res://tests/test_*.gd` 继承 `McpTestSuite`，覆盖数据层与存档层（编辑器内运行）。
- 冒烟：`godot --headless --path <工程> --quit-after 180`，要求无脚本错误。
- UI 校验：编辑器打开场景截图 + 实机运行；后续加自动化 UI 用例。

## 10. 待定决策（后续里程碑逐一敲定）

1. 卡牌效果系统形态：数据 DSL（JSON 描述）vs 每张卡脚本。
2. 服务器账号密码哈希算法与传输层加密方式。
3. UI 主题系统与中文本地化资源组织。
4. 卡包概率、合成/分解数值、货币经济模型。

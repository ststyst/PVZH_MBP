# 卡牌对决（工程代号 PVZH_MBP）

类《炉石传说》的卡牌回合制对战游戏，Godot 4.7.2 + GDScript，目标平台 Windows / Android。

> 需求、架构、编码规范、里程碑分别见：
> [`docs/Charter.md`](docs/Charter.md)、[`docs/Architecture.md`](docs/Architecture.md)、
> [`docs/Conventions.md`](docs/Conventions.md)、[`docs/Roadmap.md`](docs/Roadmap.md)。

## 当前状态：M0 工程基座完成

已具备：

- 1280×720 横屏 + `canvas_items` 拉伸，安卓横屏，GL Compatibility 渲染。
- 全局单例：`GameState`（身份/场景切换）、`SaveManager`（本地多存档 + 服务器地址缓存）、
  `CardDatabase`（卡表加载）、`NetManager`（局域网发现 + 登录入口）。
- 数据模型：`CardData`、`DeckData`（30 张/同名 2 张规则）、`PlayerProfile`、`SaveSlotInfo`。
- 登录界面：本地存档列表（新建/进入/删除）、服务器登录表单（地址/端口/账号/密码/记住）、
  局域网服务器搜索入口。
- 主界面：对战 / 牌组 / 收藏 / 社交 / 活动 / 设置；社交与活动在单机身份下禁用。
- 单机存档读写（原子写、本地时区显示）与 MCP 测试套件。

尚未实现：卡牌内容、牌组编辑器、战斗逻辑、联机协议、社交与活动（见路线图）。

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
data/cards/      卡牌 JSON（当前为空，格式见其 README）
tests/           MCP 测试套件 + 开发辅助脚本
docs/            需求章程 / 架构 / 规范 / 路线图
assets/          美术素材（当前留空）
```

## 两条硬性约定

1. **身份与存档分离**：单机存档在 `user://saves/<slot>/profile.json`；服务器身份存档由服务器托管，
   本地只缓存最近服务器地址与账号（可选密码）。
2. **素材留空**：UI 全部使用纯色与内置控件，不引用图片；确需占位时用全透明 PNG。

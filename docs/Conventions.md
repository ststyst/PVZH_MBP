# 编码规范

> 用户指定规范 + 本项目落细说明。Godot 4.7.2 / GDScript。

## 1. 命名

| 对象 | 规范 | 示例 |
|---|---|---|
| 文件夹 | snake_case | `scripts/core`、`scenes/main` |
| 场景文件 | PascalCase（"驼峰"按大驼峰执行） | `LoginScreen.tscn`、`MainScreen.tscn` |
| 场景根节点 | 与场景文件同名 | `LoginScreen` |
| 类名（`class_name`） | PascalCase | `class_name CardData` |
| 全局单例（autoload） | PascalCase | `GameState`、`SaveManager` |
| 脚本文件 | snake_case | `login_screen.gd`、`save_manager.gd` |
| 函数 / 方法 | snake_case | `enter_local_game()` |
| 参数、局部变量、私有成员 | snake_case（私有加 `_` 前缀） | `slot_key`、`_slots` |
| 信号 | snake_case | `identity_changed` |
| 枚举 | 类型名与成员**全大写** | `enum CARD_TYPE { MINION, SPELL }` |
| 常量 | UPPER_SNAKE_CASE | `const DEFAULT_MAX_CARD_COUNT: int = 40` |

> 说明：用户需求原文「场景文件、类名、全局变量用驼峰」，工程既有占位场景为 `LoginScreen.tscn`/`MainScreen.tscn`，因此本项目统一按**大驼峰 PascalCase** 执行；`snake_case` 只用于其余对象。

## 2. 类型

- 变量、参数、返回值尽量显式标注类型；避免裸 `Variant`。
- 数值类型明确：费用/血量/数量用 `int`；时间戳用 `int`（Unix 秒）。
- 容器尽量写成 `Array[T]` / `Dictionary[K, V]`。
- JSON 解析结果先赋给 `Variant` 再判断类型（`is Array` / `is Dictionary`），不直接信任结构。

## 3. 结构

- 单脚本单一职责；UI 脚本不直接读写文件、不直接建 socket。
- 数据模型（Resource）不依赖节点树与场景。
- 场景根节点脚本与其文件名对应：`LoginScreen.tscn` ↔ `scripts/ui/login_screen.gd`。
- 场景路径统一由 `GameState` 常量提供，不在 UI 中硬编码。

## 4. 注释

- 公共方法与类用 `##` 文档注释，中文描述用途与副作用。
- 关键设计决策写进 `docs/Architecture.md`，不在代码里写长篇说明。

## 5. 素材

- 图片优先留空（不引用纹理）。
- 必须占位时使用**全透明**素材（如 1×1 透明 PNG）。
- 不提交来源不明、版权不清的素材。

## 6. 提交约定（启用 git 后）

- 一次提交只做一件事；提交信息用中文祈使句，例如「新增本地存档读写」「实现登录界面骨架」。
- 提交前跑：headless 冒烟 + MCP 测试套件。

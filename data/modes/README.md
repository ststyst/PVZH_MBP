# 玩法配置（JSON）

默认文件：`data/modes/default_mode.json`
覆盖文件：`user://modes/default_mode.json`（存在时优先；服务器管理员可修改）
运行时加载：`ModeManager.load_mode_file(path)`（加载任意玩法文件，服务器可为不同对局切换）

## 字段

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `deck_max_size` | int | 40 | 牌组卡牌数量上限 |
| `enforce_full_deck` | bool | true | true 时牌组必须正好满编才能开始；false 时允许少于上限；任何时候不允许超上限 |
| `max_copies_by_rarity` | int[] | [4,4,4,4,1,4,4,4] | 按全局配置稀有度顺序，每种卡可编入的张数；超出数组长度的稀有度默认 1 |
| `player_hero_max_health` | int | 20 | p 阵营（我方）英雄生命上限 |
| `enemy_hero_max_health` | int | 20 | z 阵营（敌方）英雄生命上限 |
| `player_initial_energy` | int | 1 | p 阵营初始回合费用 |
| `enemy_initial_energy` | int | 1 | z 阵营初始回合费用 |
| `player_initial_draw` | int | 4 | p 阵营初始抽牌数 |
| `enemy_initial_draw` | int | 4 | z 阵营初始抽牌数 |
| `hand_limit` | int | 10 | 双方手牌上限；超过时取消抽牌 |
| `energy_cap` | int | 99 | 双方费用上限 |
| `phase_time_limit_seconds` | int | 40 | 单个回合阶段真实时间上限（秒），到点强制结束；**与电脑对战时不生效（不限时）**，预留给玩家对玩家 |
| `player_draw_per_turn` | int | 1 | 从第二回合起，每回合开始时我方抽牌数（第一回合不触发；0 = 不抽） |
| `enemy_draw_per_turn` | int | 1 | 从第二回合起，每回合开始时敌方抽牌数（第一回合不触发；0 = 不抽） |

玩家对战时：p 阵营英雄使用 `player_*` 数据，z 阵营英雄使用 `enemy_*` 数据。

## 示例

```json
{
  "deck_max_size": 40,
  "enforce_full_deck": true,
  "max_copies_by_rarity": [4, 4, 4, 4, 1, 4, 4, 4],
  "player_hero_max_health": 20,
  "enemy_hero_max_health": 20,
  "player_initial_energy": 1,
  "enemy_initial_energy": 1,
  "player_initial_draw": 4,
  "enemy_initial_draw": 4,
  "hand_limit": 10,
  "energy_cap": 99,
  "phase_time_limit_seconds": 40,
  "player_draw_per_turn": 1,
  "enemy_draw_per_turn": 1
}
```

所有字段均可省略；省略时使用默认值。文件缺失或解析失败时回退默认值并记录在 `ModeManager.load_errors`。

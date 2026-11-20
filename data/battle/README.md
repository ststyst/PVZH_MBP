# 推荐卡组 `recommended_decks.csv`

用于“推荐卡组展示（以后做）”与“电脑随机卡组对战”模式的电脑牌组来源。
电脑会从所有推荐卡组中随机抽一套，且英雄阵营必须与玩家英雄不同（p ↔ z）。

## 格式

```csv
deck_name,hero_name,card_name,count
太阳守卫,green_knight,novice,2
太阳守卫,green_knight,shield_pair,2
亡灵先锋,zombie_captain,gnoll,2
```

| 列 | 说明 |
|---|---|
| `deck_name` | 牌组名称（同一名称 + 英雄的行归为一套） |
| `hero_name` | 英雄英文名（与 `heroes.csv` 对应） |
| `card_name` | 卡牌英文名（与 `cards.csv` 对应） |
| `count` | 组入数量（正整数） |

- 每行一张卡；同一套牌组写多行。
- 卡牌/英雄不存在、数量非正数会记录到 `RecommendedDecks.load_errors`。
- 修改后在开发者工具/启动时调用 `BattleManager.reload_recommended_decks()` 重新加载。

## 与玩家牌组的关系

- 玩家准备界面只显示带 `default` 标签的牌组。
- 玩家牌组的英雄阵营由英雄决定；电脑推荐卡组的英雄阵营必须不同。
- 推荐卡组不参与 `DeckRules` 的“满编 40 张”校验，仅为电脑提供牌库。

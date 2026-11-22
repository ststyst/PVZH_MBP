# UI 图形素材占位与接口

设计分辨率：720 × 1280（竖屏 9:16）。

## 战斗界面 `scenes/battle/Battle.tscn`

占位节点都在 `Background/ArtPlaceholders` 下，`mouse_filter` 均为忽略，不会阻挡操作。

| 节点 | 用途 | 推荐素材尺寸 |
|---|---|---|
| `BattleBackgroundImage` | 全屏战斗背景，支持运行时切换 | 720 × 1280（2×：1440 × 2560） |
| `BoardArtArea/BoardArtTexture` | 双方全部实体放置区域；锚点固定为屏幕宽度 90%、高度 60% | 648 × 768（2×：1296 × 1536） |
| `EnemyHeroArtArea` | 敌方英雄立绘/头像 | 256 × 320，透明 PNG |
| `PlayerHeroArtArea` | 我方英雄立绘/头像 | 256 × 320，透明 PNG |

棋盘区域计算：

- 宽度：720 × 0.9 = 648
- 高度：1280 × 0.6 = 768
- 锚点：左右 5% 边距，上下 20% 起点到 80% 终点

### 战斗背景切换接口

`scripts/ui/battle_screen.gd`：

```gdscript
set_battle_background(texture: Texture2D)
set_battle_background_path(path: String)
clear_battle_background()
get_battle_background() -> Texture2D

set_board_art(texture: Texture2D)
set_board_art_path(path: String)
set_hero_art(side: String, texture: Texture2D)
set_hero_art_path(side: String, path: String)
```

同时提供信号：

```gdscript
signal battle_background_changed(texture: Texture2D)
```

## 牌组编辑界面 `scenes/deck/DeckEditor.tscn`

占位节点都在 `Background/ArtPlaceholders` 下。

| 节点 | 用途 | 推荐素材尺寸 |
|---|---|---|
| `DeckBackgroundImage` | 牌组编辑全屏背景 | 720 × 1280（2×：1440 × 2560） |
| `HeroPortraitArea` | 右上英雄头像 | 256 × 256 |
| `DeckHeaderArtArea` | 顶部标题装饰 | 512 × 160，透明 PNG |
| `DeckPanelArtArea/DeckPanelTexture` | 卡牌列表大面板底图 | 648 × 1056，建议九宫格 |

### 牌组界面接口

`scripts/ui/deck_editor.gd`：

```gdscript
set_deck_background(texture: Texture2D)
set_deck_background_path(path: String)
set_hero_portrait(texture: Texture2D)
set_hero_portrait_path(path: String)
set_deck_header_art(texture: Texture2D)
```

## 卡牌素材

| 素材 | 推荐尺寸 |
|---|---|
| 卡牌完整框 | 720 × 1000，透明 PNG |
| 卡牌插画 | 512 × 512 或 768 × 768，1:1 |
| 手牌缩略图 | 256 × 356 |
| 攻击力图标 | 128 × 128，显示 48–72 px |
| 生命值图标 | 128 × 128，显示 48–72 px |
| 防御值图标 | 128 × 128，显示 40–64 px |
| 词缀徽章 | 128 × 128，显示 40–56 px |
| Buff/Debuff 图标 | 128 × 128 |
| 九宫格卡框边角 | 256 × 256，16–24 px 边距 |

建议所有图形使用 PNG 透明通道，并保留 2× 源图以适配 Android 高 DPI。

## 实际布局更新（720 × 1280）

- 棋盘区使用 `BoardArtArea` 实际大小，约 **648 × 590**
- 棋盘内 5 列 × 4 行，中央分隔条占一行高度的 1/3
- 手牌区使用 `HandScroll` 实际大小，约 **690 × 230**
- 手牌为 2 行 × 5 列；超过 10 张时横向滚动，列数可继续增加
- 实体槽约 126 × 136，手牌槽约 126 × 104

### 实体与手牌素材建议

| 素材 | 推荐尺寸 | 比例 |
|---|---|---|
| 实体卡框/插画 | 512 × 448 | 约 1.14:1，横版 |
| 实体小图 | 256 × 224 | 约 1.14:1 |
| 手牌卡框/插画 | 512 × 416 | 约 1.23:1，横版 |
| 手牌小图 | 256 × 208 | 约 1.23:1 |
| 棋盘槽位安全区 | 126 × 136 | 建议内缩 8 px |
| 手牌槽位安全区 | 126 × 104 | 建议内缩 6 px |

实体与手牌素材应比高度宽，并保留透明边距，避免内容贴边被裁切。

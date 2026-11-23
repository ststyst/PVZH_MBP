# UI 图形素材占位与接口

设计分辨率：720 × 1280（竖屏 9:16）。

## 战斗界面 `scenes/battle/Battle.tscn`

占位节点都在 `Background/ArtPlaceholders` 下，`mouse_filter` 均为忽略，不会阻挡操作。

| 节点 | 用途 | 推荐素材尺寸 |
|---|---|---|
| `BattleBackgroundImage` | 全屏战斗背景，支持运行时切换 | 720 × 1280（2×：1440 × 2560） |
| `BoardArtArea/BoardArtTexture` | 双方全部实体放置区域；实际锚点与偏移见场景 | 648 × 590 |
| `EnemyHeroArtArea` | 敌方英雄立绘/头像 | 256 × 320，透明 PNG |
| `PlayerHeroArtArea` | 我方英雄立绘/头像 | 256 × 320，透明 PNG |

棋盘区域计算：

- 宽度：720 × 0.9 = 648
- 高度：按当前场景偏移约 590
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
| 手牌整卡 | 252 × 208（2× 126×104） |
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
| 实体小图 | 252 × 258（2× 126×129） | 接近方形 |
| 手牌卡框/插画 | 512 × 416 | 约 1.23:1，横版 |
| 手牌小图 | 252 × 208 | 约 1.21:1，横版 |
| 棋盘槽位安全区 | 126 × 136 | 建议内缩 8 px |
| 手牌槽位安全区 | 126 × 104 | 建议内缩 6 px |

实体与手牌素材应比高度宽，并保留透明边距，避免内容贴边被裁切。

## 边框素材接入

### 手牌/牌组卡牌

节点：`CardTile/BorderSprite`

固定按稀有度加载：

```text
res://assets/cards/borders/<rarity>.png
```

例如：

```text
res://assets/cards/borders/normal.png
res://assets/cards/borders/rare.png
res://assets/cards/borders/super_rare.png
res://assets/cards/borders/legend.png
```

接口：

```gdscript
tile.set_border_texture(texture)
tile.set_border_path("res://assets/cards/borders/rare.png")
```

边框素材与卡牌背景同尺寸：

- 母版：`512 × 640`
- 九宫格边距：`32 px`
- 透明 PNG

### 场上实体

节点：`BattleEntityView/WholeRoot/BorderSprite`

优先：

```text
res://assets/battle/entities/borders/<rarity>.png
```

通用回退：

```text
res://assets/battle/entities/borders/border.png
```

接口：

```gdscript
view.set_border_texture(texture)
view.set_border_path("res://assets/battle/entities/borders/rare.png")
```

边框素材与实体背景同尺寸，当前实体背景设计尺寸为 `136 × 84`，建议源图 `272 × 168`（2×）。

### 费用文字

`CardTile` 已补回 `CostLabel`：

- 节点：`CardTile/CostLabel`
- 自动显示 `CardData.cost`
- 位置在卡面右上角
- 费用图标仍由 `CostIconSprite` 承载

## 卡牌素材尺寸

| 素材 | 推荐尺寸 |
|---|---|
| 完整卡面母版 | 504 × 516 |
| 手牌显示 | 126 × 104 |
| 手牌插画区域 | 110 × 48 |
| 卡牌背景/边框 | 512 × 640 |
| 实体背景/边框 | 272 × 168（2×） |

## 默认卡面

`art_path` 为空时自动使用：

```text
res://assets/cards/art/XXXdefault.png
```

不再回退纯色文字。缺失具体文件仍显示默认卡面（如果默认图存在）。

## 实体插画放大

`BattleEntityView` 现在按实体控件的实际尺寸计算插画区域，而不再固定使用旧的 `136 × 84` 设计尺寸：

- 背景/边框按实体槽完整覆盖
- 插画区域约为槽宽的 94%、槽高的 62%
- 插画中心位于槽高约 34% 处
- 名称与攻击/生命文字会自动移到槽底部

这解决的是**旧代码固定 `ART_BOX = 124 × 58` 导致插画被限制在很小区域**的问题，不是素材本身分辨率不足。素材仍需足够大，但主要原因是显示框太小。

## 实体与手牌插画最终放大

- 实体视图整体缩放为槽位的 96%，不再随普通刷新改变大小
- 实体插画区域：槽宽 96%、槽高 70%，中心位于槽高 33%
- 实体视图只在控件尺寸变化时重新计算一次，动画以外的刷新不会改变整体大小
- 手牌插画区域：118 × 62，中心 (63, 34)
- 手牌文字区从插画下方开始，ArtSpacer 为 62

建议素材：

| 素材 | 尺寸 |
|---|---|
| 手牌插画源图 | 236 × 124（2× 118×62） |
| 实体插画源图 | 约 240 × 180（按 126×129 槽位的 96%×70% 计算） |
| 实体完整控件 | 槽位的 96% |

## 插画窗口逻辑

手牌和实体都改为“宽度铺满、上下裁切”的窗口模式：

### 手牌

- 卡牌根节点启用 `clip_contents`
- 插画宽度固定缩放为卡面宽度 `126`
- 插画高度按原图比例，超出卡面部分被裁掉
- 插画中心 Y 由 `ART_WINDOW_CENTER_Y` 控制，默认 `0.45`

```gdscript
ART_WINDOW_CENTER_Y = 0.45
```

### 实体

- `BattleEntityView` 根节点启用 `clip_contents`
- 插画宽度固定缩放为实体视图宽度
- 插画中心位于实体视图中心
- 超出实体视图的上下部分被裁切

这样完整卡牌插画会优先填满宽度，手牌/实体只显示窗口内的部分，不再使用 `contain` 留白。

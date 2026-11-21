# 场上实体素材（BattleEntityView）

所有召唤出的实体共用 `scenes/battle/BattleEntityView.tscn`；数据与图片由脚本注入。

## 空 Sprite2D 节点

| 节点 | 用途 | 显示区域/位置 |
|---|---|---|
| `BackgroundSprite` | 实体背景（通用或按稀有度） | 136 × 84，cover 缩放 |
| `ArtSprite` | 实体外观（`cards.csv` 的 `art_path`） | 124 × 58，contain 缩放 |
| `AttackIconSprite` | 攻击力图标（空素材，等你自己放） | 左下方图标位置 |
| `HealthIconSprite` | 生命值图标（空素材） | 右下方图标位置 |

数值文本在图标上方：
- `AttackLabel`：左下，显示当前攻击力
- `HealthLabel`：右下，显示当前生命值
- 不显示费用、不显示防御

## 背景素材路径

优先按稀有度读取，再回退通用背景：

```
assets/battle/entities/normal.png
assets/battle/entities/rare.png
assets/battle/entities/super_rare.png
assets/battle/entities/legend.png
assets/battle/entities/unknown.png
assets/battle/entities/background.png   # 通用兜底
```

都没有时回退到 `assets/cards/backgrounds/<rarity>.png`。

## 尺寸参考

| 素材 | 建议尺寸 | 说明 |
|---|---|---|
| 实体背景 | **272 × 168 px**（2 倍 136×84） | 四周留约 8px 安全边；可出 544×336 |
| 实体外观 | **248 × 116 px**（约 2.14:1） | 主体居中，显示框内 contain，不裁切 |
| 攻击/生命图标 | **24 × 24 px** | 透明背景 PNG；数值文字由场景 Label 显示 |

Sprite2D 节点位置在场景里直接调；数值 Label 也已在对应图标上方排好。

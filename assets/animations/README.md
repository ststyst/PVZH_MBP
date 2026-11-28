# 实体动画素材（AnimationLibrary）

这里放 3 个动画库，对应实体动画的三种模式。完整制作流程（含编辑器步骤、轨道路径口径、
常见坑）见 **`docs/AnimationDsl.md` 的「制作流程」一节**，本文件只做速查。

| 文件 | 模式 | 挂载的 AnimationPlayer | `root_node`（轨道基准） |
|---|---|---|---|
| `whole.tres` | `whole` | `WholePlayer` | `WholeRoot`（背景 + 外观 + 数值/名称整体） |
| `background.tres` | `background` | `BackgroundPlayer` | `WholeRoot/BackgroundRoot`（仅背景） |
| `art.tres` | `art` | `ArtPlayer` | `WholeRoot/ArtRoot`（仅外观） |

## 速查

1. 打开 `scenes/battle/BattleEntityView.tscn`，选中对应的 AnimationPlayer。
2. Animation 面板 → 新建动画（名字唯一）→ 设 `Length`（秒）。
3. 选中 `WholeRoot` / `BackgroundRoot` / `ArtRoot`，在 Inspector 里对
   `rotation` / `scale` / `position` / `modulate` / `pivot_offset` 点钥匙插关键帧。
4. 保存场景（三个 `.tres` 库文件会一起保存）。
5. 在 `data/cards/official/cards.csv` 的 `animation` 列按名字引用，例如：
   `when attack: play_animation(self, 'attack_swing', 'whole'); wait(0.2); play_animation(target, 'hit_flash', 'art')`

## 关键口径

- 轨道路径**相对 `root_node`**：动 `root_node` 本身时路径是 `.`（如 `.:rotation`）。
  写成 `WholeRoot:rotation` / `/BattleEntityView/WholeRoot:rotation` 都不会生效。
  在编辑器里点钥匙插入关键帧会自动写对，不要手改。
- 动画名找不到时**静默跳过**，所以“没反应”先查名字与库是否已保存。
- **不要在 `whole` 库里给 `position` 打关键帧**：位移请用伪代码的
  `move_to` / `move_back`（运行时按目标位置计算，还能控制偏移与缓动），
  两者抢同一个属性会抖。
- 攻击动画建议 ≤ 0.3s：战斗逐列结算，每列动画播完才进入下一列。
- 动画只作用场上实体（`BattleEntityView`）；手牌 `CardTile` 目前没有 AnimationPlayer。
- 通用特效：伪代码 `play_fx(self, "smoke")` 会实例化 `assets/battle/fx/smoke.tscn`
  （该目录需要自己创建）。

## 默认动画（没写动画的卡会自动用）

`data/battle/default_animation.txt`（纯文本，可直接改）是**所有卡的默认动画伪代码**：
卡牌的 `animation` 列为空或语法出错时自动回退到它。当前默认是「攻击时快速贴上去、
播 `hit`（自身）/ `hurt`（目标）、立刻归位」，所以做 `whole.tres` 时可以顺手做两个同名动画
`hit`、`hurt`，否则默认动画只有位移、没有卡面变化。

# 实体动画素材（AnimationLibrary）

这里放 3 个动画库，对应实体动画的三种模式：

| 文件 | 模式 | 作用对象 |
|---|---|---|
| `whole.tres` | `whole` | 整个实体（背景 + 外观 + 数值/名称），像一张图片一样整体旋转/缩放/颤动 |
| `background.tres` | `background` | 只作用实体背景 |
| `art.tres` | `art` | 只作用实体外观 |

## 制作方法

1. 在 Godot 中打开 `scenes/battle/BattleEntityView.tscn`。
2. 选中 `WholePlayer` / `BackgroundPlayer` / `ArtPlayer` 三个 AnimationPlayer。
3. 它们的动画库已分别指向上面 3 个 `.tres`；在动画面板里新建动画并命名（名字唯一）。
4. 动画轨道直接作用于对应的根节点：
   - `whole`：`WholeRoot`（整体）
   - `background`：`BackgroundRoot`
   - `art`：`ArtRoot`
   常用属性：`rotation`、`scale`、`position`、`modulate`、`pivot_offset`。
5. 保存后，在卡牌 CSV 的 `animation` 列用动画名引用即可。

代码会在实例化时自动加载这 3 个库；动画名找不到时会跳过（不报错）。

## 简单动画思路

- 旋转：`rotation` 0 → 0.4 → 0
- 放大/缩小：`scale` 1 → 1.15 → 1
- 颤动：`position` 在 ±3px 之间快速往返
- 模拟 3D 翻转：`scale:x` 1 → 0 → 1
- 撕裂/闪烁：`modulate` 闪烁 + 位移抖动（更复杂可做 shader/帧动画）
- 通用特效：在伪代码里写 `play_fx(self, "smoke")`，会实例化
  `assets/battle/fx/smoke.tscn`（你自己做的特效场景）。

## 卡牌动画伪代码示例

```text
when attack:
    play_animation(self, "attack_swing", "whole")
    wait(0.3)
    play_animation(target, "hit_flash", "art")
when ability:
    play_animation(self, "skill_glow", "background")
when die:
    play_animation(self, "death_tear", "whole")
```

- 模式省略时默认 `whole`
- `wait(秒)` 控制先后顺序
- 伪代码写在 `cards.csv` 的 `animation` 列

## 尺寸/节点

实体显示区域设计尺寸 136×84；背景/外观/图标 Sprite2D 与数值 Label 的布局见
`assets/battle/entities/README.md`。

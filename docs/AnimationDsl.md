# 卡牌动画伪代码（Animation DSL）

用于在卡牌 CSV 的 `animation` 列描述实体做出行为时播放哪些动画。语法与能力伪代码保持一致：
`when` 触发块 + 函数调用，支持单行/缩进块与 `;` 分隔。

## 触发块

```text
when attack:     # 自身攻击时
when ability:    # 自身特殊能力被触发时
when die:        # 自身死亡时
when cast:       # 自己打出的法术结算时
```

## 语句

### play_animation(目标, "动画名", "模式")

- 目标：`self`（自己）或 `target`（本次动作涉及的全部受击/法术目标）
- 模式：`whole`（整体）、`background`（仅背景）、`art`（仅外观）；省略默认 `whole`
- 动画名对应 `assets/animations/<模式>.tres` 中的 AnimationLibrary 动画名
- 多目标时 `target` 表示目标数组，同一条指令会同时作用在所有目标视图上

### wait(秒)

等待指定秒数，常用于“先播放自身攻击动画，等待几秒后播放目标受击动画”。

### move_to(目标, 秒[, 偏移x, 偏移y][, "缓动"])

把**自身视图整体平移**到本次动作的目标位置上（攻击者扑到受击者身上就是用它）。

- 目标只能是 `target`（可与 `play_animation` 一样是实体或英雄）
- 目标格坐标**运行时才确定**，所以不要在 AnimationPlayer/AnimatedSprite2D 里烘焙绝对坐标；
  这条指令在播放时用两个视图的 `global_position` 相减得到相对位移
- **偏移**（可选，两个数字）：叠加在目标位置上。想让攻击者停在目标的左上/旁边而不完全遮挡，
  就写 `move_to(target, 0.12, -18, -10)`（单位=设计像素，720×1280 基准）
- **缓动**（可选）：`linear` / `ease_in` / `ease_out` / `ease_in_out` / `back_out` / `bounce_out`
  - 省略时 `move_to` 用 `ease_in`（加速撞过去，收尾干脆，冲击力强）
  - `back_out` 会先越过再回正（回弹感），适合重击；`bounce_out` 是落地弹跳
  - 只给缓动不给偏移也合法：`move_to(target, 0.12, "back_out")`
- 目标实体已经死亡/视图已隐藏时，会自动用 ghost 视图定位
- 目标是英雄（没有场上视图）时，对齐到该英雄的按钮中心（偏移同样生效，例如往下偏一点）
- 平移用的是 `position` 上的 Tween，**不要**在 `whole` 模式的动画轨道里再写 `position`，两者会互相抢属性
- 位移期间该视图的 `z_index` 会被临时抬高，并临时抬升所在列，保证不被同格/相邻列遮住

### move_back(秒[, "缓动"])

回到 `move_to` 之前的位置（默认缓动 `ease_out`，减速滑回）。即使脚本里忘了写，动画播完后也会自动复位。

### play_fx(目标, "特效名")

实例化 `assets/battle/fx/<特效名>.tscn`（烟雾/爆炸等通用特效，场景由你自己制作）。
目标额外支持 `global`，表示不绑定实体、在全局特效层播放：

```text
play_fx(global, "explosion")
```

## 示例

```text
when attack:
	play_animation(self, "attack_swing", "whole")
	wait(0.3)
	play_animation(target, "hit_flash", "art")
when ability:
	play_animation(self, "skill_glow", "background")
when die:
	play_animation(self, "death_tear", "whole")
when cast:
	play_animation(self, "cast_glow", "whole")
	wait(0.2)
	play_animation(target, "magic_hit", "art")
	play_fx(global, "explosion")
```

扑击示例（移动到受击者位置 → 挥击/受击 → 归位）：

```text
when attack:
	move_to(target, 0.12)
	play_animation(self, "attack_swing", "art")
	play_animation(target, "hit_flash", "art")
	wait(0.18)
	move_back(0.12)
```

带偏移与冲击力缓动的版本（停在目标左上方，不糊住对方；撞过去带一点回弹）：

```text
when attack:
	move_to(target, 0.1, -18, -12, "back_out")
	play_animation(self, "attack_swing", "art")
	play_animation(target, "hit_flash", "art")
	wait(0.16)
	move_back(0.12, "ease_out")
```

单行写法：

```text
when attack: play_animation(self, "swing", "whole"); wait(0.2); play_animation(target, "hit", "art")
```

## CSV 写法

`animation` 列是一个字符串字段；CSV 中需要用双引号包住，内部字符串用单引号：

```csv
...,art_path,animation,deck_includable
...,"","when attack: play_animation(self, 'swing', 'whole'); wait(0.2); play_animation(target, 'hit', 'art')",1
```

## 动画库与模式

| 模式 | 文件 | 根节点 |
|---|---|---|
| whole | `assets/animations/whole.tres` | `WholeRoot`（背景+外观+数值整体） |
| background | `assets/animations/background.tres` | `BackgroundRoot` |
| art | `assets/animations/art.tres` | `ArtRoot` |

- 动画名在各自库内唯一；找不到的动画会被跳过（不报错）
- **只使用 AnimationPlayer**：不接入 AnimationTree；动画库直接挂在三个 AnimationPlayer 上
- 动画轨道常用属性：`rotation`、`scale`、`position`、`modulate`、`pivot_offset`
- “整体”模式可以像一张图片一样旋转/缩放/颤动；背景或外观也可以单独做同样的动作
- 通用特效通过 `play_fx` 或动画的 method track 触发

## 战斗层接口（联机方向）

**动画伪代码由客户端解析**，服务端只广播动作事实，不执行动画脚本：

```json
{ "seq": 42, "type": "animation", "trigger": "attack",
  "actor_id": 12, "target_ids": [7, 9],
  "hit_index": 1, "hit_count": 2 }
```

- `attack`：一次攻击；`target_ids` 可以是多个（同时攻击多个目标）
- 多段攻击/依次攻击：每段发一条独立事件，客户端每段完整重播一次 `when attack`
- `cast`：法术结算事件；`target_ids` 为全部法术目标，无目标时为空
- `ability`：能力触发；`actor_id` 为拥有者，`target_ids` 为涉及实体
- `die`：只有 `actor_id`
- 客户端根据 `card_id` 取本地 `animation` 脚本，用 `trigger` 执行；全局特效 `play_fx(global, ...)` 进全局层
- 服务端不发送牌库/手牌隐藏被动的动画事件，避免泄露信息

本地接口：

- `BattleEntityView.play_animation(name, mode) -> float`：播放并返回时长
- `BattleEntityView.play_fx(name) -> Node`
- `BattleEntityView.move_by(offset, 秒, "缓动") -> float` / `move_home(秒, "缓动") -> float` / `reset_motion()`：
  位移动画；`move_to` / `move_back` 就是调它们，`offset` 由 UI 在播放时按目标视图 + 伪代码偏移算出
- `BattleEngine.animation_cue(trigger, actor, target)` 信号：本地/AI 战斗的动画请求
- 卡牌载入时会解析 `animation` 列到 `CardData.animation_script`；语法错误记入
  `CardDatabase.load_errors` 与编译器报告

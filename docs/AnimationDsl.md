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

**执行模型**：一个 `when` 块里的语句按顺序处理，但只有 `wait` 会真正阻塞；
`play_animation` / `play_fx` / `move_to` 都是「立刻开始、不等待」。
整个 cue 播完才会处理队列里的下一条动作（时长取所有动画/位移里**最长的那个**），
所以要让动作先后发生，必须用 `wait` 隔开。

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

| 模式 | 库文件 | AnimationPlayer（场景内节点） | `root_node`（轨道基准） | 作用内容 |
|---|---|---|---|---|
| whole | `assets/animations/whole.tres` | `WholePlayer` | `WholeRoot` | 背景 + 外观 + 数值/名称，整体像一张图 |
| background | `assets/animations/background.tres` | `BackgroundPlayer` | `WholeRoot/BackgroundRoot` | 只作用实体背景 |
| art | `assets/animations/art.tres` | `ArtPlayer` | `WholeRoot/ArtRoot` | 只作用实体外观 |

- 动画名在各自库内唯一；找不到的动画会被跳过（不报错，所以拼错名字只会“什么都不发生”）
- **只使用 AnimationPlayer**：不接入 AnimationTree；三个库由 `scenes/battle/BattleEntityView.tscn` 的
  `libraries/` 挂着，`battle_entity_view.gd` 只负责在运行时按名字播放
- **轨道路径必须相对 `root_node`**：要动 `root_node` 本身（例如 whole 模式动 `WholeRoot`）时，
  轨道路径是 `.`（带子属性就是 `.:rotation`、`.:scale`）。写成 `WholeRoot:rotation` 或
  `/BattleEntityView/WholeRoot:rotation` **都不会生效**（`root_node` 会再拼一层，找不到节点就静默跳过）。
  在编辑器里用节点 Inspector 上的钥匙图标插关键帧时，Godot 会自动算对路径，**不要手改**。
- 动画轨道常用属性：`rotation`、`scale`、`position`、`modulate`、`pivot_offset`
- “整体”模式可以像一张图片一样旋转/缩放/颤动；背景或外观也可以单独做同样的动作
- 通用特效通过 `play_fx` 或动画的 method track 触发（`play_fx` 需要 `assets/battle/fx/<名字>.tscn`）

## 制作流程：给一张卡配动画

### 第 1 步：在编辑器里做动画

1. 编辑器打开 `res://scenes/battle/BattleEntityView.tscn`（所有场上实体共用这个场景）。
2. 选中 `WholePlayer`（整体）/ `BackgroundPlayer`（背景）/ `ArtPlayer`（外观）之一。
3. 底部 **Animation** 面板 → 「Animation」下拉框旁边点 **新建动画**，命名（例如 `attack_swing`）。
   - 名字在各库内唯一；不同模式可以同名，但建议按用途命名：`attack_swing` / `hit_flash` / `death_tear` / `skill_glow`。
   - 时长改面板上方的 `Length`（秒）。**建议攻击动画 ≤ 0.3s**：动画时长会直接决定战斗节奏（见第 3 步）。
4. 选中要动的节点（例如 `WholeRoot`），在右侧 Inspector 里对 `rotation` / `scale` / `position` /
   `modulate` / `pivot_offset` 点**钥匙图标**插入关键帧，然后拖动时间轴调出动作。
   - 编辑器会自动把轨道路径写成相对 `root_node` 的正确形式（whole 模式就是 `.`）。
5. **保存**（Ctrl+S 保存场景）。动画写在 `assets/animations/whole.tres` 这类外部库文件里，
   保存场景时 Godot 会把被改动的库一起保存（如果弹出「保存 whole.tres」，选保存）。

> 三个库文件当前是空的（只有 `[resource]`），第一次新建动画后才会长出内容，这是正常的。

### 第 2 步：在卡牌 CSV 里引用

编辑 `data/cards/official/cards.csv` 的 `animation` 列（见本文末尾「CSV 写法」），
把动画名填进伪代码：

```text
when attack:
	move_to(target, 0.1, -18, -12, "back_out")
	play_animation(self, "attack_swing", "whole")
	play_animation(target, "hit_flash", "art")
	wait(0.16)
	move_back(0.12)
```

### 第 3 步：生效与验证

- 运行战斗（准备界面 → 对战电脑），打出这张卡/让它攻击，观察效果。
- 卡牌动画在 `CardDatabase` 载入时解析到 `CardData.animation_script`；**CSV 语法错误**会进
  `CardDatabase.load_errors` 与卡包编译报告，能用开发者面板看到。
- **如果编译过卡包**（`user://card_packs/compiled/official.cardpack` 存在），`CardDatabase.reload()`
  会优先读这个包，改 CSV 不生效：需要重新编译（开发者面板的编译入口）或
  `CardDatabase.clear_compiled_official_pack()` 再 reload。当前仓库没有这个包，改 CSV 重开战斗即可。
- 节奏影响：一个攻击 cue 的时长 = 该 cue 里所有动画/位移里**最长的那个**（`wait` 会额外串行等待），
  战斗阶段是逐列结算、每列动画播完再等 `COMBAT_COLUMN_GAP = 0.2s` 进入下一列。
  粗算：5 列各打一次、动画 0.3s → 一轮战斗约 `5 × (0.3 + 0.2) ≈ 2.5s`；
  想更紧凑就把攻击动画压到 0.15~0.2s，或把 `COMBAT_COLUMN_GAP` 调小。

### 常见坑

| 现象 | 原因 |
|---|---|
| 动画完全没反应 | 动画名拼错（静默跳过）；库文件没保存；轨道路径不是相对 `root_node` |
| 动画播了但卡面没变 | 模式选错：`art` 只动外观、`background` 只动背景、数值/名称要 `whole` |
| 整体位置在抖 | 在 `whole` 库里给 `position` 打了关键帧，同时又用了 `move_to`（Tween 和动画抢同一属性）。位移统一交给 `move_to` / `move_back` |
| 动画比预期短 | `play_animation` 只负责播放，cue 的等待时长取最长项；多段动作要配 `wait` |
| 改了 CSV 没变化 | 存在编译过的 `official.cardpack`（见上） |
| 手牌/卡面没有动画 | 当前只有场上实体（`BattleEntityView`）有 AnimationPlayer；手牌 `CardTile` 不支持动画 |

## 默认动画伪代码（卡牌没写 / 写错时自动用）

**文件**：`data/battle/default_animation.txt`（纯文本，可直接编辑，不需要改任何脚本）

```text
when attack:
    move_to(target, 0.06, -18, 0, "ease_in")
    play_animation(self, "hit", "whole")
    play_animation(target, "hurt", "whole")
    wait(0.02)
    move_back(0.06, "ease_out")
```

- **什么时候用**：某张卡的 `animation` 列为空，**或**那列伪代码解析出错（`errors` 非空）时，
  卡牌会自动改用这份默认动画（`CardAnimationScript.apply_fallback()`）。
  语法错误仍然会出现在 `CardDatabase.load_errors` 与编译报告里，不会被静默吞掉。
- **生效范围**：CSV 载入（`CardDatabase`）、卡包编译（编译产物里写入默认动画）、卡包载入
  （`CardData.from_pack_dict`）三条路径一致。
- **改完何时生效**：默认文本每次都在解析时读文件，所以保存后**重新载入卡牌**
  （重开战斗 / 开发者面板重载卡数据库）即生效；不用重启编辑器，也不用改代码。
- **注意**：默认动画里引用的 `hit` / `hurt` 需要在 `assets/animations/whole.tres` 里做出同名动画，
  否则这两条会被静默跳过，只剩位移（这正是现在的状态，等你自己补动画）。
- 想临时验证回退是否生效：把 `card_animation_script.gd` 的 `DEFAULT_SOURCE_PATH` 指到别的文件，
  或直接改这个 txt 看战斗表现即可。

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

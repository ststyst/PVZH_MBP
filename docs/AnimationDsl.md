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
- `BattleEngine.animation_cue(trigger, actor, target)` 信号：本地/AI 战斗的动画请求
- 卡牌载入时会解析 `animation` 列到 `CardData.animation_script`；语法错误记入
  `CardDatabase.load_errors` 与编译器报告

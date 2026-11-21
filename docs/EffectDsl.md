# 卡牌能力 DSL（已定稿：方案 D）

> 采用**函数调用 + 缩进块**的混合语法；支持变量、四则运算、条件、循环、条件目标与事件块。
> 解析器：`scripts/data/effects/effect_parser.gd`；执行器：`effect_runner.gd`；
> 编译产物：`CardEffectScript`（挂在 `CardData.ability_script` 上）。
> CSV 的能力列在载入时编译，语法/语义错误会写进 `CardDatabase.load_errors`（不阻断其他卡）。

## 一、实体与锦囊的语义区别

- **锦囊（spell）**：能力属于这张牌，**打出时执行一次**顶层语句；**不允许** `when` 事件块。
- **环境（environment）**：顶层语句在打出时执行（同时战斗层把所选列环境改为这张牌）；**不允许** `when` 事件块。
- **实体（entity）**：能力属于**召唤出来的实体**，必须写在 `when` 事件块中（例如 `when enter:` 表示该实体入场）；
  实体牌本身被“打出”时没有任何锦囊式效果。顶层语句会被判定为非法。
- 事件块**默认只响应自己**（触发事件的实体 == 技能拥有者）。要监听其他实体，用过滤条件（见事件一节）。
- 技能拥有者用 `self` 表示；触发事件的实体用 `event` 表示。

## 二、可用原语（语句）

| 原语 | 参数 | 说明 |
|---|---|---|
| `summon(card_name, count = 1)` | 英文名、数量 | 召唤实体（实体牌入场也走它） |
| `draw_cards(count)` | 数值 | 抽牌 |
| `deal_damage(target, amount)` | 目标、数值 | 造成伤害 |
| `heal(target, amount)` | 目标、数值 | 治疗 |
| `gain_shield(target, amount)` | 目标、数值 | 加护甲 |
| `buff_stats(target, attack, health)` | 目标、两个增减值 | 修改攻/血 |
| `gain_energy(amount)` | 数值 | 获得费用 |
| `give_keyword(target, keyword, value = 0)` | 目标、词缀 id、数值 | 赋予词缀；已有同词缀则累加数值（如先攻 2 + 先攻 3 = 先攻 5） |
| `destroy(target)` | 目标 | 消灭 |
| `choose(count, selector)` | 数量、选择器 | 声明最多选择 N 个目标（玩家选择；`chosen` 为目标数组） |
| `gain_attack(amount)` | 数值 | 修改当前卡牌实例的攻击（用于牌库/手牌被动，打出后转为实体攻击） |
| `reduce_cost(amount)` | 数值 | 修改当前卡牌实例的费用（最低 0，用于手牌被动） |
| `add_marker(name, amount)` | 标志物名、增减值 | 修改玩家特殊标志物数量（允许负数） |
| `remove_marker(name, amount)` | 标志物名、数量 | 减少玩家特殊标志物（等价于负数 add_marker） |
| `move_entity(target, column, slot)` | 实体、列(0-4)、位置(0普通/1组队) | 把实体移动到空位；成功触发 `position_changed` |

多目标选择器（`all_enemies` / `all_allies` / `other_allies`）会被解释器**逐个**调用原语。

## 三、表达式与变量

- 变量：`x = 2 + 3 * 2`（后续语句可用 `x`）
- 四则运算：`+ - * /`（整数运算，除数为 0 会记录运行错误）
- 比较：`== != < <= > >=`；逻辑：`and` `or` `not`
- 查询函数：`attack(target)`、`health(target)`、`shield(target)`、`min(a,b)`、`max(a,b)`、`has_tribe("pea")`、`marker_count("名字")`（`marker_count` 用于玩家特殊标志物数量）
- 字符串可用单引号或双引号：`side == 'enemy'` / `side == "enemy"`

## 四、目标选择器

| 选择器 | 含义 |
|---|---|
| `self` | 技能拥有者（实体自己） |
| `event` | 触发本次事件的实体 |
| `chosen` | 玩家本次选中的目标（**数组**；可以用 `choose` 选多个） || `chosen_if(<条件>)` | 选中目标中满足条件的（没有则本次原语跳过） |
| `hero` / `enemy_hero` | 我方 / 敌方英雄 |
| `all_enemies` / `all_allies` | 所有敌方 / 友方实体 |
| `other_allies` | 除技能拥有者外的友方实体 |
| `random_enemy` / `random_ally` | 随机敌方 / 友方实体 |

条件目标示例：`destroy(chosen_if(attack <= 3))`、`deal_damage(chosen_if(has_tribe('pea') and side == 'enemy'), 4)`。

## 五、事件

目前支持：

`enter`（入场）、`die`（死亡）、`attack`（攻击）、`attacked`（受击）、`healed`（被治疗）、
`attack_changed`（攻击力变化）、`health_changed`（生命值变化）、`turn_start`（回合开始）、`turn_end`（回合结束）、
`ally_die`（友方实体死亡，可触发牌库/手牌中的卡牌被动）、`position_changed`（实体被卡牌效果移动位置）。

### 区域被动

`ally_die` 会对技能拥有者的**手牌/牌库卡牌实例**触发，配合 `zone` 过滤：

```
when ally_die(zone == 'deck'):
    gain_attack(1)

when ally_die(zone == 'hand'):
    gain_attack(1)
    reduce_cost(1)
```

`zone` 取值为 `'deck'` / `'hand'` / `'board'` / `'discard'`。手牌/牌库中的攻击与费用修正会跟随卡牌移动，
在打出时转为实体攻击/实际费用；费用最低为 0。

> 扩展事件只需改 `EffectParser.EVENTS` 与战斗层触发点。

### 事件过滤

```
when enter(side == 'enemy' and attack > 3):
    deal_damage(event, 2)
```

过滤条件可用的字段：

| 字段 | 说明 |
|---|---|
| `side` | `'self'` / `'ally'` / `'enemy'`；`side == 'any'` 表示不过滤阵营 |
| `class` | 职业 id，如 `'solar'` |
| `tribes` + `has_tribe("pea")` | 流派检测 |
| `attack` / `health` / `shield` | 数值检测（支持四则/比较） |

默认（不写过滤）= 只响应自己。监听其他实体请显式写条件，例如 `side != 'self'`、`side == 'enemy'`、`side == 'any'`。

## 六、多异能

同一张卡可以写**多个 `when` 块**（换行或 `;` 分隔），例如“死亡时给 2 费 + 入场时 +2 攻”：

```
when die: gain_energy(2); when enter: buff_stats(self, 2, 0)
```

执行时按事件分别触发，互不影响。也可以同一个事件写多个块（都会按顺序触发）。

## 七、示例

## 七、示例

实体（入场获得 2 费）：

```
when enter: gain_energy(2)
```

实体（其他敌方实体入场且攻击力 > 3 时，抽 1 张牌）：

```
when enter(side == 'enemy' and attack > 3):
    draw_cards(1)
```

实体（亡语治疗英雄）：

```
when die: heal(hero, 3)
```

锦囊（对选中目标造成 6 点伤害）：

```
deal_damage(chosen, 6)
```

锦囊（随机 3 次 1 点伤害）：

```
repeat(3): deal_damage(random_enemy, 1)
```

锦囊（条件目标）：

```
destroy(chosen_if(attack <= 3))
```

锦囊（两条语句）：

```
deal_damage(all_enemies, 2); heal(all_allies, 2)
```

### 区域/多目标示例

入场选择最多两个其他友方实体 +2 攻击（不足两个也可打出）：

```
when enter:
    choose(2, "other_allies")
    buff_stats(chosen, 2, 0)
```

牌库内友方死亡时自身攻击 +1：

```
when ally_die(zone == 'deck'):
    gain_attack(1)
```

手牌内友方死亡时自身攻击 +1、费用 -1：

```
when ally_die(zone == 'hand'):
    gain_attack(1)
    reduce_cost(1)
```

入场检查特殊标志物：

```
when enter:
    if marker_count("special_marker_1") > 1:
        add_marker("special_marker_2", 3)
        add_marker("special_marker_3", -1)
```

移动实体并触发位置事件：

```
move_entity(event, 2, 0)
```

赋予/叠加词缀数值（先攻 2）：

```
give_keyword(self, "first_strike", 2)
```

若目标已有先攻 2，则变为先攻 4；不同词缀使用不同键，数值互不影响。

拥有位置被动的实体：

```
when position_changed:
    add_marker("moved", 1)
```

注意：打出组队实体时把原实体挤到同列另一格，属于“放置规则”，**不会触发** `position_changed`；只有卡牌效果调用 `move_entity` 才会触发。

特殊标志物名字是任意英文字符串，不注册种类，数量允许负数。

## 八、书写规则

- 块可以用两种写法：
  - 多行缩进（推荐）：
    ```
    if attack(chosen) > 3:
        destroy(chosen)
    ```
  - 冒号后单个语句（CSV 一行很方便）：`repeat(3): deal_damage(random_enemy, 1)`
- `#` 是注释；`;` 等价于换行分隔语句。
- 缩进用空格（Tab 按 4 空格计），同一块内必须一致。
- 未定义变量、除以 0、未知函数/事件、参数数量错误都会记录错误；**运行期错误不会中断战斗**。

## 九、战斗层接入（实现 `EffectContext`）

战斗层需要实现 `scripts/data/effects/effect_context.gd`：

```gdscript
func set_self_target(handle) -> void          # 设置技能拥有者实体
func set_event_target(handle) -> void         # 由解释器调用，设置事件实体
func resolve_selector(selector: String) -> Array   # 返回句柄数组
func describe_entity(handle) -> Dictionary    # { side, class, tribes, attack, health, shield }
func summon(card_name, count) / draw_cards(n) / deal_damage(handle, n) / heal(...) / ...
```

调用方式：

```gdscript
# 实体能力
var ctx := MyBattleEffectContext.new()
ctx.set_self_target(entity_handle)
card.ability_script.run_event(ctx, "enter", entity_handle)

# 锦囊
var ctx2 := MyBattleEffectContext.new()
card.ability_script.run_on_play(ctx2)
```

`RecordingEffectContext` 是现成的测试实现，可直接断言原语调用。

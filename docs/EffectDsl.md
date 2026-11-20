# 卡牌能力 DSL（已定稿：方案 D）

> 采用**函数调用 + 缩进块**的混合语法；支持变量、四则运算、条件、循环、条件目标与事件块。
> 解析器：`scripts/data/effects/effect_parser.gd`；执行器：`effect_runner.gd`；
> 编译产物：`CardEffectScript`（挂在 `CardData.ability_script` 上）。
> CSV 的能力列在载入时编译，语法/语义错误会写进 `CardDatabase.load_errors`（不阻断其他卡）。

## 一、实体与锦囊的语义区别

- **锦囊（spell）**：能力属于这张牌，**打出时执行一次**顶层语句；**不允许** `when` 事件块。
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
| `give_keyword(target, keyword)` | 目标、词缀 id（字符串） | 赋予词缀 |
| `destroy(target)` | 目标 | 消灭 |

多目标选择器（`all_enemies` / `all_allies`）会被解释器**逐个**调用原语。

## 三、表达式与变量

- 变量：`x = 2 + 3 * 2`（后续语句可用 `x`）
- 四则运算：`+ - * /`（整数运算，除数为 0 会记录运行错误）
- 比较：`== != < <= > >=`；逻辑：`and` `or` `not`
- 查询函数：`attack(target)`、`health(target)`、`shield(target)`、`min(a,b)`、`max(a,b)`、`has_tribe("pea")`（仅事件过滤/条件目标中有意义）
- 字符串可用单引号或双引号：`side == 'enemy'` / `side == "enemy"`

## 四、目标选择器

| 选择器 | 含义 |
|---|---|
| `self` | 技能拥有者（实体自己） |
| `event` | 触发本次事件的实体 |
| `chosen` | 玩家本次选中的目标 |
| `chosen_if(<条件>)` | 选中目标中满足条件的（没有则本次原语跳过） |
| `hero` / `enemy_hero` | 我方 / 敌方英雄 |
| `all_enemies` / `all_allies` | 所有敌方 / 友方实体 |
| `random_enemy` / `random_ally` | 随机敌方 / 友方实体 |

条件目标示例：`destroy(chosen_if(attack <= 3))`、`deal_damage(chosen_if(has_tribe('pea') and side == 'enemy'), 4)`。

## 五、事件

目前支持：

`enter`（入场）、`die`（死亡）、`attack`（攻击）、`attacked`（受击）、`healed`（被治疗）、
`attack_changed`（攻击力变化）、`health_changed`（生命值变化）。

> 后续还会扩展更多事件（你提到“之后再说”），扩展点只需改 `EffectParser.EVENTS` 与战斗层触发点。

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

## 六、示例

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

## 七、书写规则

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

## 八、战斗层接入（实现 `EffectContext`）

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

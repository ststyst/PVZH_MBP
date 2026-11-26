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
| `summon(card_name)` | 英文名 | 在合法位置召唤一个实体；每次语句只召唤一个 |
| `summon(card_name, column)` | 英文名、列 | 法术/环境：绝对列 1~5；实体异能：相对自身列 -4~4（0=本列） |
| `summon(card_name, min_column, max_column)` | 英文名、范围 | 在范围内随机尝试一个合法列；坐标含义同上 |
| `place_environment(offset, card_name)` | 相对列偏移、环境英文名 | 在基准列偏移位置尝试放置环境；受保护环境不可覆盖 |
| `apply_buff(target, buff_id, amount = 1)` | 实体、Buff id、层数 | 施加内置 Buff/Debuff |
| `remove_buff(target, buff_id)` | 实体、Buff id | 解除内置 Buff/Debuff |
| `force_attack(target)` | 实体 | 让实体按当前列目标攻击一次；冰冻时失败；触发额外攻击事件 |
| `remove_entity(target)` | 实体 | 将实体移出战场；不触发死亡/亡语 |
| `evolve(filter)` | 卡牌筛选表达式 | 实体牌专属：可放置到已有友方实体位置并移除原实体；筛选匹配时触发 `evolved` |
| `base()` | — | 实体牌专属：允许其他非底座实体放置到自身位置；触发 `mounted` |
| `add_random_cards_to_deck(target, count, filter)` | 目标、数量、筛选条件 | 从卡牌数据库筛选随机牌，塞入目标阵营牌库随机位置 |
| `add_random_cards_to_hand(target, count, filter)` | 目标、数量、筛选条件 | 从卡牌数据库筛选随机牌，塞入目标阵营手牌随机位置 |
| `choose_column()` | — | 锦囊打出时要求玩家选择一列；`chosen_column` 生效 |
| `entities_in_column(min, max, side, min_attack = 0)` | 相对偏移、偏移、阵营、最低攻击 | 返回基准列偏移范围内的实体数组 |
| `draw_cards(count)` | 数值 | 抽牌 |
| `deal_damage(target, amount)` | 目标、数值 | 造成伤害 |
| `heal(target, amount)` | 目标、数值 | 治疗 |
| `gain_shield(target, amount)` | 目标、数值 | 加防御 |
| `buff_stats(target, attack, health)` | 目标、两个增减值 | 修改攻/血 |
| `gain_energy(amount)` | 数值 | 获得费用 |
| `give_keyword(target, keyword, value = 0)` | 目标、词缀 id、数值 | 赋予词缀；已有同词缀则累加数值（如先攻 2 + 先攻 3 = 先攻 5）；受卡牌种类白名单限制 |
| `give_keyword` 的 `bullseye` | — | 伤害类型变为必中；必中伤害不增加充能护盾充能 |
| `destroy(target)` | 目标 | 消灭 |
| `choose(count, selector)` | 数量、选择器 | 声明最多选择 N 个目标（玩家选择；`chosen` 为目标数组） |
| `gain_attack(amount)` | 数值 | 修改当前卡牌实例的攻击（用于牌库/手牌被动，打出后转为实体攻击） |
| `reduce_cost(amount)` | 数值 | 修改当前卡牌实例的费用（最低 0，用于手牌被动） |
| `add_marker(name, amount)` | 标志物名、增减值 | 修改玩家特殊标志物数量（允许负数） |
| `remove_marker(name, amount)` | 标志物名、数量 | 减少玩家特殊标志物（等价于负数 add_marker） |
| `move_entity(target)` | 实体 | 玩家在出牌时选择目标实体的移动位置；只能在该实体所属阵营半场，且排除当前位置 |
| `move_entity(target, column, slot)` | 实体、列(0-4)、位置(0普通/1组队) | 直接移动到固定位置；成功触发 `position_changed` |

多目标选择器（`all_enemies` / `all_allies` / `other_allies`）会被解释器**逐个**调用原语。

除原语外，语句层面还有三种控制结构（不是原语，写法见第十节）：

| 语句 | 说明 |
|---|---|
| `if 条件:` / `elif 条件:` / `else:` | 条件分支；`elif` 可连续使用，等价于 `else:` 里再套 `if` |
| `repeat(n):` | 重复执行块 n 次（上限 100） |
| `for_each(目标) as 名称:` | 对目标数组逐个执行**整个块**，块内可读当前目标的事实变量 |

## 三、表达式与变量

- 变量：`x = 2 + 3 * 2`（后续语句可用 `x`）
- 四则运算：`+ - * /`（整数运算，除数为 0 会记录运行错误）
- 比较：`== != < <= > >=`；逻辑：`and` `or` `not`
- 查询函数：`attack(target)`、`health(target)`、`max_health(target)`、`shield(target)`、`defense(target)`、`cost(target)`、`highest(目标集合, 数值名[, 条件])`、`lowest(目标集合, 数值名[, 条件])`、`entities_matching(筛选)`、`entities_matching(范围, 筛选)`、`min(a,b)`、`max(a,b)`、`has_tribe("pea")`、`has_tribe("pea", target)`、`has_keyword("frost")`、`has_keyword("frost", target)`、`keyword_value("first_strike", target)`、`has_buff("frozen", target)`、`environment_kind([target])`、`environment_owner([target])`、`is_entity(target)`、`marker_count("名字")`（`marker_count` 用于玩家特殊标志物数量）
- 单参数形式读“当前作用域目标”（事件触发者 / `for_each` 当前目标），双参数形式显式指定实体；`defense` 与 `shield` 等价
- `environment_kind` / `environment_owner` 的 0 参数形式读当前基准列（实体自身列 / 锦囊选中的列），1 参数形式读指定实体所在列；详见“列、实体事件与环境”一节
- 字符串可用单引号或双引号：`side == 'enemy'` / `side == "enemy"`

### 变量赋值示例

```text
x = 2 + 3 * 2
deal_damage(chosen, x)
```

功能：先计算 `2 + 3 * 2`，结果保存到 `x`，后续语句可用 `x`；按乘法优先，实际伤害为 8。

```text
damage = 2
damage = damage + 1
deal_damage(chosen, damage)
```

功能：变量可以重复赋值；第二次读取旧值并加 1，最终造成 3 点伤害。

```text
bonus = 0
if marker_count("充能") >= 3:
	bonus = 2
deal_damage(all_enemies, 2 + bonus)
```

功能：默认额外伤害为 0；标志物数量达到 3 时额外伤害变为 2；对全体敌人造成 2 或 4 点伤害。

```text
target = chosen
if attack(chosen) <= 3:
	destroy(target)
```

功能：把玩家选择的目标保存到 `target`，根据目标攻击力判断，满足条件时消灭该目标。

```text
selector = 'enemy_entities'
choose(1, selector)
destroy(chosen)
```

功能：用变量保存目标选择器字符串；让玩家从敌方实体中选择一个；消灭选择结果。

```text
times = 2
repeat(times):
	deal_damage(random_enemy, 1)
```

功能：变量决定循环次数；这里随机对敌人造成两次 1 点伤害。

```text
amount = attack(self) / 2
heal(self, amount)
```

功能：变量可以保存查询结果和四则运算结果；治疗量等于自身攻击力的一半（整数除法）。

### 变量可以保存的内容

- 整数
- 字符串
- 布尔值
- 目标句柄，如 `chosen`、`self`、`enemy_hero`
- 目标数组，如 `all_enemies`
- 查询结果，如 `attack(self)`、`health(chosen)`
- 四则运算结果
- 比较结果

### 变量限制

- 没有 `var x = ...` 声明关键字，直接写 `x = ...`
- 不支持 `+=`、`-=`、`++`，统一写成 `x = x + 1`
- 不支持数组下标访问，如 `targets[0]`
- 不支持属性赋值，如 `self.attack = 3`
- 变量不能跨卡牌、跨事件或跨回合保存
- 每次 `run_on_play` 或事件响应开始时变量表会清空
- 同一次能力结算内变量可以连续使用
- `if` 内赋值的变量在 `if` 外仍然有效，当前没有块级变量作用域

```text
x = 1
if attack(self) > 2:
	x = 3
deal_damage(chosen, x)
```

上面 `if` 内赋值的 `x` 在 `if` 外部仍然有效；使用时注意不要在不同分支里意外覆盖同名变量。

## 四、目标选择器

| 选择器 | 含义 |
|---|---|
| `self` | 技能拥有者（实体自己） |
| `event` | 触发本次事件的实体 |
| `damage_source` | 伤害类事件（`damaged` / `hero_damaged`）的来源；无来源时为空数组 |
| `chosen` | 玩家本次选中的目标（**数组**；可以用 `choose` 选多个） |
| `chosen_if(<条件>)` | 选中目标中满足条件的（没有则本次原语跳过） |
| `hero` / `enemy_hero` | 我方 / 敌方英雄 |
| `all_enemies` / `all_allies` | 所有敌方 / 友方实体 |
| `other_allies` | 除技能拥有者外的友方实体 |
| `random_enemy` / `random_ally` | 随机敌方 / 友方实体 |

条件目标示例：`destroy(chosen_if(attack <= 3))`、`deal_damage(chosen_if(has_tribe('pea') and side == 'enemy'), 4)`。

## 五、事件

目前支持：`enter`（入场）、`die`（死亡）、`attack`（攻击）、`attacked`（受击）、`damaged`（实际受到伤害）、
`hero_damaged`（英雄受到有效伤害）、
`healed`（被治疗）、`attack_changed`（攻击力变化）、`health_changed`（生命值变化）、`turn_start`（回合开始）、
`turn_end`（回合结束）、`ally_die`（友方实体死亡，可触发牌库/手牌被动）、`position_changed`（被卡牌移动）、
`buff_applied` / `buff_removed`（Buff 添加/移除）、`extra_attack`（额外攻击）、`after_attack`（攻击动作完成）、
`damage_dealt`（自身造成有效伤害）、`evolved`（进化成功）、`mounted`（底座被放置实体）、
`tombstone_enter`（埋入墓碑）、`tombstone_reveal`（墓碑揭示）、`transformed`（实体被变形）、
`hand_transformed`（手牌被变形）、`drawn`（抽到牌）、`hand_played`（手牌被打出）、
`ally_attack_gained`（友方攻击力提升）。

### 事件触发判定

- `attack`：每次实际发起攻击都触发；双重打击的第二次也触发
- `extra_attack`：`force_attack` 或狂热追加攻击触发；双重打击第二次不触发
- `damaged`：只有在隐形、实体防御、无敌、锦囊免疫等全部结算后，**最终伤害 > 0** 才触发；
  致命也要求最终伤害 > 0
- `healed`：实际回复生命或生命值增益成功时触发
- `die`：生命值降至 1 以下后触发；被 `remove_entity` 移除不触发
- `tombstone_enter`：实体埋入墓碑时触发，不触发 `enter`
- `tombstone_reveal`：Z 方锦囊阶段结束揭示时触发，随后触发 `enter`
- Buff 光环来源离场时只移除该来源提供的 Buff，不重复移除其他来源
- 事件默认只响应自己；环境/底座监听其所在列/挂载；需要监听其他实体时使用过滤条件

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

### 多目标锦囊

锦囊可以在顶层声明多目标选择，`chosen` 随后是目标数组：

```text
choose(2, "all_enemies")
deal_damage(chosen, 2)
```

- `count` 是最多选择数量
- 可用选择器：`all_enemies` / `all_allies` / `other_allies` 等候选实体
- UI 使用与实体入场相同的 `handles` 数组；选完后点击“确认目标”
- 引擎 `play_card` 的 `target.handles` 会校验数量与候选范围

### 事件过滤

```
when enter(side == 'enemy' and attack > 3):
	deal_damage(event, 2)
```

### 连锁结算顺序

事件触发会**深度优先立即结算**。例如“全体友方 +1 攻击”：

1. 目标实体攻击 +1，触发 `attack_changed`
2. 监听攻击力变化的实体立即结算（例如自己治疗 +1）
3. 治疗改变生命，触发 `health_changed`
4. 手牌中的 `health_changed` 被动立即结算（例如费用 -1）
5. 回到第 1 步继续处理下一个被增益的实体，直到本次法术所有目标处理完
6. 本次出牌行为才算结束，期间当前玩家不能再次出牌

每次出牌/战斗行为有连锁上限（`data/server/server_config.json` 的
`match.effect_resolution_limit`，默认 100）；超过后强制结束后续连锁，防止同类能力无限循环卡死。

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

移动实体并触发位置事件（固定位置）：

```text
move_entity(event, 2, 0)
```

把敌方实体移动到敌方半场的指定位置（玩家选择）：

```text
choose(1, "all_enemies")
move_entity(chosen)
```

规则：

- 单参数 `move_entity(target)` 会要求玩家选择位置；位置候选来自**被移动实体所属阵营**的半场
- 候选位置排除该实体当前所在位置
- 目标阵营的合法位置与打出实体牌一致：空格可放；已有同阵营实体时，只要**该列已有实体或新实体至少一方有 `team_up`**，就可以挤压到另一格
- 移动实体本身不需要具备 `team_up`；若目标格是已有 `team_up` 实体，普通实体也能触发挤压
- 移动实体带 `team_up` 移入已有友方实体格时，原实体会被挤到同列另一格；这属于放置挤压，**不触发** `position_changed`
- 被移动的实体本身会触发一次 `position_changed`
- 不能把实体移动到另一阵营半场

### 召唤位置

```text
summon("gnoll", 1)          # 法术：绝对第 1 列
summon("gnoll", -1)         # 实体异能：相对自身左一列
summon("gnoll", 2, 4)       # 在范围内随机尝试合法列
```

- 法术/环境中的数字是绝对列，合法范围 1~5
- 实体异能中的数字是相对列，合法范围 -4~4；0 表示自身所在列
- 范围形式会在范围内随机选择列，并逐个尝试；全部不合法则放弃召唤
- 召唤不会挤开已有实体；列满或不满足组队条件时该列召唤失败
- 每一条 `summon(...)` 语句只召唤一个实体；需要多个实体就写多条语句

### 列、实体事件与环境

实体事件条件中可使用 `column`（相对技能拥有者所在列）和 `column_abs`（绝对列 1~5）：

```text
when enter(side == 'ally' and column == -1):
	buff_stats(entities_in_column(1, 1, "ally", 4), 1, 0)
```

上例：左侧一列有友方实体入场时，为右侧一列攻击力至少 4 的友方实体 +1 攻击。

锦囊选择一列：

```text
choose_column()
destroy(entities_in_column(0, 0, "both"))
```

范围列：

```text
choose_column()
destroy(entities_in_column(-1, 1, "both"))
```

实体异能按自身列偏移放置环境：

```text
when enter:
	place_environment(-1, "sunny_field")
```

锦囊选择一列后在该列放置环境（`place_environment` 的基准列就是选中的列）：

```text
choose_column()
place_environment(0, "sunny_field")
```

- 环境归属方是打出它的锦囊/实体/环境的拥有者；被覆盖或无法覆盖时 `place_environment` 静默失败（返回 false，不中断脚本）
- 初始环境（高地/水池/默认）不可被覆盖，见下方 `protected_environments`

环境牌的事件能力就是该环境所在列的效果：

```text
when turn_end:
	heal(entities_in_column(0, 0, "ally"), 1)

when enter(side == 'enemy'):
	deal_damage(event, 5)
```

- 环境拥有者决定 `side` 的基准
- 环境监听自己所在列的实体事件；`turn_start` / `turn_end` 每列触发一次
- `place_environment` 和普通环境打出都受服务器 `protected_environments` 限制
- `column` 对实体/环境以自身所在列为 0；对无基准的上下文回退为绝对 1~5 列
- 初始环境没有打出者，视为中立；中立环境不能执行需要判断 ally/enemy 的效果

### 读取列的环境（种类 / 归属方）

- `environment_kind()`：当前基准列的环境种类；实体能力读自身列，`choose_column()` 锦囊读选中的列
- `environment_kind(target)`：指定实体所在列的环境种类（环境 id，如 `highground` / `water` / `default` / 环境牌英文名）
- `environment_owner()` / `environment_owner(target)`：该列环境的归属方，相对技能拥有者返回 `ally` / `enemy` / `neutral`；初始环境没有打出者，返回 `neutral`
- 目标不是实体、或实体已离场时返回空字符串

锦囊选择一个敌方实体，按目标实体所在列的环境种类改变攻击力：

```text
choose(1, 'enemy_entities')
if environment_kind(chosen) == 'highground' or environment_kind(chosen) == 'water' or environment_kind(chosen) == 'default':
	buff_stats(chosen, -2, 0)
else:
	buff_stats(chosen, -4, 0)
```

上例：目标在初始环境（高地/水池/默认）时攻击力 -2，否则 -4。

实体入场时若自身所在列的环境属于我方，则获得攻击力 +2（初始环境为中立，不会触发）：

```text
when enter:
	if environment_owner(self) == 'ally':
		buff_stats(self, 2, 0)
```

### Buff / Debuff 与新增词缀

内置 Buff：

```text
apply_buff(self, "frozen")
apply_buff(self, "invincible")
apply_buff(self, "spell_immune")
remove_buff(self, "frozen")
```

事件：

```text
when buff_applied:
	gain_attack(1)
when buff_removed:
	add_marker("buff_removed", 1)
```

- Buff 不是词缀，只存在于战场实体上；可在代码中解除
- `frozen`：不能攻击；所在列战斗结算完成后解除
- `invincible`：词缀**只在入场时给一层无敌 Buff**，Buff 免疫伤害（**不**阻止消灭），所在列战斗结算完成后解除
- `spell_immune`：只拦**敌方锦囊**——敌方锦囊不能选它、伤害/消灭无效；我方锦囊、实体能力、环境等效果正常生效（不判断效果有益或有害）
- 相关实体词缀：双重打击、狂热、锦囊免疫、克制英雄、穿透、致命、无敌、捕猎、两栖、溅射、寒霜、反伤、免疫负面
- `debuff_immune` 会阻止冰冻等 Debuff 被施加
- 战斗阶段中，每一列的战斗**完全结束**（两轮攻击 + 死亡结算之后）时，只清除该列**存活**实体的 `frozen` 与 `invincible`（清掉全部叠加层数）；其余 Buff（`spell_immune` / `hatred` / `life_force` / `buried` / `bounce` / `frozen_tombstone`）与临时词缀 Buff 不会在战斗结束时清除
- 已被消灭或已移出该列的实体不参与这次清除；战斗阶段之外的强制攻击不触发该清除
- 词缀定义在 `scripts/data/card_keywords.gd`，Buff 定义在 `scripts/data/card_buffs.gd`，战斗实现在 `scripts/battle/battle_engine.gd`

### 进化、底座与额外攻击

```text
evolve("name == 'gnoll'")
when evolved:
	apply_buff(self, "invincible")

base()
when mounted:
	apply_buff(mounted, "frozen")
```

- `evolve(filter)` 只允许实体牌；可放置在已有友方实体位置，原实体被移除但不触发死亡
- 只有被移除的原实体满足筛选条件时，才触发新实体的 `evolved` 事件
- 进化放置对“已有实体位置”的判定优先于环境词缀限制
- `base()` 只允许实体牌；非底座实体打出到该位置时移除底座，并继承底座当前攻击/生命/防御
- 底座 `when mounted` 的 `mounted` / `event` 指向刚放上去的实体
- 底座和进化的“放到已有实体上”只对**打出**生效；移动仍走普通组队/合法位置/挤压规则
- `force_attack` 与狂热触发的额外攻击会触发 `extra_attack`；双重打击第二次攻击和普通战斗攻击不触发

### 随机塞牌与筛选条件

```text
add_random_cards_to_deck(hero, 2, "kind == 'spell' and rarity == 'rare'")
add_random_cards_to_deck(enemy_hero, 1, "class == 'guardian'")
add_random_cards_to_hand(hero, 2, "name == 'fireball' or name == 'frostbolt'")
add_random_cards_to_hand(enemy_hero, 1, "keyword == 'team_up' and not tribe == 'pet'")
```

- `target` 使用 `hero`（施放者阵营）或 `enemy_hero`（对方阵营）
- 只从 `CardDatabase` 读取卡牌，不会从当前牌局已有牌中取
- 每张牌独立随机抽取，因此可能重复
- 牌库插入位置随机；手牌插入位置随机，并遵守手牌上限
- 筛选语法：`and` / `or` / `not`，支持括号
- 可用字段：
  - `name`：卡牌英文名（推荐）
  - `kind`：卡牌种类（`entity`/`spell`/`environment`，也兼容直接写英文名）
  - `rarity`：稀有度
  - `class`：职业
  - `keyword`：是否拥有某词缀
  - `tribe`：是否拥有某流派
  - `deck_includable`：是否可被组入牌组
- 如果没有显式写出 `deck_includable` 条件，自动只匹配 `deck_includable == true` 的卡牌
- 例：`"deck_includable == false"` 可以显式允许不可组入卡牌
- 比较值建议用引号；布尔值写 `true` / `false`

### 生命值减益

- 生命值减益同时降低当前生命和生命上限
- 无视护盾、隐形、无敌等伤害减免
- 不触发 `damaged`
- 当前生命小于 1 时，即使有无敌 Buff 也会死亡
- 对手牌中的实体牌进行数值变化时：
  - 攻击力不会低于 0
  - 防御力不会低于 0
  - 生命值不会低于 1

### 墓碑

```text
# 实体词缀：tombstone
# 入场时自动获得 buried Buff，不触发 when enter，只触发 when tombstone_enter
when tombstone_enter:
	...

# Z 方锦囊阶段结束时：
# 按列从左到右移除 buried，依次触发 tombstone_reveal 和 enter
```

- 埋入墓碑期间，敌方看不到实体信息；低层快照用 `public_entity_snapshot(viewer_side)` 过滤
- 埋入墓碑的实体不会受到任何伤害，也不会成为普通实体锦囊目标；但仍可被 `destroy` 消灭
- 墓碑专用选择器/查询：`all_buried`、`buried_entities`、`buried_in_column`、`buried_in_columns(side, -2, 2)`
- 弹回墓碑：`apply_buff(target, 'bounce')`，效果与普通实体相同；离开时只广播费用变化，不广播实体信息
- 冻结墓碑：`apply_buff(target, 'frozen_tombstone')`；揭示时先施加 `frozen`，再移除 `frozen_tombstone`，最后结算入场
- 移动墓碑：使用 `move_entity`；不广播实体信息
- 打乱墓碑位置预留 `shuffle_buried_positions` 引擎接口，伪代码示例：
  ```text
  shuffle_buried_positions(hero)
  ```
- 墓碑费用通过 `visible_energy_for(side, viewer_side)` 对敌方隐藏
- 对场上实体施加 `tombstone` 词缀会立刻埋入并触发 `tombstone_enter`
- 揭示后恢复正常入场结算
- `buried_in_column` 选择器可选当前列全部墓碑实体；`all_buried` 可选全部墓碑实体

### 三连打

```text
# 实体词缀：triple_strike
# 攻击时依次攻击左列、自身列、右列
# 第一列没有左列、最后一列没有右列时跳过该次攻击
```

### 芦荟队长

```text
when hand_played:
	gain_attack(1)
when ally_attack_gained:
	buff_stats(self, 0, 1)
```

- 这两条异能只在手牌/牌库区域生效
- 入场后保留手牌期间获得的攻击/生命修正
- 入场后不再触发这两条区域异能

### 墓碑目标规则

当前埋入墓碑的实体：

- 不会受到任何伤害（`damage_entity` 直接返回）
- 不会被普通实体锦囊选为目标（`can_target` 返回 false）
- 可以被 `destroy` 消灭
- 可以被 `remove_entity` 移除
- 可以被墓碑专用消灭能力选为目标
- 可以被墓碑专用弹回/冻结/移动/打乱能力处理；这些能力需要走墓碑专用入口，不走普通目标选择

### 弹回、隐形与牌库顶

```text
apply_buff(target, 'bounce')
apply_buff(target, 'bounce', 1)
```

`bounce` 是 Debuff：

1. 先判定**自身**死亡（只结算被弹回的实体，不牵连其他实体）
2. 存活则移除实体（不触发死亡/亡语）
3. 将原卡牌以数据库原始数据加入所属玩家手牌
4. 手牌已满时插入牌库第 0 位
5. 不触发抽牌或“牌库被插入”事件

隐形词缀：

```text
give_keyword(self, 'invisible', 2)
```

- 数值 > 0 时免疫伤害类型不包含 `bullseye`（必中）的伤害
- 不会免疫消灭 `destroy` 或移除 `remove_entity`
- 每次回合结束，全场隐形数值 -1，最低为 0
- 锦囊造成的伤害默认没有任何特殊伤害类型；`from_spell` 仅用于锦囊免疫与来源判断

牌库顶操作：

```text
put_card_on_deck_top(hero, "cost <= 3")
put_hand_card_on_deck_top(hero, "kind == spell")
```

- `put_card_on_deck_top` 从数据库随机抽一张符合筛选的牌放到牌库顶
- `put_hand_card_on_deck_top` 将手牌中第一张符合筛选的牌移到牌库顶
- 两者都不触发抽牌/插入事件
- 筛选器支持 `cost < / <= / > / >= / == / !=`，并可与 `and/or/not` 组合

`destroy` 的机制：

- 不造成伤害，直接尝试将实体生命值设为 0
- 无敌 Buff **不阻止**消灭：消灭时先移除 1 层无敌 Buff，再把生命归零
- 会被墓碑等离场规则处理
- 隐形不阻止 `destroy`
- `remove_entity` 与 `destroy` 不同：移除不触发死亡与亡语

### 示例卡牌与结算顺序

终极地雷：

```text
double_death_effects()
when die:
	deal_damage(random_enemy_in_column_or_hero, 5)
```

结算顺序：

1. 友方实体生命值降至 1 以下
2. 终极地雷（若仍存活）将使该友方实体的亡语触发次数变为 2
3. 连续触发两次 `die` 事件（以及两次区域 `ally_die`）
4. 移除该实体

终极地雷自身死亡时，若没有另一张存活的终极地雷，则它自己的亡语只触发一次。

扁豆教授：

```text
when enter(side != 'enemy'):
	buff_stats(self, 1, 0)
when enter:
	summon('novice')
	summon('novice')
```

- 光环类 `when enter` 与入场效果按事件块顺序依次结算
- 先执行光环触发，再执行召唤；随后每次真实召唤都会再次触发光环

招聘专员：

```text
when enter:
	add_random_cards_to_hand(hero, 2, 'kind == spell', -1)
```

目标示例：

```text
choose(1, 'enemy_hero_or_entities'); deal_damage(chosen, 2)
deal_damage_each(random_targets(3, 'enemy_hero_or_entities'), 1, 2, 4)
deal_damage(enemy_hero, 3)
choose(1, 'enemy_entities'); destroy(chosen)
destroy(random_targets(2, 'frozen_enemies'))
heal(random_targets(2, 'injured_allies'), 6)
heal(all_allies_and_hero, 5)
```

### 目标选择与随机目标

```text
choose(1, "enemy_hero_or_entities")
deal_damage(chosen, 2)

deal_damage_each(random_targets(3, "enemy_hero_or_entities"), 1, 2, 4)
destroy(random_targets(2, "frozen_enemies"))
heal(random_targets(2, "injured_allies"), 6)
heal(all_allies_and_hero, 5)
```

可用选择器：

- `enemy_hero_or_entities`
- `enemy_entities`
- `frozen_enemies`
- `injured_allies`
- `all_allies_and_hero`
- `all_entities`
- `all_heroes_and_entities`

`random_targets(count, selector)` 会从候选中随机取最多 count 个目标；`deal_damage_each(targets, 1, 2, 4)` 按顺序分配不同伤害。

### 按数值挑选目标（`highest` / `lowest`）

在任意目标集合里挑出**当前数值**最高或最低的实体，把结果当普通目标传给任意原语：

```text
deal_damage(highest(all_enemies, 'attack'), 3)
destroy(lowest(all_allies, 'health'))
apply_buff(lowest(enemy_entities, 'defense'), 'frozen')
give_keyword(highest(all_allies, 'cost'), 'team_up')
for_each(highest(all_enemies, 'health')) as e: gain_energy(1)
```

- 形式：`highest(<目标集合>, <数值名>[, <条件>])` / `lowest(<目标集合>, <数值名>[, <条件>])`
- 第三个参数可选：**逐目标条件**。只有满足条件的候选才参与比较，条件里可以直接读该目标自己的事实变量（`attack` / `health` / `shield` / `cost` / `class` / `tribes` / `keywords` …）与查询函数：

```text
deal_damage(highest(all_enemies, 'attack', health >= 5), 3)
apply_buff(lowest(all_allies, 'cost', has_keyword('frost')), 'frozen')
```

- `<目标集合>`：任何能得到句柄数组的表达式——选择器（`all_enemies` / `all_allies` / `enemy_entities` …）、`entities_in_column(...)`、`random_targets(...)`、`damage_targets`、循环变量等。
- `<数值名>`（大小写不敏感，中英文都可用）：

| 数值名 | 含义 |
|---|---|
| `attack` / `攻击` | 当前攻击力 |
| `health` / `生命` | 当前生命值 |
| `max_health` / `生命上限` | 生命上限 |
| `shield` / `defense` / `防御` | 当前防御值（两者等价） |
| `cost` / `费用` | 当前费用 |

- 结果是**数组**：并列极值的实体会全部返回，所以多目标原语会逐个生效；只接受单个目标的原语（`apply_buff` / `remove_buff` / `force_attack` / `move_entity` / `remove_entity` 等）在并列时会记录运行错误。
- 空集合返回空数组：不执行、不报错。
- 只按数值挑选，**不检查**锦囊免疫 / 隐形等目标限制；具体原语仍按自身规则过滤（例如敌方锦囊伤害会跳过锦囊免疫目标）。
- 读到的都是**当前值**（已结算 Buff、光环、环境修正），不是卡牌数据库里的原始数值。

### 用卡牌筛选语法筛选在场实体（`entities_matching`）

`entities_matching` 把**卡牌数据库的筛选语法**直接用到在场实体上：

```text
# 全场：职业为士兵且当前费用 <= 3 的在场实体
destroy(entities_matching("class == 'soldier' and cost <= 3"))

# 限定范围：只在我方实体里挑豆族
heal(entities_matching(all_allies, "tribe == 'pea'"), 2)

# 敌方里所有带寒霜的
deal_damage(entities_matching(enemy_entities, "keyword == 'frost'"), 1)
```

- 形式：`entities_matching(<筛选>)` / `entities_matching(<范围>, <筛选>)`
- 单参数：在**全部在场实体**（双方、存活）里筛；双参数：在给定范围里筛（选择器 / `entities_in_column(...)` / `random_targets(...)` / 循环变量 / 其它数组结果）。
- 筛选字段与卡牌数据库一致：

| 字段 | 说明 |
|---|---|
| `name` | 英文名（别名 `english` / `card_name`） |
| `kind` | 类型；也可直接写英文名（`kind == 'snowpea'`） |
| `rarity` | 稀有度 |
| `class` | 职业 |
| `category` / `class_category` | 职业类别 |
| `keyword` | 词缀，**包含**语义 |
| `tribe` | 流派，**包含**语义 |
| `deck_includable` | 是否可编入牌组；未显式写出时**默认要求 true** |
| `cost` / `费用` | 当前费用，支持 `< <= > >= == !=` |

- 支持 `and` / `or` / `not` 与括号（也认 `&&` / `||` / `!`）。
- 判定用**当前状态**：Buff / 环境临时赋予的词缀同样参与匹配，`cost` 是当前费用。
- 筛选语法写错会在运行时记录错误并返回空数组（后续原语不执行）；空结果本身不报错。

### 生命值与防御

- 实体 `shield` 是固定减伤，不会像英雄护盾一样被消耗；必中伤害无视该减伤
- `buff_stats(target, attack, health)` 的生命值变化会同时改变当前生命与生命上限
- 生命值增益会触发 `healed`
- `heal` 不能超过生命上限
- `gain_max_health(target, delta)` 修改实体/英雄生命上限
- 攻击力小于 1 的实体不能发起战斗攻击、额外攻击或狂热追击

### 光环与费用

实体顶层可声明：

```text
aura_buff("ally", "spell_immune", -1, 1, true)
aura_buff("ally", "hatred", -4, 4, false)
aura_hand_cost("self", "kind == 'spell'", -1)
aura_spell_cost("enemy", 6)
```

- 光环 Buff 按来源实体追踪；来源离场后只移除该来源提供的 Buff
- `aura_hand_cost` 按筛选器修改手牌费用
- `aura_spell_cost` 修改锦囊费用
- `draw_cards(count, cost_delta)` 和随机塞牌可追加费用修饰符

固定位置形式也遵循上述阵营、当前位置、组队和挤压规则。

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

注意：打出组队实体时把原实体挤到同列另一格，属于“放置规则”，**不会触发** `position_changed`；只有卡牌效果调用 `move_entity` 才会让**被移动的实体**触发。因移动造成的挤压同样不会触发被挤开实体的 `position_changed`。

特殊标志物名字是任意英文字符串，不注册种类，数量允许负数。

### 循环 / 极值 / 实体筛选组合示例

```text
# 1) 对每个敌方实体按自己的当前数值分流（for_each + if/elif/else）
when enter:
    for_each(all_enemies) as e:
        if health <= 2:
            destroy(e)
        elif has_keyword('frost'):
            deal_damage(e, 1)
        else:
            gain_energy(1)

# 2) 只处理筛选后的敌方实体（卡牌筛选语法 + 循环）
when enter:
    for_each(entities_matching(enemy_entities, "class == 'soldier'")) as e:
        buff_stats(e, 0, 1)

# 3) 挑当前攻击力最高的敌方，吃 3 点伤害
when enter:
    deal_damage(highest(all_enemies, 'attack'), 3)

# 4) 先收窄再挑：当前生命 >= 5 的敌方里防御最高的，冻住
when enter:
    apply_buff(highest(all_enemies, 'defense', health >= 5), 'frozen')

# 5) 我方费用最高的、还没有组队的实体获得组队
when turn_end:
    give_keyword(highest(all_allies, 'cost', not has_keyword('team_up')), 'team_up')

# 6) 遍历本次造成有效伤害的所有目标（事件回调数组作为循环源）
when damage_dealt:
    for_each(damage_targets) as hurt:
        if attack(hurt) > 4:
            gain_energy(1)

# 7) 筛选 + 极值：只在我方豆族里找当前生命最低的，治疗 3 点
when turn_end:
    heal(lowest(entities_matching(all_allies, "tribe == 'pea'"), 'health'), 3)

# 8) 多职业类别 / 词缀组合筛选
when enter:
    destroy(entities_matching(enemy_entities, "category == 'growth' and keyword == 'team_up' and cost <= 4"))
```

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
func summon(card_name, column = null, max_column = null) / draw_cards(n) / deal_damage(handle, n) / heal(...) / ...
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

### 区域作用域

实体牌默认能力只在**场上**生效。若要在手牌或牌库生效，必须显式声明：

```text
in_hand()
when health_changed(side == 'ally'):
	reduce_cost(1)

in_deck()
when ally_die(zone == 'deck'):
	gain_attack(1)
```

规则：

- 没有 `in_hand()` / `in_deck()` 的实体牌能力不会从手牌/牌库触发
- `in_hand()` 允许手牌中的能力响应事件
- `in_deck()` 允许牌库中的能力响应事件
- 可以同时声明两者
- 手牌/牌库能力的伤害来源会记录为 `手牌：卡名` 或 `牌库：卡名`
- `when hand_played`、`when ally_attack_gained` 等事件仍需要对应的 `in_hand()` 作用域

### 职业类别与筛选

全局配置 `config.csv` 使用 `type=class_category` 和 `members` 列定义职业类别：

```text
type,name,label_zh,members
class_category,growth,成长系,"grow,bloom"
```

- 每个职业必须属于且只能属于一个职业类别
- 未在 `members` 中出现的职业会自动归入 `uncategorized`（未分类）
- 筛选条件支持：
  ```text
  category == 'growth'
  class == 'grow'
  ```

### 变形

```text
transform(chosen, "cost == 2 and category == 'growth'")
transform(all_enemies, "kind == 'entity' and cost <= 3")
transform(random_enemy, "keyword == 'frost'")
```

- 第一个参数是实体选择器
- 第二个参数是卡牌筛选条件
- 将目标实体原地移除，并按筛选条件随机召唤一个实体
- 会触发 `transformed` 事件，事件目标为新实体

### 手牌变形

```text
transform_hand('ally', "cost == 2", "kind == 'spell' and cost == 3")
transform_hand('enemy', "kind == 'entity'", "category == 'growth'")
```

- 第一个参数：`ally` / `enemy` / `all`
- 第二个参数：原手牌筛选条件
- 第三个参数：新手牌筛选条件
- 会触发 `hand_transformed` 事件

### 混乱进化与混乱手牌

- `chaos_evolution`：实体回合结束时，变形为费用 +1、职业类别相同的随机实体，并保留该词缀
- `chaos_hand`：手牌回合开始时，变形为费用 +1、职业类别和类型相同的随机手牌，并保留该词缀

相关事件：

```text
when transformed(side == 'ally'):
	...
when hand_transformed:
	...
```

### 生命力量

```text
apply_buff(self, "life_force")
```

- 具备 `life_force` 的实体攻击时，主攻击、穿透、溅射使用**当前生命值**作为伤害数值，而不是攻击力
- 攻击前的攻击力检查、双重打击的第二次攻击检查也使用生命值
- 先攻仍然使用先攻词缀自身的数值
- 其他词缀照常生效：致命、寒霜、必中、穿透、溅射等

### 环境临时数值

```text
environment_grant_stats(2, 1, 1, 'ally')
environment_grant_stats(-1, 0, 0, 'enemy')
```

参数：

1. 攻击力变化
2. 生命值变化
3. 防御值变化
4. `ally` / `enemy` / `all`

- 只对当前环境所在列的实体生效
- 实体移动离开该列时移除
- 实体进入该列时按环境条件重新应用
- 环境被覆盖时移除旧环境赋予的数值

### 底座与进化顺序

```text
base()
when mounted:
	apply_buff(mounted, "frozen")

evolve("name == 'gnoll'")
when evolved:
	...
```

进化实体放置在底座上时：

1. 新实体先入场
2. 先结算底座的 `mounted` 能力
3. 再判断进化筛选条件
4. 满足时触发 `evolved`

### 创造牌时内联施加词缀与数值

`add_random_cards_to_hand` / `add_random_cards_to_deck` 支持在创建时对**每一张新创建的牌**施加同样的效果：

```text
add_random_cards_to_hand(hero, 2, "kind == 'entity'", 0, "frost", 1, 2, 1, 0)
```

参数顺序：

1. 目标阵营或英雄
2. 数量
3. 筛选条件
4. 费用修正
5. 词缀（空字符串表示不赋予）
6. 攻击力修正
7. 生命值修正
8. 防御值修正
9. 词缀数值（无数值词缀写 0）

示例：

```text
# 创建 3 张 1 费实体，全部获得先攻 2、攻击 +1、生命 +2、防御 +1
add_random_cards_to_hand(hero, 3, "kind == 'entity' and cost == 1", 0, "first_strike", 1, 2, 1, 2)

# 创建 2 张锦囊并减 1 费，不赋予词缀
add_random_cards_to_hand(hero, 2, "kind == 'spell'", -1)

# 将随机一张牌放到牌库顶，并赋予寒霜、攻击 +1、生命 +2、防御 +1
put_card_on_deck_top(hero, "kind == 'entity'", "frost", 1, 2, 1, 0)
```

规则：

- 多张创建时，对每一张分别执行相同的词缀和数值修正
- 数值修正写入卡牌实例的 `attack_bonus` / `health_bonus` / `shield_bonus`
- 词缀写入卡牌实例，打出后转为实体词缀
- 费用修正只影响手牌有效费用
- 这些效果不会修改卡牌数据库中的原始卡牌

### 随机插入牌库

如果要从卡牌数据库创造牌并随机插入牌库，使用：

```text
add_random_cards_to_deck(hero, 3, "kind == 'entity'")
```

效果：

- 从卡牌数据库中选择 3 张符合条件的牌
- 每张创建为独立卡牌实例
- 随机插入牌库的随机位置
- 允许重复
- 不赋予词缀、不加数值、不改费用

带费用修正：

```text
add_random_cards_to_deck(hero, 3, "kind == 'spell'", -1)
```

带词缀和数值：

```text
add_random_cards_to_deck(
	hero,
	3,
	"kind == 'entity'",
	0,
	"frost",
	1,
	2,
	1,
	0
)
```

以上表示：创造 3 张实体，全部随机插入牌库，全部获得寒霜、攻击 +1、生命 +2、防御 +1。

### 放到牌库顶

```text
put_card_on_deck_top(hero, "kind == 'entity'")
```

- 随机创造 1 张符合条件的牌
- 放到牌库顶
- 不是随机插入
- 不赋予词缀、不加数值、不改费用

### 创造牌参数省略规则

`add_random_cards_to_hand` / `add_random_cards_to_deck`：

```text
(target, count, filter)
(target, count, filter, cost_delta)
(target, count, filter, cost_delta, keyword)
(target, count, filter, cost_delta, keyword, attack, health, shield)
(target, count, filter, cost_delta, keyword, attack, health, shield, keyword_value)
```

`put_card_on_deck_top`：

```text
(target, filter)
(target, filter, keyword)
(target, filter, keyword, attack, health, shield)
(target, filter, keyword, attack, health, shield, keyword_value)
```

省略可选参数时默认：

```text
费用修正 = 0
词缀 = 空
攻击修正 = 0
生命修正 = 0
防御修正 = 0
词缀数值 = 0
```

### 无词缀写法

```text
# 只创造，不加效果
add_random_cards_to_hand(hero, 2, "kind == 'spell'")
add_random_cards_to_deck(hero, 2, "kind == 'entity'")
put_card_on_deck_top(hero, "kind == 'entity'")

# 只改费用，不加词缀
add_random_cards_to_hand(hero, 2, "kind == 'spell'", -1)

# 不加词缀，但加数值
add_random_cards_to_hand(hero, 2, "kind == 'entity'", 0, "", 1, 2, 0)
```

### 创造牌与抽牌的区别

- `draw_cards(count)`：从当前牌库顶抽已有牌，不创建新牌
- `add_random_cards_to_hand`：从卡牌数据库创造新牌，随机插入手牌
- `add_random_cards_to_deck`：从卡牌数据库创造新牌，随机插入牌库
- `put_card_on_deck_top`：从卡牌数据库创造新牌，放到牌库顶
- `summon`：从卡牌数据库召唤实体，不走手牌/牌库
- `transform` / `transform_hand`：把已有实体或手牌替换为随机卡牌，不是新增复制
- 创造到手的牌受手牌上限约束：手牌已满时该张创造失败，不触发任何事件
- 创造到手每成功一张触发 `drawn`；创造到牌库 / 牌库顶不触发 `drawn`，只发 `changed` 界面信号

### 创造牌可施加的效果

当前创建原语可内联施加：

- 费用修正
- 一个词缀及其数值
- 攻击力修正
- 生命值修正
- 防御值修正

这些效果对该次创造出的每一张牌都生效。

当前创建原语不能内联施加：

- 多个不同词缀
- 任意 Buff
- 卡牌专属的复杂效果
- 直接指定“第 N 张新牌”
- 创建后再对某一张新牌单独赋不同效果

需要这些效果时，应拆分创建与后续处理，或扩展新的原语。

### 牌库搜寻抽牌

```text
draw_matching_cards(hero, 2, "kind == 'spell' and cost <= 3")
draw_matching_cards(enemy_hero, 1, "class == 'guardian'", -1)
```

参数：

1. 目标英雄/阵营
2. 数量
3. 筛选条件
4. 可选费用修正

行为：

- 从当前牌库中随机寻找符合筛选条件的牌
- 不创建新牌，只移动已有牌
- 抽到的牌进入手牌
- 每张都触发 `drawn` 事件
- 牌库为空时视为抽牌失败，增加 1 层疲劳，不触发 `drawn`
- 手牌已满时停止抽牌，且不触发 `drawn`
- 牌库有牌但没有符合条件的牌时不会增加疲劳

### 疲劳标志物

牌库为空仍要抽牌时：

```text
add_marker('fatigue', 1)
```

回合开始时：

- 拥有 `fatigue` 标志物的英雄受到等同标志物数量的伤害
- 伤害来源显示为“疲劳”
- 伤害类型为普通非攻击、非锦囊伤害
- 会正常经过英雄护盾、充能护盾和免伤机制

标志物目前存储在玩家英雄上，不支持实体标志物。

### 标志物伪代码能力

```text
add_marker('fatigue', 1)
remove_marker('fatigue', 1)
marker_count('fatigue')
```

- 标志物名字是任意字符串，不需要预先注册
- 数量允许为负
- `add_marker` / `remove_marker` 默认作用于施放者所在阵营的英雄
- `marker_count` 查询施放者阵营英雄的标志物
- 可用于条件、循环和伤害数值

示例：

```text
when turn_end:
	if marker_count('fatigue') >= 3:
		add_marker('wounded', 1)
```

### 抽牌事件

```text
when drawn(side == 'ally'):
	...
```

- `draw_cards` / `draw_matching_cards` / 创造到手牌（每张）都会触发
- 事件目标是抽牌方英雄句柄
- 手牌已满、牌库为空导致的失败都不触发 `drawn`
- 用 `side` 事实区分 `side == 'ally'`（我方）/ `'enemy'`（敌方）/ `'neutral'`（中立视角）
- 创造到牌库 / 牌库顶不触发 `drawn`
- 手牌/牌库中带 `in_hand()` / `in_deck()` 作用域的能力也可以响应

### 同列前后位置伤害

```text
damage_column_relative(2, 'front')
damage_column_relative(3, 'back', -1)
damage_column_relative(1, 'front', 1)
```

参数：

1. 伤害数值
2. `front` / `back`
3. 可选相对列偏移，默认 0

- `front`：目标列普通位（靠前）
- `back`：目标列组队位（靠后）
- 偏移 `0`：当前列；`-1`：左侧列；`1`：右侧列
- 如果目标列只有一个敌方实体，无论 `front` 还是 `back` 都会命中它
- 目标列没有敌方实体时不造成伤害
- 只伤害敌方实体，不命中英雄
- 伤害携带施放者词缀
- 不进入攻击流程，不触发先攻、双击、狂热、穿透、三连等攻击形式

也接受 `ahead` / `behind` 和 `前` / `后`。

实体能力示例：

```text
when enter:
	damage_column_relative(2, 'front')

when turn_end:
	damage_column_relative(3, 'back', -1)
```

选列锦囊示例：

```text
choose_column()
damage_column_relative(4, 'back')
```

环境牌示例：

```text
damage_column_relative(2, 'front')
```

- 选列锦囊使用玩家选择的列作为参考列
- 环境牌使用自身所在列作为参考列

### 攻击完成事件

```text
when after_attack:
	...
```

- 实体完成一次攻击动作后触发
- 事件目标是执行攻击的实体
- 每次实际执行的攻击动作都会触发
- 攻击被冰冻、攻击力不足、已死亡或对局结束时不会触发
- **在死亡判定之前结算**：被这次攻击击杀的实体此时仍在场（生命 ≤ 0 但尚未移除），
  所以 `for_each(all_enemies)` / `entities_matching(...)` / `highest(...)` 仍能看到它
- 与 `attacked` 的关系：`attacked` 先触发；`after_attack` 之后才是狂热追加攻击
- 不进入攻击流程的特殊能力伤害不会触发

与其他攻击形式的关系：

- 双重打击：两次攻击动作，各自触发一次
- 三连打：每一列的攻击动作分别触发一次
- 狂热：追加攻击各自触发一次
- 穿透：同一次穿透攻击只触发一次
- 强制攻击 / 额外攻击：每次攻击动作触发
- 先攻：先攻伤害包含在该攻击动作中；如果先攻直接结束对局，则不会再触发完成事件

### 造成有效伤害事件

`damage_dealt` 在实体对另一个实体或英雄造成有效伤害后触发：

```text
when damage_dealt:
	...
```

- 事件实体是伤害来源
- 只有有效伤害 `> 0` 才触发
- 攻击、特殊能力伤害都会触发
- 反伤、充能免伤、被完全格挡的伤害不会触发
- 不需要选择目标；伤害目标通过 `damage_targets` 数组访问

```text
when damage_dealt:
	heal(damage_targets, 1)
```

`damage_targets` 数组元素可能是：

- `BattleEntity`
- 英雄句柄，例如 `hero:p`、`hero:z`

### 多目标伤害的数组回调

如果一次能力对多个实体/英雄造成有效伤害：

```text
when enter:
	deal_damage(all_enemies, 2)

when damage_dealt:
	deal_damage_each(damage_targets, 1)
```

一次结算中所有有效目标会汇总到 `damage_targets`，然后触发一次 `damage_dealt`。

支持把 `damage_targets` 直接传给可接受目标数组的原语，例如：

```text
heal(damage_targets, 1)
buff_stats(damage_targets, 1, 1)
deal_damage_each(damage_targets, 1)
```

注意：

- 可以用 `for_each(damage_targets) as hurt:` 逐个处理本次受伤的目标（见第十节）
- 不写循环时，对数组逐个执行原语依赖原语自身的目标数组展开
- `damage_dealt` 内部再次造成伤害会继续产生新的 `damage_dealt`，受到连锁上限保护

### 多目标伤害后按类型分流（英雄 / 实体）

典型需求：一张实体牌入场时对**敌方所有实体和英雄**造成伤害，并且只对**英雄**造成有效伤害时才触发后续能力。

```text
when enter:
    deal_damage(enemy_hero_or_entities, 2)

when damage_dealt:
    for_each(damage_targets) as t:
        if class == 'hero':
            gain_energy(1)
        else:
            give_keyword(t, 'frost')
```

要点：

- `damage_targets` 是**本次结算里造成有效伤害的目标数组**，实体句柄与英雄句柄混在同一个数组里。
- 判定"命中英雄"用 `class == 'hero'`。英雄句柄的事实：`attack == 0`、`health` 是英雄当前生命、
  `side` 是相对来源的 `ally` / `enemy` / `neutral`；英雄没有 `tribes` / `keywords`。
- **没造成有效伤害的目标根本不会进数组**（护盾/免疫/充能免伤挡下的都不算），所以循环体里不需要再判一次"有没有伤害"。
- 一次结算汇总成**一个** `damage_dealt` 事件（不是每个目标触发一次）：英雄 + 3 个实体只触发一次能力、循环 4 轮。
- `damage_dealt` **只在伤害来源是实体时触发**：锦囊、环境、以及没有来源实体的效果伤害都不会触发它，
  这类要写在该锦囊/环境自己的能力里。
- 循环内再次造成伤害会继续产生新的 `damage_dealt`，受连锁上限保护。

只针对敌方英雄的写法：

```text
when damage_dealt:
    for_each(damage_targets) as t:
        if class == 'hero' and side == 'enemy':
            draw_cards(1)
```

想对实体目标套用卡牌筛选语法，可以配合 `entities_matching` 再用英雄事实分流；
英雄句柄不是卡牌，`entities_matching` 不会返回英雄，这正好可以用来区分两类目标。

### 与 `damaged` 的区别

`damaged`（受伤）与 `damage_dealt`（造成有效伤害）是**两个独立触发器**，不能互相替代：

| 对比项 | `damaged` | `damage_dealt` |
|---|---|---|
| 谁触发 | **被伤害的实体**自己 | **伤害来源实体**自己 |
| 事件目标 `event` | 受伤者 | 来源实体 |
| 触发次数 | 每个受伤目标各一次 | 每次结算按来源汇总一次 |
| 能拿到什么 | 只有受伤者自己；另外可通过 `damage_source` 读伤害来源 | `damage_targets` 数组：本次所有造成有效伤害的实体 + 英雄 |
| 英雄受伤 | **不触发**（英雄没有这个事件） | 能包含英雄目标 |
| 来源要求 | 无 | **必须有一个实体来源**：锦囊 / 环境 / 无来源效果伤害不触发 |
| 时机 | 在 `damage_entity` 内立即触发 | 在结算点批量触发（攻击里在 `attack` 事件之后） |

由此带来的写法差异：

```text
# 这是"我被打了"——默认只响应自己；要观察友方受伤需要过滤
when damaged(side == 'ally'):
    ...

# 这是"我打出了有效伤害"——能拿到被打的目标数组
when damage_dealt:
    for_each(damage_targets) as t:
        if class == 'hero':
            ...
```

### 伤害来源事实（`damage_source` / `damage_amount`）

`damaged` 与 `hero_damaged` 事件里都能读到伤害来源，不需要再去猜：

| 名称 | 类型 | 说明 |
|---|---|---|
| `damage_source` | 选择器 | 伤害来源句柄；没有来源（锦囊 / 环境 / 无来源效果伤害）时返回**空数组** |
| `is_entity(目标)` | 查询 | 该目标是否是实体（英雄句柄、卡牌实例、`null` 都返回 false），**空值保护就靠它** |
| `damage_amount` | 事实变量 | 本次造成的**有效伤害**数值 |
| `damage_source_is_entity` | 事实变量 | 等价于 `is_entity(damage_source)` 的快捷布尔 |

```text
# 受伤时给来源上 Buff（先判类型：来源为空或为英雄时自动跳过）
when damaged:
    if is_entity(damage_source):
        apply_buff(damage_source, 'hatred')

# 带刺玫瑰式写法：友方受伤 → 消灭伤害来源实体
when damaged(side == 'ally'):
    if is_entity(damage_source):
        destroy(damage_source)

# 按伤害量分流
when damaged:
    if damage_amount >= 3:
        draw_cards(1)
```

- `damage_source` 直接当目标传给原语是安全的：空数组会被原语自动跳过（`destroy(damage_source)` 在没有来源时什么都不做）。
- 但**查询函数**（`attack(x)` / `cost(x)` …）要求单个目标，无来源时会记录运行错误——所以先 `if is_entity(damage_source):` 再读。
- 来源是**英雄**时 `is_entity` 为 false；要区分"英雄来源"可以再判 `class == 'hero'`。

### 英雄受伤事件（`hero_damaged`）

```text
when hero_damaged(side == 'ally'):
    ...
```

- 事件目标是**受伤的英雄句柄**（`hero:p` / `hero:z`）。英雄没有自己的技能，所以监听方必须写过滤条件
  （`side == 'ally'` / `'enemy'`）；不写过滤不会触发。
- 只在**有效伤害**时触发：护盾完全吸收、充能免伤、`hero_ward` 挡下都不触发。
- 同样携带 `damage_source` / `damage_amount`（见上表），可以据此反制伤害来源。
- **环境牌不监听该事件**（英雄没有所在列，否则会按 5 列重复触发）。
- 与 `damaged` 互补：`damaged` 只对实体触发，`hero_damaged` 只对英雄触发。

## 十、循环与逐目标分支（`for_each`）

`for_each` 是**语句**（不是原语）：对一组目标逐个执行整个语句块，块内可以读当前目标自己的数值、用 `if`/`elif`/`else` 分流、调用任意原语。

### 语法

```text
for_each(<目标表达式>) as <名称>:
    <任意语句块>
```

- `<目标表达式>`：任何能得到句柄或句柄数组的表达式——
  选择器（`all_enemies`、`chosen`、`damage_targets`）、
  查询函数（`entities_in_column(-1, 1, 'enemy')`、`random_targets(2, 'all_enemies')`）、
  或保存了数组的变量（`group = all_enemies` 之后 `for_each(group) as e:`）。
- `as <名称>` 可省略，默认名称是 `it`。
- 块内可写：原语、赋值、`if`/`elif`/`else`、`repeat`、嵌套 `for_each`；**不能**在块内声明 `when`。
- 每个目标**独立结算**：当前这一轮的原语只作用在当前目标上，按数组顺序依次执行。
- 目标为空数组时不执行块、不报错；`null` 句柄被跳过。

### 循环内可直接读取的事实变量

块内不必写 `attack(e)`：直接写 `attack` 就是**当前目标**的数值。

| 变量 | 含义 |
|---|---|
| `attack` / `health` / `max_health` | 当前攻击力 / 当前生命 / 生命上限 |
| `shield` / `defense` | 防御值（两者等价，`defense` 是别名） |
| `cost` | 当前费用（在场实体为数据库原始费用；手牌/牌库为结算后的有效费用） |
| `side` | `self` / `ally` / `enemy` / `neutral`（相对技能拥有者） |
| `class` | 职业；英雄为 `hero` |
| `tribes` / `keywords` / `buffs` | 流派数组 / 词缀 id 数组 / 当前 Buff id 数组 |
| `keyword_values` | 词缀数值字典，如 `first_strike` 的数值 |
| `column` / `column_abs` | 相对列（-4~4）/ 绝对列（1~5） |
| `turn` / `entered_this_turn` | 当前回合数 / 是否本回合入场 |
| `loop_index` / `loop_count` | 本次下标（从 0 开始）/ 目标总数 |
| `loop_target` | 当前目标句柄（等价于循环变量） |

真正的句柄用**循环变量**引用，作为原语参数：

```text
for_each(all_enemies) as e:
    if health <= 3:
        destroy(e)
    elif has_keyword('frost'):
        buff_stats(e, 0, 2)
    else:
        deal_damage(e, 1)
```

### 条件分支

```text
for_each(all_enemies) as e:
    if cost >= 5 and not has_keyword('spell_immune'):
        destroy(e)
```

- `elif` 可连续使用，等价于 `else:` 里再套一个 `if`。
- 条件里可以混用事实变量、查询函数、算术与 `and` / `or` / `not`。

### 新增查询函数

| 查询 | 含义 |
|---|---|
| `cost(target)` | 目标当前费用 |
| `max_health(target)` | 目标生命上限 |
| `defense(target)` | 目标防御值（与 `shield(target)` 相同） |
| `has_tribe(流派[, 实体])` | 是否具有该流派（**包含**语义） |
| `has_keyword(词缀[, 实体])` | 是否具有该词缀（包含语义） |
| `keyword_value(词缀[, 实体])` | 该词缀的当前数值，没有则为 0 |
| `has_buff(buff_id[, 实体])` | 是否带有该 Buff/Debuff |

带 `[实体]` 的形式省略第二个参数时读“当前作用域目标”，传入实体时显式查询它——这也是嵌套循环里读外层目标的手段。

### 嵌套与遮蔽

- 内层 `for_each` 的变量与事实**遮蔽**外层：块内 `attack` 永远指最内层当前目标。
- 读外层目标请用双参数查询：`attack(outer_var)`、`cost(outer_var)`、`has_keyword('frost', outer_var)`。
- 循环结束后循环变量的旧绑定会恢复，不会破坏同名变量。

```text
when damage_dealt:
    for_each(damage_targets) as hurt:
        for_each(all_allies) as friend:
            if health > 0:
                heal(friend, 1)
        if attack(hurt) > 4:
            gain_energy(1)
```

上例中内层的 `health` 是 `friend` 的当前生命；内层循环结束后，`attack(hurt)` 用双参数查询读外层目标。

### 命名限制

循环变量名不能是：

- 语句关键字：`if` / `elif` / `else` / `repeat` / `for_each` / `when` / `as` / `and` / `or` / `not` / `true` / `false`
- 选择器名：`self` / `event` / `chosen` / `all_enemies` / `damage_targets` …
- 事实变量名：`attack` / `health` / `cost` / `shield` / `keywords` / `loop_index` …

违反时在**解析阶段**直接报错，不会等到运行时。

### 与“目标数组原语”的区别

- `deal_damage(all_enemies, 2)`：一次调用被展开到每个目标，参数是共享的常量/表达式结果。
- `for_each(all_enemies) as e:`：**每个目标重新执行整个块**，因此能按目标自己的数值走不同分支、调用不同原语、累加不同变量。

### 与 `repeat` 的区别

- `repeat(n)`：次数固定，与目标无关，上限 100。
- `for_each`：次数等于目标数量，没有 100 次上限；但每个目标都会真实执行块，注意能力强度与连锁限制。

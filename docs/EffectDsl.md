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
| `gain_shield(target, amount)` | 目标、数值 | 加护甲 |
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

目前支持：`enter`（入场）、`die`（死亡）、`attack`（攻击）、`attacked`（受击）、`damaged`（实际受到伤害）、
`healed`（被治疗）、`attack_changed`（攻击力变化）、`health_changed`（生命值变化）、`turn_start`（回合开始）、
`turn_end`（回合结束）、`ally_die`（友方实体死亡，可触发牌库/手牌被动）、`position_changed`（被卡牌移动）、
`buff_applied` / `buff_removed`（Buff 添加/移除）、`extra_attack`（额外攻击）、`evolved`（进化成功）、
`mounted`（底座被放置实体）、`tombstone_enter`（埋入墓碑）、`tombstone_reveal`（墓碑揭示）。

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
- `invincible`：免疫伤害和直接消灭；所在列战斗结算完成后解除
- `spell_immune`：不作为锦囊目标，锦囊效果/伤害不生效
- 相关实体词缀：双重打击、狂热、锦囊免疫、克制英雄、穿透、致命、无敌、捕猎、两栖、溅射、寒霜、反伤、免疫负面
- `debuff_immune` 会阻止冰冻等 Debuff 被施加
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

1. 先进行死亡判定
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
- 仍会被无敌 Buff 阻止
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

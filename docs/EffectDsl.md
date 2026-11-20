# 卡牌能力伪代码（Effect DSL）方案

> 状态：**待你选择语法**。当前 CSV 的 `ability` 列是我用「候选 A（函数调用式）」写的占位示例，
> 选定后会实现对应解析器与静态校验，再统一改写示例数据。

设计前提：

- 代码只提供**抽象原语**（`scripts/data/effects/effect_context.gd`），战斗层实现它；伪代码解释器只调用原语。
- 卡牌引用使用**英文名**（如 `summon("Peashooter")`），解释器通过 `CardDatabase.find_by_english()` 解析，
  官方/模组卡牌靠内部 ID 的命名空间自动区分，伪代码里不用写 `pvzh:` 前缀。
- 能力默认在「打出时（on play）」执行；触发类能力需要事件包装（见下）。
- 未知函数、未知目标选择器应在**加载期**报错，而不是运行时静默失败。

---

## 一、可用原语

| 原语 | 参数 | 说明 |
|---|---|---|
| `summon(card_name, count = 1)` | 英文名、数量 | 召唤实体（实体牌打出也走它） |
| `draw_cards(count)` | int | 抽牌 |
| `deal_damage(target, amount)` | 选择器、数值 | 造成伤害 |
| `heal(target, amount)` | 选择器、数值 | 治疗 |
| `gain_shield(target, amount)` | 选择器、数值 | 加护甲/防御力 |
| `buff_stats(target, atk, hp)` | 选择器、两个增减值 | 修改攻/血 |
| `gain_energy(amount)` | int | 获得费用 |
| `give_keyword(target, keyword)` | 选择器、词缀 id | 赋予词缀（如 `"taunt"`） |
| `destroy(target)` | 选择器 | 消灭 |
| `get_attack(target)` / `get_health(target)` / `get_shield(target)` | 选择器 | 供条件/表达式取值 |

**目标选择器**（字符串）：`self`（这张牌/它的实体）、`chosen`（玩家本次选中的目标）、
`hero`（我方英雄）、`enemy_hero`、`all_enemies`、`random_enemy`、`all_allies`、`random_ally`。

**事件钩子**（需要解释器支持）：`when_play`（默认，可省略）、`when_damaged`、`when_destroyed`、
`when_hero_attacked`、`when_any_damage`。

---

## 二、候选语法（同一组能力对比）

示例能力（涵盖简单伤害、循环、条件、触发、获得费用）：

1. 对选中目标造成 3 点伤害
2. 随机对敌人造成 1 点伤害，重复 3 次
3. 若选中目标攻击力 ≤ 3，则消灭它
4. 每当任意角色受到伤害，随机对敌人造成 1 点伤害
5. 打出时获得 2 点费用

### 候选 A · 函数调用式

```
deal_damage(chosen, 3)

repeat(3) { deal_damage(random_enemy, 1) }

if get_attack(chosen) <= 3 { destroy(chosen) }

when(any_damage) { deal_damage(random_enemy, 1) }

gain_energy(2)
```

- 优点：解析器最简单、性能好、最容易做静态校验；与代码原语一一对应。
- 缺点：可读性一般，复杂卡写起来像代码。
- 实现成本：**低**。

### 候选 B · 中文自然语序

```
对 选中目标 造成 3 点伤害
重复 3 次：对 随机敌人 造成 1 点伤害
若 选中目标 的攻击力 ≤ 3，则 消灭 它
每当 任意角色 受到伤害：对 随机敌人 造成 1 点伤害
获得 2 点费用
```

- 优点：你写卡时最直观，接近卡面描述。
- 缺点：要处理分词、同义词、语序、歧义；写错时报错定位困难；国际化困难。
- 实现成本：**高**。

### 候选 C · Lua 风格脚本（变量/条件/循环/事件）

```
local t = choose(enemy, attack <= 3)
if t then destroy(t) end

for i = 1, 3 do
    deal_damage(random_enemy(), 1)
end

on(any_damage, function(e)
    deal_damage(random_enemy(), 1)
end)
```

- 优点：表达力最强，复杂卡也能写；方便未来模组扩展。
- 缺点：需要完整解析器 + 沙箱（安全执行、限制函数白名单），模组作者门槛高。
- 实现成本：**高**。

### 候选 D · 混合式（函数调用 + 块结构）

```
target = chosen
deal_damage(target, 3)

repeat(3):
    deal_damage(random_enemy, 1)

if attack(chosen) <= 3:
    destroy(chosen)

when any_damage:
    deal_damage(random_enemy, 1)

gain_energy(2)
```

- 优点：比 A 可读、比 C 简单；有变量/条件/循环/事件块，覆盖绝大多数卡牌。
- 缺点：解析器比 A 复杂一些。
- 实现成本：**中**。

---

## 三、对比

| 维度 | A 函数调用 | B 中文语序 | C 脚本式 | D 混合式 |
|---|---|---|---|---|
| 编写门槛 | 中 | 低 | 高 | 中 |
| 可读性 | 中 | 高 | 中 | 中高 |
| 解析器成本 | 低 | 高 | 高 | 中 |
| 静态校验 | 易 | 难 | 中 | 易 |
| 复杂卡支持 | 中（需扩展括号语法） | 差 | 强 | 强 |
| 模组友好度 | 中 | 低 | 高 | 高 |

## 四、我的建议

**选 D（混合式）**：用函数调用做原语、用 `if` / `repeat` / `when` 做结构，变量可选；
可读性和实现成本平衡最好，也最适合未来模组。

如果你更看重「写卡像写卡面描述」，选 B；如果只想尽快跑通简单卡，选 A（后续再升级到 D 也兼容——D 是 A 的超集）。

---

## 五、待你决定

1. 语法选 A / B / C / D（或提出你的变体，比如 `对目标造成伤害` 的中英混合）。
2. 能力触发方式：默认「打出时」+ `when(...)` 事件块，是否够用？
3. 是否需要变量（`x = ...`）与四则运算（如 `deal_damage(chosen, cost * 2)`）？
4. 是否需要「条件选择目标」，如 `chosen_if(attack <= 3)`？

选定后我会：实现解析器 + 静态校验 → 加单元测试 → 把 30 张示例卡的 `ability` 列统一改成最终语法。

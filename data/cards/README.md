# 卡牌数据目录（CSV，数据驱动）

```
data/cards/official/
  config.csv   全局配置：稀有度 / 职业 / 流派（可中文标签）
  cards.csv    每行一张卡牌
```

游戏启动时由 `CardDatabase`（autoload）扫描载入；缺列、非法职业/稀有度会**跳过该行**并记录到 `CardDatabase.load_errors`；
未知词缀/流派会被忽略并记入 `load_errors`，不会让整张卡失效。

---

## 一、全局配置 `config.csv`

```csv
type,name,label_zh
rarity,normal,普通
class,smarty,聪明
tribe,pea,豌豆
```

| 列 | 说明 |
|---|---|
| `type` | `rarity` / `class` / `tribe` |
| `name` | 内部名称（小写，供 CSV 卡牌引用） |
| `label_zh` | 中文显示名（可省略，省略时用 `name`） |

默认值：

- 稀有度：normal / rare / super rare / legend / unknown
- 职业：grow / bloom / solar / smarty / guardian / brainy / sneaky / hearty / beastly / crazy / neutral
- 流派：pea / flower / pet / robot / universe / fruit

## 二、卡牌 `cards.csv`

表头（列顺序可调整，按列名读取）：

```csv
english_name,chinese_name,kind,cost,attack,health,shield,class,rarity,keywords,tribes,ability,description
```

| 列 | 类型 | 说明 |
|---|---|---|
| `english_name` | string | 英文命名，也是内部 ID 的来源（去空格、转小写、空格换下划线） |
| `chinese_name` | string | 中文显示名（默认语言为中文） |
| `kind` | string | `entity`（打出后召唤实体）或 `spell`（锦囊） |
| `cost` | int | 费用 |
| `attack` / `health` | int | 攻击力 / 生命值（锦囊填 0） |
| `shield` | int | 防御力（护甲） |
| `class` | string | 职业，必须是 `config.csv` 中的 class 之一 |
| `rarity` | string | 稀有度，必须是 `config.csv` 中的 rarity 之一 |
| `keywords` | string | 词缀，逗号分隔；未知词缀会被忽略 |
| `tribes` | string | 流派，逗号分隔；必须是配置中的 tribe |
| `ability` | string | 特殊能力，伪代码（见下） |
| `description` | string | 中文简介，卡牌详情页底部显示 |

### 词缀（由代码决定）

`charge` 冲锋、`taunt` 嘲讽、`deadly` 剧毒、`armored` 护甲、`strikethrough` 穿透、
`bullseye` 必中、`double_strike` 双击、`overshoot` 溅射、`frenzy` 狂怒、`untrickable` 免疫锦囊。

完整定义见 `scripts/data/card_keywords.gd`。

### 特殊能力（伪代码，方案 D）

`ability` 列写这张牌的具体效果（函数调用 + 缩进块 + 变量/四则运算/条件目标/事件块），
载入时编译到 `CardData.ability_script`；语法/语义错误记入 `CardDatabase.load_errors`。

- **锦囊（spell）**：顶层语句在打出时执行一次；不能用 `when` 块。
- **实体（entity）**：能力属于召唤出的实体，必须写在 `when` 事件块里；实体牌本身没有锦囊式打出效果。

```csv
# 锦囊：对选中目标造成 6 点伤害
deal_damage(chosen, 6)

# 锦囊：随机 3 次 1 点伤害
repeat(3): deal_damage(random_enemy, 1)

# 锦囊：条件目标
destroy(chosen_if(attack <= 3))

# 实体：入场获得 2 点费用
when enter: gain_energy(2)

# 实体：其他敌方实体（攻击力 > 3）入场时抽 1 张
when enter(side == 'enemy' and attack > 3):
    draw_cards(1)

# 实体：亡语治疗英雄
when die: heal(hero, 3)
```

事件：`enter / die / attack / attacked / healed / attack_changed / health_changed`；
过滤字段：`side`（`self/ally/enemy`，`any` 通配）、`class`、`has_tribe("pea")`、`attack/health/shield`。
不写过滤 = 只响应自己。

完整语法见 `docs/EffectDsl.md`。

## 三、内部命名与模组

- 官方卡牌内部 ID：`pvzh:<english_name>`（`pvzh` 为游戏名前缀，常量在 `CardDatabase.OFFICIAL_NAMESPACE`）。
- 未来模组卡牌：`<作者名>.<模组名>:<english_name>`，例如 `alice.better_cards:spore_shot`。
- 由于命名空间不同，模组卡牌不会与官方卡牌重名；模组目录 `user://mods/...` 的载入接口已预留（`load_mod_card_set`），当前未启用。

## 四、经济数值（按稀有度）

| 稀有度 | 合成（钻石） | 分解（钻石） | 最大持有 |
|---|---|---|---|
| normal | 40 | 5 | 2 |
| rare | 100 | 20 | 2 |
| super rare | 400 | 100 | 2 |
| legend | 1600 | 400 | 1 |
| unknown | 0 | 0 | 2 |

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

### 特殊能力（伪代码）

`ability` 列写这张牌的具体效果，由后续实现的解释器执行抽象原语（召唤、抽牌、造成伤害、治疗、加护甲等）。
语法形式待定稿，示例见 `docs/EffectDsl.md`。

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

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
| `type` | `rarity` / `class` / `tribe` / `neutral_class` |
| `name` | 内部名称（小写，供 CSV 卡牌引用） |
| `label_zh` | 中文显示名（可省略，省略时用 `name`） |

默认值：

- 稀有度：normal / rare / super rare / legend / unknown
- 职业：grow / bloom / solar / smarty / guardian / brainy / sneaky / hearty / beastly / crazy / neutral
- 流派：pea / flower / pet / robot / universe / fruit
- 中立职业（`neutral_class`）：默认 `neutral`（该职业的卡牌在牌组中不受英雄职业限制；只能填已有职业）

## 二、卡牌 `cards.csv`

表头（列顺序可调整，按列名读取）：

```csv
english_name,chinese_name,kind,cost,attack,health,shield,class,rarity,keywords,tribes,ability,description
```

| 列 | 类型 | 说明 |
|---|---|---|
| `english_name` | string | 英文命名，也是内部 ID 的来源（去空格、转小写、空格换下划线） |
| `chinese_name` | string | 中文显示名（默认语言为中文） |
| `kind` | string | `entity`（召唤实体）/ `spell`（锦囊）/ `environment`（环境牌，打出后改变一列环境） |
| `cost` | int | 费用 |
| `attack` / `health` | int | 攻击力 / 生命值（锦囊、环境牌填 0） |
| `shield` | int | 防御力（护甲） |
| `class` | string | 职业，必须是 `config.csv` 中的 class 之一 |
| `rarity` | string | 稀有度，必须是 `config.csv` 中的 rarity 之一 |
| `keywords` | string | 词缀，逗号分隔；带数值的写 `id:数值`（如 `first_strike:2`）；未知词缀或该卡牌种类不允许获得的词缀会被忽略/报错。`bullseye` 表示伤害类型为必中，不增加充能护盾充能 |
| `tribes` | string | 流派，逗号分隔；必须是配置中的 tribe |
| `ability` | string | 特殊能力，伪代码（见下） |
| `description` | string | 中文简介，卡牌详情页底部显示 |
| `art_path` | string | 卡牌外观图路径（如 `res://assets/cards/art/fireball.png`）；留空只显示稀有度背景 |
| `animation` | string | 动画伪代码（when attack/ability/die + play_animation/wait/play_fx），见 `docs/AnimationDsl.md` |
| `deck_includable` | int | 是否可被牌组编入：`1` 可（默认），`0` 不可 |

### 卡面组成与素材尺寸

卡面 = **稀有度背景**（`assets/cards/backgrounds/<rarity>.png`）+ **外观图**（`art_path`）。

- 背景按稀有度取图：`normal.png`、`rare.png`、`super_rare.png`、`legend.png`、`unknown.png`；
  缺图时回退默认纯色卡牌。背景按 9 宫格拉伸，边距 32 px。
- 参考尺寸：背景 **512×640 px（4:5）**，可出 1024×1280；
  外观图建议 **768×512 px（3:2）**（或 512×512），主体居中并留 8% 安全边。
- 列表格子显示 160×200，详情弹窗卡面约 320×480；外观图按 contain/cover 裁切。
- 牌组编辑与战斗手牌共用 `CardTile.tscn`；场上实体使用 `BattleEntityView.tscn`，背景/外观/图标均为空 Sprite2D 节点，详见 `assets/battle/entities/README.md`。
- 详见 `assets/cards/backgrounds/README.md`。

### 词缀（由代码决定）

`charge` 冲锋、`taunt` 嘲讽、`deadly` 剧毒、`armored` 护甲、`strikethrough` 穿透、
`bullseye` 必中、`double_strike` 双击、`overshoot` 溅射、`frenzy` 狂怒、`untrickable` 免疫锦囊、`team_up` 组队。

完整定义见 `scripts/data/card_keywords.gd`。

### 超能力与英雄专属牌

英雄数据 `special_cards` 列出的法术牌就是该英雄的超能力牌池来源。超能力牌在 `tribes` 中带有 `superpower` 流派标记：

- 每个英雄的池子按 `special_card_ids` 生成，每个卡牌 ID 一份
- 开局初始抽牌后随机发放一张到该英雄手牌
- 充能护盾触发免疫时再随机发放一张，并进入超能力特殊回合
- 英雄之间可以共用同一张超能力牌

### 带数值的词缀与种类白名单

CSV 的 `keywords` 列支持 `id:数值`，一张牌可以同时有多个词缀：

```csv
"first_strike:2,team_up"
```

- 读取后进入 `CardData.keywords` 和 `CardData.keyword_values`
- `CardData.keyword_value("first_strike")` 返回 2
- 显示文本为 `先攻 2、组队`
- 先攻伤害走普通英雄伤害结算：免疫 → 护盾 → 生命，并触发 `hero_damaged` 信号
- 没有数值的词缀写 `team_up` 即可

白名单在 `CardKeywords.DEFINITIONS` 的 `allowed_kinds` 中配置，例如：

```gdscript
"first_strike": {
    "label": "先攻",
    "value": true,
    "allowed_kinds": ["entity"],
}
```

当前 `first_strike` 只允许实体牌；锦囊/环境牌无法通过卡牌数据或效果获得它。
未来随机赋予手牌时，应先用 `CardKeywords.can_receive(keyword, card.kind)` 过滤候选。

### 特殊能力（伪代码，方案 D）

`ability` 列写这张牌的具体效果（函数调用 + 缩进块 + 变量/四则运算/条件目标/事件块），
载入时编译到 `CardData.ability_script`；语法/语义错误记入 `CardDatabase.load_errors`。

- **锦囊（spell）**：顶层语句在打出时执行一次；不能用 `when` 块。
- **环境（environment）**：顶层语句在打出时执行；打出时会把所选列的环境改为这张环境牌；不能用 `when` 块。
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


## 四、英雄 `heroes.csv`

与 `cards.csv` 同目录：`data/cards/official/heroes.csv`。

```csv
english_name,chinese_name,faction,classes,special_cards
green_knight,绿影骑士,p,"solar,guardian","fireball,armor_up"
```

| 列 | 说明 |
|---|---|
| `english_name` | 英雄英文名（内部 ID 由它规范化，如 `green_knight`） |
| `chinese_name` | 中文名 |
| `faction` | 阵营：`p` 或 `z` |
| `classes` | 正好两个职业，逗号分隔，必须在全局配置的职业列表中 |
| `special_cards` | 专属卡牌英文名，逗号分隔；必须是 `cards.csv` 里存在的卡 |

英雄不是卡牌。牌组先选英雄，英雄的两个职业限制牌组可用的卡（中立职业除外，专属卡无视限制）。
英雄生命值、初始费用、初始抽牌等由玩法配置决定（p 阵营用“我方”数值，z 阵营用“敌方”数值）。

## 五、玩法配置

默认文件：`data/modes/default_mode.json`；可用 `user://modes/default_mode.json` 覆盖（服务器管理员可改）。
字段说明见 `data/modes/README.md`。未配置任何玩法文件时全部使用内置默认值。
## 六、编译与快速载入（开发者测试界面）

- 待编译目录：`user://card_packs/import/`（放 `config.csv` / `cards.csv`）。
- 调用 `DeveloperTools.compile_card_set()`（源码目录可指定）：
  - 校验全局配置、职业/稀有度/词缀/流派、数值规则（费用必须为正、实体生命 ≥1 等）、伪代码语法与实体/锦囊/环境语义、
    `deck_includable` 必须为 0/1；
  - 报错写入 `user://card_packs/compile_report.txt`，带行号与原因；
  - 全部通过时生成 `user://card_packs/compiled/<命名空间>.cardpack`（已编译能力程序，跳过运行时解析）。
- 启动时若存在 `user://card_packs/compiled/official.cardpack`，`CardDatabase` 会优先读取它（更快）；
  删除该文件或调用 `clear_compiled_official_pack()` 即回退 CSV。
- 模组同样走编译流程：内部 ID 使用 `<作者.模组>:<英文名>` 命名空间，产物可随模组分发。

## 七、经济数值（按稀有度）

| 稀有度 | 合成（钻石） | 分解（钻石） | 最大持有 |
|---|---|---|---|
| normal | 40 | 5 | 2 |
| rare | 100 | 20 | 2 |
| super rare | 400 | 100 | 2 |
| legend | 1600 | 400 | 1 |
| unknown | 0 | 0 | 2 |

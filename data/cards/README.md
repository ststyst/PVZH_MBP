# 卡牌数据目录

卡牌定义由 `CardDatabase`（autoload）启动时扫描本目录的 `*.json` 文件加载。
本目录当前为空，卡牌将在里程碑 M1 填充。

## 文件格式

单个文件可以是数组，也可以是 `{ "cards": [ ... ] }`：

```json
{
  "cards": [
    {
      "card_id": "neutral_young_dragonhawk",
      "display_name": "幼龙鹰",
      "description": "风怒。",
      "card_type": "MINION",
      "rarity": "COMMON",
      "card_class": "NEUTRAL",
      "cost": 1,
      "attack": 1,
      "health": 1,
      "keywords": ["WINDFURY"],
      "art_path": "",
      "craft_cost": 40,
      "disenchant_value": 5
    }
  ]
}
```

## 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `card_id` | string | 全局唯一 ID，建议 `职业_名称`，禁止重复 |
| `display_name` | string | 显示名 |
| `description` | string | 卡牌描述（中文） |
| `card_type` | string | `MINION` / `SPELL` / `WEAPON` / `HERO_POWER` / `LOCATION` |
| `rarity` | string | `FREE` / `COMMON` / `RARE` / `EPIC` / `LEGENDARY` |
| `card_class` | string | `NEUTRAL` / `WARRIOR` / `MAGE` / `HUNTER` / `PRIEST` / `ROGUE` / `DRUID` / `PALADIN` / `SHAMAN` / `WARLOCK` |
| `cost` | int | 法力消耗 |
| `attack` / `health` | int | 随从身材；法术留 0 |
| `keywords` | string[] | 见下 |
| `art_path` | string | 美术留空（需求：优先留空） |
| `craft_cost` / `disenchant_value` | int | 合成 / 分解数值 |

关键词（`CardData.KEYWORD`）：`TAUNT`、`CHARGE`、`RUSH`、`DIVINE_SHIELD`、`LIFESTEAL`、`POISONOUS`、`WINDFURY`、`SPELL_DAMAGE`、`BATTLE_CRY`、`DEATH_RATTLE`。

## 校验

- 缺少 `card_id` 或 ID 重复会被跳过并输出警告（`CardDatabase` 日志）。
- 未知枚举值回退到默认值；未知关键词忽略。

## 模组预留

后续模组可从 `user://mods/<mod_id>/cards/*.json` 加载，ID 建议使用 `mod_id:card_id` 命名空间，避免与官方卡冲突。

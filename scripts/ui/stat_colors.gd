class_name StatColors
extends RefCounted
## 数值涨跌配色（实体攻击/生命、手牌费用/攻击/生命共用）。
##
## 约定：绿色 = 比基准更好、白色 = 与基准相同、红色 = 比基准更差。
## 想换配色只改这三个常量即可（支持 Color(1, 0.42, 0.42) 或 Color("#6b6b6b") 两种写法）。

## 绿色：比基准更好（攻击更高 / 费用更低 / 生命更高）
const BUFFED: Color = Color(0.42, 0.94, 0.45, 1.0)
## 白色：与基准相同
const NORMAL: Color = Color(1.0, 1.0, 1.0, 1.0)
## 红色：比基准更差（攻击更低 / 费用更高 / 生命更低 / 已受伤）
const DEBUFFED: Color = Color(1.0, 0.42, 0.42, 1.0)


## 「当前值 vs 基准值」的一般比较。
## higher_is_better = true 用于攻击/生命；false 用于费用（越低越好）。
static func compare(current: int, base: int, higher_is_better: bool) -> Color:
	if current == base:
		return NORMAL
	var better: bool = current > base if higher_is_better else current < base
	return BUFFED if better else DEBUFFED


## 实体生命：受伤（低于当前生命上限）优先显示红；否则高于数据库初始生命显示绿；其余白。
static func health(current: int, max_health: int, base_health: int) -> Color:
	if current < max_health:
		return DEBUFFED
	if current > base_health:
		return BUFFED
	return NORMAL

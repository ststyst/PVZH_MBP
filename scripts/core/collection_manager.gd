extends Node
## 收藏操作：合成卡牌 / 分解卡牌（消耗与产出钻石）。
## 所有函数只操作传入的 PlayerProfile 与 CardData，不依赖其他单例，便于测试。

const MAX_COPIES_DEFAULT: int = 2
const MAX_COPIES_LEGENDARY: int = 1

signal collection_changed()


## 该卡牌允许持有的最大张数（传说卡 1 张，其余 2 张）。
func max_copies_for(card: CardData) -> int:
	if card == null:
		return 0
	if card.rarity == CardData.RARITY.LEGENDARY:
		return MAX_COPIES_LEGENDARY
	return MAX_COPIES_DEFAULT


func owned_count(profile: PlayerProfile, card: CardData) -> int:
	if profile == null or card == null:
		return 0
	return profile.get_card_count(card.card_id)


func can_craft(profile: PlayerProfile, card: CardData) -> bool:
	if profile == null or card == null:
		return false
	if owned_count(profile, card) >= max_copies_for(card):
		return false
	return profile.diamond >= card.craft_cost


func can_disenchant(profile: PlayerProfile, card: CardData) -> bool:
	if profile == null or card == null:
		return false
	return profile.get_card_count(card.card_id) > 0


## 合成一张卡牌。返回 { ok: bool, message: String }。
func craft_card(profile: PlayerProfile, card: CardData) -> Dictionary:
	if profile == null or card == null:
		return {"ok": false, "message": "数据缺失，无法合成。"}
	var owned: int = profile.get_card_count(card.card_id)
	if owned >= max_copies_for(card):
		return {"ok": false, "message": "已达到可持有的最大张数。"}
	if profile.diamond < card.craft_cost:
		return {
			"ok": false,
			"message": "钻石不足，还差 %d。" % (card.craft_cost - profile.diamond),
		}
	profile.diamond -= card.craft_cost
	profile.add_card(card.card_id, 1)
	collection_changed.emit()
	return {"ok": true, "message": "合成成功：%s" % card.display_name}


## 分解一张卡牌。返回 { ok: bool, message: String }。
func disenchant_card(profile: PlayerProfile, card: CardData) -> Dictionary:
	if profile == null or card == null:
		return {"ok": false, "message": "数据缺失，无法分解。"}
	if not profile.remove_card(card.card_id, 1):
		return {"ok": false, "message": "你没有这张卡，无法分解。"}
	profile.diamond += card.disenchant_value
	collection_changed.emit()
	return {
		"ok": true,
		"message": "分解 %s，获得 %d 钻石。" % [card.display_name, card.disenchant_value],
	}

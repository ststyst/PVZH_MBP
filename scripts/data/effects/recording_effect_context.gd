class_name RecordingEffectContext
extends EffectContext
## 用于测试/调试的上下文：只记录调用，不改变任何游戏状态。
## 伪代码解释器写好后，可用它断言“这段能力最终调用了哪些原语”。

var calls: Array[Dictionary] = []


func reset() -> void:
	calls.clear()


func summon(card_name: String, count: int = 1) -> Array:
	calls.append({"op": "summon", "card": card_name, "count": count})
	return []


func draw_cards(count: int) -> int:
	calls.append({"op": "draw_cards", "count": count})
	return count


func deal_damage(target: String, amount: int) -> void:
	calls.append({"op": "deal_damage", "target": target, "amount": amount})


func heal(target: String, amount: int) -> void:
	calls.append({"op": "heal", "target": target, "amount": amount})


func gain_shield(target: String, amount: int) -> void:
	calls.append({"op": "gain_shield", "target": target, "amount": amount})


func buff_stats(target: String, attack_delta: int, health_delta: int) -> void:
	calls.append({
		"op": "buff_stats",
		"target": target,
		"attack": attack_delta,
		"health": health_delta,
	})


func gain_energy(amount: int) -> void:
	calls.append({"op": "gain_energy", "amount": amount})


func give_keyword(target: String, keyword: String) -> void:
	calls.append({"op": "give_keyword", "target": target, "keyword": keyword})


func destroy(target: String) -> void:
	calls.append({"op": "destroy", "target": target})

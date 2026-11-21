class_name DeckRow
extends Button
## 牌组列表中的单行按钮（所有行共用此场景，便于替换素材）。
## 数据由 setup() 注入，点击由牌组列表界面处理。

var deck_id: String = ""


func setup(deck: DeckData, hero_name: String, is_default: bool = false) -> void:
	deck_id = deck.deck_id
	var tag: String = " · 默认" if is_default else ""
	text = "%s — %s（%d/40%s）" % [deck.deck_name, hero_name, deck.card_count(), tag]
	tooltip_text = deck.deck_name

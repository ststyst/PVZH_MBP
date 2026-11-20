extends Node
## 战斗入口管理：推荐卡组加载、可用牌组筛选、开始“电脑随机卡组”对局。

const RECOMMENDED_FILE: String = "res://data/battle/recommended_decks.csv"
const DIFFICULTY_EASY: String = "easy"

var recommended_decks: RecommendedDecks = null
var current_battle: Dictionary = {}


func _ready() -> void:
	reload_recommended_decks()


func reload_recommended_decks() -> void:
	recommended_decks = RecommendedDecks.new()
	recommended_decks.load_file(RECOMMENDED_FILE, CardDatabase, HeroDatabase)


## 可出战的玩家牌组：必须带有 default 标签。
func get_available_player_decks() -> Array[DeckData]:
	var result: Array[DeckData] = []
	var profile: PlayerProfile = GameState.profile
	if profile == null:
		return result
	for deck: DeckData in profile.decks:
		if deck.has_tag(DeckRules.TAG_DEFAULT):
			result.append(deck)
	return result


## 开始“电脑随机卡组对战”。成功时写入 current_battle，供战斗场景读取。
func start_vs_ai(player_deck_id: String, difficulty: String = DIFFICULTY_EASY) -> Dictionary:
	if difficulty != DIFFICULTY_EASY:
		return {"ok": false, "message": "暂只支持简单难度。"}
	var deck: DeckData = DeckManager.get_deck(player_deck_id)
	if deck == null:
		return {"ok": false, "message": "牌组不存在。"}
	if not deck.has_tag(DeckRules.TAG_DEFAULT):
		return {"ok": false, "message": "该牌组未满足默认规则，不能出战。"}
	if deck.card_count() == 0:
		return {"ok": false, "message": "该牌组为空，不能出战。"}
	var hero: HeroData = HeroDatabase.get_hero(deck.hero_id)
	if hero == null:
		return {"ok": false, "message": "牌组英雄不存在。"}
	var enemy: Dictionary = _pick_enemy_deck(hero.faction)
	if enemy.is_empty():
		return {"ok": false, "message": "没有可用的电脑推荐卡组（需要不同阵营）。"}
	current_battle = {
		"player_deck_id": deck.deck_id,
		"player_side": hero.faction,
		"player_hero_id": hero.hero_id,
		"player_deck_ids": deck.card_ids.duplicate(),
		"enemy_side": "z" if hero.faction == "p" else "p",
		"enemy_hero_id": str(enemy.get("hero_id", "")),
		"enemy_deck_ids": enemy.get("card_ids", []).duplicate(),
		"difficulty": difficulty,
	}
	return {"ok": true, "message": "对局已准备：%s vs %s" % [deck.deck_name, enemy.get("deck_name", "")]}


func clear_current_battle() -> void:
	current_battle = {}


func _pick_enemy_deck(player_faction: String) -> Dictionary:
	if recommended_decks == null:
		return {}
	var candidates: Array[Dictionary] = recommended_decks.decks_for_enemy(player_faction)
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]

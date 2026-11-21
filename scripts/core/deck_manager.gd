extends Node
## 牌组管理 API：新增 / 删除 / 编辑 / 当前编辑牌组 / 加牌 / 去牌 / 改名 / 换英雄。
##
## 牌组数据持久化在 PlayerProfile.decks（随存档保存；服务器身份下由服务器代理）。
## 名称规则：
##   - 保存时名称为空 → 英雄名称 + "#" + 随机三位数字，重名则重新生成；
##   - 玩家自定义名称与已有牌组重名 → 取消保存并提示“牌组重名”。
## 标签规则：
##   - 保存后若完全符合当前玩法配置的牌组要求 → 打上 default 标签；否则移除。

signal decks_changed()
signal editing_changed(deck_id: String)

var _editing_deck_id: String = ""


# ----- 查询 -----

func get_decks() -> Array[DeckData]:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return []
	return profile.decks


func get_deck(deck_id: String) -> DeckData:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return null
	return profile.find_deck(deck_id)


func get_editing_deck_id() -> String:
	return _editing_deck_id


func get_editing_deck() -> DeckData:
	if _editing_deck_id.is_empty():
		return null
	return get_deck(_editing_deck_id)


func begin_edit(deck_id: String) -> DeckData:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return null
	_editing_deck_id = deck_id
	editing_changed.emit(deck_id)
	return deck


func end_edit() -> void:
	_editing_deck_id = ""
	editing_changed.emit("")


func get_deck_errors(deck_id: String) -> Array[String]:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return ["牌组不存在。"]
	return DeckRules.validate(deck, CardDatabase, HeroDatabase, ModeManager.get_mode(), _profile())


## 当前牌组可选择的卡牌列表（牌组编辑器用）：
## 只显示玩家背包中拥有、可编入、且符合英雄职业（或中立/专属）的卡。
func get_available_cards(deck_id: String) -> Array[Dictionary]:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return []
	return DeckRules.selectable_cards(_profile(), deck, CardDatabase, HeroDatabase, ModeManager.get_mode())


## 可选卡牌 ID 列表（便捷版）。
func get_available_card_ids(deck_id: String) -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in get_available_cards(deck_id):
		ids.append(str(entry.get("card_id", "")))
	return ids


# ----- 新增 / 删除 / 改名 / 换英雄 -----

## 创建牌组；deck_name 为空时自动生成「英雄名#三位数字」。
func create_deck(hero_id: String, deck_name: String = "") -> Dictionary:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return _fail("当前没有玩家存档。")
	var hero: HeroData = HeroDatabase.get_hero(hero_id)
	if hero == null:
		return _fail("英雄不存在：%s" % hero_id)
	var resolved: Dictionary = _resolve_deck_name(hero, deck_name, "")
	if not bool(resolved.get("ok", false)):
		return resolved
	var deck := DeckData.new()
	deck.deck_id = _generate_deck_id(profile)
	deck.deck_name = str(resolved.get("name", ""))
	deck.hero_id = hero.hero_id
	deck.allowed_classes = hero.classes.duplicate()
	deck.updated_at_unix = int(Time.get_unix_time_from_system())
	profile.decks.append(deck)
	DeckRules.refresh_tags(deck, CardDatabase, HeroDatabase, ModeManager.get_mode(), _profile())
	_persist()
	decks_changed.emit()
	return {"ok": true, "message": "已创建牌组：%s" % deck.deck_name, "deck_id": deck.deck_id, "deck": deck}


func delete_deck(deck_id: String) -> Dictionary:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return _fail("当前没有玩家存档。")
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	profile.remove_deck(deck_id)
	if _editing_deck_id == deck_id:
		_editing_deck_id = ""
		editing_changed.emit("")
	_persist()
	decks_changed.emit()
	return {"ok": true, "message": "已删除牌组：%s" % deck.deck_name, "deck_id": deck_id}


func rename_deck(deck_id: String, new_name: String) -> Dictionary:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	var hero: HeroData = HeroDatabase.get_hero(deck.hero_id)
	if hero == null:
		return _fail("牌组英雄不存在，无法生成名称。")
	var resolved: Dictionary = _resolve_deck_name(hero, new_name, deck_id)
	if not bool(resolved.get("ok", false)):
		return resolved
	deck.deck_name = str(resolved.get("name", ""))
	deck.updated_at_unix = int(Time.get_unix_time_from_system())
	_persist()
	decks_changed.emit()
	return {"ok": true, "message": "已重命名为：%s" % deck.deck_name, "deck_id": deck_id}


func set_deck_hero(deck_id: String, hero_id: String) -> Dictionary:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	var hero: HeroData = HeroDatabase.get_hero(hero_id)
	if hero == null:
		return _fail("英雄不存在：%s" % hero_id)
	deck.hero_id = hero.hero_id
	deck.allowed_classes = hero.classes.duplicate()
	var errors: Array[String] = DeckRules.refresh_tags(
		deck, CardDatabase, HeroDatabase, ModeManager.get_mode(), _profile()
	)
	_persist()
	decks_changed.emit()
	return {"ok": true, "message": "已切换英雄：%s" % hero.display_name(), "errors": errors, "tags": deck.tags.duplicate()}


# ----- 编入 / 移除卡牌 -----

func add_card(deck_id: String, card_id: String) -> Dictionary:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return _fail("当前没有玩家存档。")
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	var card: CardData = CardDatabase.get_card(card_id)
	if card == null:
		return _fail("卡牌不存在：%s" % card_id)
	if not card.deck_includable:
		return _fail("该卡牌不可被编入牌组。")
	var hero: HeroData = HeroDatabase.get_hero(deck.hero_id)
	if hero == null:
		return _fail("请先为牌组选择英雄。")
	var mode: GameModeConfig = ModeManager.get_mode()
	if deck.card_count() >= mode.deck_max_size:
		return _fail("牌组已达上限（%d 张）。" % mode.deck_max_size)
	var owned: int = profile.get_card_count(card_id)
	if deck.count_of(card_id) >= owned:
		return _fail("存档中只有 %d 张该卡牌，不能再加入。" % owned)
	var max_copies: int = DeckRules.max_copies_for(card, CardDatabase, mode)
	if deck.count_of(card_id) >= max_copies:
		return _fail("该卡牌已达上限（%d 张）。" % max_copies)
	if not DeckRules.class_allowed(card, hero, CardDatabase.get_neutral_classes()):
		return _fail("该卡牌的职业不符合英雄要求。")
	if not deck.add_card(card_id):
		return _fail("加入卡牌失败。")
	DeckRules.refresh_tags(deck, CardDatabase, HeroDatabase, mode, profile)
	_persist()
	decks_changed.emit()
	return {
		"ok": true,
		"message": "已加入：%s" % card.display_name(),
		"deck_id": deck_id,
		"count": deck.count_of(card_id),
	}


func remove_card(deck_id: String, card_id: String) -> Dictionary:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	if not deck.remove_card(card_id):
		return _fail("牌组中没有该卡牌。")
	DeckRules.refresh_tags(deck, CardDatabase, HeroDatabase, ModeManager.get_mode(), _profile())
	_persist()
	decks_changed.emit()
	return {"ok": true, "message": "已移除一张卡牌。", "deck_id": deck_id, "count": deck.count_of(card_id)}


## 保存牌组：无论是否符合默认组卡规则都会保存成功；
## 完全符合时打上 default 标签，不符合时仅移除该标签（不阻止保存）。
func save_deck(deck_id: String) -> Dictionary:
	var deck: DeckData = get_deck(deck_id)
	if deck == null:
		return _fail("牌组不存在。")
	var errors: Array[String] = DeckRules.refresh_tags(
		deck, CardDatabase, HeroDatabase, ModeManager.get_mode(), _profile()
	)
	deck.updated_at_unix = int(Time.get_unix_time_from_system())
	_persist()
	decks_changed.emit()
	var message: String = "牌组已保存。"
	if not errors.is_empty():
		message = "牌组已保存（未满足完整牌组要求，已移除 default 标签）。"
	return {
		"ok": true,
		"message": message,
		"errors": errors,
		"tags": deck.tags.duplicate(),
	}


# ----- 内部 -----

func _profile() -> PlayerProfile:
	return GameState.profile


func _resolve_deck_name(hero: HeroData, requested: String, exclude_deck_id: String) -> Dictionary:
	var trimmed: String = requested.strip_edges()
	if trimmed.is_empty():
		return {"ok": true, "name": _generate_unique_name(hero)}
	if _deck_name_exists(trimmed, exclude_deck_id):
		return {"ok": false, "message": "牌组重名"}
	return {"ok": true, "name": trimmed}


func _generate_unique_name(hero: HeroData) -> String:
	var base_name: String = hero.display_name()
	for _attempt: int in range(200):
		var candidate: String = "%s#%03d" % [base_name, randi() % 1000]
		if not _deck_name_exists(candidate, ""):
			return candidate
	return "%s#%03d" % [base_name, int(Time.get_unix_time_from_system()) % 1000]


func _deck_name_exists(deck_name: String, exclude_deck_id: String) -> bool:
	var profile: PlayerProfile = _profile()
	if profile == null:
		return false
	var lowered: String = deck_name.strip_edges().to_lower()
	for deck: DeckData in profile.decks:
		if deck.deck_id == exclude_deck_id:
			continue
		if deck.deck_name.strip_edges().to_lower() == lowered:
			return true
	return false


func _generate_deck_id(profile: PlayerProfile) -> String:
	var base: String = "deck_%d" % int(Time.get_unix_time_from_system())
	var candidate: String = base
	var suffix: int = 1
	while profile.find_deck(candidate) != null:
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _persist() -> void:
	if GameState.profile != null:
		GameState.save_active_profile()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

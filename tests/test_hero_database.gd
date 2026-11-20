@tool
extends McpTestSuite
## 英雄数据加载测试。suite = "heroes"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const HeroDatabaseScript := preload("res://scripts/core/hero_database.gd")
const HERO_FILE: String = "res://data/cards/official/heroes.csv"
const TEMP_DIR: String = "user://test_heroes"

var cards: Node = null
var heroes: Node = null


func suite_name() -> String:
	return "heroes"


func setup() -> void:
	_cleanup()
	cards = CardDatabaseScript.new()
	cards.reload(false)
	heroes = HeroDatabaseScript.new()
	heroes.reload_from(HERO_FILE, cards)


func teardown() -> void:
	_cleanup()
	if is_instance_valid(cards):
		cards.free()
	cards = null
	if is_instance_valid(heroes):
		heroes.free()
	heroes = null


func _cleanup() -> void:
	var file_path: String = TEMP_DIR.path_join("heroes.csv")
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR)


func _write_heroes_csv(text: String) -> String:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path: String = TEMP_DIR.path_join("heroes.csv")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	return path


func test_official_heroes_loaded() -> void:
	assert_gt(heroes.heroes.size(), 2, "应载入官方英雄")
	assert_eq(heroes.load_errors.size(), 0, "官方英雄不应有加载错误：%s" % [heroes.load_errors])
	var hero: HeroData = heroes.get_hero("green_knight")
	assert_true(hero != null)
	if hero == null:
		return
	assert_eq(hero.chinese_name, "绿影骑士")
	assert_eq(hero.faction, "p")
	assert_eq(hero.classes.size(), 2)
	assert_true(hero.has_class("solar"))
	assert_true(hero.has_class("guardian"))
	assert_true(hero.special_card_ids.has("pvzh:fireball"), "专属卡牌应解析为内部 ID")
	assert_true(hero.special_card_ids.has("pvzh:armor_up"))


func test_factions() -> void:
	assert_gt(heroes.heroes_by_faction("p").size(), 0)
	assert_gt(heroes.heroes_by_faction("z").size(), 0)
	for hero: HeroData in heroes.heroes_by_faction("p"):
		assert_true(hero.is_p())
	for hero: HeroData in heroes.heroes_by_faction("z"):
		assert_true(hero.is_z())


func test_unknown_class_reports_error() -> void:
	var path: String = _write_heroes_csv(
		"english_name,chinese_name,faction,classes,special_cards\nbad_hero,坏英雄,p,\"solar,bogus\",\"\"\n"
	)
	heroes.reload_from(path, cards)
	assert_true(heroes.load_errors.size() > 0, "未知职业应报错")
	var joined: String = "\n".join(heroes.load_errors)
	assert_true(joined.find("职业不在全局配置中") != -1, "错误应说明职业问题：%s" % joined)
	heroes.reload_from(HERO_FILE, cards)


func test_missing_special_card_reports_error() -> void:
	var path: String = _write_heroes_csv(
		"english_name,chinese_name,faction,classes,special_cards\nbad_special,坏专属,p,\"solar,guardian\",not_a_card\n"
	)
	heroes.reload_from(path, cards)
	var joined: String = "\n".join(heroes.load_errors)
	assert_true(joined.find("专属卡牌不存在") != -1, "错误应说明专属卡牌问题：%s" % joined)
	heroes.reload_from(HERO_FILE, cards)


func test_hero_must_have_two_classes() -> void:
	var path: String = _write_heroes_csv(
		"english_name,chinese_name,faction,classes,special_cards\none_class,单职业,p,solar,\"\"\n"
	)
	heroes.reload_from(path, cards)
	var joined: String = "\n".join(heroes.load_errors)
	assert_true(joined.find("正好拥有两个职业") != -1, "应要求两个职业：%s" % joined)
	heroes.reload_from(HERO_FILE, cards)

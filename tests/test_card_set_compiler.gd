@tool
extends McpTestSuite
## 卡牌 CSV 编译器测试：校验、报错文件、编译包与快速载入。suite = "card_compiler"。

const CardDatabaseScript := preload("res://scripts/core/card_database.gd")
const TEST_ROOT: String = "user://test_card_packs"
const HEADER: String = "english_name,chinese_name,kind,cost,attack,health,shield,class,rarity,keywords,tribes,ability,description\n"
const CONFIG_TEXT: String = "type,name,label_zh\nrarity,normal,普通\nrarity,rare,稀有\nclass,neutral,中立\nclass,solar,光能\ntribe,pea,豌豆\n"


func suite_name() -> String:
	return "card_compiler"


func setup() -> void:
	_remove_directory(TEST_ROOT)


func teardown() -> void:
	_remove_directory(TEST_ROOT)


func _remove_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		var full_path: String = path.path_join(entry_name)
		if dir.current_is_dir():
			_remove_directory(full_path)
		else:
			dir.remove(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _make_pack(folder: String, rows: Array[String]) -> void:
	var dir_path: String = TEST_ROOT.path_join(folder)
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	var cards_text: String = HEADER
	for row: String in rows:
		cards_text += row + "\n"
	_write_text(dir_path.path_join("cards.csv"), cards_text)


## 编译到测试目录内，避免污染 user://card_packs/compiled。
func _compile(folder: String, card_namespace: String = "testmod") -> Dictionary:
	var dir_path: String = TEST_ROOT.path_join(folder)
	return CardSetCompiler.compile_pack(
		dir_path,
		card_namespace,
		dir_path.path_join("compiled.cardpack"),
	)


func test_valid_pack_compiles_and_loads() -> void:
	_make_pack("valid", [
		'test_pawn,测试兵,entity,1,1,2,0,neutral,normal,taunt,pea,"when enter: gain_energy(2)","测试用随从。"',
		'test_bolt,测试弹,spell,2,0,0,0,neutral,normal,"","","deal_damage(chosen, 3)","测试用法术。"',
	])
	var result: Dictionary = _compile("valid")
	assert_true(bool(result.get("ok", false)), "有效 CSV 应编译成功：%s" % [result.get("errors", [])])
	assert_true(str(result.get("pack_path", "")).ends_with(".cardpack"))
	if not str(result.get("pack_path", "")).is_empty():
		assert_true(FileAccess.file_exists(str(result.get("pack_path", ""))), "编译包应存在")
	assert_true(FileAccess.file_exists(CardSetCompiler.REPORT_PATH), "应生成编译报告")
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	var loaded: int = database.load_pack_file(str(result.get("pack_path", "")), "", true)
	assert_eq(loaded, 2)
	var card: CardData = database.get_card("testmod:test_pawn")
	assert_true(card != null, "编译包应能载入卡牌")
	if card != null:
		assert_eq(card.chinese_name, "测试兵")
		assert_eq(card.ability_script.events.size(), 1)
		if not card.ability_script.events.is_empty():
			assert_eq(str(card.ability_script.events[0].get("event", "")), "enter")
	if is_instance_valid(database):
		database.free()


func test_multi_ability_entity_compiles() -> void:
	_make_pack("multi", [
		'two_forms,双能,entity,2,2,2,0,neutral,normal,"","","when die: gain_energy(2); when enter: buff_stats(self, 2, 0)","双异能测试。"',
	])
	var result: Dictionary = _compile("multi")
	assert_true(bool(result.get("ok", false)), "双异能实体应编译成功：%s" % [result.get("errors", [])])
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	database.load_pack_file(str(result.get("pack_path", "")), "", true)
	var card: CardData = database.get_card("testmod:two_forms")
	assert_true(card != null)
	if card != null:
		assert_eq(card.ability_script.events.size(), 2, "应保留两个事件块")
	if is_instance_valid(database):
		database.free()


func test_invalid_pack_reports_all_problems() -> void:
	_make_pack("invalid", [
		'zero_cost,零费,entity,0,1,1,0,neutral,normal,"","pea","","费用为 0。"',
		'dead_entity,零血,entity,1,1,0,0,neutral,normal,"","","","生命为 0。"',
		'bad_keyword,坏词缀,entity,1,1,1,0,neutral,normal,nope,"pea","","未知词缀。"',
		'bad_tribe,坏流派,entity,1,1,1,0,neutral,normal,"","wizard","","未知流派。"',
		'bad_class,坏职业,entity,1,1,1,0,wizard,normal,"","","","未知职业。"',
		'bad_rarity,坏稀有度,entity,1,1,1,0,neutral,mythic,"","","","未知稀有度。"',
		'bad_ability,坏能力,spell,1,0,0,0,neutral,normal,"","","boom(1)","语法错误。"',
		'entity_top,实体顶层,entity,2,2,2,0,neutral,normal,"","","gain_energy(2)","实体不能有顶层语句。"',
		'dup_card,重复一,entity,1,1,1,0,neutral,normal,"","","","重复 ID。"',
		'dup_card,重复二,entity,1,1,1,0,neutral,normal,"","","","重复 ID。"',
	])
	var result: Dictionary = _compile("invalid")
	assert_false(bool(result.get("ok", true)), "非法 CSV 不应编译成功")
	assert_eq(str(result.get("pack_path", "")), "", "失败时不应生成编译包")
	var errors: Array = result.get("errors", [])
	var joined: String = "\n".join(errors)
	assert_true(joined.find("费用必须为正数") != -1, "应报告费用问题：%s" % joined)
	assert_true(joined.find("生命值不能小于 1") != -1, "应报告实体生命问题：%s" % joined)
	assert_true(joined.find("未知词缀") != -1, "应报告未知词缀：%s" % joined)
	assert_true(joined.find("未知流派") != -1, "应报告未知流派：%s" % joined)
	assert_true(joined.find("职业不在全局配置中") != -1, "应报告职业问题：%s" % joined)
	assert_true(joined.find("稀有度不在全局配置中") != -1, "应报告稀有度问题：%s" % joined)
	assert_true(joined.find("能力语法错误") != -1, "应报告伪代码语法问题：%s" % joined)
	assert_true(joined.find("能力语义错误") != -1, "应报告实体顶层语句问题：%s" % joined)
	assert_true(joined.find("卡牌 ID 重复") != -1, "应报告重复 ID：%s" % joined)
	var report: String = FileAccess.get_file_as_string(CardSetCompiler.REPORT_PATH)
	assert_true(report.find("错误") != -1, "报告文件应包含错误清单")
	assert_true(report.find("第 2 行") != -1, "报告应带行号：%s" % report)


func test_spell_nonzero_stats_is_warning_only() -> void:
	_make_pack("warning", [
		'odd_spell,怪法术,spell,1,1,1,0,neutral,normal,"","","deal_damage(chosen, 1)","数值异常但可编译。"',
	])
	var result: Dictionary = _compile("warning")
	assert_true(bool(result.get("ok", false)), "只有警告时应编译成功：%s" % [result.get("errors", [])])
	var warnings: Array = result.get("warnings", [])
	var joined: String = "\n".join(warnings)
	assert_true(joined.find("锦囊牌") != -1, "应提示锦囊牌数值异常：%s" % joined)


func test_missing_cards_csv_reports_error() -> void:
	var dir_path: String = TEST_ROOT.path_join("empty")
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	var result: Dictionary = CardSetCompiler.compile_pack(dir_path, "testmod")
	assert_false(bool(result.get("ok", true)))
	var joined: String = "\n".join(result.get("errors", []))
	assert_true(joined.find("cards.csv") != -1, "应报告缺少 cards.csv：%s" % joined)


func test_animation_column_roundtrip() -> void:
	var dir_path: String = TEST_ROOT.path_join("anim")
	var header: String = HEADER.trim_suffix("\n") + ",animation\n"
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(
		dir_path.path_join("cards.csv"),
		header + "anim_unit,动画单位,entity,1,1,1,0,neutral,normal,\"\",\"\",\"\",\"\",\"when attack: play_animation(self, 'slash', 'whole')\"\n"
	)
	var result: Dictionary = _compile("anim")
	assert_true(bool(result.get("ok", false)), "动画列应能编译：%s" % [result.get("errors", [])])
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	database.load_pack_file(str(result.get("pack_path", "")), "", true)
	var card: CardData = database.get_card("testmod:anim_unit")
	assert_true(card != null)
	if card != null:
		assert_true(card.animation_script != null)
		assert_true(card.animation_script.has_trigger("attack"))
	if is_instance_valid(database):
		database.free()


func test_keyword_values_and_kind_whitelist() -> void:
	var dir_path: String = TEST_ROOT.path_join("keywords")
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(
		dir_path.path_join("cards.csv"),
		HEADER
		+ 'kw_entity,词缀实体,entity,1,1,1,0,neutral,normal,"first_strike:2,team_up","","",""\n'
		+ 'kw_spell,词缀锦囊,spell,1,0,0,0,neutral,normal,first_strike:2,"","",""\n'
	)
	var result: Dictionary = _compile("keywords")
	assert_false(bool(result.get("ok", true)), "锦囊牌不应允许先攻词缀")
	var errors: Array = result.get("errors", [])
	assert_true(str(errors).find("词缀不允许") != -1, "编译器应报告种类白名单错误：%s" % [errors])

	# 只编译合法实体行，验证数值与显示文本进入编译包
	_write_text(
		dir_path.path_join("cards.csv"),
		HEADER + 'kw_entity,词缀实体,entity,1,1,1,0,neutral,normal,"first_strike:2,team_up","","",""\n'
	)
	var valid: Dictionary = _compile("keywords")
	assert_true(bool(valid.get("ok", false)), "合法词缀应能编译：%s" % [valid.get("errors", [])])
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	database.load_pack_file(str(valid.get("pack_path", "")), "", true)
	var card: CardData = database.get_card("testmod:kw_entity")
	assert_true(card != null)
	if card != null:
		assert_eq(card.keyword_value("first_strike"), 2)
		assert_true(card.has_keyword("first_strike"))
		assert_true(card.has_keyword("team_up"))
		assert_eq(card.get_keywords_text(), "先攻 2、组队")
	if is_instance_valid(database):
		database.free()


func test_environment_kind_compiles() -> void:
	var dir_path: String = TEST_ROOT.path_join("env")
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(
		dir_path.path_join("cards.csv"),
		HEADER + 'env_card,环境卡,environment,1,0,0,0,neutral,normal,"","","",""\n'
	)
	var result: Dictionary = _compile("env")
	assert_true(bool(result.get("ok", false)), "环境牌应能编译：%s" % [result.get("errors", [])])


func test_namespace_required() -> void:
	_make_pack("nons", [
		'pawn,兵,entity,1,1,1,0,neutral,normal,"","","",""',
	])
	var result: Dictionary = _compile("nons", "")
	assert_false(bool(result.get("ok", true)), "空命名空间应报错")


func test_art_path_roundtrip_and_validation() -> void:
	var dir_path: String = TEST_ROOT.path_join("art")
	var header: String = HEADER.trim_suffix("\n") + ",art_path\n"
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(
		dir_path.path_join("cards.csv"),
		header + 'art_card,美术卡,entity,1,1,1,0,neutral,normal,"","","","",res://icon.svg\n'
	)
	var result: Dictionary = _compile("art")
	assert_true(bool(result.get("ok", false)), "有效美术路径应能编译：%s" % [result.get("errors", [])])
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	database.load_pack_file(str(result.get("pack_path", "")), "", true)
	var card: CardData = database.get_card("testmod:art_card")
	assert_true(card != null)
	if card != null:
		assert_eq(card.art_path, "res://icon.svg")
	if is_instance_valid(database):
		database.free()

	var bad_dir: String = TEST_ROOT.path_join("art_bad")
	_write_text(bad_dir.path_join("config.csv"), CONFIG_TEXT)
	_write_text(
		bad_dir.path_join("cards.csv"),
		header + 'art_bad,坏美术,entity,1,1,1,0,neutral,normal,"","","","",res://missing_art.png\n'
	)
	var bad: Dictionary = _compile("art_bad")
	assert_false(bool(bad.get("ok", true)), "缺失美术文件应编译失败")
	var joined: String = "\n".join(bad.get("errors", []))
	assert_true(joined.find("美术素材不存在") != -1, "应报告美术素材缺失：%s" % joined)


func test_deck_includable_flag_roundtrip() -> void:
	var dir_path: String = TEST_ROOT.path_join("flag")
	var header: String = HEADER.trim_suffix("\n") + ",deck_includable\n"
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(dir_path.path_join("cards.csv"), header + 'token_unit,代币,entity,1,1,1,0,neutral,normal,"","","","",0\n')
	var result: Dictionary = _compile("flag")
	assert_true(bool(result.get("ok", false)), "deck_includable=0 应能编译：%s" % [result.get("errors", [])])
	var database: Node = CardDatabaseScript.new()
	database.reload(false)
	database.load_pack_file(str(result.get("pack_path", "")), "", true)
	var card: CardData = database.get_card("testmod:token_unit")
	assert_true(card != null)
	if card != null:
		assert_false(card.deck_includable, "编译包应保留 deck_includable=0")
	if is_instance_valid(database):
		database.free()


func test_deck_includable_invalid_reports_error() -> void:
	var dir_path: String = TEST_ROOT.path_join("flag_bad")
	var header: String = HEADER.trim_suffix("\n") + ",deck_includable\n"
	_write_text(dir_path.path_join("config.csv"), CONFIG_TEXT)
	_write_text(dir_path.path_join("cards.csv"), header + 'token_unit,代币,entity,1,1,1,0,neutral,normal,"","","","",2\n')
	var result: Dictionary = _compile("flag_bad")
	assert_false(bool(result.get("ok", true)), "deck_includable=2 应编译失败")
	var joined: String = "\n".join(result.get("errors", []))
	assert_true(joined.find("必须是 0 或 1") != -1, "应报告标志位非法：%s" % joined)

@tool
extends McpTestSuite
## 联机协议/消息序列化基础测试。suite = "net"。

func suite_name() -> String:
	return "net"


func test_protocol_roundtrip() -> void:
	var message: Dictionary = BattleProtocol.command(3, 2, "hand", "play_card", {
		"hand_index": 1,
		"target": {"column": 2, "slot": 0, "handles": [4, 5]},
	})
	var payload: PackedByteArray = BattleProtocol.encode(message)
	var decoded: Dictionary = BattleProtocol.decode(payload)
	assert_true(bool(decoded.get("ok", false)))
	var restored: Dictionary = decoded.get("message", {})
	assert_eq(str(restored.get("type", "")), BattleProtocol.MSG_COMMAND)
	assert_eq(int(restored.get("seq", 0)), 3)
	var target: Dictionary = restored.get("payload", {}).get("target", {})
	assert_eq(int(target.get("column", -1)), 2)
	assert_eq((target.get("handles", []) as Array).size(), 2)


func test_handshake_helpers() -> void:
	var hello: Dictionary = BattleProtocol.hello("tester", "cardhash", "modehash", false)
	assert_true(BattleProtocol.is_supported(hello))
	assert_false(bool(hello.get("mods", true)))
	assert_eq(str(hello.get("card_hash", "")), "cardhash")


func test_invalid_payload_is_rejected() -> void:
	var decoded: Dictionary = BattleProtocol.decode(PackedByteArray())
	assert_false(bool(decoded.get("ok", true)))
	var bad: Dictionary = BattleProtocol.decode("not json".to_utf8_buffer())
	assert_false(bool(bad.get("ok", true)))

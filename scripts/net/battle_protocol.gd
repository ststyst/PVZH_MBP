class_name BattleProtocol
extends RefCounted
## 联机战斗消息协议（基础版）。
## 传输层只负责字节收发；具体对局状态/命令校验由 BattleServer 会话层处理。

const PROTOCOL_VERSION: int = 1
const DEFAULT_GAME_PORT: int = 45770

const MSG_HELLO: String = "hello"
const MSG_WELCOME: String = "welcome"
const MSG_MATCH_START: String = "match_start"
const MSG_COMMAND: String = "command"
const MSG_COMMAND_ACK: String = "command_ack"
const MSG_SNAPSHOT: String = "snapshot"
const MSG_EVENT: String = "event"
const MSG_ANIMATION: String = "animation"
const MSG_PHASE_TIMER: String = "phase_timer"
const MSG_MATCH_END: String = "match_end"
const MSG_ERROR: String = "error"


static func encode(message: Dictionary) -> PackedByteArray:
	return JSON.stringify(message).to_utf8_buffer()


static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return {"ok": false, "error": "空数据包"}
	var json := JSON.new()
	var parse_error: Error = json.parse(payload.get_string_from_utf8())
	if parse_error != OK:
		return {"ok": false, "error": json.get_error_message()}
	if not json.data is Dictionary:
		return {"ok": false, "error": "消息不是对象"}
	return {"ok": true, "message": json.data}


static func hello(
	account: String,
	card_hash: String,
	mode_hash: String,
	mods_allowed: bool = false,
) -> Dictionary:
	return {
		"type": MSG_HELLO,
		"protocol": PROTOCOL_VERSION,
		"account": account,
		"card_hash": card_hash,
		"mode_hash": mode_hash,
		"mods": mods_allowed,
	}


static func command(seq: int, turn: int, phase: String, command_type: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": MSG_COMMAND,
		"seq": seq,
		"turn": turn,
		"phase": phase,
		"command": command_type,
		"payload": payload,
	}


static func is_supported(message: Dictionary) -> bool:
	return int(message.get("protocol", 0)) == PROTOCOL_VERSION

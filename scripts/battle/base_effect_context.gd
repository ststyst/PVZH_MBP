class_name BaseEffectContext
extends BattleEffectContext
## 底座被放置实体时，运行底座自己的 when mounted 能力。
## self 仍为底座（可能已离场），event / mounted 指向新放置的实体。


func get_zone() -> String:
	return "base"

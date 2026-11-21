class_name EnvironmentEffectContext
extends BattleEffectContext
## 环境牌事件上下文：环境不是实体，但有所属阵营和所在列。
## when 事件中的 side 以环境拥有者为基准；查询列时以环境所在列为基准。

var environment_owner: String = "p"
var environment_column: int = 0


func _init(engine_ref: BattleEngine, owner: String, column: int) -> void:
	super(engine_ref, owner)
	environment_owner = owner
	environment_column = column
	set_base_column(column)


func get_zone() -> String:
	return "environment"

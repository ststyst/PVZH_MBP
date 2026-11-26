class_name EnvironmentEffectContext
extends BattleEffectContext
## 环境牌事件上下文：环境不是实体，但有所属阵营和所在列。
## when 事件中的 side 以环境拥有者为基准；查询列时以环境所在列为基准。

## 环境牌的拥有者阵营（与 caster_side 相同）；保留独立字段供环境上下文自身读取。
var environment_side_owner: String = "p"
var environment_column: int = 0


func _init(engine_ref: BattleEngine, owner: String, column: int) -> void:
	super(engine_ref, owner)
	environment_side_owner = owner
	environment_column = column
	set_base_column(column)


func get_zone() -> String:
	return "environment"

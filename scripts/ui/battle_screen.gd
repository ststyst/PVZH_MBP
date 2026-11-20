extends Control
## 战斗场景占位：M3 在此实现回合、法力水晶、手牌与随从区。

@onready var back_button: Button = %BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	GameState.go_to_main()

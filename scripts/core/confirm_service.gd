extends Node
## 通用弹出框服务：确认框 / 提示框。
## 调用方用 await 拿结果：
##   var yes: bool = await ConfirmService.ask_yes_no("确定删除这个存档吗？")
##   ConfirmService.show_message("开发者的话……")

## 弹出「是 / 否」确认框，等待玩家选择。返回 true = 是，false = 否/关闭。
func ask_yes_no(
	message: String,
	title: String = "确认",
	yes_text: String = "是",
	no_text: String = "否",
) -> bool:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = yes_text
	dialog.cancel_button_text = no_text
	dialog.dialog_hide_on_ok = true
	dialog.exclusive = true
	var root: Window = get_tree().root
	root.add_child(dialog)
	dialog.popup_centered()

	# 用字典保存状态：GDScript 闭包按引用捕获字典，回调里写入才能被外面看到。
	var state: Dictionary = {"result": false, "finished": false}

	var on_confirmed: Callable = func() -> void:
		state["result"] = true
		state["finished"] = true
	var on_cancelled: Callable = func() -> void:
		state["finished"] = true

	dialog.confirmed.connect(on_confirmed, CONNECT_ONE_SHOT)
	dialog.canceled.connect(on_cancelled, CONNECT_ONE_SHOT)
	# 右上角关闭 / ESC 也视为「否」
	dialog.close_requested.connect(on_cancelled, CONNECT_ONE_SHOT)

	while not bool(state["finished"]):
		if not is_instance_valid(dialog):
			return false
		await get_tree().process_frame

	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()
	return bool(state["result"])


## 弹出只有「确定」的提示框，不阻塞调用方。
func show_message(message: String, title: String = "提示") -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.exclusive = true
	var root: Window = get_tree().root
	root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free, CONNECT_ONE_SHOT)
	dialog.close_requested.connect(dialog.queue_free, CONNECT_ONE_SHOT)

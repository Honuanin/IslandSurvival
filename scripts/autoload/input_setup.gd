## 输入注册：全部走逻辑动作名，玩法脚本不直接判断物理键（GDD 10.3）。
## 使用 physical_keycode 以规避中文输入法吞键。
## @trace UI-001
extends Node


func _ready() -> void:
	_register_keys("move_up", [KEY_W])
	_register_keys("move_down", [KEY_S])
	_register_keys("move_left", [KEY_A])
	_register_keys("move_right", [KEY_D])
	_register_keys("sprint", [KEY_SHIFT])
	_register_keys("interact", [KEY_E])
	_register_keys("toggle_inventory", [KEY_TAB])
	_register_keys("toggle_build", [KEY_B])
	_register_keys("pause", [KEY_ESCAPE])
	_register_keys("rotate_build", [KEY_R])
	_register_keys("demolish", [KEY_X])
	_register_mouse("attack", MOUSE_BUTTON_LEFT)
	_register_mouse("dodge", MOUSE_BUTTON_RIGHT)
	for i in range(1, 6):
		_register_keys("hotbar_%d" % i, [KEY_0 + i])
	_register_keys("hotbar_5", [KEY_5])


func _register_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.pressed = true
		InputMap.action_add_event(action, ev)


func _register_mouse(action: String, button: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = true
	InputMap.action_add_event(action, mb)

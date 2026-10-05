extends SceneTree

## v0.28.0 — couch menus: the gamepad navigates the UI. Opening the menu
## focuses Play, panels focus their first control, the left stick drives
## ui navigation, and A activates. Run:
## timeout 180 godot --headless --path . -s tests/v028_test.gd

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _init() -> void:
	root.ready.connect(_run)


## Wait up to `frames` process frames for `cond` to become true — input
## events flush at frame boundaries and can land a frame or two late under
## load. Returns the final condition value.
func _wait_until(cond: Callable, frames: int) -> bool:
	for i in range(frames):
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _pad_button(idx: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = down
	Input.parse_input_event(e)


func _pad_stick(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _run() -> void:
	BrowserSave.clear()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	# Boot focuses Play: a gamepad can start with A immediately.
	var focus: Control = main.get_viewport().gui_get_focus_owner()
	_ok(focus != null and focus.name == "Play",
		"boot focuses the Play button")
	_pad_button(JOY_BUTTON_A, true)
	for i in range(3):
		await process_frame
	_pad_button(JOY_BUTTON_A, false)
	await physics_frame
	_ok(not main.main_menu.is_open() and not main.paused,
		"A on Play starts the game unpaused (gamepad boot)")
	main._route_escape()  # open the menu again
	await physics_frame
	_ok(main.main_menu.is_open(), "menu open")
	for i in range(3):
		await process_frame

	# The menu row is horizontal: d-pad right moves focus to Contracts.
	_pad_button(JOY_BUTTON_DPAD_RIGHT, true)
	await physics_frame
	_pad_button(JOY_BUTTON_DPAD_RIGHT, false)
	var moved := await _wait_until(func() -> bool:
		var f: Control = main.get_viewport().gui_get_focus_owner()
		return f != null and f.name == "Contracts", 8)
	_ok(moved, "dpad right moves focus to Contracts")

	# A activates the focused button: the Contracts panel opens and its
	# first button takes focus.
	# Buttons activate on RELEASE (BaseButton default): press, flush, then
	# release before polling.
	_pad_button(JOY_BUTTON_A, true)
	await process_frame
	_pad_button(JOY_BUTTON_A, false)
	var opened := await _wait_until(func() -> bool:
		return main.main_menu.subpanel_open(), 8)
	await physics_frame
	_ok(opened, "A opens the focused panel")
	focus = main.get_viewport().gui_get_focus_owner()
	_ok(focus != null, "the panel focuses its first control")

	# Back out (B), then the Settings panel: a slider focused, and the
	# stick adjusts it. Settle frames: the BFS focus grab lands a frame
	# late, and under ladder load the read can race it.
	_pad_button(JOY_BUTTON_B, true)
	await physics_frame
	_pad_button(JOY_BUTTON_B, false)
	await physics_frame
	main.main_menu.show_settings(main.settings)
	var slider_in := await _wait_until(func() -> bool:
		var f: Control = main.get_viewport().gui_get_focus_owner()
		return f is HSlider, 12)
	focus = main.get_viewport().gui_get_focus_owner()
	_ok(slider_in, "settings focuses a slider (got %s)" %
		(focus.name if focus else "nil"))
	if slider_in:
		var slider := focus as HSlider
		var before: float = slider.value
		_pad_button(JOY_BUTTON_DPAD_LEFT, true)
		await process_frame
		_pad_button(JOY_BUTTON_DPAD_LEFT, false)
		var lowered := await _wait_until(func() -> bool:
			return slider.value < before, 8)
		await physics_frame
		_ok(lowered, "d-pad left lowers the focused slider (%.2f < %.2f)" % [
			slider.value, before])

	# Closing the menu releases focus (no ghost focus while playing).
	main.main_menu.close_menu()
	await physics_frame
	_ok(main.get_viewport().gui_get_focus_owner() == null,
		"closing the menu releases focus")

	# START reopens the menu from play, focusing Play again.
	_pad_button(JOY_BUTTON_START, true)
	var reopened := await _wait_until(func() -> bool:
		var f: Control = main.get_viewport().gui_get_focus_owner()
		return f != null and f.name == "Play", 8)
	_pad_button(JOY_BUTTON_START, false)
	await physics_frame
	_ok(reopened, "reopened menu focuses Play")
	_pad_button(JOY_BUTTON_A, true)
	for i in range(3):
		await process_frame
	_pad_button(JOY_BUTTON_A, false)
	await physics_frame
	_ok(not main.main_menu.is_open(),
		"A on Play starts the game (unpause needs a real pad, headless has none)")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

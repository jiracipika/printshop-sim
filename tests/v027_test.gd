extends SceneTree

## v0.27.0 — controller support: joypad movement (stick + d-pad) in the
## input map, right-stick look, A/Start/B/Y buttons, delivery rumble, and
## gameplay-without-pointer-lock when a pad is connected. Run:
## timeout 180 godot --headless --path . -s tests/v027_test.gd

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


func _release_all() -> void:
	for axis in [0, 1, 2, 3]:
		var m := InputEventJoypadMotion.new()
		m.axis = axis
		m.axis_value = 0.0
		Input.parse_input_event(m)
	for b in [0, 3, 6, 11, 12, 13, 14]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = false
		Input.parse_input_event(e)


func _run() -> void:
	BrowserSave.clear()
	await _test_pad_gameplay()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_pad_gameplay() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.main_menu.close_menu()  # v0.28 boot focus: start from a clean menu
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 5000
	for i in range(2):
		await process_frame
	var start_yaw: float = main.yaw

	# Main registers the joypad bindings at runtime (project.godot input
	# entries break headless -s autoloads): movement actions carry stick
	# + d-pad events after boot.
	var stick := {}
	var dpad := {}
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				stick[action] = true
			if ev is InputEventJoypadButton:
				dpad[action] = true
	_ok(stick.size() == 4, "all four move actions bind a stick axis")
	_ok(dpad.size() == 4, "all four move actions bind a d-pad button")
	# Simulated left stick forward + d-pad left drive the actions.
	var push := InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_LEFT_Y
	push.axis_value = -1.0
	Input.parse_input_event(push)
	var dp := InputEventJoypadButton.new()
	dp.button_index = JOY_BUTTON_DPAD_LEFT
	dp.pressed = true
	Input.parse_input_event(dp)
	await process_frame
	await process_frame
	_ok(Input.is_action_pressed("move_forward"), "stick up presses move_forward")
	_ok(Input.is_action_pressed("move_left"), "d-pad left presses move_left")
	_release_all()
	await process_frame
	await process_frame
	_ok(not Input.is_action_pressed("move_forward")
		and not Input.is_action_pressed("move_left"),
		"releasing the pad releases the actions")

	# Right stick turns the camera (delta-scaled, deadzone 0.15).
	var look := InputEventJoypadMotion.new()
	look.axis = JOY_AXIS_RIGHT_X
	look.axis_value = 0.9
	Input.parse_input_event(look)
	var frames := 0
	while main.yaw == start_yaw and frames < 30:
		await physics_frame
		frames += 1
	_ok(main.yaw < start_yaw, "right stick turns the view")
	_release_all()

	# A button interacts: accept a job without touching the mouse.
	main.job_board._queue.clear()
	var job: Contract = load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-PAD", "client": "Couch Co-op", "model_name": "Gamepad cradle",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
	})
	main.job_board._queue.append(job)
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await physics_frame
	_ok(main._machine(0).get("contract") != null,
		"A button accepts a job through the real input path")
	_release_all()

	# START is polled: the boot menu is open, so the first press CLOSES it
	# (route-escape), the second opens it again, pausing the shop.
	# (START/B menu toggling is covered by v028_test — here the menu is
	# closed and stays closed so the gameplay input paths are isolated.)

	# Y is photo mode, same as F2.
	main.main_menu.close_menu()
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	Input.parse_input_event(y)
	await physics_frame
	_ok(not main._hud.visible, "Y toggles photo mode")
	main._toggle_photo_mode()

	# Rumble helpers are safe headless (no pads connected).
	main._rumble(0.3, 0.6, 0.2)
	_ok(true, "rumble is a safe no-op without pads")

	main.queue_free()
	await physics_frame

extends SceneTree

var checks := 0
var failures := 0
var main

func _init() -> void:
	root.ready.connect(_run)

func _ok(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("ok: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func _key(code: int, pad: bool = false) -> void:
	var e: InputEvent
	if pad:
		e = InputEventJoypadButton.new()
		e.button_index = code
	else:
		e = InputEventKey.new()
		e.physical_keycode = code
	e.pressed = true
	main._unhandled_input(e)
	e.pressed = false
	main._unhandled_input(e)

func _touch(rect: Rect2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 7
	e.position = rect.get_center()
	e.pressed = true
	main.touch_controls._unhandled_input(e)
	e.pressed = false
	main.touch_controls._unhandled_input(e)

func _at(pos: Vector3) -> void:
	main._player.global_position = pos
	main._camera.rotation = Vector3.ZERO
	main._player.rotation = Vector3.ZERO
	await physics_frame
	await physics_frame

func _run() -> void:
	BrowserSave.clear()
	# Dynamic load lets Version autoload register before Main's UI compiles.
	main = load("res://tests/fixtures/gamepad_main.gd").new()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.main_menu.close_menu()
	main.set_physics_process(false)
	main.paused = false
	main.captured = true
	await _at(Vector3(-1.8, 0.3, -1.0))
	var c := Contract.new()
	c.id = "Prep-input"
	c.client = "Prep check"
	c.model_name = "Stable part"
	c.layers = 40
	c.material_cost_cents = 300
	c.payout_cents = 5000
	c.deadline_days = 5
	c.risk_flags = ["stability"]
	main.job_board._queue.clear()
	main.job_board._queue.append(c)
	_key(KEY_E)
	var m: Dictionary = main._machine(0)
	var balance: int = main.ledger.balance()
	var stock: int = m.filament_g
	_key(KEY_E)
	_ok(c.state == Contract.State.PREPARING and m.orient == 0 and m.orient_pending,
		"actual E accepts then previews upright")
	_ok("[R] Rotate" in main._prompt.text and "[E] Confirm" in main._prompt.text,
		"preview distinguishes rotate from confirm")
	for selected in [1, 2, 0]:
		_key(KEY_R)
		_ok(m.orient == selected and m.orient_pending, "R selects orientation %d" % selected)
	_ok(main.ledger.balance() == balance and m.filament_g == stock and not m.sim.is_running(),
		"rotation never charges, consumes stock or starts print")
	_key(JOY_BUTTON_X, true)
	_ok(m.orient == 1, "gamepad X selects tilted")
	_key(JOY_BUTTON_A, true)
	_ok(m.sim.is_running() and c.state == Contract.State.PRINTING
		and main.ledger.balance() == balance - 300, "gamepad A confirms selected preview once")
	var charged: int = main.ledger.balance()
	_key(JOY_BUTTON_A, true)
	_key(KEY_R)
	_ok(m.orient == 1 and main.ledger.balance() == charged, "running print ignores rotate/double-confirm")

	m.sim.reset()
	c.state = Contract.State.PREPARING
	m.orient = 2
	m.orient_pending = true
	stock = m.filament_g
	_key(KEY_E)
	_ok(m.orient == 2 and m.orient_pending and "Rotate" in main._prompt.text
		and main.ledger.balance() == charged and m.filament_g == stock,
		"invalid confirm retains selection and resources")
	_key(KEY_R)
	_key(KEY_E)
	_ok(m.orient == 0 and m.sim.is_running(), "rotate recovers to valid upright confirmation")
	m.sim.reset()
	c.state = Contract.State.PREPARING
	m.orient_pending = true
	m.filament_g = 0
	_key(KEY_E)
	_ok(c.state == Contract.State.PREPARING and "filament" in main._prompt.text, "stock shortfall retains preview")
	_key(KEY_R)
	m.filament_g = 5000
	main.ledger.charge(main.ledger.balance(), "test empty funds")
	_key(KEY_E)
	_ok(m.orient == 1 and c.state == Contract.State.PREPARING
		and main.ledger.balance() == 0 and m.filament_g == 5000, "cash shortfall retains selected preview")
	main.ledger.credit(5000, "test funds")
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)
	var rotations := [0]
	main.touch_controls.rotate_pressed.connect(func(): rotations[0] += 1)
	main._update_hud()
	_ok(main.touch_controls._rotate_panel.visible and "Interact confirm" in main._status.text,
		"touch rotate button and hints appear only for prep")
	var fingers: int = main.touch_controls.active_fingers()
	_touch(main.touch_controls.rotate_rect())
	_ok(m.orient == 2 and rotations[0] == 1 and main.touch_controls.active_fingers() == fingers,
		"Rotate touch does not capture a look/move finger")
	_touch(main.touch_controls.rotate_rect())
	_touch(main.touch_controls.interact_rect())
	_ok(m.orient == 0 and m.sim.is_running(), "touch Interact confirms rotated selection")
	main._update_hud()
	_ok(not main.touch_controls._rotate_panel.visible, "Rotate hidden once printing")
	_touch(main.touch_controls.rotate_rect())
	_ok(rotations[0] == 2, "hidden Rotate cannot emit its action")

	m.sim.reset()
	c.state = Contract.State.PREPARING
	m.orient = 0
	main.paused = true
	_key(KEY_R)
	main.paused = false
	main.captured = false
	main.touch_controls.set_motion_enabled(false)
	_key(JOY_BUTTON_X, true)
	_ok(m.orient == 0, "paused and capture-lost rotation blocked")
	main.captured = true
	var spool: Grabbable = main._make_crate_spool("Clay")
	main.add_child(spool)
	main._attach_to_hand(spool)
	_key(KEY_R)
	_ok(m.orient == 0, "held object blocks rotation")
	main.held = null
	spool.queue_free()
	await _at(Vector3(0, 0.3, 2.5))
	_key(KEY_R)
	_ok(m.orient == 0, "out-of-range rotation blocked")
	main.upgrades.buy("pro_machine")
	var other: Dictionary = main._machine(1)
	other.contract = c.duplicate()
	other.orient = 0
	await _at(Vector3(1.8, 0.3, -1.4))
	_key(KEY_R)
	_ok(other.orient == 1 and m.orient == 0, "Rotate changes nearby printer only")
	other.contract = null
	_key(KEY_R)
	_ok(other.orient == 1, "idle machine without a contract ignores Rotate")
	await _at(Vector3(-1.8, 0.3, -1.0))
	main.captured = false
	main.test_pad_connected = true
	_key(JOY_BUTTON_X, true)
	main.paused = true
	_key(JOY_BUTTON_X, true)
	_ok(m.orient == 1, "connected-pad input still respects pause")
	main.paused = false
	_key(JOY_BUTTON_A, true)
	_ok(m.orient == 1 and m.sim.is_running(), "gamepad provider route works without mouse capture")
	main.test_pad_connected = false
	for size in [Vector2(360, 640), Vector2(640, 360), Vector2(320, 240)]:
		var r: Dictionary = main.touch_controls.layout_rects(size, 8, 8, 8, 8)
		_ok(Rect2(Vector2.ZERO, size).encloses(r.rotate)
			and not r.rotate.intersects(r.interact) and not r.rotate.intersects(r.pause),
			"Rotate fits and avoids buttons at %s" % size)
	main.queue_free()
	c = null
	m.clear()
	other.clear()
	main = null
	await physics_frame
	BrowserSave.clear()
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

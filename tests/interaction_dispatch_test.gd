extends SceneTree

## Exercise public input callbacks; direct _try_interact calls miss dispatch bugs.
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

func _press(route: String = "key") -> void:
	if route == "touch":
		main._on_touch_interact()
		return
	var event: InputEvent
	if route == "pad":
		event = InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_A
	else:
		event = InputEventKey.new()
		event.physical_keycode = KEY_E
	event.pressed = true
	main._unhandled_input(event)
	event.pressed = false
	main._unhandled_input(event)

func _at(pos: Vector3) -> void:
	main._player.global_position = pos
	main.yaw = 0.0
	main.pitch = 0.0
	main._player.rotation.y = 0.0
	main._camera.rotation.x = 0.0
	await physics_frame
	await physics_frame

func _spool() -> Grabbable:
	var spool: Grabbable = main._make_crate_spool("Sage")
	main.add_child(spool)
	main._attach_to_hand(spool)
	return spool

func _completed(id: String, walk_in: bool = false) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Nora"
	c.model_name = id
	c.payout_cents = 5000
	c.material_cost_cents = 300
	c.layers = 40
	c.deadline_days = 6
	c.walk_in = walk_in
	c.state = Contract.State.INSPECTION
	var m: Dictionary = main._machine(0)
	m["contract"] = c
	m["part"] = null
	m["scrap"] = false
	m["finished"] = false
	m["sim"].reset()
	m["sim"].state = PrintSim.State.DONE_OK
	m["sim"].layers_done = 40
	m["sim"].layers_total = 40
	m["sim"].support_need = 0.0
	m["sim"].adhesion_risk = 0.0
	m["sim"].stability_risk = 0.0
	return c

func _run() -> void:
	BrowserSave.clear()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.main_menu.close_menu()
	main.set_physics_process(false)
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)
	main.ledger.credit(30000, "dispatch test funds")
	for route in ["key", "touch", "pad"]:
		await _at(Vector3(-1.8, 0.3, -1.0))
		var spool := _spool()
		var grams: int = main._machine(0).filament_g
		var balance: int = main.ledger.balance()
		_ok("Load spool" in main._grab_prompt_line(), route + " offers loading")
		_press(route)
		_ok(main.held == null and spool.is_queued_for_deletion()
			and main._machine(0).filament_g == grams + 1500
			and main._machine(0).color == "Sage"
			and main.ledger.balance() == balance, route + " loads once without a purchase fee")
		await physics_frame
	var held_spool := _spool()
	await _at(Vector3(1.8, 0.3, -1.4))
	_press()
	_ok(main.held == held_spool and main._machine(1).filament_g == 0
		and "locked" in main._prompt.text, "locked printer retains spool")
	main.paused = true
	await _at(Vector3(-1.8, 0.3, -1.0))
	_press()
	_ok(main.held == held_spool, "paused E cannot load")
	main.paused = false
	main.captured = false
	main.touch_controls.set_motion_enabled(false)
	_press("touch")
	_ok(main.held == held_spool, "inactive touch cannot load")
	main.captured = true
	main.touch_controls.set_motion_enabled(true)
	await _at(Vector3(0, 0.3, 2.1))
	_press()
	_ok(main.held == null, "ordinary spool placement remains available")
	held_spool.queue_free()
	await physics_frame
	await _at(Vector3(-3.1, 0.3, 1.85))
	held_spool = _spool()
	_press()
	_ok(main.held == held_spool and "No room" in main._prompt.text, "invalid placement keeps object held")
	main.held = null
	held_spool.queue_free()
	await physics_frame

	var c := _completed("Dispatch board")
	await _at(Vector3(-1.8, 0.3, -1.0))
	_press()
	_ok(main._is_held_part(), "keyboard collects completed part")
	var original: Grabbable = main.held
	await _at(Vector3(2.5, 0.3, -2.1))
	_ok("Showcase" in main._grab_prompt_line(), "shelf prompt names actual action")
	_press("pad")
	_press("pad")
	_ok(main._shelf_models == [c.model_name] and main.held == original, "gamepad showcases copy once and retains original")
	await _at(main._finishing.position + Vector3(0, 0.3, 0.8))
	_ok("smooth" in main._grab_prompt_line(), "finishing prompt names actual action")
	_press("touch")
	_ok(main._machine(0).finished and main.held == original, "touch finishes held part")
	await _at(Vector3(2.0, 0.3, 0.9))
	_ok("Pack & deliver" in main._grab_prompt_line(), "board part still offers packing")
	_press()
	_ok(main.held == null and c.state == Contract.State.DELIVERED, "keyboard delivers board part")
	await physics_frame

	c = _completed("Dispatch walk-in", true)
	await _at(Vector3(-1.8, 0.3, -1.0))
	_press()
	_ok("counter" in main._prompt.text and "Nora" in main._grab_prompt_line(), "walk-in collection/carry hints name counter and client")
	await _at(Vector3(2.0, 0.3, 0.9))
	var balance: int = main.ledger.balance()
	original = main.held
	_ok("Pack & deliver" not in main._grab_prompt_line(), "walk-in never advertises packing")
	_press()
	_ok(main.held == original and main.ledger.balance() == balance, "packing refuses walk-in without consumption or payment")
	await _at(Vector3(-1.9, 0.3, 1.7))
	_ok("Nora" in main._grab_prompt_line(), "counter prompt names client")
	_press("touch")
	_ok(main.held == null and c.state == Contract.State.DELIVERED and main.ledger.balance() > balance, "touch hands walk-in to counter")
	balance = main.ledger.balance()
	_press("touch")
	_ok(main.ledger.balance() == balance, "counter cannot pay twice")

	c = _completed("Dropped part")
	main._collect_on(0) # fixture only: action under test below is real E
	original = main.held
	await _at(Vector3(-1.5, 0.3, 0))
	_press()
	_ok(main.held == null and is_instance_valid(original) and not original.is_queued_for_deletion(), "input leaves a live part on floor")
	main.upgrades.buy("pro_machine")
	await _at(Vector3(1.8, 0.3, -1.4))
	_press()
	_ok(main._machine(1).contract != null and main._machine(0).part == original, "dropped part does not block another printer")
	await _at(Vector3(-1.8, 0.3, -1.0))
	_press()
	_ok(main.held == null and main._machine(0).part == original, "original printer does not duplicate part")
	await _at(Vector3(-1.5, 0.3, 0))
	main._camera.look_at(original.global_position)
	await physics_frame
	_press()
	_ok(main.held == original, "aimed empty-hand grab retains precedence")
	main._machine(0).scrap = true
	c.walk_in = true
	await _at(Vector3(2.0, 0.3, 0.9))
	_ok("Scrap" in main._grab_prompt_line(), "walk-in F scrap still offers scrap")
	_press()
	_ok(c.state == Contract.State.FAILED and main.held == null, "scrap exception preserved")
	main.queue_free()
	c = null
	main = null
	await physics_frame
	BrowserSave.clear()
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

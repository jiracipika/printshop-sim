extends SceneTree

## v0.6.0 — the spool economy: crate purchase, loading, per-machine filament,
## consumption, refusal, persistence, milestones. Run:
##   timeout 90 godot --headless --path . -s tests/spool_test.gd

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


func _run() -> void:
	BrowserSave.clear()
	await _test_crate_and_load()
	await _test_consumption_and_persistence()
	await _test_milestones()
	_finish(1 if failures > 0 else 0)


func _test_crate_and_load() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)

	# Boot state: printer 1 ships loaded, printer 2 empty.
	_ok(int(main._machine(0).get("filament_g")) == 1500,
		"printer 1 opens with a 1500 g spool")
	_ok(int(main._machine(1).get("filament_g")) == 0, "printer 2 opens empty")

	# Buy at the crate: money out, spool in hand.
	var bal0: int = ledger.balance()
	main._player.global_position = Vector3(-3.0, 0.3, 2.1)  # at the crate
	main._try_interact()
	_ok(main.held != null and main._is_held_spool(), "crate puts a spool in your hands")
	_ok(ledger.balance() == bal0 - 1200, "a spool costs $12.00")
	main._try_interact()  # second press at the crate with full hands must not buy twice
	_ok(_count_spool_txs(ledger) == 1 and ledger.balance() == bal0 - 1200,
		"full hands never double-buy at the crate")

	# Load into printer 1: grams in, hands free.
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_ok(main.held == null, "loading empties your hands")
	_ok(int(main._machine(0).get("filament_g")) == 3000,
		"loading adds 1500 g to the machine")

	# Locked printer 2 refuses the load.
	main._player.global_position = Vector3(-3.0, 0.3, 2.1)  # back at the crate
	main._try_interact()
	_ok(main.held != null and main._is_held_spool(), "bought a second spool")
	main._player.global_position = Vector3(1.8, 0.3, -1.4)  # at printer 2
	main._try_interact()
	_ok(main.held != null and int(main._machine(1).get("filament_g")) == 0,
		"locked printer 2 refuses the load")
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _count_spool_txs(ledger: Ledger) -> int:
	var n := 0
	for t in ledger.transactions:
		if t["reason"] == "spool":
			n += 1
	return n


func _test_consumption_and_persistence() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger_credit(main, 30000)
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)

	# Drain the machine to a known small amount, then demand a big job.
	main._machine(0)["filament_g"] = 400
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()  # accept
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null, "job accepted while filament is short")
	if c == null:
		_finish(1)
		return
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	var est: int = int(PrepSystem.evaluate(c, "upright").estimated_material_g)
	main._prep_on(0)
	_ok(not main._machine(0).get("sim").is_running()
		and c.state == Contract.State.PREPARING,
		"confirm without enough filament is refused, job stays PREPARING")
	_ok("filament" in str(main._prompt.text),
		"HUD explains the filament shortfall (%d g needed)" % est)

	# Load, then the same confirm goes through and consumes the estimate.
	main._machine(0)["filament_g"] = 5000
	var bal0: int = ledger.balance()
	main._prep_on(0)
	_ok(main._machine(0).get("sim").is_running(), "confirm proceeds once filament is loaded")
	_ok(int(main._machine(0).get("filament_g")) == 5000 - est,
		"print consumed exactly the estimate (%d g)" % est)
	_ok(ledger.balance() == bal0 - c.material_cost_cents,
		"printing charges the contract's material fee on top of grams")
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._try_interact()  # collect
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()  # deliver
	_ok(main._machine(0).get("contract") == null, "delivery flow intact under the spool economy")

	# Persistence: filament grams survive save -> fresh Main.
	main._machine(0)["filament_g"] = 777
	main._machine(1)["filament_g"] = 333
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(not SaveSystem.validate(payload).is_empty(), "payload with filament validates")
	_ok(int(payload.filament[0]) == 777 and int(payload.filament[1]) == 333,
		"save carries per-machine filament")
	var bad: Dictionary = payload.duplicate(true)
	bad.filament[0] = -5
	_ok(SaveSystem.validate(bad).is_empty(), "negative grams reject the payload")

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(int(main2._machine(0).get("filament_g")) == 777
		and int(main2._machine(1).get("filament_g")) == 333,
		"fresh Main restores per-machine filament")
	main2.queue_free()
	await physics_frame
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func ledger_credit(main, cents: int) -> void:
	main.ledger.credit(cents, "test funds")


func _test_milestones() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Fresh shop: first-sale milestone undone with a hint.
	main.main_menu.open_menu()
	main._on_menu_stats()
	var body: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok("MILESTONES" in body.text and "First sale — deliver your first part" in body.text,
		"undone milestones show hints")
	_ok("Week one" in body.text, "milestone list renders")

	# Hit a couple of milestones and re-render.
	main.stats.delivered = 1
	main.stats.earned_cents = 50000
	main._on_menu_stats()
	var body2: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok("✓  First sale" in body2.text and "✓  High earner" in body2.text,
		"completed milestones flip to done")
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

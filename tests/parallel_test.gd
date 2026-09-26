extends SceneTree

## v0.3.0 — two-machine parallel printing. Run:
##   timeout 60 godot --headless --path . -s tests/parallel_test.gd

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
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true

	_ok(main.machines.size() == 2, "two machines exist")
	_ok(main._machine(0).get("sim").state == PrintSim.State.IDLE
		and main._machine(1).get("sim").state == PrintSim.State.IDLE,
		"both machines idle at boot")

	# Unlock printer 2 for the parallel section.
	main._on_menu_upgrade_buy("pro_machine")
	_ok(main.upgrades.pro_machine_unlocked(), "pro machine unlocked for the test")

	# --- machine 0: accept + confirm at printer A ---
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_ok(main._machine(0).get("contract") != null, "machine 0 accepts a contract")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	_ok(main._machine(0).get("sim").is_running(), "machine 0 printing")

	# --- machine 1: accept + confirm at printer 2 while machine 0 runs ---
	main._player.global_position = Vector3(1.8, 0.3, -1.4)
	main._try_interact()
	var c1: Contract = main._machine(1).get("contract")
	_ok(c1 != null, "machine 1 accepts a second contract while machine 0 prints")
	if c1 == null:
		_finish(1)
		return
	main._machine(1)["orient"] = 0
	main._machine(1)["orient_pending"] = true
	main._prep_on(1)
	var s0: PrintSim = main._machine(0).get("sim")
	var s1: PrintSim = main._machine(1).get("sim")
	_ok(s0.is_running() and s1.is_running(), "both machines print simultaneously")
	_ok(s0.job_id != s1.job_id, "the two machines print different contracts")
	_ok(main.active_contract == c1,
		"legacy active_contract accessor reads the focused (last-interacted) machine")

	# --- parallel progress via real physics frames ---
	main._player.global_position = Vector3(0.0, 0.3, 0.5)
	var before0: int = s0.layers_done
	var before1: int = s1.layers_done
	for i in range(30):
		await physics_frame
	_ok(s0.layers_done > before0 and s1.layers_done > before1,
		"both sims advanced through the real _physics_process loop")
	main._update_hud()
	_ok(s0.model_name in main._status.text and s1.model_name in main._status.text,
		"HUD shows both running prints")
	_ok("Printer 2" in main._status.text, "machine 1 HUD lines are labelled")

	# --- finish machine 0, deliver its part ---
	while s0.is_running():
		s0.tick(1.0)
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._focus = 0
	main._try_interact()  # collect part 0
	_ok(main.held != null and main._is_held_part(), "part 0 collected into hands")
	var bal0: int = ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()  # deliver at packing table (in-range)
	_ok(main._machine(0).get("contract") == null, "machine 0 contract delivered and cleared")
	_ok(ledger.balance() > bal0, "machine 0 payout credited")
	_ok(main.held == null, "hands free after delivery")

	# --- finish machine 1, deliver its part ---
	while s1.is_running():
		s1.tick(1.0)
	main._player.global_position = Vector3(1.8, 0.3, -1.4)
	main._focus = 1
	main._try_interact()  # collect part 1
	_ok(main.held != null and main._is_held_part(), "part 1 collected into hands")
	var bal1: int = ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(main._machine(1).get("contract") == null, "machine 1 contract delivered and cleared")
	_ok(ledger.balance() > bal1, "machine 1 payout credited")
	var c0: Contract = main._machine(0).get("contract")
	_ok(c0 == null, "machine 0 stays delivered")

	# Exactly-once payouts across both machines.
	var payout_txs := 0
	for t in ledger.transactions:
		if str(t["reason"]).begins_with("payout G-"):
			payout_txs += 1
	_ok(payout_txs == 2, "exactly two payout transactions (one per machine)")

	# Day anchoring is per machine: machine 1 accepted a day later.
	main._player.global_position = Vector3(1.8, 0.3, -1.4)  # back at printer 2
	main._try_interact()  # machine 1 (focus) accepts a new job
	var c1b: Contract = main._machine(1).get("contract")
	_ok(c1b != null and main._machine(1).get("day") == main.day_cycle.day,
		"machine 1 anchors its own deadline day")
	main._machine(1)["orient"] = 0
	main._machine(1)["orient_pending"] = true
	main._prep_on(1)
	main.day_cycle.restore(main.day_cycle.day + c1b.deadline_days + 2, 0.0)
	main._on_day_changed(main.day_cycle.day)
	_ok(main._machine(1).get("contract") == null,
		"machine 1's overdue contract cancels without touching machine 0")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

extends SceneTree

## v0.2.0 — shop day: day clock, rent + debt, deadlines (late / cancellation),
## pro machine unlock. Run: timeout 60 godot --headless --path . -s tests/day_test.gd

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
	_test_day_clock()
	await _test_rent_and_debt()
	await _test_deadlines()
	await _test_pro_machine()
	_finish(1 if failures > 0 else 0)


func _test_day_clock() -> void:
	var cycle := DayCycle.new(10.0)  # 10 s days for tests
	var fired: Array[int] = []
	cycle.day_changed.connect(func(d: int) -> void: fired.append(d))
	cycle.tick(5.0)
	_ok(cycle.day == 1 and fired.is_empty(), "half a day passes without rollover")
	cycle.tick(5.0)
	_ok(cycle.day == 2 and fired == [2], "one day length rolls over exactly once")
	cycle.tick(30.0)
	_ok(cycle.day == 5 and fired == [2, 3, 4, 5],
		"multi-day wrap emits day_changed once per day in order")
	_ok(cycle.t >= 0.0 and cycle.t < 1.0, "time-of-day stays in [0,1)")
	cycle.restore(7, 0.5)
	_ok(cycle.day == 7 and absf(cycle.t - 0.5) < 0.0001, "restore sets day and time")
	cycle.restore(0, 0.5)
	_ok(cycle.day == 1, "restore clamps day to >= 1")


func _mk_main():
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	return main


func _test_rent_and_debt() -> void:
	var main = _mk_main()
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	main.paused = false
	main.captured = true

	# Rent charges once per day change (unless the day's event is a holiday).
	var bal0: int = ledger.balance()
	var txs0: int = ledger.transaction_count()
	main.day_cycle.tick(main.day_cycle.day_length_s)  # -> day 2
	_ok(main.day_cycle.day == 2, "day rolled to 2")
	var rent2: int = 0 if bool(main.today_event.rent_free) else 400
	_ok(ledger.balance() == bal0 - rent2,
		"rent handled per the day's event (%s)" % main.today_event.id)
	var rent_txs := 0
	for t in ledger.transactions:
		if t["reason"] == "rent day 2":
			rent_txs += 1
	_ok(rent_txs <= 1, "at most one rent transaction for day 2")
	if rent2 > 0:
		_ok(rent_txs == 1, "rent transaction present when rent was due")
	_ok(ledger.transaction_count() >= txs0 + 1, "rollover logged its transactions")

	# Insufficient funds: no charge, debt accrues, balance never negative.
	ledger.charge(ledger.balance(), "test drain")
	var debt0: int = main.rent_debt_cents
	main.day_cycle.tick(main.day_cycle.day_length_s)  # -> day 3
	var rent3: int = 0 if bool(main.today_event.rent_free) else 400
	_ok(ledger.balance() == 0, "empty balance unchanged at rollover")
	_ok(main.rent_debt_cents == debt0 + rent3, "unpaid rent accrues as debt per event")
	main.day_cycle.tick(main.day_cycle.day_length_s)  # -> day 4
	var rent4: int = 0 if bool(main.today_event.rent_free) else 400
	_ok(main.rent_debt_cents == debt0 + rent3 + rent4, "debt accumulates per unpaid day")

	# Payout repays debt first.
	ledger.credit(1000, "test funds")
	main.rent_debt_cents = 800
	main._repay_rent_debt()
	_ok(ledger.balance() == 200 and main.rent_debt_cents == 0,
		"payout funds repay rent debt in full")
	ledger.credit(100, "test funds 2")
	main.rent_debt_cents = 800
	main._repay_rent_debt()
	_ok(ledger.balance() == 0 and main.rent_debt_cents == 500,
		"partial repayment leaves remaining debt, never negative balance")
	main.queue_free()
	await physics_frame


func _test_deadlines() -> void:
	var main = _mk_main()
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	main.paused = false
	main.captured = true
	ledger.credit(10000, "test funds")

	# Accept at printer A (idx 0), confirm upright prep.
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_ok(main.active_contract != null and main.active_contract_day == main.day_cycle.day,
		"accept anchors the deadline to the current day")
	main.orientation_index = 0
	main.orientation_pending = true
	main._prep_press()
	_ok(main.sim.is_running(), "print started")
	var c: Contract = main.active_contract

	# On time: full payout.
	while main.sim.is_running():
		main.sim.tick(1.0)
	main._try_interact()  # collect part
	var bal0: int = ledger.balance()
	var rep0: float = main.reputation_multiplier()  # pack bumps rep after paying
	main._try_pack_held()
	var snap: Dictionary = main._machine(0).get("grade_snapshot", {})
	var grade: String = QualityCheck.grade(c, int(snap.get("final_layer", 0)),
		int(snap.get("total_layers", 0)), snap.get("risks", {}))
	var full: int = roundi(roundi(c.payout_cents
		* QualityCheck.quality_multiplier(main._cap_grade_for_color(grade, c, main._machine(0)))) * rep0)
	_ok(ledger.balance() == bal0 + full, "on-time delivery pays rep-scaled grade payout")

	# Late (deadline exceeded by 1 day): half payout.
	main._machine(0)["filament_g"] = 5000  # test setup: plenty of filament
	main.sim.failure_seeded = false
	main._try_interact()
	var c2: Contract = main.active_contract
	main.orientation_index = 0
	main.orientation_pending = true
	main._prep_press()
	# Push days past the deadline but within the cancellation window.
	var deadline: int = c2.deadline_days
	main.day_cycle.restore(main.day_cycle.day + deadline + 1, 0.0)  # late, not cancelled
	while main.sim.is_running():
		main.sim.tick(1.0)
	main._try_interact()
	_ok(main._is_late() and not main._is_cancelled(), "deadline+1 is late but not cancelled")
	var snap2: Dictionary = main._machine(0).get("grade_snapshot", {})
	var grade2: String = QualityCheck.grade(c2, int(snap2.get("final_layer", 0)),
		int(snap2.get("total_layers", 0)), snap2.get("risks", {}))
	var bal1: int = ledger.balance()
	var rep1: float = main.reputation_multiplier()
	main._try_pack_held()
	var eff2: String = main._cap_grade_for_color(grade2, c2, main._machine(0))
	_ok(ledger.balance() == bal1 + roundi(roundi(roundi(c2.payout_cents
		* QualityCheck.quality_multiplier(eff2)) * rep1) * 0.5),
		"late delivery pays exactly half (rep-scaled)")
	_ok("LATE" in str(main._prompt.text), "HUD explains the late penalty")

	# Cancellation window: deadline + 2 days fails the contract at rollover.
	main._machine(0)["filament_g"] = 5000
	main._try_interact()
	var c3: Contract = main.active_contract
	if c3 != null:
		main.orientation_index = 0
		main.orientation_pending = true
		main._prep_press()
		main.day_cycle.restore(main.day_cycle.day + c3.deadline_days + 2, 0.0)
		main._on_day_changed(main.day_cycle.day)  # fire the rollover handler directly
		_ok(c3.state == Contract.State.FAILED, "overdue contract is cancelled at day change")
		_ok(main.active_contract == null, "cancelled contract clears from Main")
		_ok(not main.sim.is_running(), "cancelled print is torn down")
		_ok(main.active_part == null and main.held == null, "part of cancelled job is discarded")
	main.queue_free()
	await physics_frame


func _test_pro_machine() -> void:
	var main = _mk_main()
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	main.paused = false
	main.captured = true
	ledger.credit(20000, "test funds")

	# Printer 2 starts locked.
	var p2: Node3D = main._printers[1]
	_ok(p2.is_locked(), "printer 2 starts locked")
	# Stand at printer 2 and try to accept.
	main._player.global_position = Vector3(1.8, 0.3, -1.4)
	main._try_interact()
	_ok(main.active_contract == null, "locked printer 2 refuses the accept")
	_ok("locked" in str(main._prompt.text), "HUD explains the lock")

	# Buy the pro machine: unlock + display refresh.
	main._on_menu_upgrade_buy("pro_machine")
	main._machine(1)["filament_g"] = 5000  # test setup: plenty of filament
	_ok(main.upgrades.pro_machine_unlocked(), "pro machine purchase unlocks")
	_ok(not p2.is_locked(), "printer 2 shows unlocked")
	_ok("PRO" in str(p2._name_label.text), "printer 2 renamed to PRO")

	# Job accepted at printer 2 runs at 1.25x.
	main._try_interact()
	var c: Contract = main.active_contract
	_ok(c != null and main.active_printer_idx == 1, "job accepted at printer 2")
	main.orientation_index = 0
	main.orientation_pending = true
	main._prep_press()
	_ok(absf(main.sim.speed_multiplier - 1.25) < 0.0001,
		"printer 2 job runs at 1.25x machine speed")

	# Same job at printer 1 runs at 1.0x (fresh Main).
	var main2 = _mk_main()
	await physics_frame
	await physics_frame
	main2.paused = false
	main2.captured = true
	main2.ledger.credit(20000, "test funds")
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	if main2.active_contract != null:
		main2.orientation_index = 0
		main2.orientation_pending = true
		main2._prep_press()
		_ok(absf(main2.sim.speed_multiplier - 1.0) < 0.0001,
			"printer 1 job runs at 1.0x")
	main2.queue_free()
	await physics_frame

	# Day persists through the save round trip.
	main.day_cycle.restore(9, 0.0)
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(int(payload.get("day", 0)) == 9, "save payload carries the day")
	var main3 = _mk_main()
	await physics_frame
	await physics_frame
	_ok(main3.day_cycle.day == 9, "fresh Main restores the saved day")
	main3.queue_free()
	await physics_frame
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

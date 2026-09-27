extends SceneTree

const BrowserSave = preload("res://scripts/BrowserSave.gd")

## Economy loop test (task 09): contracts + money wired into the real Main scene.
## Run: timeout 60 godot --headless --path . -s tests/economy_test.gd
## RED before Main/JobBoard economy wiring; GREEN after.

var checks := 0
var failures := 0
var main = null


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _prop(node: Node, prop: String):
	return node.get(prop) if node != null else null


func _fmt(cents: int) -> String:
	return "%d.%02d" % [cents / 100, absi(cents) % 100]


func _drive(max_steps := 60000) -> void:
	var steps := 0
	while main.sim.state == PrintSim.State.RUNNING and steps < max_steps:
		main.sim.tick(1.0 / 60.0)
		steps += 1


func _stand_at_printer_a() -> void:
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main.yaw = 0.0
	main._player.rotation.y = main.yaw


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_ok(packed != null, "Main.tscn loads")
	if packed == null:
		_finish(1)
		return
	BrowserSave.clear()  # fresh-boot economy assertions need no persisted save
	main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# --- boot: opening balance ---
	var ledger: Ledger = _prop(main, "ledger")
	_ok(ledger != null, "Main exposes a Ledger")
	_ok(_prop(main, "active_contract") == null, "no active contract at boot")
	_ok(ledger != null and ledger.balance() == 2500, "opening balance is 2500 cents")
	if ledger != null:
		var opening_ok := false
		for t in ledger.transactions:
			if t["reason"] == "opening funds" and t["delta_cents"] == 2500:
				opening_ok = true
		_ok(opening_ok, "opening funds logged once")
	main._update_hud()
	_ok("Balance: $25.00" in main._status.text, "HUD shows opening balance $25.00")

	_stand_at_printer_a()
	main.paused = false
	main.captured = true  # desktop pointer-lock intent (headless stand-in)

	# --- 1. accept at printer: OFFERED->ACCEPTED->PREPARING, orientation prep ---
	var board_before: int = main.job_board.get_available_count()
	main._try_interact()
	var contract: Contract = _prop(main, "active_contract")
	_ok(contract is Contract, "E at printer accepts a Contract")
	if contract == null:
		_finish(1)
		return
	_ok(contract.state == Contract.State.PREPARING,
		"accept parks contract at PREPARING for orientation prep")
	_ok(not main.sim.is_running(), "print does not start before orientation confirm")
	_ok(ledger.balance() == 2500, "no money spent before orientation confirm")
	_ok(int(main._machine(0).get("filament_g")) == 1500,
		"printer ships with a 1500 g spool, untouched before confirm")
	main._update_hud()
	_ok("Prep" in main._status.text, "HUD shows prep prompt while PREPARING")
	main._try_interact()  # first prep press: preview (index advances to tilted)
	_ok(main.orientation_pending and "tilted" in str(main._prompt.text),
		"E previews next orientation with estimate")
	_ok(contract.state == Contract.State.PREPARING and not main.sim.is_running(),
		"preview does not start the print")
	main._try_interact()  # second prep press: confirm tilted
	_ok(contract.state == Contract.State.PRINTING,
		"confirm drives PREPARING->PRINTING via legal path")
	_ok(main.sim.is_running() and main.sim.job_id == contract.id,
		"sim printing the accepted contract id")
	var tilted_eval: Dictionary = PrepSystem.evaluate(contract, "tilted")
	_ok(absf(main.sim.support_need - float(tilted_eval.support_need)) < 0.001 \
		and absf(main.sim.adhesion_risk - float(tilted_eval.adhesion_risk)) < 0.001,
		"prep risks written into sim (tilted, matches PrepSystem)")
	var tilted_est: int = int(PrepSystem.evaluate(contract, "tilted").estimated_material_g)
	_ok(int(main._machine(0).get("filament_g")) == 1500 - tilted_est,
		"confirm consumes the prep estimate from the loaded spool (%d g)" % tilted_est)
	_ok(ledger.balance() == 2500, "filament, not money, is the material cost")
	main._update_hud()
	_ok(contract.model_name in main._status.text
		and Contract.state_name(contract.state) in main._status.text,
		"HUD active-contract line shows model and state")
	_ok("Filament" in main._status.text, "HUD shows the filament line")

	# --- 2. cannot accept a second contract while one is active ---
	var bal_running: int = ledger.balance()
	main._try_interact()
	_ok(_prop(main, "active_contract") == contract
		and ledger.balance() == bal_running
		and main.job_board.get_available_count() == board_before,
		"second accept rejected while contract active (board topped back up)")

	# --- 3. DONE_OK parks at INSPECTION, no payout yet ---
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_OK, "sim reached DONE_OK")
	_ok(contract.state == Contract.State.INSPECTION, "DONE_OK parks contract at INSPECTION")
	_ok(not ledger.has_paid(contract.id) and ledger.balance() == bal_running,
		"no payout before collect")
	main._update_hud()
	_ok("collect the part" in main._status.text, "HUD prompts collect while parked at INSPECTION")

	# --- 4. collect the physical part, deliver at the packing table ---
	main.paused = false
	var bal_before_payout: int = ledger.balance()
	var rep_at_pack: float = main.reputation_multiplier()  # delivery bumps rep after paying
	main._try_interact()
	_ok(main.held != null and main._is_held_part(),
		"collect attaches the printed part to hands")
	_ok(str(main.held.get_meta("part_contract", "")) == contract.id,
		"part carries the contract id")
	_ok(_prop(main, "active_contract") == contract
		and contract.state == Contract.State.INSPECTION,
		"contract stays INSPECTION while the part is carried")
	_ok(not ledger.has_paid(contract.id), "no payout on collect alone")
	_ok(main._try_pack_held(), "packing table packs the carried part")
	var grade_expected: String = QualityCheck.grade(contract, main.sim.layers_done,
		main.sim.layers_total, {
			"support_need": main.sim.support_need,
			"adhesion_risk": main.sim.adhesion_risk,
			"stability_risk": main.sim.stability_risk,
		})
	# Final payout: grade scale first, then reputation (rep 3.0 -> x1.04),
	# matching Main's rounding order exactly.
	var eff_grade: String = main._cap_grade_for_color(grade_expected, contract, main._machine(0))
	var expected_payout: int = roundi(roundi(contract.payout_cents
		* QualityCheck.quality_multiplier(eff_grade)) * rep_at_pack)
	_ok(grade_expected in ["A", "B", "C"], "completed print grades deliverable (%s)" % grade_expected)
	_ok(_prop(main, "active_contract") == null, "delivery clears active contract")
	_ok(contract.state == Contract.State.DELIVERED, "delivery walks INSPECTION->PACKED->DELIVERED")
	print("DBG expected=", expected_payout, " grade=", grade_expected, " rep=", main.reputation_multiplier(),
		" bal_before=", bal_before_payout, " bal_now=", ledger.balance())
	_ok(ledger.balance() == bal_before_payout + expected_payout,
		"grade-scaled payout credited exactly once to balance")
	_ok(ledger.has_paid(contract.id), "ledger marks contract paid")
	var payout_txs := 0
	for t in ledger.transactions:
		if t["delta_cents"] == expected_payout and t["reason"] == "payout %s" % contract.id:
			payout_txs += 1
	_ok(payout_txs == 1, "exactly one payout transaction for the contract")
	_ok(not ledger.pay_once(contract.id, contract.payout_cents, "payout %s" % contract.id),
		"pay_once idempotent on repeated attempt for same id")
	_ok(not main._try_pack_held(), "repeated pack attempt refused (nothing held)")
	_ok(main.active_part == null and main.held == null,
		"part consumed by delivery (double delivery impossible)")
	_ok(ledger.balance() == bal_before_payout + expected_payout,
		"balance unchanged after repeated collect/pack attempts")
	main._update_hud()
	_ok("Balance: $%s" % _fmt(bal_before_payout + expected_payout) in main._status.text,
		"HUD shows post-payout balance")

	# --- 5. failure path: FAILED via legal path, clear required, zero payout ---
	main._machine(0)["filament_g"] = 5000  # test setup: plenty of filament
	main.sim.failure_seeded = true
	main._try_interact()  # accept next fixture job -> PREPARING
	_ok(_prop(main, "active_contract") != null
		and _prop(main, "active_contract").state == Contract.State.PREPARING,
		"second contract accepted to PREPARING")
	main._try_interact()  # preview
	main._try_interact()  # confirm
	var contract2: Contract = _prop(main, "active_contract")
	_ok(contract2 is Contract and contract2.state == Contract.State.PRINTING,
		"second contract confirmed to PRINTING")
	if contract2 == null:
		_finish(1)
		return
	var bal2: int = ledger.balance()
	_ok(bal2 == bal_before_payout + expected_payout,
		"confirm spends filament, not money")
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_FAIL, "seeded failure reaches DONE_FAIL")
	_ok(_prop(main, "active_contract") == null, "failed contract cleared from Main")
	_ok(contract2.state == Contract.State.FAILED, "failed contract state is FAILED")
	_ok(ledger.balance() == bal2, "no payout on failure path")
	main._update_hud()
	_ok("FAIL" in main._status.text, "HUD explains the failure")
	main.sim.failure_seeded = false
	main.paused = false
	main._try_interact()  # clear the spoiled print off the bed
	_ok(main.sim.state == PrintSim.State.IDLE, "failed print must be cleared before the next job")

	# --- 6. no funds, no spools: the crate refuses, nothing prints ---
	ledger.charge(ledger.balance(), "test drain")  # keeps tx-replay invariant
	main._player.global_position = Vector3(-2.95, 0.3, 0.3)  # at the spool crate
	main.paused = false
	var hands_before: int = 0 if main.held == null else 1
	main._try_interact()
	_ok(main.held == null and hands_before == 0, "crate refuses when broke: no spool in hand")
	_ok("not enough funds" in str(main._prompt.text), "HUD explains the spool price")
	_ok(_prop(main, "active_contract") == null and not main.sim.is_running(),
		"nothing started while broke")

	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

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

	# --- 1. accept at printer: OFFERED->ACCEPTED->PREPARING->PRINTING ---
	var board_before: int = main.job_board.get_available_count()
	main._try_interact()
	var contract: Contract = _prop(main, "active_contract")
	_ok(contract is Contract, "E at printer accepts a Contract")
	if contract == null:
		_finish(1)
		return
	_ok(contract.state == Contract.State.PRINTING,
		"accept drives contract to PRINTING via legal path")
	_ok(Contract.can_transition(Contract.State.ACCEPTED, Contract.State.PREPARING)
		and Contract.can_transition(Contract.State.PREPARING, Contract.State.PRINTING),
		"accept-path transitions ACCEPTED->PREPARING->PRINTING are legal")
	_ok(main.sim.is_running() and main.sim.job_id == contract.id,
		"sim printing the accepted contract id")
	_ok(ledger.balance() == 2500 - contract.material_cost_cents,
		"material_cost_cents charged at print start")
	var charged := false
	for t in ledger.transactions:
		if contract.id in str(t["reason"]) and t["delta_cents"] == -contract.material_cost_cents:
			charged = true
	_ok(charged, "material charge logged in transactions with contract id")
	main._update_hud()
	_ok(contract.model_name in main._status.text
		and Contract.state_name(contract.state) in main._status.text,
		"HUD active-contract line shows model and state")
	_ok("Balance: $%s" % _fmt(2500 - contract.material_cost_cents) in main._status.text,
		"HUD balance reflects material charge")

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
	_ok("[E] Collect" in main._status.text, "HUD prompts collect while parked at INSPECTION")

	# --- 4. collect: PACKED->DELIVERED, exactly-once payout ---
	main.paused = false
	var bal_before_payout: int = ledger.balance()
	main._try_interact()
	_ok(_prop(main, "active_contract") == null, "collect clears active contract")
	_ok(contract.state == Contract.State.DELIVERED, "collect walks INSPECTION->PACKED->DELIVERED")
	_ok(ledger.balance() == bal_before_payout + contract.payout_cents,
		"payout credited exactly once to balance")
	_ok(ledger.has_paid(contract.id), "ledger marks contract paid")
	var payout_txs := 0
	for t in ledger.transactions:
		if t["delta_cents"] == contract.payout_cents and t["reason"] == "payout %s" % contract.id:
			payout_txs += 1
	_ok(payout_txs == 1, "exactly one payout transaction for the contract")
	_ok(not ledger.pay_once(contract.id, contract.payout_cents, "payout %s" % contract.id),
		"pay_once idempotent on repeated attempt for same id")
	var repeat_paid := true
	if main.has_method("_pay_payout"):
		repeat_paid = main._pay_payout(contract)
	else:
		repeat_paid = false
	_ok(not repeat_paid, "repeated collect does not double-pay")
	_ok(ledger.balance() == bal_before_payout + contract.payout_cents,
		"balance unchanged after repeated collect attempt")
	main._update_hud()
	_ok("Balance: $%s" % _fmt(bal_before_payout + contract.payout_cents) in main._status.text,
		"HUD shows post-payout balance")

	# --- 5. failure path: FAILED via legal path, zero payout ---
	main.sim.failure_seeded = true
	main._try_interact()  # accept next fixture job
	var contract2: Contract = _prop(main, "active_contract")
	_ok(contract2 is Contract and contract2.state == Contract.State.PRINTING,
		"second contract accepted to PRINTING")
	if contract2 == null:
		_finish(1)
		return
	var bal2: int = ledger.balance()
	_ok(bal2 == bal_before_payout + contract.payout_cents - contract2.material_cost_cents,
		"material charged for second job")
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_FAIL, "seeded failure reaches DONE_FAIL")
	_ok(_prop(main, "active_contract") == null, "failed contract cleared from Main")
	_ok(contract2.state == Contract.State.FAILED, "failed contract state is FAILED")
	_ok(ledger.balance() == bal2, "no payout on failure path")
	main._update_hud()
	_ok("FAIL" in main._status.text, "HUD explains the failure")
	main.sim.failure_seeded = false

	# --- 6. insufficient funds refuses print start ---
	ledger.balance_cents = 0  # test-only drain (Ledger frozen; direct field access)
	main.paused = false
	main._try_interact()
	_ok(_prop(main, "active_contract") == null, "no contract active after refused start")
	_ok(not main.sim.is_running(), "print did not start without funds")
	_ok(ledger.balance() == 0, "no material charge without funds")
	_ok("Not enough funds" in main._prompt.text, "HUD explains Not enough funds")

	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

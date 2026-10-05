extends SceneTree

## v0.32.0 — "Loyalty & calm": returning clients pay +5% per prior order
## (cap +15%), and a new Steady hands daily event lowers failure risk.
## Run: timeout 180 godot --headless --path . -s tests/v032_test.gd

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
	await _test_loyalty()
	_test_event()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_loyalty() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# The multiplier math: +5% per prior order, capped at +15%.
	_ok(absf(main._loyalty_mult("Nobody / Nowhere") - 1.0) < 1e-6,
		"a new client pays base rate")
	for prior in range(1, 6):
		main.client_orders["Loyal / Client"] = prior
		var want := 1.0 + 0.05 * mini(prior, 3)
		_ok(absf(main._loyalty_mult("Loyal / Client") - want) < 1e-6,
			"%d prior orders -> x%.2f" % [prior, want])

	# End to end: the second delivery to a client pays exactly 5% more.
	main.job_board._queue.clear()
	var mk := func(id: String, client: String) -> Contract:
		return load("res://scripts/JobBoard.gd")._contract_from({
			"id": id, "client": client, "model_name": "Repeat part",
			"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
			"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
			"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
			"note": "",
		})
	var delivered := 0
	for run in range(2):
		main.job_board._queue.clear()
		main.job_board._queue.append(mk.call("G-LY%d" % run, "Repeat / Buyer"))
		main._player.global_position = Vector3(-1.8, 0.3, -1.0)
		main._try_interact()
		var sim: PrintSim = main._machine(0).get("sim")
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		sim._failure_tick = -1
		sim.failure_seeded = false
		while sim.is_running():
			sim.tick(1.0)
		main._try_interact()
		var bal_before: int = main.ledger.balance()
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		main._try_interact()
		delivered = main.ledger.balance() - bal_before
		# The prompt names the bonus on the repeat.
		if run == 1:
			_ok(main._prompt.text.contains("returning client x1.05"),
				"the repeat delivery names the loyalty bonus")
	# Run 2's payout must equal the documented chain with the loyalty inside
	# the base: _finalize_payout takes the rep MULTIPLIER when rep >= 0.
	var rep_before_run2: float = main.reputation - 0.2
	var rep_mult: float = 0.8 + (rep_before_run2 / 5.0) * 0.4
	var base_with_loyalty: int = roundi(5000 * 1.05)
	var want2: int = main._finalize_payout(base_with_loyalty, false,
		main._machine(0), rep_mult)
	_ok(delivered == want2,
		"2nd delivery pays the documented chain with +5%% (%d == %d)" % [
			delivered, want2])
	_ok(int(main.client_orders.get("Repeat / Buyer", 0)) == 2,
		"the bonus uses orders completed BEFORE this one")
	main.queue_free()
	await physics_frame


func _test_event() -> void:
	await physics_frame
	# Steady hands exists in the rotation with its -0.10 risk relief.
	var found := false
	for day in range(2, 80):
		var ev: Dictionary = Events.for_day(day)
		if str(ev.id) == "steady_hands":
			found = true
			_ok(absf(float(ev.failure_delta) + 0.10) < 1e-6,
				"steady hands carries failure_delta -0.10")
			break
	_ok(found, "steady hands occurs in the rotation")
	# Deterministic per day.
	_ok(str(Events.for_day(3).id) == str(Events.for_day(3).id),
		"daily events stay deterministic")
	# The failure threshold reads today_event.failure_delta (v0.7 plumbing)
	# — verify the prep seam accepts the negative delta.
	var main = await _fresh_main()
	main.today_event = Events.for_day(2)
	main.today_event["failure_delta"] = -0.10
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	var c: Contract = Contract.new()
	c.id = "C-SH"
	c.client = "Test"
	c.model_name = "Part"
	c.payout_cents = 5000
	c.layers = 100
	c.deadline_days = 3
	c.risk_flags = ["overhangs"]
	main._machine(0)["contract"] = c
	main._machine(0)["sim"].start_job("sh", "Part", 100)
	main._machine(0)["sim"].reset()
	var ev: Dictionary = main._prep_eval(c, "upright")
	_ok(bool(ev.get("valid", false)), "steady-hands prep evaluates fine")
	main.queue_free()
	await physics_frame


func _fresh_main():
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var m = packed.instantiate()
	root.add_child(m)
	for i in range(4):
		await physics_frame
	return m

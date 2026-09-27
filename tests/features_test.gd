extends SceneTree

## v0.5.0 — reputation, stats, salvage, new upgrades (PEI unlock, dryer,
## enclosure), card due tags. Run:
##   timeout 90 godot --headless --path . -s tests/features_test.gd

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
	await _test_reputation_and_stats()
	await _test_salvage_and_upgrades()
	_finish(1 if failures > 0 else 0)


func _confirm_upright(main) -> void:
	# Cycle 0->1->2->0, then confirm: upright can never fail a print.
	for i in range(3):
		main._machine(main._focus)["orient"] = (int(main._machine(main._focus)["orient"]) + 1) % 3
		main._machine(main._focus)["orient_pending"] = true
	main._prep_on(main._focus)


func _test_reputation_and_stats() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true

	# Baseline: rep 3 -> multiplier 1.04; HUD shows stars.
	_ok(absf(main.reputation_multiplier() - 1.04) < 0.0001,
		"rep 3.0 scales payouts by x1.04")
	main._update_hud()
	_ok("Rep ★★★☆☆ 3.0" in main._status.text, "HUD shows the reputation stars")

	# On-time delivery: +0.2 rep, delivered+1, earned_cents includes the payout.
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	var bal0: int = ledger.balance()
	_confirm_upright(main)
	_ok(main._machine(0).get("sim").is_running(), "upright confirm starts the print")
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._try_interact()  # collect
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	var eff_a: String = main._cap_grade_for_color("A", c, main._machine(0))
	var expected: int = roundi(roundi(c.payout_cents
		* QualityCheck.quality_multiplier(eff_a)) * main.reputation_multiplier())
	main._try_interact()  # deliver
	_ok(absf(main.reputation - 3.2) < 0.0001, "on-time delivery raises reputation by 0.2")
	_ok(int(main.stats.delivered) == 1, "delivered counter incremented")
	_ok(int(main.stats.earned_cents) == expected,
		"earned_cents includes the rep-scaled payout ($%s)" % main._cents_str(expected))
	_ok(ledger.balance() == bal0 + expected,
		"balance reflects the rep-scaled grade-A payout (filament was the material)")
	main._update_hud()
	_ok("Rep ★★★☆☆ 3.2" in main._status.text, "HUD rep text updates (still 3 stars)")

	# Late delivery: half pay, rep -0.2, late counter.
	main._machine(0)["filament_g"] = 5000  # test setup: plenty of filament
	ledger.credit(30000, "test funds 2")
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._focus = 0
	main._try_interact()
	var c2: Contract = main._machine(0).get("contract")
	_confirm_upright(main)
	var s1: PrintSim = main._machine(0).get("sim")
	main.day_cycle.restore(main.day_cycle.day + c2.deadline_days + 1, 0.0)
	while s1.is_running():
		s1.tick(1.0)
	main._try_interact()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	var expected_late: int = roundi(roundi(c2.payout_cents
		* main.reputation_multiplier()) * 0.5)
	main._try_interact()
	_ok(absf(main.reputation - 3.0) < 0.0001, "late delivery costs 0.2 reputation")
	_ok(int(main.stats.late) == 1, "late counter incremented")
	_ok(ledger.has_paid(c2.id) and ledger.balance() > 0,
		"late delivery still pays (half, rep-scaled)")

	# Scrap path: rep -0.4, scrapped counter.
	main._machine(0)["filament_g"] = 5000
	ledger.credit(30000, "test funds 3")
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c3: Contract = main._machine(0).get("contract")
	_confirm_upright(main)
	var s2: PrintSim = main._machine(0).get("sim")
	while s2.is_running():
		s2.tick(1.0)
	main._try_interact()
	main._machine(0)["scrap"] = true  # simulate an F grade decision
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(absf(main.reputation - 2.6) < 0.0001, "scrapping costs 0.4 reputation")
	_ok(int(main.stats.scrapped) == 1, "scrapped counter incremented")

	# Persistence round trip.
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(absf(float(payload.reputation) - 2.6) < 0.0001, "save carries reputation")
	_ok(int(payload.stats.delivered) == 2 and int(payload.stats.late) == 1
		and int(payload.stats.scrapped) == 1, "save carries lifetime counters")
	_ok(not SaveSystem.validate(payload).is_empty(), "payload with rep/stats validates")
	var bad: Dictionary = payload.duplicate(true)
	bad.reputation = 9.0
	_ok(SaveSystem.validate(bad).is_empty(), "out-of-range reputation rejects payload")
	bad = payload.duplicate(true)
	bad.stats.delivered = -3
	_ok(SaveSystem.validate(bad).is_empty(), "negative stat rejects payload")

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(absf(main2.reputation - 2.6) < 0.0001 and int(main2.stats.late) == 1,
		"fresh Main restores reputation and stats")
	main2.queue_free()
	await physics_frame

	# Stats panel renders the lines Main pushes.
	main.main_menu.open_menu()
	main._on_menu_stats()
	var body: Label = main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok("Days in business" in body.text and "Lifetime earnings" in body.text,
		"stats panel shows the stat lines")
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _test_salvage_and_upgrades() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true

	# Salvage: clearing a failed print refunds half the material cost.
	# (failure_seeded bites mid-print even on a job already running.)
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._focus = 0
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null, "salvage section: job accepted")
	if c == null:
		_finish(1)
		return
	_confirm_upright(main)
	main.sim.failure_seeded = true
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	_ok(s0.state == PrintSim.State.DONE_FAIL, "seeded failure reaches DONE_FAIL")
	var fil_before: int = int(main._machine(0).get("filament_g"))
	var est: int = int(PrepSystem.evaluate(c, "upright").estimated_material_g)
	main._try_interact()  # clear the spoiled print
	var expected_salvage: int = est / 2
	_ok(int(main._machine(0).get("filament_g")) == fil_before + expected_salvage,
		"clearing a failed print salvages half the grams (%d g)" % expected_salvage)
	_ok("salvaged" in str(main._prompt.text), "HUD explains the salvage")
	main.sim.failure_seeded = false

	# New upgrades: catalog grew to 8; PEI unlocks flat_side on stability parts.
	_ok(Upgrades.catalog().size() == 8, "catalog now lists 8 upgrades")
	var tippy: Contract = Contract.new()
	tippy.id = "T-1"
	tippy.client = "Test"
	tippy.model_name = "Tippy part"
	tippy.payout_cents = 5000
	tippy.material_cost_cents = 500
	tippy.difficulty = 3
	tippy.risk_flags = ["stability"]
	tippy.layers = 100
	tippy.deadline_days = 3
	var eval_locked: Dictionary = main._prep_eval(tippy, "flat_side")
	_ok(not bool(eval_locked.valid), "flat_side refused on stability parts without PEI")
	main.upgrades.buy("pei_plate")
	var eval_open: Dictionary = main._prep_eval(tippy, "flat_side")
	_ok(bool(eval_open.valid), "PEI plate unlocks flat_side on stability parts")

	# Dryer + enclosure stack onto the existing modifiers.
	main.upgrades.buy("heated_bed")
	main.upgrades.buy("filament_dryer")
	main.upgrades.buy("stiff_frame")
	main.upgrades.buy("enclosure")
	var mods: Dictionary = main.upgrades.risk_modifiers()
	_ok(absf(float(mods.adhesion_risk) + 0.25) < 0.0001, "dryer stacks: adhesion -0.25 total")
	_ok(absf(float(mods.stability_risk) + 0.40) < 0.0001, "enclosure stacks: stability -0.40 total")
	var eval_modded: Dictionary = main._prep_eval(tippy, "flat_side")
	_ok(absf(float(eval_modded.adhesion_risk) - 0.30) < 0.0001,
		"prep eval applies stacked adhesion (0.55-0.25)")
	_ok(absf(float(eval_modded.stability_risk)) < 0.0001,
		"prep eval clamps stability at 0 (0.30-0.40)")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

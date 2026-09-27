extends SceneTree

## v0.8.0 — filament color demands. Run:
##   timeout 90 godot --headless --path . -s tests/color_test.gd

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
	_test_contract_colors()
	await _test_crate_and_cap()
	await _test_persistence_and_board()
	_finish(1 if failures > 0 else 0)


func _test_contract_colors() -> void:
	# Fixtures demand valid colors.
	for j in Contract.make_fixture_jobs():
		_ok(j.color in Contract.VALID_COLORS, "fixture %s demands a valid color (%s)" % [j.id, j.color])
	# Generated sweep: valid colors everywhere, all three demanded.
	var seen := {}
	for day in range(1, 30):
		for slot in range(8):
			var c: Contract = Contract.generate(day, slot)
			if c.color in Contract.VALID_COLORS:
				seen[c.color] = true
			else:
				_ok(false, "generated %s has invalid color %s" % [c.id, c.color])
	_ok(seen.has("Clay") and seen.has("Sage") and seen.has("Honey"),
		"generated board demands all three colors over time")

	# Color is part of board summaries.
	var board = load("res://scripts/JobBoard.gd").new()
	root.add_child(board)
	var summaries: Array[Dictionary] = board.available_summaries()
	_ok(summaries[0].has("color") and str(summaries[0].color) != "",
		"summaries carry the demanded color")
	board.queue_free()
	await physics_frame


func _test_crate_and_cap() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)

	# Crate cycles Clay -> Sage -> Honey -> Clay ...; each buy charges.
	main._player.global_position = Vector3(-3.0, 0.3, 2.1)
	var bal0: int = ledger.balance()
	var bought: Array[String] = []
	var guard := 0
	while bought.size() < 3 and guard < 12:
		guard += 1
		if main.held != null:
			# set the held spool down on a fresh floor spot, then buy again
			main._player.global_position = Vector3(0.0 + 0.5 * bought.size(), 0.3, 0.3)
			main.yaw = 0.0
			main.pitch = -0.9
			main._player.rotation.y = main.yaw
			main._camera.rotation.x = main.pitch
			await physics_frame
			main._try_place()
			continue
		main._player.global_position = Vector3(-3.0, 0.3, 2.1)
		await physics_frame
		var want: String = main._crate_color()
		var before: int = ledger.balance()
		main._try_interact()
		if main.held != null and ledger.balance() == before - 1200:
			bought.append(str(main.held.get_meta("spool_color", "")))
			_ok(str(want) == bought[bought.size() - 1],
				"crate handed out the advertised color (%s)" % want)
	_ok(bought == ["Clay", "Sage", "Honey"],
		"three buys rotate through the palette (%s)" % str(bought))
	_ok(ledger.balance() == bal0 - 3600, "each spool costs $12.00 (quiet day)")

	# Loading sets the machine color (shown on the HUD line).
	var spool: Grabbable = main._make_crate_spool("Sage")
	add_child_to_root(main, spool)
	spool.global_position = main._player.global_position + Vector3(0, 1.2, 0)
	main._attach_to_hand(spool)
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()  # load
	_ok(str(main._machine(0).get("color")) == "Sage", "loading a Sage spool sets the machine color")
	main._update_hud()
	_ok("Sage" in main._status.text, "HUD filament line shows the color")

	# Grade cap: A with a mismatched spool ships as B; matches stay A.
	var m0: Dictionary = main._machine(0)
	var fake: Contract = Contract.new()
	fake.id = "COL-1"
	fake.client = "Test"
	fake.model_name = "Color test"
	fake.payout_cents = 5000
	fake.material_cost_cents = 500
	fake.difficulty = 1
	fake.layers = 100
	fake.deadline_days = 3
	fake.color = "Honey"
	_ok(main._cap_grade_for_color("A", fake, m0) == "B",
		"mismatched color caps an A at B")
	m0["color"] = "Honey"
	_ok(main._cap_grade_for_color("A", fake, m0) == "A",
		"matching color keeps the A")
	_ok(main._cap_grade_for_color("C", fake, m0) == "C"
		and main._cap_grade_for_color("F", fake, m0) == "F",
		"C and F grades pass through the cap untouched")

	# End-to-end: mismatched delivery pays the B rate on a perfect print.
	m0["color"] = "Clay"  # wrong color on purpose
	var s0: PrintSim = m0.get("sim")
	main._try_interact()  # accept (standing at printer 1)
	var c: Contract = main._machine(0).get("contract")
	if c != null:
		c.color = "Honey"  # force a mismatch against the Clay-loaded machine
		for i in range(3):
			main._machine(0)["orient"] = (int(main._machine(0)["orient"]) + 1) % 3
			main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		while s0.is_running():
			s0.tick(1.0)
		main._try_interact()  # collect
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		var snap: Dictionary = main._machine(0).get("grade_snapshot", {})
		var grade := QualityCheck.grade(c, int(snap.get("final_layer", 0)),
			int(snap.get("total_layers", 0)), snap.get("risks", {}))
		var eff: String = main._cap_grade_for_color(grade, c, main._machine(0))
		var expected: int = roundi(roundi(roundi(c.payout_cents
			* QualityCheck.quality_multiplier(eff)) * main.reputation_multiplier())
			* float(main.today_event.payout_mult))
		var bal1: int = ledger.balance()
		main._try_interact()  # deliver
		_ok(eff == "B" and ledger.balance() == bal1 + expected,
			"mismatched delivery paid the B rate ($%s, eff %s)" % [main._cents_str(expected), eff])

	# Persistence round trip.
	main._machine(0)["color"] = "Sage"
	main._machine(1)["color"] = "Honey"
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(not SaveSystem.validate(payload).is_empty(), "payload with spool colors validates")
	_ok(payload.spool_colors[0] == "Sage" and payload.spool_colors[1] == "Honey",
		"save carries per-machine spool colors")
	var bad: Dictionary = payload.duplicate(true)
	bad.spool_colors = "Sage"
	_ok(SaveSystem.validate(bad).is_empty(), "non-array spool colors reject the payload")

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(str(main2._machine(0).get("color")) == "Sage"
		and str(main2._machine(1).get("color")) == "Honey",
		"fresh Main restores per-machine spool colors")
	main2.queue_free()
	await physics_frame
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func add_child_to_root(main, spool) -> void:
	main.add_child(spool)


func _test_persistence_and_board() -> void:
	# Card tag renders the demanded color.
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.main_menu.open_menu()
	main._on_menu_contracts()
	var cards: Array = main.main_menu.contract_cards()
	_ok(cards.size() >= 3, "board renders cards")
	var tag_found := false
	for card in cards:
		var tag: Label = card.find_child("ColorTag", true, false)
		if tag != null and tag.text.contains("["):
			tag_found = true
	_ok(tag_found, "cards show a [Color] tag")
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

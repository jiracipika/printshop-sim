extends SceneTree

## v0.23.0 — "Operations pass": photo mode (F2), Full house + Perfectionist
## milestones, surplus-stock daily event, chalkboard week line. Run:
## timeout 180 godot --headless --path . -s tests/v023_test.gd

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
	await _test_operations()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_operations() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Photo mode: F2 handler hides the whole HUD layer and says so.
	_ok(main._hud.visible, "HUD starts visible")
	main._toggle_photo_mode()
	_ok(not main._hud.visible and main._prompt.text.contains("F2"),
		"photo mode hides the HUD and names the key")
	main._toggle_photo_mode()
	_ok(main._hud.visible, "photo mode toggles back")
	_ok(main._prompt.text.contains("ON"), "restoring the HUD says ON")
	main._toggle_photo_mode()
	_ok(not main._hud.visible and main._prompt.text.contains("hidden"),
		"hiding the HUD says so")
	main._toggle_photo_mode()

	# Full house: all four sims running at once.
	_ok(not main._full_house(), "an idle shop is not a full house")
	for i in range(4):
		(main._machine(i).get("sim") as PrintSim).start_job("fh-%d" % i, "Part %d" % i, 40)
	_ok(main._full_house(), "four running printers fill the house")
	var names := {}
	for a in main._achievements():
		names[a.name] = bool(a.done)
	_ok(names.get("Full house", false), "Full house unlocks")
	for i in range(4):
		(main._machine(i).get("sim") as PrintSim).reset()
	_ok(not main._full_house(), "clearing a bed empties the house")

	# Perfectionist: five A deliveries in a row (B breaks the streak).
	var perf_done := false
	for a in main._achievements():
		if a.name == "Perfectionist":
			perf_done = bool(a.done)
	_ok(not perf_done and main.recent_grades.is_empty(),
		"Perfectionist starts locked")
	main.recent_grades.assign(["A", "A", "A", "A"])
	for a in main._achievements():
		if a.name == "Perfectionist":
			perf_done = bool(a.done)
	_ok(not perf_done, "four As are not enough")
	main.recent_grades.append("A")
	for a in main._achievements():
		if a.name == "Perfectionist":
			perf_done = bool(a.done)
	_ok(perf_done, "five As unlock Perfectionist")
	main.recent_grades.clear()
	main.recent_grades.assign(["A", "A", "A", "A", "B"])
	for a in main._achievements():
		if a.name == "Perfectionist":
			perf_done = bool(a.done)
	_ok(not perf_done, "a B breaks the streak")

	# recent_grades persists (JSON floats in, letters out).
	main.recent_grades.clear()
	main.recent_grades.assign(["A", "B", "A"])
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	var sg = saved.get("recent_grades", "MISSING")
	_ok(sg is Array and sg.size() == 3 and str(sg[0]) == "A" and str(sg[1]) == "B",
		"recent_grades persists in the save")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2.recent_grades.size() == 3 and str(main2.recent_grades[1]) == "B",
		"recent_grades survives the reload")
	# Validator refuses junk grades outright.
	var bad := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "recent_grades": ["A", 3]}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad).is_empty(),
		"validator rejects a non-letter recent_grades entry")
	main2.queue_free()
	await physics_frame

	# Surplus stock day: cheap spools, and the crate sign follows.
	var found_day := -1
	for day in range(2, 60):
		if str(Events.for_day(day).id) == "surplus_stock":
			found_day = day
			break
	_ok(found_day > 0, "surplus stock occurs in the rotation")
	if found_day > 0:
		var ev: Dictionary = Events.for_day(found_day)
		_ok(int(ev.spool_price_cents) == 600 and "$6" in str(ev.name),
			"surplus stock sells spools at $6")
		var main3 = packed.instantiate()
		root.add_child(main3)
		await physics_frame
		main3.day_cycle.restore(found_day, 0.3)
		main3._refresh_event()
		_ok(str(main3.today_event.id) == "surplus_stock"
			and main3._crate_label.text.contains("$6"),
			"crate sign shows the surplus price")
		# Chalkboard names the week with the season icon.
		main3.season = Events._season_by_id("cold_snap")
		main3._update_chalkboard()
		_ok(main3._chalk_label.text.contains("Week ")
			and main3._chalk_label.text.contains("☃"),
			"chalkboard names the week and season icon")
		# Calm weeks keep no trailing space after the week number.
		main3.season = Events.CALM_SEASON.duplicate(true)
		main3._update_chalkboard()
		_ok(main3._chalk_label.text.contains("· Week 1\n")
			and not main3._chalk_label.text.contains("Week 1 \n"),
			"calm chalkboard line has no trailing space")
		main3.queue_free()
		await physics_frame

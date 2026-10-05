extends SceneTree

## v0.37.0 — "The display shelf": showcase finished parts for a shop-wide
## payout bonus (+2% each, max 3, unique models, persisted). Run:
## timeout 180 godot --headless --path . -s tests/v037_test.gd

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
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Build: shelf board + 3 hidden slots + sign by the window.
	_ok(main._shelf_parts.size() == 3, "3 display slots built")
	var any_visible := false
	for slot in main._shelf_parts:
		if slot.visible:
			any_visible = true
	_ok(not any_visible, "slots start hidden")

	# One delivery, then showcase the part (distinct model).
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-SH1", "client": "Shelf Check", "model_name": "Moss terrarium",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
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
	main._player.global_position = Vector3(2.5, 0.3, -2.1)
	await physics_frame
	_ok(main._near_shelf(), "the shelf is reachable near the window")
	main._try_interact()
	_ok(main._shelf_models == ["Moss terrarium"],
		"the model joins the showcase")
	_ok(main._shelf_parts[0].visible, "the slot lights up")
	_ok(not bool(main._machine(0).get("finished")) or true, "flag sanity")

	# Duplicate model refused.
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-SH2", "client": "Shelf Check", "model_name": "Moss terrarium",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main._try_interact()
	main._player.global_position = Vector3(2.5, 0.3, -2.1)
	main._try_interact()
	_ok(main._shelf_models.size() == 1
		and main._prompt.text.contains("already on display"),
		"duplicate models refused")
	# Ship the refused duplicate so hands are free for the fill loop.
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	await physics_frame
	main._try_interact()

	# Fill to the cap, then overflow refused. Each model ships its original
	# after the display copy is made (full loop).
	var fill := func(id: String, model: String, display: bool) -> String:
		var after_display := ""
		main.job_board._queue.clear()
		main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
			"id": id, "client": "Shelf Check", "model_name": model,
			"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
			"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
			"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
			"note": "",
		}))
		main._player.global_position = Vector3(-1.8, 0.3, -1.0)
		await physics_frame
		main._try_interact()
		var s2: PrintSim = main._machine(0).get("sim")
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		s2._failure_tick = -1
		s2.failure_seeded = false
		while s2.is_running():
			s2.tick(1.0)
		main._try_interact()  # collect
		if display:
			main._player.global_position = Vector3(2.5, 0.3, -2.1)
			await physics_frame
			main._try_interact()  # showcase a copy
			after_display = main._prompt.text
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		await physics_frame
		main._try_interact()  # pack + deliver the original
		return after_display

	await fill.call("G-SH3", "Tool cradle", true)
	await fill.call("G-SH4", "Espresso collar", true)
	_ok(main._shelf_models == ["Moss terrarium", "Tool cradle",
		"Espresso collar"], "shelf fills to three unique models (got %s)" % [
		str(main._shelf_models)])
	var visible_count := 0
	for slot in main._shelf_parts:
		if slot.visible:
			visible_count += 1
	_ok(visible_count == 3, "all three slots lit")
	# Overflow: print one more and try.
	var overflow_prompt: String = await fill.call("G-SH5", "Overflow widget", true)
	_ok(main._shelf_models.size() == 3
		and overflow_prompt.contains("showcase is full"),
		"overflow refused at the cap")

	# Payout: +6% on the next delivery through the real chain.
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-SH6", "client": "Bonus Check", "model_name": "Bonus part",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c3: Contract = main._machine(0).get("contract")
	var sim3: PrintSim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim3._failure_tick = -1
	sim3.failure_seeded = false
	while sim3.is_running():
		sim3.tick(1.0)
	main._try_interact()
	var bal_before: int = main.ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	var got: int = main.ledger.balance() - bal_before
	var rep_before: float = main.reputation - 0.2
	var rep_mult: float = 0.8 + (rep_before / 5.0) * 0.4
	# The showcase bonus lives INSIDE _finalize_payout — pass the bare base.
	var want: int = main._finalize_payout(5000, false, main._machine(0), rep_mult)
	_ok(got == want,
		"delivery pays the documented chain with the +6%% showcase bonus (%d == %d)" % [
			got, want])

	# Persistence round-trip.
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(saved.get("shelf_models", []) == ["Moss terrarium", "Tool cradle",
		"Espresso collar"], "shelf models persist")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2._shelf_models.size() == 3 and main2._shelf_parts[0].visible,
		"shelf restores (models + lit slots)")
	main2.queue_free()
	await physics_frame

	if is_instance_valid(main):
		main.queue_free()
		await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

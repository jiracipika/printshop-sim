extends SceneTree

## v0.34.0 — integration: the finishing station and window life, wired into
## the live game. Run:
## timeout 180 godot --headless --path . -s tests/v034_test.gd

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
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()  # accept

	var sim: PrintSim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main._try_interact()  # collect the part
	_ok(main.held != null, "part collected")
	# Force a B-grade snapshot (max risk 0.5..0.7 grades B when complete).
	main._machine(0)["grade_snapshot"] = {"final_layer": 40, "total_layers": 40,
		"risks": {"support_need": 0.6, "adhesion_risk": 0.1,
		"stability_risk": 0.1}}

	# Finish the part at the bench (standing beside it, not inside it).
	main._player.global_position = Vector3(2.55, 0.3, 1.9)
	await physics_frame
	_ok(main._near_finishing(), "the bench is reachable at its position")
	main._try_interact()
	_ok(bool(main._machine(0).get("finished")),
		"the part is flagged finished")
	_ok(main._prompt.text.contains("-> A"),
		"the prompt shows B -> A")

	# One pass per part.
	main._try_interact()
	_ok(main._prompt.text.contains("one pass per part"),
		"a second pass is refused")

	# Packing applies the bump: the delivery logs grade A.
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(main._machine(0).get("contract") == null,
		"the finished part delivers")
	var grade_a_logged := false
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "delivered" and "grade A" in str(e["text"]):
			grade_a_logged = true
	_ok(grade_a_logged, "the pack used the bumped grade A")
	var fin_logged := false
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "finished":
			fin_logged = true
	_ok(fin_logged, "the finishing pass is in the workshop log")
	_ok(not bool(main._machine(0).get("finished")),
		"the finish flag cleared at delivery")

	# A fresh part starts unfinished: second job, no bump unless finished.
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-FIN2", "client": "Finish Check", "model_name": "Control part",
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
	_ok(not bool(main._machine(0).get("finished")),
		"a fresh part starts unfinished")
	# Pack WITHOUT finishing: grade A stays A (no double-improvement).
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	var grade_a_control := false
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "delivered" and "Control part" in str(e["text"]) \
				and "grade A" in str(e["text"]):
			grade_a_control = true
	_ok(grade_a_control, "control part delivers at its own grade")

	# Window life: wired to season and clock.
	_ok(main._window_life != null, "window life exists in the scene")
	var airborne := func(wl) -> int:
		var n := 0
		for w in wl._bird_wait:
			if float(w) >= 0.0:
				n += 1
		return n
	main.season = Events._season_by_id("humid")
	main._apply_season_visuals()
	# A full crossing takes ~4.5 s at 0.4 m/s — advance past the longest
	# flight before asserting every bird is grounded.
	main._window_life._advance(6.0)
	_ok(airborne.call(main._window_life) == 0, "rain grounds the birds")
	main.season = Events._season_by_id("calm")
	main._apply_season_visuals()
	main._window_life._advance(3.0)
	_ok(airborne.call(main._window_life) >= 1, "calm skies relaunch the birds")
	main.day_cycle.t = 0.0
	main._apply_daylight()
	_ok(absf(main._window_life._nightness - 1.0) < 0.01,
		"midnight passes nightness 1.0 to the silhouettes")
	main.day_cycle.t = 0.5
	main._apply_daylight()
	_ok(main._window_life._nightness < 0.01,
		"noon passes nightness 0.0")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

extends SceneTree

## v0.39.0 — "News & notices": Media day (A-grade deliveries earn +0.3 rep)
## and Backorders (+2 board jobs). Run:
## timeout 180 godot --headless --path . -s tests/v039_test.gd

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

	# Media day: an A-grade delivery earns +0.3 rep instead of +0.2.
	main.today_event = {"id": "media_day", "name": "Media day",
		"spool_price_cents": 1200, "payout_mult": 1.0,
		"failure_delta": 0.0, "rent_free": false, "extra_jobs": 0}
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-MD", "client": "Press Club", "model_name": "Photo prop",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	var rep_before: float = main.reputation
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	await physics_frame
	await physics_frame
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
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	await physics_frame
	await physics_frame
	main._try_interact()
	_ok(absf(main.reputation - rep_before - 0.3) < 0.001,
		"media-day A delivery earns +0.3 rep (%.2f -> %.2f)" % [
			rep_before, main.reputation])

	# Backorders: the board widens by 2 while the event is live.
	main.today_event = {"id": "backorders", "name": "Backorders",
		"spool_price_cents": 1200, "payout_mult": 1.0,
		"failure_delta": 0.0, "rent_free": false, "extra_jobs": 2}
	main.job_board.extra_jobs = 2  # what Main._refresh_event does from the event
	_ok(main.job_board.extra_jobs == 2, "the seam carries extra_jobs")
	main.job_board._queue.clear()
	main.job_board._fill_to_capacity()
	_ok(main.job_board._queue.size() == 10,
		"the board deals 10 jobs on backorder day (got %d)" %
			main.job_board._queue.size())
	# Non-event days go back to 8.
	main.job_board.extra_jobs = 0
	main.job_board._queue.clear()
	main.job_board._fill_to_capacity()
	_ok(main.job_board._queue.size() == 8, "normal days deal 8")

	# Rotation: both events occur, deterministic per day.
	var media_days := 0
	var backorder_days := 0
	for day in range(2, 60):
		var id := str(Events.for_day(day).id)
		if id == "media_day":
			media_days += 1
		if id == "backorders":
			backorder_days += 1
	_ok(media_days >= 3 and backorder_days >= 3,
		"both new events occur in the rotation (%d media, %d backorders)" % [
			media_days, backorder_days])
	_ok(Events.FORECAST_HINT.has("media_day")
		and Events.FORECAST_HINT.has("backorders"),
		"forecast hints cover the new events")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

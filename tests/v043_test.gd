extends SceneTree

## v0.43.0 — "Milestones II": Paper star (3 A-grades on media days),
## Board magnet (12 jobs on the board), Distinguished (5 regulars + 5
## stars). Run: timeout 180 godot --headless --path . -s tests/v043_test.gd

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

	# Milestone definitions exist.
	var names := {}
	for a in main._achievements():
		names[a.name] = bool(a.done)
	for n in ["Paper star", "Board magnet", "Distinguished"]:
		_ok(names.has(n), "'%s' exists" % n)
	_ok(not names["Paper star"] and not names["Board magnet"]
		and not names["Distinguished"], "all three start locked")

	# Paper star: 3 A-grades on media days (direct counter + delivery path).
	main.today_event = {"id": "media_day", "name": "Media day",
		"spool_price_cents": 1200, "payout_mult": 1.0,
		"failure_delta": 0.0, "rent_free": false, "extra_jobs": 0}
	main._machine(0)["filament_g"] = 50000
	for i in range(3):
		main.job_board._queue.clear()
		main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
			"id": "G-PS%d" % i, "client": "Press %d" % i,
			"model_name": "Photo prop %d" % i,
			"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
			"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
			"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
			"note": "",
		}))
		main._player.global_position = Vector3(-1.8, 0.3, -1.0)
		main.yaw = -0.6
		main.pitch = 0.0
		main._player.rotation.y = main.yaw
		main._camera.rotation.x = main.pitch
		await physics_frame
		await physics_frame
		main._try_interact()
		var sim: PrintSim = main._machine(0).get("sim")
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		sim._failure_tick = -1
		sim.failure_seeded = false
		sim.failure_threshold = 1.5
		while sim.is_running():
			sim.tick(1.0)
		main._try_interact()
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		await physics_frame
		await physics_frame
		main._try_interact()
	_ok(int(main.media_a_deliveries) == 3, "3 media-day A deliveries counted")
	for a in main._achievements():
		if a.name == "Paper star":
			_ok(bool(a.done), "Paper star unlocks at 3")

	# Board magnet: 12 jobs on the board at once.
	main.today_event = {"id": "backorders", "name": "Backorders",
		"spool_price_cents": 1200, "payout_mult": 1.0,
		"failure_delta": 0.0, "rent_free": false, "extra_jobs": 4}
	main._refresh_event()
	main.job_board.extra_jobs = 4
	main.job_board._queue.clear()
	main.job_board._fill_to_capacity()
	_ok(main.job_board.get_available_count() >= 12, "board widened to 12")
	for a in main._achievements():
		if a.name == "Board magnet":
			_ok(bool(a.done), "Board magnet unlocks at 12 jobs")

	# Distinguished: 5 regulars + 5 stars.
	main.reputation = 5.0
	main.client_orders = {"A": 3, "B": 3, "C": 3, "D": 3, "E": 3}
	for a in main._achievements():
		if a.name == "Distinguished":
			_ok(bool(a.done), "Distinguished unlocks at 5 regulars + 5 stars")

	# Persistence: the media counter round-trips.
	main.media_a_deliveries = 7
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(int(saved.get("media_a_deliveries", -1)) == 7, "counter persists")
	var bad := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "media_a_deliveries": -2}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad).is_empty(),
		"validator rejects a negative counter")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	BrowserSave.save_path = "user://v043_test_save.json"
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

extends SceneTree

## v0.31.0 — "Regulars": client order memory, loyalty notes stamped on
## freshly dealt jobs, Stats line and the Neighborhood favorite milestone.
## Run: timeout 180 godot --headless --path . -s tests/v031_test.gd

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
	await _test_regulars()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_regulars() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Deliver twice for the same client: memory increments per completion.
	main.job_board._queue.clear()
	var mk := func(id: String, client: String) -> Contract:
		var c: Contract = load("res://scripts/JobBoard.gd")._contract_from({
			"id": id, "client": client, "model_name": "Repeat part",
			"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
			"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
			"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
			"note": "",
		})
		return c
	main.job_board._queue.append(mk.call("G-REG1", "Mara / Corner Plant Co."))
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
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(int(main.client_orders.get("Mara / Corner Plant Co.", 0)) == 1,
		"first delivery counts the client")

	main.job_board._queue.clear()
	main.job_board._queue.append(mk.call("G-REG2", "Mara / Corner Plant Co."))
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
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(int(main.client_orders.get("Mara / Corner Plant Co.", 0)) == 2,
		"second delivery makes Mara a regular-to-be")
	_ok(main._regulars_count() == 0, "3+ orders still needed for regular status")

	# Loyalty notes stamp onto freshly dealt jobs for 2+ clients. Deal a
	# probe board first and pick whichever client actually shows up.
	main.job_board.regulars = {}
	main.job_board.deal_day(9, 5, 1.0)
	var probe_client: String = str(main.job_board._queue[0].client)
	main.job_board.regulars = {probe_client: 2}
	main.job_board.deal_day(9, 5, 1.0)
	var loyal := 0
	var client_jobs := 0
	var pool := 0
	var names: Array = load("res://scripts/JobBoard.gd").LOYALTY_NOTES
	var first: Contract = null
	for c in main.job_board._queue:
		if c.client == probe_client:
			client_jobs += 1
			if names.has(c.note):
				loyal += 1
			if first == null:
				first = c
		elif c.note != "":
			pool += 1
	_ok(client_jobs >= 1 and loyal == client_jobs,
		"every dealt job of a regular carries a loyalty note (%d/%d)" % [
			loyal, client_jobs])
	_ok(pool >= 1, "other clients still draw generic notes")
	# Deterministic per job id.
	main.job_board.deal_day(9, 5, 1.0)
	var again: Contract = null
	for c in main.job_board._queue:
		if str(c.id) == str(first.id):
			again = c
			break
	_ok(again != null and again.note == first.note,
		"loyalty notes are pinned per job id")

	# Persistence: memory round-trips; validator rejects junk.
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(int(saved.get("client_orders", {}).get("Mara / Corner Plant Co.", 0)) == 2,
		"client memory persists in the save")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(int(main2.client_orders.get("Mara / Corner Plant Co.", 0)) == 2
		and main2.job_board.regulars.has("Mara / Corner Plant Co."),
		"client memory and board regulars survive the reload")
	main2.queue_free()
	await physics_frame
	var bad := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "client_orders": {"": 3}}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad).is_empty(),
		"validator rejects an empty client name")
	var bad2 := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "client_orders": {"X": 0}}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad2).is_empty(),
		"validator rejects a zero count")

	# Stats line + milestone at the thresholds.
	var main3 = packed.instantiate()
	root.add_child(main3)
	await physics_frame
	main3.client_orders = {"A": 3, "B": 3, "C": 3, "D": 3, "E": 2}
	main3._on_menu_stats()
	var text: String = main3.main_menu._stats_panel.get_node(
		"Sheet/SheetBox/Body").text
	_ok(text.contains("Regulars: 4"), "stats counts 4 regulars")
	var favorite := false
	for a in main3._achievements():
		if a.name == "Neighborhood favorite":
			favorite = bool(a.done)
	_ok(not favorite, "4 regulars is not a neighborhood favorite yet")
	main3.client_orders["E"] = 3
	for a in main3._achievements():
		if a.name == "Neighborhood favorite":
			favorite = bool(a.done)
	_ok(favorite, "5 regulars unlock Neighborhood favorite")
	main3.queue_free()
	await physics_frame

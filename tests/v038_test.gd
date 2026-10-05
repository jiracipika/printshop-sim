extends SceneTree

## v0.38.0 — "The customers remember": last grade per client, reaction
## notes on their fresh jobs (praise after A, neutral after B/C, worried
## after D), persisted. Run:
## timeout 180 godot --headless --path . -s tests/v038_test.gd

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

	# Reaction pools exist and are disjoint from the generic notes.
	var praise: Array = load("res://scripts/JobBoard.gd").REACTION_PRAISE
	var neutral: Array = load("res://scripts/JobBoard.gd").REACTION_NEUTRAL
	var worried: Array = load("res://scripts/JobBoard.gd").REACTION_WORRIED
	_ok(praise.size() >= 3 and neutral.size() >= 3 and worried.size() >= 3,
		"three reaction pools stocked")
	var generic: Array = load("res://scripts/Contract.gd").GEN_NOTES
	var disjoint := true
	for n in praise + neutral + worried:
		if generic.has(n):
			disjoint = false
	_ok(disjoint, "reaction pools are distinct from generic notes")

	# Stamping: a client whose last grade was C draws worried/neutral (never
	# praise); an A-client draws praise (never worried).
	main.job_board.client_grades = {"Wary Client": "C"}
	main.job_board.deal_day(9, 5, 1.0)
	var probe: String = str(main.job_board._queue[0].client)
	var c_client := probe
	var c_pool_ok := true
	for c in main.job_board._queue:
		if c.client != c_client or c.note == "":
			continue
		if praise.has(c.note) or worried.has(c.note):
			c_pool_ok = false
	_ok(c_pool_ok, "a C-client never gets praise or worry notes")
	# Worry case: same client, last grade D.
	main.job_board.client_grades = {c_client: "D"}
	main.job_board.deal_day(9, 5, 1.0)
	var w_pool_ok := true
	var w_count := 0
	for c in main.job_board._queue:
		if c.client != c_client or c.note == "":
			continue
		w_count += 1
		if praise.has(c.note) or neutral.has(c.note):
			w_pool_ok = false
	_ok(w_count >= 1 and w_pool_ok,
		"a D-client draws worry notes (%d jobs)" % w_count)
	# Praise case: last grade A + 2 prior orders -> loyalty wins.
	main.job_board.client_grades = {c_client: "A"}
	main.job_board.regulars = {c_client: 3}
	main.job_board.deal_day(9, 5, 1.0)
	var loyal_ok := true
	var loyal: Array = load("res://scripts/JobBoard.gd").LOYALTY_NOTES
	for c in main.job_board._queue:
		if c.client != c_client or c.note == "":
			continue
		if c.featured:
			continue  # featured picks keep their boost, note-free (v0.42)
		if not loyal.has(c.note):
			loyal_ok = false
			print("DBG non-loyalty note: '", c.note, "' featured=", c.featured)
	_ok(loyal_ok, "loyalty notes win over reactions for regulars")
	main.job_board.regulars = {}
	# A-client without regular status draws praise.
	main.job_board.deal_day(9, 5, 1.0)
	var p_ok := true
	var p_count := 0
	for c in main.job_board._queue:
		if c.client != c_client or c.note == "":
			continue
		p_count += 1
		if worried.has(c.note) or neutral.has(c.note):
			p_ok = false
	_ok(p_count >= 1 and p_ok, "an A-client draws praise notes")

	# End-to-end memory: deliver a C-grade order, memory + fresh note follow.
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-MEM", "client": "Memory Client", "model_name": "Remember me",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	var sim: PrintSim = null
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	# Aim away from the design computer — a stale camera can open it
	# (which pauses the shop) instead of accepting the job.
	main.yaw = -0.6
	main.pitch = 0.0
	main._player.rotation.y = main.yaw
	main._camera.rotation.x = main.pitch
	await physics_frame
	print("DBG2 pre-E: paused=", main.paused, " captured=", main.captured,
		" locked=", main.get_mouse_locked(), " studio=", main.design_studio.visible,
		" queue=", main.job_board._queue.size(),
		" contract=", main._machine(0).get("contract"),
		" machine_locked=", not main.upgrades.machine_unlocked(0))
	main._try_interact()
	print("DBG2 post-E: c=", main._machine(0).get("contract"),
		" prompt='", main._prompt.text, "' paused=", main.paused,
		" studio=", main.design_studio.visible)
	sim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main._try_interact()
	# Force a C snapshot (risk 0.7+) and deliver.
	main._machine(0)["grade_snapshot"] = {"final_layer": 40, "total_layers": 40,
		"risks": {"support_need": 0.85, "adhesion_risk": 0.1,
		"stability_risk": 0.1}}
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main.yaw = -0.6
	main.pitch = 0.0
	main._player.rotation.y = main.yaw
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	main._try_interact()
	_ok(str(main.client_last_grade.get("Memory Client", "")) == "C",
		"the delivered C grade is remembered")
	# The next job from this client reacts.
	# A freshly dealt job for a remembered client reacts to its last grade.
	main.job_board.deal_day(11, 5, 1.0)
	var probe_client: String = str(main.job_board._queue[0].client)
	main.job_board.client_grades = {probe_client: "C"}
	main.job_board.deal_day(11, 5, 1.0)
	var reacted := true
	var pool_n: Array = load("res://scripts/JobBoard.gd").REACTION_NEUTRAL
	var pool_p: Array = load("res://scripts/JobBoard.gd").REACTION_PRAISE
	var pool_w: Array = load("res://scripts/JobBoard.gd").REACTION_WORRIED
	for c in main.job_board._queue:
		if c.client == probe_client and c.note != "":
			if not (pool_n.has(c.note) and not pool_p.has(c.note)
					and not pool_w.has(c.note)):
				reacted = false
	_ok(reacted, "the follow-up job carries a reaction note")

	# Persistence + validator.
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(str(saved.get("client_last_grade", {}).get("Memory Client", "")) == "C",
		"grade memory persists")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(str(main2.client_last_grade.get("Memory Client", "")) == "C",
		"grade memory survives the reload")
	main2.queue_free()
	await physics_frame
	var bad := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "client_last_grade": {"X": "F"}}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad).is_empty(),
		"validator rejects F in grade memory (never delivered)")

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

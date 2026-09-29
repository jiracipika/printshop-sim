extends SceneTree

## v0.18.0 — "Multi-part orders": contracts asking for 2-3 copies, partial
## packs stacking on the packing table, reprint flow, order grade
## aggregation (one F caps C, two F kill the order), single final payout.
## Run: timeout 180 godot --headless --path . -s tests/v018_test.gd

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
	_test_contract_data()
	_test_generation_and_board()
	await _test_multipart_loop()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- pure contract data -----------------------------------------------------------

func _mk(id: String, parts: int) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Test client"
	c.model_name = "Test part"
	c.payout_cents = 5000
	c.material_cost_cents = 500
	c.layers = 100
	c.deadline_days = 3
	c.parts_total = parts
	return c


func _test_contract_data() -> void:
	var single := _mk("C-S", 1)
	_ok(not single.is_multi_part() and single.needs_parts()
		and single.order_payout_cents() == 5000, "single-part basics hold")
	var multi := _mk("C-M", 3)
	_ok(multi.is_multi_part() and multi.order_payout_cents() == 15000,
		"multi-part order payout is per-copy x count")
	multi.parts_packed = 3
	_ok(not multi.needs_parts(), "needs_parts false when all copies packed")
	multi.parts_packed = 4
	_ok(not multi.is_valid(), "parts_packed above total is invalid")
	var too_big := _mk("C-B", 4)
	_ok(not too_big.is_valid(), "parts_total 4 is invalid")
	var too_small := _mk("C-SM", 0)
	_ok(not too_small.is_valid(), "parts_total 0 is invalid")

	# Grade aggregation rules.
	var empty: Array[String] = []
	_ok(Contract.aggregate_grades(empty) == "D", "no grades aggregate to D")
	var aa: Array[String] = ["A", "A"]
	_ok(Contract.aggregate_grades(aa) == "A", "A+A averages to A")
	var ab: Array[String] = ["A", "B"]
	_ok(Contract.aggregate_grades(ab) == "A", "A+B (3.5) floors up to A")
	var bc: Array[String] = ["B", "C"]
	_ok(Contract.aggregate_grades(bc) == "B", "B+C (2.5) stays B")
	var dd: Array[String] = ["D", "D"]
	_ok(Contract.aggregate_grades(dd) == "D", "D+D stays D")
	var one_f: Array[String] = ["A", "F", "A"]
	_ok(Contract.aggregate_grades(one_f) == "C", "a single F caps the order at C")
	var two_f: Array[String] = ["F", "A", "F"]
	_ok(Contract.aggregate_grades(two_f) == "F", "two F copies fail the order")
	var f_only: Array[String] = ["F"]
	_ok(Contract.aggregate_grades(f_only) == "C", "lone F in a 1-part order caps C")

	# Reprint transition: INSPECTION -> PREPARING is legal now.
	_ok(Contract.can_transition(Contract.State.INSPECTION, Contract.State.PREPARING),
		"INSPECTION -> PREPARING legal (multi-part reprint)")
	_ok(not Contract.can_transition(Contract.State.INSPECTION, Contract.State.PRINTING),
		"INSPECTION -> PRINTING stays illegal")


## --- generation + board persistence -----------------------------------------------

func _test_generation_and_board() -> void:
	# Generation stays deterministic; multi-part is the LAST draw so every
	# pre-v0.18 pinned (day, slot) value is untouched.
	var multi_count := 0
	var all_valid := true
	for day in range(1, 11):
		for slot in range(0, 8):
			var c := Contract.generate(day, slot)
			if not c.is_valid():
				all_valid = false
			if c.parts_total < 1 or c.parts_total > 3:
				all_valid = false
			if c.parts_total > 1:
				multi_count += 1
			if c.parts_packed != 0 or not c.copy_grades.is_empty():
				all_valid = false
	_ok(all_valid, "80 generated contracts valid with sane parts fields")
	_ok(multi_count >= 12 and multi_count <= 40,
		"~1 in 4 generated jobs is multi-part (%d/80)" % multi_count)
	_ok(Contract.generate(3, 2).parts_total == Contract.generate(3, 2).parts_total,
		"parts_total deterministic per (day, slot)")

	# Board summaries and persistence carry parts_total; old saves without
	# the key restore as single-part.
	var board = load("res://scripts/JobBoard.gd").new()
	board.generation_enabled = true
	board.rotate_day(4, false)
	var has_multi := false
	var all_summaries_tagged := true
	for s in board.available_summaries():
		if not s.has("parts_total"):
			all_summaries_tagged = false
		elif int(s.parts_total) > 1:
			has_multi = true
	_ok(all_summaries_tagged, "summaries carry parts_total")
	_ok(has_multi, "day-4 board shows at least one multi-part offer")
	var snap: Dictionary = board.snapshot_payload()
	var json: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var board2 = load("res://scripts/JobBoard.gd").new()
	board2.generation_enabled = true
	_ok(board2.restore_payload(json), "board with parts_total round-trips JSON")
	var match_parts := true
	for i in range(board._queue.size()):
		if int(board._queue[i].parts_total) != int(board2._queue[i].parts_total):
			match_parts = false
	_ok(match_parts, "restored queue keeps every parts_total")
	var old_job: Dictionary = snap.jobs[0].duplicate()
	old_job.erase("parts_total")
	var board3 = load("res://scripts/JobBoard.gd").new()
	board3.generation_enabled = true
	_ok(board3.restore_payload({"day": snap.day, "cycle": snap.cycle, "jobs": [old_job]}),
		"pre-v0.18 board payload (no parts key) still restores")
	_ok(int(board3._queue[0].parts_total) == 1, "old saves restore single-part")


## --- live multi-part loop -----------------------------------------------------------

func _hand(id: String, parts: int) -> Contract:
	var c := _mk(id, parts)
	c.difficulty = 1
	c.layers = 40
	c.deadline_days = 6
	c.material_cost_cents = 300
	return c


## Print one copy on machine 0, collect it, and leave the player at the
## packing table holding it. Returns the pack-adjacent state via main.
func _print_and_collect(main) -> void:
	var m: Dictionary = main._machine(0)
	var sim: PrintSim = m.get("sim")
	m["orient"] = 0
	m["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main._try_interact()  # collect the copy


func _test_multipart_loop() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Deal exactly one 3-part order and accept it.
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand("G-MP", 3))
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null and c.parts_total == 3 and c.parts_packed == 0,
		"3-part order accepted")
	_ok(main._prompt.text.contains("3-part order"),
		"accept prompt announces the multi-part order")
	c.color = str(main._machine(0).get("color"))

	# Copy 1: print, collect, pack — partial, no payout yet.
	_print_and_collect(main)
	_ok(main._prompt.text.contains("Copy 1 of 3"),
		"collect prompt names the copy")
	var balance_before: int = main.ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(c.state == Contract.State.INSPECTION and c.parts_packed == 1,
		"copy 1 packed, order still open")
	_ok(main.ledger.balance() == balance_before, "partial pack pays nothing")
	_ok(main.packing_station.stack_count() == 1, "one part stacks on the table")
	_ok(main._machine(0).get("part") == null, "packed copy leaves the hands")
	var part_log := false
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "packed" and "part 1/3" in str(e["text"]):
			part_log = true
	_ok(part_log, "log records the partial pack")

	# HUD reflects the progress.
	main._update_hud()
	_ok(main._status.text.contains("parts 1/3"), "HUD shows parts 1/3")

	# Copy 2 via the reprint branch (E at the printer goes back through prep).
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_ok(c.state == Contract.State.PREPARING, "reprint branch re-enters prep")
	_ok(main._prompt.text.contains("copy 2 of 3"), "reprint prompt names copy 2 of 3")
	_print_and_collect(main)
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(c.parts_packed == 2 and main.packing_station.stack_count() == 2,
		"copy 2 packed, stack grows")

	# Copy 3 completes the order: paid exactly once, aggregate grade applied.
	var rep_before: float = main.reputation
	var expected_eff: int = roundi(c.order_payout_cents()
		* load("res://scripts/QualityCheck.gd").quality_multiplier("A"))
	var expected_total: int = main._finalize_payout(expected_eff, false, main._machine(0))
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_print_and_collect(main)
	# Baseline AFTER the last material charge, BEFORE the payout.
	var balance_final: int = main.ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()
	_ok(c.state == Contract.State.DELIVERED and main._machine(0).get("contract") == null,
		"final copy delivers the order")
	_ok(main.ledger.balance() == balance_final + expected_total,
		"payout lands exactly once at the aggregate grade")
	_ok(main.packing_station.stack_count() == 0, "stack clears on delivery")
	_ok(main.reputation > rep_before, "delivery rep bump applies once")
	_ok(int(main.stats.delivered) == 1, "one order = one delivery stat")
	var order_log := false
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "delivered" and "×3" in str(e["text"]) and "grade A" in str(e["text"]):
			order_log = true
	_ok(order_log, "delivery log names the order size and grade")

	main.queue_free()
	await physics_frame

	# --- Second shop: F-copy flows, two-F failure, cancel with stack ---------
	BrowserSave.clear()
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	main2.paused = false
	main2.captured = true
	main2._machine(0)["filament_g"] = 50000

	# Copy 1 grades F at the station (forced degenerate snapshot): scrap it,
	# reprint, and finish — the single F caps the order at C.
	main2.job_board._queue.clear()
	main2.job_board._queue.append(_hand("G-FC", 2))
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	var fc: Contract = main2._machine(0).get("contract")
	fc.color = str(main2._machine(0).get("color"))
	_print_and_collect(main2)
	main2._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0, "risks": {}}
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()
	_ok(fc.parts_packed == 0 and fc.copy_grades == ["F"]
		and fc.state == Contract.State.INSPECTION,
		"F copy recorded, order survives")
	_ok(bool(main2._machine(0).get("scrap")), "F copy flagged for scrap")
	var rep2: float = main2.reputation
	main2._try_interact()  # scrap the F copy
	_ok(main2.reputation < rep2 and fc.state == Contract.State.INSPECTION
		and int(main2.stats.scrapped) == 1,
		"scrapping the F copy costs rep but not the order")
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()  # reprint copy 1
	_ok(fc.state == Contract.State.PREPARING, "reprint after scrap works")
	_print_and_collect(main2)
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()
	_ok(fc.parts_packed == 1 and main2.packing_station.stack_count() == 1,
		"clean copy packs 1/2")
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	_print_and_collect(main2)
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()
	var fc_final: String = Contract.aggregate_grades(fc.copy_grades)
	_ok(fc.state == Contract.State.DELIVERED and fc_final == "C"
		and int(main2.ledger.balance()) > 0,
		"[F,A] order delivers capped at C")

	# Two F copies kill the order at the second F: no payout, contract gone.
	main2.job_board._queue.clear()
	main2.job_board._queue.append(_hand("G-FF", 2))
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	var ff: Contract = main2._machine(0).get("contract")
	ff.color = str(main2._machine(0).get("color"))
	_print_and_collect(main2)
	main2._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0, "risks": {}}
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()  # F copy 1
	main2._try_interact()  # scrap it
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()  # reprint
	_print_and_collect(main2)
	var bal_ff: int = main2.ledger.balance()  # after the last material charge
	main2._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0, "risks": {}}
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()  # F copy 2 — order dies here
	_ok(ff.state == Contract.State.FAILED and main2._machine(0).get("contract") == null,
		"second F fails the whole order")
	_ok(main2.ledger.balance() == bal_ff, "failed order pays nothing")
	_ok(int(main2.stats.cancelled) == 1, "order failure lands in the stats")
	_ok(main2.packing_station.stack_count() == 0, "stack clears on order failure")

	# Cancelling a mid-order multi-part clears the stack cleanly.
	main2.job_board._queue.clear()
	var mid := _hand("G-MID", 3)
	main2.job_board._queue.append(mid)
	main2._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main2._try_interact()
	var mc: Contract = main2._machine(0).get("contract")
	mc.color = str(main2._machine(0).get("color"))
	_print_and_collect(main2)
	main2._player.global_position = Vector3(2.0, 0.3, 0.9)
	main2._try_interact()
	_ok(main2.packing_station.stack_count() == 1, "mid-order stack visible")
	main2._machine(0)["day"] = main2.day_cycle.day - (mc.deadline_days + 2)
	var cancelled_before: int = main2.stats.cancelled
	main2._on_day_changed(main2.day_cycle.day + 1)
	_ok(main2._machine(0).get("contract") == null
		and int(main2.stats.cancelled) == cancelled_before + 1
		and main2.packing_station.stack_count() == 0,
		"late cancel discards the mid-order and its stack")

	main2.queue_free()
	await physics_frame

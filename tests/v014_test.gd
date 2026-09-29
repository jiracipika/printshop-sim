extends SceneTree

## v0.14.0 — "First come, first served": board pressure. Run:
## timeout 120 godot --headless --path . -s tests/v014_test.gd
##
## Covers: Contract.competing/offered_day + expiry rule; JobBoard carryover,
## overnight expiry, reserve/front seam, snapshot/restore (incl. JSON);
## SaveSystem board validation + missed stat; Main rollover penalties,
## reserve handler, HUD + chalkboard surfacing, menu Reserve buttons.

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


func _hand_job(id: String, rush: bool, competing: bool, offered: int) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Test client"
	c.model_name = "Test part %s" % id
	c.payout_cents = 5000
	c.material_cost_cents = 500
	c.difficulty = 2
	c.layers = 100
	c.deadline_days = 3
	c.rush = rush
	c.competing = competing
	c.offered_day = offered
	c.color = "Clay"
	return c


func _run() -> void:
	BrowserSave.clear()
	_test_contract_expiry()
	await _test_board_carryover()
	await _test_reserve_seam()
	await _test_board_persistence()
	_test_save_validation()
	await _test_main_integration()
	await _test_menu_reserve_cards()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- Contract level -----------------------------------------------------------

func _test_contract_expiry() -> void:
	# offered_day stamps the generating day; competing is deterministic.
	var a: Contract = Contract.generate(4, 2)
	var b: Contract = Contract.generate(4, 2)
	_ok(a.offered_day == 4 and b.offered_day == 4, "generate stamps offered_day")
	_ok(a.competing == b.competing, "competing is deterministic per (day, slot)")
	var comp := 0
	var sweep := 29 * 8
	for day in range(1, 30):
		for slot in range(8):
			var c: Contract = Contract.generate(day, slot)
			if c.competing:
				comp += 1
			if not c.is_valid():
				_ok(false, "generated %s stays valid with new fields" % c.id)
	var ratio := float(comp) / float(sweep)
	_ok(ratio > 0.1 and ratio < 0.6,
		"competing ratio plausible (%.2f over %d)" % [ratio, sweep])

	# Expiry rule: rush/competing vanish overnight; calm never expires.
	var rush_d1 := _hand_job("X-R", true, false, 1)
	var comp_d1 := _hand_job("X-C", false, true, 1)
	var calm_d1 := _hand_job("X-P", false, false, 1)
	var calm_d2 := _hand_job("X-Q", false, false, 2)
	_ok(rush_d1.has_expired_for(2) and comp_d1.has_expired_for(2),
		"rush/competing offered day 1 expire into day 2")
	_ok(not rush_d1.has_expired_for(1) and not comp_d1.has_expired_for(1),
		"today's offers never expire against today")
	_ok(not calm_d1.has_expired_for(9) and not calm_d2.has_expired_for(9),
		"calm jobs never expire")


## --- JobBoard level -------------------------------------------------------------

func _fresh_gen_board() -> Node:
	var board = load("res://scripts/JobBoard.gd").new()
	root.add_child(board)
	board.generation_enabled = true
	board.rotate_day(1)
	return board


func _test_board_carryover() -> void:
	var board = await _fresh_gen_board()
	var ids_d1: Array[String] = []
	for s in board.available_summaries():
		ids_d1.append(s["id"])
	_ok(ids_d1.size() == 8, "generated board fills to capacity")

	# Same-day re-rotation replays; nothing expires against its own day.
	var again: Array = board.rotate_day(1)
	_ok(again.is_empty(), "no expiry rolling into the offer day itself")

	# Hand-built controlled queue: 2 expiring + 1 calm, all offered day 1.
	board._queue.clear()
	board._queue.append(_hand_job("H-RUSH", true, false, 1))
	board._queue.append(_hand_job("H-COMP", false, true, 1))
	board._queue.append(_hand_job("H-CALM", false, false, 1))
	_ok(board.expiring_count(2) == 2, "expiring_count counts overnight offers")
	_ok(board.expiring_count(1) == 0, "expiring_count is 0 against today")

	var expired: Array = board.rotate_day(2)
	var expired_ids: Array[String] = []
	for c in expired:
		expired_ids.append(c.id)
	_ok(expired_ids.size() == 2 and "H-RUSH" in expired_ids and "H-COMP" in expired_ids,
		"rotate_day returns exactly the expired offers")
	var kept: Array[String] = []
	for s in board.available_summaries():
		kept.append(s["id"])
	_ok(kept[0] == "H-CALM", "calm job carries over and keeps its place")
	_ok(board.get_available_count() == 8, "board refills to capacity after expiry")
	var fresh_ok := false
	for s in board.available_summaries():
		if str(s["id"]).begins_with("G-2-"):
			fresh_ok = true
	_ok(fresh_ok, "fresh day-2 deals replace the expired offers")

	# Fixture mode: rotate_day stays a no-op and reports nothing.
	var fixture_board = load("res://scripts/JobBoard.gd").new()
	root.add_child(fixture_board)
	_ok(fixture_board.rotate_day(3).is_empty(), "fixture mode never expires")
	fixture_board.queue_free()
	board.queue_free()
	await physics_frame


func _test_reserve_seam() -> void:
	var board = await _fresh_gen_board()
	board._queue.clear()
	board._queue.append(_hand_job("R-A", false, false, 1))
	board._queue.append(_hand_job("R-B", false, false, 1))
	board._queue.append(_hand_job("R-C", false, false, 1))
	_ok(board.front_id() == "R-A", "front_id reads the queue head")
	_ok(board.rotate_to_front(board._queue[2]), "rotate_to_front finds the job")
	_ok(board.front_id() == "R-C", "reserved job now fronts the queue")
	_ok(board._queue[1].id == "R-A" and board._queue[2].id == "R-B",
		"reserve preserves the tail order")
	_ok(not board.rotate_to_front(_hand_job("GHOST", false, false, 1)),
		"rotate_to_front rejects a job that is not queued")
	var taken: Contract = board.take_next()
	_ok(taken.id == "R-C", "take_next serves the reserved job first")
	board.queue_free()
	await physics_frame


func _test_board_persistence() -> void:
	# Full-board roundtrip: a live 8-job board reproduces EXACTLY.
	var board = await _fresh_gen_board()
	var snap_full: Dictionary = board.snapshot_payload()
	var board2 = load("res://scripts/JobBoard.gd").new()
	root.add_child(board2)
	board2.generation_enabled = true
	board2.rotate_day(7)
	_ok(board2.restore_payload(snap_full), "restore_payload accepts a good snapshot")
	var ids: Array[String] = []
	for s in board2.available_summaries():
		ids.append(s["id"])
	var orig_ids: Array[String] = []
	for s in board.available_summaries():
		orig_ids.append(s["id"])
	_ok(str(ids) == str(orig_ids), "full-board restore reproduces ids and order")
	_ok(board2._gen_day == 1 and board2._fixture_cycle == 8,
		"restored day and deal-cycle counters match")
	var cont: Contract = board2.take_next()
	_ok(cont.id == orig_ids[0], "restored board serves in order")
	_ok(board2._queue[board2._queue.size() - 1].id == Contract.generate(1, 8).id,
		"post-take refill continues the persisted cycle (no duplicates)")

	# Partial snapshot (live boards are always full, but be defensive): the
	# restored jobs keep their places at the front and the top-up continues
	# from the persisted cycle counter.
	board._queue.clear()
	board._queue.append(_hand_job("S-A", true, false, 1))
	board._queue.append(_hand_job("S-B", false, true, 3))
	board._queue.append(_hand_job("S-C", false, false, 2))
	board._fixture_cycle = 41
	var snap: Dictionary = board.snapshot_payload()
	_ok(snap["day"] == 1 and snap["cycle"] == 41 and snap["jobs"].size() == 3,
		"snapshot_payload carries day, cycle and every queued job")
	var board3 = load("res://scripts/JobBoard.gd").new()
	root.add_child(board3)
	board3.generation_enabled = true
	_ok(board3.restore_payload(snap), "partial restore accepted")
	var ids3: Array[String] = []
	for s in board3.available_summaries():
		ids3.append(s["id"])
	_ok(ids3.size() == 8 and ids3[0] == "S-A" and ids3[1] == "S-B" and ids3[2] == "S-C",
		"restored jobs keep the front of the queue")
	_ok(board3._queue[3].id == Contract.generate(1, 41).id,
		"top-up continues the persisted cycle (no duplicate deals)")
	_ok(board3._queue[7].id == Contract.generate(1, 45).id,
		"top-up deals cycle slots in order")
	_ok(board3.take_next().id == "S-A", "restored board serves in order")
	var sb: Dictionary = board3.snapshot_payload()
	_ok(sb["jobs"][0]["id"] == "S-B", "re-snapshot reflects the mutated queue")

	# JSON round-trip (ints become floats) must still restore.
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap_full))
	var board4 = load("res://scripts/JobBoard.gd").new()
	root.add_child(board4)
	board4.generation_enabled = true
	_ok(board4.restore_payload(parsed), "restore survives a JSON round-trip")
	_ok(board4.front_id() == orig_ids[0], "JSON-restored queue keeps order")

	# Garbage never mutates the board.
	for bad in [{}, {"day": 1, "cycle": 0}, {"day": 1, "cycle": 0, "jobs": "nope"},
			{"day": 0, "cycle": 0, "jobs": []},
			{"day": 1, "cycle": -1, "jobs": []},
			{"day": 1, "cycle": 0, "jobs": [{"id": "X"}]},
			{"day": 1, "cycle": 0, "jobs": [{"id": "X", "client": "c",
				"model_name": "m", "payout_cents": 0, "material_cost_cents": 1,
				"difficulty": 2, "risk_flags": [], "layers": 10,
				"deadline_days": 1, "rush": false, "competing": false,
				"offered_day": 1, "color": ""}]}]:
		if board4.restore_payload(bad):
			_ok(false, "restore rejects %s" % str(bad))
	_ok(board4.front_id() == orig_ids[0], "rejected restores leave the queue untouched")

	for b in [board, board2, board3, board4]:
		b.queue_free()
	await physics_frame


## --- SaveSystem level ------------------------------------------------------------

func _test_save_validation() -> void:
	var board = load("res://scripts/JobBoard.gd").new()
	root.add_child(board)
	board.generation_enabled = true
	board.rotate_day(2)
	var payload := {
		"version": 1,
		"balance_cents": 100,
		"ledger": {"balance_cents": 100, "transactions": [
			{"id": 1, "reason": "open", "delta_cents": 100, "balance_after": 100},
		], "paid_contract_ids": [], "next_seq": 1},
		"active_contract": {},
		"paid_ids": [],
		"board": board.snapshot_payload(),
		"stats": {"delivered": 1, "missed": 3},
	}
	_ok(not SaveSystem.validate(payload).is_empty(), "payload with board + missed validates")
	var roundtrip: Dictionary = SaveSystem.validate(JSON.parse_string(JSON.stringify(payload)))
	_ok(not roundtrip.is_empty(), "board payload validates after JSON round-trip")

	var bad := payload.duplicate(true)
	bad["board"]["jobs"][0]["difficulty"] = 9
	_ok(SaveSystem.validate(bad).is_empty(), "board job with difficulty 9 rejected")

	bad = payload.duplicate(true)
	bad["board"]["jobs"][0]["color"] = "Neon"
	_ok(SaveSystem.validate(bad).is_empty(), "board job with unknown color rejected")

	bad = payload.duplicate(true)
	bad["board"].erase("cycle")
	_ok(SaveSystem.validate(bad).is_empty(), "board missing cycle rejected")

	bad = payload.duplicate(true)
	bad["board"]["jobs"][0]["competing"] = "yes"
	_ok(SaveSystem.validate(bad).is_empty(), "board job with non-bool competing rejected")

	bad = payload.duplicate(true)
	bad["stats"]["missed"] = -1
	_ok(SaveSystem.validate(bad).is_empty(), "negative missed stat rejected")

	var legacy := payload.duplicate(true)
	legacy.erase("board")
	legacy["stats"] = {"delivered": 1}
	_ok(not SaveSystem.validate(legacy).is_empty(), "pre-v0.14 payloads still validate")
	board.queue_free()
	await physics_frame


## --- Main level -------------------------------------------------------------------

func _test_main_integration() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Seed a controlled board: 2 expiring + 1 calm, offered today.
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand_job("M-RUSH", true, false, 1))
	main.job_board._queue.append(_hand_job("M-COMP", false, true, 1))
	main.job_board._queue.append(_hand_job("M-CALM", false, false, 1))

	main._update_hud()
	_ok("2 expire overnight" in main._status.text,
		"HUD counts offers that expire overnight")

	var chalk: Label3D = null
	for child in main.get_children():
		if child is Label3D and child.position.x < -3.3 and absf(child.position.z - 0.7) < 0.1:
			chalk = child
	main._update_hud()
	_ok(chalk != null and "Missed: 0" in chalk.text, "chalkboard shows the Missed counter")

	var rep_before: float = main.reputation
	main._on_day_changed(2)
	_ok(absf(main.reputation - (rep_before - 0.2)) < 0.001,
		"rollover charges -0.1 rep per expired offer")
	_ok(int(main.stats.missed) == 2, "rollover counts missed offers")
	_ok("Missed 2 board jobs" in str(main._prompt.text),
		"rollover prompt names the missed jobs")
	var kept_ids: Array[String] = []
	for s in main.job_board.available_summaries():
		kept_ids.append(s["id"])
	_ok(kept_ids[0] == "M-CALM", "calm offer carried through the live rollover")

	# Reserve through the real handler; contracts panel re-renders reserved.
	main._on_menu_reserve("M-CALM")
	_ok(main.job_board.front_id() == "M-CALM", "reserve handler fronts the job")
	main.main_menu.open_menu()
	main._on_menu_contracts()
	var cards: Array = main.main_menu.contract_cards()
	var first_card: PanelContainer = cards[0]
	_ok(bool(first_card.get_meta("reserved", false)), "front card flagged reserved")
	var reserve_btn: Button = first_card.find_child("Reserve", true, false)
	_ok(reserve_btn != null and reserve_btn.disabled, "reserved card's button is disabled")
	_ok(cards.size() == 8, "contracts panel renders the full board")
	main.main_menu.close_menu()

	# The persisted save carries the board.
	main._save_game()
	var payload: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(payload.has("board") and payload["board"]["jobs"].size() == 8,
		"save payload includes the board queue")
	_ok(int(payload["stats"].get("missed", -1)) == 2, "save payload includes missed stat")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


## --- Menu level -------------------------------------------------------------------

func _test_menu_reserve_cards() -> void:
	var menu = load("res://scripts/MainMenu.gd").new()
	root.add_child(menu)
	var summaries: Array[Dictionary] = []
	summaries.append({
		"id": "K-1", "client": "A / B", "model_name": "Part one",
		"payout_cents": 5000, "difficulty": 2, "risk_flags": [],
		"rush": true, "deadline_days": 1, "color": "Clay", "competing": true,
		"reserved": false,
	})
	summaries.append({
		"id": "K-2", "client": "C / D", "model_name": "Part two",
		"payout_cents": 4200, "difficulty": 1, "risk_flags": [],
		"rush": false, "deadline_days": 4, "color": "Sage", "competing": false,
		"reserved": true,
	})
	var got := []
	menu.reserve_pressed.connect(func(id: String) -> void: got.append(id))
	menu.show_contracts(summaries)
	var cards: Array = menu.contract_cards()
	_ok(cards.size() == 2, "menu renders both cards")
	var comp_tag: Label = cards[0].find_child("CompetingTag", true, false)
	_ok(comp_tag != null and "2 waiting" in comp_tag.text,
		"competing card shows the [2 waiting] tag")
	var rush_tag: Label = cards[0].find_child("RushTag", true, false)
	_ok(rush_tag != null, "rush tag still renders alongside competing")
	var btn1: Button = cards[0].find_child("Reserve", true, false)
	var btn2: Button = cards[1].find_child("Reserve", true, false)
	_ok(not btn1.disabled, "unreserved card offers Reserve")
	_ok(btn2.disabled and btn2.text.contains("Reserved"),
		"reserved card shows the reserved state")
	btn1.pressed.emit()
	_ok(got == ["K-1"], "Reserve button emits reserve_pressed with the job id")
	menu.queue_free()
	await physics_frame

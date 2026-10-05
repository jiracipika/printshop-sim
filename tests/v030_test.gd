extends SceneTree

## v0.30.0 — "Customer voices & shop history": flavor notes on job cards,
## a 7-day earnings sparkline on the chalkboard. Run:
## timeout 180 godot --headless --path . -s tests/v030_test.gd

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
	_test_notes()
	await _test_history()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_notes() -> void:
	# Determinism: every pinned field is unchanged, notes are the last draw.
	var a := Contract.generate(5, 3)
	var b := Contract.generate(5, 3)
	_ok(a.note == b.note and a.payout_cents == b.payout_cents
		and a.parts_total == b.parts_total and a.model_name == b.model_name,
		"generation stays fully deterministic")
	var notes_valid := true
	var with_note := 0
	for day in range(1, 13):
		for slot in range(0, 6):
			var c := Contract.generate(day, slot)
			if c.note != "" and not Contract.GEN_NOTES.has(c.note):
				notes_valid = false
			if c.note != "":
				with_note += 1
	_ok(notes_valid, "generated notes come from the flavor table")
	_ok(with_note >= 15 and with_note <= 60,
		"~45 pct of generated jobs carry a note (%d/72)" % with_note)
	# Fixtures: two hand-written notes.
	var fixtures := Contract.make_fixture_jobs()
	var fixture_notes := 0
	for c in fixtures:
		if c.note != "":
			fixture_notes += 1
	_ok(fixture_notes == 2, "two fixture jobs carry hand-written notes")
	# Notes ride summaries, persistence, and old saves restore bare.
	var board = load("res://scripts/JobBoard.gd").new()
	board.generation_enabled = true
	board.rotate_day(4, false)
	var carried := false
	for sm in board.available_summaries():
		if str(sm.get("note", "")) != "":
			carried = true
	_ok(carried, "board summaries carry the note")
	var snap: Dictionary = board.snapshot_payload()
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var board2 = load("res://scripts/JobBoard.gd").new()
	board2.generation_enabled = true
	_ok(board2.restore_payload(round_trip), "notes survive the JSON round-trip")
	var match_notes := true
	for i in range(board._queue.size()):
		if str(board._queue[i].note) != str(board2._queue[i].note):
			match_notes = false
	_ok(match_notes, "restored notes match the dealt board")
	var bare: Dictionary = snap.jobs[0].duplicate()
	bare.erase("note")
	var board3 = load("res://scripts/JobBoard.gd").new()
	board3.generation_enabled = true
	_ok(board3.restore_payload({"day": snap.day, "cycle": snap.cycle, "jobs": [bare]})
		and str(board3._queue[0].note) == "",
		"pre-v0.30 payloads restore with no note")

	# The card renders the note in quotes.
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.job_board._queue.clear()
	main.job_board._queue.append(board._queue[0].duplicate())
	main._on_menu_contracts()
	await physics_frame
	var note_label: Label = main.main_menu._contracts_panel.find_child(
		"NoteTag", true, false)
	_ok(note_label != null
		and str(note_label.text).contains(str(board._queue[0].note)),
		"the card shows the client's note in quotes")
	main.queue_free()
	await physics_frame


func _test_history() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Rollover banks the day's take and resets it.
	main.day_earned_today = 1230
	main._on_day_changed(main.day_cycle.day + 1)
	_ok(main.daily_earned == [1230] and main.day_earned_today == 0,
		"rollover banks the day's earnings")
	# Eight days caps the window at 7.
	for i in range(8):
		main.day_earned_today = 100 * (i + 1)
		main._on_day_changed(main.day_cycle.day + 1)
	_ok(main.daily_earned.size() == 7 and int(main.daily_earned[0]) == 200,
		"history keeps the last 7 days (first is %d)" % int(main.daily_earned[0]))
	# The sparkline renders on the chalkboard.
	main._update_chalkboard()
	_ok(main._chalk_label.text.contains("Last days: ")
		and main._chalk_label.text.contains("█"),
		"the chalkboard draws the sparkline")
	_ok(not main._chalk_label.text.contains("No history yet"),
		"populated history replaces the placeholder")
	# Persistence round-trip.
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(saved.get("daily_earned", []).size() == 7
		and int(saved.get("day_earned_today", -1)) == 0,
		"history persists in the save")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2.daily_earned.size() == 7,
		"history survives the reload")
	main2._update_chalkboard()
	_ok(main2._chalk_label.text.contains("Last days: "),
		"the reloaded chalkboard still draws the sparkline")
	main2.queue_free()
	await physics_frame

	# Validator: junk is rejected outright.
	var bad := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "daily_earned": [1, -5]}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad).is_empty(),
		"validator rejects a negative history entry")
	var bad2 := {"version": 9, "balance_cents": 0, "ledger": {"balance_cents": 0,
		"transactions": [], "paid_contract_ids": [], "next_seq": 1},
		"paid_ids": [], "day_earned_today": 1.5}
	_ok(load("res://scripts/SaveSystem.gd").validate(bad2).is_empty(),
		"validator rejects a fractional daily total")

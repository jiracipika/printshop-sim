extends SceneTree

## v0.49.0 — "Customer voices II": expanded note pools (praise/neutral/
## worried/loyalty/generic) plus a first-visit voice for clients with no
## history. Loyalty and grade reactions keep precedence. Run:
## godot --headless --path . -s tests/v049_test.gd

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


func _notes_in(main) -> Array:
	var out: Array = []
	for c in main.job_board._queue:
		out.append(str(c.note))
	return out


func _run() -> void:
	BrowserSave.clear()
	var jb = load("res://scripts/JobBoard.gd")
	var ct = load("res://scripts/Contract.gd")

	# Pool sizes + hygiene: every line real, no duplicates anywhere.
	var pools := {
		"praise": jb.REACTION_PRAISE, "neutral": jb.REACTION_NEUTRAL,
		"worried": jb.REACTION_WORRIED, "loyalty": jb.LOYALTY_NOTES,
		"first": jb.FIRST_NOTES, "generic": ct.GEN_NOTES,
	}
	var min_sizes := {"praise": 8, "neutral": 6, "worried": 6,
		"loyalty": 10, "first": 6, "generic": 20}
	for key in pools:
		var pool: Array = pools[key]
		_ok(pool.size() >= int(min_sizes[key]),
			"%s pool expanded (%d lines)" % [key, pool.size()])
		var seen := {}
		var clean := true
		for line in pool:
			var s := str(line)
			if s.is_empty() or s != s.strip_edges() or seen.has(s):
				clean = false
			seen[s] = true
		_ok(clean, "%s pool lines are non-empty, trimmed, unique" % key)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	# Fresh boot (no regulars, no grades): first-visit voice fills the
	# board, and every stamped note comes from a known pool.
	main.job_board.regulars = {}
	main.job_board.client_grades = {}
	var known := {}
	for key in pools:
		for line in pools[key]:
			known[str(line)] = true
	var first_seen := {}
	var all_clean := true
	for day in range(1, 5):
		main.job_board.deal_day(day)
		for c in main.job_board._queue:
			var s := str(c.note)
			if s.is_empty():
				continue
			if not known.has(s):
				all_clean = false
			if jb.FIRST_NOTES.has(s):
				first_seen[s] = true
	_ok(all_clean, "every stamped note comes from a known pool")
	_ok(first_seen.size() >= 2,
		"first-visit voice appears with variety (%d distinct)" % first_seen.size())

	# Loyalty precedence: a 2+ regular only ever writes loyalty lines.
	# Deal day 1 first and pick its own client — lineups are pinned per
	# (day, slot), so the re-deal below regenerates the same faces.
	main.job_board.regulars = {}
	main.job_board.client_grades = {}
	main.job_board.deal_day(1)
	var first_client: String = str(main.job_board._queue[0].client)
	main.job_board.regulars = {first_client: 3}
	main.job_board.deal_day(1)
	var loyal_ok := true
	var loyal_hits := 0
	for c in main.job_board._queue:
		if str(c.client) == first_client:
			loyal_hits += 1
			if not jb.LOYALTY_NOTES.has(str(c.note)):
				loyal_ok = false
	_ok(loyal_hits >= 1, "the picked regular actually deals (%d jobs)" % loyal_hits)
	_ok(loyal_ok, "a regular's jobs carry loyalty notes only")

	# Grade reactions keep second precedence: an A client praises, a D
	# client worries — and never drifts into the other pools.
	var second_client := ""
	for c in main.job_board._queue:
		if str(c.client) != first_client:
			second_client = str(c.client)
			break
	main.job_board.regulars = {}
	main.job_board.client_grades = {second_client: "A"}
	main.job_board.deal_day(1)
	var praise_ok := true
	for c in main.job_board._queue:
		if str(c.client) == second_client and not jb.REACTION_PRAISE.has(str(c.note)):
			praise_ok = false
	_ok(praise_ok, "an A-grade client's jobs carry praise notes")
	main.job_board.client_grades = {second_client: "D"}
	main.job_board.deal_day(1)
	var worry_ok := true
	for c in main.job_board._queue:
		if str(c.client) == second_client and not jb.REACTION_WORRIED.has(str(c.note)):
			worry_ok = false
	_ok(worry_ok, "a D-grade client's jobs carry worry notes")

	# Determinism: re-dealing the same day reproduces the same notes.
	main.job_board.regulars = {}
	main.job_board.client_grades = {}
	main.job_board.deal_day(2)
	var notes_a: Array = _notes_in(main)
	main.job_board.deal_day(2)
	var notes_b: Array = _notes_in(main)
	_ok(notes_a == notes_b, "re-dealing a day reproduces the same notes")

	# Generic pool reachability: over a week of fresh boards, several
	# generic lines survive the first-visit draw.
	var gen_seen := {}
	for day in range(1, 7):
		main.job_board.deal_day(day)
		for c in main.job_board._queue:
			if ct.GEN_NOTES.has(str(c.note)):
				gen_seen[str(c.note)] = true
	_ok(gen_seen.size() >= 3,
		"generic notes stay reachable (%d distinct)" % gen_seen.size())

	# Persistence: the stamped queue round-trips the save wholesale.
	main.job_board.deal_day(3)
	var notes_before: Array = _notes_in(main)
	main._save_game()
	var saved_notes: Array = (BrowserSave.load_payload().get("board", {}).get("jobs", []))
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	var notes_after: Array = _notes_in(main2)
	_ok(notes_after == notes_before, "restored boot reproduces the board's notes")
	_ok(saved_notes.size() == notes_before.size(),
		"board payload carries one entry per queued job")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

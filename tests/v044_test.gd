extends SceneTree

## v0.44.0 — "stale offers": a calm offer nobody took within three shop days
## rotates off the board silently at rollover (no rep hit, no missed stat —
## only rush/competing expiry penalises). Without it a board full of declined
## work could never refresh (refills only fire when a job is taken), which
## starved tier-4 farms whose player avoids the difficulty-4/5 jobs — the
## tests/sim_lategame.gd conservative-picker run sat at zero intake from day
## 5 with a board frozen at {4:7, 5:2} while rent kept charging.
## Run: timeout 180 godot --headless --path . -s tests/v044_test.gd

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


func _fresh_gen_board() -> Node:
	var board = load("res://scripts/JobBoard.gd").new()
	root.add_child(board)
	board.generation_enabled = true
	board.rotate_day(1)
	return board


func _run() -> void:
	BrowserSave.clear()
	# Await each phase: these are coroutines (they await physics_frame), and
	# an un-awaited call suspends at its first await, letting quit() race the
	# pending continuations — the Main-level checks would silently never run.
	await _test_stale_rotation()
	await _test_lifespan()
	await _test_silent_at_rollover()
	await _test_restore_keeps_stale()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## A stale calm offer rotates off WITH the expiry machinery run but is NOT
## reported as expired, and the board backfills to capacity with fresh deals.
func _test_stale_rotation() -> void:
	var board = await _fresh_gen_board()
	board._queue.clear()
	board._queue.append(_hand_job("ST-OLD", false, false, 1))
	board._queue.append(_hand_job("ST-KEEP", false, false, 2))
	board._queue.append(_hand_job("ST-RUSH", true, false, 1))
	board._queue.append(_hand_job("ST-COMP", false, true, 1))
	board._fixture_cycle = 41

	var expired: Array = board.rotate_day(4)
	var expired_ids: Array[String] = []
	for c in expired:
		expired_ids.append(c.id)
	_ok(expired_ids.size() == 2 and "ST-RUSH" in expired_ids
		and "ST-COMP" in expired_ids,
		"only rush/competing offers report as expired")
	_ok(not "ST-OLD" in expired_ids, "the stale calm offer is not an expiry")

	var ids: Array[String] = []
	var fresh := 0
	var oldest := 99
	for c in board._queue:
		ids.append(c.id)
		oldest = mini(oldest, int(c.offered_day))
		if str(c.id).begins_with("G-4-"):
			fresh += 1
	_ok(not "ST-OLD" in ids, "the stale calm offer rotated off")
	_ok("ST-KEEP" in ids, "the two-day-old offer survives (cut is offered <= day-3)")
	_ok(board._queue.size() == 8, "board backfills to capacity after retirement")
	_ok(fresh == 7, "retired + expired slots refill with fresh day-4 deals (got %d)" % fresh)
	_ok(oldest >= 2, "nothing older than the survivor remains (oldest offered day %d)" % oldest)
	board.queue_free()
	await physics_frame


## Exactly STALE_MORNINGS days of board life: a day-2 offer survives the
## day-3 and day-4 rollovers (2 > day-3 both times) and rotates off on the
## day-5 morning (2 <= 5 - 3).
func _test_lifespan() -> void:
	var board = await _fresh_gen_board()
	board._queue.clear()
	board._queue.append(_hand_job("LF-JOB", false, false, 2))
	board._fixture_cycle = 61
	board.rotate_day(3, false)
	var here := false
	for c in board._queue:
		if c.id == "LF-JOB":
			here = true
	_ok(here, "day-2 offer survives the day-3 rollover")
	board.rotate_day(4, false)
	here = false
	for c in board._queue:
		if c.id == "LF-JOB":
			here = true
	_ok(here, "day-2 offer survives the day-4 rollover")
	board.rotate_day(5, false)
	here = false
	for c in board._queue:
		if c.id == "LF-JOB":
			here = true
	_ok(not here, "day-2 offer rotates off on the day-5 morning")
	board.queue_free()
	await physics_frame


## Main level: retirement charges nothing — reputation and the missed stat
## stay put while the board still refills at the current tier terms.
func _test_silent_at_rollover() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	main.job_board._queue.clear()
	main.job_board._queue.append(_hand_job("SL-OLD", false, false, 1))
	main.job_board._fixture_cycle = 81

	var rep_before: float = main.reputation
	var missed_before: int = int(main.stats.missed)
	main._on_day_changed(4)
	_ok(absf(main.reputation - rep_before) < 0.001,
		"stale retirement never touches reputation")
	_ok(int(main.stats.missed) == missed_before,
		"stale retirement never counts as missed")
	_ok(main.job_board._queue.size() == 8, "the board still backfills to capacity")
	var stale_left := 0
	for c in main.job_board._queue:
		if int(c.offered_day) <= 1:
			stale_left += 1
	_ok(stale_left == 0, "the stale offer is gone from the live board")
	main.queue_free()
	await physics_frame


## Retirement is a rollover behavior, not a restore behavior: a save/reload
## mid-day still reproduces the exact board, stale offers included (v0.14
## persistence semantics unchanged).
func _test_restore_keeps_stale() -> void:
	var board = await _fresh_gen_board()
	board._queue.clear()
	board._queue.append(_hand_job("RS-OLD", false, false, 1))
	board._fixture_cycle = 41
	var snap: Dictionary = board.snapshot_payload()

	var board2 = load("res://scripts/JobBoard.gd").new()
	root.add_child(board2)
	board2.generation_enabled = true
	_ok(board2.restore_payload(snap), "restore accepts the stale-board snapshot")
	var found := false
	for c in board2._queue:
		if c.id == "RS-OLD":
			found = true
	_ok(found, "restore_payload keeps an offer rollover would have retired")
	board.queue_free()
	board2.queue_free()
	await physics_frame

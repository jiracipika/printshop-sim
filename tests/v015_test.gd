extends SceneTree

## v0.15.0 — "The workshop log": ring buffer + failure causes. Run:
## timeout 120 godot --headless --path . -s tests/v015_test.gd
##
## Covers: WorkshopLog append order/cap/snapshot/restore (incl. JSON),
## PrintSim failure_cause for seeded + risk-driven failures, Main event hooks
## (deliver/fail/rent/expired), the Log menu panel, save persistence, and
## SaveSystem validation of the "log" key.

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
	_test_log_unit()
	_test_failure_causes()
	await _test_main_hooks()
	await _test_menu_log_panel()
	_test_save_validation()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- WorkshopLog unit ----------------------------------------------------------

func _test_log_unit() -> void:
	var log := WorkshopLog.new()
	_ok(log.count() == 0 and log.entries().is_empty(), "new log is empty")

	# Order: entries oldest-first, seq strictly increasing, day stamped.
	log.append("delivered", "part one", 2)
	log.append("rent", "rent paid $9.00", 3)
	log.append("failed", "part two — support collapse at layer 12", 3)
	var es: Array[Dictionary] = log.entries()
	_ok(es.size() == 3 and es[0]["seq"] == 1 and es[2]["seq"] == 3,
		"entries append in order with seq")
	_ok(es[0]["day"] == 2 and es[1]["day"] == 3, "day stamps preserved")
	_ok(es[1]["text"] == "rent paid $9.00" and es[2]["kind"] == "failed",
		"kind/text round-trip verbatim")

	# Cap: oldest dropped at 30.
	for i in range(37):
		log.append("event", "filler %d" % i, 4)
	_ok(log.count() == WorkshopLog.CAP, "log caps at %d" % WorkshopLog.CAP)
	var tail: Array[Dictionary] = log.entries()
	_ok(tail[0]["text"] == "filler 7", "oldest entries dropped past the cap")
	_ok(tail[tail.size() - 1]["text"] == "filler 36", "newest entry kept")
	_ok(log.latest(2)[0]["text"] == "filler 35", "latest(n) slices newest n")

	# Snapshot/restore roundtrip preserves the buffer exactly.
	var snap: Array = log.snapshot()
	var log2 := WorkshopLog.new()
	_ok(log2.restore(snap), "restore accepts a snapshot")
	_ok(str(log2.entries()) == str(log.entries()), "restored buffer matches")

	# JSON round-trip (ints become floats).
	var parsed: Variant = JSON.parse_string(JSON.stringify({"log": snap}))
	var log3 := WorkshopLog.new()
	_ok(log3.restore(parsed["log"]), "restore survives JSON round-trip")
	_ok(log3.count() == WorkshopLog.CAP and log3.entries()[0]["text"] == "filler 7",
		"JSON-restored buffer matches")

	# Over-cap restore keeps only the newest CAP.
	var long_data: Array = []
	for i in range(45):
		long_data.append({"seq": i + 1, "day": 1, "kind": "event", "text": "e%d" % i})
	var log4 := WorkshopLog.new()
	_ok(log4.restore(long_data) and log4.count() == WorkshopLog.CAP,
		"over-cap restore keeps 30")
	_ok(log4.entries()[0]["text"] == "e15", "over-cap restore keeps the NEWEST 30")

	# Garbage never mutates.
	var before: String = str(log4.entries())
	for bad in ["nope", 7, [1, 2], [{"seq": 1, "day": 1, "kind": "", "text": "x"}],
			[{"seq": 1, "day": 0, "kind": "k", "text": "x"}],
			[{"seq": "one", "day": 1, "kind": "k", "text": "x"}],
			[{"day": 1, "kind": "k", "text": "x"}],
			[{"seq": 1, "day": 1, "kind": 5, "text": "x"}]]:
		if log4.restore(bad):
			_ok(false, "restore rejects %s" % str(bad))
	_ok(str(log4.entries()) == before, "rejected restores leave the log untouched")

	log.clear()
	_ok(log.count() == 0, "clear empties the log")


## --- PrintSim failure causes ----------------------------------------------------

func _test_failure_causes() -> void:
	# Seeded failure: worst risk names the cause.
	var sim := PrintSim.new()
	sim.support_need = 0.8
	sim.adhesion_risk = 0.2
	sim.stability_risk = 0.1
	sim.failure_seeded = true
	sim.start_job("cause-seeded", "Seeded part", 100)
	while sim.state == PrintSim.State.RUNNING:
		sim.tick(1.0)
	_ok(sim.state == PrintSim.State.DONE_FAIL, "seeded print fails")
	_ok(sim.failure_cause == "support collapse at layer 50",
		"seeded failure names the worst risk + layer (got %r)" % sim.failure_cause)

	# Risk-driven failure: huge threshold guarantees the roll lands.
	var sim2 := PrintSim.new()
	sim2.support_need = 0.1
	sim2.adhesion_risk = 0.9
	sim2.stability_risk = 0.2
	sim2.failure_threshold = 10.0
	sim2.start_job("cause-risk", "Risky part", 80)
	while sim2.state == PrintSim.State.RUNNING:
		sim2.tick(1.0)
	_ok(sim2.state == PrintSim.State.DONE_FAIL, "risk-driven print fails")
	_ok(sim2.failure_cause.begins_with("came off the bed at layer "),
		"adhesion failure names the bed (got %r)" % sim2.failure_cause)

	var sim3 := PrintSim.new()
	sim3.support_need = 0.1
	sim3.adhesion_risk = 0.1
	sim3.stability_risk = 0.95
	sim3.failure_threshold = 10.0
	sim3.start_job("cause-topple", "Tall part", 60)
	while sim3.state == PrintSim.State.RUNNING:
		sim3.tick(1.0)
	_ok(sim3.failure_cause.begins_with("part toppled at layer "),
		"stability failure names the topple (got %r)" % sim3.failure_cause)

	# Clean success leaves no cause; reset clears it.
	var sim4 := PrintSim.new()
	sim4.support_need = 0.0
	sim4.adhesion_risk = 0.0
	sim4.stability_risk = 0.0
	sim4.start_job("cause-clean", "Safe part", 30)
	while sim4.state == PrintSim.State.RUNNING:
		sim4.tick(1.0)
	_ok(sim4.state == PrintSim.State.DONE_OK and sim4.failure_cause == "",
		"successful print records no cause")
	sim4.reset()
	_ok(sim4.failure_cause == "" and sim4.state == PrintSim.State.IDLE,
		"reset clears failure state")


## --- Main event hooks -------------------------------------------------------------

func _test_main_hooks() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	_ok(main.workshop_log != null and main.workshop_log.count() == 0,
		"fresh shop starts with an empty log")

	# Failure hook: seed a mid-print failure and read the cause back.
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null, "job accepted for the log test")
	c.color = str(main._machine(0).get("color"))
	var sim0: PrintSim = main._machine(0).get("sim")
	sim0.support_need = 0.7
	sim0.failure_seeded = true
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	while sim0.is_running():
		sim0.tick(1.0)
	_ok(sim0.state == PrintSim.State.DONE_FAIL, "print failed as seeded")
	var entries: Array[Dictionary] = main.workshop_log.entries()
	var fail_lines: Array[String] = []
	for e in entries:
		if str(e["kind"]) == "failed":
			fail_lines.append(str(e["text"]))
	# The prep evaluation overwrites the sim risks from the contract's flags,
	# so pin the FORMAT, not which risk won.
	_ok(fail_lines.size() == 1 and " at layer " in fail_lines[0]
		and ("support collapse" in fail_lines[0] or "came off the bed" in fail_lines[0]
			or "part toppled" in fail_lines[0]),
		"log records the failure with its cause")

	# Clear the failed bed, then run a clean delivery through the same machine.
	main._try_interact()  # clear failed
	main._try_interact()  # accept next job
	var c2: Contract = main._machine(0).get("contract")
	_ok(c2 != null, "second job accepted")
	c2.color = str(main._machine(0).get("color"))
	var sim2: PrintSim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	# The prep evaluation writes the contract's real risks (and restores the
	# failure threshold), and failure_seeded persists across reset() by design
	# (the debug panel seeds "next print fails") — cancel BOTH failure paths:
	# this delivery print must complete for the log assertion.
	sim2._failure_tick = -1
	sim2.failure_seeded = false
	while sim2.is_running():
		sim2.tick(1.0)
	main._try_interact()  # collect
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()  # deliver
	var deliv: Array[String] = []
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "delivered":
			deliv.append(str(e["text"]))
	_ok(deliv.size() == 1 and c2.model_name in deliv[0] and "$" in deliv[0],
		"log records the delivery with payout")

	# Rollover: rent + expired entries land in order.
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand("L-RUSH", true, false, 1))
	main._on_day_changed(2)
	var kinds: Array[String] = []
	for e in main.workshop_log.entries():
		kinds.append(str(e["kind"]))
	_ok("rent" in kinds, "rent logged at rollover")
	_ok("expired" in kinds, "expired offer logged at rollover")
	_ok(kinds.find("expired") < kinds.find("rent"),
		"entries stay in append order (expiry logged before rent)")

	# Persist: save carries the log; a fresh Main restores it. Freeze the
	# shop first: milestone toasts (v0.21) save on their own while the
	# physics loop is still running, which would mutate the file after the
	# snapshot and shift the expected count.
	main.paused = true
	main._save_game()
	var payload: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(payload.has("log") and payload["log"].size() >= 4,
		"save payload carries the log (got %d entries)" % payload.get("log", []).size())
	main.queue_free()
	await physics_frame

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(main2.workshop_log.count() == payload["log"].size(),
		"restored shop replays the log exactly")
	var restored_kinds: Array[String] = []
	for e in main2.workshop_log.entries():
		restored_kinds.append(str(e["kind"]))
	_ok("failed" in restored_kinds and "delivered" in restored_kinds
		and "rent" in restored_kinds, "restored log keeps the event kinds")
	main2.queue_free()
	await physics_frame
	BrowserSave.clear()


func _hand(id: String, rush: bool, competing: bool, offered: int) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Log test"
	c.model_name = "Log part %s" % id
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


## --- Log menu panel ----------------------------------------------------------------

func _test_menu_log_panel() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	main.main_menu.open_menu()
	_ok(not main.main_menu.subpanel_open(), "main panel has no subpanel open")
	main._on_menu_log()
	_ok(main.main_menu.subpanel_open(), "log panel opens as a subpanel")
	var body_lines: Array = main.main_menu.get_node("Root/LogPanel/Sheet/SheetBox/Scroll/List").get_children()
	_ok(body_lines.size() == 1 and "Nothing in the log yet" in body_lines[0].text,
		"empty log explains itself")
	main.main_menu.open_menu()
	_ok(not main.main_menu.subpanel_open(), "open_menu steps back out of the log")

	# Populated log renders newest-first with day stamps.
	main.workshop_log.append("delivered", "older delivery", 1)
	main.workshop_log.append("failed", "newer failure — toppled", 2)
	main._on_menu_log()
	body_lines = main.main_menu.get_node("Root/LogPanel/Sheet/SheetBox/Scroll/List").get_children()
	_ok(body_lines.size() == 2, "log lines render one per entry")
	_ok("newer failure" in body_lines[0].text and "older delivery" in body_lines[1].text,
		"newest entry renders at the top")
	_ok("Day 2" in body_lines[0].text, "lines carry the day stamp")
	var hot: Label = body_lines[0]
	_ok(hot.get_theme_color("font_color") == main.main_menu.COLOR_TERRA,
		"failure lines read terracotta")
	var calm: Label = body_lines[1]
	_ok(calm.get_theme_color("font_color") == main.main_menu.COLOR_PAPER,
		"delivery lines read paper")

	# The Log button is wired to the same panel.
	main.main_menu.open_menu()
	var log_btn: Button = main.main_menu.get_node("Root/Layout/Buttons/Log")
	_ok(log_btn != null, "Log button exists on the main panel")
	log_btn.pressed.emit()
	_ok(main.main_menu.subpanel_open() and main.main_menu._log_open,
		"Log button opens the log panel")
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


## --- SaveSystem validation ----------------------------------------------------------

func _test_save_validation() -> void:
	var base := {
		"version": 1,
		"balance_cents": 100,
		"ledger": {"balance_cents": 100, "transactions": [
			{"id": 1, "reason": "open", "delta_cents": 100, "balance_after": 100},
		], "paid_contract_ids": [], "next_seq": 1},
		"active_contract": {},
		"paid_ids": [],
		"log": [
			{"seq": 1, "day": 1, "kind": "rent", "text": "rent paid $9.00"},
			{"seq": 2, "day": 2, "kind": "delivered", "text": "hook — grade A, $40.00"},
		],
	}
	_ok(not SaveSystem.validate(base).is_empty(), "payload with log validates")
	var rt: Dictionary = SaveSystem.validate(JSON.parse_string(JSON.stringify(base)))
	_ok(not rt.is_empty(), "log payload validates after JSON round-trip")

	for mutate in [
		func(p: Dictionary) -> void: p["log"] = "nope",
		func(p: Dictionary) -> void: p["log"][0].erase("kind"),
		func(p: Dictionary) -> void: p["log"][0]["kind"] = 5,
		func(p: Dictionary) -> void: p["log"][0]["day"] = 0,
		func(p: Dictionary) -> void: p["log"][0]["day"] = 1.5,
		func(p: Dictionary) -> void: p["log"][0]["seq"] = "one",
		func(p: Dictionary) -> void: p["log"][0]["text"] = 9,
	]:
		var bad: Dictionary = base.duplicate(true)
		mutate.call(bad)
		if not SaveSystem.validate(bad).is_empty():
			_ok(false, "log mutation rejected (%s)" % str(bad.get("log")))
	_ok(true, "all malformed log payloads rejected")

	var legacy: Dictionary = base.duplicate(true)
	legacy.erase("log")
	_ok(not SaveSystem.validate(legacy).is_empty(), "payloads without log still validate")

extends SceneTree

## v0.11.0 — seasons, chalkboard, same-day tips. Run:
##   timeout 90 godot --headless --path . -s tests/v011_test.gd

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
	_test_seasons()
	await _test_season_effects()
	await _test_tip_and_chalkboard()
	_finish(1 if failures > 0 else 0)


func _test_seasons() -> void:
	# Week 1 always calm; deterministic otherwise; every id occurs.
	var w1: Dictionary = Events.season_for_week(1)
	_ok(str(w1.id) == "calm" and int(w1.extra_rent_cents) == 0
		and float(w1.payout_mult) == 1.0, "week 1 is calm")
	_ok(Events.season_for_week(3).id == Events.season_for_week(3).id,
		"season_for_week is deterministic")
	var seen := {}
	for w in range(2, 40):
		var e: Dictionary = Events.season_for_week(w)
		_ok_soft(e.has("id") and e.has("name") and e.has("adhesion_delta")
			and e.has("extra_rent_cents") and e.has("payout_mult"),
			"week %d season well-formed" % w)
		seen[str(e.id)] = true
	_ok(seen.has("humid") and seen.has("cold_snap") and seen.has("boom"),
		"all season ids occur within 40 weeks")
	_ok(absf(float(Events._season_by_id("humid").adhesion_delta) - 0.05) < 0.0001,
		"humid: adhesion +0.05")
	_ok(int(Events._season_by_id("cold_snap").extra_rent_cents) == 100,
		"cold snap: rent +$1/day")
	_ok(absf(float(Events._season_by_id("boom").payout_mult) - 1.10) < 0.0001,
		"boom: payouts x1.10")


var _soft := 0

func _ok_soft(cond: bool, label: String) -> void:
	if not cond:
		_soft += 1
		if _soft <= 3:
			printerr("FAIL (soft) %s" % label)


func _test_season_effects() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger_credit(main, 30000)
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)
	main._machine(0)["filament_g"] = 5000

	# Boom week: payout multiplied by the season on top of the event.
	main.season = Events._season_by_id("boom")
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null, "boom section: job accepted")
	if c == null:
		_finish(1)
		return
	c.color = str(main._machine(0).get("color"))  # no color cap in this test
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._try_interact()  # collect
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	var base := roundi(c.payout_cents * QualityCheck.quality_multiplier(
		main._cap_grade_for_color("A", c, main._machine(0))))
	var expected: int = main._finalize_payout(base, false, main._machine(0))
	var bal0: int = ledger.balance()
	main._try_interact()  # deliver
	_ok(ledger.balance() == bal0 + expected,
		"boom + same-day tip paid through _finalize_payout ($%s)" % main._cents_str(expected))
	_ok(expected > roundi(roundi(base * main.reputation_multiplier())
		* float(main.today_event.payout_mult)),
		"season and tip both lift the payout above the plain path")

	# Humid week: prep evaluation carries the adhesion delta.
	main.season = Events._season_by_id("humid")
	var job: Contract = main.job_board.take_next()
	var eval: Dictionary = main._prep_eval(job, "upright")
	var plain: Dictionary = PrepSystem.evaluate(job, "upright")
	_ok(absf(float(eval.adhesion_risk) - clampf(float(plain.adhesion_risk) + 0.05, 0.0, 1.0)) < 0.0001,
		"humid season adds +0.05 adhesion risk to the prep eval")

	# Cold snap: rent rises to $5/day at rollover within a cold week.
	var cold_week := -1
	for w in range(2, 40):
		var day_in_week: int = (w - 1) * 7 + 7
		if str(Events.season_for_week(w).id) == "cold_snap" \
				and not bool(Events.for_day(day_in_week).rent_free):
			cold_week = w
			break
	_ok(cold_week > 0, "a non-holiday cold-snap week exists")
	if cold_week > 0:
		main.day_cycle.day = (cold_week - 1) * 7 + 6  # last day of the cold week
		main._refresh_event()
		var bal1: int = ledger.balance()
		main.day_cycle.tick(main.day_cycle.day_length_s)  # rolls within the week
		_ok(int(main.season.extra_rent_cents) == 100, "cold-snap season active after rollover")
		_ok(ledger.balance() == bal1 - 500, "cold-snap rent is $5.00")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()

	if _soft > 0:
		failures += _soft


func ledger_credit(main, cents: int) -> void:
	main.ledger.credit(cents, "test funds")


func _test_tip_and_chalkboard() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger_credit(main, 30000)
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)

	# Chalkboard exists and updates after a delivery.
	var board: Label3D = null
	for child in main.get_children():
		if child is Label3D and child.position.x < -3.3 and absf(child.position.z - 0.7) < 0.1:
			board = child
	_ok(board != null, "chalkboard label exists on the left wall")
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	c.color = str(main._machine(0).get("color"))
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._try_interact()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()  # deliver same day
	main._update_hud()
	_ok(board != null and "Delivered: 1" in board.text and "Day 1" in board.text,
		"chalkboard reflects the delivery live")
	_ok("Same-day tip" in str(main._prompt.text), "HUD celebrates the same-day tip")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

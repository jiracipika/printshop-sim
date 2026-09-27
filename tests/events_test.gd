extends SceneTree

## v0.7.0 — daily shop events. Run:
##   timeout 90 godot --headless --path . -s tests/events_test.gd

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
	_test_event_table()
	await _test_event_effects()
	await _test_hud_and_crate()
	_finish(1 if failures > 0 else 0)


func _test_event_table() -> void:
	# Day 1 is always quiet.
	var d1: Dictionary = Events.for_day(1)
	_ok(str(d1.id) == "quiet" and float(d1.payout_mult) == 1.0
		and int(d1.spool_price_cents) == 1200 and not bool(d1.rent_free),
		"day 1 opens quiet with standard prices")
	_ok(Events.for_day(1).id == Events.for_day(1).id, "for_day is deterministic")

	# Same day -> same event; every id appears in a bounded range.
	var seen: Dictionary = {}
	for d in range(2, 60):
		var e: Dictionary = Events.for_day(d)
		_ok_soft(e.has("id") and e.has("name") and e.has("spool_price_cents")
			and e.has("payout_mult") and e.has("failure_delta") and e.has("rent_free"),
			"day %d event well-formed" % d)
		if Events.for_day(d).id != e.id:
			_ok(false, "day %d event not deterministic" % d)
		seen[str(e.id)] = true
	_ok(seen.has("filament_sale") and seen.has("rush_week")
		and seen.has("power_hiccup") and seen.has("rent_holiday") and seen.has("quiet"),
		"all five event ids occur within 60 days (%d seen)" % seen.size())
	_ok(Events.all_ids_seen_within(60), "all_ids_seen_within agrees")

	# Each special event's parameters.
	_ok(Events._by_id("filament_sale").spool_price_cents == 800
		and float(Events._by_id("filament_sale").payout_mult) == 1.0,
		"filament sale: spools $8, payouts normal")
	_ok(absf(float(Events._by_id("rush_week").payout_mult) - 1.25) < 0.0001,
		"rush week: payouts x1.25")
	_ok(absf(float(Events._by_id("power_hiccup").failure_delta) - 0.10) < 0.0001,
		"power hiccup: failure threshold +0.10")
	_ok(bool(Events._by_id("rent_holiday").rent_free), "rent holiday is rent-free")

	# Days before 1 clamp to quiet day 1.
	_ok(str(Events.for_day(0).id) == "quiet" and str(Events.for_day(-5).id) == "quiet",
		"non-positive days clamp to quiet")


var _soft_failures := 0

## Well-formedness across ~58 days: counted separately so the suite stays
## readable; a handful of malformed days would still fail the suite.
func _ok_soft(cond: bool, label: String) -> void:
	if not cond:
		_soft_failures += 1
		if _soft_failures <= 3:
			printerr("FAIL (soft) %s" % label)


func _test_event_effects() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(30000, "test funds")
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)
	main._machine(0)["filament_g"] = 5000

	# Filament sale: the crate charges the event price.
	main.today_event = Events._by_id("filament_sale")
	var bal0: int = ledger.balance()
	main._player.global_position = Vector3(-3.0, 0.3, 2.1)
	main._try_interact()
	_ok(ledger.balance() == bal0 - 800, "spool bought at the sale price ($8)")

	# Rush week: payout multiplied by the event.
	main.today_event = Events._by_id("rush_week")
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	if c != null:
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		var s0: PrintSim = main._machine(0).get("sim")
		while s0.is_running():
			s0.tick(1.0)
		main._try_interact()  # collect
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		var grade := QualityCheck.grade(c, s0.layers_done, s0.layers_total,
			{"support_need": s0.support_need, "adhesion_risk": s0.adhesion_risk,
			"stability_risk": s0.stability_risk})
		var expected: int = roundi(roundi(roundi(c.payout_cents
			* QualityCheck.quality_multiplier(grade)) * main.reputation_multiplier()) * 1.25)
		var bal1: int = ledger.balance()
		main._try_interact()  # deliver
		_ok(ledger.balance() == bal1 + expected,
			"rush-week delivery pays x1.25 ($%s)" % main._cents_str(expected))

	# Power hiccup: confirm writes the raised failure threshold.
	main.today_event = Events._by_id("power_hiccup")
	main._machine(0)["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c2: Contract = main._machine(0).get("contract")
	if c2 != null:
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		_ok(absf(main.sim.failure_threshold - 0.65) < 0.0001,
			"power hiccup raises the failure threshold to 0.65")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()

	if _soft_failures > 0:
		failures += _soft_failures


func _test_hud_and_crate() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# HUD shows the Today line; day 1 quiet.
	main.paused = false
	main.captured = true
	main._update_hud()
	_ok("Today: Quiet day" in main._status.text, "HUD shows the quiet-day line")

	# A sale day updates both the HUD line and the crate's price tag.
	# Find a real filament-sale day and drive the true refresh path.
	var sale_day := -1
	for d in range(2, 60):
		if str(Events.for_day(d).id) == "filament_sale":
			sale_day = d
			break
	_ok(sale_day > 0, "a filament-sale day exists within 60 days")
	main.day_cycle.day = sale_day
	main._refresh_event()
	main._update_hud()
	_ok("Today: Filament sale" in main._status.text, "HUD shows the sale")
	_ok("$8" in str(main._crate_label.text), "crate sign shows the sale price")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

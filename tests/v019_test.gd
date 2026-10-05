extends SceneTree

## v0.19.0 — "Reputation tiers": board difficulty gates + rush premiums per
## tier, once-per-threshold announcements, achievements, Stats panel lines.
## Run: timeout 120 godot --headless --path . -s tests/v019_test.gd

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
	_test_tier_tables()
	_test_generation_caps()
	await _test_tier_announcements()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- tier tables --------------------------------------------------------------------

func _test_tier_tables() -> void:
	_ok(Events.tier_for_rep(0.0) == 1 and Events.tier_for_rep(2.99) == 1,
		"below 3.0 is tier 1")
	_ok(Events.tier_for_rep(3.0) == 2 and Events.tier_for_rep(3.49) == 2,
		"3.0..3.49 is tier 2")
	_ok(Events.tier_for_rep(3.5) == 3 and Events.tier_for_rep(4.24) == 3,
		"3.5..4.24 is tier 3")
	_ok(Events.tier_for_rep(4.25) == 4 and Events.tier_for_rep(5.0) == 4,
		"4.25+ is tier 4")
	for t in range(1, 5):
		_ok(Events.tier_max_difficulty(t) == t + 1,
			"tier %d caps jobs at difficulty %d" % [t, t + 1])
	_ok(absf(Events.tier_rush_mult(1) - 1.0) < 1e-6
		and absf(Events.tier_rush_mult(2) - 1.1) < 1e-6
		and absf(Events.tier_rush_mult(3) - 1.2) < 1e-6
		and absf(Events.tier_rush_mult(4) - 1.3) < 1e-6,
		"rush premium scales +10 pct per tier")
	_ok(Events.TIER_NAMES.size() == 5 and Events.TIER_NAMES[4] == "Top of the market",
		"tier names table complete")


## --- generation caps ------------------------------------------------------------------

func _test_generation_caps() -> void:
	# Default generate() is untouched: with no cap argument, values match a
	# pinned pair exactly across the cap parameter's absence.
	var plain := Contract.generate(5, 3)
	var explicit := Contract.generate(5, 3, 5)
	_ok(plain.difficulty == explicit.difficulty
		and plain.payout_cents == explicit.payout_cents
		and plain.model_name == explicit.model_name,
		"default generate is unchanged by the cap parameter")
	# Sweeps: capped generation never exceeds the cap (and the rng stream is
	# consumed identically, so payouts stay pinned per slot).
	var all_within := true
	for cap in [2, 3, 4]:
		for day in range(1, 9):
			for slot in range(0, 6):
				if Contract.generate(day, slot, cap).difficulty > cap:
					all_within = false
	_ok(all_within, "capped generation respects every difficulty cap")

	# Board deal terms: deal_day caps the queue and bumps rush payouts.
	var board = load("res://scripts/JobBoard.gd").new()
	board.generation_enabled = true
	board.deal_day(3, 2, 1.1)
	var cap_ok := true
	var rush_seen := 0
	for c in board._queue:
		if c.difficulty > 2:
			cap_ok = false
		if c.rush:
			rush_seen += 1
			if c.payout_cents > 9500:
				cap_ok = false
	_ok(cap_ok and board._queue.size() > 0,
		"tier-2 deal: queue capped at difficulty 2, rush payouts legal")
	# Rush payouts scale by exactly the tier multiplier; calm jobs unchanged.
	var bump_ok := true
	for c in board._queue:
		if c.featured:
			continue  # the featured pick carries its own +15% (v0.42)
		var slot := int(str(c.id).get_slice("-", 2))
		var base := Contract.generate(3, slot, 2)
		if c.rush:
			if c.payout_cents != mini(roundi(float(base.payout_cents) * 1.1), 9500):
				bump_ok = false
		elif c.payout_cents != base.payout_cents:
			bump_ok = false
	_ok(bump_ok, "rush payouts scale by the tier multiplier, calm payouts unchanged")

	# rotate_day accepts tier updates for the morning deal.
	board.rotate_day(4, false, 4, 1.2)
	var cap4 := true
	for c in board._queue:
		if c.difficulty > 4:
			cap4 = false
	_ok(cap4, "rotate_day re-deals at the updated tier cap")


## --- live announcements ----------------------------------------------------------------

func _stats_text(main) -> String:
	main._on_menu_stats()
	return main.main_menu._stats_panel.get_node("Sheet/SheetBox/Body").text


func _test_tier_announcements() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Fresh shop at 3.0 stars starts AT tier 2 — no pending announcement.
	_ok(main.announced_tier == 2, "fresh shop adopts its starting tier silently")
	_ok(main.job_board._deal_cap == 3 and absf(main.job_board._deal_rush_mult - 1.1) < 1e-6,
		"boot board dealt at tier-2 terms")

	# Crossing 3.5 announces exactly once, logs, and persists.
	main.reputation = 3.4
	main._rep_event(0.2)
	_ok(main.announced_tier == 3, "crossing 3.5 bumps the high-water mark")
	var tier_logs := 0
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "tier" and "buzzing" in str(e["text"]):
			tier_logs += 1
	_ok(tier_logs == 1, "tier-up logged exactly once")
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(int(saved.get("tier_announced", 0)) == 3, "high-water mark persists")

	# Rep drops and re-crosses: still exactly one announcement for tier 3.
	main._rep_event(-0.5)
	main._rep_event(0.3)
	_ok(main.announced_tier == 3, "re-crossing a announced tier stays silent")
	var tier_logs2 := 0
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "tier":
			tier_logs2 += 1
	_ok(tier_logs2 == 1, "no duplicate tier lines in the log")

	# Crossing 4.25 announces tier 4 once.
	main.reputation = 4.2
	main._rep_event(0.1)
	_ok(main.announced_tier == 4, "crossing 4.25 reaches the top tier")
	var tier_logs3 := 0
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "tier":
			tier_logs3 += 1
	_ok(tier_logs3 == 2, "one announcement per threshold, ever")

	# Achievements at the thresholds.
	main.reputation = 3.5
	var names := {}
	for a in main._achievements():
		names[a.name] = bool(a.done)
	_ok(names.has("Board regular") and names["Board regular"],
		"Board regular unlocks at 3.5")
	_ok(not names["Top of the market"], "Top of the market still locked at 3.5")
	main.reputation = 4.25
	for a in main._achievements():
		names[a.name] = bool(a.done)
	_ok(names["Top of the market"], "Top of the market unlocks at 4.25")

	# Stats panel shows the tier and the next unlock.
	main.reputation = 3.6
	var text := _stats_text(main)
	_ok(text.contains("Trusted studio") and text.contains("difficulty 4"),
		"stats panel names the current tier and its terms")
	_ok(text.contains("Top of the market") and text.contains("4.25"),
		"stats panel shows the next unlock")
	main.reputation = 4.5
	text = _stats_text(main)
	_ok(text.contains("Top tier reached"), "top tier says so")

	# Rollover deals at the CURRENT tier: at 4.5 stars refills go to 5.
	main.reputation = 4.5
	main._on_day_changed(main.day_cycle.day + 1)
	var capped_low := false
	for c in main.job_board._queue:
		if str(c.id).begins_with("G-") and c.difficulty < 1:
			capped_low = true
	_ok(not capped_low, "rollover deals legal jobs at the current tier")
	_ok(main.job_board._deal_cap == 5 and absf(main.job_board._deal_rush_mult - 1.3) < 1e-6,
		"rollover adopted top-tier deal terms")

	main.queue_free()
	await physics_frame

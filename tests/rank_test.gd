extends SceneTree

## v0.61.0 — "Shop rank career": five DERIVED levels (Sprout/Staple/Known/
## Fixture/Institution) off lifetime delivered + rep high-water, +2%/level
## payout tail at the very END of _finalize_payout, once-per-level gold
## toast + "rank" log entry + chalkboard header line, a Stats RANK block and
## three new milestones. Run:
## godot --headless --path . -s tests/rank_test.gd

const TOTAL := 33

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _rank_log_count(main) -> int:
	var n := 0
	for e in main.workshop_log.entries():
		if str(e.kind) == "rank":
			n += 1
	return n


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	print("%d checks defined" % TOTAL)
	BrowserSave.clear()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	# --- A. the derived level table -------------------------------------------
	# A fresh shop derives L1: zero delivered (the rep bar 3.0 is already met
	# by the opening standing — delivered is what keeps it at Sprout).
	_ok(main.shop_rank_level() == 1 and main.RANK_NAMES[0] == "Sprout"
		and main.announced_rank == 1 and absf(main.rank_payout_mult() - 1.0) < 0.0001,
		"a fresh shop is L1 Sprout at x1.00 and never announced")
	# Boundaries 14/15, 39/40, 79/80, 149/150 on delivered; exact rep bars
	# count as the higher level (tier_for_rep's >= rule).
	main.stats["delivered"] = 14
	main.rep_high_water = 5.0
	_ok(main.shop_rank_level() == 1, "14 delivered is L1 even at a 5.0 high-water")
	main.stats["delivered"] = 15
	main.rep_high_water = 3.0
	_ok(main.shop_rank_level() == 2 and main.RANK_NAMES[1] == "Staple",
		"15 delivered + exactly 3.0 high-water is L2 Staple")
	main.rep_high_water = 2.99
	_ok(main.shop_rank_level() == 1, "3.0 minus a hair drops back to L1")
	main.stats["delivered"] = 39
	main.rep_high_water = 3.5
	_ok(main.shop_rank_level() == 2, "39 delivered is L2 even at the 3.5 bar")
	main.stats["delivered"] = 40
	_ok(main.shop_rank_level() == 3 and main.RANK_NAMES[2] == "Known",
		"40 delivered + exactly 3.5 high-water is L3 Known")
	main.stats["delivered"] = 79
	main.rep_high_water = 4.0
	_ok(main.shop_rank_level() == 3, "79 delivered is L3 even at the 4.0 bar")
	main.stats["delivered"] = 80
	_ok(main.shop_rank_level() == 4 and main.RANK_NAMES[3] == "Fixture",
		"80 delivered + exactly 4.0 high-water is L4 Fixture")
	main.stats["delivered"] = 149
	main.rep_high_water = 4.5
	_ok(main.shop_rank_level() == 4, "149 delivered is L4 even at the 4.5 bar")
	main.stats["delivered"] = 150
	_ok(main.shop_rank_level() == 5 and main.RANK_NAMES[4] == "Institution",
		"150 delivered + exactly 4.5 high-water is L5 Institution")

	# --- B. payout math through the documented chain ---------------------------
	# Controlled contract: calm season, quiet day, not late, no same-day tip
	# (m carries day 0 so days_taken = 1), rep passed explicitly as the
	# MULTIPLIER 0.88 (the rep>=0 branch takes a multiplier — v0.32 rule).
	# Chain: 1000 x 0.88 = 880 at L1; the rank factor lands LAST.
	main.season = Events.CALM_SEASON.duplicate(true)
	main.today_event = Events.QUIET.duplicate(true)
	var m := {"day": 0}
	main.stats["delivered"] = 0
	_ok(main._finalize_payout(1000, false, m, 0.88) == 880,
		"L1 base: $10.00 x 0.88 rep pays 880 cents exactly")
	main.stats["delivered"] = 15
	main.rep_high_water = 3.0
	_ok(main._finalize_payout(1000, false, m, 0.88) == 898,
		"L2 appends x1.02: 880 -> roundi(897.6) = 898")
	main.stats["delivered"] = 40
	main.rep_high_water = 3.5
	_ok(main._finalize_payout(1000, false, m, 0.88) == 915,
		"L3 = base x 1.04 composed after every other factor: roundi(915.2) = 915")
	main.stats["delivered"] = 80
	main.rep_high_water = 4.0
	_ok(main._finalize_payout(1000, false, m, 0.88) == 933,
		"L4 appends x1.06: roundi(932.8) = 933")
	main.stats["delivered"] = 150
	main.rep_high_water = 4.5
	_ok(main._finalize_payout(1000, false, m, 0.88) == 950,
		"L5 appends x1.08: roundi(950.4) = 950")
	# Walk-in + rank pinned exactly: counter premium x1.10 FIRST, rank x1.04
	# LAST. 1010 x 0.88 = 888.8 -> 889; x1.10 = 977.9 -> 978; x1.04 = 1017.12
	# -> 1017. (The reverse order would round to 1018.)
	main.stats["delivered"] = 40
	main.rep_high_water = 3.5
	_ok(main._finalize_payout(1010, false, m, 0.88, true) == 1017,
		"counter premium x1.10 lands before the L3 x1.04: 1017 exactly")
	# Shelf bonus composes before rank: 880 -> shelf x1.02 -> 898 -> L3
	# x1.04 -> roundi(933.92) = 934.
	main._shelf_models.assign(["Moss terrarium"])
	_ok(main._finalize_payout(1000, false, m, 0.88) == 934,
		"shelf bonus x1.02 lands before the L3 x1.04: 934 exactly")
	main._shelf_models.clear()
	# Late half composes before rank: 880 -> x0.5 = 440 -> x1.04 -> 458.
	_ok(main._finalize_payout(1000, true, m, 0.88) == 458,
		"late half lands before the L3 x1.04: 458 exactly")

	# --- C. the announcement lifecycle ------------------------------------------
	main.stats["delivered"] = 15
	main.rep_high_water = 3.0
	main._rep_event(0.0)  # the real trigger site (_rep_event updates the mark)
	_ok(main.announced_rank == 2 and main._toast.text == "Shop rank: Staple"
		and _rank_log_count(main) == 1,
		"crossing L2 announces once: toast + one rank log entry")
	main._update_chalkboard()
	_ok(main._chalk_label.text.contains("SHOP LEDGER\nRANK: Staple"),
		"the chalkboard header carries RANK: Staple")
	# Re-crossing is silent: drop below the bar (the mark survives), climb
	# back through L3 — announce 3, then flip delivered across the L2 gate
	# again: no third entry, no re-announce.
	main._rep_event(-0.6)
	_ok(main.announced_rank == 2 and absf(main.rep_high_water - 3.0) < 0.0001
		and main.shop_rank_level() == 2,
		"the high-water survives a rep drop (level stays L2)")
	main.stats["delivered"] = 40
	main._rep_event(1.5)
	_ok(main.announced_rank == 3 and main._toast.text == "Shop rank: Known"
		and _rank_log_count(main) == 2,
		"crossing L3 announces once more (exactly one entry per level)")
	main.stats["delivered"] = 15
	main.stats["delivered"] = 40
	_ok(main.announced_rank == 3 and _rank_log_count(main) == 2,
		"re-crossing L2/L3 is silent — the mark is once per level, ever")
	# Round-trip: the save carries both keys; a reload adopts silently.
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2.announced_rank == 3 and absf(main2.rep_high_water - 3.9) < 0.0001
		and _rank_log_count(main2) == 2,
		"a reload restores the marks (log rides the ring buffer; no re-log)")
	# Old-save absence: strip both keys from the file; the boot bootstraps the
	# high-water from what is derivable (rep 3.9, board tier 3 -> 3.5 floor)
	# and adopts the derived level as the announcement mark.
	var payload: Dictionary = BrowserSave.load_payload()
	payload.erase("announced_rank")
	payload.erase("rep_high_water")
	BrowserSave.save_payload(payload)
	var main3 = packed.instantiate()
	root.add_child(main3)
	await physics_frame
	_ok(absf(main3.rep_high_water - 3.9) < 0.0001
		and main3.announced_rank == main3.shop_rank_level()
		and main3.announced_rank == 3,
		"a pre-v0.61 save bootstraps the high-water and adopts the level silently")

	# --- D. SaveSystem validators ------------------------------------------------
	var base := {
		"version": 1, "balance_cents": 0,
		"ledger": {"balance_cents": 0, "transactions": [],
			"paid_contract_ids": [], "next_seq": 0},
		"active_contract": {}, "paid_ids": []}
	var good: Dictionary = base.duplicate(true)
	good["announced_rank"] = 3
	good["rep_high_water"] = 4.5
	var vg: Dictionary = SaveSystem.validate(good)
	_ok(not vg.is_empty() and int(vg.announced_rank) == 3
		and absf(float(vg.rep_high_water) - 4.5) < 0.0001,
		"validate accepts announced_rank 1..5 and rep_high_water 0..5")
	var bad_rank: Dictionary = base.duplicate(true)
	bad_rank["announced_rank"] = 6
	_ok(SaveSystem.validate(bad_rank).is_empty(),
		"validate rejects an announced_rank outside 1..5")
	var bad_rep: Dictionary = base.duplicate(true)
	bad_rep["rep_high_water"] = 5.1
	_ok(SaveSystem.validate(bad_rep).is_empty(),
		"validate rejects a rep_high_water outside 0..5")

	# --- E. the three new milestones at their edges -------------------------------
	main3.walkins_served = 9
	var undone := [false, false, false]
	for a in main3._achievements():
		if str(a.name) == "Counter regular":
			undone[0] = not bool(a.done)
	main3.walkins_served = 10
	var done := [false, false, false]
	for a in main3._achievements():
		if str(a.name) == "Counter regular":
			done[0] = bool(a.done)
	_ok(undone[0] and done[0],
		"Counter regular: 9 walk-ins served is undone, 10 is done")
	main3.stats["delivered"] = 79
	main3.rep_high_water = 4.0
	main3.walkins_served = 0
	var face_done := false
	var inst_undone := true
	for a in main3._achievements():
		if str(a.name) == "Face of the street":
			face_done = bool(a.done)
		if str(a.name) == "Institution":
			inst_undone = not bool(a.done)
	_ok(face_done and inst_undone,
		"Face of the street: L4 counts, and L5 does not fire at L4")
	main3.stats["delivered"] = 150
	main3.rep_high_water = 4.5
	for a in main3._achievements():
		if str(a.name) == "Institution":
			inst_undone = not bool(a.done)
	_ok(not inst_undone, "Institution: L5 fires exactly at the L5 gate")

	# --- F. the Stats RANK block ---------------------------------------------------
	main3.stats["delivered"] = 40
	main3.rep_high_water = 3.5
	main3._on_menu_stats()
	await physics_frame
	var body: Label = main3.main_menu._stats_panel.get_node("Sheet/SheetBox/Body")
	_ok(body.text.contains("RANK (v0.61)")
		and body.text.contains("Known — payouts +4%")
		and body.text.contains("Next: Fixture at 80 delivered and 4.00 stars"),
		"the RANK block shows the level, the bonus and the next gate")
	_ok(body.text.find("RANK (v0.61)") > body.text.find("BOARD TIER"),
		"the RANK block sits after the BOARD TIER block")

	main3.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

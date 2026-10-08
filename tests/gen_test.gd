extends SceneTree

## v0.4.0 — procedural contract generation + polish (glow, shadows, vignette,
## how-to panel). Run: timeout 90 godot --headless --path . -s tests/gen_test.gd

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
	_test_generation()
	await _test_board_generation()
	await _test_polish()
	_finish(1 if failures > 0 else 0)


func _test_generation() -> void:
	# Determinism: same (day, slot) -> identical contract.
	var a: Contract = Contract.generate(3, 5)
	var b: Contract = Contract.generate(3, 5)
	_ok(a.id == b.id and a.client == b.client and a.model_name == b.model_name
		and a.payout_cents == b.payout_cents and a.layers == b.layers
		and a.rush == b.rush and a.deadline_days == b.deadline_days
		and a.material_cost_cents == b.material_cost_cents
		and str(a.risk_flags) == str(b.risk_flags),
		"generation is fully deterministic for the same (day, slot)")

	# Validity + playability bounds across a wide sweep.
	var rush_count := 0
	var affordable := true
	for day in range(1, 30):
		for slot in range(8):
			var c: Contract = Contract.generate(day, slot)
			if not c.is_valid():
				_ok(false, "generated %s is_valid()" % c.id)
				_finish(1)
				return
			if c.material_cost_cents > 2400:
				affordable = false
			if c.payout_cents < 3000 or c.payout_cents > 9500:
				_ok(false, "%s payout in range (%d)" % [c.id, c.payout_cents])
			if c.layers < 60 or c.layers > 400:
				_ok(false, "%s layers in range (%d)" % [c.id, c.layers])
			if c.rush:
				rush_count += 1
				if c.deadline_days > 2:
					_ok(false, "rush %s deadline <= 2" % c.id)
			elif c.deadline_days < 2 or c.deadline_days > 6:
				_ok(false, "calm %s deadline in 2-6 (%d)" % [c.id, c.deadline_days])
	_ok(affordable, "materials always <= $24 (affordable on the $25 opening balance)")
	var total := 29 * 8
	var rush_ratio := float(rush_count) / float(total)
	_ok(rush_ratio > 0.05 and rush_ratio < 0.5,
		"rush ratio plausible (%.2f over %d contracts)" % [rush_ratio, total])

	# Rush work pays a premium over the same difficulty's calm base.
	var found_pair := false
	for day in range(1, 30):
		for slot in range(8):
			var c: Contract = Contract.generate(day, slot)
			if c.rush:
				var base: int = Contract.GEN_BASE_PAYOUT[c.difficulty - 1]
				var calm_floor := 1.2  # premium even after layer bonuses differ
				if float(c.payout_cents) >= float(base) * calm_floor:
					found_pair = true
	_ok(found_pair, "rush jobs clear the premium bar")

	# Day 2 board differs from day 1 (fresh offerings each morning).
	var d1_ids: Array[String] = []
	var d2_ids: Array[String] = []
	for slot in range(8):
		d1_ids.append(Contract.generate(1, slot).id)
		d2_ids.append(Contract.generate(2, slot).id)
	_ok(d1_ids[0] != d2_ids[0] or str(d1_ids) != str(d2_ids), "day boards differ")


func _test_board_generation() -> void:
	var board = load("res://scripts/JobBoard.gd").new()
	root.add_child(board)
	# Default: fixture mode (suites depend on it).
	_ok(board.available_summaries()[0]["id"] == "C-014",
		"fixture mode unchanged by default")

	board.generation_enabled = true
	board.rotate_day(1)
	var summaries: Array[Dictionary] = board.available_summaries()
	_ok(summaries.size() == 8, "generated board fills to capacity")
	_ok(str(summaries[0]["id"]).begins_with("G-1-"), "generated ids use G-<day>-<slot>")

	# Same day -> same board; day change -> different board; capacity holds.
	var snapshot_ids: Array[String] = []
	for s in summaries:
		snapshot_ids.append(s["id"])
	board.rotate_day(1)
	var again: Array[String] = []
	for s in board.available_summaries():
		again.append(s["id"])
	_ok(str(again) == str(snapshot_ids), "rotate_day back to the same day replays the same board")

	board.rotate_day(2)
	var day2: Array[String] = []
	for s in board.available_summaries():
		day2.append(s["id"])
	_ok(str(day2) != str(snapshot_ids), "a new day deals a new board")
	_ok(board.get_available_count() == 8, "capacity invariant after rotation")

	# v0.14.0 board pressure: calm jobs carry over; rush/competing expire.
	# Expectation is computed from the generator rather than hardcoded.
	var survivors: Array[String] = []
	for slot in range(8):
		var gc: Contract = Contract.generate(1, slot)
		if not gc.has_expired_for(2):
			survivors.append(gc.id)
	if survivors.is_empty():
		_ok(str(day2[0]).begins_with("G-2-"), "all-expired day-1 board deals day 2 first")
	else:
		_ok(day2[0] == survivors[0], "oldest surviving calm job sits at the front")
		_ok(day2.has(survivors[survivors.size() - 1]), "calm day-1 jobs carry over to day 2")

	# Taking jobs keeps capacity and serves the front of the queue
	# (first come, first served).
	var ids_now: Array[String] = []
	for s in board.available_summaries():
		ids_now.append(s["id"])
	var taken: Contract = board.take_next()
	_ok(taken.id == ids_now[0], "take_next serves the front (first come, first served)")
	_ok(board.get_available_count() == 8, "board tops back up after a take")

	board.queue_free()
	await physics_frame


func _test_polish() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Live shop serves the generated board.
	_ok(str(main.job_board.available_summaries()[0]["id"]).begins_with("G-1-"),
		"Main's live board is generated, not fixtures")

	# Environment polish: glow enabled, sun casts shadows by default.
	var env: Environment = main._env
	_ok(env != null and env.glow_enabled, "glow enabled (Compatibility-safe bloom)")
	var sun: DirectionalLight3D = main._sun
	_ok(sun != null and sun.shadow_enabled, "sun shadows on by default")

	# Quality toggle applies live and persists.
	main.apply_setting("shadows", false, false)
	_ok(not sun.shadow_enabled, "shadows toggle turns shadows off live")
	main.apply_setting("shadows", true, false)
	_ok(sun.shadow_enabled, "shadows toggle turns shadows back on")

	# Vignette overlay present and non-blocking.
	var vignette: TextureRect = main._hud.get_node_or_null("Vignette")
	_ok(vignette != null and vignette.texture != null, "vignette overlay exists")
	_ok(vignette.mouse_filter == Control.MOUSE_FILTER_IGNORE, "vignette never blocks input")

	# How-to panel reachable from the menu and self-contained.
	var menu = main.main_menu
	menu.open_menu()
	menu._show_panel(menu._howto_panel)
	_ok(menu._howto_panel.visible and menu.subpanel_open(), "how-to panel opens as a subpanel")
	var body: Label = menu._howto_panel.get_node("Sheet/SheetBox/Body")
	_ok("PACKING" in body.text and "Rent" in body.text, "how-to explains the loop and the clock")
	menu.open_menu()
	_ok(not menu._howto_panel.visible, "Esc/route back clears the how-to panel")

	# Settings panel carries the shadows checkbox.
	menu.show_settings(main.settings)
	var shadows: CheckBox = menu.get_node("Root/SettingsPanel/Sheet/SheetScroll/SheetBox/ShadowsCheck")
	_ok(shadows.is_pressed(), "settings panel reflects the shadows value")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

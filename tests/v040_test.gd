extends SceneTree

## v0.40.0 — "Grand showcase": the upgrade widens the shelf to 5 models
## (+10% max payout) and unlocks the Curator milestone. Run:
## timeout 180 godot --headless --path . -s tests/v040_test.gd

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
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Before the upgrade: cap is 3.
	_ok(main._shelf_cap() == 3, "base cap is 3 slots")
	# The catalog carries the upgrade at $150.
	var e: Dictionary = Upgrades.entry("grand_showcase")
	_ok(not e.is_empty() and int(e.cost_cents) == 15000,
		"grand showcase in the catalog at $150")

	# Fill 3 through the real display flow.
	var fill := func(id: String, model: String) -> String:
		var after_display := ""
		main.job_board._queue.clear()
		main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
			"id": id, "client": "Gallery", "model_name": model,
			"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
			"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
			"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
			"note": "",
		}))
		main._player.global_position = Vector3(-1.8, 0.3, -1.0)
		await physics_frame
		main._try_interact()
		var s2: PrintSim = main._machine(0).get("sim")
		main._machine(0)["orient"] = 0
		main._machine(0)["orient_pending"] = true
		main._prep_on(0)
		s2._failure_tick = -1
		s2.failure_seeded = false
		while s2.is_running():
			s2.tick(1.0)
		main._try_interact()
		main._player.global_position = Vector3(2.5, 0.3, -2.1)
		await physics_frame
		main._try_interact()
		after_display = main._prompt.text
		main._player.global_position = Vector3(2.0, 0.3, 0.9)
		await physics_frame
		main._try_interact()
		return after_display

	# Base cap: 3 via direct state, then the upgrade widens it to 5.
	main._shelf_models.assign(["Model one", "Model two", "Model three"])
	main._refresh_shelf_slots()
	_ok(main._shelf_cap() == 3 and main.upgrades.is_owned("grand_showcase") == false,
		"base cap is 3 before the upgrade")
	main.ledger.credit(20000, "test funds")
	main._on_menu_upgrade_buy("grand_showcase")
	_ok(main.upgrades.is_owned("grand_showcase"), "grand showcase purchased")
	_ok(main._shelf_cap() == 5, "cap widens to 5")

	# Two more display cycles fill the widened shelf through the real flow.
	await fill.call("G-GS4b", "Model four")
	await fill.call("G-GS5", "Model five")
	_ok(main._shelf_models == ["Model one", "Model two", "Model three",
		"Model four", "Model five"], "5 models displayed")
	var visible_count := 0
	for slot in main._shelf_parts:
		if slot.visible:
			visible_count += 1
	_ok(visible_count == 5, "all five slots lit")

	# Curator milestone + payout cap +10%.
	var curator := false
	for a in main._achievements():
		if a.name == "Curator":
			curator = bool(a.done)
	_ok(curator, "Curator unlocks at 5 models")
	var rep_mult: float = 0.8 + (main.reputation / 5.0) * 0.4
	var want: int = main._finalize_payout(5000, false, main._machine(0), rep_mult)
	# Shelf bonus (+10% at 5 models) plus same-day tip (+10%) inside the
	# chain: ratio vs the bare base is ~1.21.
	_ok(absf(float(want) / 5000.0 / rep_mult - 1.21) < 0.03,
		"payout carries the +10% showcase cap (+10%% same-day tip)")
	_ok(main.upgrades.catalog().size() == 11,
		"the catalog carries 11 upgrades (Fully kitted tracks 11)")

	# Persistence: 5 models survive (the restore guard allows 5).
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(saved.get("shelf_models", []).size() == 5, "5 models persist")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2._shelf_models.size() == 5, "5 models survive the reload")
	main2.queue_free()
	await physics_frame

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

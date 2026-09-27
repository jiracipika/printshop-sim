extends SceneTree

## Task 12 — printer upgrades, settings, and their persistence.
## Run: timeout 60 godot --headless --path . -s tests/upgrades_test.gd

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
	_test_catalog_and_ownership()
	await _test_main_purchase_flow()
	await _test_settings_and_menu()
	_finish(1 if failures > 0 else 0)


func _test_catalog_and_ownership() -> void:
	var ids: Array[String] = []
	for e in Upgrades.catalog():
		ids.append(e.id)
		_ok(int(e.cost_cents) > 0 and str(e.name) != "" and str(e.desc) != "",
			"catalog entry %s well-formed" % e.id)
	_ok(ids.size() == 8 and ids.size() == _unique(ids).size(), "eight unique upgrade ids")

	var up := Upgrades.new()
	_ok(not up.is_owned("heated_bed"), "nothing owned at start")

	# buy() succeeds once, refuses the second time without side effects.
	_ok(up.buy("heated_bed"), "first buy succeeds")
	_ok(not up.buy("heated_bed"), "second buy of same id refused")
	_ok(up.owned_count() == 1 and up.owned_ids() == ["heated_bed"],
		"owned set tracks exactly the bought id")
	_ok(not up.buy(""), "empty id refused")
	_ok(not up.buy("nonexistent"), "unknown id refused")
	_ok(absf(up.speed_multiplier() - 1.0) < 0.0001, "no speed multiplier without extruder upgrade")
	_ok(absf(up.failure_threshold_delta()) < 0.0001, "no threshold delta without nozzle upgrade")
	var mods: Dictionary = up.risk_modifiers()
	_ok(absf(float(mods.adhesion_risk) + 0.15) < 0.0001, "heated bed reduces adhesion risk by 0.15")
	_ok(up.buy("dual_gear") and absf(up.speed_multiplier() - 1.3) < 0.0001,
		"dual gear yields 1.3x speed")
	_ok(up.buy("premium_nozzle") and absf(up.failure_threshold_delta() + 0.12) < 0.0001,
		"premium nozzle lowers failure threshold by 0.12")

	# load_owned restores ids without charging or duplicating.
	var up2 := Upgrades.new()
	_ok(up2.load_owned(["heated_bed", "heated_bed", "bogus", ""]) == 1,
		"load_owned restores valid ids once, skipping junk")
	_ok(up2.is_owned("heated_bed") and up2.owned_count() == 1, "load_owned idempotent")


func _unique(a: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


func _test_main_purchase_flow() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger

	# Upgrade effects reach the sim (fresh shop: none owned).
	_ok(absf(main.sim.speed_multiplier - 1.0) < 0.0001, "fresh sim runs at 1x speed")
	_ok(absf(main.sim.failure_threshold - 0.55) < 0.0001, "fresh sim uses base failure threshold")

	# Cannot buy without funds (drain via the ledger API so the
	# transaction-replay invariant the save validator checks stays intact).
	ledger.charge(ledger.balance(), "test drain")
	var before_txs: int = ledger.transaction_count()
	main._on_menu_upgrade_buy("heated_bed")
	_ok(not main.upgrades.is_owned("heated_bed"), "purchase refused without funds")
	_ok(ledger.transaction_count() == before_txs, "refused purchase logs no transaction")

	# Affordable purchase charges exactly the catalog price, exactly once.
	ledger.credit(5000, "test funds")
	main._on_menu_upgrade_buy("heated_bed")
	_ok(main.upgrades.is_owned("heated_bed"), "purchase registers ownership")
	_ok(ledger.balance() == 2500, "heated bed charged $25.00")
	main._on_menu_upgrade_buy("heated_bed")
	_ok(ledger.balance() == 2500, "double purchase does not double-charge")
	_ok(absf(main.sim.failure_threshold - 0.55) < 0.0001,
		"heated bed alone does not change failure threshold")

	# Risk modifiers flow through the prep evaluation.
	var job: Contract = main.job_board.take_next()
	var eval: Dictionary = main._prep_eval(job, "tilted")
	_ok(absf(float(eval.adhesion_risk) - 0.0) < 0.0001,
		"prep eval with heated bed: tilted adhesion 0.15-0.15")
	_ok(main.upgrades.risk_modifiers().stability_risk == 0.0,
		"stability untouched without frame upgrade")

	# Extruder upgrade accelerates the running sim, not the layer math.
	ledger.credit(4000, "test funds 2")
	main._on_menu_upgrade_buy("dual_gear")
	_ok(absf(main.sim.speed_multiplier - 1.3) < 0.0001, "sim speed multiplier applied to live sim")
	main._accept_print()
	var c: Contract = main.active_contract
	if c != null:
		main.orientation_index = 0
		main.orientation_pending = true
		main._prep_press()
	var t0: int = Time.get_ticks_msec()
	var steps := 0
	while main.sim.is_running() and steps < 200000:
		main.sim.tick(1.0 / 10.0)
		steps += 1
	var elapsed_ms: int = Time.get_ticks_msec() - t0
	_ok(not main.sim.is_running(), "accelerated sim completes")
	_ok(steps == int(c.layers / 1.3) or steps == int(c.layers / 1.3) + 1,
		"speed multiplier reduces tick count by 1/1.3 (steps=%d)" % steps)
	_ok(elapsed_ms < 20000, "accelerated run stays bounded (ms=%d)" % elapsed_ms)

	# Menu upgrades panel renders cards from Main state.
	main.main_menu.open_menu()
	main._on_menu_upgrades()
	var cards: Array = main.main_menu.upgrade_cards_ui()
	_ok(cards.size() == 8, "upgrades panel lists the full catalog")
	var found_owned := false
	for card in cards:
		if card.has_meta("upgrade_id") and str(card.get_meta("upgrade_id")) == "heated_bed" \
				and card.get_meta("owned"):
			found_owned = true
	_ok(found_owned, "owned upgrade card marked Installed")

	main.queue_free()
	await physics_frame


func _test_settings_and_menu() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Settings apply live: sensitivity scales look, volume drives the bus.
	main.apply_setting("mouse_sens_scale", 2.0, false)
	_ok(absf(main._mouse_sens() - 0.0025 * 2.0) < 0.000001, "mouse sens scales with setting")
	main.apply_setting("invert_y", true, false)
	_ok(bool(main.settings.invert_y), "invert_y setting stored")
	main.apply_setting("sfx_volume", 0.5, false)
	_ok(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"sfx bus unmuted at 0.5 volume")
	var db_at_half: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	main.apply_setting("sfx_volume", 0.0, false)
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"sfx bus muted at zero volume")
	main.apply_setting("sfx_volume", 0.8, false)
	_ok(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) > db_at_half,
		"volume raises bus db")

	# Settings panel reflects current values without re-emitting signals.
	var menu = main.main_menu
	menu.open_menu()
	menu.show_settings(main.settings)
	var sens: HSlider = menu.get_node("Root/SettingsPanel/Sheet/SheetBox/SensSliderRow/SensSlider")
	_ok(absf(float(sens.value) - float(main.settings.mouse_sens_scale)) < 0.0001,
		"settings panel shows live sensitivity value")

	# Settings + upgrades persist through the save payload round trip.
	main.apply_setting("mouse_sens_scale", 1.7, true)
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(not payload.is_empty(), "save payload written")
	_ok(payload.has("upgrades"), "payload carries upgrades")
	_ok(payload.upgrades.has("dual_gear") and payload.upgrades.has("heated_bed"),
		"payload carries both bought upgrades")
	_ok(absf(float(payload.settings.mouse_sens_scale) - 1.7) < 0.0001,
		"payload carries sensitivity setting")
	var validated: Dictionary = SaveSystem.validate(payload)
	_ok(not validated.is_empty(), "payload with extras validates")
	_ok(validated.upgrades.has("dual_gear") and validated.upgrades.has("heated_bed"),
		"validated payload carries both bought upgrades")
	var bad: Dictionary = payload.duplicate(true)
	bad.settings.sfx_volume = 7.0
	_ok(SaveSystem.validate(bad).is_empty(), "invalid volume rejects payload")
	bad = payload.duplicate(true)
	bad.upgrades = "heated_bed"
	_ok(SaveSystem.validate(bad).is_empty(), "non-array upgrades reject payload")

	# A fresh Main restores ownership, effects and settings from the save.
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(main2.upgrades.is_owned("heated_bed") and main2.upgrades.is_owned("dual_gear"),
		"fresh Main restores owned upgrades")
	_ok(absf(main2.sim.speed_multiplier - 1.3) < 0.0001, "restored upgrades apply sim effects")
	_ok(absf(float(main2.settings.mouse_sens_scale) - 1.7) < 0.0001,
		"fresh Main restores sensitivity setting")
	main2.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

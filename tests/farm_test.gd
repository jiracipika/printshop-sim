extends SceneTree

## v0.13.0 — the print farm: rear extension, kits A/B, four machines. Run:
##   timeout 90 godot --headless --path . -s tests/farm_test.gd

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
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger
	ledger.credit(60000, "test funds")
	main.paused = false
	main.captured = true
	main.touch_controls.force_enabled = true
	main.touch_controls.set_motion_enabled(true)

	# Boot: four machines, farm ones locked and empty.
	_ok(main.machines.size() == 4, "four machines exist at boot")
	_ok(not main.upgrades.machine_unlocked(2) and not main.upgrades.machine_unlocked(3),
		"farm machines start locked")
	_ok(main._printers[2].is_locked() and main._printers[3].is_locked(),
		"farm printers show LOCKED")
	_ok(int(main._machine(2).get("filament_g")) == 0
		and int(main._machine(3).get("filament_g")) == 0,
		"farm printers ship with no filament")
	_ok(not main._door_body.get_child(0).disabled, "farm door starts sealed")

	# Catalog carries the kits.
	var ids: Array[String] = []
	for e in Upgrades.catalog():
		ids.append(e.id)
	_ok(ids.has("farm_kit_a") and ids.has("farm_kit_b"), "farm kits in the catalog")

	# Kit A: unlock printer 3, open the door, kit B stays locked.
	main._on_menu_upgrade_buy("farm_kit_a")
	_ok(main.upgrades.machine_unlocked(2) and not main.upgrades.machine_unlocked(3),
		"kit A unlocks printer 3 only")
	_ok(not main._printers[2].is_locked() and main._printers[3].is_locked(),
		"printer 3 shows unlocked, printer 4 still locked")
	await physics_frame  # set_deferred applies at end of frame
	_ok(main._door_body.get_child(0).disabled, "door opens with kit A")
	_ok("FARM" in str(main._printers[2]._name_label.text), "printer 3 renamed with FARM tag")

	# Accept + print on printer 3 (load filament first — it ships empty).
	ledger.credit(30000, "test funds 2")
	main._player.global_position = Vector3(-1.8, 0.3, -3.9)
	main._try_interact()
	var c: Contract = main._machine(2).get("contract")
	_ok(c != null, "printer 3 accepts a contract once unlocked")
	if c == null:
		_finish(1)
		return
	main._machine(2)["filament_g"] = 5000
	main._machine(2)["orient"] = 0
	main._machine(2)["orient_pending"] = true
	main._prep_on(2)
	var s2: PrintSim = main._machine(2).get("sim")
	_ok(s2.is_running(), "printer 3 prints")
	_ok(absf(s2.speed_multiplier - 1.0) < 0.0001,
		"farm printers have no speed bonus (pro stays exclusive to printer 2)")

	# Confirm the farm door physically separates: without the kit the accept
	# is refused even standing at printer 4.
	main._player.global_position = Vector3(1.8, 0.3, -3.9)
	main._focus = 3
	var c4_before: int = main.job_board.get_available_count()
	main._try_interact()
	_ok(main._machine(3).get("contract") == null, "locked printer 4 refuses accepts")

	# Kit B: unlock printer 4 and run it in parallel with printer 3.
	ledger.credit(30000, "test funds 3")
	main._on_menu_upgrade_buy("farm_kit_b")
	_ok(main.upgrades.machine_unlocked(3) and not main._printers[3].is_locked(),
		"kit B unlocks printer 4")
	main._machine(3)["filament_g"] = 5000
	main._try_interact()  # accept at printer 4
	var c4: Contract = main._machine(3).get("contract")
	_ok(c4 != null, "printer 4 accepts a contract")
	main._machine(3)["orient"] = 0
	main._machine(3)["orient_pending"] = true
	main._prep_on(3)
	_ok(main._machine(2).get("sim").is_running() and main._machine(3).get("sim").is_running(),
		"farm printers 3 and 4 run in parallel")

	# Filament + color persistence now covers four machines.
	for i in range(4):
		main._machine(i)["filament_g"] = 100 * (i + 1)
	main._machine(0)["color"] = "Sage"
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(payload.filament.size() == 4, "save carries four filament entries")
	_ok(int(payload.filament[3]) == 400, "farm printer filament persisted")
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(int(main2._machine(3).get("filament_g")) == 400
		and str(main2._machine(0).get("color")) == "Sage",
		"fresh Main restores farm printer supplies")

	main.queue_free()
	main2.queue_free()
	await physics_frame
	await physics_frame
	BrowserSave.clear()
	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

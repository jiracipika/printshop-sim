extends SceneTree

## v0.9.0 — guided first-run objectives + reset shop. Run:
##   timeout 90 godot --headless --path . -s tests/guide_test.gd

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
	await _test_guide_chain()
	await _test_reset()
	_finish(1 if failures > 0 else 0)


func _test_guide_chain() -> void:
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

	# Boot: nothing done, HUD shows the first objective.
	main._update_hud()
	_ok("▸ Objective: Accept a job at a printer" in main._status.text,
		"first objective shows at boot")

	# Real loop walk-through advances the chain.
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	_ok(bool(main.guide_flags.accepted), "accepting marks the accept objective")
	main._update_hud()
	_ok("Confirm an orientation" in main._status.text, "HUD advances to the print objective")

	for i in range(3):
		main._machine(0)["orient"] = (int(main._machine(0)["orient"]) + 1) % 3
		main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	_ok(bool(main.guide_flags.printed), "confirming marks the print objective")
	var s0: PrintSim = main._machine(0).get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._try_interact()  # collect
	_ok(bool(main.guide_flags.collected), "collecting marks the collect objective")
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	main._try_interact()  # deliver
	_ok(bool(main.guide_flags.delivered), "delivering marks the deliver objective")

	# Spool load + prototype objectives.
	main._machine(0)["color"] = "Clay"
	var spool: Grabbable = main._make_crate_spool("Clay")
	main.add_child(spool)
	spool.global_position = main._player.global_position + Vector3(0, 1.2, 0)
	main._attach_to_hand(spool)
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()  # load
	_ok(bool(main.guide_flags.loaded), "loading marks the spool objective")

	main._machine(0)["filament_g"] = 5000
	var design: Dictionary = DesignStudio.defaults()
	var grams: int = DesignStudio.estimate_grams(DesignStudio.normalize(design))
	main._on_design_test_print(design)
	_ok(bool(main.guide_flags.prototype), "prototype marks the design objective")

	# Stars objective completes the guide and persists.
	main.reputation = 4.2
	main._guide("stars")
	_ok(main.guide_done, "all objectives done retires the guide")
	main._save_game()
	var payload: Dictionary = BrowserSave.load_payload()
	_ok(bool(payload.guide_done), "guide completion persists")
	_ok(not SaveSystem.validate(payload).is_empty(), "payload with guide keys validates")
	var bad: Dictionary = payload.duplicate(true)
	bad.guide_done = "yes"
	_ok(SaveSystem.validate(bad).is_empty(), "non-bool guide_done rejects the payload")

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(main2.guide_done, "fresh Main restores the retired guide")
	main2._update_hud()
	_ok("▸ Objective" not in main2._status.text, "no objective line after the guide retires")
	main2.queue_free()
	await physics_frame

	# A fresh shop without a save shows the guide again.
	BrowserSave.clear()
	var main3 = packed.instantiate()
	root.add_child(main3)
	await physics_frame
	await physics_frame
	_ok(not main3.guide_done and not bool(main3.guide_flags.accepted),
		"new game starts with the guide active")
	main3.queue_free()
	await physics_frame
	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _test_reset() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var ledger: Ledger = main.ledger

	# Build some state, save it.
	ledger.credit(5000, "test funds")
	main._save_game()
	_ok(not BrowserSave.load_payload().is_empty(), "save exists before reset")

	# Two-press confirm: first press arms, does not wipe.
	main.request_reset_shop()
	_ok(not BrowserSave.load_payload().is_empty(), "first press only arms the reset")
	var reset_btn: Button = main.main_menu.get_node("Root/SettingsPanel/Sheet/SheetScroll/SheetBox/ResetButton")
	_ok("Really reset" in reset_btn.text, "reset button shows the confirm state")

	# Leaving settings disarms.
	main.main_menu.disarm_reset_button()
	_ok("Reset shop (new game)" in reset_btn.text, "disarm restores the button label")
	main.request_reset_shop()
	_ok(not BrowserSave.load_payload().is_empty(), "disarmed press does not wipe")

	# Second armed press wipes the save.
	main.request_reset_shop()
	_ok(BrowserSave.load_payload().is_empty(), "confirmed reset wipes the save")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

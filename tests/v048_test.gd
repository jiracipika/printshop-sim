extends SceneTree

## v0.48.0 — "Rumble settings": persisted haptics strength (0..100) scales
## both rumble magnitudes; the settings sheet gains a slider for it. Run:
## godot --headless --path . -s tests/v048_test.gd

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

	# Default + gain math.
	_ok(int(main.settings.get("haptics_strength", -1)) == 100,
		"strength defaults to 100")
	_ok(is_equal_approx(main.haptics_gain(), 1.0),
		"gain is 1.0 at the default strength")
	main.settings["haptics"] = false
	_ok(main.haptics_gain() == 0.0, "haptics off silences the gain")
	main.settings["haptics"] = true
	main.settings["haptics_strength"] = 40
	_ok(is_equal_approx(main.haptics_gain(), 0.4), "gain 0.4 at strength 40")
	main.settings["haptics_strength"] = 150
	_ok(is_equal_approx(main.haptics_gain(), 1.0), "gain clamps over 100")
	main.settings["haptics_strength"] = -5
	_ok(main.haptics_gain() == 0.0, "gain floors below 0")
	main.settings["haptics_strength"] = 0
	_ok(main.haptics_gain() == 0.0, "strength 0 mutes the pads")
	main.settings["haptics_strength"] = 25.0  # sliders emit whole floats
	_ok(is_equal_approx(main.haptics_gain(), 0.25), "float strengths work")

	# The gated call path stays safe headless (pads absent) in both states.
	main._rumble(0.5, 0.5, 0.1)
	main.settings["haptics_strength"] = 0
	main._rumble(0.5, 0.5, 0.1)
	_ok(true, "_rumble runs safely at gain 0 and 1")

	# Persistence.
	main.settings["haptics_strength"] = 40
	main._save_game()
	var saved: Dictionary = BrowserSave.load_payload()
	_ok(int(saved.get("settings", {}).get("haptics_strength", -1)) == 40,
		"strength persists in the save")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(int(main2.settings.get("haptics_strength", -1)) == 40,
		"strength survives the reload")
	_ok(is_equal_approx(main2.haptics_gain(), 0.4), "gain right after reload")

	# Validators: whole numbers 0..100 only; absence is fine (old saves).
	var ss = load("res://scripts/SaveSystem.gd")
	var no_key: Dictionary = saved.duplicate(true)
	(no_key["settings"] as Dictionary).erase("haptics_strength")
	_ok(not ss.validate(no_key).is_empty(), "payloads without strength validate (old saves)")
	var over: Dictionary = saved.duplicate(true)
	(over["settings"] as Dictionary)["haptics_strength"] = 150
	_ok(ss.validate(over).is_empty(), "validator rejects strength over 100")
	var under: Dictionary = saved.duplicate(true)
	(under["settings"] as Dictionary)["haptics_strength"] = -5
	_ok(ss.validate(under).is_empty(), "validator rejects negative strength")
	var frac: Dictionary = saved.duplicate(true)
	(frac["settings"] as Dictionary)["haptics_strength"] = 40.5
	_ok(ss.validate(frac).is_empty(), "validator rejects fractional strength")
	var text: Dictionary = saved.duplicate(true)
	(text["settings"] as Dictionary)["haptics_strength"] = "loud"
	_ok(ss.validate(text).is_empty(), "validator rejects a text strength")

	# Settings sheet: the slider exists, spans 0..100 in steps of 10, and
	# show_settings pushes the persisted value into it without re-emitting.
	main2.main_menu.open_menu()
	main2.main_menu.show_settings(main2.settings)
	await physics_frame
	var slider: HSlider = main2.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/RumbleSliderRow/RumbleSlider")
	_ok(slider != null, "RumbleSlider exists on the settings sheet")
	_ok(slider.min_value == 0.0 and slider.max_value == 100.0
		and is_equal_approx(slider.step, 10.0),
		"slider spans 0..100 step 10")
	_ok(is_equal_approx(slider.value, 40.0),
		"show_settings pushes the persisted strength into the slider")

	# Dragging the slider applies the setting live (emits -> apply_setting).
	slider.value = 70.0
	await physics_frame
	_ok(int(main2.settings.get("haptics_strength", -1)) == 70,
		"moving the slider applies the strength live")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

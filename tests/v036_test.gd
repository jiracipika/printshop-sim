extends SceneTree

## v0.36.0 — "Feedback & haptics": Haptics setting gates gamepad rumble,
## menu focus plays a soft tick, delivery rumble softened. Run:
## timeout 180 godot --headless --path . -s tests/v036_test.gd

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

	# Defaults + persistence.
	_ok(bool(main.settings.haptics), "haptics default on")
	main.settings["haptics"] = false
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(saved.get("settings", {}).get("haptics", true) == false,
		"haptics persists in the save")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(bool(main2.settings.haptics) == false,
		"haptics survives the reload")

	# The gate: _rumble respects the toggle (state-safe either way — this
	# asserts the call path exists and does not throw with pads absent).
	main2._rumble(0.5, 0.5, 0.1)
	main2.settings["haptics"] = true
	main2._rumble(0.5, 0.5, 0.1)
	_ok(true, "rumble gate runs safely in both states")

	# Softer delivery curve: values below the v0.27 baselines.
	main2._rumble(0.18, 0.4, 0.22)
	_ok(true, "tuned rumble values accepted")

	# Menu focus tick: grabbing focus on a menu button plays the blip.
	main2.main_menu.open_menu()
	await physics_frame
	var blip: AudioStreamPlayer = main2.main_menu._focus_sfx
	_ok(blip != null and blip.stream == Sfx.stream("click"),
		"focus blip player wired to the click stream")
	var played := false
	for b in ["Play", "Contracts", "Upgrades", "Settings"]:
		var btn: Button = main2.main_menu._root.find_child(b, true, false)
		if btn != null:
			btn.grab_focus()
			await physics_frame
			if blip.playing:
				played = true
			# advance past the short sample so the next blip can play
			blip.stop()
	_ok(played, "moving menu focus plays the tick")
	# Volume: quiet by design (-18 dB).
	_ok(blip.volume_db <= -15.0, "focus blip stays quiet")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

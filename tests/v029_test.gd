extends SceneTree

## v0.29.0 — atmosphere & onboarding: snowfall outside cold-snap windows,
## moonlight spilling through the glass at night, and a How-to-play input
## section covering all three input methods. Run:
## timeout 180 godot --headless --path . -s tests/v029_test.gd

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
	main.main_menu.close_menu()
	main.paused = false
	main.captured = true

	# Snow: hidden everywhere except cold-snap weeks.
	_ok(main._snow != null and main._snow.get_child_count() == 12,
		"12 snowflakes built")
	_ok(not main._snow.visible, "calm weeks have no snow")
	main.season = Events._season_by_id("cold_snap")
	main._apply_season_visuals()
	_ok(main._snow.visible and not main._rain.visible,
		"cold snap shows snow, not rain")
	# Flakes fall, sway, and wrap inside the pane.
	var y0: float = (main._snow.get_child(2) as Node3D).position.y
	for i in range(120):
		main._animate_snow(0.016)
	var flake := main._snow.get_child(2) as Node3D
	_ok(flake.position.y < y0 or flake.position.y > 2.0,
		"snow falls (and wraps at the sill)")
	var bounded := true
	for i in range(main._snow.get_child_count()):
		var f2 := main._snow.get_child(i) as Node3D
		if f2.position.y < 1.27 or f2.position.y > 2.34:
			bounded = false
		if f2.position.x < 1.1 or f2.position.x > 2.7:
			bounded = false
	_ok(bounded and main._snow.get_child_count() == 12,
		"snow stays bounded, node never grows")
	# Quality gate + back to calm.
	main.settings["quality_preset"] = "Low"
	main._apply_quality()
	_ok(not main._snow.visible, "quality off hides the snow")
	main.settings["quality_preset"] = "Standard"
	main._apply_quality()
	_set_cold(main)
	_ok(main._snow.visible, "quality on brings the snow back")
	main.season = Events._season_by_id("calm")
	main._apply_season_visuals()
	_ok(not main._snow.visible, "calm hides it again")

	# Moonlight: dark at noon, cool spill at midnight, gated by the clock.
	_ok(main._moonlight != null and main._moonlight.light_color == Color("#A9C3E8"),
		"moonlight exists and is cool blue")
	main.day_cycle.t = 0.5
	main._apply_daylight()
	_ok(main._moonlight.light_energy < 0.01, "noon: no moonlight")
	main.day_cycle.t = 0.0
	main._apply_daylight()
	_ok(main._moonlight.light_energy > 0.5, "midnight: moonlight spills")
	_ok(not main._moonlight.shadow_enabled, "moonlight casts no shadows (cheap)")

	# How-to-play documents all three input methods.
	var howto: String = main.main_menu._howto_panel.get_node(
		"Sheet/SheetBox/Body").text
	_ok(howto.contains("WASD"), "how-to covers mouse + keyboard")
	_ok(howto.contains("Touch"), "how-to covers touch")
	_ok(howto.contains("Gamepad") and howto.contains("START"),
		"how-to covers gamepad")

	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _set_cold(main) -> void:
	main.season = Events._season_by_id("cold_snap")
	main._apply_season_visuals()

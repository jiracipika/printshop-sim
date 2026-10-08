extends SceneTree

## v0.51.0 — "Calm mode": a persisted reduced-motion setting. Rain, snow,
## clouds and the window's birds/van freeze while it is on. Run:
## godot --headless --path . -s tests/v051_test.gd

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

	# Defaults: motion everywhere.
	_ok(not bool(main.settings.get("calm_mode", true)),
		"calm_mode defaults to false")
	_ok(not main.calm_motion(), "calm_motion() reads false by default")
	_ok(bool(main._window_life.motion_enabled),
		"the window animates by default")

	# The setting drives the window motion gate.
	main.apply_setting("calm_mode", true, false)
	_ok(main.calm_motion(), "calm_motion() reads true when set")
	_ok(not bool(main._window_life.motion_enabled),
		"setting calm mode stops the window's heartbeat")

	# Rain freezes (forced visible — day 1 is a calm week).
	main._rain.visible = true
	var streak: Node3D = main._rain.get_child(0)
	var y0: float = streak.position.y
	main._animate_rain(1.0)
	_ok(streak.position.y == y0, "calm mode holds the rain still")
	main.apply_setting("calm_mode", false, false)
	streak.position.y = 2.2  # mid-pane: a 1 s fall cannot reach the sill wrap
	main._animate_rain(1.0)
	_ok(streak.position.y < 2.2, "with calm off the rain falls again")

	# Snow freezes, phases included.
	main.apply_setting("calm_mode", true, false)
	main._snow.visible = true
	var flake: Node3D = main._snow.get_child(0)
	var fy0: float = flake.position.y
	var ph0: float = main._snow_phases[0]
	main._animate_snow(1.0)
	_ok(flake.position.y == fy0 and main._snow_phases[0] == ph0,
		"calm mode holds the snow and its sway phase")
	main.apply_setting("calm_mode", false, false)
	flake.position.y = 2.2  # mid-pane: one step cannot reach the wrap
	main._animate_snow(1.0)
	_ok(flake.position.y < 2.2, "with calm off the snow falls again")

	# Clouds freeze, alpha included.
	main.apply_setting("calm_mode", true, false)
	var cloud: MeshInstance3D = main._clouds[0]
	var cx0: float = cloud.position.x
	main._animate_clouds(2.0)
	_ok(cloud.position.x == cx0, "calm mode holds the clouds")
	main.apply_setting("calm_mode", false, false)
	main._animate_clouds(2.0)
	_ok(cloud.position.x < cx0, "with calm off the clouds drift again")

	# Live physics frames agree: with calm on, NOTHING outside moves.
	main.apply_setting("calm_mode", true, false)
	main._window_life._launch_bird(0, 1.45, 1.0, 0.42, 1.9)
	main._window_life._spawn_van(1.0)
	var bx0: float = main._window_life._birds[0].position.x
	var vx0: float = main._window_life._van.position.x
	for i in range(3):
		await physics_frame
	_ok(main._window_life._birds[0].position.x == bx0,
		"live frames hold the birds with calm on")
	_ok(main._window_life._van.position.x == vx0,
		"live frames hold the van with calm on")

	# Calm off: the deterministic heartbeat moves both again.
	main.apply_setting("calm_mode", false, false)
	var wl = main._window_life
	wl.set_motion(false)
	wl._advance(120.0)
	_ok(wl._van.position.x == vx0, "a stopped window ignores whole minutes")
	wl.set_motion(true)
	var vx1: float = wl._van.position.x
	wl._advance(1.0)
	_ok(absf(wl._van.position.x - (vx1 + 0.35)) < 0.001,
		"a running window steps the van at its own speed")

	# Settings sheet: checkbox exists, shows the persisted value, and
	# toggling it applies live through the settings_changed path.
	main.apply_setting("calm_mode", false, false)
	main.main_menu.open_menu()
	main.main_menu.show_settings(main.settings)
	await physics_frame
	var check: CheckBox = main.main_menu._settings_panel \
		.get_node("Sheet/SheetScroll/SheetBox/CalmCheck")
	_ok(check != null, "CalmCheck exists on the settings sheet")
	_ok(not check.button_pressed, "show_settings pushes calm off into the box")
	check.button_pressed = true
	await physics_frame
	_ok(bool(main.settings.get("calm_mode", false)),
		"checking the box applies calm mode live")
	_ok(not bool(main._window_life.motion_enabled),
		"the live apply reached the window")
	main.main_menu.show_settings(main.settings)
	await physics_frame
	_ok(check.button_pressed, "show_settings pushes the persisted calm state")

	# Persistence + validators.
	main._save_game()
	var saved: Dictionary = BrowserSave.load_payload()
	_ok(bool(saved.get("settings", {}).get("calm_mode", false)),
		"calm mode persists in the save")
	var ss = load("res://scripts/SaveSystem.gd")
	_ok(not ss.validate(saved).is_empty(), "a calm-mode payload validates")
	var bad_text: Dictionary = saved.duplicate(true)
	(bad_text["settings"] as Dictionary)["calm_mode"] = "yes"
	_ok(ss.validate(bad_text).is_empty(), "validator rejects a text calm_mode")
	var bad_int: Dictionary = saved.duplicate(true)
	(bad_int["settings"] as Dictionary)["calm_mode"] = 1
	_ok(ss.validate(bad_int).is_empty(), "validator rejects an int calm_mode")
	var old_save: Dictionary = saved.duplicate(true)
	(old_save["settings"] as Dictionary).erase("calm_mode")
	_ok(not ss.validate(old_save).is_empty(),
		"payloads without calm_mode validate (old saves)")

	# The saved shop boots calm: the restore path re-applies the motion gate.
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2.calm_motion(), "a calm shop boots calm")
	_ok(not bool(main2._window_life.motion_enabled),
		"a calm shop boots with the window stopped")

	main2.queue_free()
	await physics_frame
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

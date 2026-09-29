extends SceneTree

## v0.25.0 — "Outside the window": light-box window with a day view, a night
## starfield featuring one real constellation per real-world month, a moon
## with its real phase, a lit skyline and drifting clouds. Run:
## timeout 180 godot --headless --path . -s tests/v025_test.gd

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
	_test_sky_art()
	await _test_window()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_sky_art() -> void:
	# Twelve months, twelve featured constellations, all data sound.
	_ok(ShopArt.MONTH_SKY.size() == 12, "twelve month skies")
	_ok(ShopArt.featured_constellation(1) == "orion"
		and ShopArt.featured_constellation(3) == "leo"
		and ShopArt.featured_constellation(6) == "scorpius"
		and ShopArt.featured_constellation(7) == "lyra"
		and ShopArt.featured_constellation(12) == "taurus",
		"featured constellations follow the month")
	var data_ok := true
	var ids := {}
	for month in range(1, 13):
		var id := ShopArt.featured_constellation(month)
		ids[id] = true
		if not ShopArt.CONSTELLATIONS.has(id):
			data_ok = false
			continue
		var c: Dictionary = ShopArt.CONSTELLATIONS[id]
		var count: int = (c.stars as Array).size()
		if count < 4:
			data_ok = false
		for ln in c.lines:
			if int(ln[0]) >= count or int(ln[1]) >= count:
				data_ok = false
	_ok(data_ok and ids.size() == 12, "constellation data sound and distinct")
	# Night textures build per month, cached, distinct.
	var jan: ImageTexture = ShopArt.window_night(1)
	var jul: ImageTexture = ShopArt.window_night(7)
	_ok(jan != null and ShopArt.window_night(1) == jan,
		"night texture cached per month")
	_ok(jan != jul, "different months get different skies")
	# Moon phase: anchored to the 2000-01-06 new moon.
	_ok(absf(ShopArt.moon_phase(947182440)) < 0.02, "phase 0 at the new-moon epoch")
	_ok(absf(ShopArt.moon_phase(947182440 + 14 * 86400) - 0.5) < 0.06,
		"phase ~0.5 two weeks later")
	_ok(ShopArt.moon_phase() >= 0.0 and ShopArt.moon_phase() <= 1.0,
		"today's phase is a valid fraction")
	_ok(ShopArt.window_day() != null and ShopArt.cloud() != null,
		"day view and cloud textures build")


func _test_window() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Night pane exists, sits in front of the day pane, starts transparent.
	_ok(main._night_pane != null and main._night_mat != null,
		"night pane exists")
	_ok(main._night_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		and main._night_mat.albedo_texture != null,
		"night pane is an alpha-blended textured layer")
	# Fresh shops boot at t=0 — midnight — so the sky starts ON.
	_ok(main._night_mat.albedo_color.a > 0.9 and main.day_cycle.t == 0.0,
		"boot at midnight shows the starfield")
	_ok(main._window_mat.albedo_texture != null,
		"day pane carries the day view texture")

	# The shop clock drives the crossfade: t=0 is midnight, t=0.5 is noon.
	main.day_cycle.t = 0.0
	main._apply_daylight()
	var a_night: float = main._night_mat.albedo_color.a
	main.day_cycle.t = 0.5
	main._apply_daylight()
	var a_day: float = main._night_mat.albedo_color.a
	_ok(a_night > 0.9 and a_day < 0.05,
		"stars fade in at night (%.2f) and out at day (%.2f)" % [a_night, a_day])
	main.day_cycle.t = 0.0
	main._apply_daylight()
	var glow_night: float = main._window_mat.emission_energy_multiplier
	main.day_cycle.t = 0.5
	main._apply_daylight()
	_ok(main._window_mat.emission_energy_multiplier > glow_night,
		"day pane glows brighter at noon than at night")

	# Clouds: two wisps, drifting, wrapping inside the window band.
	_ok(main._clouds.size() == 2 and main._cloud_speeds.size() == 2,
		"two cloud wisps")
	var x0: float = main._clouds[0].position.x
	main._animate_clouds(2.0)
	var x1: float = main._clouds[0].position.x
	_ok(x1 < x0, "clouds drift sideways")
	main._clouds[0].position.x = 0.98
	main._animate_clouds(0.05)
	_ok(main._clouds[0].position.x > 2.0, "clouds wrap back across the glass")

	# The featured texture matches the real month.
	var real_month: int = Time.get_date_dict_from_system().month
	_ok(main._night_mat.albedo_texture == ShopArt.window_night(real_month),
		"the window shows this real month's sky")

	# A calendar-month rollover mid-session rebinds on the next refresh
	# (regression: the sky used to keep its boot month until reload).
	main._current_sky_month = (1 if real_month == 12 else real_month + 1)
	main._refresh_event()
	_ok(main._night_mat.albedo_texture == ShopArt.window_night(real_month)
		and main._current_sky_month == real_month,
		"refresh rebinds the sky when the month counter drifts")

	main.queue_free()
	await physics_frame

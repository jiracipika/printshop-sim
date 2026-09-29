extends SceneTree

## v0.17.0 — "Weather in the windows": per-season window/fog/sun visuals,
## rain streaks on humid weeks, frost band on cold snaps, HUD weather icons,
## quality-toggle gating. Run:
## timeout 120 godot --headless --path . -s tests/v017_test.gd

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
	_test_season_table()
	await _test_season_visuals()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- season data ------------------------------------------------------------------

func _test_season_table() -> void:
	# Runtime load, not a static reference: a -s script that names the Main
	# class compiles before autoloads exist (see the v0.16 hazard note).
	var main_script: GDScript = load("res://scripts/Main.gd")
	var look_table: Dictionary = main_script.SEASON_LOOK
	# The look table covers every season id the generator can produce.
	for id in ["calm", "humid", "cold_snap", "boom"]:
		_ok(look_table.has(id), "SEASON_LOOK covers '%s'" % id)
	# Calm reproduces the pre-v0.17 window exactly.
	var calm: Dictionary = look_table["calm"]
	_ok(calm.pane == Color("#D8E8DF") and calm.glow == Color("#CFE3DA")
		and absf(float(calm.energy) - 1.2) < 0.001,
		"calm look keeps the original pane colors")
	_ok(calm.sun == Color(1.0, 1.0, 1.0) and absf(float(calm.fog_density) - 0.008) < 1e-6,
		"calm look keeps the original sun and fog")
	# Season generation is unchanged: week 1 calm, deterministic, valid ids.
	_ok(Events.season_for_week(1).id == "calm", "week 1 stays calm")
	var pool := ["calm", "humid", "cold_snap", "boom"]
	var all_valid := true
	var all_stable := true
	for w in range(2, 15):
		var s: Dictionary = Events.season_for_week(w)
		if not pool.has(str(s.id)):
			all_valid = false
		if str(Events.season_for_week(w).id) != str(s.id):
			all_stable = false
	_ok(all_valid, "season ids stay within the known pool")
	_ok(all_stable, "season per week is deterministic")


## --- visuals on a live Main -------------------------------------------------------

func _set_season(main, id: String) -> void:
	# The real Events dict so HUD name assertions read true strings.
	main.season = Events._season_by_id(id)
	main._apply_season_visuals()


func _test_season_visuals() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Nodes exist and start calm.
	_ok(main._window_mat != null and main._rain != null and main._frost != null,
		"window material + rain + frost nodes exist")
	_ok(not main._rain.visible and not main._frost.visible,
		"overlays hidden on the calm first week")
	_ok(main._window_mat.albedo_color == Color("#D8E8DF"),
		"calm pane keeps the original albedo")
	_ok(absf(main._env.fog_density - 0.008) < 1e-6,
		"calm fog density unchanged")

	# Humid: haze + rain, denser fog.
	_set_season(main, "humid")
	_ok(main._rain.visible and not main._frost.visible,
		"humid week shows rain and no frost")
	_ok(main._window_mat.albedo_color != Color("#D8E8DF"),
		"humid pane hazier than calm")
	_ok(absf(main._env.fog_density - 0.012) < 1e-6, "humid fog is denser")
	_ok(main._rain.get_child_count() == 10 and main._rain_speeds.size() == 10,
		"10 rain streaks with matching speeds")
	var in_bounds := true
	for i in range(main._rain.get_child_count()):
		var streak := main._rain.get_child(i) as Node3D
		if streak.position.x < 1.15 or streak.position.x > 2.65:
			in_bounds = false
		if streak.position.y < 1.28 or streak.position.y > 2.35:
			in_bounds = false
	_ok(in_bounds, "streaks start inside the pane rect")

	# Cold snap: frost + a cooler sun at the same time of day.
	_set_season(main, "calm")
	main.day_cycle.t = 0.25  # fixed midday
	main._apply_daylight()
	var calm_red: float = main._sun.light_color.r
	var calm_blue: float = main._sun.light_color.b
	_set_season(main, "cold_snap")
	main._apply_daylight()
	_ok(main._frost.visible and not main._rain.visible,
		"cold snap shows frost and no rain")
	_ok(main._sun.light_color.r < calm_red and main._sun.light_color.b >= calm_blue,
		"cold sun is cooler at the same hour")
	_ok(absf(main._env.fog_density - 0.008) < 1e-6, "cold fog density unchanged")

	# Boom: warm golden fog and sun. Since v0.25 the clock scales the pane's
	# emission — at noon it lands exactly on the season's energy value.
	_set_season(main, "boom")
	main.day_cycle.t = 0.5
	main._apply_daylight()
	var calm_fog: Color = (load("res://scripts/Main.gd") as GDScript).SEASON_LOOK["calm"].fog_color
	_ok(main._env.fog_light_color.r > calm_fog.r
		and main._env.fog_light_color.b < calm_fog.b,
		"boom fog warms up")
	_ok(main._sun.light_color.b < calm_blue, "boom sun loses blue (gold)")
	_ok(absf(float(main._window_mat.emission_energy_multiplier) - 1.25) < 0.001,
		"boom pane glows warmer at noon")

	# Back to calm restores everything.
	_set_season(main, "calm")
	_ok(main._window_mat.albedo_color == Color("#D8E8DF")
		and not main._rain.visible and not main._frost.visible,
		"calm restores pane and hides overlays")

	# Quality toggle gates the overlays (tints are free and stay). Since
	# v0.20 the preset owns the gate: Low = off, Standard/High = on.
	main.settings["quality_preset"] = "Low"
	main._apply_quality()
	_set_season(main, "humid")
	_ok(not main._rain.visible and main._sun.shadow_enabled == false,
		"quality off hides rain even on humid weeks")
	_set_season(main, "cold_snap")
	_ok(not main._frost.visible, "quality off hides frost too")
	main.settings["quality_preset"] = "Standard"
	main._apply_quality()
	_ok(main._frost.visible, "quality on brings frost back")
	_set_season(main, "humid")
	_ok(main._rain.visible, "quality on brings rain back")

	# Rain animation wraps inside the pane and never grows the node.
	var before_y: float = (main._rain.get_child(3) as Node3D).position.y
	main._animate_rain(0.016)
	var after_y: float = (main._rain.get_child(3) as Node3D).position.y
	_ok(after_y < before_y, "rain slides down")
	var bounded := true
	for i in range(3750):  # ~60 s of gameplay at 60 Hz
		main._animate_rain(0.016)
	for i in range(main._rain.get_child_count()):
		var streak := main._rain.get_child(i) as Node3D
		if streak.position.y < 1.28 or streak.position.y > 2.36:
			bounded = false
	_ok(bounded and main._rain.get_child_count() == 10,
		"60 s of rain stays bounded, node never grows")
	main._rain.visible = false
	var frozen_y: float = (main._rain.get_child(3) as Node3D).position.y
	main._animate_rain(0.016)
	_ok((main._rain.get_child(3) as Node3D).position.y == frozen_y,
		"hidden rain does not animate")

	# HUD weather icons on the season line.
	main.settings["shadows"] = true
	_set_season(main, "cold_snap")
	main._update_hud()
	_ok(main._status.text.contains("☃") and main._status.text.contains("Cold snap"),
		"cold HUD line carries the snow icon")
	_set_season(main, "humid")
	main._update_hud()
	_ok(main._status.text.contains("☔"), "humid HUD line carries the rain icon")
	_set_season(main, "boom")
	main._update_hud()
	_ok(main._status.text.contains("☀"), "boom HUD line carries the sun icon")
	main.season = Events.CALM_SEASON.duplicate(true)
	main._update_hud()
	_ok(not main._status.text.contains("This week:"),
		"calm weeks keep no season line")

	# Rollover integration: a real week change re-derives season + visuals.
	var week2: String = str(Events.season_for_week(2).id)
	main.day_cycle.restore(8, 0.0)  # day 8 = week 2
	main._refresh_event()
	main._update_hud()
	_ok(str(main.season.id) == week2, "rollover to week 2 picks the generated season")
	var overlay_expected: bool = week2 == "humid" or week2 == "cold_snap"
	_ok(main._rain.visible == (week2 == "humid")
		and main._frost.visible == (week2 == "cold_snap")
		and (overlay_expected or not overlay_expected),
		"rollover applies the matching overlay")
	_ok(main._status.text.contains(_icon_for(week2)) if week2 != "calm" else true,
		"rollover HUD line carries the season icon")

	main.queue_free()
	await physics_frame


func _icon_for(id: String) -> String:
	match id:
		"humid":
			return "☔"
		"cold_snap":
			return "☃"
		"boom":
			return "☀"
	return ""

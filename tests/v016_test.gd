extends SceneTree

## v0.16.0 — "The radio": procedural lo-fi loop, Music bus, ducking, servo
## blips, radio prop + settings. Run:
## timeout 120 godot --headless --path . -s tests/v016_test.gd

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


func _music_vol_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))


func _run() -> void:
	BrowserSave.clear()
	_test_music_stream()
	await _test_main_radio()
	_test_save_validation()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- stream + bus ----------------------------------------------------------------

func _test_music_stream() -> void:
	# The loop builds, is long enough to be a loop, and loops seamlessly.
	var music: AudioStreamWAV = Sfx.stream("music")
	_ok(music != null, "music stream builds headless")
	_ok(music.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and music.loop_begin == 0 and music.loop_end == music.data.size() / 2,
		"music loops across the full buffer")
	var seconds := music.data.size() / 2.0 / Sfx.RATE
	var bpm := float(Sfx.STATIONS[0].bpm)
	var expect := 4.0 * 60.0 / bpm * Sfx.MUSIC_BARS
	_ok(absf(seconds - expect) < 0.1,
		"music is 4 bars at ~%d BPM (%.1fs)" % [int(bpm), seconds])
	# Quiet by design: peak amplitude stays well under the SFX norm.
	var peak := 0.0
	for i in range(0, music.data.size(), 512):
		var v: int = absi(music.data.decode_s16(i))
		peak = maxf(peak, float(v) / 32767.0)
	_ok(peak > 0.0 and peak < 0.25, "music stays quiet (peak %.3f)" % peak)
	var servo: AudioStreamWAV = Sfx.stream("servo")
	_ok(servo != null and servo.data.size() / 2.0 / Sfx.RATE < 0.1,
		"servo blip is a short tick")

	# Music bus exists, separate from SFX, and the volume helper drives it.
	var bus_idx := AudioServer.get_bus_index(Sfx.music_bus_name())
	_ok(bus_idx != -1 and bus_idx != AudioServer.get_bus_index("SFX"),
		"Music bus exists and is separate from SFX")
	var before := _music_vol_db()
	Sfx.set_music_volume(0.5)
	var half := _music_vol_db()
	Sfx.set_music_volume(0.25)
	_ok(_music_vol_db() < half and half < before,
		"set_music_volume lowers the bus stepwise")
	Sfx.set_music_volume(0.0)
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
		"zero volume mutes the Music bus")


## --- Main integration ---------------------------------------------------------------

func _test_main_radio() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Music player wired to the loop on the Music bus, playing by default.
	_ok(main._music != null and main._music.bus == "Music"
		and main._music.stream == Sfx.stream("music"),
		"radio player plays the loop on the Music bus")
	_ok(main._music.playing, "radio is on by default")
	_ok(absf(float(main.settings.music_volume) - 0.35) < 0.001
		and bool(main.settings.music_enabled),
		"defaults: music enabled at low volume")

	# The radio prop exists on the shelf.
	var radio: Node3D = main.get_node_or_null("Radio")
	_ok(radio != null and bool(radio.get_meta("radio", false))
		and radio.position.distance_to(main.RADIO_POS) < 0.001,
		"radio prop sits on the shelf")

	# E near the radio toggles the music off and back on, with a log line.
	main.paused = false
	main.captured = true
	main._player.global_position = Vector3(-3.0, 0.3, -1.0)
	# v0.21.0: E cycles stations Lo-fi -> Synthwave -> Ambient -> off -> on.
	main._try_interact()
	_ok(main._music.playing and int(main.settings.radio_station) == 1,
		"E at the radio moves to station 2, still playing")
	main._try_interact()
	_ok(main._music.playing and int(main.settings.radio_station) == 2,
		"E again moves to station 3")
	main._try_interact()
	_ok(not main._music.playing and not bool(main.settings.music_enabled),
		"E past the last station turns the music off")
	main._try_interact()
	_ok(main._music.playing and bool(main.settings.music_enabled)
		and int(main.settings.radio_station) == 2,
		"E again turns the music back on the same station")
	var radio_log: Array[String] = []
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "radio":
			radio_log.append(str(e["text"]))
	_ok(radio_log.size() == 4 and "off" in radio_log[2],
		"radio station changes land in the workshop log")

	# Slider writes through apply_setting; disabled stops the player.
	main.apply_setting("music_volume", 0.6, false)
	_ok(absf(_music_vol_db() - linear_to_db(0.6)) < 0.01,
		"music_volume drives the bus volume")
	main.apply_setting("music_enabled", false, false)
	_ok(not main._music.playing and AudioServer.is_bus_mute(
		AudioServer.get_bus_index("Music")), "disabled stops and mutes")
	main.apply_setting("music_enabled", true, false)
	main.apply_setting("music_volume", 0.35, false)

	# Duck: design-studio open quiets, close restores.
	main._open_design_studio()
	_ok(main._music_ducked and absf(_music_vol_db() - linear_to_db(0.35 * 0.3)) < 0.01,
		"design studio ducks the radio to 30 pct")
	main._close_design_studio()
	_ok(not main._music_ducked and absf(_music_vol_db() - linear_to_db(0.35)) < 0.01,
		"closing the studio restores the volume")

	# Servo blips: rate-limited countdowns per running machine only.
	main.paused = false
	main.captured = true
	var m0: Dictionary = main._machine(0)
	m0["filament_g"] = 5000
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main._try_interact()
	var c: Contract = m0.get("contract")
	_ok(c != null, "job accepted for the servo test")
	c.color = str(m0.get("color"))
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	# First call grows the timer array (all zero) and blips the running
	# machine immediately; the re-arm window must then hold off the second.
	main._servo_blips(0.016)
	_ok(main._servo_timers[0] > 0.5, "blip re-arms a rate-limit window")
	main._servo_blips(0.016)
	_ok(main._servo_timers[0] > 0.5, "second frame within the window does not re-blip")
	var s0: PrintSim = m0.get("sim")
	while s0.is_running():
		s0.tick(1.0)
	main._servo_timers[0] = 0.05
	main._servo_blips(1.0)
	_ok(main._servo_timers[0] < 0.0, "idle machine never re-arms")

	# Settings panel: slider + checkbox reflect state and emit mapped keys.
	var menu = main.main_menu
	menu.open_menu()
	menu.show_settings(main.settings)
	var slider: HSlider = menu.get_node("Root/SettingsPanel/Sheet/SheetScroll/SheetBox/MusicSliderRow/MusicSlider")
	var check: CheckBox = menu.get_node("Root/SettingsPanel/Sheet/SheetScroll/SheetBox/MusicCheck")
	_ok(slider != null and absf(slider.value - 0.35) < 0.001,
		"music slider reflects the setting")
	_ok(check != null and check.is_pressed(), "music checkbox reflects on")
	# Instance call, NOT the MainMenu class: a static reference would make
	# MainMenu.gd a compile-time dependency of this -s script, and its
	# Version autoload reference fails to resolve before autoloads register.
	_ok(menu.slider_name_to_key("MusicSlider") == "music_volume"
		and menu.slider_name_to_key("VolSlider") == "sfx_volume"
		and menu.slider_name_to_key("SensSlider") == "mouse_sens_scale",
		"slider key mapping covers all three sliders")
	var got := []
	menu.settings_changed.connect(func(key: String, value) -> void: got.append([key, value]))
	slider.set_value_no_signal(0.7)
	slider.value_changed.emit(0.7)
	check.set_pressed_no_signal(false)
	check.toggled.emit(false)
	_ok(got.size() == 2 and got[0][0] == "music_volume" and absf(float(got[0][1]) - 0.7) < 0.001
		and got[1][0] == "music_enabled" and got[1][1] == false,
		"controls emit the mapped settings keys")
	main.apply_setting("music_volume", 0.35, false)
	main.apply_setting("music_enabled", true, false)

	# Persistence: save carries music settings; a fresh shop restores them.
	main.apply_setting("music_enabled", false, false)
	main._save_game()
	var payload: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(payload.has("settings") and not bool(payload.settings.music_enabled)
		and absf(float(payload.settings.music_volume) - 0.35) < 0.001,
		"save payload carries music settings")
	main.queue_free()
	await physics_frame

	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(not main2._music.playing and not bool(main2.settings.music_enabled),
		"restored shop respects saved radio-off")
	main2.queue_free()
	await physics_frame
	BrowserSave.clear()


## --- save validation ------------------------------------------------------------------

func _test_save_validation() -> void:
	var base := {
		"version": 1,
		"balance_cents": 100,
		"ledger": {"balance_cents": 100, "transactions": [
			{"id": 1, "reason": "open", "delta_cents": 100, "balance_after": 100},
		], "paid_contract_ids": [], "next_seq": 1},
		"active_contract": {},
		"paid_ids": [],
		"settings": {"music_enabled": true, "music_volume": 0.35},
	}
	_ok(not SaveSystem.validate(base).is_empty(), "music settings validate")
	var rt: Dictionary = SaveSystem.validate(JSON.parse_string(JSON.stringify(base)))
	_ok(not rt.is_empty(), "music settings validate after JSON round-trip")

	for mutate in [
		func(p: Dictionary) -> void: p["settings"]["music_volume"] = 1.5,
		func(p: Dictionary) -> void: p["settings"]["music_volume"] = "loud",
		func(p: Dictionary) -> void: p["settings"]["music_enabled"] = "yes",
	]:
		var bad: Dictionary = base.duplicate(true)
		mutate.call(bad)
		if not SaveSystem.validate(bad).is_empty():
			_ok(false, "bad music setting rejected (%s)" % str(bad["settings"]))
	_ok(true, "malformed music settings rejected")

	var legacy: Dictionary = base.duplicate(true)
	legacy["settings"] = {"sfx_volume": 0.8}
	_ok(not SaveSystem.validate(legacy).is_empty(), "settings without music keys validate")

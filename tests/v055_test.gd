extends SceneTree

const BrowserSave = preload("res://scripts/BrowserSave.gd")

## v0.55.0 — "Jazz": a fourth radio station. New dominant-7th synth loop at
## 96 BPM on the dial; the hard-coded 0..2 station guards and the save
## validators widen to the station count; a new Full dial milestone rewards
## hearing all four (Radio star stays at three so old saves keep it). Run:
## godot --headless --path . -s tests/v055_test.gd

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _done(main, achievement_name: String) -> bool:
	for a in main._achievements():
		if str(a.name) == achievement_name:
			return bool(a.done)
	return false


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

	# A real payload is the validator base — validate() demands the mandatory
	# ledger/day shape before it ever reaches the optional settings keys.
	main._save_game()
	var base: Dictionary = BrowserSave.load_payload()
	_ok(not base.is_empty(), "a fresh save validates as the test base")

	# --- save validators widened to 0..3 ----------------------------------------
	var ss = load("res://scripts/SaveSystem.gd")
	var ok3: Dictionary = base.duplicate(true)
	ok3["settings"] = {"radio_station": 3}
	_ok(not ss.validate(ok3).is_empty(), "radio_station 3 validates now")
	var ok3f: Dictionary = base.duplicate(true)
	ok3f["settings"] = {"radio_station": 3.0}
	_ok(not ss.validate(ok3f).is_empty(), "float radio_station 3.0 validates")
	var bad4: Dictionary = base.duplicate(true)
	bad4["settings"] = {"radio_station": 4}
	_ok(ss.validate(bad4).is_empty(), "radio_station 4 is still rejected")
	var badfrac: Dictionary = base.duplicate(true)
	badfrac["settings"] = {"radio_station": 2.5}
	_ok(ss.validate(badfrac).is_empty(), "fractional stations are still rejected")
	var heard4: Dictionary = base.duplicate(true)
	heard4["stations_heard"] = [0, 1, 2, 3]
	_ok(not ss.validate(heard4).is_empty(), "four heard stations validate")
	var heard_over: Dictionary = base.duplicate(true)
	heard_over["stations_heard"] = [4]
	_ok(ss.validate(heard_over).is_empty(), "heard station index 4 is rejected")
	var heard_big: Dictionary = base.duplicate(true)
	heard_big["stations_heard"] = [0, 1, 2, 3, 3]
	_ok(ss.validate(heard_big).is_empty(), "five heard stations are rejected")
	var heard_old: Dictionary = base.duplicate(true)
	heard_old["stations_heard"] = [0, 1, 2]
	_ok(not ss.validate(heard_old).is_empty(), "old three-station saves still validate")

	# --- the station itself (pure Sfx) -------------------------------------------
	var names := Sfx.station_names()
	_ok(names.size() == 4 and names[3] == "Jazz", "the dial carries a fourth station, Jazz")
	var jazz: AudioStreamWAV = Sfx.music_station_stream(3)
	_ok(jazz != null and jazz.data.size() > 0, "the Jazz stream renders")
	_ok(jazz.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and jazz.loop_end == jazz.data.size() / 2, "Jazz loops seamlessly")
	_ok(absf(jazz.data.size() / 2.0 / Sfx.RATE - 4.0 * 4.0 * 60.0 / 96.0) < 0.1,
		"Jazz is 4 bars at 96 BPM")
	var sizes := {}
	for i in range(4):
		sizes[Sfx.music_station_stream(i).data.size()] = true
	_ok(sizes.size() == 4, "all four stations differ in length (tempo)")
	_ok(Sfx.music_station_stream(3) == jazz, "the Jazz stream is cached")

	# --- milestones: Radio star keeps its bar, Full dial raises it ----------------
	# The boot radio marks station 0 only.
	_ok(main._stations_heard == [0], "a fresh boot has heard only the boot station")
	_ok(not _done(main, "Full dial"), "Full dial starts undone")
	main._stations_heard.assign([0, 1, 2])
	_ok(_done(main, "Radio star"), "Radio star still unlocks at three stations")
	_ok(not _done(main, "Full dial"), "three of four is not the full dial")
	main._stations_heard.assign([0, 1, 2, 3])
	_ok(_done(main, "Full dial"), "hearing all four unlocks Full dial")

	# The hear-mark guard accepts station 3 and refuses station 4.
	main._stations_heard.clear()
	main._mark_station_heard(3)
	_ok(main._stations_heard == [3], "_mark_station_heard records station 3")
	main._mark_station_heard(4)
	_ok(main._stations_heard == [3], "_mark_station_heard refuses an out-of-dial index")

	# Cycling off the end: from station 3 the next E turns the radio off.
	main.settings["radio_station"] = 3
	main.settings["music_enabled"] = true
	main._toggle_radio()
	_ok(not bool(main.settings.music_enabled),
		"the next E past Jazz turns the radio off")

	# --- persistence: station 3 + a full dial survive the reload -----------------
	main._stations_heard.assign([0, 1, 2, 3])
	main.settings["radio_station"] = 3
	main._save_game()
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(int(main2.settings.radio_station) == 3,
		"a restored boot stays on station 3 (not clamped to 2)")
	_ok(main2._stations_heard == [0, 1, 2, 3], "the full dial survives the reload")
	main2.queue_free()
	await physics_frame

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

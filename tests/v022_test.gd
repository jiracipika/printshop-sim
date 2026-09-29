extends SceneTree

## v0.22.0 — "Presence pass": footsteps while walking, morning bell on day
## rollover, Radio star milestone. Run:
## timeout 180 godot --headless --path . -s tests/v022_test.gd

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
	_test_streams()
	await _test_presence()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_streams() -> void:
	for key in ["step1", "step2", "bell"]:
		_ok(Sfx.stream(key) != null, "%s stream builds" % key)
	var step_len: float = Sfx.stream_lengths()["step1"]
	var bell_len: float = Sfx.stream_lengths()["bell"]
	_ok(step_len < 0.2 and bell_len > 0.6 and bell_len < 1.2,
		"steps are ticks (%.2fs), the bell rings (%.2fs)" % [step_len, bell_len])
	for key in ["step1", "step2", "bell"]:
		var s: AudioStreamWAV = Sfx.stream(key)
		var peak := 0.0
		for i in range(0, s.data.size(), 256):
			peak = maxf(peak, float(absi(s.data.decode_s16(i))) / 32767.0)
		# Noise-based one-shots vary per run; just refuse clipping.
		_ok(peak > 0.0 and peak < 0.95, "%s stays audible but tame (peak %.2f)" % [key, peak])


func _test_presence() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# Footsteps: first step lands immediately, then paces by the interval.
	_ok(main._step_timer == 0.0 and main._steps_played == 0, "feet start quiet")
	main._footsteps(0.016, true, true)
	_ok(main._steps_played == 1 and absf(main._step_timer - 0.42) < 0.001,
		"first footstep lands on the first moving frame")
	main._footsteps(0.016, true, true)
	_ok(main._steps_played == 1, "no double-step inside the interval")
	main._footsteps(0.42, true, true)
	main._footsteps(0.42, true, true)
	_ok(main._steps_played == 3, "steps pace out over the distance")
	main._step_alt = false
	main._footsteps(0.5, true, true)
	_ok(main._step_alt, "footsteps alternate variants")
	var played_before: int = main._steps_played
	main._footsteps(1.0, false, true)
	main._footsteps(1.0, true, false)
	_ok(main._steps_played == played_before,
		"idle feet and airborne feet never step")

	# Morning bell rings on a live rollover.
	var bells: int = main._bells_played
	main._on_day_changed(main.day_cycle.day + 1)
	_ok(main._bells_played == bells + 1, "day rollover rings the bell")

	# Radio star: the boot station counts, cycling marks the rest.
	_ok(main._stations_heard == [0], "boot marks the playing station")
	main.paused = false
	main.captured = true
	main._player.global_position = Vector3(-3.0, 0.3, -1.0)
	main._try_interact()
	main._try_interact()
	_ok(main._stations_heard == [0, 1, 2], "cycling marks every station heard")
	var names := {}
	for a in main._achievements():
		names[a.name] = bool(a.done)
	_ok(names.get("Radio star", false), "Radio star unlocks at three stations")
	main._update_hud()
	_ok(main._toast.visible and main._toast.text.contains("Radio star"),
		"Radio star toasts")
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	var heard_saved = saved.get("stations_heard", "MISSING")
	_ok(heard_saved is Array and heard_saved.size() == 3
		and int(heard_saved[0]) == 0 and int(heard_saved[1]) == 1
		and int(heard_saved[2]) == 2,
		"stations_heard persists in the save")
	main.queue_free()
	await physics_frame

	# Reload: the set restores and the milestone stays silent at boot.
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(main2._stations_heard.size() == 3, "stations_heard survives the reload")
	# The restored log legitimately carries main1's Radio star entry; what
	# must NOT happen is a second one after the reload's first HUD render.
	var relogged := 0
	for e in main2.workshop_log.entries():
		if str(e["kind"]) == "milestone" and "Radio star" in str(e["text"]):
			relogged += 1
	main2._update_hud()
	var relogged_after := 0
	for e in main2.workshop_log.entries():
		if str(e["kind"]) == "milestone" and "Radio star" in str(e["text"]):
			relogged_after += 1
	_ok(relogged >= 1 and relogged_after == relogged,
		"reload never re-toasts Radio star")
	main2.queue_free()
	await physics_frame

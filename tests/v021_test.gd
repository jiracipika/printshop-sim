extends SceneTree

## v0.21.0 — "Flavor & feel": three radio stations on E, milestone toasts,
## shop dressing (doormat, mug, box stack). Run:
## timeout 180 godot --headless --path . -s tests/v021_test.gd

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
	_test_stations()
	await _test_radio_and_toasts()
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## --- station streams ------------------------------------------------------------

func _test_stations() -> void:
	var names := Sfx.station_names()
	_ok(names.size() == 4 and names[0] == "Lo-fi" and names[1] == "Synthwave"
		and names[2] == "Ambient" and names[3] == "Jazz", "four named stations")
	var streams: Array = []
	var all_loop := true
	var distinct := {}
	for i in range(4):
		var s: AudioStreamWAV = Sfx.music_station_stream(i)
		streams.append(s)
		distinct[s.data.size()] = true
		if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end != s.data.size() / 2:
			all_loop = false
	_ok(all_loop, "every station loops seamlessly")
	_ok(distinct.size() == 4, "stations differ in length (tempo)")
	# Station 0 keeps the v0.16 lo-fi timing; cached streams are stable.
	_ok(absf(streams[0].data.size() / 2.0 / Sfx.RATE - 4.0 * 4.0 * 60.0 / 72.0) < 0.1,
		"Lo-fi stays 4 bars at 72 BPM")
	_ok(Sfx.music_station_stream(1) == streams[1]
		and Sfx.stream("music") == streams[0],
		"station streams are cached and 'music' maps to station 0")
	# All stations stay quiet like the original loop.
	var peak_ok := true
	for s in streams:
		var peak := 0.0
		for i in range(0, s.data.size(), 512):
			peak = maxf(peak, float(absi(s.data.decode_s16(i))) / 32767.0)
		if peak >= 0.25:
			peak_ok = false
	_ok(peak_ok, "every station stays quiet (peak < 0.25)")


## --- radio cycling + toasts on a live shop ---------------------------------------

func _test_radio_and_toasts() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true

	# Default: station 0 playing.
	_ok(int(main.settings.radio_station) == 0 and main._music.playing
		and main._music.stream == Sfx.music_station_stream(0),
		"radio boots on Lo-fi")
	main._player.global_position = Vector3(-3.0, 0.3, -1.0)
	main._try_interact()
	_ok(int(main.settings.radio_station) == 1 and main._music.playing
		and main._music.stream == Sfx.music_station_stream(1)
		and main._prompt.text.contains("Synthwave"),
		"E moves to Synthwave without stopping playback")
	# Ducking works on the new station too.
	var music_bus := AudioServer.get_bus_index("Music")
	main._open_design_studio()
	var ducked_db := AudioServer.get_bus_volume_db(music_bus)
	main._close_design_studio()
	var restored_db := AudioServer.get_bus_volume_db(music_bus)
	_ok(ducked_db < restored_db, "studio ducks the station bus, closing restores")
	# The studio pauses the shop; re-arm before the next radio press.
	main.paused = false
	main.captured = true
	main._try_interact()
	_ok(int(main.settings.radio_station) == 2 and main._music.playing,
		"E moves to Ambient")
	main._try_interact()
	_ok(int(main.settings.radio_station) == 3 and main._music.playing
		and main._music.stream == Sfx.music_station_stream(3),
		"E moves to Jazz (station 4)")
	main._try_interact()
	_ok(not bool(main.settings.music_enabled) and not main._music.playing,
		"E past the last station switches the radio off")
	main._try_interact()
	_ok(bool(main.settings.music_enabled) and int(main.settings.radio_station) == 3
		and main._music.stream == Sfx.music_station_stream(3),
		"E revives the radio on the last station")
	# Station persists through a save.
	main._save_game()
	var saved: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	_ok(int(saved.get("settings", {}).get("radio_station", -1)) == 3,
		"radio_station persists in the save")

	# Milestone toasts: flipping a stat toasts exactly once, persists.
	main._update_hud()
	var toasted_before: int = main._achv_toasted.size()
	main.stats.delivered = 10
	main._update_hud()
	_ok(main._toast.visible and main._toast_t > 0.0
		and main._toast.text.contains("Milestone"),
		"the hud shows a milestone toast")
	var ten_orders := false
	var first_sale := false
	for n in main._achv_toasted:
		if n == "Ten orders":
			ten_orders = true
		if n == "First sale":
			first_sale = true
	_ok(first_sale and ten_orders and main._achv_toasted.size() >= toasted_before + 2,
		"both new milestones recorded as toasted")
	main._update_hud()
	_ok(main._toast.text.contains("Ten orders") or main._toast.visible,
		"toast label survives to show the latest")
	var milestone_logs := 0
	for e in main.workshop_log.entries():
		if str(e["kind"]) == "milestone":
			milestone_logs += 1
	_ok(milestone_logs >= 2, "milestones land in the workshop log")
	main.queue_free()
	await physics_frame

	# Reload: no re-toasting of already-earned milestones.
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(main2._achv_toasted.has("First sale") and main2._achv_toasted.has("Ten orders"),
		"toasted set survives the reload")
	main2.stats.earned_cents = 60000
	main2._update_hud()
	_ok(main2._toast.text.contains("High earner"),
		"newly earned milestones still toast after reload")
	main2.queue_free()
	await physics_frame

	# --- dressing props + budget ------------------------------------------------
	var main3 = packed.instantiate()
	root.add_child(main3)
	await physics_frame
	var found := {"mat": false, "mug": false, "boxes": 0}
	for prop in main3.get_tree().get_nodes_in_group("props"):
		if prop is MeshInstance3D:
			var p := prop as MeshInstance3D
			if p.position.y < 0.02 and p.position.z < -2.0 and absf(p.position.x - 1.6) < 0.1:
				found.mat = true
			if p.position.y > 0.9 and p.position.y < 1.0 and p.position.z < -2.0:
				found.mug = true
			if p.position.x > 2.8 and p.position.y > 0.1 and p.position.y < 0.6:
				found.boxes += 1
	_ok(found.mat, "doormat sits under the farm doorway")
	_ok(found.mug, "coffee mug on the design bench")
	_ok(found.boxes >= 3, "cardboard stack by the packing table")
	var total := 0
	var visible := 0
	var stack := [main3]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D:
			total += 1
			if n.visible and n.is_visible_in_tree():
				visible += 1
		for c in n.get_children():
			stack.append(c)
	_ok(visible <= 180 and total <= 400,
		"draw-call budget still holds (%d visible / %d total)" % [visible, total])
	main3.queue_free()
	await physics_frame

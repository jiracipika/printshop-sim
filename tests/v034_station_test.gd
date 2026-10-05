extends SceneTree

## Finishing station tests (station layer only). Pure logic + station node,
## no Main scene (Main integration is a parent-owned follow-up, like the
## packing station). Run:
## timeout 60 godot --headless --path . -s tests/v034_station_test.gd

const FinishingStation := preload("res://scripts/FinishingStation.gd")

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
	_test_grade_mapping()
	_test_last_result_and_signal()
	_test_station_shape()
	_test_set_active()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_grade_mapping() -> void:
	var station: FinishingStation = FinishingStation.new()
	root.add_child(station)
	# The full bump table.
	var table := {"B": "A", "C": "B", "D": "C"}
	for g in table:
		var res: Dictionary = station.try_finish(g)
		_ok(res.get("finished", false) == true, "%s finishes (finished true)" % g)
		_ok(String(res.get("grade", "")) == table[g], "%s -> %s" % [g, table[g]])
	# A and ungraded pass through unchanged, still finished.
	var a: Dictionary = station.try_finish("A")
	_ok(a.get("finished", false) == true, "A finishes (nothing to improve)")
	_ok(String(a.get("grade", "")) == "A", "A stays A")
	var blank: Dictionary = station.try_finish("")
	_ok(blank.get("finished", false) == true, "ungraded finishes (nothing to improve)")
	_ok(String(blank.get("grade", "")) == "", "ungraded stays ungraded")
	# F is refused outright.
	var f: Dictionary = station.try_finish("F")
	_ok(f.get("finished", false) == false, "F refused (finished false)")
	_ok(String(f.get("grade", "")) == "F", "F stays F")
	# Unknown inputs fail closed.
	for g in ["Z", "b", "AB", "ff"]:
		var bad: Dictionary = station.try_finish(g)
		_ok(bad.get("finished", true) == false, "unknown '%s' fails closed" % g)
		_ok(String(bad.get("grade", "")) == "F", "unknown '%s' reports F" % g)
	station.queue_free()


func _test_last_result_and_signal() -> void:
	var station: FinishingStation = FinishingStation.new()
	var sigs: Array = []
	station.finished.connect(func(old_g: String, new_g: String) -> void:
		sigs.append([old_g, new_g]))
	root.add_child(station)

	var res: Dictionary = station.try_finish("C")
	_ok(station.last_result == res, "last_result mirrors the C call")
	_ok(sigs.size() == 1, "exactly one finished signal on a real change")
	_ok(sigs[0][0] == "C" and sigs[0][1] == "B", "signal args (old, new) correct")

	# No change -> no signal, but last_result still updates.
	res = station.try_finish("A")
	_ok(station.last_result == res, "last_result mirrors the A call")
	_ok(sigs.size() == 1, "A emits no signal")
	res = station.try_finish("F")
	_ok(station.last_result == res, "last_result mirrors the F refusal")
	_ok(sigs.size() == 1, "F refusal emits no signal")
	res = station.try_finish("Z")
	_ok(station.last_result == res, "last_result mirrors the unknown refusal")
	_ok(sigs.size() == 1, "unknown refusal emits no signal")

	# A second real change fires exactly once more.
	station.try_finish("B")
	_ok(sigs.size() == 2, "second real change emits exactly once more")
	_ok(sigs[1][0] == "B" and sigs[1][1] == "A", "second signal B -> A")

	station.queue_free()


func _visible_mesh_count(station: FinishingStation) -> int:
	var n := 0
	for m in station.find_children("*", "MeshInstance3D", true, false):
		if m.visible:
			n += 1
	return n


func _test_station_shape() -> void:
	var station: FinishingStation = FinishingStation.new()
	root.add_child(station)
	_ok(station is Node3D, "station is a Node3D")
	_ok(station.is_in_group("stations"), "station joins 'stations' group")
	_ok(String(station.get_meta("station_kind", "")) == "finishing",
		"meta station_kind = 'finishing'")
	var body: Array = station.find_children("*", "StaticBody3D", true, false)
	_ok(body.size() >= 1, "station has a StaticBody3D collision body")
	if body.size() >= 1:
		var shapes: Array = body[0].find_children("*", "CollisionShape3D", true, false)
		_ok(shapes.size() >= 1, "collision body has a CollisionShape3D")
		if shapes.size() >= 1:
			_ok(shapes[0].shape is BoxShape3D, "collision shape is a BoxShape3D")
	var meshes: Array = station.find_children("*", "MeshInstance3D", true, false)
	_ok(meshes.size() >= 3, "station built from primitive meshes (top, legs, basin)")
	# Sign in the PackingStation style.
	var labels: Array = station.find_children("*", "Label3D", true, false)
	var sign: Label3D = null
	for l in labels:
		if String(l.text) == "FINISHING":
			sign = l
	_ok(sign != null, "station carries a 'FINISHING' sign")
	if sign != null:
		_ok(sign.font_size == 48 and absf(sign.pixel_size - 0.0022) < 0.0001,
			"sign sized like the packing sign (48 / 0.0022)")
		_ok(sign.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "sign billboards")
		_ok(sign.modulate == Color("#EEE5D3")
			and sign.outline_modulate == Color("#202B2B"), "sign uses the shop palette")
	station.queue_free()


func _test_set_active() -> void:
	var station: FinishingStation = FinishingStation.new()
	root.add_child(station)
	station.set_active(false)
	var off := _visible_mesh_count(station)
	station.set_active(true)
	_ok(station.is_active(), "set_active(true) marks the bench active")
	var on := _visible_mesh_count(station)
	_ok(on == off + 1, "active bench reveals exactly the working strip")
	var lights: Array = station.find_children("*", "OmniLight3D", true, false)
	_ok(lights.size() == 1 and lights[0].visible, "spill light toggles on")
	station.set_active(false)
	_ok(not station.is_active(), "set_active(false) clears the bench")
	_ok(_visible_mesh_count(station) == off, "strip hides again when idle")
	_ok(lights.size() == 1 and not lights[0].visible, "spill light toggles off")
	station.queue_free()

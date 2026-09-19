extends SceneTree

## Packing station tests (task 11, station layer only). Pure logic + station
## node, no Main scene (Main integration is a parent-owned follow-up).
## Run: timeout 60 godot --headless --path . -s tests/packing_test.gd
## RED before QualityCheck.gd / PackingStation.gd exist; GREEN after.

const Contract := preload("res://scripts/Contract.gd")
const QualityCheck := preload("res://scripts/QualityCheck.gd")
const PackingStation := preload("res://scripts/PackingStation.gd")

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _grade(final_layer: int, total_layers: int, risks: Dictionary) -> String:
	return QualityCheck.grade(null, final_layer, total_layers, risks)


func _mk_contract(state: int, payout_cents: int) -> Contract:
	var c := Contract.new()
	c.id = "C-PACK"
	c.client = "Test Client"
	c.model_name = "Test Model"
	c.payout_cents = payout_cents
	c.material_cost_cents = 100
	c.difficulty = 1
	c.risk_flags = []
	c.layers = 10
	c.deadline_days = 1
	c.state = state
	return c


func _snapshot(final_layer: int, total_layers: int, risks: Dictionary) -> Dictionary:
	return {"final_layer": final_layer, "total_layers": total_layers, "risks": risks}


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	_test_grade_complete_boundaries()
	_test_grade_completion_boundaries()
	_test_grade_wild_and_degenerate()
	_test_grade_deterministic()
	_test_multiplier_table()
	_test_try_pack_wrong_state()
	_test_try_pack_null_contract()
	_test_try_pack_grades_and_payouts()
	_test_try_pack_signal_exactly_once()
	_test_try_pack_no_state_mutation()
	_test_station_shape()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	if failures > 0:
		printerr("packing_test: %d/%d checks FAILED" % [failures, checks])
	elif checks == 0:
		printerr("packing_test: no checks ran")
		code = 1
	else:
		print("packing_test: all %d checks passed" % checks)
	quit(code)


func _test_grade_complete_boundaries() -> void:
	# Complete print (final == total), risk max vs the 0.5 / 0.7 cut lines.
	_ok(_grade(10, 10, {}) == "A", "complete + no risks -> A")
	_ok(_grade(10, 10, {"overhangs": 0.49}) == "A", "complete + risk 0.49 -> A")
	_ok(_grade(10, 10, {"overhangs": 0.5}) == "B", "risk exactly 0.5 -> B (not A)")
	_ok(_grade(10, 10, {"stability": 0.69}) == "B", "risk 0.69 -> B")
	_ok(_grade(10, 10, {"stability": 0.7}) == "C", "risk exactly 0.7 -> C (not B)")
	_ok(_grade(10, 10, {"bed adhesion": 0.99}) == "C", "complete + bounded risk 0.99 -> C")
	# Max across multiple risk entries wins.
	_ok(_grade(10, 10, {"overhangs": 0.2, "stability": 0.6}) == "B", "max of risks 0.2/0.6 -> B")
	_ok(_grade(10, 10, {"overhangs": 0.2, "stability": 0.75}) == "C", "max of risks 0.2/0.75 -> C")


func _test_grade_completion_boundaries() -> void:
	# 0.9 * total completion line, exact.
	_ok(_grade(9, 10, {}) == "C", "9/10 layers -> C")
	_ok(_grade(8, 10, {}) == "F", "8/10 layers -> F")
	_ok(_grade(210, 210, {}) == "A", "210/210 -> A")
	_ok(_grade(189, 210, {}) == "C", "189/210 == 0.9*total exactly -> C")
	_ok(_grade(188, 210, {}) == "F", "188/210 < 0.9*total -> F")
	# Completion never upgrades past risk cuts: short print with zero risk stays C.
	_ok(_grade(9, 10, {"overhangs": 0.1}) == "C", "9/10 + low risk -> C")


func _test_grade_wild_and_degenerate() -> void:
	# Wild risk data (outside [0, 1]) fails inspection outright.
	_ok(_grade(10, 10, {"overhangs": 1.5}) == "F", "risk 1.5 (wild) -> F even when complete")
	_ok(_grade(10, 10, {"overhangs": -0.1}) == "F", "negative risk (wild) -> F")
	# Degenerate layer counts.
	_ok(_grade(0, 0, {}) == "F", "zero total layers -> F")
	_ok(_grade(-1, 10, {}) == "F", "negative final layer -> F")


func _test_grade_deterministic() -> void:
	var risks := {"overhangs": 0.42}
	var a: String = QualityCheck.grade(null, 10, 10, risks)
	var b: String = QualityCheck.grade(null, 10, 10, risks)
	_ok(a == b and a == "A", "grade is deterministic across calls")


func _test_multiplier_table() -> void:
	_ok(is_equal_approx(QualityCheck.quality_multiplier("A"), 1.0), "multiplier A = 1.0")
	_ok(is_equal_approx(QualityCheck.quality_multiplier("B"), 0.9), "multiplier B = 0.9")
	_ok(is_equal_approx(QualityCheck.quality_multiplier("C"), 0.7), "multiplier C = 0.7")
	_ok(is_equal_approx(QualityCheck.quality_multiplier("F"), 0.0), "multiplier F = 0.0")
	_ok(is_equal_approx(QualityCheck.quality_multiplier(""), 0.0), "multiplier unknown '' -> 0.0")
	_ok(is_equal_approx(QualityCheck.quality_multiplier("Z"), 0.0), "multiplier unknown 'Z' -> 0.0")


func _test_try_pack_wrong_state() -> void:
	var station: PackingStation = PackingStation.new()
	var sigs: Array = []
	station.packed.connect(func(cid: String, g: String, pc: int) -> void:
		sigs.append([cid, g, pc]))
	root.add_child(station)

	var c := _mk_contract(Contract.State.PRINTING, 6400)
	var res: Dictionary = station.try_pack(c, _snapshot(10, 10, {}))
	_ok(res.get("packed", true) == false, "PRINTING contract rejected (packed false)")
	_ok(String(res.get("reason", "")) != "", "rejection carries a reason")
	_ok(int(res.get("payout_cents", -1)) == 0, "rejected pack pays 0")
	_ok(String(res.get("grade", "X")) == "", "rejected pack has no grade")
	_ok(sigs.is_empty(), "no packed signal on rejected state")
	_ok(station.last_result == res, "last_result mirrors rejection")

	# Also a terminal state.
	c.state = Contract.State.DELIVERED
	res = station.try_pack(c, _snapshot(10, 10, {}))
	_ok(res.get("packed", true) == false, "DELIVERED contract rejected")
	_ok(sigs.is_empty(), "still no signal after DELIVERED rejection")

	station.queue_free()


func _test_try_pack_null_contract() -> void:
	var station: PackingStation = PackingStation.new()
	var res: Dictionary = station.try_pack(null, _snapshot(10, 10, {}))
	_ok(res.get("packed", true) == false, "null contract rejected")
	_ok(String(res.get("reason", "")) != "", "null rejection has reason")
	station.queue_free()


func _test_try_pack_grades_and_payouts() -> void:
	# A: full payout.
	var station: PackingStation = PackingStation.new()
	root.add_child(station)
	var a := _mk_contract(Contract.State.INSPECTION, 6400)
	var res: Dictionary = station.try_pack(a, _snapshot(10, 10, {}))
	_ok(res.get("packed", false) == true, "A-grade packs")
	_ok(res.get("grade", "") == "A", "A-grade reported")
	_ok(int(res.get("payout_cents", 0)) == 6400, "A pays full 6400")
	_ok(String(res.get("reason", "x")) != "", "success result carries reason")
	_ok(station.last_result == res, "last_result mirrors success")

	# B: exactly 90%.
	var b := _mk_contract(Contract.State.INSPECTION, 4200)
	res = station.try_pack(b, _snapshot(10, 10, {"overhangs": 0.5}))
	_ok(res.get("grade", "") == "B", "risk 0.5 snapshot grades B")
	_ok(int(res.get("payout_cents", 0)) == 3780, "B pays 4200 * 0.9 = 3780")

	# C: exactly 70%.
	var cc := _mk_contract(Contract.State.INSPECTION, 4200)
	res = station.try_pack(cc, _snapshot(9, 10, {}))
	_ok(res.get("grade", "") == "C", "9/10 snapshot grades C")
	_ok(int(res.get("payout_cents", 0)) == 2940, "C pays 4200 * 0.7 = 2940")

	# Rounding: 999 * 0.7 = 699.3 -> roundi -> 699.
	var r := _mk_contract(Contract.State.INSPECTION, 999)
	res = station.try_pack(r, _snapshot(9, 10, {}))
	_ok(int(res.get("payout_cents", 0)) == 699, "roundi rounding on 999*0.7 -> 699")

	# F: zero payout, not packed.
	var f := _mk_contract(Contract.State.INSPECTION, 4200)
	res = station.try_pack(f, _snapshot(5, 10, {}))
	_ok(res.get("grade", "x") == "F", "5/10 snapshot grades F")
	_ok(res.get("packed", true) == false, "F does not pack")
	_ok(int(res.get("payout_cents", -1)) == 0, "F pays 0")

	station.queue_free()


func _test_try_pack_signal_exactly_once() -> void:
	var station: PackingStation = PackingStation.new()
	var sigs: Array = []
	station.packed.connect(func(cid: String, g: String, pc: int) -> void:
		sigs.append([cid, g, pc]))
	root.add_child(station)

	var c := _mk_contract(Contract.State.INSPECTION, 4200)
	station.try_pack(c, _snapshot(10, 10, {"stability": 0.6}))
	_ok(sigs.size() == 1, "exactly one packed signal on success")
	_ok(sigs[0][0] == "C-PACK" and sigs[0][1] == "B" and sigs[0][2] == 3780,
		"signal args (id, grade, payout) correct")

	# A rejection afterwards emits nothing more.
	station.try_pack(_mk_contract(Contract.State.OFFERED, 100), _snapshot(10, 10, {}))
	_ok(sigs.size() == 1, "rejection adds no second signal")

	station.queue_free()


func _test_try_pack_no_state_mutation() -> void:
	# Station layer only: the INSPECTION -> PACKED contract write stays with
	# Main. try_pack must leave the contract state untouched.
	var station: PackingStation = PackingStation.new()
	root.add_child(station)
	var c := _mk_contract(Contract.State.INSPECTION, 6400)
	station.try_pack(c, _snapshot(10, 10, {}))
	_ok(c.state == Contract.State.INSPECTION, "try_pack does not mutate contract state")
	station.queue_free()


func _test_station_shape() -> void:
	var station: PackingStation = PackingStation.new()
	root.add_child(station)
	_ok(station is Node3D, "station is a Node3D")
	_ok(station.is_in_group("stations"), "station joins 'stations' group")
	_ok(String(station.get_meta("station_kind", "")) == "packing", "meta station_kind = 'packing'")
	var body: Array = station.find_children("*", "StaticBody3D", true, false)
	_ok(body.size() >= 1, "station has a StaticBody3D collision body")
	if body.size() >= 1:
		var shapes: Array = body[0].find_children("*", "CollisionShape3D", true, false)
		_ok(shapes.size() >= 1, "collision body has a CollisionShape3D")
	var meshes: Array = station.find_children("*", "MeshInstance3D", true, false)
	_ok(meshes.size() >= 3, "station built from primitive meshes (table, legs/fascia, box)")
	station.queue_free()

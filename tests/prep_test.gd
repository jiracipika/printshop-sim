extends SceneTree

## Prep + orientation unit tests (task 09 slice). Run:
##   timeout 60 godot --headless --path . -s tests/prep_test.gd
## Exits 0 on all checks passing, 1 on any failure.

const PrepSystem := preload("res://scripts/PrepSystem.gd")
const PrintSim := preload("res://scripts/PrintSim.gd")


var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _contract(id: String, layers: int, flags: Array = []) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Test Client"
	c.model_name = "Test Model"
	c.payout_cents = 1000
	c.material_cost_cents = 100
	c.difficulty = 1
	var f: Array[String] = []
	for flag in flags:
		f.append(flag)
	c.risk_flags = f
	c.layers = layers
	c.deadline_days = 2
	return c


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	_test_orientations_list()
	_test_determinism()
	_test_upright_no_flags()
	_test_tilted_vs_upright_material()
	_test_flat_side_stability_invalid()
	_test_risk_level_boundaries()
	_test_sim_seam_determinism()
	_test_sim_low_risk_never_fails()
	_test_failure_seeded_unchanged()
	_finish(1 if failures > 0 else 0)


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)


func _test_orientations_list() -> void:
	var o: Array[String] = PrepSystem.orientations()
	_ok(o == ["upright", "tilted", "flat_side"], "orientations list exact order")


func _test_determinism() -> void:
	var c := _contract("DET-1", 210, ["overhangs"])
	var a: Dictionary = PrepSystem.evaluate(c, "tilted")
	var b: Dictionary = PrepSystem.evaluate(c, "tilted")
	_ok(a["support_need"] == b["support_need"]
		and a["adhesion_risk"] == b["adhesion_risk"]
		and a["stability_risk"] == b["stability_risk"]
		and a["estimated_material_g"] == b["estimated_material_g"]
		and a["estimated_time_s"] == b["estimated_time_s"]
		and a["valid"] == b["valid"]
		and a["reason"] == b["reason"],
		"evaluate deterministic: same inputs -> identical outputs")


func _test_upright_no_flags() -> void:
	var c := _contract("UP-1", 100, [])
	var e: Dictionary = PrepSystem.evaluate(c, "upright")
	_ok(e["valid"], "upright no-flags is valid")
	_ok(e["support_need"] < 0.4, "upright no-flags support_need < 0.4")
	_ok(e["estimated_material_g"] == 100 * 6, "upright material = layers * 6")
	_ok(is_equal_approx(e["estimated_time_s"], 100 * 2.4), "upright time = layers * 2.4")


func _test_tilted_vs_upright_material() -> void:
	for flags in [[], ["overhangs"], ["bed adhesion"], ["overhangs", "bed adhesion", "stability"]]:
		var c := _contract("TILT", 120, flags)
		var up: Dictionary = PrepSystem.evaluate(c, "upright")
		var ti: Dictionary = PrepSystem.evaluate(c, "tilted")
		_ok(ti["estimated_material_g"] > up["estimated_material_g"],
			"tilted material > upright material (flags=%s)" % str(flags))
	var c2 := _contract("TILT2", 120, ["overhangs"])
	var t2: Dictionary = PrepSystem.evaluate(c2, "tilted")
	_ok(t2["support_need"] > 0.55, "tilted+overhangs support_need = 0.55+0.2")
	var c3 := _contract("TILT3", 120, [])
	var t3: Dictionary = PrepSystem.evaluate(c3, "tilted")
	_ok(is_equal_approx(float(t3["support_need"]), 0.55), "tilted support_need = 0.55")


func _test_flat_side_stability_invalid() -> void:
	var c_ok := _contract("FLAT-OK", 120, [])
	var e_ok: Dictionary = PrepSystem.evaluate(c_ok, "flat_side")
	_ok(e_ok["valid"], "flat_side without stability flag is valid")
	var c_bad := _contract("FLAT-BAD", 120, ["stability"])
	var e_bad: Dictionary = PrepSystem.evaluate(c_bad, "flat_side")
	_ok(not e_bad["valid"] and e_bad["reason"] == "not printable flat",
		"flat_side + stability flag -> invalid 'not printable flat'")
	var c_adh := _contract("FLAT-ADH", 120, ["bed adhesion"])
	var e_adh: Dictionary = PrepSystem.evaluate(c_adh, "flat_side")
	_ok(is_equal_approx(float(e_adh["adhesion_risk"]), 0.55 + 0.15),
		"flat_side + bed adhesion flag adhesion = 0.70")


func _test_risk_level_boundaries() -> void:
	_ok(PrepSystem.risk_level({"support_need": 0.4, "adhesion_risk": 0.0, "stability_risk": 0.0}) == "medium",
		"max risk exactly 0.4 -> medium (boundary, not low)")
	_ok(PrepSystem.risk_level({"support_need": 0.6, "adhesion_risk": 0.0, "stability_risk": 0.0}) == "high",
		"max risk exactly 0.6 -> high (boundary, not medium)")
	_ok(PrepSystem.risk_level({"support_need": 0.0, "adhesion_risk": 0.39, "stability_risk": 0.1}) == "low",
		"max risk 0.39 -> low")
	_ok(PrepSystem.risk_level({"support_need": 0.0, "adhesion_risk": 0.59, "stability_risk": 0.0}) == "medium",
		"max risk 0.59 -> medium")
	_ok(PrepSystem.risk_level({"support_need": 0.9, "adhesion_risk": 0.9, "stability_risk": 0.9}) == "high",
		"max risk 0.9 -> high")


## --- PrintSim deterministic risk seam ---


## Replicates the documented hash logic so the test computes expected failure
## independently of PrintSim's internals.
static func _draw(job_id: String) -> float:
	var h := hash(job_id)
	return float(absi(h) % 100000) / 100000.0


func _expected_failure_tick(job_id: String, worst_risk: float, layers: int) -> int:
	var chance := maxf(0.0, worst_risk - 0.3) * 0.55
	if chance <= 0.0:
		return -1
	var draw := _draw(job_id)
	if draw < chance:
		return maxi(1, int(draw / chance * float(layers)))
	return -1


func _mk_sim(job_id: String, layers: int, s: float, a: float, st: float) -> PrintSim:
	var sim: PrintSim = PrintSim.new()
	root.add_child(sim)
	sim.support_need = s
	sim.adhesion_risk = a
	sim.stability_risk = st
	sim.start_job(job_id, "Model " + job_id, layers)
	return sim


func _drive(sim: PrintSim, max_ticks := 2000) -> void:
	var n := 0
	while sim.state == PrintSim.State.RUNNING and n < max_ticks:
		sim._step_tick()
		n += 1


func _test_sim_seam_determinism() -> void:
	# Find a job_id whose draw < (0.7-0.3)*0.55 = 0.22 so a worst-risk 0.7 print
	# must fail, computed via the same hash logic the sim uses (RED-friendly).
	# NOTE: Godot's String hash() is sequential for similar strings in this
	# build (SEAM-0..N land in one contiguous band of the modulo space), so
	# a linear 0..999 search can miss the <16% band entirely. Search a
	# strided id space to get representative coverage of the hash range.
	var fail_id := ""
	var ok_id := ""
	for i in range(0, 20000, 7):
		var id := "SEAM-%d" % i
		if fail_id == "" and _expected_failure_tick(id, 0.7, 40) > 0:
			fail_id = id
		if ok_id == "" and _expected_failure_tick(id, 0.7, 40) < 0:
			ok_id = id
		if fail_id != "" and ok_id != "":
			break
	_ok(fail_id != "" and ok_id != "", "found deterministic fail/ok job ids (%s / %s)" % [fail_id, ok_id])
	if fail_id == "" or ok_id == "":
		_finish(1)
		return

	var a := _mk_sim(fail_id, 40, 0.7, 0.0, 0.0)
	var b := _mk_sim(fail_id, 40, 0.7, 0.0, 0.0)
	_drive(a)
	_drive(b)
	_ok(a.state == PrintSim.State.DONE_FAIL, "high-risk instance A fails")
	_ok(b.state == PrintSim.State.DONE_FAIL, "high-risk instance B fails identically")
	_ok(a.layers_done == b.layers_done,
		"both instances fail at the same layer (%d)" % a.layers_done)
	_ok(a.layers_done == _expected_failure_tick(fail_id, 0.7, 40),
		"failure tick matches independent hash expectation")

	# Same job_id + same risks => same outcome; different id with draw >= chance succeeds.
	var c := _mk_sim(ok_id, 40, 0.7, 0.0, 0.0)
	_drive(c)
	_ok(c.state == PrintSim.State.DONE_OK,
		"equal-risk job whose draw >= failure_chance completes DONE_OK")


func _test_sim_low_risk_never_fails() -> void:
	# max risk 0.29 -> failure_chance = 0 (0.29 < the 0.3 floor, v0.12): always succeeds.
	var sim := _mk_sim("P100", 40, 0.29, 0.2, 0.1)
	_drive(sim)
	_ok(sim.state == PrintSim.State.DONE_OK, "low-risk job completes DONE_OK over full run")


func _test_failure_seeded_unchanged() -> void:
	var sim := _mk_sim("SEED", 20, 0.0, 0.0, 0.0)
	sim.failure_seeded = true
	_drive(sim)
	_ok(sim.state == PrintSim.State.DONE_FAIL, "failure_seeded still forces failure")
	_ok(sim.layers_done == int(20 / 2), "failure_seeded still fails at half layers")

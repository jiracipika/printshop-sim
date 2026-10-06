extends SceneTree

const BrowserSave = preload("res://scripts/BrowserSave.gd")

## v0.45.0 — "wear & tear": completed prints accrue machine wear (6 +
## difficulty; 12 on a failure), wear widens the PrintSim failure threshold
## at start_job (0.55 fresh -> 0.80 at 100), and an idle printer at 50+
## wear offers a 15 s cleaning cycle on E (resets wear, counts toward the
## Meticulous milestone). Cleaning never fires below 50 wear, so the accept
## press at a lightly-worn printer is never stolen.
## Run: godot --headless --path . -s tests/v045_test.gd

var checks := 0
var failures := 0
var main = null


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _drive(max_steps := 60000) -> void:
	var steps := 0
	while main.sim.state == PrintSim.State.RUNNING and steps < max_steps:
		main.sim.tick(1.0 / 60.0)
		steps += 1


func _stand_at_printer_a() -> void:
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main.yaw = 0.0
	main._player.rotation.y = main.yaw


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	BrowserSave.clear()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true

	var fresh := true
	for m in main.machines:
		if float(m.get("wear", -1.0)) != 0.0 or float(m.get("clean_left_s", -1.0)) != 0.0:
			fresh = false
	_ok(fresh, "fresh machines carry no wear and no clean countdown")

	# --- full loop: accept -> prep -> confirm -> collect -> pack -------------
	_stand_at_printer_a()
	main._try_interact()  # accept
	var c0 = main.active_contract
	if c0 == null:
		_ok(false, "E at printer A accepts a contract")
		_finish()
		return
	_ok(c0.state == Contract.State.PREPARING, "accept parks the contract at PREPARING")
	main._try_interact()  # preview
	main._try_interact()  # confirm
	_ok(c0.state == Contract.State.PRINTING and main.sim.is_running(),
		"confirm starts the print")
	_ok(absf(main.sim.failure_threshold - 0.55) < 0.001,
		"a fresh machine keeps the pinned 0.55 failure threshold")
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_OK, "print completes")
	main.paused = false
	main._try_interact()  # collect the part
	_ok(main._is_held_part(), "collect attaches the part")
	var diff1: int = c0.difficulty
	_ok(main._try_pack_held(), "pack delivers the part")
	_ok(absf(float(main._machine(0).get("wear")) - float(6 + diff1)) < 0.001,
		"completed print accrues 6+difficulty wear (got %.0f, diff %d)" % [
			float(main._machine(0).get("wear")), diff1])

	# --- light wear never steals the accept press ----------------------------
	main._try_interact()
	var c1 = main.active_contract
	_ok(c1 != null and c1.state == Contract.State.PREPARING,
		"a lightly-worn idle printer still accepts on E")

	# --- worn threshold written at start_job ---------------------------------
	var wear_now := float(main._machine(0).get("wear"))
	main._machine(0)["filament_g"] = 5000  # test setup: room for a second job
	main._try_interact()  # preview
	main._try_interact()  # confirm
	_ok(c1.state == Contract.State.PRINTING, "second print confirmed")
	_ok(absf(main.sim.failure_threshold - (0.55 + 0.25 * wear_now / 100.0)) < 0.0001,
		"start_job widens the threshold by the wear fraction")

	# --- failed print accrues 12 ---------------------------------------------
	main.sim.failure_seeded = true
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_FAIL, "seeded failure lands")
	main.sim.failure_seeded = false
	main.paused = false
	main._try_interact()  # clear the failed print
	_ok(absf(float(main._machine(0).get("wear")) - (wear_now + 12.0)) < 0.001,
		"failed print accrues 12 wear (now %.0f)" % float(main._machine(0).get("wear")))
	_ok(main.active_contract == null, "machine idle after the clear")

	# --- cleaning cycle -------------------------------------------------------
	main._machine(0)["wear"] = 60.0
	main._try_interact()
	_ok(absf(float(main._machine(0).get("clean_left_s")) - main.CLEAN_TIME_S) < 0.001,
		"E at a 50%+ worn idle printer starts a clean")
	_ok("Cleaning" in str(main._prompt.text), "prompt names the cleaning")
	var board_before: int = main.job_board.get_available_count()
	main._try_interact()
	_ok(main.active_contract == null and main.job_board.get_available_count() == board_before,
		"E during a clean neither accepts nor mutates the board")
	_ok("Cleaning" in str(main._prompt.text), "E during a clean reports the countdown")
	main._machine(0)["clean_left_s"] = 0.016
	await physics_frame
	await physics_frame
	await physics_frame
	_ok(float(main._machine(0).get("wear")) == 0.0
		and float(main._machine(0).get("clean_left_s")) == 0.0,
		"cycle completion resets wear and the countdown")
	_ok(int(main.cleans) == 1, "the clean is counted")

	# --- Meticulous milestone -------------------------------------------------
	main.cleans = 9
	main._machine(0)["wear"] = 60.0
	main._try_interact()
	main._machine(0)["clean_left_s"] = 0.016
	await physics_frame
	await physics_frame
	await physics_frame
	var meticulous := false
	for a in main._achievements():
		if a.name == "Meticulous":
			meticulous = bool(a.done)
	_ok(int(main.cleans) == 10 and meticulous, "10 cleans unlock Meticulous")

	# --- persistence -----------------------------------------------------------
	main._machine(0)["wear"] = 12.0
	main._machine(1)["wear"] = 100.0
	main.cleans = 4
	main._save_game()
	var saved: Dictionary = BrowserSave.load_payload()
	var wear_ok: bool = typeof(saved.get("wear")) == TYPE_ARRAY \
		and saved["wear"].size() == 4 \
		and int(saved["wear"][0]) == 12 and int(saved["wear"][1]) == 100
	_ok(wear_ok, "per-machine wear persists in the payload")
	_ok(int(saved.get("cleans", -1)) == 4, "clean count persists")
	var ss = load("res://scripts/SaveSystem.gd")
	var no_wear: Dictionary = saved.duplicate(true)
	no_wear.erase("wear")
	no_wear.erase("cleans")
	_ok(not ss.validate(no_wear).is_empty(),
		"payloads without wear/cleans still validate (old saves)")
	var neg: Dictionary = saved.duplicate(true)
	neg["wear"] = [-1, 0, 0, 0]
	_ok(ss.validate(neg).is_empty(), "validator rejects negative wear")
	var over: Dictionary = saved.duplicate(true)
	over["wear"] = [101, 0, 0, 0]
	_ok(ss.validate(over).is_empty(), "validator rejects wear over 100")
	var bad_cleans: Dictionary = saved.duplicate(true)
	bad_cleans["cleans"] = -2
	_ok(ss.validate(bad_cleans).is_empty(), "validator rejects a negative clean count")

	# --- restore path: a fresh boot picks wear + cleans up ---------------------
	var packed2: PackedScene = load("res://scenes/Main.tscn")
	var main2 = packed2.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	_ok(float(main2._machine(0).get("wear")) == 12.0
		and float(main2._machine(1).get("wear")) == 100.0
		and int(main2.cleans) == 4,
		"restored boot rebuilds wear and the clean count")
	main2.queue_free()
	await physics_frame

	_finish()


func _finish() -> void:
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

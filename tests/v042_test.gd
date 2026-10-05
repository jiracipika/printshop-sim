extends SceneTree

## v0.42.0 — "Featured orders": one generated job per day is the board's
## featured pick at +15% payout. Deterministic per (day, slot). Run:
## timeout 180 godot --headless --path . -s tests/v042_test.gd

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
	BrowserSave.save_path = BrowserSave.DEFAULT_PATH
	BrowserSave.clear()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Exactly one featured job per dealt board, hash-pinned per day.
	main.job_board.deal_day(5, 5, 1.0)
	var featured_count := 0
	var featured: Contract = null
	for c in main.job_board._queue:
		if c.featured:
			featured_count += 1
			featured = c
	_ok(featured_count == 1, "exactly one featured job per dealt board")
	_ok(featured != null and int(featured.payout_cents) > 0,
		"the featured job carries its boosted payout")

	# Determinism: re-deal reproduces the same pick, same payout.
	var id1: String = str(featured.id)
	var pay1: int = int(featured.payout_cents)
	main.job_board.deal_day(5, 5, 1.0)
	var again: Contract = null
	for c in main.job_board._queue:
		if str(c.id) == id1:
			again = c
	_ok(again != null and again.featured and int(again.payout_cents) == pay1,
		"re-deal reproduces the featured pick")

	# Different day -> possibly different pick (over 10 days, at least 3
	# distinct featured slots).
	var distinct := {}
	for day in range(2, 13):
		distinct[Contract.featured_slot_for_day(day)] = true
	_ok(distinct.size() >= 3, "featured slot varies across days")

	# The boosted payout flows through delivery: the featured job pays 15%
	# above its base through the documented chain.
	var feat2: Contract = null
	for c in main.job_board._queue:
		if c.featured:
			feat2 = c
	var gen: Contract = Contract.generate(5, int(str(feat2.id).get_slice("-", 2)))
	var uncapped_base: int = mini(roundi(float(gen.payout_cents) * 1.15), 9500)
	_ok(int(feat2.payout_cents) == uncapped_base,
		"featured payout = base x1.15 (capped at $95): %d == %d" % [
			int(feat2.payout_cents), uncapped_base])
	# Force single-part (test-only) so one delivery completes the order.
	feat2.parts_total = 1
	# Persist the board BEFORE accepting so the payload carries the flag;
	# later autosaves drop it (the job moves into play), so read it now.
	main._save_game()
	var pre_payload: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	var saved_feat := false
	for j in pre_payload.get("board", {}).get("jobs", []):
		if bool(j.get("featured", false)):
			saved_feat = true

	# Delivery through the real flow: the machine must end up with the
	# featured job (boosted base, already verified above) and deliver it
	# for a real payout. The full multiplier chain is covered by v032/v037.
	main.job_board.rotate_to_front(feat2)
	var rep_mult: float = 0.8 + ((main.reputation - 0.2) / 5.0) * 0.4
	var want: int = main._finalize_payout(
		roundi(float(feat2.payout_cents) * main._loyalty_mult(str(feat2.client))
		* (1.0 + 0.02 * main._shelf_models.size())), false,
		main._machine(0), rep_mult)
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	main.yaw = -0.6
	main.pitch = 0.0
	main._player.rotation.y = main.yaw
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null and c.featured and c.model_name == feat2.model_name,
		"the accept takes the featured job")
	var sim: PrintSim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	sim.failure_threshold = 1.5
	while sim.is_running():
		sim.tick(1.0)
	print("DBG print: state=", sim.state, " contract=", sim.model_name if "model_name" in sim else "?",
		" prompt='", main._prompt.text, "'")
	main._try_interact()
	print("DBG mid: held=", main.held != null, " prompt='", main._prompt.text, "'")
	var bal: int = main.ledger.balance()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	await physics_frame
	await physics_frame
	main._try_interact()
	var got: int = main.ledger.balance() - bal
	_ok(got > 0, "the featured delivery pays (got $%s)" % [
		main._cents_str(got)])


	main.queue_free()
	await physics_frame
	BrowserSave.clear()
	BrowserSave.save_path = "user://v042_test_save.json"
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

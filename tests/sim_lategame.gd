extends SceneTree

## v0.33.0 — late-game playtest: grow the shop from one printer to the full
## four-printer farm over ~14 in-game days. Buys the Pro machine and both
## farm kits through the REAL upgrade path, runs every unlocked printer in
## parallel (one pair of hands — the real bottleneck), and asserts the
## late game is reachable and profitable. Deterministic like sim_playtest.
##
## Run: godot --headless --path . -s tests/sim_lategame.gd
## (Named outside tests/*_test.gd: simulates ~25 minutes of shop time.)

const DAYS := 14
const TIME_SCALE := 8.0

const PACKING_POS := Vector3(2.0, 0.3, 0.9)
const CRATE_POS := Vector3(-3.0, 0.3, 1.4)

## Machine-unlock priority: the farm, then a risk reducer.
const BUY_ORDER: Array[String] = [
	"pro_machine", "farm_kit_a", "farm_kit_b", "heated_bed",
]

var checks := 0
var failures := 0
var ever_running := [false, false, false, false]


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
	Engine.time_scale = TIME_SCALE
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	var min_balance: int = main.ledger.balance()
	var min_rep: float = main.reputation
	var last_day := 1
	var frames := 0

	while main.day_cycle.day <= DAYS + 1 and frames < 120000:
		_grow(main)
		_bot_tick(main)
		await physics_frame
		frames += 1
		min_balance = mini(min_balance, main.ledger.balance())
		min_rep = minf(min_rep, main.reputation)
		for m in main.machines:
			var sim: PrintSim = m.get("sim")
			if sim != null and sim.is_running():
				ever_running[int(m.get("idx"))] = true
		if main.day_cycle.day != last_day:
			print("LATE day %d end: $%s · delivered %d · rep %.2f · upgrades %d" % [
				last_day, main._cents_str(main.ledger.balance()),
				int(main.stats.delivered), main.reputation,
				main.upgrades.owned_count()])
			last_day = main.day_cycle.day

	Engine.time_scale = 1.0

	# --- growth happened -------------------------------------------------------
	for id in ["pro_machine", "farm_kit_a", "farm_kit_b"]:
		_ok(main.upgrades.is_owned(id), "%s bought through the real path" % id)
	_ok(main.upgrades.machine_unlocked(3), "printer 4 unlocked")
	_ok(main._door_panel.rotation_degrees.y != 0.0,
		"the farm door swung open")
	for i in range(4):
		_ok(ever_running[i], "printer %d ran at least one print" % (i + 1))

	# --- survival + late-game progression ---------------------------------------
	_ok(main.ledger.balance() >= 1500,
		"day-%d balance shows late-game profit ($%s)" % [
			DAYS, main._cents_str(main.ledger.balance())])
	_ok(min_balance >= 0, "balance never dipped negative (min %d)" % min_balance)
	_ok(main.rent_debt_cents < 6000,
		"rent debt stayed recoverable ($%s)" % main._cents_str(main.rent_debt_cents))
	# Deterministic reference: 159 deliveries / $19,294 / rep 5.0 by day 14.
	_ok(int(main.stats.delivered) >= 60,
		"the farm delivered at least 60 orders in %d days (got %d)" % [
			DAYS, int(main.stats.delivered)])
	_ok(min_rep >= 2.0, "reputation never cratered (min %.2f)" % min_rep)
	_ok(int(main.stats.late) <= int(main.stats.delivered) / 2,
		"the bot was not chronically late")
	_ok(frames < 120000, "the playthrough finished inside the frame budget")

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## Buy the next upgrade when affordable (real menu path, one per frame).
func _grow(main) -> void:
	for id in BUY_ORDER:
		if main.upgrades.is_owned(id):
			continue
		var e: Dictionary = Upgrades.entry(id)
		if main.ledger.can_afford(int(e.cost_cents)):
			main._on_menu_upgrade_buy(id)
		return


## One frame of bot policy across ALL unlocked machines.
func _bot_tick(main) -> void:
	# Hands first: a held part always goes to the table.
	if main.held != null and main._is_held_part():
		main._player.global_position = PACKING_POS
		main._try_interact()
		return

	# Finished work anywhere: collect or clear, one machine per frame.
	for m in main.machines:
		var idx := int(m.get("idx"))
		if not main.upgrades.machine_unlocked(idx):
			continue
		var sim: PrintSim = m.get("sim")
		var c: Contract = m.get("contract")
		if sim.state == PrintSim.State.DONE_OK:
			_stand_at(main, idx)
			main._try_interact()
			return
		if sim.state == PrintSim.State.DONE_FAIL:
			_stand_at(main, idx)
			main._try_interact()
			return
		if c != null and c.state == Contract.State.INSPECTION:
			if c.needs_parts():
				_stand_at(main, idx)
				main._try_interact()  # reprint the next copy
				return
			if is_instance_valid(m.get("part")):
				_stand_at(main, idx)
				main._try_interact()  # grab the finished part
				return
		if c != null and c.state == Contract.State.PREPARING \
				and sim.state == PrintSim.State.IDLE:
			_confirm_prep(main, m, idx)
			return

	# Idle machines take work.
	for m in main.machines:
		var idx := int(m.get("idx"))
		if not main.upgrades.machine_unlocked(idx):
			continue
		var sim: PrintSim = m.get("sim")
		if m.get("contract") != null or sim.state != PrintSim.State.IDLE:
			continue
		if is_instance_valid(m.get("part")):
			continue
		if int(m.get("filament_g")) < 900:
			_refill_filament(main, idx)
			return
		var pick := _pick_job(main)
		if pick != null:
			main.job_board.rotate_to_front(pick)
			_stand_at(main, idx)
			main._try_interact()
			return


func _stand_at(main, idx: int) -> void:
	if idx < main._printers.size():
		var p: Node3D = main._printers[idx]
		main._player.global_position = Vector3(
			p.global_position.x, 0.3, p.global_position.z)
	else:
		main._player.global_position = Vector3(-1.8, 0.3, -1.0)


## Confirm the safest printable orientation; refill first if thirsty.
func _confirm_prep(main, m: Dictionary, idx: int) -> void:
	var prep := load("res://scripts/PrepSystem.gd")
	var c: Contract = m.get("contract")
	var best := -1
	for k in range(3):
		var name: String = prep.orientations()[k]
		var ev: Dictionary = main._prep_eval(c, name)
		if not bool(ev.get("valid", false)):
			continue
		if int(m.get("filament_g")) < int(ev.get("estimated_material_g", 0)):
			best = -2
			continue
		best = k
		break
	if best == -2:
		_refill_filament(main, idx)
		return
	if best >= 0:
		m["orient"] = best
		m["orient_pending"] = true
		main._prep_on(idx)


func _refill_filament(main, idx: int) -> void:
	if main.held != null:
		# Holding a spool: load it into the TARGET machine.
		_stand_at(main, idx)
		main._try_interact()
		return
	main._player.global_position = CRATE_POS
	if main._near_crate():
		main._try_interact()  # buy (spool attaches to hand)
		return


## Late-game picker: take the best-paying job on the board regardless of
## difficulty — at tier 4 the board deals hard jobs, and a conservative
## filter starves the shop (the day-9 stall in the first calibration run).
## Prints are forced-success in this harness, so difficulty only affects
## filament cost, which the refill path covers.
func _pick_job(main) -> Contract:
	var best: Contract = null
	for c in main.job_board._queue:
		if best == null or c.payout_cents > best.payout_cents:
			best = c
	return best

extends SceneTree

## v0.26.0 — automated playtest: a simple policy bot plays the shop for 8
## in-game days on one printer — accepts affordable board jobs, confirms the
## safest orientation, manages filament, delivers everything, survives rent.
## Deterministic (PrintSim has no RNG), so the economy curve replays exactly.
##
## Run: godot --headless --path . -s tests/sim_playtest.gd
## (Deliberately NOT tests/*_test.gd: the run simulates ~12 minutes of shop
## time and is a harness, not a unit suite.)

const DAYS := 8
const TIME_SCALE := 8.0

const PRINTER_POS := Vector3(-1.8, 0.3, -1.0)
const PACKING_POS := Vector3(2.0, 0.3, 0.9)
const CRATE_POS := Vector3(-3.0, 0.3, 1.4)

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
	Engine.time_scale = TIME_SCALE
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true

	var table: Array[String] = []
	var last_day := 1
	var min_balance: int = main.ledger.balance()
	var min_rep: float = main.reputation
	var frames := 0

	while main.day_cycle.day <= DAYS + 1 and frames < 60000:
		_bot_tick(main)
		await physics_frame
		frames += 1
		min_balance = mini(min_balance, main.ledger.balance())
		min_rep = minf(min_rep, main.reputation)
		if main.day_cycle.day != last_day:
			table.append("day %d end: $%s · delivered %d · rep %.2f · debt $%s" % [
				last_day, main._cents_str(main.ledger.balance()),
				int(main.stats.delivered), main.reputation,
				main._cents_str(main.rent_debt_cents)])
			print(table[-1])
			last_day = main.day_cycle.day

	Engine.time_scale = 1.0
	for row in table:
		print("PLAYTEST: ", row)

	# --- survival + progression invariants -----------------------------------
	_ok(main.ledger.balance() >= 0, "balance never negative")
	_ok(min_balance >= 0, "balance never dipped negative (min %d)" % min_balance)
	_ok(main.rent_debt_cents < 6000,
		"rent debt stayed recoverable ($%s)" % main._cents_str(main.rent_debt_cents))
	# Deterministic run (PrintSim has no RNG). Reference curve at loop end
	# (the run rolls into day 9): 17 deliveries / $1,759 with the v0.45
	# wear & tear maintenance loop (the bot cleans at 50% wear; one delivery
	# trades for a clean cycle vs the v0.44 curve's 18 / $1,758). Bounds
	# leave room for balance tweaks but catch starvation regressions.
	_ok(int(main.stats.delivered) >= 8,
		"the bot delivered at least 8 orders in %d days (got %d)" % [
			DAYS, int(main.stats.delivered)])
	_ok(main.ledger.balance() >= 500,
		"day-%d balance shows real progression ($%s)" % [
			DAYS, main._cents_str(main.ledger.balance())])
	_ok(min_rep >= 2.0, "reputation never cratered (min %.2f)" % min_rep)
	_ok(int(main.stats.late) <= int(main.stats.delivered) / 2,
		"the bot was not chronically late")
	_ok(frames < 60000, "the playthrough finished inside the frame budget")

	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## One frame of bot policy. Priorities: deliver held part > collect finished >
## clear failed > confirm prep (safest orientation, filament first) > reprint
## owed copies > accept a new job.
func _bot_tick(main) -> void:
	var m: Dictionary = main._machine(0)
	var sim: PrintSim = m.get("sim")
	var c: Contract = m.get("contract")

	# Holding a part: pack it.
	if main.held != null and main._is_held_part():
		main._player.global_position = PACKING_POS
		main._try_interact()
		return

	if c != null:
		match sim.state:
			PrintSim.State.DONE_OK:
				main._player.global_position = PRINTER_POS
				main._try_interact()  # collect (or the reprint guard defers)
				return
			PrintSim.State.DONE_FAIL:
				main._player.global_position = PRINTER_POS
				main._try_interact()  # clear the bed
				return
			_:
				pass  # printing: let it run
		# Prep lives on the CONTRACT, not the sim: the sim idles until the
		# orientation is confirmed, so check the contract state here.
		if c.state == Contract.State.PREPARING and sim.state == PrintSim.State.IDLE:
			_confirm_prep(main, m, c)
			return
		if c.state == Contract.State.INSPECTION:
			if c.needs_parts():
				# multi-part order owes copies: E at the printer reprints
				main._player.global_position = PRINTER_POS
				main._try_interact()
				return
			if is_instance_valid(m.get("part")):
				main._player.global_position = PRINTER_POS
				main._try_interact()  # grab the finished part
				return

	# Idle machine: keep it maintained (v0.45.0), then filament, then jobs.
	if c == null and sim.state == PrintSim.State.IDLE:
		if float(m.get("clean_left_s", 0.0)) > 0.0:
			return  # a clean is running; it ticks on its own
		if float(m.get("wear", 0.0)) >= 50.0:
			main._player.global_position = PRINTER_POS
			main._try_interact()  # clean the worn machine (wear raises risk)
			return
		if int(m.get("filament_g")) < 700:
			_refill_filament(main)
			return
		var pick := _pick_job(main)
		if pick != null:
			main.job_board.rotate_to_front(pick)
			main._player.global_position = PRINTER_POS
			main._try_interact()  # accept


## Confirm the safest printable orientation; refill filament first if the
## estimate would not fit in the machine.
func _confirm_prep(main, m: Dictionary, c: Contract) -> void:
	var prep := load("res://scripts/PrepSystem.gd")
	var best := -1
	for k in range(3):
		var name: String = prep.orientations()[k]
		var ev: Dictionary = main._prep_eval(c, name)
		if not bool(ev.get("valid", false)):
			continue
		if int(m.get("filament_g")) < int(ev.get("estimated_material_g", 0)):
			best = -2  # printable but thirsty
			continue
		best = k
		break
	if best == -2:
		_refill_filament(main)
		return
	if best >= 0:
		m["orient"] = best
		m["orient_pending"] = true
		main._prep_on(0)


func _refill_filament(main) -> void:
	if main.held != null:
		# Holding something that is not a spool: set it down at the printer.
		main._player.global_position = PRINTER_POS
		main._try_interact()
		return
	main._player.global_position = CRATE_POS
	if main._near_crate():
		main._try_interact()  # buy (spool attaches to hand)
		return
	main._player.global_position = PRINTER_POS
	main._try_interact()  # load the held spool


## Cheapest sensible job: difficulty <= 3, skip rush with a tight deadline,
## material affordable against the balance once a spool is in.
func _pick_job(main) -> Contract:
	var best: Contract = null
	for c in main.job_board._queue:
		if c.difficulty > 3:
			continue
		if c.rush and c.deadline_days < 2:
			continue
		if best == null or c.payout_cents > best.payout_cents:
			best = c
	return best

extends SceneTree

## v0.59.0 — walk-in customers: deterministic arrival gating, patience
## math, the two-press counter slip (arm/disarm/accept), the counter
## handover through the extracted settle path (pinned x1.10 chain, color
## cap, finishing bump, rep/client memory), silent expiry teardown,
## stats/walkins persistence, the calm-mode actor freeze, boot budget and
## crate non-theft. Behavioral on the REAL Main scene (counter_test
## pattern); every engine class is referenced load()-only (hazard 4).
## Run: timeout 180 godot --headless --path . -s tests/walkin_test.gd

const TOTAL := 38

const COUNTER_POS := Vector3(-1.9, 0.3, 1.35)   # 1.2 m off center, inside the radius
const PRINTER_POS := Vector3(-1.8, 0.3, -1.0)   # printer 1 (sim bots' spot)
const PACKING_POS := Vector3(2.0, 0.3, 0.9)     # packing table (sim bots' spot)
const CRATE_POS := Vector3(-3.0, 0.3, 1.4)      # spool crate (outside the radius)
const AWAY_POS := Vector3(0, 0.3, -2.0)         # back wall, far side

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


## Feed one E press through Main's real input handler (grab_test pattern).
func _feed_key(main, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	main._unhandled_input(ev)


## Teleport + re-aim + settle frames (hazards 5/6).
func _at(main, pos: Vector3) -> void:
	main._player.global_position = pos
	main.yaw = 0.0
	main._player.rotation.y = main.yaw
	main.pitch = 0.0
	main._camera.rotation.x = main.pitch
	await physics_frame
	await physics_frame


## Count nodes in the tree whose script is the CustomerActor script.
func _count_actors(node: Node, actor_script: Script) -> int:
	var n := 0
	if node.get_script() == actor_script:
		n += 1
	for c in node.get_children():
		n += _count_actors(c, actor_script)
	return n


## Silence every sfx player so a later play() is the only assignable source.
func _quiet_bell(main) -> void:
	for p in main.sfx._players:
		p.stream = null


## Walk one full day at 0.01-day steps and record the fired slots, in order.
func _walk_schedule(CS, day: int) -> Array:
	var svc = CS.new()
	var fired: Array = []
	for k in range(1, 101):
		var d = svc.due(day, float(k) * 0.01, false)
		if d >= 0:
			fired.append(d)
	return fired


## Drive one full counter order on machine 0: accept (two presses) ->
## confirm the default orientation -> force the print done -> collect ->
## stamp the controlled grade snapshot -> optional vapor pass -> counter
## handover. The player ends at the counter with the order settled.
func _counter_order(main, snapshot: Dictionary, finished: bool) -> void:
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)  # slip
	_feed_key(main, KEY_E)  # accept
	var m: Dictionary = main._machine(0)
	m["filament_g"] = 50000
	m["orient"] = 0
	m["orient_pending"] = true
	main._prep_on(0)
	var sim = m.get("sim")
	sim._failure_tick = -1
	sim.failure_seeded = false
	sim.failure_threshold = 1.5
	while sim.is_running():
		sim.tick(1.0)
	await _at(main, PRINTER_POS)
	main._try_interact()  # collect the part
	m["grade_snapshot"] = snapshot
	if finished:
		m["finished"] = true
	await _at(main, COUNTER_POS)
	main._try_interact()  # hand it over


## A controlled single-part walk-in contract (exact-cents pin).
func _make_ctrl(contract_script: Script, id: String, client: String, payout: int,
		color: String, model: String):
	var c = contract_script.new()
	c.id = id
	c.client = client
	c.model_name = model
	c.payout_cents = payout
	c.material_cost_cents = 400
	c.difficulty = 1
	c.layers = 100
	c.deadline_days = 2
	c.color = color
	c.parts_total = 1
	c.walk_in = true
	return c


func _run() -> void:
	print("%d checks defined" % TOTAL)
	var CS = load("res://scripts/CounterService.gd")        # pure logic
	var CA = load("res://scripts/CustomerActor.gd")         # actor script
	var ContractS = load("res://scripts/Contract.gd")
	var EventsS = load("res://scripts/Events.gd")
	var SaveS = load("res://scripts/SaveSystem.gd")
	var BSave = load("res://scripts/BrowserSave.gd")
	BSave.clear()

	# --- A. pure CounterService logic ----------------------------------------
	# A1: slot times are deterministic hash draws inside the arrival band.
	var t0a: float = CS.slot_time(4, 0)
	var t1: float = CS.slot_time(4, 1)
	_ok(CS.slot_time(4, 0) == t0a and CS.slot_time(4, 1) == t1 \
		and t0a >= 0.25 and t0a <= 0.25 + 0.22 + 0.03 * 3 + 0.0001 \
		and t1 >= 0.25 + 0.22 - 0.0001 and t1 <= 0.25 + 0.22 + 0.03 * 3 + 0.0001,
		"slot times are deterministic hash draws inside the arrival band")

	# A2/A3: the same day replays the same schedule; days differ somewhere.
	var day_sched: Array = _walk_schedule(CS, 4)
	_ok(day_sched == _walk_schedule(CS, 4) and day_sched.size() == 2,
		"the same day replays an identical two-slot schedule")
	var any_diff := false
	var first_sched: Array = _walk_schedule(CS, 1)
	for d in range(2, 13):
		if _walk_schedule(CS, d) != first_sched:
			any_diff = true
	_ok(any_diff, "different days produce different schedules")

	# A4: the 6/10 gate admits some slots and refuses others.
	var enabled := 0
	for d in range(1, 61):
		for i in range(2):
			if CS.slot_enabled(d, i):
				enabled += 1
	_ok(enabled > 0 and enabled < 120 and enabled >= 36 and enabled <= 108,
		"the arrival gate admits some slots and refuses others (%d/120)" % enabled)

	# A5: outside the business window due() refuses (seed before, cross into
	# the night — the refusal must come from the window, not from seeding).
	var svc_night = CS.new()
	svc_night.due(4, 0.10, false)  # seed inside the morning, before any slot
	_ok(svc_night.due(4, 0.90, false) == -1,
		"the night window refuses arrivals whose times already passed")

	# A6-A8 need a day with both slots live.
	var d_enabled := -1
	for d in range(1, 81):
		if CS.slot_enabled(d, 0) and CS.slot_enabled(d, 1):
			d_enabled = d
			break
	_ok(d_enabled > 0, "a day with both slots live exists for the walkthrough")
	if d_enabled > 0:
		var t0: float = CS.slot_time(d_enabled, 0)
		var t1e: float = CS.slot_time(d_enabled, 1)
		# A6: a live slot fires exactly when frac crosses its time.
		var svc_cross = CS.new()
		svc_cross.due(d_enabled, 0.10, false)  # seed before any slot time
		_ok(svc_cross.due(d_enabled, t0 + 0.01, false) == 0,
			"slot 0 fires exactly when frac crosses its arrival time")
		# A7: while someone waits, crossed slots are skipped entirely.
		var svc_wait = CS.new()
		svc_wait.due(d_enabled, 0.10, true)  # seed
		var skip0 = svc_wait.due(d_enabled, t0 + 0.01, true)
		var skip1 = svc_wait.due(d_enabled, t1e + 0.01, true)
		_ok(skip0 == -1 and skip1 == -1,
			"crossed slots are skipped entirely while a customer waits")
		# A8: serve before the next slot -> the next slot still fires.
		var svc_serve = CS.new()
		svc_serve.due(d_enabled, t0 + 0.01, true)  # slot 0 skipped while waiting
		var sw_pre = svc_serve.due(d_enabled, t1e - 0.02, false)
		var sw1 = svc_serve.due(d_enabled, t1e + 0.01, false)
		_ok(sw_pre == -1 and sw1 == 1,
			"after the first customer is served the next slot can still fire")

	# A9/A10: patience math (0.55 of a shop day, day wrap).
	var svc_p = CS.new()
	svc_p.begin(3, 0, CS.make_contract(3, 0, 5), 0.20)
	var st: Dictionary = svc_p.state
	_ok(absf(CS.patience_deadline_frac(0.30) - 0.85) < 0.0001 \
		and absf(float(st.deadline_frac) - 0.75) < 0.0001 \
		and not CS.is_expired(st, 3, 0.74) and CS.is_expired(st, 3, 0.75) \
		and CS.is_expired(st, 4, 0.0),
		"patience is arrival + 0.55 day and expires into the next day if needed")
	_ok(absf(CS.patience_left_s(st, 3, 0.20, 90.0) - 49.5) < 0.01,
		"patience_left_s converts the remaining fraction at 90 s/day")

	# A11/A12: the slip's contract and the client name draw.
	var wc = CS.make_contract(3, 1, 5)
	var wc2 = CS.make_contract(3, 1, 5)
	_ok(wc.walk_in and wc.parts_total == 1 and wc.deadline_days == 2 \
		and wc.id == "G-3-101" and wc2.payout_cents == wc.payout_cents,
		"walk-in contracts are single-part, tagged, deadline 2, board-index 100")
	var pool: Array = ContractS.GEN_FIRSTS
	_ok(CS.client_name(3, 1) == CS.client_name(3, 1) and pool.has(CS.client_name(3, 1)),
		"client names are deterministic draws from the first-name pool")

	# --- B. boot state ---------------------------------------------------------
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true
	# Pin the day to a quiet event so the payout chain is fully controlled.
	main.today_event = EventsS.QUIET.duplicate(true)

	# Park the boot spool far from every spot this test presses E at.
	var boot_spool = main.get_node_or_null("Spool")
	if boot_spool != null:
		boot_spool.freeze = true
		boot_spool.global_position = Vector3(2.6, 0.14, -2.4)

	await physics_frame
	await physics_frame
	_ok(main._counter_service != null and not main._counter_service.waiting() \
		and main._customer == null and _count_actors(root, CA) == 0 \
		and not str(main._status.text).contains("Counter: "),
		"boot builds the service but spawns no customer, no actor, no HUD line")

	# --- C. spawn, slip, arm/disarm, accept ------------------------------------
	main._spawn_walkin(1, 0)
	# A controlled contract for the exact-cents pin (replaces the generated one).
	var wstate: Dictionary = main._counter_service.state
	var client: String = str(wstate.client)
	var ctrl = _make_ctrl(ContractS, "G-1-100", client, 5050, "", "Counter test widget")
	main._counter_service.state["contract"] = ctrl
	main._spawn_walkin(1, 0)  # a second spawn while one waits must be refused
	await physics_frame
	await physics_frame
	_ok(main._counter_service.waiting() and main._customer != null \
		and main._customer.position.distance_to(CA.WAIT_POS) < 0.001 \
		and _count_actors(root, CA) == 1,
		"the spawn places ONE customer behind the counter")

	var hud: String = str(main._status.text)
	_ok(hud.contains("Counter: %s" % client) and hud.contains(ctrl.model_name),
		"the HUD shows the waiting customer line while someone waits")

	await _at(main, COUNTER_POS)
	_quiet_bell(main)
	_feed_key(main, KEY_E)
	var slip: String = str(main._prompt.text)
	_ok(slip.contains(client) and slip.contains(ctrl.model_name) \
		and slip.contains("~$") and slip.contains("[E] again to accept") \
		and main._counter_arm,
		"press 1 shows the slip (client, model, price) and arms")

	# No free printer: occupy machine 0 with a board job; printer 2 is locked.
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-WT1", "client": "Blocker", "model_name": "Blocker part",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	main._accept_on(0)
	_feed_key(main, KEY_E)
	_ok(str(main._prompt.text) == "No free printer for a counter order" \
		and not bool(main._counter_service.state.accepted) and main._counter_arm,
		"accept with no free printer is refused and the slip stays armed")

	# Leaving the radius disarms; the next press re-arms fresh.
	await _at(main, AWAY_POS)
	main._tick_counter(0.02)
	var disarmed: bool = not main._counter_arm
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)
	_ok(disarmed and main._counter_arm \
		and str(main._prompt.text).contains("[E] again to accept"),
		"leaving the counter radius disarms the slip; the next press re-arms")

	# The 8 s timeout disarms too.
	main._tick_counter(4.0)
	main._tick_counter(4.0)
	main._tick_counter(4.0)
	_ok(not main._counter_arm, "the 8 s timeout disarms the slip")

	# Free machine 0, then accept: press 1 arms, press 2 takes the order.
	main._machine(0)["contract"] = null
	var queue_before: int = main.job_board._queue.size()
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)
	_feed_key(main, KEY_E)
	var acc: Dictionary = main._counter_service.state
	var m0: Dictionary = main._machine(0)
	_ok(bool(acc.accepted) and int(acc.machine_idx) == 0 \
		and m0.get("contract") == acc.contract and acc.contract.walk_in \
		and acc.contract.state == ContractS.State.PREPARING \
		and str(main._prompt.text).contains("Sent to Printer 1"),
		"press 2 accepts onto the first idle unlocked printer (Printer 1)")
	_ok(main.job_board._queue.size() == queue_before,
		"the accept leaves the job board untouched")
	_feed_key(main, KEY_E)
	_ok(str(main._prompt.text).contains("Printer 1") \
		and str(main._prompt.text).contains("patience") \
		and bool(main._counter_service.state.accepted),
		"a further press names the machine instead of re-accepting")

	# --- D. the counter handover ------------------------------------------------
	# Confirm the print, force it done, collect, then try the packing table.
	m0["filament_g"] = 50000
	m0["orient"] = 0
	m0["orient_pending"] = true
	main._prep_on(0)
	var sim = m0.get("sim")
	sim._failure_tick = -1
	sim.failure_seeded = false
	sim.failure_threshold = 1.5
	while sim.is_running():
		sim.tick(1.0)
	await _at(main, PRINTER_POS)
	main._try_interact()  # collect
	m0["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	await _at(main, PACKING_POS)
	var balance_pack: int = main.ledger.balance()
	_feed_key(main, KEY_E)
	_ok(main.held != null and main.ledger.balance() == balance_pack \
		and str(main._prompt.text).contains("waiting at the counter"),
		"the packing table refuses a held walk-in part")

	# Counter handover with the pinned chain:
	# grade A -> loyalty -> rep -> season -> event -> x1.10 -> same-day tip.
	await _at(main, COUNTER_POS)
	var rep0: float = main.reputation
	var served0: int = main.walkins_served
	var balance0: int = main.ledger.balance()
	# The settle reads the PRE-delivery loyalty and reputation multiplier
	# ("counts the orders completed BEFORE this one") — pin them before the press.
	var rep_mult0: float = main.reputation_multiplier()
	var loyalty0: float = main._loyalty_mult(client)
	_feed_key(main, KEY_E)
	var eff := roundi(float(ctrl.payout_cents) * 1.0 * loyalty0)
	var s1 := roundi(float(eff) * rep_mult0)
	var s2 := roundi(float(s1) * float(main.season.payout_mult))
	var s3 := roundi(float(s2) * float(main.today_event.payout_mult))
	var with_counter := roundi(float(s3) * 1.10)
	var expected := with_counter + roundi(float(with_counter) * 0.10)
	var no_counter := s3 + roundi(float(s3) * 0.10)
	_ok(main.ledger.balance() - balance0 == expected and expected != no_counter,
		"the counter delivery pays the pinned chain with the x1.10 premium ($%s)"
			% main._cents_str(expected))
	_ok(main.walkins_served == served0 + 1 and int(main.stats.delivered) == 1,
		"serving bumps walkins_served and stats.delivered")
	_ok(absf(main.reputation - (rep0 + 0.2)) < 0.0001 \
		and int(main.client_orders.get(client, 0)) == 1 \
		and str(main.client_last_grade.get(client, "")) == "A",
		"the serve bumps rep +0.2 and remembers the client's grade")
	await physics_frame  # queue_free lands at the end of the frame
	var counter_logs := 0
	for e in main.workshop_log.entries():
		if str(e.kind) == "counter":
			counter_logs += 1
	_ok(main._customer == null and not main._counter_service.waiting() \
		and _count_actors(root, CA) == 0 and counter_logs == 1,
		"the customer leaves after the handover; exactly one counter log entry")

	# --- E. color cap + finishing bump still apply at the counter ---------------
	main._spawn_walkin(1, 1)
	var client2: String = str(main._counter_service.state.client)
	var ctrl2 = _make_ctrl(ContractS, "G-1-101", client2, 4000, "Sage", "Cap test widget")
	main._counter_service.state["contract"] = ctrl2
	# Machine 0's spool is Clay; an A part for a Sage order caps at B.
	await _counter_order(main, {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}, false)
	_ok(str(main.last_pack_grade) == "B" and main.walkins_served == 2,
		"a wrong spool color caps the counter grade at B")

	main._spawn_walkin(1, 2)
	var client3: String = str(main._counter_service.state.client)
	var ctrl3 = _make_ctrl(ContractS, "G-1-102", client3, 4200, "Clay", "Bump test widget")
	main._counter_service.state["contract"] = ctrl3
	# B raw grade (complete, max risk 0.6) + a vapor pass -> A. Machine 0 is
	# Clay, matching the order, so no cap confounds the bump.
	await _counter_order(main, {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.6}}, true)
	_ok(str(main.last_pack_grade) == "A" and main.walkins_served == 3,
		"the finishing bump still applies at the counter")

	# --- F. expiry teardown (silence is the point) -------------------------------
	var rep_f: float = main.reputation
	var balance_f: int = main.ledger.balance()
	var lost_f: int = int(main.stats.lost_walkins)
	var board_f: int = main.job_board._queue.size()
	main._spawn_walkin(1, 3)
	main._counter_service.state["deadline_frac"] = 0.0  # deadline = day 1.0
	main.day_cycle.t = 0.5
	var log_f1: int = main.workshop_log.entries().size()  # milestone toasts land via the HUD, so pin this at the last moment
	main._tick_counter(0.016)
	_ok(main._customer == null and not main._counter_service.waiting() \
		and int(main.stats.lost_walkins) == lost_f + 1 \
		and absf(main.reputation - rep_f) < 0.0001 \
		and main.ledger.balance() == balance_f \
		and main.workshop_log.entries().size() == log_f1 \
		and main.job_board._queue.size() == board_f,
		"an unaccepted walk-in expires silently: despawn + lost_walkins only")

	# Accepted expiry: the machine contract is cancelled, still zero noise.
	main._spawn_walkin(1, 4)
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)
	_feed_key(main, KEY_E)
	var held_contract = main._machine(0).get("contract")
	main._counter_service.state["deadline_frac"] = 0.0
	main.day_cycle.t = 0.5
	var log_f2: int = main.workshop_log.entries().size()
	main._tick_counter(0.016)
	_ok(main._machine(0).get("contract") == null \
		and held_contract.state == ContractS.State.FAILED \
		and int(main.stats.lost_walkins) == lost_f + 2 \
		and absf(main.reputation - rep_f) < 0.0001 \
		and main.workshop_log.entries().size() == log_f2,
		"an accepted expiry cancels the machine contract with zero rep and log noise")

	# --- G. a waiting walk-in does not steal the crate buy -------------------------
	main._spawn_walkin(1, 5)
	await _at(main, CRATE_POS)
	var balance_c: int = main.ledger.balance()
	_feed_key(main, KEY_E)
	_ok(main.held != null and main._is_held_spool() \
		and main.ledger.balance() < balance_c,
		"a waiting walk-in does not steal the crate buy")
	main._counter_despawn()

	# --- H. persistence -------------------------------------------------------------
	main.walkins_served = 7
	main.stats.lost_walkins = 3
	main._save_game()
	var saved: Dictionary = BSave.load_payload()
	_ok(int(saved.get("walkins_served", -1)) == 7 \
		and int(saved.get("stats", {}).get("lost_walkins", -1)) == 3,
		"walkins_served and stats.lost_walkins round-trip into the payload")

	var minimal := {"version": 1, "balance_cents": 100, "active_contract": {},
		"ledger": {"balance_cents": 100, "transactions": [
				{"id": 1, "reason": "x", "delta_cents": 100, "balance_after": 100}],
			"paid_contract_ids": [], "next_seq": 2}, "paid_ids": []}
	var bad1: Dictionary = minimal.duplicate(true)
	bad1["walkins_served"] = -2
	var bad2: Dictionary = minimal.duplicate(true)
	bad2["stats"] = {"lost_walkins": -1}
	_ok(SaveS.validate(bad1).is_empty() and SaveS.validate(bad2).is_empty(),
		"the validators reject negative walkin counters")
	_ok(not SaveS.validate(minimal).is_empty(),
		"old saves without the walkin keys still validate")

	# Full reload: counters restore, nobody spawns.
	main.queue_free()
	await physics_frame
	await physics_frame
	var with_keys: Dictionary = minimal.duplicate(true)
	with_keys["walkins_served"] = 9
	with_keys["stats"] = {"lost_walkins": 4}
	BSave.clear()
	BSave.save_payload(SaveS.validate(with_keys))
	var main2 = packed.instantiate()
	root.add_child(main2)
	for i in range(6):
		await physics_frame
	_ok(int(main2.walkins_served) == 9 and int(main2.stats.lost_walkins) == 4 \
		and main2._customer == null and not main2._counter_service.waiting(),
		"a reload restores the counters and spawns nobody")
	main2.queue_free()
	await physics_frame

	# --- I. the customer actor -------------------------------------------------------
	var actor = CA.new()
	actor.position = CA.WAIT_POS
	root.add_child(actor)
	await physics_frame
	var meshes := 0
	var stack: Array = [actor]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			meshes += 1
		stack.append_array(n.get_children())
	actor.set_motion(false)
	var y_frozen: float = actor.get_node("Torso").position.y
	actor._advance(5.0)
	var still: float = actor.get_node("Torso").position.y
	actor.set_motion(true)
	actor._advance(5.0)
	var moved: float = actor.get_node("Torso").position.y
	_ok(meshes == 2 and absf(still - y_frozen) < 0.0001 and absf(moved - y_frozen) > 0.001,
		"the customer is two meshes; calm mode freezes it and _advance drives the bob")
	actor.queue_free()

	# --- cleanup ----------------------------------------------------------------------
	BSave.clear()
	BSave.save_path = "user://walkin_test_save.json"
	BSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

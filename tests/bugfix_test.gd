extends SceneTree

## v0.61.x bugfix batch (parent-verified slice):
##   1. The packing-table stack visual is RECOMPUTED from live state
##      (_refresh_stack_visual) instead of blindly zeroed — unrelated
##      deliveries/accepts/expiries no longer wipe a mid-completion multi-part
##      order's stacked copies, while the multi-part itself completing or
##      failing still clears the table.
##   2. Event prompts (the only writes through _set_prompt) age out after
##      ~6 s of _physics_process deltas; direct _prompt.text writes (boot
##      capture / pause hints) never arm the window and never age.
##   3. MeshKit dedup: the shared offset/box helpers live in MeshKit.gd;
##      ShopFront/CustomerActor carry no private copies.
## Behavioral on the REAL Main scene (counter_test/v018 pattern); Main and
## MainMenu are never named at compile time (hazard 4).
## Run: timeout 180 godot --headless --path . -s tests/bugfix_test.gd

const TOTAL := 34

const PRINTER1_POS := Vector3(-1.8, 0.3, -1.0)  # printer 1 (sim bots' spot)
const PACKING_POS := Vector3(2.0, 0.3, 0.9)     # packing table (sim bots' spot)
const COUNTER_POS := Vector3(-1.9, 0.3, 1.35)   # inside the counter radius

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


## Stand at printer `idx` using the live scene positions (sim_lategame's
## _stand_at pattern, so any machine layout change stays honest).
func _at_printer(main, idx: int) -> void:
	var p: Node3D = main._printers[idx]
	await _at(main, Vector3(p.global_position.x, 0.3, p.global_position.z))


## Controlled contract (v018_test's _hand shape — fast prints, long leash).
func _hand(id: String, parts: int) -> Contract:
	var c := Contract.new()
	c.id = id
	c.client = "Test client"
	c.model_name = "Test part"
	c.payout_cents = 5000
	c.material_cost_cents = 300
	c.difficulty = 1
	c.layers = 40
	c.deadline_days = 6
	c.parts_total = parts
	return c


## Controlled single-part WALK-IN contract (walkin_test's _make_ctrl shape).
func _walkin_hand(id: String, color: String) -> Contract:
	var c := _hand(id, 1)
	c.payout_cents = 4000
	c.material_cost_cents = 400
	c.deadline_days = 2
	c.color = color
	c.walk_in = true
	return c


## Print one copy on machine `idx` and collect it (v018_test's
## _print_and_collect driver, parameterized): confirm orientation 0, run the
## sim to DONE_OK failure-free, then E-collect at the printer.
func _print_and_collect(main, idx: int) -> void:
	var m: Dictionary = main._machine(idx)
	var sim: PrintSim = m.get("sim")
	m["orient"] = 0
	m["orient_pending"] = true
	main._prep_on(idx)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	await _at_printer(main, idx)
	main._try_interact()  # collect the copy


## Accept the front-of-queue board job on machine `idx` (E at that printer).
func _accept_front(main, idx: int) -> Contract:
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand("BF-Q-%d" % idx, 1))
	await _at_printer(main, idx)
	main._try_interact()
	return main._machine(idx).get("contract")


func _run() -> void:
	print("%d checks defined" % TOTAL)
	var BSave = load("res://scripts/BrowserSave.gd")
	var ContractS = load("res://scripts/Contract.gd")
	BSave.clear()

	# --- A. MeshKit dedup (pure, no scene needed) -----------------------------
	var MK = load("res://scripts/MeshKit.gd")
	var box = MK.box_mesh(Vector3(1.0, 2.0, 4.0))
	var arr: Array = MK.offset_arrays(box, Vector3(1.0, 2.0, 3.0))
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	_ok(lo.is_equal_approx(Vector3(0.5, 1.0, 1.0)) \
		and hi.is_equal_approx(Vector3(1.5, 3.0, 5.0)),
		"MeshKit.offset_arrays translates a BoxMesh's vertices exactly")
	var plain: PackedVector3Array = box.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	_ok(plain.size() == verts.size(),
		"MeshKit.offset_arrays preserves the vertex count (pure translation)")
	var SF = load("res://scripts/ShopFront.gd")
	var CA = load("res://scripts/CustomerActor.gd")
	var sf_names := ""
	for md in SF.get_script_method_list():
		sf_names += str(md.get("name", "")) + " "
	var ca_names := ""
	for md in CA.get_script_method_list():
		ca_names += str(md.get("name", "")) + " "
	var mk_names := ""
	for md in MK.get_script_method_list():
		mk_names += str(md.get("name", "")) + " "
	_ok(not sf_names.contains("offset_arrays") and not sf_names.contains("box_mesh"),
		"ShopFront no longer defines its own offset/box helpers")
	_ok(not ca_names.contains("offset_arrays") and not ca_names.contains("box_mesh"),
		"CustomerActor no longer defines its own offset/box helpers")
	_ok(mk_names.contains("offset_arrays") and mk_names.contains("box_mesh"),
		"MeshKit owns the shared offset/box helpers")

	# --- B. stack visual: unrelated paths no longer wipe it -------------------
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000
	main.ledger.credit(20000, "test funds")  # day_test pattern: buy headroom
	main._on_menu_upgrade_buy("pro_machine")
	_ok(main.upgrades.machine_unlocked(1),
		"printer 2 unlocked for the unrelated-order scenarios")
	main._machine(1)["filament_g"] = 50000

	# A 3-part order on machine 0: copy 1 packed, stack shows 1.
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand("BF-MP", 3))
	await _at_printer(main, 0)
	main._try_interact()
	var c: Contract = main._machine(0).get("contract")
	_ok(c != null and c.parts_total == 3 and c.parts_packed == 0
		and main.packing_station.stack_count() == 0,
		"3-part order accepted on printer 1, table empty")
	if c != null:
		c.color = str(main._machine(0).get("color"))
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	await _at(main, PACKING_POS)
	main._try_interact()  # pack copy 1
	_ok(c.parts_packed == 1 and main.packing_station.stack_count() == 1,
		"copy 1 packed, stack shows 1")

	# Unrelated BOARD order on machine 1: accepting it must keep the stack...
	var single: Contract = await _accept_front(main, 1)
	_ok(single != null and single.parts_total == 1
		and main.packing_station.stack_count() == 1,
		"board accept on printer 2 leaves the multi-part stack visible")
	if single != null:
		single.color = str(main._machine(1).get("color"))
	# ...and delivering that single at the TABLE must keep it too.
	await _print_and_collect(main, 1)
	main._machine(1)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	var bal_a: int = main.ledger.balance()
	await _at(main, PACKING_POS)
	main._try_interact()  # final (only) copy -> delivery through the settle tail
	_ok(main._machine(1).get("contract") == null and main.ledger.balance() > bal_a \
		and main.packing_station.stack_count() == 1,
		"an unrelated board delivery keeps the multi-part stack visible")

	# Unrelated WALK-IN served at the counter (v0.59 handover path): the named
	# bug — its delivery used to zero the visual while parts_packed still 1.
	main._spawn_walkin(1, 0)
	var wctrl = _walkin_hand("BF-W1", str(main._machine(1).get("color")))
	main._counter_service.state["contract"] = wctrl
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)  # arm the slip
	_feed_key(main, KEY_E)  # accept onto printer 2 (printer 1 is busy)
	_ok(main._machine(1).get("contract") == wctrl
		and main.packing_station.stack_count() == 1,
		"walk-in accept on printer 2 leaves the multi-part stack visible")
	await _print_and_collect(main, 1)
	main._machine(1)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	var served_a: int = int(main.walkins_served)
	var bal_b: int = main.ledger.balance()
	await _at(main, COUNTER_POS)
	main._try_interact()  # counter handover (via_counter settle)
	_ok(int(main.walkins_served) == served_a + 1
		and main.ledger.balance() > bal_b
		and main._machine(1).get("contract") == null
		and main.packing_station.stack_count() == 1,
		"an unrelated counter delivery keeps the multi-part stack visible")

	# An accepted walk-in whose patience expires (the v0.59 known cosmetic
	# edge): the teardown must still leave the board order's copy stacked.
	main._spawn_walkin(1, 1)
	var wctrl2 = _walkin_hand("BF-W2", str(main._machine(1).get("color")))
	main._counter_service.state["contract"] = wctrl2
	await _at(main, COUNTER_POS)
	_feed_key(main, KEY_E)
	_feed_key(main, KEY_E)
	_ok(main._machine(1).get("contract") == wctrl2, "second walk-in accepted")
	var lost_a: int = int(main.stats.lost_walkins)
	main._counter_service.state["deadline_frac"] = 0.0  # deadline = day 1.0
	main.day_cycle.t = 0.5
	main._tick_counter(0.016)  # patience expiry fires
	_ok(main._machine(1).get("contract") == null
		and int(main.stats.lost_walkins) == lost_a + 1
		and main.packing_station.stack_count() == 1,
		"a walk-in patience expiry keeps the multi-part stack visible")

	# The multi-part order ITSELF completes: copies 2 and 3 pack (stack grows
	# to 2) and the final delivery clears the table.
	await _at_printer(main, 0)
	main._try_interact()  # reprint branch: INSPECTION -> PREPARING
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	await _at(main, PACKING_POS)
	main._try_interact()  # pack copy 2 (partial)
	_ok(c.parts_packed == 2 and main.packing_station.stack_count() == 2,
		"copy 2 packed, stack shows 2")
	await _at_printer(main, 0)
	main._try_interact()  # reprint again
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	var bal_c: int = main.ledger.balance()
	await _at(main, PACKING_POS)
	main._try_interact()  # final copy -> delivery clears the stack
	_ok(c.state == ContractS.State.DELIVERED
		and main._machine(0).get("contract") == null
		and main.ledger.balance() > bal_c
		and main.packing_station.stack_count() == 0,
		"the multi-part order completing clears its stack")

	# Two F copies kill an order: its own stacked copy must clear.
	main.job_board._queue.clear()
	main.job_board._queue.append(_hand("BF-FF", 2))
	await _at_printer(main, 0)
	main._try_interact()
	var ff: Contract = main._machine(0).get("contract")
	if ff != null:
		ff.color = str(main._machine(0).get("color"))
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 100, "total_layers": 100,
		"risks": {"support_need": 0.0, "adhesion_risk": 0.0, "stability_risk": 0.0}}
	await _at(main, PACKING_POS)
	main._try_interact()  # clean copy 1/2
	_ok(ff.parts_packed == 1 and main.packing_station.stack_count() == 1,
		"the doomed order's clean copy stacks (1)")
	main._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0,
		"risks": {}}
	await _at_printer(main, 0)
	main._try_interact()  # reprint for copy 2
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0,
		"risks": {}}
	await _at(main, PACKING_POS)
	main._try_interact()  # F copy 1 recorded
	_ok(ff.copy_grades.count("F") == 1 and ff.copy_grades.size() == 2
		and ff.parts_packed == 1
		and main.packing_station.stack_count() == 1,
		"F copy recorded, the clean copy stays stacked")
	main._try_interact()  # scrap the F copy
	await _at_printer(main, 0)
	main._try_interact()  # reprint after scrap
	await _print_and_collect(main, 0)
	main._machine(0)["grade_snapshot"] = {"final_layer": 0, "total_layers": 0,
		"risks": {}}
	var bal_d: int = main.ledger.balance()
	var canc_a: int = int(main.stats.cancelled)
	await _at(main, PACKING_POS)
	main._try_interact()  # second F — the order dies here
	_ok(ff.state == ContractS.State.FAILED
		and main._machine(0).get("contract") == null
		and main.ledger.balance() == bal_d
		and int(main.stats.cancelled) == canc_a + 1
		and main.packing_station.stack_count() == 0,
		"the second F clears the dead order's stack, pays nothing")

	# --- C. _refresh_stack_visual unit semantics (max over live multi-parts) --
	var c1 = _hand("BF-U1", 3)
	c1.parts_packed = 2
	c1.state = ContractS.State.INSPECTION
	main._machine(0)["contract"] = c1
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 2,
		"refresh shows an INSPECTION multi-part's parts_packed")
	var cs = _hand("BF-US", 1)
	cs.parts_packed = 1
	cs.state = ContractS.State.INSPECTION
	main._machine(1)["contract"] = cs
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 2,
		"single-part contracts never count toward the stack")
	var c2 = _hand("BF-U2", 2)
	c2.parts_packed = 1
	c2.state = ContractS.State.INSPECTION
	main._machine(1)["contract"] = c2
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 2,
		"two live multi-parts show the max parts_packed")
	c1.state = ContractS.State.DELIVERED
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 1,
		"DELIVERED contracts stop counting")
	c1.state = ContractS.State.FAILED
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 1,
		"FAILED contracts stop counting")
	main._machine(0)["contract"] = null
	main._machine(1)["contract"] = null
	main._refresh_stack_visual()
	_ok(main.packing_station.stack_count() == 0,
		"no live multi-part means an empty table")

	main.queue_free()
	await physics_frame

	# --- D. event prompts age out; direct writes never do ---------------------
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	await physics_frame
	# The boot state never arms the window (the boot prompt must not age).
	_ok(float(main2._prompt_t) == 0.0,
		"boot never arms the prompt-aging window")
	main2._prompt.text = "Click to play"  # direct write, exactly like _route_escape
	for i in range(10):
		main2._physics_process(1.0)
	_ok(str(main2._prompt.text) == "Click to play",
		"a direct write with no armed window never ages")
	main2._set_prompt("Part 2/3 packed (B) — [E] at Printer 1 prints the next copy")
	_ok(str(main2._prompt.text).contains("Part 2/3 packed"),
		"_set_prompt shows the event prompt")
	for i in range(5):
		main2._physics_process(1.0)
	_ok(str(main2._prompt.text).contains("Part 2/3 packed"),
		"the prompt survives 5 s of deltas (window is ~6 s)")
	main2._physics_process(1.0)
	_ok(str(main2._prompt.text) == "",
		"the prompt clears after 6 s of deltas")
	main2._set_prompt("Print FAILED — clear the bed and reprint")
	for i in range(5):
		main2._physics_process(1.0)
	_ok(str(main2._prompt.text).contains("Print FAILED"),
		"a fresh prompt restarts the window (5 s in)")
	main2._set_prompt("Pack refused: contract not at inspection")
	for i in range(5):
		main2._physics_process(1.0)
	_ok(str(main2._prompt.text).contains("Pack refused"),
		"re-setting again re-arms (10 s since the first prompt, still shown)")
	main2._physics_process(1.0)
	_ok(str(main2._prompt.text) == "",
		"the restarted window also ages out at 6 s")
	main2._set_prompt("arm the window")
	main2._prompt.text = main2._boot_prompt  # direct boot-capture write (~299/615)
	for i in range(7):
		main2._physics_process(1.0)
	_ok(str(main2._prompt.text) == str(main2._boot_prompt),
		"the boot capture prompt does not age, even with a window pending")

	main2.queue_free()
	await physics_frame

	# --- cleanup ---------------------------------------------------------------
	BSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

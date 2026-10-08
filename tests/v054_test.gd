extends SceneTree

const BrowserSave = preload("res://scripts/BrowserSave.gd")

## v0.54.0 — "Surge protector": the 12th catalog upgrade. Conditioned power
## halves the wear every completed/failed print accrues (6+difficulty -> same
## x0.5, 12 -> 6). "Fully kitted" now tracks the catalog size generically so
## it can never drift again. Run:
## godot --headless --path . -s tests/v054_test.gd

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


func _kitted_done() -> bool:
	for a in main._achievements():
		if str(a.name) == "Fully kitted":
			return bool(a.done)
	return false


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

	# --- catalog shape --------------------------------------------------------
	var cat := Upgrades.catalog()
	_ok(cat.size() == 12, "the catalog now carries 12 upgrades")
	var e := Upgrades.entry("surge_protector")
	_ok(not e.is_empty() and str(e.name) == "Surge protector"
		and int(e.cost_cents) == 10000 and absf(float(e.wear_multiplier) - 0.5) < 0.0001,
		"surge_protector entry carries name, $100 cost and a 0.5 wear multiplier")

	# --- multiplier semantics --------------------------------------------------
	_ok(absf(main.upgrades.wear_multiplier() - 1.0) < 0.0001,
		"without the protector wear accrues at 1.0")
	_ok(not _kitted_done(), "Fully kitted starts undone at 11 of 12")
	main.ledger.credit(50000, "test funds")
	var bal_before := int(main.ledger.snapshot().balance_cents)
	main._on_menu_upgrade_buy("surge_protector")
	_ok(main.upgrades.is_owned("surge_protector"),
		"the real purchase path installs the protector")
	_ok(int(main.ledger.snapshot().balance_cents) == bal_before - 10000,
		"the purchase charges exactly $100")
	var install_logged := false
	for entry in main.workshop_log.entries():
		if str(entry["kind"]) == "upgrade" and "Surge protector" in str(entry["text"]):
			install_logged = true
	_ok(install_logged, "the install lands in the workshop log")
	_ok(absf(main.upgrades.wear_multiplier() - 0.5) < 0.0001,
		"with the protector wear accrues at 0.5")
	main._on_menu_upgrade_buy("surge_protector")
	_ok(int(main.ledger.snapshot().balance_cents) == bal_before - 10000,
		"a second buy is refused without a second charge")

	# --- a completed print wears half as fast ----------------------------------
	_stand_at_printer_a()
	main._try_interact()  # accept
	var c0 = main.active_contract
	if c0 == null:
		_ok(false, "E at printer A accepts a contract")
		_finish()
		return
	main._try_interact()  # preview
	main._try_interact()  # confirm
	_ok(c0.state == Contract.State.PRINTING, "print confirmed")
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_OK, "print completes")
	main.paused = false
	main._try_interact()  # collect
	var diff1: int = c0.difficulty
	_ok(main._try_pack_held(), "pack delivers the part")
	_ok(absf(float(main._machine(0).get("wear")) - float(6 + diff1) * 0.5) < 0.001,
		"completed print accrues (6+difficulty)*0.5 wear (got %.1f, diff %d)" % [
			float(main._machine(0).get("wear")), diff1])

	# --- a failed print wears half as fast (12 -> 6) ----------------------------
	main._machine(0)["filament_g"] = 5000  # test setup: room for a second job
	main._try_interact()  # accept
	var c1 = main.active_contract
	if c1 == null:
		_ok(false, "second contract accepts")
		_finish()
		return
	main._try_interact()  # preview
	main._try_interact()  # confirm
	var wear_now := float(main._machine(0).get("wear"))
	main.sim.failure_seeded = true
	main.paused = true
	_drive()
	_ok(main.sim.state == PrintSim.State.DONE_FAIL, "seeded failure lands")
	main.sim.failure_seeded = false
	main.paused = false
	main._try_interact()  # clear the failed print
	_ok(absf(float(main._machine(0).get("wear")) - (wear_now + 6.0)) < 0.001,
		"failed print accrues 12*0.5 = 6 wear (now %.1f)" % float(main._machine(0).get("wear")))

	# --- Fully kitted tracks the catalog size -----------------------------------
	main.upgrades.load_owned(Upgrades.catalog().map(func(x) -> String: return str(x.id)))
	var hint := ""
	for a in main._achievements():
		if str(a.name) == "Fully kitted":
			hint = str(a.hint)
			_ok(bool(a.done), "owning all 12 unlocks Fully kitted")
	_ok(hint == "own all 12 upgrades", "the hint names the new catalog size")

	# --- the upgrades panel lists the new card -----------------------------------
	var cards: Array = main.upgrade_cards()
	_ok(cards.size() == 12, "upgrade_cards lists 12 cards")
	var found := false
	for card in cards:
		if str(card.id) == "surge_protector":
			found = str(card.name) == "Surge protector" and bool(card.owned)
	_ok(found, "the panel carries the surge protector card, marked owned")

	# --- persistence: ownership survives save + reload ---------------------------
	main._save_game()
	var saved: Dictionary = BrowserSave.load_payload()
	var ids: Array = saved.get("upgrades", [])
	_ok(ids.has("surge_protector"), "ownership persists in the payload")
	main.queue_free()
	await physics_frame
	var main2 = packed.instantiate()
	root.add_child(main2)
	await physics_frame
	_ok(main2.upgrades.is_owned("surge_protector")
		and absf(main2.upgrades.wear_multiplier() - 0.5) < 0.0001,
		"a restored boot wears at 0.5 again")
	main2.queue_free()
	await physics_frame

	_finish()


func _finish() -> void:
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

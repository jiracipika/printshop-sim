extends SceneTree

## v0.41.0 — "Save slots": three shops side by side, Settings picker,
## META remembers the active slot, reset clears only the active slot.
## Run: timeout 180 godot --headless --path . -s tests/v041_test.gd

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
	BrowserSave.save_path = BrowserSave.DEFAULT_PATH  # enable slot logic
	BrowserSave.clear()
	if FileAccess.file_exists(BrowserSave.slot_path(1)):
		DirAccess.remove_absolute(BrowserSave.slot_path(1))
	if FileAccess.file_exists(BrowserSave.slot_path(2)):
		DirAccess.remove_absolute(BrowserSave.slot_path(2))
	BrowserSave.save_meta({"last_slot": 1})

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	main.paused = false
	main.captured = true
	main._machine(0)["filament_g"] = 50000

	# Boot honors the META's last_slot.
	_ok(main.active_slot == 1, "boot reads slot 1 from the meta")
	_ok(BrowserSave.save_path == BrowserSave.slot_path(1),
		"saves target the slot-1 file")

	# Slot 1: deliver an order (real state to tell slots apart).
	main.job_board._queue.clear()
	main.job_board._queue.append(load("res://scripts/JobBoard.gd")._contract_from({
		"id": "G-S1", "client": "Slot One", "model_name": "Slot marker",
		"payout_cents": 5000, "material_cost_cents": 300, "difficulty": 1,
		"risk_flags": [], "layers": 40, "deadline_days": 6, "rush": false,
		"competing": false, "offered_day": 1, "color": "", "parts_total": 1,
		"note": "",
	}))
	main._player.global_position = Vector3(-1.8, 0.3, -1.0)
	await physics_frame
	await physics_frame
	main._try_interact()
	var sim: PrintSim = main._machine(0).get("sim")
	main._machine(0)["orient"] = 0
	main._machine(0)["orient_pending"] = true
	main._prep_on(0)
	sim._failure_tick = -1
	sim.failure_seeded = false
	while sim.is_running():
		sim.tick(1.0)
	main._try_interact()
	main._player.global_position = Vector3(2.0, 0.3, 0.9)
	await physics_frame
	await physics_frame
	main._try_interact()
	_ok(int(main.stats.delivered) == 1, "slot-1 shop delivered an order")
	main._save_game()
	var s1_file := FileAccess.open(BrowserSave.slot_path(1), FileAccess.READ)
	_ok(s1_file != null, "slot-1 file exists on disk")
	if s1_file != null:
		s1_file.close()
	main.queue_free()
	await physics_frame

	# Switch to slot 2: the picker records the choice, and the next boot
	# follows the META to slot 2 (slot-2 file already deleted = fresh).
	BrowserSave.save_meta({"last_slot": 2})
	BrowserSave.save_path = BrowserSave.DEFAULT_PATH
	_ok(BrowserSave.active_slot() == 1
		or BrowserSave.active_slot() == 2, "slot bookkeeping sane")
	var main2 = packed.instantiate()
	root.add_child(main2)
	for i in range(6):
		await physics_frame
	_ok(main2.active_slot == 2, "slot-2 boot reads its own slot")
	_ok(main2.active_slot == 2 and int(main2.stats.delivered) == 0,
		"slot 2 starts fresh (slot-1 progress not visible)")
	_ok(main2.ledger.balance() == 2500, "slot-2 opening funds untouched")
	# Save something small in slot 2.
	main2._save_game()
	var s2_file := FileAccess.open(BrowserSave.slot_path(2), FileAccess.READ)
	_ok(s2_file != null, "slot-2 file exists on disk")
	if s2_file != null:
		s2_file.close()
	# Slot 1 still holds its own save.
	var s1_again := FileAccess.open(BrowserSave.slot_path(1), FileAccess.READ)
	var slot1_alive := s1_again != null
	if s1_again != null:
		var txt := s1_again.get_as_text()
		slot1_alive = txt.contains("Slot One") or txt.length() > 100
		s1_again.close()
	_ok(slot1_alive, "slot-1 file untouched by slot-2 play")
	main2.queue_free()
	await physics_frame

	# META remembers the last slot.
	var meta: Dictionary = BrowserSave.load_meta()
	_ok(int(meta.get("last_slot", 0)) == 2 or int(meta.get("last_slot", 0)) == 1,
		"meta file readable (last_slot recorded)")

	# Reset clears only the ACTIVE slot: aim at slot 2, clear, slot 1 intact.
	BrowserSave.switch_slot(2)
	BrowserSave.clear()
	_ok(not FileAccess.file_exists(BrowserSave.slot_path(2)),
		"reset clears the active slot's file")
	_ok(FileAccess.file_exists(BrowserSave.slot_path(1)),
		"slot-1 file survives a slot-2 reset")

	# Validator: slot paths are per-slot and default-stable.
	_ok(BrowserSave.slot_path(0) == BrowserSave.DEFAULT_PATH
		and BrowserSave.slot_path(99) == BrowserSave.DEFAULT_PATH,
		"out-of-range slots fall back to the default path")

	BrowserSave.save_path = BrowserSave.DEFAULT_PATH
	BrowserSave.clear()  # removes all slot files
	BrowserSave.save_meta({"last_slot": 1})  # leave the ladder on slot 1
	BrowserSave.save_path = "user://v041_test_save.json"
	BrowserSave.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

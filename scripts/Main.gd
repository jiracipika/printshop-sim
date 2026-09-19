extends Node3D

## Main scene: first-person shop floor with two 3D printers.
## Interact (E) at a printer to start the queued job; print sim drives scores.

const PLAYER_SPEED := 4.5
const MOUSE_SENS := 0.0025
const INTERACT_RANGE := 3.0
const GRAB_RANGE := 2.2

var sim: PrintSim
var job_board: Node
var ledger: Ledger
var active_contract: Contract = null
var pitch := 0.0
var yaw := 0.0
var captured := false
var paused := true
var held: Grabbable = null

var _player: CharacterBody3D
var _camera: Camera3D
var _printers: Array[Node3D] = []
var _print_visuals: Array[Node3D] = []
var _hud: CanvasLayer
var _status: Label
var _prompt: Label
var touch_controls: TouchControls

## Room palette (task 01 spec): exposed for tests and future theming.
var world := {}

const ROOM_W := 7.0
const ROOM_D := 6.0
const ROOM_H := 3.0

func _ready() -> void:
	add_to_group("main")
	ledger = Ledger.new()
	ledger.credit(2500, "opening funds")
	_build_world()
	_build_player()
	_add_spool(Vector3(0.2, 0.14, 0.2))
	_build_hud()
	# Browser-safe start: mouse visible, gameplay paused until a deliberate
	# left click captures the pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	captured = false
	paused = true

func _build_world() -> void:
	# Palette materials (sage / honey / dark steel / terracotta).
	var sage := StandardMaterial3D.new()
	sage.albedo_color = Color("#738771")
	sage.roughness = 0.9
	var honey := StandardMaterial3D.new()
	honey.albedo_color = Color("#C3A076")
	honey.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#202B2B")
	steel.roughness = 0.5
	var terracotta := StandardMaterial3D.new()
	terracotta.albedo_color = Color("#DA623A")
	terracotta.roughness = 0.6
	world = {"sage": sage, "honey": honey, "steel": steel, "terracotta": terracotta}

	# Floor: terracotta slab 7x6 m.
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(ROOM_W, 0.2, ROOM_D)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = terracotta
	floor_mesh.position = Vector3(0, -0.1, 0)
	add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_col := BoxShape3D.new()
	floor_col.size = Vector3(ROOM_W, 0.2, ROOM_D)
	floor_shape.shape = floor_col
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)

	# Four walls: sage, each with a matching StaticBody3D (meta "wall").
	var wall_specs := [
		# [size, position]
		[Vector3(ROOM_W, ROOM_H, 0.2), Vector3(0, ROOM_H / 2.0, -ROOM_D / 2.0)],      # back
		[Vector3(ROOM_W, ROOM_H, 0.2), Vector3(0, ROOM_H / 2.0, ROOM_D / 2.0)],       # front
		[Vector3(0.2, ROOM_H, ROOM_D), Vector3(-ROOM_W / 2.0, ROOM_H / 2.0, 0)],      # left
		[Vector3(0.2, ROOM_H, ROOM_D), Vector3(ROOM_W / 2.0, ROOM_H / 2.0, 0)],       # right
	]
	for spec in wall_specs:
		var wall_mesh := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		wall_box.size = spec[0]
		wall_mesh.mesh = wall_box
		wall_mesh.material_override = sage
		wall_mesh.position = spec[1]
		add_child(wall_mesh)

		var wall_body := StaticBody3D.new()
		wall_body.collision_layer = 1
		wall_body.set_meta("wall", true)
		var wshape := CollisionShape3D.new()
		var wcol := BoxShape3D.new()
		wcol.size = spec[0]
		wshape.shape = wcol
		wall_body.add_child(wshape)
		wall_body.position = spec[1]
		add_child(wall_body)

	# Workbench: honey ply top, dark steel legs, terracotta fascia stripe.
	var bench := Node3D.new()
	bench.add_to_group("bench")
	bench.position = Vector3(-1.8, 0, -2.0)

	var bench_top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(2.4, 0.1, 0.9)
	bench_top.mesh = top_box
	bench_top.material_override = honey
	bench_top.position = Vector3(0, 0.9, 0)
	bench.add_child(bench_top)

	var bench_fascia := MeshInstance3D.new()
	var fascia_box := BoxMesh.new()
	fascia_box.size = Vector3(2.4, 0.12, 0.94)
	bench_fascia.mesh = fascia_box
	bench_fascia.material_override = terracotta
	bench_fascia.position = Vector3(0, 0.79, 0)
	bench.add_child(bench_fascia)

	for sx in [-1.05, 1.05]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.1, 0.8, 0.1)
			leg.mesh = leg_box
			leg.material_override = steel
			leg.position = Vector3(sx, 0.4, sz)
			bench.add_child(leg)

	var bench_body := StaticBody3D.new()
	bench_body.collision_layer = 1
	var bshape := CollisionShape3D.new()
	var bcol := BoxShape3D.new()
	bcol.size = Vector3(2.4, 1.0, 0.94)
	bshape.shape = bcol
	bench_body.add_child(bshape)
	bench_body.position = Vector3(0, 0.5, 0)
	bench.add_child(bench_body)
	add_child(bench)

	# Lights
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.8, 0)
	lamp.omni_range = 12.0
	lamp.light_energy = 0.5
	add_child(lamp)

	# Two printers: one on the bench, one on a steel floor stand against the back wall.
	var printer_a := _make_printer(0)
	printer_a.position = Vector3(-1.8, 0.95, -2.0)
	add_child(printer_a)
	_printers.append(printer_a)

	var printer_b := _make_printer(1)
	printer_b.position = Vector3(1.8, 0.8, -2.4)
	add_child(printer_b)
	_printers.append(printer_b)

	var stand := MeshInstance3D.new()
	var stand_box := BoxMesh.new()
	stand_box.size = Vector3(0.8, 0.8, 0.8)
	stand.mesh = stand_box
	stand.material_override = steel
	stand.position = Vector3(1.8, 0.4, -2.4)
	add_child(stand)

	sim = PrintSim.new()
	sim.add_to_group("print_sim")
	add_child(sim)
	sim.print_started.connect(_on_print_started)
	sim.print_finished.connect(_on_print_done)
	job_board = load("res://scripts/JobBoard.gd").new()
	job_board.add_to_group("job_board")
	add_child(job_board)

func _add_spool(pos: Vector3) -> void:
	var spool := Grabbable.new()
	spool.name = "Spool"
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.28
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#DA623A")
	mat.roughness = 0.6
	mesh.material_override = mat
	spool.add_child(mesh)
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.14
	col.height = 0.28
	shape.shape = col
	spool.add_child(shape)
	# Hold marker: where a grabbed prop attaches, in front of the camera.
	var hold := Marker3D.new()
	hold.name = "HoldMarker"
	hold.position = Vector3(0.25, -0.1, -0.55)
	_camera.add_child(hold)
	spool.position = pos
	spool.mass = 1.0
	add_child(spool)

## Center-screen grab ray. Returns { "collider": Object, "grabbable": Grabbable }
## for the first body hit within GRAB_RANGE; walls/bench bodies occlude.
func _grab_raycast() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		_camera.global_position,
		_camera.global_position - _camera.global_transform.basis.z * GRAB_RANGE)
	q.collision_mask = 1 | 4  # world + grabbable; player (2) excluded
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var grab: Grabbable = hit.collider as Grabbable
	return {"collider": hit.collider, "grabbable": grab}

func _current_grabbable() -> Grabbable:
	var r := _grab_raycast()
	return r.get("grabbable", null)

func _try_grab() -> bool:
	# Second object cannot be grabbed while holding one.
	if held != null:
		return false
	var g := _current_grabbable()
	if g == null or not g.can_grab():
		return false
	g.on_grabbed()
	held = g
	g.get_parent().remove_child(g)
	_camera.get_node("HoldMarker").add_child(g)
	g.transform = Transform3D.IDENTITY
	return true

## Placement validator: floor or bench-top surface allowed; overlap with
## wall/bench (or any world static) invalid. Returns "" if valid else reason.
func _placement_error(world_pos: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.15
	shape.height = 0.3
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, world_pos)
	q.collision_mask = 1  # world statics only
	if not space.intersect_shape(q, 1).is_empty():
		return "No room here"
	return ""

func _try_place() -> bool:
	if held == null:
		return false
	var marker: Node3D = _camera.get_node("HoldMarker")
	var drop_pos: Vector3 = marker.global_position
	# Drop toward the floor from the hold point; ray finds the support surface.
	var space := get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(drop_pos, drop_pos + Vector3(0, -3.0, 0))
	rq.collision_mask = 1
	rq.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(rq)
	var target: Vector3 = drop_pos
	if not hit.is_empty():
		target = hit.position + Vector3(0, 0.15, 0)  # spool half-height above surface
	var err := _placement_error(target)
	if err != "":
		_set_prompt(err)
		return false  # keeps the object held
	var old_parent := held.get_parent()
	old_parent.remove_child(held)
	add_child(held)
	held.global_position = target
	held.on_released()
	held = null
	return true

## E / touch Interact: grab when empty-handed, place when holding.
## Falls through to printer interaction when empty-handed and nothing
## grabbable is targeted (desktop pointer-lock / touch-active gating lives
## in _try_interact; the key path is only reachable while unpaused).
func _try_grab_or_place() -> void:
	if paused:
		return
	if held != null:
		_try_place()
		return
	if not _try_grab():
		_try_interact()

func _set_prompt(t: String) -> void:
	_prompt.text = t

func _make_printer(idx: int) -> Node3D:
	var root: Node3D = load("res://scripts/Printer.gd").new()
	root.name = "Printer%d" % idx
	root.set_meta("printer_index", idx)

	# PrintVisual sits on the bed plate (bed top = 0.10 above printer origin).
	var visual: Node3D = load("res://scripts/PrintVisual.gd").new()
	visual.name = "PrintVisual"
	visual.position = Vector3(0, 0.10, 0)
	root.add_child(visual)
	_print_visuals.append(visual)

	var label := Label3D.new()
	label.text = "Printer %d" % (idx + 1)
	label.position = Vector3(0, 0.85, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.85, 0.4)
	root.add_child(label)
	return root

func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.collision_layer = 2
	_player.collision_mask = 1
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	col.shape = capsule
	_player.add_child(col)
	col.position = Vector3(0, 0.85, 0)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.6, 0)
	_camera.fov = 75.0
	_player.add_child(_camera)
	_player.add_to_group("player")
	_player.position = Vector3(0, 0.3, 1.8)
	add_child(_player)
	_camera.current = true

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override("font_size", 16)
	_status.text = "..."
	_hud.add_child(_status)
	# Filled each frame by _update_hud via Version autoload (resolved at runtime).
	_prompt = Label.new()
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -64
	_prompt.offset_bottom = -32
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.text = "Click to play"
	_hud.add_child(_prompt)

	# Mobile touch overlay (visibility follows effective_enabled()).
	touch_controls = TouchControls.new()
	touch_controls.interact_pressed.connect(_on_touch_interact)
	touch_controls.pause_requested.connect(_on_touch_pause)
	touch_controls.resume_requested.connect(_on_touch_resume)
	add_child(touch_controls)
	# Startup prompt must tell mobile users the real gesture: the boot state is
	# paused and mobile has no pointer-lock click — the way in is the Resume tap.
	_prompt.text = "Tap Resume to play" if touch_controls.effective_enabled() \
			else "Click to play"

## --- touch (mobile) state — separate from desktop `captured` pointer lock --

func _on_touch_interact() -> void:
	if paused:
		return
	_try_grab_or_place()

func _on_touch_pause() -> void:
	paused = true
	touch_controls.set_motion_enabled(false)
	_prompt.text = "Paused — tap Resume"

func _on_touch_resume() -> void:
	paused = false
	touch_controls.set_motion_enabled(true)
	_prompt.text = "Left stick move   Right side look   Interact   Pause"

func get_touch_move_axis() -> Vector2:
	return touch_controls.get_move_axis()

func consume_touch_look_delta() -> Vector2:
	return touch_controls.consume_look_delta()

## Effective pointer-lock state. On real display servers `Input.mouse_mode`
## is the sole authority: if the browser denies or loses pointer lock the raw
## mode falls back to VISIBLE and the game reports unlocked/paused even though
## our `captured` intent flag is set. The headless display server cannot
## reflect pointer lock at all (probed: mouse_mode pinned to VISIBLE), so
## there the intent flag stands in to keep behavioral tests meaningful.
func get_mouse_locked() -> bool:
	if DisplayServer.get_name() == "headless":
		return captured
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _release_capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	captured = false
	paused = true
	_prompt.text = "Click to play"

func _unhandled_input(event: InputEvent) -> void:
	# Browsers may synthesize mouse events after a touch gesture.
	if event is InputEventMouse and touch_controls != null and touch_controls.effective_enabled():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_release_capture()
		elif event.physical_keycode == KEY_E:
			_try_grab_or_place()
	# Deliberate (re)capture: allowed when paused, or when effectively
	# unlocked (covers the browser case where pointer lock was denied or
	# lost — raw mode fell back to VISIBLE while captured was still true —
	# so the next click can re-request it instead of soft-locking).
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and (paused or not get_mouse_locked()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		captured = true
		paused = false
		_prompt.text = "WASD move   Mouse look   E interact   Esc release mouse"
	elif event is InputEventMouseMotion and get_mouse_locked():
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENS
		pitch = clampf(pitch - mm.relative.y * MOUSE_SENS, -1.4, 1.4)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Desktop: release capture. Mobile: clear fingers/axes and pause.
		if touch_controls != null:
			touch_controls.clear_all_fingers()
		if get_mouse_locked():
			_release_capture()
		elif not paused:
			paused = true
			touch_controls.set_motion_enabled(false)
			_prompt.text = "Paused — tap Resume"

## Shared motion drop on pause/focus-loss (desktop keys + touch fingers/axes).
func drop_motion_inputs() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	if touch_controls != null:
		touch_controls.clear_all_fingers()
	_player.velocity = Vector3.ZERO

## Fold pending touch look into yaw/pitch (deadzone-free, pitch-clamped).
func apply_touch_look() -> void:
	if touch_controls == null:
		return
	var look := touch_controls.consume_look_delta()
	if look == Vector2.ZERO:
		return
	var sens := get_touch_look_sens()
	yaw -= look.x * sens
	pitch = clampf(pitch - look.y * sens, -1.4, 1.4)

## Look sensitivity scaled by viewport size so look speed is stable on phones.
func get_touch_look_sens() -> float:
	var vs := get_viewport().get_visible_rect().size
	return MOUSE_SENS * 3.0 * (720.0 / maxf(vs.y, 1.0))

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var touch_active := touch_controls != null and touch_controls.effective_enabled() and touch_controls.is_motion_enabled()
	if paused or (not get_mouse_locked() and not touch_active):
		# Paused (Esc/focus loss) or browser took pointer lock away: no
		# movement, no simulation, and latched inputs are dropped.
		drop_motion_inputs()
		return
	apply_touch_look()
	_player.rotation.y = yaw
	_camera.rotation.x = pitch
	var dir := Vector3.ZERO
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var tmove := get_touch_move_axis()
	if Input.is_action_pressed("move_forward") or tmove.y < -0.01:
		dir += fwd
	if Input.is_action_pressed("move_back") or tmove.y > 0.01:
		dir -= fwd
	if Input.is_action_pressed("move_left") or tmove.x < -0.01:
		dir -= right
	if Input.is_action_pressed("move_right") or tmove.x > 0.01:
		dir += right
	if dir.length_squared() > 0.0:
		dir = dir.normalized() * PLAYER_SPEED
	_player.velocity.x = dir.x
	_player.velocity.z = dir.z
	if not _player.is_on_floor():
		_player.velocity.y -= 14.0 * delta
	_player.move_and_slide()
	sim.tick(delta)
	_update_print_visuals(delta)
	_update_hud()

## Drive the per-printer deposition visual from the sim (task 04).
## Only one printer prints at a time; the visual shows on printer 0 unless
## the nearest printer is closer than a small threshold while RUNNING.
func _update_print_visuals(delta: float) -> void:
	var target := 0  # nearest-active printer, else printer 0
	if _print_visuals.is_empty():
		return
	var running := sim.is_running()
	var done := sim.state == PrintSim.State.DONE_OK or sim.state == PrintSim.State.DONE_FAIL
	for i in range(_print_visuals.size()):
		var visual = _print_visuals[i]
		var is_active_printer := (i == target) and (running or done)
		if running and sim.state == PrintSim.State.RUNNING and is_active_printer:
			visual.set_progress(sim.progress(), sim.model_name)
		elif is_active_printer:
			# DONE_OK: hold final shape. DONE_FAIL: gray it out once.
			visual.set_progress(sim.progress(), sim.model_name)
			if sim.state == PrintSim.State.DONE_FAIL and not visual.is_failed():
				visual.mark_failed()
		else:
			visual.reset()

	# Nozzle "life": slow oscillation while RUNNING, on the active printer.
	if running:
		var printer = _printers[target]
		if printer != null and printer.get("set_nozzle_scan") != null:
			printer.set_nozzle_scan(elapsed_nozzle_clock)
	elapsed_nozzle_clock += delta

var elapsed_nozzle_clock := 0.0

## Called whenever a fresh job begins so the visual restarts clean.
func _on_print_started() -> void:
	for visual in _print_visuals:
		visual.reset()

## Sim finished: park the contract at INSPECTION (success) or FAILED.
func _on_print_done(ok: bool) -> void:
	if active_contract == null:
		return
	if ok and active_contract.state == Contract.State.PRINTING:
		_advance(active_contract, Contract.State.INSPECTION)
	elif not ok:
		if active_contract.state in [Contract.State.PREPARING, Contract.State.PRINTING, Contract.State.INSPECTION]:
			_advance(active_contract, Contract.State.FAILED)
		_set_prompt("Print FAILED — %s lost. No payout." % active_contract.model_name)
		active_contract = null

func _nearest_printer() -> Node3D:
	var best: Node3D = null
	var best_d := INTERACT_RANGE
	for p in _printers:
		var d: float = _player.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

## --- contract economy (task 09) ---

## Legal transition helper. Contract owns the table; Main owns the write.
func _advance(contract: Contract, to: Contract.State) -> bool:
	if not Contract.can_transition(contract.state, to):
		return false
	contract.state = to
	return true

func _collect_print() -> bool:
	var c := active_contract
	if c == null or c.state != Contract.State.INSPECTION:
		return false
	if not _advance(c, Contract.State.PACKED):
		return false
	if not _advance(c, Contract.State.DELIVERED):
		return false
	if not ledger.pay_once(c.id, c.payout_cents, "payout %s" % c.id):
		return false
	active_contract = null
	_set_prompt("Delivered %s — $%s" % [c.model_name, _cents_str(c.payout_cents)])
	return true

func _accept_print() -> void:
	if not job_board.has_available():
		return
	var job: Contract = job_board.take_next()
	# OFFERED -> ACCEPTED -> PREPARING -> PRINTING, all validated.
	if not _advance(job, Contract.State.ACCEPTED):
		job_board.put_back(job)
		return
	if not _advance(job, Contract.State.PREPARING):
		_advance(job, Contract.State.FAILED)
		job_board.put_back(job)
		return
	if not ledger.can_afford(job.material_cost_cents):
		# Refuse BEFORE any irreversible step; hand the job back untouched.
		job.state = Contract.State.OFFERED
		job_board.put_back(job)
		_set_prompt("Not enough funds for materials ($%s)" % _cents_str(job.material_cost_cents))
		return
	if not ledger.charge(job.material_cost_cents, "materials %s" % job.id):
		job.state = Contract.State.OFFERED
		job_board.put_back(job)
		_set_prompt("Not enough funds for materials ($%s)" % _cents_str(job.material_cost_cents))
		return
	if not _advance(job, Contract.State.PRINTING):
		_advance(job, Contract.State.FAILED)
		job_board.put_back(job)
		# Refund: the print never started.
		ledger.credit(job.material_cost_cents, "refund materials %s" % job.id)
		return
	active_contract = job
	sim.start_job(job.id, job.model_name, job.layers)

func _cents_str(cents: int) -> String:
	return "%d.%02d" % [cents / 100, absi(cents) % 100]

func _try_interact() -> void:
	if paused:
		return
	# Desktop requires pointer lock; mobile requires touch motion active
	# (resume state). Either gameplay-active path may interact.
	if not get_mouse_locked() and not touch_controls.is_motion_enabled():
		return
	# Holding an object: E means place, not start a print.
	if held != null:
		_try_place()
		return
	if sim.is_running():
		return
	var printer := _nearest_printer()
	if printer == null:
		return
	# Collect a finished print first (INSPECTION park from DONE_OK).
	if _collect_print():
		return
	if active_contract != null:
		return  # one contract at a time
	if not job_board.has_available():
		return
	_accept_print()

## Contextual grab/place HUD line, appended to the status panel.
func _grab_prompt_line() -> String:
	if held != null:
		return "[E] Place"
	var g := _current_grabbable()
	if g != null and g.can_grab():
		return "[E] Grab spool"
	return ""

func _update_hud() -> void:
	var lines: Array[String] = []
	var version_label: String = "Print Shop Sim"
	if Engine.has_singleton("Version") or get_node_or_null("/root/Version") != null:
		version_label = get_node("/root/Version").label()
	lines.append(version_label)
	if ledger != null:
		lines.append("Balance: $%s" % _cents_str(ledger.balance()))
	if active_contract != null:
		lines.append("Contract %s — %s [%s] pays $%s" % [
			active_contract.id,
			active_contract.model_name,
			Contract.state_name(active_contract.state),
			_cents_str(active_contract.payout_cents),
		])
	lines.append("Jobs waiting: %d" % job_board.get_available_count())
	match sim.state:
		PrintSim.State.IDLE:
			var p := _nearest_printer()
			if p != null and job_board.has_available():
				if active_contract == null:
					lines.append("[E] Accept job")
				else:
					lines.append("[E] Start print job")
		PrintSim.State.RUNNING:
			lines.append("Printing %s — layer %d/%d  %.0f%%" % [
				sim.model_name, sim.layers_done, sim.layers_total, sim.progress() * 100.0])
			lines.append("Material: %d g   Risks: %s" % [sim.material_used_g(), str(sim.current_risks())])
		PrintSim.State.DONE_OK:
			if active_contract != null and active_contract.state == Contract.State.INSPECTION:
				lines.append("Print complete — [E] Collect  $%s" % _cents_str(active_contract.payout_cents))
			else:
				lines.append("Print complete! Jobs waiting: %d" % job_board.get_available_count())
		PrintSim.State.DONE_FAIL:
			lines.append("Print FAILED (part detached mid-print). No payout.")
	var grab_line := _grab_prompt_line()
	if grab_line != "":
		lines.append(grab_line)
	_status.text = "\n".join(lines)

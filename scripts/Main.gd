extends Node3D

## Main scene: first-person shop floor with two 3D printers.
## Interact (E) at a printer to start the queued job; print sim drives scores.

const PLAYER_SPEED := 4.5
const MOUSE_SENS := 0.0025
const INTERACT_RANGE := 2.8

var sim: PrintSim
var job_board: Node
var pitch := 0.0
var yaw := 0.0
var captured := false
var paused := true

var _player: CharacterBody3D
var _camera: Camera3D
var _printers: Array[Node3D] = []
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
	_build_world()
	_build_player()
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
	printer_b.position = Vector3(1.8, 0, -2.4)
	add_child(printer_b)
	_printers.append(printer_b)

	var stand := MeshInstance3D.new()
	var stand_box := BoxMesh.new()
	stand_box.size = Vector3(1.4, 0.8, 1.4)
	stand.mesh = stand_box
	stand.material_override = steel
	stand.position = Vector3(1.8, 0.4, -2.4)
	add_child(stand)

	sim = PrintSim.new()
	sim.add_to_group("print_sim")
	add_child(sim)
	job_board = load("res://scripts/JobBoard.gd").new()
	job_board.add_to_group("job_board")
	add_child(job_board)

func _make_printer(idx: int) -> Node3D:
	var root := Node3D.new()
	root.add_to_group("printers")
	root.set_meta("printer_index", idx)

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.2, 1.2)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#202B2B") if idx == 0 else Color("#DA623A")
	mat.roughness = 0.6
	body.material_override = mat
	body.position = Vector3(0, 0.6, 0)
	root.add_child(body)

	var static_body := StaticBody3D.new()
	static_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	col.shape = shape
	static_body.add_child(col)
	static_body.position = Vector3(0, 0.6, 0)
	root.add_child(static_body)

	var nozzle := MeshInstance3D.new()
	var nozzle_mesh := BoxMesh.new()
	nozzle_mesh.size = Vector3(0.16, 0.5, 0.16)
	nozzle.mesh = nozzle_mesh
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.85, 0.85, 0.9)
	nozzle.material_override = nozzle_mat
	nozzle.position = Vector3(0, 1.45, 0)
	root.add_child(nozzle)

	var label := Label3D.new()
	label.text = "Printer %d" % (idx + 1)
	label.position = Vector3(0, 1.9, 0)
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
	_try_interact()

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
			_try_interact()
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
	_update_hud()

func _nearest_printer() -> Node3D:
	var best: Node3D = null
	var best_d := INTERACT_RANGE
	for p in _printers:
		var d: float = _player.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _try_interact() -> void:
	if paused:
		return
	# Desktop requires pointer lock; mobile requires touch motion active
	# (resume state). Either gameplay-active path may interact.
	if not get_mouse_locked() and not touch_controls.is_motion_enabled():
		return
	if sim.is_running():
		return
	var printer := _nearest_printer()
	if printer == null:
		return
	if not job_board.has_available():
		return
	var job: Dictionary = job_board.take_next()
	sim.start_job(job.id, job.model, job.layers)

func _update_hud() -> void:
	var lines: Array[String] = []
	var version_label: String = "Print Shop Sim"
	if Engine.has_singleton("Version") or get_node_or_null("/root/Version") != null:
		version_label = get_node("/root/Version").label()
	lines.append(version_label)
	lines.append("Jobs waiting: %d" % job_board.get_available_count())
	match sim.state:
		PrintSim.State.IDLE:
			var p := _nearest_printer()
			if p != null and job_board.has_available():
				lines.append("[E] Start print job")
		PrintSim.State.RUNNING:
			lines.append("Printing %s — layer %d/%d  %.0f%%" % [
				sim.model_name, sim.layers_done, sim.layers_total, sim.progress() * 100.0])
			lines.append("Material: %d g   Risks: %s" % [sim.material_used_g(), str(sim.current_risks())])
		PrintSim.State.DONE_OK:
			lines.append("Print complete! Jobs waiting: %d" % job_board.get_available_count())
		PrintSim.State.DONE_FAIL:
			lines.append("Print FAILED (part detached mid-print).")
	_status.text = "\n".join(lines)

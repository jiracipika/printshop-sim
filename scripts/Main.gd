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

var _player: CharacterBody3D
var _camera: Camera3D
var _printers: Array[Node3D] = []
var _hud: CanvasLayer
var _status: Label
var _prompt: Label

func _ready() -> void:
	add_to_group("main")
	_build_world()
	_build_player()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	captured = true

func _build_world() -> void:
	# Floor
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(14, 0.2, 12)
	floor_mesh.mesh = floor_box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.16, 0.2)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.1, 0)
	add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_col := BoxShape3D.new()
	floor_col.size = Vector3(14, 0.2, 12)
	floor_shape.shape = floor_col
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)

	# Back wall for orientation
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(14, 3, 0.2)
	wall.mesh = wall_box
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.12, 0.12, 0.16)
	wall.material_override = wall_mat
	wall.position = Vector3(0, 1.5, -6)
	add_child(wall)

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

	# Two printers on the back wall
	for i in 2:
		var printer := _make_printer(i)
		printer.position = Vector3(-2.5 + i * 5.0, 0, -4.6)
		add_child(printer)
		_printers.append(printer)

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
	mat.albedo_color = Color(0.25, 0.3, 0.42) if idx == 0 else Color(0.42, 0.28, 0.2)
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
	_player.position = Vector3(0, 0.2, 3.5)
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
	_prompt.text = "WASD move   Mouse look   E interact   Esc release mouse"
	_hud.add_child(_prompt)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			captured = false
		elif event.physical_keycode == KEY_E:
			_try_interact()
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		captured = true
	elif event is InputEventMouseMotion and captured:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENS
		pitch = clampf(pitch - mm.relative.y * MOUSE_SENS, -1.4, 1.4)

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_player.rotation.y = yaw
	_camera.rotation.x = pitch
	var dir := Vector3.ZERO
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	if Input.is_action_pressed("move_forward"):
		dir += fwd
	if Input.is_action_pressed("move_back"):
		dir -= fwd
	if Input.is_action_pressed("move_left"):
		dir -= right
	if Input.is_action_pressed("move_right"):
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

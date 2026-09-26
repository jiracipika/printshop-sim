extends Node3D

## Main scene: first-person shop floor with two 3D printers.
## Full loop: accept at a printer -> pick an orientation -> print -> collect
## the part -> carry it to the packing table -> pack & deliver -> payout.

const PLAYER_SPEED := 4.5
const MOUSE_SENS := 0.0025
const INTERACT_RANGE := 3.0
const GRAB_RANGE := 2.2
## Base PrintSim.failure_threshold (kept in sync with PrintSim's default);
## upgrade deltas are added on top.
const BASE_FAILURE_THRESHOLD := 0.55

var sim: PrintSim
var job_board: Node
var ledger: Ledger
var upgrades: Upgrades
var active_contract: Contract = null
var packing_station: PackingStation
var settings := {"mouse_sens_scale": 1.0, "sfx_volume": 0.8, "invert_y": false}
var _settings_dirty := false
var sfx: Sfx
var _hum: AudioStreamPlayer3D
var _reticle: ColorRect
var pitch := 0.0
var yaw := 0.0
var captured := false
var paused := true
var held: Grabbable = null
## Printed part awaiting delivery (meta part_contract = active contract id).
var active_part: Grabbable = null
var _scrap_armed := false
## Prep state: orientation under consideration for the active contract.
## E while PREPARING previews (advances the index); E again confirms.
var orientation_index := 0
var orientation_pending := false

var _player: CharacterBody3D
var _camera: Camera3D
var _printers: Array[Node3D] = []
var _print_visuals: Array[Node3D] = []
var _hud: CanvasLayer
var _status: Label
var _prompt: Label
var touch_controls: TouchControls
var main_menu: MainMenu
var debug_panel: DebugPanel
var last_pack_grade := ""
var save_status_line := "no save yet"
var _boot_prompt := "Click to play"

## --- menus slice -----------------------------------------------------------

func _on_menu_play() -> void:
	# Menu closes; the existing capture prompt flow takes over from here.
	main_menu.close_menu()
	_flush_settings_if_dirty()
	_prompt.text = _boot_prompt

func _on_menu_contracts() -> void:
	main_menu.show_contracts(job_board.available_summaries())

func _on_menu_upgrades() -> void:
	main_menu.show_upgrades(upgrade_cards(),
		"Balance $%s" % _cents_str(ledger.balance()))

func _on_menu_upgrade_buy(id: String) -> void:
	var e: Dictionary = Upgrades.entry(id)
	if e.is_empty() or upgrades.is_owned(id):
		return
	if not ledger.charge(int(e.cost_cents), "upgrade %s" % id):
		_set_prompt("Not enough funds for %s ($%s)" % [e.name, _cents_str(int(e.cost_cents))])
		return
	upgrades.buy(id)
	_apply_upgrade_effects()
	_save_game()
	sfx.play("upgrade")
	_set_prompt("Installed %s" % e.name)
	main_menu.show_upgrades(upgrade_cards(),
		"Balance $%s" % _cents_str(ledger.balance()))  # refresh owned/affordability

func _on_menu_setting(key: String, value) -> void:
	apply_setting(key, value, false)
	_settings_dirty = true

## Settings sliders write through on menu close, not on every drag tick.
func _flush_settings_if_dirty() -> void:
	if _settings_dirty:
		_save_game()

## Upgrade cards for the menu panel.
func upgrade_cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in Upgrades.catalog():
		out.append({
			"id": e.id,
			"name": e.name,
			"desc": e.desc,
			"cost_cents": int(e.cost_cents),
			"owned": upgrades.is_owned(e.id),
			"affordable": ledger.can_afford(int(e.cost_cents)),
		})
	return out

func _apply_upgrade_effects() -> void:
	if sim != null:
		sim.speed_multiplier = upgrades.speed_multiplier()
		sim.failure_threshold = BASE_FAILURE_THRESHOLD + upgrades.failure_threshold_delta()

## Esc routing: a subpanel (contracts/upgrades/settings) steps back to the
## main panel; the main panel closes to the resume prompt; playing opens the
## menu and pauses. Touch Pause button also lands here.
func _route_escape() -> void:
	if main_menu.is_open() and main_menu.visible:
		if main_menu.subpanel_open():
			main_menu.open_menu()
		else:
			main_menu.close_menu()
			_flush_settings_if_dirty()
			_prompt.text = _boot_prompt
		return
	main_menu.open_menu()
	paused = true
	touch_controls.set_motion_enabled(false)
	_prompt.text = ""

## Debug-panel seam: start the highest-risk offered fixture via the REAL
## accept + confirm path (used by DebugPanel action [1]).
func debug_spawn_test_print() -> bool:
	if active_contract != null or sim.is_running() or not job_board.has_available():
		return false
	var best: Contract = null
	var best_score := -1.0
	for c in job_board._queue:
		var score := float(c.risk_flags.size()) * 10.0 + float(c.difficulty)
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		return false
	# Move the chosen job to the front of the queue in place (no take/put
	# rotation — take_next refills as it pops, which makes rotation lossy).
	job_board.rotate_to_front(best)
	var before := ledger.balance()
	_accept_print()
	if active_contract != best:
		return false
	# Confirm the "upright" prep so the print actually starts (risks written).
	orientation_index = 0
	orientation_pending = true
	_prep_press()
	if active_contract != best or not sim.is_running():
		return false
	return ledger.balance() <= before + best.material_cost_cents and sim.is_running()

## Room palette (task 01 spec): exposed for tests and future theming.
var world := {}

const ROOM_W := 7.0
const ROOM_D := 6.0
const ROOM_H := 3.0

func _ready() -> void:
	add_to_group("main")
	ledger = Ledger.new()
	ledger.credit(2500, "opening funds")
	upgrades = Upgrades.new()
	_build_world()
	_build_player()
	_add_spool(Vector3(0.2, 0.14, 0.2))
	_build_audio()
	_build_hud()
	_load_save()
	apply_setting("sfx_volume", float(settings.sfx_volume), false)
	# Browser-safe start: mouse visible, gameplay paused until a deliberate
	# left click captures the pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	captured = false
	paused = true

## --- audio (task 12) --------------------------------------------------------

func _build_audio() -> void:
	sfx = Sfx.new()
	add_child(sfx)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sfx.stream("hum")
	_hum.bus = Sfx.bus_name()
	_hum.volume_db = -6.0
	_hum.unit_size = 4.0
	add_child(_hum)

## --- persistence (task 12) ---

func _load_save() -> void:
	var payload: Dictionary = load("res://scripts/BrowserSave.gd").load_payload()
	if payload.is_empty():
		return
	ledger.restore(payload.ledger)
	if payload.has("upgrades"):
		upgrades.load_owned(payload.upgrades)
		_apply_upgrade_effects()
	if payload.has("settings"):
		var s: Dictionary = payload.settings
		for key in ["mouse_sens_scale", "sfx_volume", "invert_y"]:
			if s.has(key):
				apply_setting(key, s[key], false)

func apply_setting(key: String, value, persist := true) -> void:
	settings[key] = value
	match key:
		"sfx_volume":
			Sfx.set_volume(float(value))
		# mouse_sens_scale / invert_y are read live by the look paths.
	if persist:
		_save_game()

func _save_game() -> void:
	var snapshot: Dictionary = ledger.snapshot()
	var payload: Dictionary = load("res://scripts/SaveSystem.gd").build_payload(
		snapshot, {}, snapshot.balance_cents, snapshot.paid_contract_ids, {
			"upgrades": upgrades.owned_ids(),
			"settings": settings,
		})
	var ok: bool = load("res://scripts/BrowserSave.gd").save_payload(payload)
	save_status_line = "%s at %s" % ["saved ok" if ok else "save FAILED",
		Time.get_time_string_from_system()]
	_settings_dirty = false

func _build_world() -> void:
	# Palette materials (sage / honey / dark steel / terracotta), dressed with
	# runtime-procedural textures (task 12 art pass). Albedo goes white so the
	# texture carries the palette color exactly once.
	var sage_col := Color("#738771")
	var honey_col := Color("#C3A076")
	var steel_col := Color("#202B2B")
	var terra_col := Color("#AD5F3D")  # floor: slightly deeper than the accent

	var sage := StandardMaterial3D.new()
	sage.albedo_color = Color.WHITE
	sage.albedo_texture = ShopArt.plaster(sage_col)
	sage.roughness = 0.95
	var honey := StandardMaterial3D.new()
	honey.albedo_color = Color.WHITE
	honey.albedo_texture = ShopArt.wood(honey_col)
	honey.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color.WHITE
	steel.albedo_texture = ShopArt.metal(steel_col)
	steel.roughness = 0.45
	steel.metallic = 0.4
	var terracotta := StandardMaterial3D.new()
	terracotta.albedo_color = Color("#DA623A")  # painted accent, untextured
	terracotta.roughness = 0.55
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color.WHITE
	floor_mat.albedo_texture = ShopArt.floor_tiles(terra_col)
	floor_mat.roughness = 0.9
	world = {"sage": sage, "honey": honey, "steel": steel, "terracotta": terracotta,
		"floor": floor_mat}

	_build_environment()

	# Floor: terracotta tile slab 7x6 m.
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(ROOM_W, 0.2, ROOM_D)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = floor_mat
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

	# Lights: warm sun + ceiling omnis over the work lanes.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.8, 0)
	lamp.omni_range = 12.0
	lamp.light_energy = 0.5
	add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.position = Vector3(-1.8, 2.6, 1.4)
	lamp2.omni_range = 8.0
	lamp2.light_energy = 0.35
	add_child(lamp2)

	_build_props()

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

	# Packing station against the right wall (task 11).
	packing_station = load("res://scripts/PackingStation.gd").new()
	packing_station.position = Vector3(2.4, 0, 1.2)
	add_child(packing_station)

	sim = PrintSim.new()
	sim.add_to_group("print_sim")
	add_child(sim)
	sim.print_started.connect(_on_print_started)
	sim.print_finished.connect(_on_print_done)
	job_board = load("res://scripts/JobBoard.gd").new()
	job_board.add_to_group("job_board")
	add_child(job_board)

## Sky, ambient light, ceiling and window (task 12 art pass). Everything is
## procedural — ProceduralSkyMaterial for the soft daylight ambience.
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#9FB8AD")
	sky_mat.sky_horizon_color = Color("#D8CDB4")
	sky_mat.ground_bottom_color = Color("#3C4A42")
	sky_mat.ground_horizon_color = Color("#D8CDB4")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#C9C2AE")
	env.fog_density = 0.008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Ceiling slab (closes the box; no collision needed).
	var ceiling := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(ROOM_W, 0.2, ROOM_D)
	ceiling.mesh = cb
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color("#E3DCCB")
	ceil_mat.roughness = 1.0
	ceiling.material_override = ceil_mat
	ceiling.position = Vector3(0, ROOM_H + 0.1, 0)
	add_child(ceiling)

	# Emissive ceiling fixtures above the two work lanes.
	for x in [-1.7, 1.7]:
		var fixture := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(1.1, 0.06, 0.28)
		fixture.mesh = fb
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color("#FFF4DC")
		fm.emission_enabled = true
		fm.emission = Color("#FFE9C4")
		fm.emission_energy_multiplier = 1.6
		fixture.material_override = fm
		fixture.position = Vector3(x, ROOM_H - 0.05, 0)
		fixture.add_to_group("props")
		add_child(fixture)

	# Back-wall window: emissive pane (daylight source) in a steel frame.
	var pane := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(1.5, 1.1, 0.04)
	pane.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#D8E8DF")
	pm.emission_enabled = true
	pm.emission = Color("#CFE3DA")
	pm.emission_energy_multiplier = 1.2
	pane.material_override = pm
	pane.position = Vector3(1.9, 1.8, -ROOM_D / 2.0 + 0.13)
	pane.add_to_group("props")
	add_child(pane)
	for rail in [
		[Vector3(1.62, 0.04, 0.08), Vector3(1.9, 1.8, -ROOM_D / 2.0 + 0.11)],
		[Vector3(0.06, 1.2, 0.08), Vector3(1.16, 1.8, -ROOM_D / 2.0 + 0.11)],
		[Vector3(0.06, 1.2, 0.08), Vector3(2.64, 1.8, -ROOM_D / 2.0 + 0.11)],
		[Vector3(1.62, 0.04, 0.08), Vector3(1.9, 1.21, -ROOM_D / 2.0 + 0.11)],
		[Vector3(1.62, 0.04, 0.08), Vector3(1.9, 2.39, -ROOM_D / 2.0 + 0.11)],
	]:
		var rail_mesh := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = rail[0]
		rail_mesh.mesh = rb
		rail_mesh.material_override = world.steel
		rail_mesh.position = rail[1]
		add_child(rail_mesh)

## Decorative props: shelf with spare spools, rug, posters, wall clock,
## cardboard stack and a plant. Group "props" for tests; colliders only where
## the player can reasonably walk into something solid.
func _build_props() -> void:
	# Spool shelf on the left wall.
	for y in [1.5, 1.92]:
		var board := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.32, 0.04, 1.4)
		board.mesh = bb
		board.material_override = world.honey
		board.position = Vector3(-ROOM_W / 2.0 + 0.2, y, -1.4)
		board.add_to_group("props")
		add_child(board)
	var spool_colors := [Color("#DA623A"), Color("#738771"), Color("#C3A076")]
	for i in spool_colors.size():
		var spool := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.1
		cyl.bottom_radius = 0.1
		cyl.height = 0.12
		spool.mesh = cyl
		spool.rotation_degrees = Vector3(0, 0, 90)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = spool_colors[i]
		sm.roughness = 0.6
		spool.material_override = sm
		spool.position = Vector3(-ROOM_W / 2.0 + 0.2, 1.63, -1.9 + i * 0.45)
		spool.add_to_group("props")
		add_child(spool)

	# Rug in the middle of the room (no collision — flush decor).
	var rug := MeshInstance3D.new()
	var rug_box := BoxMesh.new()
	rug_box.size = Vector3(2.4, 0.02, 1.5)
	rug.mesh = rug_box
	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color.WHITE
	rug_mat.albedo_texture = ShopArt.weave(Color("#8A4A34"))
	rug_mat.roughness = 1.0
	rug.material_override = rug_mat
	rug.position = Vector3(0.2, 0.011, 0.7)
	rug.add_to_group("props")
	add_child(rug)

	# Posters with captions.
	_add_poster(ShopArt.poster(Color("#EEE5D3"), Color("#DA623A"), [[0.08, 0.08, 0.92, 0.22]]),
		Vector3(-ROOM_W / 2.0 + 0.11, 1.7, -0.4), Vector3(0, 90, 0), "MAKE / REPAIR")
	_add_poster(ShopArt.poster(Color("#EEE5D3"), Color("#738771"), [[0.3, 0.35, 0.7, 0.75]]),
		Vector3(-0.6, 1.8, -ROOM_D / 2.0 + 0.11), Vector3(0, 0, 0), "PRINT SHOP")

	# Wall clock (real system time, ticking minute hand).
	var clock: Node3D = load("res://scripts/Clock.gd").new()
	clock.position = Vector3(0, 2.2, ROOM_D / 2.0 - 0.13)
	clock.rotation_degrees = Vector3(0, 180, 0)
	clock.add_to_group("props")
	add_child(clock)

	# Cardboard stack beside the packing station (walkable-into blocker).
	var cardboard_mat := StandardMaterial3D.new()
	cardboard_mat.albedo_color = Color.WHITE
	cardboard_mat.albedo_texture = ShopArt.cardboard(Color("#B08D57"))
	cardboard_mat.roughness = 0.9
	for spec in [
		[Vector3(0.5, 0.35, 0.42), Vector3(3.0, 0.175, 1.75), 12.0],
		[Vector3(0.4, 0.3, 0.36), Vector3(3.05, 0.5, 1.8), -8.0],
	]:
		var crate := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = spec[0]
		crate.mesh = cb
		crate.material_override = cardboard_mat
		crate.position = spec[1]
		crate.rotation_degrees = Vector3(0, spec[2], 0)
		crate.add_to_group("props")
		add_child(crate)
	var crate_body := StaticBody3D.new()
	crate_body.collision_layer = 1
	var crate_shape := CollisionShape3D.new()
	var crate_col := BoxShape3D.new()
	crate_col.size = Vector3(0.6, 0.7, 0.5)
	crate_shape.shape = crate_col
	crate_body.add_child(crate_shape)
	crate_body.position = Vector3(3.0, 0.35, 1.78)
	add_child(crate_body)

	# Potted plant in the front-left corner.
	var pot := MeshInstance3D.new()
	var pot_cyl := CylinderMesh.new()
	pot_cyl.top_radius = 0.18
	pot_cyl.bottom_radius = 0.13
	pot_cyl.height = 0.26
	pot.mesh = pot_cyl
	pot.material_override = world.terracotta
	pot.position = Vector3(-2.9, 0.13, 2.25)
	pot.add_to_group("props")
	add_child(pot)
	for i in 3:
		var leaf := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.13 + 0.03 * i
		sphere.height = 2.0 * (0.13 + 0.03 * i)
		leaf.mesh = sphere
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color("#5E7A5A").lightened(0.06 * i)
		leaf_mat.roughness = 0.9
		leaf.material_override = leaf_mat
		leaf.position = Vector3(-2.9 + 0.05 * i, 0.42 + 0.1 * i, 2.25 - 0.04 * i)
		leaf.add_to_group("props")
		add_child(leaf)
	var pot_body := StaticBody3D.new()
	pot_body.collision_layer = 1
	var pot_shape := CollisionShape3D.new()
	var pot_col := CylinderShape3D.new()
	pot_col.radius = 0.18
	pot_col.height = 0.6
	pot_shape.shape = pot_col
	pot_body.add_child(pot_shape)
	pot_body.position = Vector3(-2.9, 0.3, 2.25)
	add_child(pot_body)

func _add_poster(tex: ImageTexture, pos: Vector3, rot_deg: Vector3, caption: String) -> void:
	var poster := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.6)
	poster.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mat.roughness = 0.85
	poster.material_override = mat
	poster.position = pos
	poster.rotation_degrees = rot_deg
	poster.add_to_group("props")
	add_child(poster)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 72
	label.pixel_size = 0.0022
	label.modulate = Color("#202B2B")
	label.position = pos + Vector3(0, 0.22, 0).rotated(Vector3.UP, deg_to_rad(rot_deg.y))
	label.rotation_degrees = rot_deg
	label.add_to_group("props")
	add_child(label)

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
	# Dark steel hub so the spool reads as a spool, not a bare cylinder.
	var hub := MeshInstance3D.new()
	var hub_cyl := CylinderMesh.new()
	hub_cyl.top_radius = 0.05
	hub_cyl.bottom_radius = 0.05
	hub_cyl.height = 0.3
	hub.mesh = hub_cyl
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color("#3A4644")
	hub_mat.roughness = 0.4
	hub.material_override = hub_mat
	spool.add_child(hub)
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
	_attach_to_hand(g)
	sfx.play("grab")
	return true

## Attach any grabbable to the camera hold marker with physics disabled.
func _attach_to_hand(g: Grabbable) -> void:
	g.on_grabbed()
	held = g
	g.get_parent().remove_child(g)
	_camera.get_node("HoldMarker").add_child(g)
	g.transform = Transform3D.IDENTITY

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
	held = null  # a dropped part stays tracked via active_part; re-grabbable
	sfx.play("place")
	return true

## E / touch Interact: grab when empty-handed, place when holding.
## Falls through to printer interaction when empty-handed and nothing
## grabbable is targeted (desktop pointer-lock / touch-active gating lives
## in _try_interact; the key path is only reachable while unpaused).
func _try_grab_or_place() -> void:
	if paused:
		return
	if held != null:
		# Delivering beats placing: a held part at the packing table goes
		# through the interact path (pack / scrap), never drops on the spot.
		if _is_held_part() and _near_packing_station():
			_try_interact()
			return
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

	# PrintVisual sits on the bed plate (bed top = 0.08 above printer origin).
	var visual: Node3D = load("res://scripts/PrintVisual.gd").new()
	visual.name = "PrintVisual"
	visual.position = Vector3(0, 0.081, 0)
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
	# Translucent steel card behind the status block for readability over the
	# bright workshop.
	var card := PanelContainer.new()
	card.name = "StatusCard"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.125, 0.169, 0.169, 0.55)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(10, 10)
	_hud.add_child(card)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.text = "..."
	card.add_child(_status)
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

	# Center reticle: a tiny dot for the grab/interact ray.
	_reticle = ColorRect.new()
	_reticle.color = Color(0.93, 0.9, 0.83, 0.85)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.anchor_left = 0.5
	_reticle.anchor_right = 0.5
	_reticle.anchor_top = 0.5
	_reticle.anchor_bottom = 0.5
	_reticle.offset_left = -2
	_reticle.offset_right = 2
	_reticle.offset_top = -2
	_reticle.offset_bottom = 2
	_reticle.visible = false
	_hud.add_child(_reticle)

	# Mobile touch overlay (visibility follows effective_enabled()).
	touch_controls = TouchControls.new()
	touch_controls.interact_pressed.connect(_on_touch_interact)
	touch_controls.pause_requested.connect(_on_touch_pause)
	touch_controls.resume_requested.connect(_on_touch_resume)
	add_child(touch_controls)

	# Menus slice: main menu at boot; gameplay prompt suppressed while open.
	main_menu = MainMenu.new()
	add_child(main_menu)
	main_menu.play_pressed.connect(_on_menu_play)
	main_menu.contracts_pressed.connect(_on_menu_contracts)
	main_menu.upgrades_pressed.connect(_on_menu_upgrades)
	main_menu.upgrade_buy_pressed.connect(_on_menu_upgrade_buy)
	main_menu.settings_pressed.connect(func() -> void:
		main_menu.show_settings(settings))
	main_menu.settings_changed.connect(_on_menu_setting)
	main_menu.open_menu()

	# Menus slice: dev-only debug panel (hidden by default; debug builds only).
	debug_panel = load("res://scripts/DebugPanel.gd").new()
	debug_panel.main = self
	add_child(debug_panel)

	# Startup prompt must tell mobile users the real gesture: the boot state is
	# paused and mobile has no pointer-lock click — the way in is the Resume tap.
	_boot_prompt = "Tap Resume to play" if touch_controls.effective_enabled() \
		else "Click to play"
	_prompt.text = ""  # suppressed while the main menu is open

## --- touch (mobile) state — separate from desktop `captured` pointer lock --

func _on_touch_interact() -> void:
	if paused:
		return
	_try_grab_or_place()

func _on_touch_pause() -> void:
	paused = true
	touch_controls.set_motion_enabled(false)
	_prompt.text = "Paused — tap Resume"
	_set_reticle(false)
	_route_escape()  # menus slice: touch Pause opens the main menu

func _on_touch_resume() -> void:
	paused = false
	touch_controls.set_motion_enabled(true)
	_prompt.text = "Left stick move   Right side look   Interact   Pause"

## Reticle shows only during active gameplay.
func _set_reticle(on: bool) -> void:
	if _reticle != null:
		_reticle.visible = on and not main_menu.is_open()

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
	_set_reticle(false)
	_prompt.text = "Click to play"

func _unhandled_input(event: InputEvent) -> void:
	# Browsers may synthesize mouse events after a touch gesture.
	if event is InputEventMouse and touch_controls != null and touch_controls.effective_enabled():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_route_escape()
		elif event.physical_keycode == KEY_E:
			_try_grab_or_place()
	# Deliberate (re)capture: allowed when paused, or when effectively
	# unlocked (covers the browser case where pointer lock was denied or
	# lost — raw mode fell back to VISIBLE while captured was still true —
	# so the next click can re-request it instead of soft-locking).
	# While the main menu is open, clicks belong to the menu: never capture.
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and not main_menu.is_open() \
			and (paused or not get_mouse_locked()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		captured = true
		paused = false
		_set_reticle(true)
		_prompt.text = "WASD move   Mouse look   E interact   Esc release mouse"
	elif event is InputEventMouseMotion and get_mouse_locked():
		var mm := event as InputEventMouseMotion
		var sens := _mouse_sens()
		var y_dir := -1.0 if bool(settings.get("invert_y", false)) else 1.0
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch + y_dir * mm.relative.y * sens * -1.0, -1.4, 1.4)

## Look sensitivity scaled by the settings slider (task 12).
func _mouse_sens() -> float:
	return MOUSE_SENS * float(settings.get("mouse_sens_scale", 1.0))

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
	var y_dir := -1.0 if bool(settings.get("invert_y", false)) else 1.0
	yaw -= look.x * sens
	pitch = clampf(pitch + y_dir * look.y * sens * -1.0, -1.4, 1.4)

## Look sensitivity scaled by viewport size so look speed is stable on phones.
func get_touch_look_sens() -> float:
	var vs := get_viewport().get_visible_rect().size
	return MOUSE_SENS * float(settings.get("mouse_sens_scale", 1.0)) * 3.0 * (720.0 / maxf(vs.y, 1.0))

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

	# Nozzle "life": slow oscillation while RUNNING, on the active printer,
	# plus the looping printer hum attached to it.
	if running:
		var printer = _printers[target]
		if printer != null and printer.get("set_nozzle_scan") != null:
			printer.set_nozzle_scan(elapsed_nozzle_clock)
		if _hum != null:
			_hum.global_position = printer.global_position + Vector3(0, 0.3, 0)
			if not _hum.playing:
				_hum.play()
	elif _hum != null and _hum.playing:
		_hum.stop()
	elapsed_nozzle_clock += delta

var elapsed_nozzle_clock := 0.0

## Called whenever a fresh job begins so the visual restarts clean.
func _on_print_started() -> void:
	for visual in _print_visuals:
		visual.reset()

## Sim finished: park the contract at INSPECTION (success) or FAILED.
func _on_print_done(ok: bool) -> void:
	if ok:
		sfx.play("chime")
	if active_contract == null:
		return
	if ok and active_contract.state == Contract.State.PRINTING:
		_advance(active_contract, Contract.State.INSPECTION)
	elif not ok:
		sfx.play("buzz")
		if not _printers.is_empty() and _printers[0].get("set_failed") != null:
			_printers[0].set_failed(true)
		if active_contract.state in [Contract.State.PREPARING, Contract.State.PRINTING, Contract.State.INSPECTION]:
			_advance(active_contract, Contract.State.FAILED)
		_set_prompt("Print FAILED — %s lost. [E] clear the printer" % active_contract.model_name)
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

## --- printed part: collect, deliver, scrap ----------------------------------

func _is_held_part() -> bool:
	return held != null and str(held.get_meta("part_contract", "")) != ""

func _near_packing_station() -> bool:
	return packing_station != null and _player != null \
		and _player.global_position.distance_to(packing_station.global_position) <= INTERACT_RANGE

## A finished print (DONE_OK -> contract INSPECTION) becomes a physical part
## that the player carries to the packing table. Returns true when the press
## was consumed by collection flow (even if it only showed a hint).
func _collect_print() -> bool:
	var c := active_contract
	if c == null or c.state != Contract.State.INSPECTION:
		return false
	if is_instance_valid(active_part):
		_set_prompt("Grab the printed part and take it to the packing table")
		return true
	if held != null:
		_set_prompt("Hands full — put that down first")
		return true
	var part := _make_part(c)
	add_child(part)
	var printer := _nearest_printer()
	var origin: Vector3 = printer.global_position if printer != null else _player.global_position
	part.global_position = origin + Vector3(0, 0.28, 0)
	_attach_to_hand(part)
	active_part = part
	sfx.play("grab")
	_set_prompt("%s printed — take it to the packing table" % c.model_name)
	return true

## The delivered object: a small printed block tagged with its contract id.
func _make_part(c: Contract) -> Grabbable:
	var part := Grabbable.new()
	part.name = "PrintedPart_%s" % c.id
	part.mass = 0.4
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.1, 0.12)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#DA623A")
	mat.roughness = 0.55
	mesh.material_override = mat
	part.add_child(mesh)
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(0.12, 0.1, 0.12)
	shape.shape = col
	part.add_child(shape)
	part.set_meta("part_contract", c.id)
	return part

## Free the active part wherever it is (delivered or scrapped).
func _discard_part() -> void:
	if held != null and held == active_part:
		held.get_parent().remove_child(held)
		held.queue_free()
		held = null
	elif is_instance_valid(active_part):
		active_part.queue_free()
	active_part = null

## Pack the held part at the packing table: grade via QualityCheck, scale the
## payout, advance INSPECTION -> PACKED -> DELIVERED, pay exactly once.
func _try_pack_held() -> bool:
	var c := active_contract
	if c == null or c.state != Contract.State.INSPECTION or not _is_held_part():
		return false
	var result := packing_station.try_pack(c, {
		"final_layer": sim.layers_done,
		"total_layers": sim.layers_total,
		"risks": {
			"support_need": sim.support_need,
			"adhesion_risk": sim.adhesion_risk,
			"stability_risk": sim.stability_risk,
		},
	})
	if not result.get("packed", false):
		if result.get("grade", "") == "F":
			_scrap_armed = true
			_set_prompt("Quality F — %s not deliverable. [E] scrap it" % c.model_name)
		else:
			_set_prompt("Pack refused: %s" % result.get("reason", "?"))
		return true
	if not _advance(c, Contract.State.PACKED):
		return true
	if not _advance(c, Contract.State.DELIVERED):
		return true
	if not ledger.pay_once(c.id, result.payout_cents, "payout %s" % c.id):
		return true
	_discard_part()
	active_contract = null
	last_pack_grade = result.grade
	_save_game()
	sfx.play("cash")
	_set_prompt("Delivered %s (%s) — $%s" % [c.model_name, result.grade, _cents_str(result.payout_cents)])
	return true

## F-grade escape hatch: scrap the part, fail the contract, no payout.
func _scrap_held() -> bool:
	var c := active_contract
	if c == null or c.state != Contract.State.INSPECTION or not _is_held_part():
		return false
	_advance(c, Contract.State.FAILED)
	_discard_part()
	active_contract = null
	_save_game()
	sfx.play("buzz")
	_set_prompt("Scrapped %s. No payout." % c.model_name)
	return true

## DONE_FAIL leaves the spoiled print on the bed; clear it before the next job.
func _clear_failed_print() -> bool:
	if sim.state != PrintSim.State.DONE_FAIL:
		return false
	sim.reset()
	for visual in _print_visuals:
		visual.reset()
	if not _printers.is_empty() and _printers[0].get("set_failed") != null:
		_printers[0].set_failed(false)
	sfx.play("place")
	_set_prompt("Failed print cleared from the bed")
	return true

## --- orientation prep (task 09 gameplay) ------------------------------------

func _orientation_name() -> String:
	var names: Array[String] = PrepSystem.orientations()
	return names[clampi(orientation_index, 0, names.size() - 1)]

## Prep evaluation for the active contract, with owned-upgrade modifiers.
func _prep_eval(contract: Contract, orientation: String) -> Dictionary:
	var eval: Dictionary = PrepSystem.evaluate(contract, orientation)
	if not eval.get("valid", false):
		return eval
	var mods: Dictionary = upgrades.risk_modifiers()
	eval.adhesion_risk = clampf(float(eval.adhesion_risk) + float(mods.adhesion_risk), 0.0, 1.0)
	eval.stability_risk = clampf(float(eval.stability_risk) + float(mods.stability_risk), 0.0, 1.0)
	return eval

func _write_prep_to_sim(eval: Dictionary) -> void:
	sim.support_need = eval.support_need
	sim.adhesion_risk = eval.adhesion_risk
	sim.stability_risk = eval.stability_risk
	sim.speed_multiplier = upgrades.speed_multiplier()
	sim.failure_threshold = BASE_FAILURE_THRESHOLD + upgrades.failure_threshold_delta()

## E while the contract is PREPARING: first press previews an orientation,
## second press confirms (charges materials, starts the print). An invalid
## preview (e.g. flat side on a stability part) can't be confirmed — E cycles
## on instead. Insufficient funds returns the job to the board untouched.
func _prep_press() -> void:
	var c := active_contract
	if c == null or c.state != Contract.State.PREPARING:
		return
	if not orientation_pending:
		orientation_index = (orientation_index + 1) % PrepSystem.orientations().size()
		orientation_pending = true
		_show_prep_preview()
		return
	var eval := _prep_eval(c, _orientation_name())
	if not eval.get("valid", false):
		orientation_index = (orientation_index + 1) % PrepSystem.orientations().size()
		_show_prep_preview()
		return
	if not ledger.can_afford(c.material_cost_cents):
		c.state = Contract.State.OFFERED
		job_board.put_back(c)
		active_contract = null
		orientation_pending = false
		_set_prompt("Not enough funds for materials ($%s)" % _cents_str(c.material_cost_cents))
		return
	if not ledger.charge(c.material_cost_cents, "materials %s" % c.id):
		return
	if not _advance(c, Contract.State.PRINTING):
		ledger.credit(c.material_cost_cents, "refund materials %s" % c.id)
		active_contract = null
		return
	_write_prep_to_sim(eval)
	orientation_pending = false
	sim.start_job(c.id, c.model_name, c.layers)
	sfx.play("beep")
	_set_prompt("Printing %s — %s orientation confirmed" % [c.model_name, _orientation_name()])

func _show_prep_preview() -> void:
	var c := active_contract
	if c == null:
		return
	var orient := _orientation_name()
	var eval := _prep_eval(c, orient)
	if not eval.get("valid", false):
		_set_prompt("%s: %s — [E] cycle" % [orient, eval.reason])
		return
	_set_prompt("%s: %d%% supports, ~%dg, risk %s — [E] cycle, [E] again to confirm" % [
		orient, roundi(float(eval.support_need) * 100.0),
		int(eval.estimated_material_g), PrepSystem.risk_level(eval)])
	if debug_panel != null:
		debug_panel.orientation_in_use = orient

## --- contract economy (task 09) ---

## Legal transition helper. Contract owns the table; Main owns the write.
func _advance(contract: Contract, to: Contract.State) -> bool:
	if not Contract.can_transition(contract.state, to):
		return false
	contract.state = to
	return true

func _accept_print() -> void:
	if not job_board.has_available():
		return
	var job: Contract = job_board.take_next()
	# OFFERED -> ACCEPTED -> PREPARING. The print only starts once the player
	# confirms an orientation via _prep_press.
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
	active_contract = job
	orientation_index = 0
	orientation_pending = false
	sfx.play("click")
	_set_prompt("Accepted %s — [E] to preview orientation" % job.model_name)

func _cents_str(cents: int) -> String:
	return "%d.%02d" % [cents / 100, absi(cents) % 100]

func _try_interact() -> void:
	if paused:
		return
	# Desktop requires pointer lock; mobile requires touch motion active
	# (resume state). Either gameplay-active path may interact.
	if not get_mouse_locked() and not touch_controls.is_motion_enabled():
		return
	# Holding the printed part at the packing table delivers (or scraps) it —
	# this beats the generic place action so E never drops the part at the
	# station when the player means to deliver.
	if held != null and _is_held_part() and _near_packing_station():
		if _scrap_armed:
			_scrap_armed = false
			_scrap_held()
		else:
			_try_pack_held()
		return
	# Holding an object: E means place, not start a print.
	if held != null:
		_try_place()
		return
	# Near the packing table without the part in hand: nudge, don't act.
	if _near_packing_station() and active_contract != null \
			and active_contract.state == Contract.State.INSPECTION \
			and is_instance_valid(active_part):
		_set_prompt("The printed part is by the printer — bring it here")
		return
	var printer := _nearest_printer()
	if printer == null:
		return
	if sim.is_running():
		return
	if sim.state == PrintSim.State.DONE_FAIL:
		_clear_failed_print()
		return
	if _collect_print():
		return
	if active_contract != null:
		if active_contract.state == Contract.State.PREPARING:
			_prep_press()
		return  # one contract at a time
	if not job_board.has_available():
		return
	_accept_print()

## Contextual grab/place HUD line, appended to the status panel.
func _grab_prompt_line() -> String:
	if held != null:
		if _is_held_part():
			if _near_packing_station():
				return "[E] Scrap this part" if _scrap_armed else "[E] Pack & deliver"
			return "Carry it to the packing table ([E] sets it down)"
		return "[E] Place"
	var g := _current_grabbable()
	if g != null and g.can_grab():
		return "[E] Grab"
	return ""

func _update_hud() -> void:
	_set_reticle(paused == false)
	var lines: Array[String] = []
	var version_label: String = "Print Shop Sim"
	if Engine.has_singleton("Version") or get_node_or_null("/root/Version") != null:
		version_label = get_node("/root/Version").label()
	lines.append(version_label)
	if ledger != null:
		lines.append("Balance: $%s" % _cents_str(ledger.balance()))
	if active_contract != null:
		lines.append("Contract %s — %s [%s] pays $%s · due %dd" % [
			active_contract.id,
			active_contract.model_name,
			Contract.state_name(active_contract.state),
			_cents_str(active_contract.payout_cents),
			active_contract.deadline_days,
		])
	# Orientation prep block while the player is choosing how to print.
	if active_contract != null and active_contract.state == Contract.State.PREPARING:
		if orientation_pending:
			var eval := _prep_eval(active_contract, _orientation_name())
			if eval.get("valid", false):
				lines.append("Prep: %s — %d%% supports · ~%dg · risk %s" % [
					_orientation_name(), roundi(float(eval.support_need) * 100.0),
					int(eval.estimated_material_g), PrepSystem.risk_level(eval)])
				lines.append("[E] Confirm · [E] cycle")
			else:
				lines.append("Prep: %s — %s" % [_orientation_name(), eval.reason])
				lines.append("[E] cycle")
		else:
			lines.append("Prep: [E] preview orientation")
	lines.append("Jobs waiting: %d" % job_board.get_available_count())
	match sim.state:
		PrintSim.State.IDLE:
			if active_contract == null or active_contract.state != Contract.State.PREPARING:
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
				lines.append("Print complete — [E] collect the part")
			else:
				lines.append("Print complete! Jobs waiting: %d" % job_board.get_available_count())
		PrintSim.State.DONE_FAIL:
			lines.append("Print FAILED — [E] clear the bed, then take a new job")
	var grab_line := _grab_prompt_line()
	if grab_line != "":
		lines.append(grab_line)
	_status.text = "\n".join(lines)

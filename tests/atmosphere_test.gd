extends SceneTree

## v0.60.0 — atmosphere & presence pass: the entry door (spec position,
## collision-free swing, deterministic _advance seam, calm-mode snap, swings
## on walk-in arrival AND despawn through the slice-2 API), the OPEN sign
## (lit inside the business window via the real counter tick, dim outside,
## non-emissive at Low quality), the counter pendant (no shadows, energy
## 0.5, emissive bulb + under-lip strip), counter clutter, customer outfit
## determinism (6-color palette, hashed cap/scarf), the HUD token restyle
## (shared ink StyleBoxFlat, paper/clay/gold text, texts unchanged) and the
## v020 draw-call budget WITH a walk-in active (mirrored audit method).
## counter_test/walkin_test SceneTree pattern; every engine class is
## referenced load()-only (hazard 4). Run:
## timeout 180 godot --headless --path . -s tests/atmosphere_test.gd

const TOTAL := 25

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


## The v020 draw-call audit, mirrored: walk `from`'s subtree, count
## MeshInstance3D total and visible-in-tree (tests/v020_test.gd method).
func _audit(from: Node) -> Dictionary:
	var total := 0
	var visible := 0
	var stack: Array = [from]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			total += 1
			if n.visible and n.is_visible_in_tree():
				visible += 1
		for c in n.get_children():
			stack.append(c)
	return {"total": total, "visible": visible}


## First node under `from` whose script is `script`.
func _find_scripted(from: Node, script: Script) -> Node:
	var stack: Array = [from]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n.get_script() == script:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _has_class(from: Node, klass: String) -> bool:
	var stack: Array = [from]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n.is_class(klass):
			return true
		for c in n.get_children():
			stack.append(c)
	return false


func _count_class(from: Node, klass: String) -> int:
	var n := 0
	var stack: Array = [from]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node.is_class(klass):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


## A mesh's surface count (multi-surface ArrayMeshes count their surfaces;
## primitive meshes count once).
func _surface_total(mi: MeshInstance3D) -> int:
	var mesh: Mesh = mi.mesh
	if mesh is ArrayMesh:
		return mesh.get_surface_count()
	return 1


## Surface material s of a mesh instance: the node override, else the
## surface material for ArrayMesh surfaces, else the PrimitiveMesh's own
## mesh-level material.
func _mesh_mat(mi: MeshInstance3D, s: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var mesh: Mesh = mi.mesh
	if mesh is ArrayMesh:
		if s < mesh.get_surface_count():
			return mesh.surface_get_material(s)
		return null
	return mesh.material


## Highest local vertex y across a mesh instance's surfaces.
func _max_vertex_y(mi: MeshInstance3D) -> float:
	var mesh: Mesh = mi.mesh
	var m := -INF
	if mesh is ArrayMesh:
		for s in range(mesh.get_surface_count()):
			m = maxf(m, _surface_max_y(mesh, s))
	else:
		for v in mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
			m = maxf(m, float(v.y))
	return m


## Highest vertex y of ONE surface of a mesh.
func _surface_max_y(mesh: Mesh, s: int) -> float:
	var m := -INF
	for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
		m = maxf(m, float(v.y))
	return m


func _run() -> void:
	print("%d checks defined" % TOTAL)
	var SF = load("res://scripts/ShopFront.gd")
	var CA = load("res://scripts/CustomerActor.gd")
	var CS = load("res://scripts/CounterService.gd")
	var BS = load("res://scripts/BrowserSave.gd")
	BS.clear()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in range(6):
		await physics_frame
	# The test stays paused the whole way through: every gate below is driven
	# through its deterministic seam (direct calls), so shop time never moves
	# on its own (no natural arrivals, no natural sign flips).
	var sf: Node = _find_scripted(main, SF)

	# --- A. construction (boot) -------------------------------------------------
	_ok(sf != null and sf.get_node_or_null("DoorPivot") != null
		and absf(sf.get_node("DoorPivot").position.x - (-2.4)) < 0.001
		and absf(sf.get_node("DoorPivot").position.z - 2.88) < 0.001,
		"the shopfront builds with the door pivot at the front-wall hinge")
	var panel: MeshInstance3D = sf.get_node("DoorPivot/DoorPanel")
	var pbox: BoxMesh = panel.mesh
	_ok(pbox is BoxMesh and absf(pbox.size.x - 1.0) < 0.001 \
		and absf(pbox.size.y - 2.1) < 0.001 \
		and absf(panel.position.x - 0.5) < 0.001,
		"the door is a flush 1.0 x 2.1 panel centered on the hinge span")
	_ok(not _has_class(sf, "StaticBody3D") and not _has_class(sf, "CollisionShape3D"),
		"the door swing adds no collision (the front wall stays solid)")
	_ok(absf(sf.open_frame()) < 0.0001 and absf(sf.door_angle_deg()) < 0.0001 \
		and not sf.sign_lit() and sf.is_processing(),
		"the door boots closed, the sign boots unlit, the node animates")

	# --- B. swing seam determinism (direct _advance, no engine frames) ---------
	sf.set_motion(true)
	sf.swing()
	sf._advance(0.3)
	_ok(absf(sf.open_frame() - 0.5) < 1e-6 \
		and absf(sf.door_angle_deg() - 37.5) < 1e-4,
		"advance 0.3 s of the 0.6 s swing lands at frame 0.5 / angle 37.5")
	sf._advance(0.3)
	var open_ok := absf(sf.open_frame() - 1.0) < 1e-6 \
		and absf(sf.door_angle_deg() - 75.0) < 1e-4
	sf._advance(1.2)
	_ok(open_ok and absf(sf.open_frame() - 1.0) < 1e-6,
		"the door reaches 75 deg, holds open through the 1.2 s dwell")
	sf._advance(0.3)
	var closing_ok := absf(sf.open_frame() - 0.5) < 1e-6 \
		and absf(sf.door_angle_deg() - 37.5) < 1e-4
	sf._advance(0.3)
	_ok(closing_ok and absf(sf.open_frame()) < 1e-6 \
		and absf(sf.door_angle_deg()) < 1e-4,
		"the door closes back to 0 deg exactly one gesture after swing()")
	# Mid-closing re-arm: continuous from the current openness, deterministic.
	# (+0.05 slack so the IEEE drift of 0.6+1.2 cannot leave the dwell short.)
	sf.swing()
	sf._advance(0.6 + 1.2 + 0.05)  # opening + dwell + 0.05 into closing
	sf._advance(0.40)              # 0.45 into closing: frame 0.25
	var rearm_frame: float = sf.open_frame()
	sf.swing()
	sf._advance(0.15)
	_ok(absf(rearm_frame - 0.25) < 1e-6 \
		and absf(sf.open_frame() - 0.5) < 1e-6,
		"a mid-closing swing() re-arms opening from the current openness")
	sf._advance(3.0)
	sf.set_motion(false)
	sf.swing()
	sf._advance(0.016)
	# Angle tolerance 1e-4: deg_to_rad round-trips a hair under 75.0 exactly.
	var snap_open := absf(sf.door_angle_deg() - 75.0) < 1e-4
	sf._advance(0.6 + 1.2 + 0.6)
	_ok(snap_open and absf(sf.door_angle_deg()) < 1e-4 \
		and not _has_class(sf, "Tween"),
		"calm mode snaps open/closed with no tween residue")
	sf.set_motion(true)

	# --- C. the door swings on arrival AND despawn (slice-2 API) ----------------
	# Driven through the deterministic seam (engine-frame deltas vary between
	# headless runs; the seam exists so no check depends on them).
	main._spawn_walkin(50, 0)
	sf._advance(0.3)
	var arrived := absf(sf.open_frame() - 0.5) < 1e-6
	sf._advance(3.0)  # finish the arrival gesture: closed again
	var closed_again := absf(sf.open_frame()) < 1e-6
	main._counter_despawn()
	var actor_gone: bool = main._customer == null \
		and not main._counter_service.waiting()
	sf._advance(0.3)
	_ok(arrived,
		"a walk-in arrival swings the door open")
	_ok(closed_again and actor_gone and absf(sf.open_frame() - 0.5) < 1e-6,
		"the despawn removes the customer and swings the door again")

	# --- D. the OPEN sign ---------------------------------------------------------
	var sign: Label3D = sf.get_node("DoorPivot/OpenSign")
	sf.set_business_open(true)
	var lit: bool = sf.sign_lit()
	var lit_look: Color = sign.modulate
	sf.set_business_open(false)
	var dim_look: Color = sign.modulate
	_ok(sign != null and sign.text == "OPEN" and lit and not sf.sign_lit() \
		and lit_look == SF.SIGN_LIT and dim_look == SF.SIGN_DIM,
		"the OPEN placard hangs on the door and flips lit/dim with the window")
	# Main wiring: pin a day whose two arrival slots are both hash-disabled, so
	# the counter ticks cannot spawn anybody while we cross the window edges.
	var quiet_day := -1
	for d in range(1, 41):
		if not CS.slot_enabled(d, 0) and not CS.slot_enabled(d, 1):
			quiet_day = d
			break
	var lit_mid := false
	var lit_night := true
	var no_spawn := false
	if quiet_day > 0:
		main.day_cycle.day = quiet_day
		main.day_cycle.t = 0.5
		main._tick_counter(0.016)
		lit_mid = sf.sign_lit()
		main.day_cycle.t = 0.9
		main._tick_counter(0.016)
		lit_night = sf.sign_lit()
		no_spawn = main._customer == null and not main._counter_service.waiting()
		main.day_cycle.t = 0.0
	_ok(quiet_day > 0 and lit_mid and not lit_night and no_spawn,
		"Main lights the sign inside the business window and dims it at night (day %d)"
			% quiet_day)
	main.apply_setting("quality_preset", "Low", false)
	main.day_cycle.t = 0.5
	main._tick_counter(0.016)
	var low_lit: bool = sf.sign_lit()
	var light: OmniLight3D = sf.get_node("CounterDressing/PendantLight")
	var light_held := light != null and light.shadow_enabled == false \
		and absf(light.light_energy - 0.5) < 1e-6
	main.apply_setting("quality_preset", "Standard", false)
	_ok(not low_lit and light_held and sf.sign_lit(),
		"Low keeps the sign but non-emissive; the pendant light is not gated")

	# --- E. pendant + under-lip strip ---------------------------------------------
	_ok(light != null and light.shadow_enabled == false \
		and absf(light.light_energy - 0.5) < 1e-6 \
		and _count_class(sf, "OmniLight3D") + _count_class(sf, "DirectionalLight3D") == 1
		and absf(sf.get_node("CounterDressing").position.x - (-1.9)) < 0.001
		and absf(sf.get_node("CounterDressing").position.z - 2.55) < 0.001,
		"the pendant is the slice's ONLY new light: shadows off, energy 0.5, over the counter")
	var dressing: MeshInstance3D = sf.get_node_or_null("CounterDressing/CounterDressingMesh")
	var bulb_ok := false
	var strip_ok := false
	if dressing != null:
		var mesh: Mesh = dressing.mesh
		for s in range(mesh.get_surface_count()):
			var mat: Material = _mesh_mat(dressing, s)
			if mat is StandardMaterial3D and bool(mat.emission_enabled) \
					and float(mat.emission_energy_multiplier) >= 1.0:
				var top: float = _surface_max_y(mesh, s)
				if top > 1.5:
					bulb_ok = true  # the bulb glows under the shade mouth
				elif top < 1.0:
					strip_ok = true  # the strip glows under the counter lip
	_ok(bulb_ok,
		"the pendant carries an emissive bulb surface under its shade")
	_ok(strip_ok,
		"the under-lip light strip glows below the counter top's front edge")

	# --- F. counter clutter --------------------------------------------------------
	var clutter: MeshInstance3D = sf.get_node_or_null("CounterDressing/CounterDressingMesh")
	var on_top := clutter != null \
		and absf(clutter.get_parent().position.x - (-1.9)) < 0.001 \
		and absf(clutter.get_parent().position.z - 2.55) < 0.001
	var clutter_surfaces := 0
	if clutter != null:
		var cmesh: Mesh = clutter.mesh
		for s in range(cmesh.get_surface_count()):
			# Clutter pieces are the low, non-emissive surfaces (counter-top
			# level); the pendant stem/shade sit far higher, the strip glows.
			var cmat: Material = _mesh_mat(clutter, s)
			var emissive: bool = cmat is StandardMaterial3D \
				and bool(cmat.emission_enabled)
			if not emissive and _surface_max_y(cmesh, s) < 1.2:
				clutter_surfaces += 1
	_ok(on_top and clutter_surfaces >= 3,
		"clutter sits on the counter top as %d surfaces of the dressing mesh (slips, plant, reader)"
			% clutter_surfaces)

	# --- G. customer outfit variety (deterministic) --------------------------------
	var fresh = CA.new()
	root.add_child(fresh)
	await physics_frame
	var fresh_meshes := _count_class(fresh, "MeshInstance3D")
	fresh.set_motion(false)
	var frozen_y: float = fresh.get_node("Torso").position.y
	fresh._advance(5.0)
	var still_y: float = fresh.get_node("Torso").position.y
	fresh.set_motion(true)
	fresh._advance(5.0)
	var moved_y: float = fresh.get_node("Torso").position.y
	fresh.queue_free()
	await physics_frame
	_ok(fresh_meshes == 2 and absf(still_y - frozen_y) < 0.0001 \
		and absf(moved_y - frozen_y) > 0.001,
		"a fresh customer is still two meshes; calm freezes and _advance drives the bob")
	var outfits: Array = CA.OUTFITS
	var distinct := true
	for a in range(outfits.size()):
		for b in range(a + 1, outfits.size()):
			if outfits[a] == outfits[b]:
				distinct = false
	_ok(outfits.size() == 6 and distinct,
		"the outfit palette widened to six distinct warm-maker colors")
	# Same (day, index) -> identical palette + accessory set.
	var twin_a = CA.new()
	twin_a.position = CA.WAIT_POS
	twin_a.set_meta("walkin_day", 7)
	twin_a.set_meta("walkin_index", 1)
	var twin_b = CA.new()
	twin_b.position = CA.WAIT_POS
	twin_b.set_meta("walkin_day", 7)
	twin_b.set_meta("walkin_index", 1)
	root.add_child(twin_a)
	root.add_child(twin_b)
	await physics_frame
	var ta_torso: MeshInstance3D = twin_a.get_node("Torso")
	var tb_torso: MeshInstance3D = twin_b.get_node("Torso")
	var ta_head: MeshInstance3D = twin_a.get_node("Head")
	var tb_head: MeshInstance3D = twin_b.get_node("Head")
	var twins_match: bool = _mesh_mat(ta_torso, 0).albedo_color \
		== _mesh_mat(tb_torso, 0).albedo_color \
		and _surface_total(ta_torso) == _surface_total(tb_torso) \
		and _surface_total(ta_head) == _surface_total(tb_head)
	twin_a.queue_free()
	twin_b.queue_free()
	await physics_frame
	_ok(twins_match,
		"the same (day, index) rebuilds an identical palette and accessory set")
	# Built actors match the static draws for one sample of each accessory kind.
	var sample_slot := {}  # kind -> [day, index]
	for d in range(1, 121):
		for i in range(2):
			var k: int = CA.accessory_kind(d, i)
			if not sample_slot.has(k):
				sample_slot[k] = [d, i]
	var all_kinds := sample_slot.has(0) and sample_slot.has(1) \
		and sample_slot.has(2)
	var built_matches := all_kinds
	for k in range(3):
		var slot: Array = sample_slot[k]
		var d2: int = int(slot[0])
		var i2: int = int(slot[1])
		var actor = CA.new()
		actor.set_meta("walkin_day", d2)
		actor.set_meta("walkin_index", i2)
		root.add_child(actor)
		await physics_frame
		var torso: MeshInstance3D = actor.get_node("Torso")
		var head: MeshInstance3D = actor.get_node("Head")
		var want := 2 + (2 if k == CA.ACC_CAP else (1 if k == CA.ACC_SCARF else 0))
		var got := _surface_total(torso) + _surface_total(head)
		var outfit_ok: bool = _mesh_mat(torso, 0).albedo_color \
			== CA.outfit_color(d2, i2)
		var acc_ok := true
		if k != CA.ACC_NONE:
			acc_ok = false
			for mi: MeshInstance3D in [torso, head]:
				for s in range(1, _surface_total(mi)):
					if _mesh_mat(mi, s).albedo_color == CA.accessory_color(d2, i2):
						acc_ok = true
		var head_ok := true
		if k == CA.ACC_CAP:
			head_ok = _max_vertex_y(head) <= 0.106  # nothing above the head top
		built_matches = built_matches and got == want and outfit_ok \
			and acc_ok and head_ok
		actor.queue_free()
		await physics_frame
	_ok(built_matches,
		"cap/scarf/none draws match the static hashes (kinds, colors, head-top bound)")

	# --- H. HUD token restyle --------------------------------------------------------
	# Still paused, so _update_hud has never run: the pinned texts are exactly
	# what a boot without the restyle shows.
	var card: PanelContainer = main._status.get_parent()
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	var texts_kept: bool = str(main._status.text) == "..." \
		and str(main._prompt.text) == ""
	main._update_hud()
	var hud_kept: bool = str(main._status.text).contains("Balance: $") \
		and str(main._status.text).contains("Day ")
	_ok(sb is StyleBoxFlat and sb.bg_color == Color(0.125, 0.169, 0.169, 0.95) \
		and sb.corner_radius_top_left == 4 and sb == main._hud_panel_style(),
		"the status card wears the shared ink StyleBoxFlat (0.95 opacity, radius 4)")
	_ok(main._prompt.get_theme_color("font_color") == Color("#DA623B") \
		and main._toast.get_theme_color("font_color") == Color("#F5CE80") \
		and texts_kept and hud_kept \
		and load("res://scripts/Version.gd").VERSION == "0.61.0",
		"prompt is clay, toast is gold, label texts and version are unchanged")

	# --- I. v020 budget with a walk-in active ----------------------------------------
	var acc_day := -1
	for d in range(1, 61):
		if CA.accessory_kind(d, 0) != 0:
			acc_day = d
			break
	main._spawn_walkin(acc_day, 0)
	for i in range(2):
		await physics_frame
	var with_actor: Dictionary = _audit(main)
	main._counter_despawn()
	await physics_frame
	var after: Dictionary = _audit(main)
	_ok(acc_day > 0 and int(with_actor.visible) <= 180 and int(with_actor.total) <= 400
		and int(after.visible) <= 180 and int(after.total) <= 400,
		"with an accessoried walk-in active the audit holds: %d/180 visible, %d/400 total"
			% [int(with_actor.visible), int(with_actor.total)])

	# --- cleanup ----------------------------------------------------------------------
	main.queue_free()
	await physics_frame
	BS.clear()
	BS.save_path = "user://atmosphere_test_save.json"
	BS.clear()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

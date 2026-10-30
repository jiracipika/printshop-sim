extends Node3D

## Shopfront atmosphere (v0.60.0) — the presence pass: the customer entry
## door (flush interior panel on the front wall, NO wall hole — the wall
## collision stays solid and scripted actors ignore collision), the swinging
## OPEN placard, the warm counter pendant and the counter clutter.
## WindowLife pattern: a room-space Node3D built from primitives, animated
## here in _process, with a deterministic _advance(seconds) seam gated by
## set_motion() so tests drive minutes of shopfront life instantly and calm
## mode cannot leave anything mid-tween. No Tween, no AnimationPlayer, no RNG.
##
## BUDGET (hazard 12): the v020 draw-call audit allows 180 visible / 400
## total MeshInstance3D and its audit moment runs at season=humid + Standard,
## so the 10 rain streaks are VISIBLE there — the slice-2 baseline at that
## point is 178 / 394, leaving room for exactly TWO new visible nodes. This
## node therefore adds exactly TWO audit nodes — the swinging door panel and
## ONE "CounterDressing" mesh over the counter — and spends the rest of its
## geometry on extra SURFACES of those meshes (pendant stem + cone shade +
## emissive bulb + under-lip light strip + the four clutter pieces are eight
## surfaces of the dressing mesh; same ~10 draw calls, five fewer scene
## nodes). The OPEN sign is a Label3D (never counted).

## Entry door: front wall interior face is z = ROOM_D/2 - 0.1 = 2.9; the
## flush panel sits just proud of it. Hinge on the left edge (from the room).
const DOOR_X := -1.9                    # panel centerline x (brief)
const DOOR_PANEL_W := 1.0               # panel width x height per brief
const DOOR_PANEL_H := 2.1
const DOOR_HINGE_X := DOOR_X - DOOR_PANEL_W / 2.0   # -2.4
const DOOR_Z := 2.88                    # flush against the interior face
const DOOR_MAX_SWING_DEG := 75.0        # brief: opens 75 deg
const DOOR_OPEN_S := 0.6                # brief: open over 0.6 s ...
const DOOR_HOLD_S := 1.2                # brief: ... and closed after 1.2 s

## Counter pendant: above the counter island center (CounterStation pos).
const PENDANT_POS := Vector3(-1.9, 0, 2.55)
const PENDANT_ENERGY := 0.5             # brief: energy 0.5, no shadows

## Swing state machine (deterministic: only _advance moves it).
enum SwingPhase { CLOSED, OPENING, HOLD, CLOSING }

## Lit OPEN sign vs dim sign (design tokens: focus amber lit, muted off).
const SIGN_LIT := Color(1.35, 1.08, 0.5)   # HDR gold — blooms via the glow
const SIGN_DIM := Color(0.43, 0.42, 0.37)  # muted light, reads as "off"

var motion_enabled := true
var _phase: SwingPhase = SwingPhase.CLOSED
var _phase_t := 0.0
var _quality_low := false
var _business_open := false

var _door_pivot: Node3D
var _sign: Label3D
var _pendant_light: OmniLight3D


func _ready() -> void:
	_build_door()
	_build_counter_dressing()
	_apply_swing()
	_apply_sign()


func _process(delta: float) -> void:
	_advance(delta)


## Deterministic heartbeat (WindowLife pattern): the swing state machine's
## ONLY mover, and time-faithful — one call consumes the full `seconds`,
## walking through as many phase transitions as the elapsed time covers (so
## _advance(3.0) from closed always lands back closed). Calm mode (v0.51.0)
## does not stop the machine — it changes how the frame is APPLIED (snap
## open/closed, no animation); a gated _advance would leave the door frozen
## open forever in calm mode, which is a visible state bug, so the gate lives
## in _apply_swing instead (documented in docs/worker-atmosphere.md).
func _advance(seconds: float) -> void:
	var left := maxf(seconds, 0.0)
	while left > 0.0 and _phase != SwingPhase.CLOSED:
		match _phase:
			SwingPhase.OPENING:
				left = _consume(left, DOOR_OPEN_S, SwingPhase.HOLD)
			SwingPhase.HOLD:
				left = _consume(left, DOOR_HOLD_S, SwingPhase.CLOSING)
			SwingPhase.CLOSING:
				left = _consume(left, DOOR_OPEN_S, SwingPhase.CLOSED)
			_:
				left = 0.0
	_apply_swing()


## Consume up to the current phase's remaining time; roll into `next` (with
## the timer reset) when the phase completes, else stop the walk there.
func _consume(left: float, duration: float, next: SwingPhase) -> float:
	var need := duration - _phase_t
	if left >= need:
		_phase = next
		_phase_t = 0.0
		return left - need
	_phase_t += left
	return 0.0


## Calm mode (v0.51.0): Main pushes the persisted "calm_mode" setting here.
func set_motion(on: bool) -> void:
	motion_enabled = on
	_apply_swing()


## Quality gate (v0.20 presets): at Low the OPEN sign stays on the door but
## drops its emissive lit look — the same pattern _apply_season_visuals uses
## for the rain/frost overlays. The pendant light is NOT gated (one cheap
## OmniLight3D with no shadows is the slice's only new real light).
func set_quality(low: bool) -> void:
	_quality_low = low
	_apply_sign()


## Walk-in business window (CounterService.DAY_START_FRAC..DAY_END_FRAC —
## the same frac source slice 2 arrives on). Main pushes the bool each
## counter tick; the sign flips between lit and dim.
func set_business_open(open: bool) -> void:
	_business_open = open
	_apply_sign()


## Is the sign currently showing its lit (emissive) face? Never when the
## quality preset is Low, regardless of the business window.
func sign_lit() -> bool:
	return _business_open and not _quality_low


## Swing the door: one full open-hold-close gesture. Main calls this when a
## walk-in arrives and when one despawns. Re-arming mid-gesture restarts the
## opening phase from the current openness (continuous, deterministic) —
## the openness is read BEFORE the phase flips, since open_frame() is
## phase-relative.
func swing() -> void:
	var f := open_frame()
	_phase = SwingPhase.OPENING
	_phase_t = f * DOOR_OPEN_S
	_apply_swing()


## Deterministic openness 0..1 of the swing state machine (0 closed, 1 open).
## Frame 0 before the first swing.
func open_frame() -> float:
	match _phase:
		SwingPhase.OPENING:
			return clampf(_phase_t / DOOR_OPEN_S, 0.0, 1.0)
		SwingPhase.HOLD:
			return 1.0
		SwingPhase.CLOSING:
			return clampf(1.0 - _phase_t / DOOR_OPEN_S, 0.0, 1.0)
	return 0.0


## The rotation actually applied to the door hinge, in degrees (0..75).
## Calm mode snaps this to the phase's binary target instead of animating.
func door_angle_deg() -> float:
	return rad_to_deg(_door_pivot.rotation.y) if _door_pivot != null else 0.0


func _apply_swing() -> void:
	if _door_pivot == null:
		return
	var f := open_frame()
	if not motion_enabled:
		# Calm: no animation — the door sits fully open or fully closed.
		f = 1.0 if _phase != SwingPhase.CLOSED else 0.0
	_door_pivot.rotation.y = deg_to_rad(DOOR_MAX_SWING_DEG) * f


func _apply_sign() -> void:
	if _sign == null:
		return
	_sign.modulate = SIGN_LIT if sign_lit() else SIGN_DIM


## Entry door: a pivot at the hinge edge carrying one flush honey panel (the
## steel jamb and the slim glass slit are painted into its procedural
## texture — the audit's node budget is spent deliberately, see the header).
## The swinging OPEN placard rides the pivot so it moves with the door.
func _build_door() -> void:
	_door_pivot = Node3D.new()
	_door_pivot.name = "DoorPivot"
	_door_pivot.position = Vector3(DOOR_HINGE_X, 0, DOOR_Z)
	add_child(_door_pivot)

	var panel := MeshInstance3D.new()
	panel.name = "DoorPanel"
	var box := BoxMesh.new()
	box.size = Vector3(DOOR_PANEL_W, DOOR_PANEL_H, 0.045)
	box.material = _door_material()
	panel.mesh = box
	panel.position = Vector3(DOOR_PANEL_W / 2.0, DOOR_PANEL_H / 2.0, 0)
	_door_pivot.add_child(panel)

	# The OPEN placard hangs on the glass slit (billboarded like the repo's
	# other Label3D signs) and swings with the door.
	_sign = Label3D.new()
	_sign.name = "OpenSign"
	_sign.text = "OPEN"
	_sign.font_size = 40
	_sign.pixel_size = 0.0022
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.outline_modulate = Color("#202B2B")
	_sign.outline_size = 5
	_sign.position = Vector3(DOOR_PANEL_W / 2.0, 1.52, -0.03)
	_door_pivot.add_child(_sign)


## The flush panel's look: honey plywood field, painted steel jamb border,
## and a slim dark glass slit up the middle. Built as one Image so the whole
## door assembly costs a single mesh node (budget note in the header).
func _door_material() -> StandardMaterial3D:
	var img := Image.create(256, 512, false, Image.FORMAT_RGB8)
	var honey := Color("#C3A076")
	var shadow := Color("#8B6948")
	var steel := Color("#202B2B")
	var glass := Color("#3E4A4A")
	img.fill(honey)
	# Loose horizontal grain: darker wash bands, deterministic sine phasing.
	for y in range(512):
		var g := 0.5 + 0.5 * sin(float(y) * 0.35 + 1.7 * sin(float(y) * 0.031))
		if g > 0.82:
			for x in range(20, 236):
				img.set_pixel(x, y, honey.lerp(shadow, 0.16 * (g - 0.82) / 0.18))
	# Steel jamb border: slim frame painted on the panel edges.
	for x in range(256):
		for y in range(512):
			if x < 14 or x >= 242 or y < 10:
				img.set_pixel(x, y, steel)
	# Slim glass slit: a dark vertical pane with a light catch line.
	for x in range(116, 140):
		for y in range(96, 330):
			var c := glass
			if x == 118:
				c = Color(0.62, 0.70, 0.68)
			elif x == 137:
				c = Color(0.22, 0.27, 0.27)
			img.set_pixel(x, y, c)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.65
	return mat


## Everything that dresses the counter, as ONE audit node: the warm pendant
## (steel stem + cone shade + emissive bulb), the slim emissive light strip
## under the counter top's front lip, and the counter clutter (slip stack,
## tiny plant, card-reader box) — eight surfaces of one ArrayMesh (budget
## note in the header), plus the slice's only new real light: an OmniLight3D
## with shadows off (brief: energy 0.5, honey/steel palette).
func _build_counter_dressing() -> void:
	var dressing := Node3D.new()
	dressing.name = "CounterDressing"
	dressing.position = PENDANT_POS
	add_child(dressing)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#4A5A5A")
	steel.metallic = 0.4
	steel.roughness = 0.45
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color("#FFF4DC")
	bulb.emission_enabled = true
	bulb.emission = Color("#FFD9A0")
	bulb.emission_energy_multiplier = 1.6
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color("#F5CE80")
	strip.emission_enabled = true
	strip.emission = Color("#F5CE80")
	strip.emission_energy_multiplier = 1.4
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("#F2EDE0")
	paper.roughness = 0.9
	var terra := StandardMaterial3D.new()
	terra.albedo_color = Color("#AD5F3D")
	terra.roughness = 0.6
	var mint := StandardMaterial3D.new()
	mint.albedo_color = Color("#A8C8AC")
	mint.roughness = 0.7
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color("#202B2B")
	ink.roughness = 0.5

	# Node origin = the counter island center at floor level (PENDANT_POS);
	# every surface below is offset from it. Surfaces 0-3 are the pendant and
	# the light strip; 4-7 are the clutter (clear of the desk bell at local
	# (-0.45, 1.04, 0) and the slip pad at (0.4, 1.04, 0.05), CounterStation).
	var am := ArrayMesh.new()
	# 0: pendant stem from the ceiling (world y 3.0) to the shade top (2.06).
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_box_mesh(Vector3(0.02, 0.96, 0.02)), Vector3(0, 2.52, 0)))
	am.surface_set_material(0, steel)
	# 1: cone shade (top radius 0) hanging over the counter (center y 1.98).
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_cyl_mesh(0.0, 0.30, 0.16), Vector3(0, 1.98, 0)))
	am.surface_set_material(1, steel)
	# 2: emissive bulb tucked under the shade mouth (center y 1.89).
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_sphere_mesh(0.05), Vector3(0, 1.89, 0)))
	am.surface_set_material(2, bulb)
	# 3: under-lip light strip at the counter's room-side face
	# (world z 2.215 = 2.55 - 0.335, y 0.955, just under the 1.0 top).
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_box_mesh(Vector3(1.2, 0.025, 0.02)), Vector3(0, 0.955, -0.335)))
	am.surface_set_material(3, strip)
	# 4: slip stack of order slips (counter top, world y 1.04 + ...).
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_box_mesh(Vector3(0.15, 0.04, 0.22)),
		Vector3(-0.12, CounterStation.TOP_Y + 0.02, -0.15)))
	am.surface_set_material(4, paper)
	# 5: tiny plant pot.
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_cyl_mesh(0.05, 0.04, 0.07),
		Vector3(0.14, CounterStation.TOP_Y + 0.035, 0.15)))
	am.surface_set_material(5, terra)
	# 6: the plant's foliage.
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_sphere_mesh(0.05),
		Vector3(0.14, CounterStation.TOP_Y + 0.10, 0.15)))
	am.surface_set_material(6, mint)
	# 7: card-reader box.
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _offset_arrays(
		_box_mesh(Vector3(0.10, 0.05, 0.14)),
		Vector3(0.14, CounterStation.TOP_Y + 0.025, -0.13)))
	am.surface_set_material(7, ink)

	var lamp := MeshInstance3D.new()
	lamp.name = "CounterDressingMesh"
	lamp.mesh = am
	dressing.add_child(lamp)

	_pendant_light = OmniLight3D.new()
	_pendant_light.name = "PendantLight"
	_pendant_light.position = Vector3(0, 1.78, 0)
	_pendant_light.light_color = Color("#FFD9A5")
	_pendant_light.omni_range = 3.0
	_pendant_light.light_energy = PENDANT_ENERGY
	_pendant_light.shadow_enabled = false
	dressing.add_child(_pendant_light)


## --- primitive helpers --------------------------------------------------------
## Primitive meshes come back centered on the origin; these translate their
## vertex arrays so several primitives can share one ArrayMesh surface set.
## Pure translation — normals and tangents carry over unchanged.

func _offset_arrays(src: PrimitiveMesh, offset: Vector3) -> Array:
	var arrays: Array = src.get_mesh_arrays()
	var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
	for i in range(verts.size()):
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	return m


func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m

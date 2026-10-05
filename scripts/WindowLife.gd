extends Node3D

## Window life (v034): birds and a delivery van living "outside" the
## back-wall window. Everything is built from primitives with unshaded
## materials (no external assets) and animated here in _process — Main only
## calls set_weather() / set_nightness(), both cheap and null-safe.
##
## Layering note: the window "view" is painted on the panes themselves (the
## day pane is an opaque emissive light box, and the night starfield pane
## goes nearly opaque at midnight), so nothing behind the glass at
## z <= -3.05 can ever be seen — the wall there backs onto the farm
## extension. Every shipped outside element (clouds, rain, frost, snow)
## therefore lives in the thin unshaded layer just in front of the panes,
## and so do the birds and the van. If the window ever becomes real
## transparent glass with a backdrop, flip BIRD_Z / VAN_Z to sit behind it.

const BIRD_COUNT := 3
## Visible glass: x 1.15..2.65, y 1.25..2.35, pane fronts at z=-2.85.
const BIRD_Z := -2.841
const VAN_Z := -2.842
const VAN_BASE_Y := 1.15
## Birds exit (and are considered gone) outside this band; the van crosses
## a slightly wider one so it slides fully past the frame.
const BIRD_X_MIN := 1.0
const BIRD_X_MAX := 2.8
const VAN_X_MIN := 0.8
const VAN_X_MAX := 3.0
const VAN_SPEED := 0.35
## Silhouette palettes: muted gray by day, near-black against the night
## sky; the headlight dot warms up and brightens after dark.
const BIRD_DAY := Color(0.30, 0.32, 0.37, 0.9)
const BIRD_NIGHT := Color(0.02, 0.02, 0.028, 0.95)
const VAN_DAY := Color(0.22, 0.24, 0.28, 1.0)
const VAN_NIGHT := Color(0.015, 0.015, 0.02, 1.0)
const LAMP_DAY := Color(0.5, 0.42, 0.28, 0.25)
const LAMP_NIGHT := Color(1.0, 0.84, 0.5, 0.95)

var _rng := RandomNumberGenerator.new()
var _weather := "calm"
var _nightness := 0.0
## Birds: nodes plus per-bird flight state. wait > 0 = seconds until the
## next appearance, wait == 0 = flying, wait < 0 = grounded by weather.
var _birds: Array[Node3D] = []
var _bird_dir: Array[float] = []
var _bird_speed: Array[float] = []
var _bird_wait: Array[float] = []
var _bird_base_y: Array[float] = []
var _bird_phase: Array[float] = []
var _side_flip := false
var _bird_mat: StandardMaterial3D
## Van: one box pair (body + cab) with a warm headlight dot on the leading
## corner; flips direction each pass.
var _van: Node3D
var _van_cab: MeshInstance3D
var _van_lamp: MeshInstance3D
var _van_dir := 1.0
var _van_flip := false
var _van_wait := 0.0
var _van_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	_build_birds()
	_build_van()
	_apply_look()


func _process(delta: float) -> void:
	_advance(delta)


## Deterministic heartbeat: steps the exact math _process runs, so tests
## can drive minutes of outside life instantly.
func _advance(seconds: float) -> void:
	_advance_birds(seconds)
	_advance_van(seconds)


## "humid" / "cold_snap" ground the birds — flights in progress finish,
## nothing new takes off — while the van runs in any weather. Anything
## else ("calm", "boom", ...) sends the birds back up.
func set_weather(id: String) -> void:
	_weather = id
	if _birds.is_empty():
		return
	var grounded := id == "humid" or id == "cold_snap"
	for i in range(_bird_wait.size()):
		if grounded and _bird_wait[i] > 0.0:
			# Still on the ground between flights: stay there, no respawn.
			_bird_wait[i] = -1.0
			_birds[i].visible = false
		elif not grounded and _bird_wait[i] < 0.0:
			_bird_wait[i] = _rng.randf_range(0.5, 2.5)


## n in 0..1 (0 = day, 1 = midnight): silhouettes darken toward near-black,
## the van's headlight brightens. Safe to call before the node is built.
func set_nightness(n: float) -> void:
	_nightness = clampf(n, 0.0, 1.0)
	_apply_look()


func _apply_look() -> void:
	if _bird_mat != null:
		_bird_mat.albedo_color = BIRD_DAY.lerp(BIRD_NIGHT, _nightness)
	if _van_mat != null:
		_van_mat.albedo_color = VAN_DAY.lerp(VAN_NIGHT, _nightness)
	if _lamp_mat != null:
		_lamp_mat.albedo_color = LAMP_DAY.lerp(LAMP_NIGHT, _nightness)


func _build_birds() -> void:
	_bird_mat = StandardMaterial3D.new()
	_bird_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bird_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bird_mat.albedo_color = BIRD_DAY
	# Two slim boxes canted into a shallow "M" read as a distant bird.
	var wing := BoxMesh.new()
	wing.size = Vector3(0.085, 0.018, 0.006)
	for i in range(BIRD_COUNT):
		var bird := Node3D.new()
		bird.name = "Bird%d" % i
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.mesh = wing
			w.material_override = _bird_mat
			w.position = Vector3(0.035 * side, 0.006, 0.0)
			w.rotation.z = 0.5 * side
			bird.add_child(w)
		add_child(bird)
		_birds.append(bird)
		_bird_dir.append(1.0)
		_bird_speed.append(0.4)
		_bird_wait.append(0.0)
		_bird_base_y.append(1.9)
		_bird_phase.append(0.0)
	# Staggered boot: two aloft mid-crossing, one still on the ground.
	_launch_bird(0, 1.45, 1.0, 0.42, 1.9)
	_launch_bird(1, 2.35, -1.0, 0.5, 1.72)
	_launch_bird(2, 1.05, 1.0, 0.45, 2.0)
	_bird_wait[2] = 3.5
	_birds[2].visible = false


func _launch_bird(i: int, x: float, dir: float, speed: float, y: float) -> void:
	_bird_dir[i] = dir
	_bird_speed[i] = speed
	_bird_wait[i] = 0.0
	_bird_base_y[i] = y
	_birds[i].visible = true
	_birds[i].position = Vector3(x, y, BIRD_Z)


func _spawn_bird(i: int) -> void:
	_side_flip = not _side_flip
	var dir := 1.0 if _side_flip else -1.0
	# Take off just outside the glass so the frame hides the pop-in.
	_launch_bird(i, 1.05 if dir > 0.0 else 2.75, dir,
		_rng.randf_range(0.3, 0.6), _rng.randf_range(1.6, 2.2))
	_bird_phase[i] = _rng.randf_range(0.0, TAU)


func _advance_birds(s: float) -> void:
	var grounded := _weather == "humid" or _weather == "cold_snap"
	for i in range(_birds.size()):
		var wait := _bird_wait[i]
		if wait < 0.0:
			continue  # grounded for the weather; set_weather reactivates
		if wait > 0.0:
			wait -= s
			if wait <= 0.0:
				if grounded:
					_bird_wait[i] = -1.0
					_birds[i].visible = false
				else:
					_spawn_bird(i)
			else:
				_bird_wait[i] = wait
			continue
		var bird := _birds[i]
		bird.position.x += _bird_dir[i] * _bird_speed[i] * s
		_bird_phase[i] += s * 7.0
		bird.position.y = _bird_base_y[i] + sin(_bird_phase[i]) * 0.025
		if (_bird_dir[i] > 0.0 and bird.position.x > BIRD_X_MAX) \
				or (_bird_dir[i] < 0.0 and bird.position.x < BIRD_X_MIN):
			bird.visible = false
			# Landed for a while — or, in bad weather, for the week.
			_bird_wait[i] = -1.0 if grounded else _rng.randf_range(5.0, 12.0)


func _build_van() -> void:
	_van_mat = StandardMaterial3D.new()
	_van_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_van_mat.albedo_color = VAN_DAY
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lamp_mat.albedo_color = LAMP_DAY
	_van = Node3D.new()
	_van.name = "DeliveryVan"
	add_child(_van)
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.9, 0.3, 0.016)
	body.mesh = body_box
	body.material_override = _van_mat
	body.position = Vector3(0.0, 0.15, 0.0)
	_van.add_child(body)
	_van_cab = MeshInstance3D.new()
	var cab_box := BoxMesh.new()
	cab_box.size = Vector3(0.3, 0.5, 0.014)
	_van_cab.mesh = cab_box
	_van_cab.material_override = _van_mat
	_van_cab.position = Vector3(0.29, 0.25, 0.0)
	_van.add_child(_van_cab)
	_van_lamp = MeshInstance3D.new()
	var lamp := SphereMesh.new()
	lamp.radius = 0.016
	lamp.height = 0.032
	_van_lamp.mesh = lamp
	_van_lamp.material_override = _lamp_mat
	_van_lamp.position = Vector3(0.47, 0.35, 0.012)
	_van.add_child(_van_lamp)
	_spawn_van(1.0)


func _spawn_van(dir: float) -> void:
	_van_dir = dir
	_van_wait = 0.0
	_van.visible = true
	_van.position = Vector3(VAN_X_MIN if dir > 0.0 else VAN_X_MAX,
		VAN_BASE_Y, VAN_Z)
	# Cab and headlight lead the way; they swap sides on the return pass.
	if _van_cab != null:
		_van_cab.position.x = 0.29 * dir
	if _van_lamp != null:
		_van_lamp.position.x = 0.47 * dir


func _advance_van(s: float) -> void:
	if _van == null:
		return
	if _van_wait > 0.0:
		_van_wait -= s
		if _van_wait <= 0.0:
			_van_flip = not _van_flip
			_spawn_van(-1.0 if _van_flip else 1.0)
		return
	_van.position.x += _van_dir * VAN_SPEED * s
	if (_van_dir > 0.0 and _van.position.x > VAN_X_MAX) \
			or (_van_dir < 0.0 and _van.position.x < VAN_X_MIN):
		_van.visible = false
		_van_wait = _rng.randf_range(45.0, 75.0)

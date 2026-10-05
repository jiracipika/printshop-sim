extends SceneTree

## v034 — "Window life": birds cross the back-wall glass and a delivery van
## rumbles past below the sill; weather grounds the birds, nightness darkens
## the silhouettes and lights the van's headlamp. Run:
## timeout 180 godot --headless --path . -s tests/v034_windowlife_test.gd
##
## Drives WindowLife directly through its deterministic _advance() —
## Main is never instantiated here.

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
	var wl = load("res://scripts/WindowLife.gd").new()
	root.add_child(wl)
	await physics_frame
	_test_build(wl)
	_test_birds_move(wl)
	_test_bird_respawn(wl)
	_test_weather(wl)
	_test_nightness(wl)
	_test_van(wl)
	wl.queue_free()
	await physics_frame
	_test_null_safe()
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_build(wl) -> void:
	_ok(wl._birds.size() == 3, "three birds built")
	var wings_ok := true
	for i in range(wl._birds.size()):
		if wl._birds[i].get_child_count() != 2:
			wings_ok = false
	_ok(wings_ok, "each bird is a two-wing silhouette")
	_ok(wl._van != null and wl._van.get_child_count() == 3,
		"van built with body, cab and headlamp")
	_ok(wl._van_lamp != null, "warm headlight dot rides the van")
	var aloft := 0
	for i in range(wl._birds.size()):
		if wl._birds[i].visible and wl._bird_wait[i] <= 0.0:
			aloft += 1
	_ok(aloft == 2, "two birds airborne at boot, one still delayed")
	_ok(absf(wl._van.position.y - 1.15) < 0.01,
		"van base sits below the sill line")
	_ok(wl._van.position.x > 0.7 and wl._van.position.x < 3.1,
		"van starts at the band edge")
	var z_ok := true
	for i in range(wl._birds.size()):
		if absf(wl._birds[i].position.z - wl.BIRD_Z) > 0.001:
			z_ok = false
	_ok(z_ok and absf(wl._van.position.z - wl.VAN_Z) < 0.001,
		"birds and van live on the window layer")


func _test_birds_move(wl) -> void:
	# Bird 0 boots airborne at x=1.45, +x, speed 0.42.
	var b0: Node3D = wl._birds[0]
	var x0: float = b0.position.x
	var y0: float = b0.position.y
	wl._advance(1.0)
	var dx: float = b0.position.x - x0
	_ok(absf(dx - 0.42) < 0.01, "bird crosses at its own speed")
	_ok(dx > 0.0, "bird flies the direction it faces")
	_ok(absf(b0.position.y - y0) < 0.1,
		"bird bobs gently around its flight height")


func _test_bird_respawn(wl) -> void:
	# Fast-forward bird 0 out of the band, then through its delay.
	wl._bird_wait[0] = 0.0
	wl._bird_dir[0] = 1.0
	wl._bird_speed[0] = 1.0
	wl._birds[0].visible = true
	wl._birds[0].position = Vector3(2.5, 1.9, wl.BIRD_Z)
	wl._advance(0.5)
	_ok(not wl._birds[0].visible, "bird exits the window band and lands")
	_ok(wl._bird_wait[0] >= 5.0 and wl._bird_wait[0] <= 12.0,
		"respawn delay is 5..12 s")
	wl._advance(wl._bird_wait[0] + 0.05)
	_ok(wl._birds[0].visible and wl._bird_wait[0] <= 0.0,
		"bird takes off again after the delay")
	var p: Vector3 = wl._birds[0].position
	_ok(p.x >= 1.0 and p.x <= 2.8 and p.y >= 1.6 and p.y <= 2.2,
		"relaunched bird re-enters inside its band")


func _test_weather(wl) -> void:
	# All three aloft, creeping so none leaves the band on its own.
	for i in range(wl._birds.size()):
		wl._bird_wait[i] = 0.0
		wl._bird_speed[i] = 0.1
		wl._birds[i].visible = true
		wl._birds[i].position = Vector3(1.9, 1.9, wl.BIRD_Z)
	wl.set_weather("humid")
	wl._advance(2.0)
	var mid := true
	for i in range(wl._birds.size()):
		if not wl._birds[i].visible:
			mid = false
	_ok(mid, "grounded birds finish their crossing")
	wl._bird_speed[0] = 5.0
	wl._advance(1.0)
	_ok(not wl._birds[0].visible and wl._bird_wait[0] < 0.0,
		"a bird leaving in the rain never respawns")
	wl._advance(30.0)
	_ok(not wl._birds[0].visible, "no takeoff even past the longest delay")
	# The van ignores the weather entirely.
	wl._van_wait = 0.0
	wl._van_dir = 1.0
	wl._van.visible = true
	wl._van.position.x = 0.8
	wl._advance(3.0)
	_ok(wl._van.visible and wl._van.position.x > 1.5,
		"van keeps running through humid weather")
	# Calm skies: grounded birds rejoin on their own.
	wl.set_weather("calm")
	wl._advance(3.0)
	_ok(wl._birds[0].visible and wl._bird_wait[0] <= 0.0,
		"calm weather sends the birds back up")


func _test_nightness(wl) -> void:
	wl.set_nightness(0.0)
	var day_bird: Color = wl._bird_mat.albedo_color
	var day_lamp: Color = wl._lamp_mat.albedo_color
	wl.set_nightness(1.0)
	var night_bird: Color = wl._bird_mat.albedo_color
	var night_lamp: Color = wl._lamp_mat.albedo_color
	_ok(night_bird.r < day_bird.r and night_bird.g < day_bird.g,
		"midnight darkens the bird silhouettes")
	_ok(night_lamp.r > day_lamp.r and night_lamp.a > day_lamp.a,
		"midnight brightens the van's headlamp")
	wl.set_nightness(7.0)
	_ok(wl._nightness == 1.0, "nightness clamps at 1")
	wl.set_nightness(-3.0)
	_ok(wl._nightness == 0.0, "nightness clamps at 0")
	wl.set_nightness(0.5)
	_ok(wl._bird_mat.albedo_color.r > night_bird.r \
		and wl._bird_mat.albedo_color.r < day_bird.r,
		"twilight sits between day and midnight")


func _test_van(wl) -> void:
	wl._van_wait = 0.0
	wl._van_dir = 1.0
	wl._van.visible = true
	wl._van.position = Vector3(0.8, 1.15, wl.VAN_Z)
	var x0: float = wl._van.position.x
	wl._advance(0.5)
	_ok(wl._van.position.x > x0, "van rolls across the band")
	# Drive the whole crossing in half-second steps (~6.3 s total).
	var t := 0.5
	var crossed := false
	while t < 20.0:
		wl._advance(0.5)
		t += 0.5
		if not wl._van.visible:
			crossed = true
			break
	_ok(crossed and t >= 5.5 and t <= 7.5,
		"van clears the window in about six seconds")
	_ok(wl._van_wait >= 45.0 and wl._van_wait <= 75.0,
		"van stays away for 45..75 s")
	wl._advance(wl._van_wait + 0.05)
	_ok(wl._van.visible and wl._van.position.x > 2.8,
		"van returns on the next pass after the delay")
	_ok(absf(wl._van_dir + 1.0) < 0.01, "the return pass flips direction")


func _test_null_safe() -> void:
	# The public API must survive being called before _ready builds anything.
	var bare = load("res://scripts/WindowLife.gd").new()
	bare.set_weather("humid")
	bare.set_nightness(0.7)
	bare._advance(10.0)
	_ok(true, "API calls before build never crash")
	bare.free()

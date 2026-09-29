extends SceneTree

## Task 12 — art pass: procedural textures, environment, props, reticle,
## and synthesized SFX streams. Run:
##   timeout 60 godot --headless --path . -s tests/shop_art_test.gd

var checks := 0
var failures := 0


func _ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("ok %d: %s" % [checks, label])
	else:
		failures += 1
		printerr("FAIL %d: %s" % [checks, label])


func _texture_ok(t: ImageTexture, label: String) -> void:
	_ok(t != null, "%s texture generated" % label)
	if t == null:
		return
	var img: Image = t.get_image()
	_ok(img.get_width() == 256 and img.get_height() == 256, "%s texture is 256x256" % label)
	# Non-flat: sample a grid, require at least two distinct colors.
	var seen: Dictionary = {}
	for y in range(0, 256, 32):
		for x in range(0, 256, 32):
			seen[img.get_pixel(x, y).to_html()] = true
	_ok(seen.size() > 1, "%s texture is not flat" % label)


func _init() -> void:
	root.ready.connect(_run)


func _run() -> void:
	_test_textures()
	await _test_scene()
	_finish(1 if failures > 0 else 0)


func _test_textures() -> void:
	_texture_ok(ShopArt.plaster(Color("#738771")), "plaster")
	_texture_ok(ShopArt.wood(Color("#C3A076")), "wood")
	_texture_ok(ShopArt.floor_tiles(Color("#AD5F3D")), "floor_tiles")
	_texture_ok(ShopArt.metal(Color("#202B2B")), "metal")
	_texture_ok(ShopArt.cardboard(Color("#B08D57")), "cardboard")
	_texture_ok(ShopArt.poster(Color("#EEE5D3"), Color("#DA623A"), []), "poster")
	_texture_ok(ShopArt.weave(Color("#8A4A34")), "weave")
	# Cached: second call returns the same instance.
	_ok(ShopArt.plaster(Color("#738771")) == ShopArt.plaster(Color("#738771")),
		"texture cache returns the same instance")

	# SFX: every sound builds a stream; the printer hum and music loop.
	var lengths: Dictionary = Sfx.stream_lengths()
	_ok(lengths.size() == 11, "all eleven sfx streams build")
	for key in lengths:
		_ok(float(lengths[key]) > 0.0, "sfx %s has positive length" % key)
	var hum: AudioStreamWAV = Sfx.stream("hum")
	_ok(hum.loop_mode == AudioStreamWAV.LOOP_FORWARD, "printer hum loops")
	var music: AudioStreamWAV = Sfx.stream("music")
	_ok(music != null and music.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"music stream loops")


func _test_scene() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	# WorldEnvironment with a procedural sky.
	var we: WorldEnvironment = null
	for child in main.get_children():
		if child is WorldEnvironment:
			we = child
	_ok(we != null, "scene has a WorldEnvironment")
	if we != null:
		_ok(we.environment.background_mode == Environment.BG_SKY, "sky background enabled")
		_ok(we.environment.fog_enabled, "gentle fog enabled")

	# Palette materials carry generated textures.
	var world: Dictionary = main.world
	_ok(world.has("sage") and world.has("honey") and world.has("steel")
		and world.has("terracotta") and world.has("floor"), "palette dictionary intact")
	for key in ["sage", "honey", "steel", "floor"]:
		var mat: StandardMaterial3D = world[key]
		_ok(mat.albedo_texture != null, "%s material is textured" % key)

	# Props: shelf spools, rug, posters, clock, crates, plant, fixtures.
	var props: Array = main.get_tree().get_nodes_in_group("props")
	_ok(props.size() >= 12, "props populated (got %d)" % props.size())
	var posters := 0
	var fixtures := 0
	var clock_found := false
	for p in props:
		if p is Label3D:
			posters += 1
		if p is MeshInstance3D and p.mesh is BoxMesh \
				and p.material_override != null \
				and p.material_override.emission_enabled:
			fixtures += 1
	for child in main.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("Clock.gd"):
			clock_found = true
	_ok(posters >= 2, "poster captions present")
	_ok(fixtures >= 2, "emissive ceiling fixtures present")
	_ok(clock_found, "wall clock exists")

	# Packing station readable as the delivery point.
	var stations: Array = main.get_tree().get_nodes_in_group("stations")
	var packing_found := false
	for s in stations:
		if s.get_meta("station_kind", "") == "packing":
			packing_found = true
	_ok(packing_found, "packing station present in world")

	# Reticle + audio exist.
	_ok(main._reticle != null and not main._reticle.visible, "reticle exists, hidden while paused")
	_ok(main.sfx != null, "sfx player node exists")
	_ok(main._hum != null and main._hum.stream != null, "printer hum player exists")
	_ok(AudioServer.get_bus_index("SFX") != -1, "SFX bus exists")
	_ok(main._hud != null and main._hud.get_node_or_null("StatusCard") != null,
		"status card panel exists")

	main.queue_free()
	await physics_frame


func _finish(code: int) -> void:
	print("---")
	print("checks=%d failures=%d" % [checks, failures])
	quit(code)

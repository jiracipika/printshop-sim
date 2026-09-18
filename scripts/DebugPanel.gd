extends CanvasLayer

# Dev-only debug panel (F3 toggles). Not exposed in public releases.

var _labels: Dictionary = {}

func _ready() -> void:
	layer = 100
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left = -360.0
	root.offset_top = 8.0
	root.offset_right = -8.0
	root.offset_bottom = 320.0
	root.add_theme_font_size_override("font_size", 13)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var title := Label.new()
	title.name = "Title"
	title.text = Version.label()
	root.add_child(title)

	for key in ["fps", "frametime", "printers", "jobs", "jobstate", "risks", "support", "adhesion", "stability", "material", "esttime", "simtime"]:
		var l := Label.new()
		l.name = key
		l.text = "%s: -" % key
		root.add_child(l)
		_labels[key] = l

	var hint := Label.new()
	hint.text = "F3: panel  LMB: grab  E: interact"
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	root.add_child(hint)
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible

func _process(_delta: float) -> void:
	if not visible:
		return
	_labels.fps.text = "fps: %d" % Engine.get_frames_per_second()
	_labels.frametime.text = "frame: %.2f ms" % (1000.0 / maxf(1.0, Engine.get_frames_per_second()))
	_labels.printers.text = "printers: %d" % get_tree().get_nodes_in_group("printers").size()
	var sim: Node = get_tree().get_first_node_in_group("print_sim")
	var job: Node = get_tree().get_first_node_in_group("job_board")
	if sim == null or job == null:
		return
	_labels.jobs.text = "jobs: %d" % job.get_available_count()
	_labels.jobstate.text = "job: %s" % sim.get_state_name()
	_labels.risks.text = "risks: %s" % str(sim.current_risks())
	_labels.support.text = "support: %.2f" % sim.support_score()
	_labels.adhesion.text = "adhesion: %.2f" % sim.bed_adhesion_score()
	_labels.stability.text = "stability: %.2f" % sim.stability_score()
	_labels.material.text = "material: %d g" % sim.material_used_g()
	_labels.esttime.text = "est: %.0f s" % sim.estimated_print_time_s()
	_labels.simtime.text = "sim t: %.0f / %.0f s" % [sim.elapsed_sim_time_s(), sim.estimated_print_time_s()]

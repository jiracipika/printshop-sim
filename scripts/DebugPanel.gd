class_name DebugPanel
extends CanvasLayer

## Menus slice — dev-only debug overlay, F3 toggled, hidden by default.
## Gate: runtime bool (web exports are release builds, panel stays inert
## there). Editor and dev desktop runs are debug builds and show it.
## Actions use existing sim/ledger/save APIs only; each logs one panel line.

## Gate: runtime bool (not const — OS.is_debug_build() isn't a constant
## expression). Web exports are release builds, so the panel stays compiled-in
## but hidden and inert there; editor/dev desktop runs show it.
var DEBUG_PANEL: bool = OS.is_debug_build()

const COLOR_STEEL := Color("#202B2B")
const COLOR_PAPER := Color("#EEE5D3")
const COLOR_MINT := Color("#A8C8AC")
const COLOR_TERRA := Color("#DA623A")

var main: Node = null            # Main (set by Main._ready)
var orientation_in_use := "upright"
var _labels: Dictionary = {}
var _log: Label
var _log_lines: Array[String] = []

func _ready() -> void:
	layer = 100
	visible = false  # hidden by default, even in debug builds
	if not DEBUG_PANEL:
		set_process_unhandled_input(false)
		return
	_build()

func _build() -> void:
	var root := PanelContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left = -400.0
	root.offset_top = 8.0
	root.offset_right = -8.0
	root.offset_bottom = 460.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COLOR_STEEL, 0.95)
	sb.border_color = COLOR_MINT
	sb.set_border_width_all(1)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)

	var title := Label.new()
	title.name = "Version"
	title.text = "DEBUG — %s" % Version.label()
	title.add_theme_color_override("font_color", COLOR_MINT)
	title.add_theme_font_size_override("font_size", 12)
	v.add_child(title)
	_labels["version"] = title

	for key in ["fps", "frame", "printers", "job", "orientation", "risk", "support",
			"adhesion", "stability", "material", "esttime", "balance", "contract",
			"pack", "save"]:
		var l := Label.new()
		l.name = key
		l.text = "%s: -" % key
		l.add_theme_font_size_override("font_size", 12)
		v.add_child(l)
		_labels[key] = l

	_log = Label.new()
	_log.name = "Log"
	_log.text = ""
	_log.add_theme_color_override("font_color", COLOR_TERRA)
	_log.add_theme_font_size_override("font_size", 12)
	v.add_child(_log)

	var hint := Label.new()
	hint.text = "F3 panel  [1]spawn [2]fail [3]skip [4]funds [5]clear save [6]reset"
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	v.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = (event as InputEventKey).physical_keycode
		# The F3 toggle must work while hidden (that is the point of a toggle);
		# all other panel keys stay gated behind visibility + the debug gate.
		if key == KEY_F3:
			if DEBUG_PANEL:
				visible = not visible
				get_viewport().set_input_as_handled()
			return
	if not visible:
		return  # hidden panel never consumes gameplay input
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = (event as InputEventKey).physical_keycode
		match key:
			KEY_1:
				_action_spawn()
			KEY_2:
				_action_seed_failure()
			KEY_3:
				_action_skip()
			KEY_4:
				_action_funds()
			KEY_5:
				_action_clear_save()
			KEY_6:
				_action_reset()

func label_text(key: String) -> String:
	if not DEBUG_PANEL or not _labels.has(key):
		return ""
	return (_labels[key] as Label).text

func action_log() -> Array[String]:
	return _log_lines

func _log_line(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 8:
		_log_lines = _log_lines.slice(_log_lines.size() - 8)
	if _log != null:
		_log.text = "\n".join(_log_lines)

func _process(_delta: float) -> void:
	if not visible:
		return
	var fps := Engine.get_frames_per_second()
	label_text_set("fps", "fps: %d" % fps)
	label_text_set("frame", "frame: %.2f ms" % (1000.0 / maxf(1.0, fps)))
	label_text_set("printers", "printers: %d" % get_tree().get_nodes_in_group("printers").size())
	if main == null:
		return
	var sim: PrintSim = main.sim
	var ledger: Ledger = main.ledger
	label_text_set("job", "job: %s [%s]" % [sim.job_id, sim.get_state_name()])
	label_text_set("orientation", "orientation: %s" % orientation_in_use)
	label_text_set("risk", "risks: support %.2f / adhesion %.2f / stability %.2f" % [
		sim.support_need, sim.adhesion_risk, sim.stability_risk])
	label_text_set("support", "support score: %.2f" % sim.support_score())
	label_text_set("adhesion", "adhesion score: %.2f" % sim.bed_adhesion_score())
	label_text_set("stability", "stability score: %.2f" % sim.stability_score())
	label_text_set("material", "material: %d g" % sim.material_used_g())
	label_text_set("esttime", "est print time: %.0f s" % sim.estimated_print_time_s())
	label_text_set("balance", "balance: $%d.%02d" % [ledger.balance() / 100, absi(ledger.balance()) % 100])
	var c: Contract = main.active_contract
	label_text_set("contract", "contract: %s" % ("none" if c == null
		else "%s [%s]" % [c.id, Contract.state_name(c.state)]))
	label_text_set("pack", "last pack grade: %s" % main.last_pack_grade)
	label_text_set("save", "save: %s" % str(main.save_status_line))

## --- actions (existing APIs only) -----------------------------------------

## [1] Spawn test print: highest-risk fixture through Main's real accept path.
func _action_spawn() -> void:
	var worst: Contract = null
	var worst_score := -1.0
	for s in main.job_board.available_summaries():
		var score := float((s.risk_flags as Array).size()) * 10.0 + float(s.difficulty)
		if score > worst_score:
			worst_score = score
			# Re-fetch the real Contract from the queue front by id.
			worst = _contract_by_id(s.id)
	if worst == null:
		_log_line("spawn: no jobs available")
		return
	# Drive the same accept path the printer uses (accepts the FIRST queued
	# job; the fixture queue rotates deterministically so the highest-risk
	# fixture arrives within one cycle — accept what is actually offered).
	main.sim.failure_seeded = main.sim.failure_seeded  # no-op; state kept
	var ok: bool = main.debug_spawn_test_print()
	_log_line("spawn: %s" % ("started %s" % main.sim.job_id if ok else "refused"))

## [2] Force next failure.
func _action_seed_failure() -> void:
	main.sim.failure_seeded = true
	_log_line("failure seeded: next print fails mid-print")

## [3] Skip print time: tick the sim to completion.
func _action_skip() -> void:
	if not main.sim.is_running():
		_log_line("skip: no print running")
		return
	var steps := 0
	while main.sim.is_running() and steps < 100000:
		main.sim.tick(1.0 / PrintSim.TICK_HZ)
		steps += 1
	_log_line("skip: print finished in %d ticks -> %s" % [steps, main.sim.get_state_name()])

## [4] Add $10 test funds.
func _action_funds() -> void:
	main.ledger.credit(1000, "debug funds")
	_log_line("funds: credited $10.00 (debug funds)")

## [5] Clear save.
func _action_clear_save() -> void:
	var ok: bool = BrowserSave.clear()
	_log_line("clear save: %s" % ("ok" if ok else "failed"))

## [6] Reset workshop.
func _action_reset() -> void:
	_log_line("reset: reloading scene")
	get_tree().reload_current_scene()

func _contract_by_id(id: String) -> Contract:
	for c in main.job_board._queue:
		if c.id == id:
			return c
	return null

func label_text_set(key: String, t: String) -> void:
	if _labels.has(key):
		(_labels[key] as Label).text = t

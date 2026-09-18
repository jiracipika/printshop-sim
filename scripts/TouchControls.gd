class_name TouchControls
extends CanvasLayer

## Reusable mobile touch overlay: left movement stick, right-side swipe look,
## Interact and Pause/Resume buttons. Sits on its own CanvasLayer above the
## HUD and is driven purely by InputEventScreenTouch / InputEventScreenDrag
## finger indices — no pointer lock is ever requested on the touch path.
##
## Integration (Main.gd):
##   touch_controls = TouchControls.new()
##   touch_controls.interact_pressed.connect(_on_touch_interact)
##   touch_controls.pause_requested.connect(_on_touch_pause)
##   touch_controls.resume_requested.connect(_on_touch_resume)
##
## API:
##   force_enabled: bool        — test-only override; normally visibility follows
##                                DisplayServer.is_touchscreen_available().
##   effective_enabled() -> bool
##   set_motion_enabled(on)     — Main toggles on resume/pause; turning it off
##                                clears every finger, the stick axis and any
##                                pending look delta.
##   get_move_axis() -> Vector2 — stick axis, deadzone-applied, clamped to a
##                                unit vector. Up (negative y) is forward.
##   consume_look_delta() -> Vector2 — accumulated drag delta since last call.
##   stick_center() / stick_region() / look_rect() / interact_rect() /
##   pause_rect()               — layout queries (used by tests and hit-testing).
##   layout_rects(...)          — pure layout function, safe-area insets in.
##   active_fingers() -> int    — number of owned fingers (0..2).
##
## Signals:
##   interact_pressed           — Interact button tapped (Main gates on state).
##   pause_requested            — Pause button tapped while motion is enabled.
##   resume_requested           — Pause/Resume button tapped while paused.
##                                Resume therefore always originates from a
##                                real user touch (a gesture).

signal interact_pressed
signal pause_requested
signal resume_requested

const STICK_RADIUS := 70.0
const STICK_DEADZONE := 0.18
const MARGIN := 24.0
const INTERACT_SIZE := Vector2(96, 96)
const PAUSE_SIZE := Vector2(72, 48)

## Test-only override: force the overlay on even without a touchscreen.
## Visibility always reflects effective_enabled() — updated here and at ready.
var force_enabled := false:
	set(value):
		force_enabled = value
		_apply_visibility()

var _motion_enabled := false
var _move_finger := -1
var _look_finger := -1
var _stick_center := Vector2.ZERO
var _stick_offset := Vector2.ZERO
var _pending_look := Vector2.ZERO

var _stick_region := Rect2()
var _look_rect := Rect2()
var _interact_rect := Rect2()
var _pause_rect := Rect2()

var _stick_base: Panel
var _stick_knob: Panel
var _interact_panel: Panel
var _pause_panel: Panel
var _pause_label: Label

func _ready() -> void:
	layer = 3
	_build_visuals()
	# Sync the Pause/Resume label to the initial (paused) motion state so the
	# button reads "Resume" at boot, matching the boot-paused state.
	set_motion_enabled(_motion_enabled)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_apply_visibility()

func _apply_visibility() -> void:
	visible = effective_enabled()

func effective_enabled() -> bool:
	if force_enabled:
		return true
	return DisplayServer.is_touchscreen_available()

## --- layout ---------------------------------------------------------------

## Pure layout math: returns every hit region for a viewport size and
## safe-area insets (left/top/right/bottom). All touch targets >= 48 px.
func layout_rects(for_size: Vector2, inset_l: float, inset_t: float,
		inset_r: float, inset_b: float) -> Dictionary:
	var stick_center := Vector2(
		inset_l + MARGIN + STICK_RADIUS,
		for_size.y - inset_b - MARGIN - STICK_RADIUS)
	var grab := STICK_RADIUS * 3.2
	var stick_region := Rect2(stick_center - Vector2.ONE * grab / 2.0, Vector2.ONE * grab)
	var interact := Rect2(
		Vector2(for_size.x - inset_r - MARGIN - INTERACT_SIZE.x,
			for_size.y - inset_b - MARGIN - INTERACT_SIZE.y),
		INTERACT_SIZE)
	var pause := Rect2(
		Vector2(for_size.x - inset_r - MARGIN - PAUSE_SIZE.x, inset_t + MARGIN),
		PAUSE_SIZE)
	var look := Rect2(
		Vector2(for_size.x * 0.45, inset_t),
		Vector2(for_size.x * 0.55, for_size.y))
	return {
		"stick_center": stick_center,
		"stick_region": stick_region,
		"interact": interact,
		"pause": pause,
		"look": look,
	}

func _relayout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var inset_l := clampf(safe.position.x, 0.0, win.x)
	var inset_t := clampf(safe.position.y, 0.0, win.y)
	var inset_r := clampf(win.x - safe.end.x, 0.0, win.x)
	var inset_b := clampf(win.y - safe.end.y, 0.0, win.y)
	var r := layout_rects(vs, inset_l, inset_t, inset_r, inset_b)
	_stick_center = r.stick_center
	_stick_region = r.stick_region
	_interact_rect = r.interact
	_pause_rect = r.pause
	_look_rect = r.look

	if _stick_base != null:
		_stick_base.position = _stick_center - Vector2.ONE * STICK_RADIUS
		_stick_knob.position = _stick_center - _stick_knob.size / 2.0
		_interact_panel.position = _interact_rect.position
		_interact_panel.size = _interact_rect.size
		_pause_panel.position = _pause_rect.position
		_pause_panel.size = _pause_rect.size

## --- visuals --------------------------------------------------------------

func _build_visuals() -> void:
	_stick_base = _make_panel(Vector2.ONE * (STICK_RADIUS * 2.0), int(STICK_RADIUS),
		Color(0.1, 0.12, 0.12, 0.35))
	add_child(_stick_base)
	_stick_knob = _make_panel(Vector2(56, 56), 28, Color(0.85, 0.85, 0.9, 0.5))
	add_child(_stick_knob)

	_interact_panel = _make_panel(INTERACT_SIZE, 20, Color(0.85, 0.39, 0.23, 0.55))
	var ilabel := Label.new()
	ilabel.text = "Interact"
	ilabel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ilabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ilabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ilabel.add_theme_font_size_override("font_size", 16)
	ilabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.add_child(ilabel)
	add_child(_interact_panel)

	_pause_panel = _make_panel(PAUSE_SIZE, 12, Color(0.13, 0.17, 0.17, 0.55))
	_pause_label = Label.new()
	_pause_label.text = "Pause"
	_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 15)
	_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_panel.add_child(_pause_label)
	add_child(_pause_panel)

func _make_panel(size: Vector2, radius: int, bg: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## --- state ----------------------------------------------------------------

## Main calls this on resume (true) and pause/focus-loss (false). Turning
## motion off releases every finger and clears the axis and pending look.
func set_motion_enabled(on: bool) -> void:
	_motion_enabled = on
	if _pause_label != null:
		_pause_label.text = "Pause" if on else "Resume"
	if not on:
		clear_all_fingers()

func is_motion_enabled() -> bool:
	return _motion_enabled

## Current Pause/Resume button text (test accessor).
func pause_label_text() -> String:
	return _pause_label.text if _pause_label != null else ""

func clear_all_fingers() -> void:
	_move_finger = -1
	_look_finger = -1
	_stick_offset = Vector2.ZERO
	_pending_look = Vector2.ZERO
	if _stick_knob != null and _stick_base != null:
		_stick_knob.position = _stick_center - _stick_knob.size / 2.0

func active_fingers() -> int:
	var n := 0
	if _move_finger != -1:
		n += 1
	if _look_finger != -1:
		n += 1
	return n

## Stick axis with deadzone applied and clamped to unit length.
## Up (negative y) means forward.
func get_move_axis() -> Vector2:
	if _move_finger == -1:
		return Vector2.ZERO
	var axis := _stick_offset / STICK_RADIUS
	if axis.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return axis.limit_length(1.0)

## Accumulated look drag since the previous call; one-shot consumption.
func consume_look_delta() -> Vector2:
	var v := _pending_look
	_pending_look = Vector2.ZERO
	return v

func stick_center() -> Vector2:
	return _stick_center

func stick_region() -> Rect2:
	return _stick_region

func look_rect() -> Rect2:
	return _look_rect

func interact_rect() -> Rect2:
	return _interact_rect

func pause_rect() -> Rect2:
	return _pause_rect

## --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not effective_enabled():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_handle_touch(t.index, t.position, t.pressed, t.canceled)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_handle_drag(d.index, d.position, d.relative)
		get_viewport().set_input_as_handled()

func _handle_touch(index: int, pos: Vector2, pressed: bool, canceled: bool) -> void:
	if canceled:
		# Cancel releases ownership of whatever this finger held.
		if index == _move_finger:
			_move_finger = -1
			_stick_offset = Vector2.ZERO
			_reset_knob()
		elif index == _look_finger:
			_look_finger = -1
		return
	if not pressed:
		if index == _move_finger:
			_move_finger = -1
			_stick_offset = Vector2.ZERO
			_reset_knob()
		elif index == _look_finger:
			_look_finger = -1
		return
	# Press: buttons win first so UI touches never start look or motion.
	if _interact_rect.has_point(pos):
		interact_pressed.emit()
		return
	if _pause_rect.has_point(pos):
		if _motion_enabled:
			pause_requested.emit()
		else:
			resume_requested.emit()
		return
	if not _motion_enabled:
		return
	if _move_finger == -1 and _stick_region.has_point(pos):
		_move_finger = index
		_update_stick(pos)
		return
	if _look_finger == -1 and _look_rect.has_point(pos):
		_look_finger = index
		return
	# Else: third (or further) finger — deliberately ignored so it can not
	# hijack movement or look ownership.

func _handle_drag(index: int, pos: Vector2, rel: Vector2) -> void:
	if index == _move_finger:
		_update_stick(pos)
	elif index == _look_finger:
		_pending_look += rel

func _update_stick(pos: Vector2) -> void:
	_stick_offset = (pos - _stick_center).limit_length(STICK_RADIUS)
	if _stick_knob != null:
		_stick_knob.position = _stick_center + _stick_offset - _stick_knob.size / 2.0

func _reset_knob() -> void:
	if _stick_knob != null:
		_stick_knob.position = _stick_center - _stick_knob.size / 2.0

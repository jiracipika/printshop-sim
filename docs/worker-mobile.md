# Worker checkpoint — mobile touch controls (GLM slice)

Date: 2026-09-18. Bounded task per docs/GLM-MOBILE-SLICE.md. No git mutations,
no deployment. All prior uncommitted room/pause work preserved.

## Files changed (exact)
- scripts/TouchControls.gd — NEW. Reusable TouchControls CanvasLayer.
  Fix (2026-09-18): `_ready` no longer hard-sets `visible = false`; visibility
  is applied from `effective_enabled()` at ready and via the `force_enabled`
  setter so the overlay is actually visible on touchscreen devices. Initial
  Pause/Resume label synced to `_motion_enabled` (false → "Resume" at boot).
  Added `pause_label_text()` test accessor.
- scripts/Main.gd — touch integration (overlay wiring, touch pause/resume/
  interact handlers, touch move axis + look folding, focus-loss clearing,
  shared drop_motion_inputs(), _try_interact gating widened to accept the
  mobile gameplay-active path). Minimal prompt fix (2026-09-18): startup
  prompt reads "Tap Resume to play" when touch is effective (mobile boots
  paused with no pointer-lock click), "Click to play" otherwise.
- tests/touch_controls_test.gd — NEW. Behavioral RED/GREEN headless gate.
- scripts/TouchControls.gd.uid, tests/touch_controls_test.gd.uid — auto UID files.
- docs/worker-mobile.md — this checkpoint.
- web_shell/index.html — NOT modified: already has `touch-action: none` on the
  canvas and `viewport-fit=cover` viewport meta, which is what mobile needs.

## TouchControls API (documented)
- Signals: `interact_pressed`, `pause_requested`, `resume_requested`
  (resume only ever emitted from a real touch = user gesture).
- `force_enabled: bool` — test-only override; normally visibility/gating
  follows `DisplayServer.is_touchscreen_available()`.
- `effective_enabled()`, `set_motion_enabled(on)` (off clears all fingers,
  axis and pending look), `is_motion_enabled()`, `clear_all_fingers()`,
  `active_fingers()`.
- `get_move_axis() -> Vector2` — deadzone-applied (0.18), clamped to unit
  length, up (−y) = forward.
- `consume_look_delta() -> Vector2` — one-shot accumulated drag delta.
- Layout queries: `stick_center()`, `stick_region()`, `look_rect()`,
  `interact_rect()`, `pause_rect()`; pure `layout_rects(size, insets)`
  (safe-area aware, all targets >= 48px, Interact 96px, Pause 72x48).
- Finger model: InputEventScreenTouch/Drag index ownership; finger 0 in stick
  region = move, independent finger in right 55% = look, buttons win first so
  UI touches never start look/motion, third+ fingers deliberately ignored,
  cancel/release clears that finger's axis or look accumulation.

## Main integration notes
- Mobile gameplay-active = `not paused and touch_controls.is_motion_enabled()`;
  desktop gameplay-active = `not paused and get_mouse_locked()`. Separate states,
  `captured` untouched on the touch path — mobile never requests pointer lock.
- Pause (button or Esc) and NOTIFICATION_APPLICATION_FOCUS_OUT clear all touch
  fingers/axes; resume requires a tap on the Pause/Resume button.
- `_try_interact` now passes for desktop locked OR mobile motion-enabled, and
  still blocks while paused (input_pause_test re-verified GREEN).
- Touch look: `yaw -= dx * get_touch_look_sens()`, pitch clamped to ±1.4
  (same bounds as desktop), sensitivity scaled by viewport height.

## Verification (actual evidence)
Commands (Python subprocess.run(timeout=60) pattern per tools/run_one_test.py;
each run exit code captured, output scanned for "SCRIPT ERROR"/"Parse Error"):
- `godot --headless --path . --import --quit` → exit 0, scan clean.
- `godot --headless --path . -s tests/touch_controls_test.gd` → exit 0,
  "44 checks — ALL PASS", scan clean. Covers: overlay attached to real Main
  scene, hidden on desktop, **visibility follows effective_enabled() at ready
  and on every force_enabled change (desktop hidden / forced-touch visible /
  override cleared hides again)**, **pause label reads "Resume" at boot**
  (motion starts disabled), 48px targets, portrait layout, no touch motion
  while paused, resume-via-tap, simultaneous two-finger move+look, releasing
  one preserves the other, third finger cannot hijack, deadzone, unit-axis
  clamp, UI touch isolation, interact gating (blocked paused / starts job
  active), pause+focus-loss clearing, desktop regression (uncaptured mouse
  ignored, click captures, look, pitch clamp, Escape, touch does not capture
  mouse). RED was observed first run (8 failures incl. the real
  `_try_interact` pointer-lock bug) before fixes.
- `godot --headless --path . -s tests/input_pause_test.gd` → exit 0,
  "21 checks — ALL PASS".
- `godot --headless --path . -s tests/room_boot_test.gd` → exit 0,
  "9 checks — ALL PASS".
- `godot --headless --path . -s tests/smoke.gd` → exit 0, "9 checks — ALL PASS".

## Limitations (honest)
- Headless cannot prove real browser/mobile touch behavior: no touchscreen in
  the headless display server, so the documented test-only
  `force_enabled` override is used, and multi-touch comes from synthetic
  InputEventScreenTouch/Drag. Parent must verify on real devices/browsers
  (Safari/Chrome iOS+Android): safe-area insets, gesture conflicts, and feel.
- Synthetic mouse events from touches are not observed to capture the pointer
  in the touch path; on real mobile browsers Godot emits its own synthetic
  mouse events — behavior there still needs browser verification.
- Stick/look tuning (radii, deadzone 0.18, sensitivity multiplier 3.0) is a
  first pass, not playtested on a phone.

## Outstanding work (parent)
- Browser/device verification of real touch gameplay (movement stick, swipe
  look, Interact, Pause/Resume, orientation rotation, safe areas).
- README notes, build stamping, commit/push, deployment (explicitly out of
  scope here).

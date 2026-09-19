# Worker checkpoint — printer visuals + visible print deposition

Task: docs/GLM-PRINTER-VISUAL-SLICE.md (task 04 + visualization section).
Model: glm-5.3-flash via zai coding plan (parent-routed; no auth/quota errors hit).
Branch: main @ 0bfad22, `git pull --ff-only` → already up to date.

## Files changed (exclusive allowlist respected)

- scripts/Printer.gd (NEW) — primitive FDM printer: dark steel base + 2 Z rails
  (#202B2B), terracotta carriage + accent brace (#DA623A), honey ply bed
  (#C3A076), X gantry with nozzle block/tip, StaticBody3D layer-1 collision
  (0.5x0.5 m footprint, 0.6 m tall). Origin at bed center. Keeps "printers"
  group + printer_index meta (set by Main). Exposes set_nozzle_scan(t) and
  set_failed(bool) (nozzle grays out on failure).
- scripts/PrintVisual.gd (NEW) — ONE deposition visual per printer: fixed pool
  of 32 box slices created in _ready (all hidden initially), set_progress()
  reveals/stacks slices with a slight taper; alternating terracotta/honey-tint
  albedo for layer lines; reset(); mark_failed() grays all slices; is_failed()
  + get_fail_mode() + get_fail_mode()/FailMode enum as the DONE_FAIL flag.
  Geometry cap: 32 instances x BoxMesh (12 tris) = 384 tris per printer.
- scripts/Main.gd — _make_printer() now instantiates Printer.gd + a
  PrintVisual child at bed-top height (y=0.10); INTERACT_RANGE 2.8 → 3.0
  (printer is smaller; task allows max 3.0); _update_print_visuals(delta)
  called from _physics_process after sim.tick: visual follows sim.progress()
  on printer 0 while RUNNING/DONE, resets otherwise; nozzle oscillates via
  set_nozzle_scan while RUNNING; sim.print_started → _on_print_started()
  resets all visuals. HUD untouched.
- tests/printer_visual_test.gd (NEW) — 28-check behavioral RED/GREEN gate on
  the real scene.
- docs/worker-printer-visual.md (this file). No UID files were generated
  (Godot wrote none for the new scripts in headless test runs; none committed).

## RED → GREEN (recorded)

RED run (first real execution): 3 parse errors in the test (type-inference on
`var x := visual.get_progress()`), then a real behavior bug surfaced:
PrintVisual slice pool was visible at zero progress (check 13 FAIL) and
DONE_OK never pushed final progress (check 19/20 FAIL). Fixes: initialize
slice.visible = false in _ready; Main now calls set_progress in the DONE
branch, not only RUNNING. One test-order bug fixed in the test itself
(sim had to be forced IDLE before asserting hidden-after-reset).
GREEN (final): 28 checks — ALL PASS, exit 0, no SCRIPT ERROR in output.

## Commands run + outcomes

- git pull --ff-only → "Already up to date." (0bfad22)
- godot --headless --path . -s tests/printer_visual_test.gd
  → 28 checks — ALL PASS (exit 0)
- Regression sweep, all green, no SCRIPT ERROR / Parse Error:
  - tests/room_boot_test.gd → 9 checks — ALL PASS (printer StaticBody3D,
    "printers" group, printer_index meta contracts kept; no test edit needed)
  - tests/grab_test.gd → 26 checks — ALL PASS (occlusion still works via the
    layer-1 printer collision box)
  - tests/input_pause_test.gd → 21 checks — ALL PASS
  - tests/touch_controls_test.gd → 47 checks — ALL PASS
  - tests/smoke.gd → 9 checks — ALL PASS

## NOT-RUN

- Real Godot Web export (parent owns export pipeline + browser verification).
- Browser gameplay / visual-composition check of the new printer geometry.
- tests/test_build_web.py (build pipeline untouched).
- git commit/push (not authorized for this worker slice).

## Handoff notes

- PrintVisual is per-printer but sim is global (one job at a time); integration
  drives printer 0. If multi-printer sim arrives, drive per-printer visuals
  from per-printer sims in _update_print_visuals.
- DONE_FAIL look = all slices grayed (FailMode.GRAY) + nozzle block grays out
  via Printer.set_failed (wired through Main's DONE_FAIL branch flag state_ok).
- Printer origin at bed center keeps _nearest_printer semantics sane; player
  teleport offsets in existing tests (e.g. +0.9/-0.6/+1.1 from origin) still
  land within INTERACT_RANGE=3.0 (all interaction tests pass unchanged).

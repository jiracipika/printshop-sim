# GLM next slice — grabbing and placement

Astra-approved implementation task. Read AGENTS.md, docs/HANDOFF.md, design/implementation-plan.md (task 03) and scripts/Main.gd first. Work only /Volumes/HARD/projects/printshop-sim. git pull --ff-only first; main is at 1b0adde and deployed. Never touch automated-newsletter or pitchforge/pitch-therapy. Model pinned glm-5.3-flash via zai coding plan (GLM_BASE_URL set by parent). Stop on quota/auth, no fallback.

Exclusive files: scripts/Main.gd, new scripts/Grabbable.gd (or Spool.gd if cleaner), tests/grab_test.gd, docs/worker-grab.md, generated UID files. No other source edits. Preserve all existing behavior and tests (touch 47, input_pause 21, room 9, smoke 9 must stay green).

Implement now (not a plan), matching design/implementation-plan.md task 03:
- One interactable interface for grabbable objects; a filament spool prop placed in the room.
- Center-screen ray from camera; interact range 2.2 m; walls/bench occlude grabbing.
- E is context-dependent: grab nearest valid target when empty-handed; place when holding. Touch Interact button uses the same path.
- One held object at a time; second object cannot be grabbed while holding.
- While held: disable its physics/collision explicitly and store original state; attach at a hold marker in front of the camera; held object must not push or launch the player.
- Placement validator: bench top surface is valid; floor valid; overlapping wall/bench collision invalid — invalid placement keeps the object held and the HUD explains why ("No room here").
- Release/restore physics state exactly on placement; no orphan nodes, no collision exceptions after 30 repeated grab/place cycles.
- HUD prompt updates contextually ("[E] Grab spool", "[E] Place", "No room here"); mobile Interact uses same logic.

Behavioral RED/GREEN headless tests (tests/grab_test.gd) exercising the REAL Main scene and physics: out-of-range not grabbable, occluded not grabbable, second-grab rejected, held-object no player launch (player velocity bounded after physics steps), wall overlap rejected + still held, bench placement restores physics body state, 30-cycle repetition leaves node/collision counts stable, touch Interact path grabs too. Also integrate spool-loading is NOT in scope (printer state machine comes later) — grabbing any spool is enough.

Use Python subprocess.run(timeout=60, capture_output) for bounded Godot runs: import --quit, grab_test, touch_controls_test, input_pause_test, room_boot_test, smoke. Scan combined output for SCRIPT ERROR/Parse Error as well as exit codes. Record genuine RED then GREEN.

Do not modify project.godot, TouchControls.gd, export config, README, or git state; no browser/deploy claims. Parent handles web export, browser verification, commit/push/deploy after review.

Checkpoint docs/worker-grab.md before budget expiry: files changed, commands+outcomes, remaining blockers, explicit NOT-RUN list. First inspection immediately, minimal prose, write code early.

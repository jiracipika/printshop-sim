# GLM 3.0 slice 1 — the front counter (v0.58.0)

Model must be glm-5.3-flash via the zai coding plan; no fallback, no auth retry —
on routing failure stop and write the blocker into the worker doc. Work on main,
no commits/push/deploy before parent review. Parent session: planning/review.

Read FIRST, in order: AGENTS.md, design/overhaul-3.0.md (the binding 3.0 plan —
geometry, hazards catalog, definition of done), docs/HANDOFF.md (top two
sections), scripts/FinishingStation.gd (the build/style pattern to copy),
scripts/Main.gd sections: the dressing block that places _finishing (search
"Front-right corner"), _near_finishing(), _try_interact(), _update_hud(),
_build_hud(), scripts/Sfx.gd stream names.

Scope: the service counter island only — furniture, bell, slip pad, interact
branch, tests. NO customers, NO queue logic, NO new save keys (that is slice 2).

New files you own: scripts/CounterStation.gd, tests/counter_test.gd,
docs/worker-counter.md. Allowed edits in existing files, additive only:
scripts/Main.gd (build call + _near_counter + interact branch + one prompt
string), scripts/Version.gd (bump to 0.58.0). Touch NOTHING else — if a failure
seems to require it, record it in the worker doc and stop.

CounterStation.gd (Node3D, pattern of FinishingStation.gd): position (-1.9, 0,
2.55) — set by Main, not baked. Build: honey-plywood top 1.4 × 0.08 × 0.65 at
y 1.0, sage fascia panel under the front edge, two dark-steel legs, a brass-
colored desk bell (small cylinder + sphere) offset (-0.45, top, 0), a paper slip
pad (thin white box, 3 stacked quads) offset (0.4, top, 0.05), a small
"COUNTER" sign Label3D above (y 1.5, facing the room, same style as the
finishing bench sign), and a StaticBody3D + BoxShape3D collision matching the
counter volume so the player cannot walk through. Reuse ShopArt/world materials
via parameters like FinishingStation does — no external assets. Total new
visible meshes: <= 10. Expose: const COUNTER_POS := Vector3(-1.9, 0, 2.55),
func bell_pos() -> Vector3, func ring_frame() (deterministic 0..1 animation
timer for the bell squash, ticked only when rung — the seam tests can freeze).

Main.gd wiring, exact points:
1. var _counter: Node3D near the _finishing declaration; build it right after
   the _finishing block in the same dressing function; _counter.position =
   CounterStation.COUNTER_POS.
2. func _near_counter() -> bool: horizontal distance < 1.35 m from
   CounterStation.COUNTER_POS (pattern of _near_finishing, which uses 1.25 m).
3. In _try_interact, add the counter branch IMMEDIATELY BEFORE the
   "Empty-handed at the crate buys a spool" branch (hazard 10: the counter sits
   inside the crate's 1.6 m radius — this order is load-bearing):
   empty-handed AND _near_counter() AND no walk-in system yet → sfx.play("bell"),
   _set_prompt("The counter is quiet — nobody waiting yet"). Holding any object
   at the counter falls through to existing behavior (place etc.) for now.
4. Nothing in _update_hud, save payloads, or logs changes in this slice.

tests/counter_test.gd (checks-format, print "N checks defined" at start and
"checks=N failures=M" at end; load scripts via load("res://scripts/..."), never
static Main/MainMenu references; instantiate Main the way tests/room_boot_test.gd
and grab_test do — read them first). Cover: counter node exists at COUNTER_POS
with a StaticBody3D whose AABB overlaps the counter volume; collision does not
intersect the grab-test placement corridor (run grab_test in the ladder — it
must stay green unmodified); _near_counter true at 1.2 m, false at 1.6 m;
E empty-handed at the counter (paused=false, captured=true set first, player
teleported near, yaw/pitch set explicitly — hazard 5) shows the quiet-counter
prompt and plays the bell; the press does NOT accept a board job, buy a spool,
or change balance; crate buying still works when standing at the crate (counter
branch does not steal it); prompt behavior unchanged when far from the counter;
paused gate: no prompt while paused; bell ring_frame advances only after a ring
and is frozen when not ticked. Target 16-22 checks.

Verification (all before you write the worker doc): bash tools/ladder.sh (FULL
ladder, sequential; ~71 suites; if it exceeds one command's runtime, split with
regex filters covering all suites — never run two at once), then
~/tools/venv/bin/python -m pytest tests/test_build_web.py -q, then
bash tools/ladder.sh --bots is NOT needed for this slice IF the full ladder is
green and you changed no money/rep/board code — instead run
`timeout 300 ~/tools/godot --headless --path . --script tests/sim_playtest.gd`
once and confirm the printed curve matches the run you record in the worker doc
(it must be identical run-to-run; you are establishing the slice-1 reference).

Definition of done: hazards catalog in design/overhaul-3.0.md fully respected;
new suite green 3 consecutive runs; full ladder LADDER_DONE failed=0; pytest
green; playtest curve recorded; Version.gd 0.58.0; docs/worker-counter.md
written (baseline, exact changes, commands + results, what you did NOT run,
blockers). Stop there — the parent session reviews, integrates, commits.

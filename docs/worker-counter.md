# Worker doc — GLM 3.0 slice 1: the front counter (v0.58.0)

Worker: glm-5.3-flash via zai coding plan (resume of an interrupted run — the
prior attempt's code was already on disk; this run reviewed it against the
brief, fixed one test-plumbing regression it caused, and ran full verification).
Date: 2026-10-30. Brief: docs/GLM-3.0-SLICE-1.md. Base: commit 7753e3e
(machine baseline recorded at 1186ca3). No commits/push/deploy — parent reviews.

## Baseline (state found on disk at resume)

The interrupted prior attempt had already written every code artifact the brief
requires, and review found them complete and brief-conformant:

- `scripts/CounterStation.gd` (new): Node3D in the FinishingStation pattern.
  `COUNTER_POS := Vector3(-1.9, 0, 2.55)` (CounterStation.gd:17), position set
  by Main, never baked. Honey-plywood top 1.4 × 0.08 × 0.65 centered at y 1.0,
  sage fascia under the front edge, two dark-steel legs, brass desk bell
  (cylinder + squashable dome) at offset (-0.45, top, 0), paper slip pad (thin
  white box + 3 stacked quads) at (0.4, top, 0.05), billboarded "COUNTER"
  Label3D at y 1.5 in the finishing-bench sign style. Exactly 10 new
  MeshInstance3D (sign is a Label3D, not a mesh) — inside the <= 10 budget.
  StaticBody3D + BoxShape3D 1.4 × 1.04 × 0.65 on layer 1 covering the island
  volume (world y 0..1.04, x -2.6..-1.2, z 2.225..2.875). Exposes
  `bell_pos()` (to_global of the bell offset), `ring()` / `tick(delta)` /
  `ring_frame()` — deterministic 0..1 seam, `_ring_t` starts at -1 (frame 0
  before first ring), advanced only by explicit `tick()`, no `_process`.
- `tests/counter_test.gd` (new): 22 checks defined / 22 reached (brief target
  16–22), SceneTree pattern of room_boot_test/grab_test, loads Main.tscn via
  `load()`, never names Main at compile time (hazard 4), sets `paused=false` +
  `captured=true` and explicit yaw/pitch after teleports (hazard 5), covers
  every required behavior: node at COUNTER_POS, collision AABB vs island
  volume + clear of the grab corridor, radius true 1.2 m / false 1.6 m,
  empty-handed E → quiet prompt + bell with zero money/board/machine/stats
  change, paused gate, crate buying intact at the crate spot, far behavior
  unchanged, ring seam frozen without ticks / clamps at 1, bell_pos world math.
- `scripts/Main.gd`: additive wiring at the brief's four exact points —
  `var _counter: Node3D` right under `_finishing` (Main.gd:185); build call
  right after the `_finishing` block in `_build_environment` (Main.gd:1505-07,
  sets `.position = CounterStation.COUNTER_POS`); `_near_counter()` right
  after `_near_finishing` (Main.gd:3052-58, horizontal Vector2 distance
  <= 1.35 m, 1.35 per brief where `_near_finishing` uses 1.25); interact
  branch IMMEDIATELY BEFORE the crate branch (Main.gd:4113-19: empty-handed +
  `_near_counter()` → `sfx.play("bell")` + prompt
  "The counter is quiet — nobody waiting yet" + return; held objects fall
  through — hazard 10 order respected). Nothing in `_update_hud`, saves, logs.
- `scripts/Version.gd`: VERSION "0.57.0" → "0.58.0".
- Teleports in `tests/color_test.gd` (2), `tests/events_test.gd` (1),
  `tests/spool_test.gd` (2): crate spot (-3.0, 0.3, 2.1) → (-3.0, 0.3, 1.4).

No gaps found against the brief; nothing was re-implemented.

## Test-plumbing deviations from the brief (parent-authorized)

1. **Three-suite crate teleport** (pre-existing on disk from the interrupted
   run; parent-authorized in the resume instructions, NOT re-escalated, NOT
   reverted): color_test.gd:71,84, events_test.gd:97 and spool_test.gd moved
   their crate teleports from (-3.0, 0.3, 2.1) to (-3.0, 0.3, 1.4). Reason:
   the old spot is 1.19 m from the counter center — inside the new 1.35 m
   `_near_counter` radius — so an empty-handed E there rings the bell instead
   of buying a spool. The new spot is 1.59 m from the counter center (outside
   the radius) and 0.3 m from the crate center (inside its 1.6 m radius).

2. **spool_test crate spot refined** (this run; same class of plumbing, found
   necessary because the ladder went red): spool_test.gd:52,69 —
   (-3.0, 0.3, 1.4) → (-3.1, 0.3, 1.85). The full ladder (run 1) failed
   tests/spool_test.gd check 7 "loading adds 1500 g to the machine"
   (checks=23 failures=1). Diagnosis (measured, not guessed): `_try_place()`
   (Main.gd:2420) drops a held object straight down from the camera's
   HoldMarker (offset +(0.25, -0.1, -0.55), Main.gd:2360-61). At
   (-3.0, 0.3, 1.4) the marker ray hits open floor at z ≈ 0.85, so the test's
   full-hands second E press (check 5, "never double-buy") silently DROPPED
   the spool (held → null); the later "load" press at printer 1 then found
   empty hands and accepted a board job instead, leaving filament_g at 1500.
   At the pre-slice spot (-3.0, 0.3, 2.1) the marker ray hit the crate top
   (box 0.55 × 0.5 × 0.45 at (-3.0, 0.25, 1.4), Main.gd:1900-08), and
   `_placement_error` returned "No room here", keeping the spool held — the
   behavior the test depends on. The refined spot (-3.1, 0.3, 1.85) restores
   it while staying outside the counter radius: measured
   counter-dist = 1.3892 (> 1.35, `_near_counter()` false), near_crate true,
   buy charges $12, full-hands press 2 → "No room here" (spool stays held),
   load → filament_g 3000, second buy works. color_test and events_test stay
   at (-3.0, 0.3, 1.4) — both green in the full ladder, no reason to move.

## Exact changes by this run

- tests/spool_test.gd: two teleport coordinates (lines 52, 69) + one comment
  line. Nothing else.
- docs/worker-counter.md: this file.
- No other file was touched. `git status` now: modified Main.gd, Version.gd,
  color_test.gd, events_test.gd, spool_test.gd; new CounterStation.gd (+.uid),
  counter_test.gd (+.uid), worker-counter.md. The .uid files are Godot 4.7
  generated; the repo already tracks scripts/*.uid (28 tracked), so the parent
  should commit them with the new scripts.

## Commands run + results (all this session, all sequential)

1. `timeout 150 ~/tools/godot --headless --path . --script tests/counter_test.gd`
   — 3 consecutive standalone runs: `checks=22 failures=0`, rc 0 each;
   full log shows `22 checks defined`, 22 ok lines, 0 SCRIPT ERROR/Parse Error
   (hazard 2 gate satisfied).
2. `bash tools/ladder.sh --bots` (run 1, pre-fix): `LADDER_DONE total=74
   failed=1: tests/spool_test.gd` → led to the plumbing fix above.
3. `bash tools/ladder.sh --bots` (run 2, post-fix, FULL and sequential):
   **`LADDER_DONE total=74 failed=0`** — 74 PASS (72 suites incl. smoke +
   sim_playtest + sim_lategame), rc 0.
4. `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` →
   **`21 passed in 0.33s`**.
5. `timeout 300 ~/tools/godot --headless --path . --script tests/sim_playtest.gd`
   (standalone, per brief) → `checks=8 failures=0`, rc 0. Curve byte-identical
   (diff-verified) to the ladder's sim_playtest run from step 3 — two
   independent runs, identical output:
   ```
   PLAYTEST: day 1 end: $151.05 · delivered 2 · rep 2.80 · debt $0.00
   PLAYTEST: day 2 end: $462.25 · delivered 5 · rep 3.20 · debt $0.00
   PLAYTEST: day 3 end: $625.12 · delivered 6 · rep 3.30 · debt $0.00
   PLAYTEST: day 4 end: $743.31 · delivered 7 · rep 3.40 · debt $0.00
   PLAYTEST: day 5 end: $657.39 · delivered 7 · rep 3.00 · debt $0.00
   PLAYTEST: day 6 end: $1024.43 · delivered 10 · rep 3.20 · debt $0.00
   PLAYTEST: day 7 end: $1377.80 · delivered 13 · rep 3.70 · debt $0.00
   PLAYTEST: day 8 end: $1665.79 · delivered 15 · rep 3.80 · debt $0.00
   PLAYTEST: day 9 end: $1749.64 · delivered 17 · rep 4.00 · debt $0.00
   ```
   The harness's own day-8 check prints $1,749.64 / 17 deliveries (ok 5) —
   BYTE-IDENTICAL to the brief's machine baseline (1186ca3). This is the
   slice-1 reference curve.
6. sim_lategame (in ladder run 2): `checks=16 failures=0`, day-14
   $4,918.89 / 64 delivered — BYTE-IDENTICAL to the brief's baseline.

## Definition of done scorecard

- New suite green 3 consecutive runs: YES (standalone ×3 + green in both full
  ladders).
- FULL ladder: `LADDER_DONE total=74 failed=0` (run 2).
- pytest: 21 passed.
- Both harnesses byte-identical to baseline: YES (slices 1–3 contract holds;
  this slice adds furniture + one gated interact branch only — no money, rep,
  board, stats, save-key, or bot-observable change).
- Version.gd 0.58.0: YES.
- Worker doc written: this file. HANDOFF untouched (parent updates it).
- No commits/push/deploy: confirmed.

## What I did NOT run

- Real Web export (`tools/build_web.sh`) — parent/integration owns it (pytest
  test_build_web.py is mocked unit tests by design; its docstring says the
  real export is run separately).
- `sim_playtest.gd`/`sim_lategame.gd` more than the runs listed (one
  standalone playtest + one of each inside ladder run 2; run 1's sims also
  passed but preceded the spool fix — its spool failure cannot affect the
  determinism sims, and run 2 re-proved both).
- Browser gameplay checks, Vercel deploy, live URL verification — out of
  worker scope (no deploy approval).
- Any concurrent Godot process — never; every run sequential (hazard 1).

## Blockers

None. Routing worked (glm-5.3-flash via zai coding plan); no auth/quota
failures encountered.

# Worker checkpoint — workshop baseline (tasks 00 + 01)

Worker: GLM 5.3 Flash via zai coding plan (this session). Branch: main (no commits yet, no remote). No git mutation, no commit/push/deploy performed.

## Task 00 — read-only inventory (DONE)

- git: branch `main`, zero commits, all files untracked, `git remote -v` empty. Untracked work preserved; nothing deleted or overwritten.
- Engine: `godot --version` → 4.7.1.stable.official.a13da4feb. Export templates `4.7.1.stable` present in `~/Library/Application Support/Godot/export_templates/`. Meets the 4.3+ non-threaded-web requirement; no upgrade needed.
- Renderer: `gl_compatibility` (project.godot), viewport 1280x720. Physics layers already named world/player/grabbable. InputMap already has move_forward/back/left/right, jump, interact (WASD/E/Space).
- Source: scripts/Main.gd (261 lines, procedural room+player+HUD), scripts/PrintSim.gd (state machine IDLE→RUNNING→DONE_OK/FAIL), scripts/JobBoard.gd (endless job queue), scripts/Version.gd (autoload), scripts/DebugPanel.gd (not referenced by Main). scenes/Main.tscn is a bare Node3D + Main.gd. tests/smoke.gd (sim-loop smoke). tools/build_web.sh, web_shell/, vercel.json, export_presets.cfg present (unverified this task).
- Note: room is 14x12 m (spec ~7x6), dark palette, only a back-wall mesh with NO wall StaticBody3D, no workbench, no floor/bench spec colors, player not in "player" group, printers ARE in "printers" group with collision.

## Baseline verification (all commands from project root)

- `godot --headless --path . --editor --import` → exit 0, no SCRIPT ERROR/Parse Error/ERROR in log (.baseline_logs/import.log).
- `godot --headless --path . -s tests/smoke.gd` → exit 0, "9 checks — ALL PASS" (.baseline_logs/smoke.log).
- macOS has no `timeout` command; all Godot runs used bounded background processes with output scan for SCRIPT ERROR/Parse Error (both mandatory checks done; counts logged).

## Task 01 — RED/GREEN (DONE)

- New file tests/room_boot_test.gd (behavioral boot/room gate): asserts Main.tscn instantiates; player CharacterBody3D in group "player" spawned above floor; floor StaticBody3D on layer 1 at origin; >=4 wall collision bodies (meta "wall"); bench in group "bench" with StaticBody3D; printer with StaticBody3D; palette colors sage #738771 / honey #C3A076 / steel #202B2B / terracotta #DA623A.
- RED run: `godot --headless --path . -s tests/room_boot_test.gd` → exit 1, zero SCRIPT ERROR/Parse Error, "9 checks — FAILURES: 4": player group missing, spawn check fails, 0 wall bodies, bench missing. Floor body and printers already pass. (.baseline_logs/room_red2.log)
- Astra review fix (test): check 7 previously set ok_palette=false on missing materials but NEVER incremented `failures` — missing palette could not fail the gate. Now has an explicit `failures += 1` branch for a missing/non-Dictionary `world`, plus each unused palette color prints FAIL and increments failures.
- Astra review fix (test strength): the old check only asserted an unused `world` Dictionary existed — an add-on purely to satisfy the test. It now scans all MeshInstance3D material_override colors under Main and requires every palette color to actually appear on at least one mesh (new helper `_all_meshes`). `world` on Main remains as the palette source, and the gate verifies real usage.

## Task 01 GREEN — production changes (scripts/Main.gd only)

- Palette materials built in `_build_world`, exposed as `var world` on Main: sage #738771 (walls), honey #C3A076 (bench top), dark steel #202B2B (bench legs, printer 0 body, floor stand), terracotta #DA623A (floor, bench fascia stripe, printer 1 body).
- Room resized 14x12 → 7x6 m (ROOM_W/ROOM_D/ROOM_H consts). Full 4-wall sage enclosure (back/front/left/right), each wall mesh paired with a StaticBody3D on layer 1 with meta "wall" — 4 wall collision bodies, GameplayAccess preserved: object access was via `get_first_node_in_group`/`get_nodes_in_group` and `_find_body` proximity, so the resize does not break access paths.
- Workbench: Node3D in group "bench" at (-1.8, 0, -2.0); honey ply top, terracotta fascia, 4 dark steel legs, single StaticBody3D+BoxShape3D collision on layer 1.
- Printers (still group "printers", meta printer_index, StaticBody3D collision — sim/jobboard/HUD untouched): printer 0 now sits ON the bench top (y=0.95), printer 1 on a dark steel floor stand (1.8, 0, -2.4). Both remain within INTERACT_RANGE of the new spawn.
- Player: added to group "player"; spawn moved to (0, 0.3, 1.8) — inside the smaller room, above floor, capsule bottom at y>0.
- Note: printer 0's StaticBody3D sits inside the bench's collision volume; both are StaticBody3D so no physics conflict, and the player interacts by distance, not by touching the bench.

## Verification (task 01 GREEN, all via Python subprocess.run timeout=60 capture_output=True text=True)

- `godot --headless --path . --editor --import --quit` → exit 0, no SCRIPT ERROR/Parse Error.
- `godot --headless --path . -s tests/room_boot_test.gd` → exit 0, "9 checks — ALL PASS": scene boot, player group + spawn y=0.30, floor body, 4 wall bodies, bench with collision, 2 printers with collision, all 4 palette colors verified ON scene meshes. (.baseline_logs/run_checks.py output, room_boot section)
- `godot --headless --path . -s tests/smoke.gd` → exit 0, "9 checks — ALL PASS" (sim loop, job board, material accounting unchanged).
- Main-scene boot: `godot --headless --path . --quit-after 120` → exit 0, no SCRIPT ERROR/Parse Error/ERROR lines (.baseline_logs/run_boot.py).
- macOS has no `timeout` command; all Godot runs are Python-subprocess-bounded at 60s with combined stdout+stderr scanned for SCRIPT ERROR/Parse Error plus exit code.

## Exact files touched (this slice)

- scripts/Main.gd — palette/room/walls/bench/printers/player-group edits only (allowlisted).
- tests/room_boot_test.gd — check 7 explicit failure branch + mesh-usage assertion + `_all_meshes` helper (allowlisted).
- docs/worker-workshop-baseline.md — this checkpoint (allowlisted).
- .baseline_logs/run_checks.py, .baseline_logs/run_boot.py — bounded check runners (log dir, not source).
- Generated UID files: tests/room_boot_test.gd.uid (auto-generated at import).

## NOT RUN / pending

- NOT RUN: rendered frame inspection at 1280x720 (headless tests do NOT prove visuals).
- NOT RUN: any browser export, browser gameplay, pointer-lock, or Vercel deployment.
- NOT RUN: web export build (tools/build_web.sh unverified).

## Remaining / next task

- Remaining for acceptance: none within this slice's scope; awaiting Astra review of GREEN.
- Next task (02): first-person player refactor — out of scope until accepted. Update docs/HANDOFF.md at acceptance.

# Print Shop Sim — bounded implementation plan

Astra is the design/planning lead. GLM 5.3 Flash is the intended implementation worker. This document does not invoke or switch any model. All implementation, export, GitHub, Vercel, and live-browser work below is future work requiring authorization. The design-pack task makes no gameplay changes, commits, deployments, credential changes, or configuration changes.

## Operating contract

Give GLM 5.3 Flash one numbered task at a time with the relevant acceptance tests, explicit file allowlist, and existing project context. Discovery is read-only before any source edit. Each task should fit one reviewable change, normally at most 6 files and approximately 300 changed source lines; split before exceeding either bound. Stop rather than rewrite unrelated systems. No replacement of existing project architecture without review. Never touch automated-newsletter or pitchforge/pitch-therapy.

Worker report: exact files changed, commands actually run, exit codes, observed behavior, test artifacts, unresolved failures. Never fabricate engine captures, browser results, URLs, FPS measurements, or deploy success. Authentication or quota failure is a hard stop: report the provider/action and sanitized error, request operator intervention, and do not retry through another account, model, or provider. Other failures may receive one bounded diagnosis/fix attempt; then return evidence and a blocker. No credentials in code, logs, prompts, or artifacts.

## Initial release gate: room / movement / grabbing / printer

This milestone is a toy workshop, not a completed tycoon. Required: load a real browser export; enter a room; move/look with collision; grab and place a spool; load the printer; trigger a short deterministic demo print; inspect state; pause/resume reliably. No contract economy, saves, packing, dynamic failure simulation, or progression yet. UI must say “Workshop prototype” rather than imply the contract loop exists.

### 00 — Read-only inventory and version gate

Inputs: existing repository, installed Godot, available export templates, test/browser tools. Record exact Godot 4.x patch version, current project structure and renderer, test entrypoints and web export compatibility. Choose and pin a version that supports non-threaded web exports (Godot 4.3+); match export templates exactly. Do not upgrade without approval. Deliver an inventory and a proposed source allowlist. Test: engine --version and template presence; report absent tools instead of claiming a build. No git mutation.

### 01 — Minimum offline-loadable room

Scope: one main scene, primitive floor/walls, bench and static printer shell, shared material resources if needed. Use meters, wall/floor collision, approximately 7×6 m room, unobstructed spawn and walking lane. No external asset dependency.

Tests: headless import and scene load without errors; spawn above floor; enumerate required collision bodies; inspect actual engine frame at 1280×720. Placeholder meshes acceptable; match the broad composition, not every SVG detail.

### 02 — First-person player

Scope: CharacterBody3D scene/script, Camera3D, explicit InputMap actions. WASD, mouse sensitivity, gravity, floor/wall collision, no forced bob. Menu prevents movement. Browser capture begins only after a user click; Esc releases capture, pauses, and cannot leave keys latched.

Tests: normalized diagonal input; grounded stop; wall collision; pitch clamp; movement remains consistent at differing physics/render rates; 20 pause/resume cycles; pointer-lock loss and window blur clear input. Actual browser pointer-lock test is required, not only a headless unit test.

### 03 — Targeting and grabbing

Scope: one interactable interface, center ray, spool scene, hold marker, placement validator. One object at a time; maximum reach 2.2 m; walls occlude interaction. Store/restore physics state explicitly while held. Invalid placement keeps object held and explains why. E means grab/place based on state.

Tests: out-of-range and occluded objects cannot be grabbed; second object cannot be grabbed; held object cannot launch the player; wall/bench overlap rejected; valid bench placement restores physics; 30 repeated grabs produce no orphan nodes or collision exceptions. Check reach at viewport aspect changes.

### 04 — Minimal printer state machine

Scope: one printer script/resource, spool socket, short demo print and status. Empty → loaded → ready → printing → complete. Load a held spool only once; consume a fixed demo quantity at start; prevent duplicate start; prohibit moving/rerunning an active job. Print a simple layered object with capped geometry and bottom-up growth. A full model preparation system is deliberately deferred.

Tests: assert legal/illegal transition table; double E does not duplicate spools or objects; start without material rejected; progress stays in [0,1]; pause policy is consistent; completed object appears once; remove resets printer correctly. Fixed-duration demo test uses injected time rather than a long real wait. Test in actual browser as well.

### 05 — HUD and accessible pause

Scope: small shared Theme, balance hidden for milestone, contextual prompt, printer progress/state, pause overlay with Resume and sensitivity control. Use language.md mapping. Mark the build as a prototype. No nonworking “Accept contract” buttons in runtime.

Tests: keyboard focus visible; text at 1280×720 and 1440×900 fits; resize does not cover reticle; UI never captures mouse motion while playing; modal blocks E; Resume click captures pointer; loading/error overlay remains readable. Essential states use words, not color alone.

### 06 — Single-thread Compatibility web gate

Scope: reviewed web export preset and build command, only after implementation authorization. Set Rendering Method to GL Compatibility (gl_compatibility) for desktop and mobile overrides. GDScript only; WebGL 2 browser required. Set Web preset Thread Support off (verify actual preset key `variant/thread_support=false` for the pinned version), extensions off unless explicitly justified. Do not use Forward+, Mobile renderer, C#, SharedArrayBuffer, or pthread-dependent code. Non-threaded export must work without cross-origin-isolation headers; do not add COOP/COEP as a substitute for disabling threads.

Example commands, adapted only after discovery:

    godot --headless --path <project> --editor --import
    godot --headless --path <project> --script res://tests/run_tests.gd
    godot --headless --path <project> --export-release Web <staging>/index.html

Use a minimal GDScript assertion runner if no test framework exists; no invented framework command. Keep staging outside source-controlled gameplay content. Serve the complete export over HTTP with application/wasm for .wasm; never validate using file://. Check index.html, JS, WASM and PCK requests all succeed; no stale mixed builds; errors surface to the user. Check exported loader/config indicates no thread requirement and no missing .worker resource. A worker alone is not proof of engine threads; inspect the actual export setting and runtime requirements.

Tests: fresh Chromium and Firefox desktop contexts; Safari/WebKit when available (otherwise mark untested); actual WebGL context initialization and first rendered frame; interaction tests 02–05; no SharedArrayBuffer/isolation error; full reload without a warmed cache; tab blur/resume. Record device, browser version, resolution, load bytes/time, console/network errors and a 60-second frame-time sample. Proposed target on the recorded baseline laptop: median at least 45 FPS at 1280×720 and no recurring stalls over 100 ms; this is a target, not a measurement. If missed, profile before increasing visual scope.

### 07 — Approved GitHub + Vercel release, then live verification

This task is NOT authorized by creating this pack. Obtain explicit approval for repo/branch, commits/push, Vercel project and public deployment. Check existing authenticated context without printing tokens. Stop on authentication or quota failure; never switch model or accounts. Review export and diff for credentials, private assets, caches and oversized artifacts before publishing.

GitHub: use an approved feature branch and PR after local tests. Pin the engine/export-template versions and build workflow. Choose either a reproducible CI export published as a deployment artifact, or reviewed static export tracking if appropriate for repository limits; document the choice. Do not rely on Vercel having Godot preinstalled. Prefer the approved CI job to produce the complete static folder, then deploy that exact folder through the approved Vercel integration/CLI. Protect release secrets with GitHub environment scoping, not committed .env files. No auto-deploy from this design task.

Vercel: static site output is the complete export directory; no SPA catch-all that rewrites .wasm or .pck to HTML. Confirm application/wasm and binary PCK responses, successful compression, and consistent cache invalidation for versioned binaries and index. Record commit SHA, build identifier and deployment URL. Read deployment status back from the exact target after write; provider success alone is not acceptance.

Actual live browser acceptance on that HTTPS URL, not localhost:

1. Open a clean context, confirm the approved build ID and first real 3D frame.
2. Capture console plus failed requests; confirm exported resources return correct types, not HTML error pages.
3. Click Play; confirm pointer lock, walk against a wall, look around, grab a spool, place it, grab again, load printer, start and complete the demo print.
4. Esc, Resume, blur, refocus and resize. Verify no stuck movement or accidental interaction.
5. Reload and repeat the cold-start path in a second supported browser. Test limited-bandwidth loading and a blocked asset to verify a clear failure state.
6. Save actual screenshots and machine-readable test evidence with URL, timestamp, browser/device, build ID and test outcomes. Evaluate visual readability manually. Automation must generate real trusted input for pointer lock; if unsupported, use an interactive browser and record manual results.

Release gate fails if no browser is available, hosting is inaccessible, or this scenario cannot be completed. Report “deployed but unverified” when only HTTP checks pass. Never call a curl 200 a working game. Rollback to a known verified deployment only with approval, and verify that target again.

## Full contract loop — only after initial gate

### 08 — Contract and money data

Bound: one typed contract resource, one ledger and one fixture suite. Define accepted/prepared/printing/inspection/packed/delivered/failed states, unique job IDs, one active job initially, integer cents and transactional material charges. Tests: insufficient funds, duplicate accept/deliver, exactly-once payouts, rejected quality, deadline boundaries, balance reconciliation. Mockup values are fixture inspiration, not final tuning.

### 09 — Orientation and support preparation

Bound: preset orientation preview, bed-fit and deterministic support heuristic, estimate panel. No runtime mesh slicer or arbitrary STL importer. Snapshot approved settings into the job. Tests: upright planter requires no supports; side orientation incurs supports under documented heuristic; out-of-bed model rejected; estimate equals consumption under the same settings; canceled preparation changes no money.

### 10 — Print simulation and recovery

Bound: deterministic seeded failure evaluation, progress/quality result, cleanup action. Material charged once, no payout on failure, clear cause and recovery. Tests: fixed seeds reproduce faults; bad prep raises documented risk; cleanup clears state without refund duplication; pause and background-tab policy do not skip transitions; no reentrant completion.

### 11 — Inspection, packing and payout

Bound: quality check, box station, packed-item delivery and receipt. Accept only correct model/material/quality for the active job. Test the full loop in GDScript and in the real deployed browser: accept → prepare → print → inspect → pack → deliver → one payout. Also test wrong object, missing box, double delivery and failed print recovery.

### 12 — Progression, persistence, polish

Split into separate reviewed tasks: printer upgrade data/purchase; versioned local save with corruption fallback; accessibility/settings; performance/art pass. Tests: cannot buy without funds, bed/material capability gates work, reload preserves exactly-once job state, invalid saves do not crash, storage denial is explained. No cloud saves until separately scoped. Repeat task 07 live acceptance including one complete contract loop before calling it a tycoon release.

## Evidence and definition of done

Local source correctness, successful export, successful host deployment, and successful live play are four different assertions. Every release report separates them. Design HTML is neither a substitute for engine art nor evidence of gameplay. Keep an acceptance matrix with pass/fail/blocked/not-run, exact evidence paths, and the next bounded action. No milestone advances on a fabricated or partial pass.

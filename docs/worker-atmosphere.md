# Worker doc — GLM 3.0 slice 3: atmosphere & presence pass (v0.60.0)

Worker: glm-5.3-flash via zai coding plan. Date: 2026-10-30. Brief:
docs/GLM-3.0-SLICE-3.md. Base: commit 0640c6b (slice 2 integrated; machine
baseline recorded at 1186ca3). No commits/push/deploy — parent reviews,
integrates, commits.

## Baseline (state found on disk)

Clean tree at 0640c6b ("feat: walk-in counter customers (v0.59.0) — Print
Shop 3.0 slice 2"). Probed before any change (v020-style audit method,
tests/v020_test.gd:78-90): fresh boot = 168 visible / 394 total
MeshInstance3D; with one walk-in actor = 170 / 396. Slice-1's counter and
slice-2's actors already sit inside those numbers.

**Budget finding that shaped this slice (measured, not guessed):** the brief's
reference point "180 visible / 400 total with a walk-in active" is NOT the
binding moment — tests/v020_test.gd itself audits at a point where it has
hard-set `main.season = Events._season_by_id("humid")` (v020_test.gd:50) and
then restored Standard quality (v020_test.gd:53), so the 10 rain-streak
meshes (Main.gd `_build_environment`, RainStreaks) are VISIBLE at the audit:
the real slice-2 baseline there is **178 visible / 394 total**. A first
implementation with four always-visible new nodes (door, pendant, strip,
clutter) measured 172 at a calm boot but failed v020 at **182/180**
(ladder run 1: `FAIL v020_test (rc=1)`, v020 log `FAIL 10: visible mesh
budget holds (182/180)`). Per the brief's relief valve ("reduce clutter
meshes, not the audit") the fix reduced NODE COUNT, not the assertion: see
"Budget-driven deviation" below. After the fix v020 stands at exactly
**180/180** at its audit point (deterministic: 168 fresh + 10 rain + 2 new
nodes) and the with-walk-in audit in atmosphere_test reads 172/398.

## What shipped

### New files (worker-owned)

- `scripts/ShopFront.gd` (~340 lines): Node3D, WindowLife pattern — room-space
  node built from primitives, `_process(delta) -> _advance(seconds)`, no
  Tween/AnimationPlayer/RNG. Main adds it in `_build_environment` right after
  the CounterService build; it never bakes a `class_name` (Main uses
  `load()` + `has_method` guards). Contents:
  - **ENTRY DOOR** (brief item 1): pivot `DoorPivot` at the hinge
    (-2.4, 0, 2.88) on the front wall's interior face (wall box spans
    z 2.9..3.1, Main.gd wall_specs front wall); one flush `DoorPanel`
    BoxMesh 1.0 × 2.1 × 0.045 centered at pivot-local (0.5, 1.05, 0). The
    steel jamb and the slim glass slit are PAINTED into a dedicated
    procedural door texture (ImageTexture built in `_door_material()`,
    honey field + steel border + dark slit) so the whole door assembly is a
    single mesh node. NO wall hole, NO new collision — atmosphere_test
    asserts zero StaticBody3D/CollisionShape3D under the node. Swing:
    `swing()` arms one open-hold-close gesture (opening 0.6 s at
    deg_to_rad(75), hold 1.2 s, closing 0.6 s) — "swings open 75 deg over
    0.6 s and closed after 1.2 s". `open_frame()` is the deterministic
    0..1 openness; `_advance` is time-faithful (one call consumes the full
    `seconds` across phase transitions, so `_advance(3.0)` from closed
    always lands closed). `set_motion(false)` (calm mode) does NOT stop the
    machine — it changes how the frame is APPLIED: `_apply_swing` snaps the
    rotation to fully-open/fully-closed. Deliberate deviation from the
    literal WindowLife early-return gate (documented in the header comment):
    a gated `_advance` would freeze the door open forever in calm mode, a
    visible state bug; the machine is pure float bookkeeping, the gate is on
    the animation. No Tween anywhere (asserted).
  - **OPEN SIGN** (brief item 2): `DoorPivot/OpenSign` Label3D "OPEN",
    billboarded, child of the pivot so it swings with the door. Lit modulate
    = HDR gold Color(1.35, 1.08, 0.5) (blooms through the existing glow),
    dim = Color(0.43, 0.42, 0.37). `set_business_open(bool)` flips it;
    `set_quality(low)` gates it — at Low the sign stays but is never lit
    (non-emissive), same pattern as `_apply_season_visuals`' rain/frost
    gating. Main pushes the window bool each `_tick_counter` from
    `day_cycle.t` against `CounterService.DAY_START_FRAC/DAY_END_FRAC` —
    the same frac source slice 2 arrives on.
  - **COUNTER PENDANT + LIGHT STRIP + CLUTTER** (brief items 3-4): one
    `CounterDressing` node at (-1.9, 0, 2.55) holding a single ArrayMesh
    (`CounterDressingMesh`) with EIGHT surfaces, plus `PendantLight`
    OmniLight3D (warm #FFD9A5, range 3.0, **energy 0.5, shadow_enabled =
    false** — the slice's only new real light, not quality-gated):
    surfaces 0-2 = pendant stem (steel) + cone shade (steel) + emissive
    bulb (energy 1.6); surface 3 = under-lip light strip, emissive gold,
    at the counter's room-side face (world y 0.955, z 2.215, just under
    the 1.0 top lip); surfaces 4-7 = clutter — slip stack (paper),
    plant pot (terracotta) + foliage (mint), card-reader box (ink) — on
    the counter top, clear of CounterStation's bell (-0.45 local) and
    slip pad (+0.4 local). ShopFront adds 2 visible/2 total mesh nodes.
  - **Shopfront dressing outside the window: untouched** (brief item 5 —
    the v0.25 window view was not modified).
- `tests/atmosphere_test.gd`: 25 checks defined / 25 reached, checks-format
  SceneTree suite (counter_test/walkin_test pattern, `load()`-only class
  references per hazard 4, BrowserSave cleared at start and re-pointed +
  cleared at the end like walkin_test). Stays paused the whole run — every
  gate is driven through the deterministic seam (direct calls), so headless
  frame-timing jitter can never flake it (an earlier draft awaited engine
  frames for the door-swing check and was flaky by construction; the seam
  exists precisely to prevent that).
- `docs/worker-atmosphere.md`: this file.
- `.uid` files for both new scripts (`scripts/ShopFront.gd.uid`,
  `tests/atmosphere_test.gd.uid`), generated via a headless
  `godot --headless --path . --import` rescan; repo convention tracks them.

### scripts/CustomerActor.gd (outfit variety ONLY, same API)

- `OUTFITS` widened 5 → 6 warm-maker colors (added mint #A8C8AC; the sixth
  slot; all distinct — asserted).
- NEW static draws, hash-pinned (absi(hash(...)) % n, repo precedent):
  `accessory_kind(day, index)` -> 0 none / 1 flat cap / 2 scarf
  (hash "walkin-acc-<day>-<i>" % 3) and `accessory_color(day, index)`
  (hash "walkin-acc-c-<day>-<i>" over a 4-color ACCENTS token palette).
- The accessory is built as extra SURFACES on the existing Torso/Head
  meshes, NOT child MeshInstance3D nodes: scarf = 1 band surface on the
  torso capsule; flat cap = crown + brim surfaces on the head sphere (2
  surfaces). Same visual, same per-accessory draw calls, ZERO extra audit
  nodes. A fresh actor (no meta) still builds exactly two plain meshes, so
  walkin_test's "the customer is two meshes" pin (walkin_test.gd:516) stays
  green UNMODIFIED — re-verified 38/38 twice this session.
- "Nothing above the head": the cap crown top sits at head-local y 0.100
  vs the sphere top 0.105 — asserted via max-vertex-y (atmosphere_test
  check 22).
- Bob unchanged (`_advance`/`set_motion` untouched); accessories ride the
  meshes they decorate so the bob carries them. Torso/Head node names,
  WAIT_POS, `outfit_color`, `outfit_color_for_instance` all unchanged.

### scripts/Main.gd (additive hooks only)

1. `var _shop_front: Node3D` (under the walk-in vars) + build call in
   `_build_environment` right after `_counter_service = CounterService.new()`.
2. `_apply_quality()`: one guarded hook after `_apply_season_visuals()` —
   `_shop_front.set_quality(preset == "Low")`.
3. `_apply_calm_motion()`: one guarded hook — `_shop_front.set_motion(
   not calm_motion())`.
4. `_tick_counter()`: one guarded hook right after `frac` is read —
   `_shop_front.set_business_open(frac >= CounterService.DAY_START_FRAC
   and frac <= CounterService.DAY_END_FRAC)`.
5. `_spawn_walkin()` / `_counter_despawn()`: one guarded `_shop_front.swing()`
   each — the same spawn/despawn points slice 2 already has (brief item 1).
6. `_build_hud()` restyle ONLY (no structure/layout/node/text changes):
   - NEW `_hud_panel_style()` helper returning a cached shared StyleBoxFlat:
     ink #202B2B at 0.95 opacity (Color(0.125, 0.169, 0.169, 0.95)), corner
     radius 4, same content margins as before. The StatusCard panel now
     wears it (was ad-hoc 0.55-opacity, radius 6).
   - `_status` label: font color paper #EEE5D3 added.
   - `_prompt` label: font color clay #DA623B + ink outline (size 4) for
     contrast — see interpretation note below.
   - `_toast`: font color #E8B24A → gold #F5CE80 (design token).
   Label texts, anchors, offsets, and every other node untouched. No suite
   pins the old colors/StyleBox (grepped tests/ — v015 pins MainMenu's
   COLOR_TERRA/COLOR_PAPER, a different file; HUD suites assert .text via
   contains() only). walkin/counter/HUD suites re-verified green unmodified.

### scripts/Version.gd

VERSION "0.59.0" -> "0.60.0".

## Budget-driven deviation (for review)

The brief's own numbers cannot coexist with the unmodifiable v020 audit at
its real audit point: door + jamb + sign placard + pendant (shade + bulb) +
strip + clutter at the brief's plain-node counts is 12-15 nodes, v020's
baseline leaves 2 visible / 6 total at its humid moment. Applied relief
valves, all node-count reductions with draw-call cost unchanged:
1. Door jamb + glass slit painted into the panel texture (1 node, not 3-5).
2. Pendant stem + shade + bulb = 3 surfaces of the dressing mesh (was
   2-3 nodes).
3. Under-lip strip = 1 surface of the dressing mesh (was 1 node) — it is
   present and emissive; the brief's "slim light-strip emissive" is
   satisfied at the draw-call level.
4. Clutter = 4 surfaces of the dressing mesh (brief said "3-5 meshes";
   satisfied as 4 surfaces / 4 draw calls, 0 extra nodes).
5. Actor accessories = surfaces (cap 2, scarf 1), not nodes.
Net: +2 visible / +2 total MeshInstance3D, ~+12 true draw calls. The OPEN
sign remains a Label3D (0 nodes). v020 passes at exactly 180/180 — zero
visible margin, but fully deterministic (the 178 base is the same 10 rain
streaks every run).

## Interpretation notes (for review)

- "prompt clay #DA623B accent bar": _build_hud may add no nodes, so there is
  no literal bar Control; the prompt label itself carries the clay accent
  (font color #DA623B) plus an ink outline for readability. Recorded here as
  the deliberate reading.
- ShopFront calm gate: the swing state machine keeps ticking in calm mode and
  only the applied rotation snaps (see What shipped). `set_motion(false)`
  snap behavior is asserted (open at 75 deg within one frame, closed one full
  gesture later, no Tween residue).
- The swinging door sweeps the spot where a waiting customer stands
  (CustomerActor.WAIT_POS (-1.9, 0, 2.75) is inside the panel's arc) for the
  ~0.6 s of a swing — scripted actors ignore collision and the panel is
  mostly hidden behind the counter, per the overhaul doc's "actors ignore
  collision"; accepted as a cosmetic transient, not escalated.

## Verification (all this session, all sequential — hazard 1)

1. `timeout 150 ~/tools/godot --headless --path . --script
   tests/atmosphere_test.gd` — **3 consecutive green runs** after the fixes
   below: `checks=25 failures=0`, rc 0 each, 0 SCRIPT ERROR / Parse Error
   lines, `25 checks defined` == `checks=25` (hazard 2 gate).
   Debug trail kept honest: ladder run 1 failed v020 (182/180) and the first
   suite drafts caught TWO real bugs — (a) `swing()` read `open_frame()`
   AFTER flipping the phase to OPENING, so a mid-CLOSING re-arm jumped the
   door 18.75 deg -> 56.25 deg (openness read as the raw closing timer);
   fixed by capturing openness before the phase flip (ShopFront.gd
   `swing()`); (b) a first `_advance` advanced only one phase per call, so a
   single large `_advance(2.4)` never reached CLOSED; fixed with the
   time-faithful `_consume` walk. Both fixes are production code, caught by
   the new suite.
2. Pinning suites standalone, UNMODIFIED: walkin_test **38/38** rc 0,
   counter_test **22/22** rc 0 (run again after the node merge).
3. `bash tools/ladder.sh --bots` (FULL, sequential) — run 1:
   `LADDER_DONE total=76 failed=1: tests/v020_test.gd` (the 182/180 budget
   miss documented above; both bots already green). Run 2 (after the merge):
   **`LADDER_DONE total=76 failed=0`** — 74 suites incl. atmosphere_test +
   smoke, plus sim_playtest + sim_lategame, runner rc 0.
4. `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` →
   **`21 passed in 0.37s`**.
5. Both harness curves from ladder run 2, BYTE-IDENTICAL to the slice-2
   reference (docs/worker-walkin.md:236-244 playtest, :254-267 lategame;
   diff-verified against files cut from those lines — `diff` empty for
   playtest 9/9 and for lategame days 1-14; the lategame log's extra line is
   day 15, the documented roll-over line, and its value $6026.39 / 74 /
   4.70 matches the reference's own day-15 line byte-for-byte):
   (curves pasted in the result evidence)
   sim_playtest `checks=8 failures=0`; sim_lategame `checks=16 failures=0`;
   both logs 0 SCRIPT ERROR / Parse Error. Walk-ins arrive and expire
   throughout (the door swings in-engine); nothing they touch is
   bot-observable (visual-only slice).
6. `tests/v020_test.gd` standalone (after the merge):
   `checks=19 failures=0`, rc 0 — the budget audit passes at its real
   humid-season audit point AND its full Low-quality delivery loop.

## Definition of done scorecard

- New suite green 3 consecutive runs: YES (25/25 × 3).
- FULL ladder: `LADDER_DONE total=76 failed=0` (run 2).
- pytest: `21 passed in 0.37s`.
- Both harnesses byte-identical to the slice-2 reference: YES (diff-empty as
  above; visual-only slice — no money, rep, board, machine, log or save-key
  change; the only Main.gd logic touched is visual hook dispatch).
- Version.gd 0.60.0: YES. HANDOFF untouched (parent updates it).
- Worker doc: this file. No commits/push/deploy: confirmed (`git status`
  shows only Main.gd/CustomerActor.gd/Version.gd modified + the new
  worker-owned files and .uid files).

## What I did NOT run

- Real Web export (`tools/build_web.sh`) and browser gameplay checks —
  parent/integration owns them; pytest's test_build_web.py is mocked unit
  tests by design.
- Screenshots / visual inspection of the new shopfront in a rendered window
  — headless only; the visuals are asserted structurally (geometry,
  materials, emission, light params), not by eye. The parent should eyeball
  a browser build before deploy.
- Any concurrent Godot process — never; probes, suites, both ladders and
  pytest all sequential (hazard 1).
- sim_playtest/sim_lategame standalone beyond their ladder runs — both ran
  green inside BOTH full ladders; run 2's logs are the evidence above.

## Blockers

None. Routing worked (glm-5.3-flash via zai coding plan); no auth/quota
failures. Stop — parent session reviews, integrates, commits.

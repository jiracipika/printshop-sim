# worker-bugfix — v0.61.x bug-fix slice (baseline 1894b03)

Worker: GLM implementation worker. Brief: docs/GLM-BUGFIX-SLICE.md. Hazards:
design/overhaul-3.0.md (binding). No commits — parent integrates.

Files touched (all inside the slice's ownership boundary):
- `scripts/Main.gd` — bug 1 (stack visual) + bug 2 (prompt aging)
- `scripts/ShopFront.gd`, `scripts/CustomerActor.gd` — bug 3 dedup only
- NEW `scripts/MeshKit.gd` (+ its generated `.uid`, tracked like every other
  script's .uid)
- NEW `tests/bugfix_test.gd` — 34 checks
- Version stays 0.61.0 (Version.gd untouched). No test files outside my
  ownership modified: packing/v018/walkin/counter/v020/v034/v037/atmosphere
  all ran green UNMODIFIED.

## Bug 1 — packing-table stack visual

New `Main.gd` helper (`_refresh_stack_visual`, at Main.gd:4036): recomputes
the count as **the max `parts_packed` over machines whose contract is
multi-part and mid-completion** — state not in
[PACKED, DELIVERED, FAILED]. INSPECTION covers the carried/packed part;
PREPARING/PRINTING cover the reprint flow with copies already on the table
(parts_packed stays > 0 through the reprint). Walk-in contracts are excluded
automatically: `CounterService.make_contract` pins `parts_total = 1`
(scripts/CounterService.gd:101), so `is_multi_part()` never admits them.

### Per-call-site decision table (7 sites, zero blind `set_stack_count(0)` left)

Line numbers are post-change Main.gd (pre-change sites in parentheses).

| Site | Path | What ends there | Decision | Why |
|---|---|---|---|---|
| 3195 (was ~3192) | walk-in patience-expiry teardown (`_tick_counter`) | the walk-in's own single-part contract (FAILED + detached just above) | `_refresh_stack_visual()` | the expiring order never contributed to the stack (walk-ins are single-part); this is the HANDOFF-named cosmetic edge — an unrelated board multi-part mid-completion keeps its copies |
| 3277 (was ~3271) | `_accept_walkin_on` | nothing (fresh order starts parts_packed = 0) | `_refresh_stack_visual()` | accepting ends no stacked order; recompute is a no-op when nothing else is stacked, and a fix where a stacked board order previously got wiped |
| 3885 (was ~3876) | `_try_pack_held`, second-F branch | the failing multi-part itself (advanced FAILED at 3875) | `_refresh_stack_visual()` | FAILED no longer counts, so the dead order's own copies clear; if another machine's multi-part is also mid-completion, its max survives |
| 3919 (was ~3907) | partial-pack branch (was `set_stack_count(c.parts_packed)`) | nothing — copies ADDED (parts_packed incremented at 3903) | `_refresh_stack_visual()` | identical to the old set in every single-order scenario (pinned flows), and shows the max instead of overwriting when two multi-parts run in parallel |
| 3975 (was ~3960) | `_settle_held_delivery` tail (final board copy AND counter handover) | the delivered order (advanced DELIVERED at 3948–3951) | `_refresh_stack_visual()` | **the primary named bug**: delivering an unrelated single-part board order or walk-in handover used to zero an unrelated multi-part's stacked copies. DELIVERED no longer counts, so THE completed order still clears its copies |
| 4265 (was ~4227) | `_accept_on` (board accept) | nothing (fresh job, parts_packed = 0) | `_refresh_stack_visual()` | same reasoning as the walk-in accept |
| 4378 (was ~4337) | `_on_day_changed` overnight cancel | the cancelled order (FAILED + detached just above) | `_refresh_stack_visual()` | its own copies clear; unrelated live orders survive; loop-safe — each cancellation in the morning sweep recomputes from live state |

Why refresh everywhere instead of keeping a plain `set_stack_count(0)`
anywhere (the brief allowed either per site): with up to four machines, TWO
multi-part orders can be mid-completion in parallel, so a plain 0 at any
end-of-order path (final copy, failure, cancel) would reintroduce the same
bug in the opposite direction — order A's completion wiping order B's stack.
The refresh form is the brief's semantics applied generally; in every
single-order scenario (all of v018_test/packing_test) the recomputed value
equals the old value, which is exactly why those suites stay green
UNMODIFIED (verified below).

## Bug 2 — event prompts age out

- `const PROMPT_TTL_S := 6.0`, `var _prompt_t := 0.0`, `var _prompt_armed := ""`
  (beside `_boot_prompt`, Main.gd ~287).
- `_set_prompt` (Main.gd:2581) arms: `_prompt_t = PROMPT_TTL_S` and records
  `_prompt_armed = t`. A fresh prompt restarts the window.
- `_physics_process`: the countdown sits beside the toast fade, ABOVE every
  early return (`_player == null`, paused/unlocked gates), so aging never
  stalls — a prompt ages in game-time even across pauses, exactly like the
  toast already did. Only `_prompt.text` is cleared; the HUD status lines are
  never touched (nothing else writes/reads `_prompt` in `_update_hud` —
  verified by grep before touching anything).
- **Timer-exempt direct writes**: direct `_prompt.text = ...` writes (boot
  capture at ~299/615, pause/resume hints, menu suppression at ~2723,
  prototype hint at ~4732) never arm the window, AND the expiry clears only
  if `_prompt.text == _prompt_armed` — so a window armed by an earlier event
  prompt can never clear a state hint written over it. This is the strict
  form of the brief's "boot capture prompt must NOT age": even
  set-prompt → write-boot-prompt-within-6-s keeps the boot prompt forever.
  Proven in bugfix_test checks 26–34.
- Suite-safety evidence: only `tests/touch_controls_test.gd:134` drives
  `_physics_process` directly (a single 1/60 s delta — cannot age a 6 s
  window); the 16 prompt-reading suites all ran green UNMODIFIED (batch 2
  below); the sim bots never read `_prompt` at all
  (`grep -n "_prompt\|_set_prompt" tests/sim_playtest.gd tests/sim_lategame.gd`
  → no matches, rc=1), so aging cannot move bot-observable behavior.

## Bug 3 — MeshKit dedup

- NEW `scripts/MeshKit.gd`: `class_name MeshKit extends RefCounted` with
  `static offset_arrays(src, offset)` and `static box_mesh(size)` — moved
  VERBATIM from the two identical private copies (verified identical by
  reading both before moving).
- `scripts/ShopFront.gd`: both helpers deleted, 12 call sites now
  `MeshKit.offset_arrays(...)` / `MeshKit.box_mesh(...)`; ShopFront-only
  `_cyl_mesh` / `_sphere_mesh` stay (single owner).
- `scripts/CustomerActor.gd`: both static helpers deleted, 5 call sites
  rewritten. The two-mesh outfit build is untouched (walkin_test two-mesh pin
  green unmodified).
- Zero geometry/material/node changes — pure code motion, so the v020
  draw-call/mesh-node budgets are unchanged (v020_test PASS unmodified).
- Parse-order hazard verified by running suites: MeshKit references only
  built-in types (no project classes), so no cycle; the ladder batch
  containing atmosphere/v034/walkin/counter (all of which build the shop
  front and spawn actors) is fully green.
- **PARENT NOTE (important)**: `class_name MeshKit` needs the global script
  class cache. `.godot/` is gitignored, so I regenerated it on this machine
  with `godot --headless --path . --import` (log line
  `update_scripts_classes | MeshKit`; the class is now in
  `.godot/global_script_class_cache.cfg`). The full ladder must run in this
  same checkout (or after a `--import`) — from a fresh clone without the
  cache, ShopFront.gd/CustomerActor.gd would fail to resolve `MeshKit` at
  parse time. No `.github/workflows` exist, so there is no CI consumer.

## Bounded free sweep (owned files only; report-first)

LIST (not fixed, out of slice scope):
- `scripts/Main.gd:4861–4863` (`_update_hud`, runs every physics frame):
  `get_node_or_null("/root/Version")` + `get_node("/root/Version")` perform
  two absolute-path lookups per HUD frame, guarded null-safe. The version
  label could be cached once at boot. Not fixed — HUD/boot plumbing outside
  the slice; zero behavioral risk, listed only.

CLEAN (grep-verified, nothing to fix):
- No `.extend(` misuse in any owned file (`grep -n "\.extend(" scripts/Main.gd scripts/ShopFront.gd scripts/CustomerActor.gd scripts/MeshKit.gd tests/bugfix_test.gd` → no matches).
- No `Timer` nodes anywhere in the owned files — all timers are float
  countdown fields (`_toast_t`, `_counter_arm_t`, new `_prompt_t`) ticked in
  `_physics_process`; nothing to leak or free.
- `scripts/Main.gd` contains ZERO `await` — no coroutine can be left
  un-awaited inside Main.gd; my new suite awaits every coroutine call.
- `CustomerActor._advance` (the calm-mode seam) touches only cached
  `_torso`/`_head` members — no per-frame `get_node`. Remaining `get_node`
  sites in Main.gd are event-driven (grab/drop HoldMarker) or boot-time.
- Typed arrays: every `Array[T]` declaration uses literal-init (legal);
  member re-assignments are `.slice()` results (same-typed) or the empty
  literal `[]` (exercised by pinned suites). The HANDOFF's
  `daily_delivered = [1, 2]` trap is a test-side pattern and appears in no
  owned file.

## Verification (all sequential this session — hazard 1; no other Godot ran)

Filtered ladder batch 1 (affected suites; ask's filter + v020 draw budget +
touch which drives `_physics_process` directly):

    bash tools/ladder.sh 'bugfix|counter|walkin|packing|v018|v034|v037|atmosphere|v020|touch'
    PASS atmosphere_test
    PASS bugfix_test
    PASS counter_test
    PASS packing_test
    PASS touch_controls_test
    PASS v018_test
    PASS v020_test
    PASS v034_station_test
    PASS v034_test
    PASS v034_windowlife_test
    PASS v037_test
    PASS walkin_test
    ----------------------------------------
    LADDER_DONE total=12 failed=0

Hazard-2 spot check on the pinning suites (each log: no SCRIPT ERROR/Parse
Error, defined == reached):
- packing_test: `checks=58 failures=0`, 0 script errors (brief pins 58)
- v018_test: `checks=55 failures=0`, 0 script errors (brief pins 55)
- walkin_test: `38 checks defined` == `checks=38 failures=0`
- counter_test: `22 checks defined` == `checks=22 failures=0`
- bugfix_test: `34 checks defined` == `checks=34 failures=0`

New suite, 3 consecutive green runs (DoD):

    consec1 rc=0 checks=34 failures=0
    consec2 rc=0 checks=34 failures=0
    consec3 rc=0 checks=34 failures=0

bugfix_test coverage (34 checks): MeshKit translation/dedup (5); the named
bug end-to-end on the real scene — unrelated board delivery, unrelated
counter handover (via_counter=true), walk-in accept, walk-in patience expiry
all keep a mid-completion multi-part's stack, multi-part completion and
two-F failure clear it (14); `_refresh_stack_visual` unit semantics — max
over live multi-parts, single-part excluded, DELIVERED/FAILED excluded
(6); prompt aging — boot never arms, direct writes never age, 5 s survives /
6 s clears, fresh `_set_prompt` restarts, boot capture prompt survives a
pending window (9).

Prompt-heavy batch 2 (every suite that reads `_prompt.text` per the pre-change grep):

    bash tools/ladder.sh 'v011|v014|v021|v023|v032|v038|v040|v042|v045|day|economy|features|grab|input|menu|spool'
    PASS day_test
    PASS economy_test
    PASS features_test
    PASS grab_test
    PASS input_pause_test
    PASS menu_test
    PASS spool_test
    PASS v011_test
    PASS v014_test
    PASS v021_test
    PASS v023_test
    PASS v032_test
    PASS v038_test
    PASS v040_test
    PASS v042_test
    PASS v045_test
    ----------------------------------------
    LADDER_DONE total=16 failed=0

pytest (the ask's command):

    /home/rs/tools/venv/bin/python -m pytest tests/test_build_web.py -q
    21 passed in 0.35s

CJK scan (user-preference discipline): `grep -nP "[\x{4e00}-\x{9fff}...]"` over
all changed/new files → no matches (rc=1, clean).

## Not run by me — parent's independent gate

- The FULL ladder and the sim_playtest / sim_lategame bot harnesses were NOT
  run by me (the ask reserves them for the parent as the independent gate).
  Inertness argument for the bots: they never read `_prompt` (grep rc=1) and
  never read `stack_count()` (its only reader is v018_test); the stack fix
  toggles `MeshInstance3D.visible` and the prompt fix clears one Label —
  neither touches money, rep, stats, board, or log counts (hazard 17).
- Byte-identical bot curves are therefore expected but NOT verified by me.
- `docs/ROADMAP.md` was already modified and `.mimosa/` untracked before I
  started (not mine, left untouched).

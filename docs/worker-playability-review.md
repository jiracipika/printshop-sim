# Playability audit and first implementation brief

Date: 2026-11-17. Source baseline:
`a74f0ae7ef685cbef356552f796f93cbdecff43f` on `jiracipika/printshop-sim`.
Role: Astra design, architecture, and review. This is a source review and bounded
implementation plan, not an implementation or release report. No gameplay source
or tests were changed by this review. The reviewed Main.gd fetched from main was
compared with the file fetched explicitly at a74f0ae and was identical.

## Evidence boundary

- Verified below means verified in source/control flow, not observed in a live
  game. The listed line numbers refer to the baseline, before any patch.
- The parent reports live-browser startup blocked by Missing WebGL2. No current
  browser playthrough, pointer-lock verification, visual-readability assessment,
  or frame-rate acceptance was completed by this reviewer.
- The available local engine is 4.6.3; repository documentation pins 4.7.1.
  Native diagnostic tests with 4.6.3 are not release validation for 4.7.1.
- Parent independently reports: headless import exited 0; sequential ladder
  filter `spool|grab|input_pause|walkin|v034_station|v037` completed with
  `LADDER_DONE total=6 failed=0`, with no SCRIPT ERROR/Parse Error detected by
  the runner. These are existing diagnostic suites, not tests of a fix; no
  implementation exists yet. This reviewer did not rerun those commands.
- AGENTS.md requires glm-5.3-flash through the user's Z.AI coding-plan route for
  implementation. The parent found no available routing tool or executable.
  Implementation is blocked until that route is verified or the user explicitly
  overrides the project implementation-model requirement. No substitution made.

## Findings, in player-impact order

| Priority | Verified source behavior | Player consequence / confidence |
| --- | --- | --- |
| P0 | Desktop E and gamepad A enter `_try_grab_or_place` (Main.gd:2815-2825); touch does too (2754-2757). With a held object, it delegates to `_try_interact` ONLY for a part near packing/counter; otherwise it calls `_try_place` (2547-2560). Loading a held spool exists only in `_try_interact` (4570-4575). | The normal input path cannot load a spool although the HUD explicitly offers E to load (4696-4699). It attempts placement instead. This breaks the replenishment loop after opening filament is spent. Control-flow verified; runtime reproduction pending. |
| P0 | The same held-object bypass excludes the showcase action (4531-4537). The showcase test stand point `(2.5, 0.3, -2.1)` is within the shelf radius but outside packing/counter radii. | E attempts to put the held part down instead of copying it to the showcase. Finishing reaches its special action only incidentally where the packing-radius carve-out overlaps. Control-flow and geometry verified. |
| P1 | Main.gd:4642 describes a packing-table nudge, but 4643-4648 has no station/selected-printer guard. It scans every machine and returns when any inspected contract has a valid physical part. | Dropping one completed part can prevent empty-handed interactions with other printers. Existing `_collect_on(idx)` already handles a dropped part on its own machine (3736-3738); the global preemption is unnecessary. Control-flow verified. |
| P1 | `_collect_on` tells all single-copy jobs to go to packing (3770-3771). `_grab_prompt_line` advertises Pack & deliver for all held parts in packing range (4690-4695). The walk-in action explicitly refuses packing and requires the counter (4558-4563). | A walk-in customer has limited patience, but the game sends the player to a station that refuses the order. Prompt/action contradiction verified. |
| P1 | Accept initializes `orient = 0`, pending false (4285-4286). The first prep press increments it before preview (4186-4189). Orientations are upright, tilted, flat_side. A valid pending preview is confirmed on the next E; only an invalid one cycles (4191-4195). Both preview and HUD promise E to cycle AND E to confirm (4237, 4906). | Normal play starts at tilted and provides no working choice to cycle away from a valid tilted preview. Upright's lower material/risk option is not selectable through the advertised flow. Verified; retain for a separate control-design slice. |
| P1 | Opening balance is $25 (694), Printer 1 has 1500g (1291), procedural jobs reach 400 layers and $24 material fees (Contract.gd:399, 407-409). Tilted needs floor(layers * 8.4)g (PrepSystem). Insufficient filament/funds leaves the contract in PREPARING (4196-4207). | A player can accept work they cannot finance, occupies the only unlocked machine, and is told to deliver something first. A starting loose spool exists (700), so do not claim every large first order is an unavoidable soft lock; it is currently also blocked by the input bug above. No explicit cancel/recovery action was found in the reviewed flow. Older HANDOFF records an actual stuck session; current fresh-save reachability still needs reproduction. |
| P2 | Printer selection uses nearest player-to-printer distance within 3m (3324-3332), unlike grabbables/design computer which use an occluded camera ray (2465-2476, 4708-4716). HUD action lines use the last `_focus`, while pressing E resolves nearest printer (4933-4949 vs 4649-4653). | Looking at one machine can operate another or show an action for the previous machine. Camera-facing/occlusion dissatisfaction is inferred from the rules; exact troublesome positions require runtime coverage. |

The economy already has many systems: physical stock, fees, rent, power, wear,
grades, deadlines, loyalty, reputation tiers, walk-ins, upgrades, and ranks.
The immediate design priority is making the existing loop understandable and
reachable through real controls, before adding another progression system.

## Why the existing green suites can miss this

This is a test-boundary issue, not a claim that the tests are worthless:

- `tests/spool_test.gd:54-73` buys and loads using `_try_interact()` directly;
  loading at line 63 bypasses the normal held-object dispatcher.
- `tests/v037_test.gd:90-92` collects and showcases through `_try_interact()`.
- `tests/walkin_test.gd:103,108` directly collects/hands over with
  `_try_interact()`; this verifies settlement but not misleading carry guidance.
- `tests/parallel_test.gd:91-109` collects and immediately delivers each part;
  it does not leave one on the floor while trying a second printer.
- Several prep fixtures set `orient = 0` and `orient_pending = true` before
  `_prep_on()`, e.g. v037_test.gd:83-85. This correctly tests upright simulation,
  but does not demonstrate that a player can select upright.

Keep the simulation/ledger pinning tests. Add a small input-route regression
suite at the public callbacks; a browser input pass remains a separate gate.

## First bounded implementation slice: make E perform the offered action

Player outcome: a bought or grabbed spool actually loads, a carried part can be
showcased, walk-in orders tell the player to use the counter, and a dropped part
does not stop work on another machine.

Allowlist (five files total, including parent handoff):

1. `scripts/Main.gd`: dispatcher, held-item prompt text, collect destination,
   removal/scoping of the global inspected-part preemption only.
2. `tests/interaction_dispatch_test.gd`: new bounded regressions below.
3. `scripts/Version.gd`: one patch bump after independent acceptance.
4. `docs/worker-interaction-dispatch.md`: actual worker evidence and limitations.
5. `docs/HANDOFF.md`: parent-only continuity update after review.

Target budget: roughly 70-100 changed gameplay lines and 140-190 test lines,
under approximately 300 changed source/test lines. Stop and split if exceeded.
`tools/ladder.sh` already discovers `tests/*_test.gd`; no runner edit is needed.
Do not change economy formulas, payouts, saves, geometry, input bindings, or
orientation controls in this slice. Do not fix targeting by rewriting Main.gd.

Implementation constraints:

- Route held-object input through the existing ordered `_try_interact` actions,
  whose final held-object fallback already places it. Keep empty-hand ray grab
  precedence. Preserve pause/pointer-lock/touch gates. Avoid two independent
  dispatchers with growing lists of special cases.
- Preserve action priority: finishing, showcase, walk-in counter handover,
  packing/scrap, spool load, then generic placement. Preserve counter-before-
  crate ordering for empty hands. Do not accidentally buy while hands are full.
- Remove the global dropped-part preemption, or scope the explanation to the
  selected station/machine so it cannot block an unrelated printer. Existing
  `_collect_on` must still prevent duplicate part creation for its own job.
- Make held-part contextual text follow the same station priority. A walk-in
  part names its client and counter; at packing it directs back to the counter
  rather than advertising payment. Board parts keep packing instructions.
  Respect the existing scrap exception at packing. Collect-result prompts must
  use the same destination rule. Finishing/showcase should advertise the action
  that pressing E will take; already-finished/full/duplicate explanations remain.
- Do not extract a general interaction framework in this patch. A later target
  resolver can unify selection after its geometry and accessibility design is
  reviewed with a working browser.

### Required regression scenarios

Use isolated BrowserSave test state, explicit player position/yaw/pitch, release
input between presses, and settle physics frames. Close the boot menu before
simulated play. Call `_unhandled_input` with a pressed, non-echo E InputEventKey
for at least the loading path; use `_on_touch_interact` and the gamepad A callback
path for equivalent smoke cases. Calling `_try_interact` directly is insufficient
for the behaviors being fixed. Direct simulation setup is allowed to arrange
completed jobs cheaply, but the action under test must traverse the public path.

1. At unlocked Printer 1 holding a known-color spool, the HUD offers load; E
   increases stock by exactly 1500g, changes color, consumes the spool once,
   leaves no dropped spool, and does not charge another purchase fee.
2. At a locked printer, attempted load leaves the same object held and stock
   unchanged, with a locked explanation. Do not silently place it.
3. Held spool away from printers follows valid placement; invalid placement
   retains it. Empty-hand aimed grabbable still grabs before station actions.
4. At `(2.5, 0.3, -2.1)` holding an inspected board part, normal input adds one
   showcase model and preserves the original in hand/contract. Repeating the
   press does not duplicate the model. Prompt offers showcase at this position.
5. Held inspected part at finishing uses finishing; at packing delivers once;
   at an ordinary floor location places. These guard priority/fallback changes.
6. Collect a walk-in part through the input callback: collect prompt and carry
   HUD name the counter. At packing, E refuses without crediting or consuming;
   at the counter, touch interaction pays once and consumes the part. Verify a
   board part still says packing and an F-flagged walk-in scrap retains scrap
   behavior. Fixture setup may call the internal accept seam.
7. Arrange a valid placed inspection part for Printer 1, hands empty, then stand
   at an unlocked Printer 2 outside packing/counter/crate/radio zones. E must
   accept/advance Printer 2's job without touching Printer 1's part. Returning
   to Printer 1 cannot create a second copy. Aim away from the dropped part so
   the empty-hand ray-grab is not the intended action.
8. Repeat a representative held action paused, then unlocked with touch motion
   disabled: no state change. Exercise keyboard, touch and gamepad entry routes
   across the cases, without claiming this proves OS/browser input delivery.

Acceptance: new suite passes three consecutive sequential runs; full ladder
and existing build tests pass on the pinned engine; early/late simulation curves
remain unchanged. No concurrent Godot processes. Inspect actual check counts and
SCRIPT ERROR/Parse Error, not exit code alone. Then perform a real browser
buy/load -> print/collect -> showcase -> pack loop, plus a walk-in counter order,
using ordinary controls. Record actual build ID and artifacts. Browser failure
is a blocked release gate even if native tests pass.

## Follow-up roadmap

1. **Usable preparation and a reliable first sale.** Separate selection from
   confirmation using explicit visible controls, default to upright, show grams,
   remaining stock and fee together. Retain deterministic simulation. Give a
   fresh shop a feasible introductory order and a short first-sale objective;
   check the complete path with real input rather than force-setting prep state.
   This changes balance/fixtures and needs its own reviewed slice.
2. **Recovery before more pressure.** Add a clear pre-print cancel/return action
   with no duplicated refund, and an explicit deterministic emergency route when
   no printable/affordable job remains. Design the zero-cash, no-stock case,
   repeat use, debt repayment, and save/reload before implementation. A cancel
   action alone does not solve total insolvency. Explain fees separately from
   filament; show actionable shortfalls instead of 'deliver something first'.
3. **One target, one action.** Define a shared camera-facing, range- and
   occlusion-aware station target used by both hint and action, with generous
   touch/gamepad tolerance. Highlight/name the selected station. Review dense
   counter/crate and finishing/packing overlaps before changing the current
   proximity contract; retain explicit tests for those overlaps.
4. **Reduce the HUD to decisions.** Show current objective, selected station,
   relevant job/stock and one next action. Keep economy detail in the existing
   Today/Contracts/Stats panels. Separate progress feedback from persistent
   interaction text. Assess 1280x720 and touch readability in actual frames.
5. **Make choices rewarding after the loop works.** Add a small number of
   customer requests with visible tradeoffs and a meaningful preview/quality
   response, then tune early wear/rent/deadlines around observed human sessions.
   Reuse current clients, counter, grades and upgrades rather than stacking more
   largely invisible rank multipliers. Targets are design proposals, not measured
   fun or retention improvements.

## Boundary / next action

Independent parent diagnostics (2026-11-17):

- `godot --headless --path . --editor --import --quit`: exit 0, no
  SCRIPT ERROR/Parse Error in the captured import log.
- `GODOT=/usr/local/bin/godot LOGDIR=/tmp/printshop-audit-logs bash
  tools/ladder.sh 'spool|grab|input_pause|walkin|v034_station|v037'`:
  exit 0; `LADDER_DONE total=6 failed=0`. Each suite's log was also checked
  for SCRIPT ERROR/Parse Error. No production code changes were involved.
- Engine: `4.6.3.stable.official.7d41c59c4`; diagnostic-only boundary applies.
- Live browser: verified loader error for missing WebGL2 at
  `https://printshop-sim.vercel.app/`; no gameplay acceptance claimed.
- No fresh export, full ladder, bot curve comparison, or deployment was run.

Design review complete; implementation not started. Restore verified GLM coding-
plan routing or obtain the explicit model override, then issue only the first
slice above. Parent owns runtime diagnostics, tool/blocker reporting, handoff,
and any authorized review-branch publication. No commit, push, deployment or
release verification was performed by this reviewer.

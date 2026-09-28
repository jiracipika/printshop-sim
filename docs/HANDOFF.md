# Current handoff — blueprint-shaped print visuals (v0.5.0, pending merge)

## Current active work

The merged design-computer slice adds a world-space workstation target on
the back bench. E opens an offline-safe Form Lab with three editable starting
shapes, width/depth/height, wall thickness, layer height, infill, PLA/PETG,
filament color, live 3D preview, and filament/time/cost estimates. Test Print
saves the blueprint, charges filament, runs on an idle unlocked printer, and
can be collected as a physical grabbable object. This iteration grows the
chosen profile on the plate: hollow planters start with a solid base, rings
follow their loop, and blocks keep their dimensions. Fine shader ridges use
the selected layer height and filament finish; the gantry rises with the
print.

Local verification on Godot 4.7.1: all 20 Godot suites pass (885 checks),
including the design-computer and expanded printer-visual checks; `python3 -m pytest
tests/test_build_web.py -q` passes (21 tests). Import prints an existing
export-preset warning for missing `preset.1/exclude_filter`, but exits 0.
No Web export, visual browser test, deployment, or release was performed.

Next iteration: inspect the editor and live print in a browser build, then
polish any layout or material issues found. Preserve GL Compatibility and the
existing suite gates.

---

# Previous handoff — reputation + stats + salvage (v0.5.0)

Read AGENTS.md and design/implementation-plan.md. Working copy:
/Users/rs-mac/.zcode/workspace/default/printshop-sim (canonical disk plan in
HANDOFF pointed at /Volumes/HARD previously; this workspace copy is the live
one for the v0.1.0 release). Private remote
https://github.com/jiracipika/printshop-sim, main. Public prototype
https://printshop-sim.vercel.app/.

## State at this checkpoint

v0.13.0 (print farm) shipped on top of v0.12.0: the shop gained a rear
extension (own floor/walls/ceiling/lights) behind a sealed honey door in the
back wall (doorway x 0.9-2.3; door panel swings and its collision disables
when either farm kit is owned). Machines grew to 4 — printers 3 and 4 sit
on stands in the farm and unlock via new Upgrades "farm_kit_a" ($80) /
"farm_kit_b" ($120) with per-machine machine_unlocked(idx); all four
idx==1 special cases were generalised (accept/load/design-computer gates
now use the helper). Farm printers ship EMPTY and have no speed bonus
(Pro stays exclusive to printer 2). Save filament/color arrays now cover
all machines. New suite tests/farm_test.gd (20 checks); all 27 suites
green (1027 checks). Audit note: the extension lighting was tuned twice
(omnis 1.4/1.0 energy) — still moodier than the main room by design.

v0.12.0 (balance pass) shipped on top of v0.11.0, driven by a read-only
economy audit (background research agent; full findings were reported to the
operator — week-1 gross ~$4,120 at >90% margins, upright unconditionally
safe, deadlines never binding, material cost never charged). Changes:
GEN_BASE_PAYOUT[4] 15500->9000, diff-4 11600->9800, payout cap 15000->9500,
rush premium 1.4->1.2, PrintSim failure floor 0.4->0.3 (upright+overhangs
now carries ~2.75% real risk), material_cost_cents charged at confirm again
(can_afford gate, stays PREPARING when broke), rent = $9 + $2x(day-1) capped
$25 (day/holiday/cold-snap aware), same-day tip 15%->10%, JobBoard capacity
cached, crate rotation persisted ("crate_next" validated). See
docs/ROADMAP.md Slice 1 for the checklist; slices renumbered v0.13-v0.20.
All 26 suites green (1005 checks); prep_test replicates the new floor.

v0.11.0 shipped on top of v0.10.0: weekly seasons (Events.season_for_week,
week = (day-1)/7+1, week 1 calm; humid +0.05 adhesion in _prep_eval,
cold_snap +$1 rent in _on_day_changed, boom payout x1.10) refreshed together
with the daily event; payout order is grade -> reputation -> season -> event
-> late half -> same-day tip (+15% when delivered the accept day), all in one
Main._finalize_payout(base, late, m, rep=-1) helper that tests call with the
pre-delivery reputation. A chalkboard ledger (left wall, live Label3D,
change-cached) shows day/delivered/earned/rep. New suite tests/v011_test.gd
(16 checks); all 26 suites green (1021 checks).

v0.10.0 (art pass) shipped on top of v0.9.0: ShopArt gained size parameters
(512px detail variants for floor/walls/wood with plank gaps, knots, stains
and scuffs; cached separately) plus pegboard, bed_grid and calendar
generators. Printers got a build-plate grid and a front LCD status screen
(set_status: Ready / Lx/y % / Done / ERROR — clear), driven from
_update_print_visuals. Main dressed the shop: baseboards on all four walls,
pegboard + three tools above the bench, wall calendar, power strip + cables
to both printers, windowsill, pendant cords, trash bin (with collision),
tape rolls + scale on the packing table, a second plant, and a teal glow
light on the design computer. New suite tests/art_pass_test.gd (16 checks);
all 25 suites green (989 checks).

v0.9.0 (guided objectives) shipped on top of v0.8.0: a seven-step onboarding
chain (accept, print, collect, deliver, load a spool, print a prototype, 4★
reputation) tracked order-agnostically in guide_flags from the real loop
event points, shown as "▸ Objective: ..." in the HUD, persisted via
"guide_flags"/"guide_done" (validated), and retired when complete. Settings
gained a two-press "Reset shop (new game)" button (arm -> confirm -> save
wipe + scene reload; disarm on leaving settings). Play-flow fix that fell out
of the guide tests: collecting the part (contract or prototype) now resets
that printer to IDLE immediately, and the pack grade reads a machine
"grade_snapshot" captured at collect time instead of live sim fields.

v0.8.0 (color demands) shipped on top of v0.7.0: contracts (fixtures and
generated) demand a filament color (Contract.color, valid set =
DesignStudio's Clay/Sage/Honey); the crate cycles colors deterministically
(_crate_next, sign shows the next color + today's price) and each buy sets
the spool's meta; loading sets the machine's color (shown in the HUD
filament line); a mismatch caps the delivery grade at B via
Main._cap_grade_for_color (single source of truth shared with tests; applied
after PackingStation grades, before reputation/event/late). Machine colors
persist in the save ("spool_colors", validated). New suite
tests/color_test.gd (27 checks); all 23 suites green (952 checks).

v0.7.0 (daily events) shipped on top of v0.6.0: Events.for_day(day) deals a
deterministic event per shop day (day 1 always quiet; from day 2 a hashed
pool of filament_sale $8 spools, rush_week payouts x1.25, power_hiccup
failure threshold +0.10, rent_holiday, and quiet). Main applies them: crate
price + sign text, payout multiplier (order: grade -> reputation -> event ->
late half), failure threshold delta (clamped with upgrades), rent skip in
_on_day_changed (holiday skips ONLY the charge — cancellations still run;
the early version of that branch skipped the whole rollover and was caught
by parallel_test). HUD shows "Today: <event>". New suite tests/events_test.gd
(15 checks); all 22 suites green (940 checks).

v0.6.0 (spool economy) shipped on top of v0.5.0 + the concurrent design-
computer commits (80f18ae, 6e6b349 — note: those sessions share this clone;
ALWAYS git pull --rebase before pushing and re-grep files before patching,
their edits landed mid-slice and silently voided three of my patches):
filament is physical now. Machines carry filament_g (printer 1 opens with a
1500 g spool; printer 2 ships loaded when bought); confirming a prep (or
sending a design-computer prototype) consumes the estimate in grams and
refuses while short (job stays PREPARING, E re-confirms after a load); the
spool crate (front-left corner, $12, tight 1.6 m radius) sells spools into
your hands; E while holding a spool at a printer loads it (meta "spool"
tagging, not names — name collisions auto-rename); failed-print clears
salvage half the consumed grams back onto the spool; printers render a
shrinking coil; HUD shows per-machine grams; filament persists in the save
("filament" validated array). Stats panel gained computed milestone
achievements (First sale, Ten orders, Five stars, Fully kitted, Week one,
High earner). debug_spawn_test_print tops up filament (dev seam). New suite
tests/spool_test.gd (23 checks); all 21 suites green (932 checks).

v0.5.0 shipped on top of v0.4.0: reputation (0-5, start 3; on-time +0.2,
late -0.2, scrap -0.4, cancel -0.6) scales payouts x0.8-x1.2
(Main.reputation_multiplier(); order: grade -> reputation -> late half) and
shows as stars in the HUD. Lifetime stats (delivered/late/scrapped/cancelled/
earned_cents) persist and render in a new menu Stats panel. Clearing a failed
print salvages half its material cost (machine dict carries material_cents
from confirm). Three new upgrades: Textured PEI plate ($35; Main._prep_eval
unlocks flat_side on stability parts — PrepSystem stays pure), filament
dryer ($45, adhesion -0.10) and print enclosure ($120, stability -0.25);
risk modifiers stack and Main clamps to [0,1]. Contract-board cards show the
deadline ("· Nd"). Save payload gained optional "reputation" (0..5) and
"stats" (non-negative int counters), validated. New suite
tests/features_test.gd (31 checks); all 19 suites green (890 checks).

v0.4.0 shipped on top of v0.3.0: the live shop's board is procedurally
generated per shop day (Contract.generate(day, slot), fully deterministic,
materials capped at $24 so day 1 is always confirmable, rush ~25% of the
board at 1.4x and <= 2-day deadlines, day 1 leans easy). JobBoard.generation_enabled
(default false keeps fixture behavior for direct-board suites) +
rotate_day(new_day) on every day rollover and save restore. Polish, all
Compatibility-safe: glow (emissive fixtures/labels bloom), sun shadows with
a Settings "Directional shadows" toggle (persists; for slow devices), soft
vignette overlay (non-blocking), and a How-to-play menu panel explaining the
loop, the clock and the shop. New suite tests/gen_test.gd (24 checks).
Android: builds/printshop-sim.apk exports unsigned from this workspace with
just the installed export templates (docs/mobile.md documents sign+install;
the SDK/apksigner toolchain lives on /Volumes/ADATA and was not mounted, so
signing remains a human step).

v0.3.0 shipped on top of v0.2.0: (a) contract variety — the fixture pool
doubles to 8 jobs (C-014..C-021; original four stay first/in order), with two
rush fixtures (deadline <= 2 d, ~1.4x payout) tagged RUSH on the board card;
summaries carry "rush". (b) True parallel printing — Main owns a `machines`
array ({idx, sim, contract, day, orient, orient_pending, part, scrap}); each
machine accepts/prepares/prints/fails/delivers independently; the held part
identifies its machine via part_contract id; legacy single-machine vars
(sim/active_contract/orientation_*/active_part) are properties over the
FOCUSED machine (last printer interacted with) so tests and the debug panel
work unchanged; _on_print_started/done now take a machine index. New suite
tests/parallel_test.gd (23 checks). PrintSim.tick gained a reentrant-
completion guard (large deltas no longer overshoot layers_total or emit
print_finished twice).

v0.2.0 (shop day) shipped on top of the completed v0.1.0 contract loop:
DayCycle drives a 90 s day with day/night lighting (sun energy/color, ambient,
sky energy); each rollover charges $4.00 rent (unaffordable rent accrues as
debt; payouts repay debt first via _repay_rent_debt); contracts anchor a
deadline at accept — late delivery pays 50%, and a contract more than one day
past deadline is cancelled at rollover (contract FAILED, sim torn down, part
discarded). Printer 2 is the purchasable Pro machine (upgrades id
"pro_machine", $60): locked with a LOCKED tag until bought, jobs accepted
there run at 1.25x machine speed. Day persists in the save ("day" optional
payload key, validated int >= 1). New suite tests/day_test.gd (36 checks);
upgrades_test updated for the 5-entry catalog.

All implementation-plan tasks 00-12 are implemented and integrated. The full
loop is playable: accept at a printer -> orientation prep (upright/tilted/
flat_side with support %, material estimate, risk level; flat_side refused on
stability parts) -> material charge on confirm -> visible layered print growth
on the bed -> risk-driven deterministic failures (clear the bed with E before
the next job) -> collect the physical part -> carry it to the packing table ->
pack & deliver (A/B/C/F grade via QualityCheck, grade-scaled payout, F scrap
path) -> exactly-once ledger payout. Upgrades shop (4 items with real sim
effects), settings panel (sensitivity/volume/invert-Y, write-through on menu
close), versioned save covering balance/upgrades/settings with corruption
fallback. Art pass: runtime-procedural textures (plaster/plywood/tiles/steel/
cardboard/posters/rug), procedural sky + fog, ceiling fixtures, window,
props (spool shelf, crates, plant, ticking wall clock), center reticle,
synthesized SFX + printer hum on an "SFX" bus.

Verification evidence (local): 27 Godot headless suites green — contract 255,
color 27, events 15, v011 16, guide 21, art_pass 16, farm 20, spool 23,
gen 24, features 31, upgrades 57, packing 58, touch 47, save 44, shop_art 51,
economy 54, day 37, design_computer 21, parallel 23, prep 29,
printer_visual 34, grab 26, input_pause 23, menu 25, debug_panel 32, room 9,
smoke 9 (1027 checks, 0 failures, no SCRIPT ERROR); Python build pipeline 21
pytest; engine screenshots confirm the sealed door and both farm printers
running in the extension.

v0.1.0 RELEASED: commits 2f1f2af (loop/features) + ab05cc4 (shell help
placement). Deployed to https://printshop-sim.vercel.app/ via vercel --prod;
live build-info.json reports git_sha ab05cc4, version 0.1.0, source clean;
index.js/wasm/pck all 200 with correct content types (application/wasm).
Live browser (ZCode IAB, 1280x720): cold load, WASM boot, WebGL render, main
menu with correct version label, Play -> gameplay HUD (balance $25.00, jobs
waiting 4) and capture prompt all verified via screenshots. Pointer lock is
not grantable in the embedded automation browser, so the full in-browser
contract loop was verified in-engine (same build, captured screenshots);
physical-device and cross-browser matrix remain open.

## Known quirks (accepted)

- Headless tests drive the sim via sim.tick(); real-time prints take
  layers*0.1 s / speed multiplier (C-014 upright ~21 s).
- The completed print visual stays on the bed until collected/failed-cleared
  or the next print starts (intentional: it's the thing you pick up).
- DebugPanel [1] spawn confirms "upright" automatically via the real path.

## Remaining work is HUMAN-ONLY (as of v0.4.0)

- Hands-on playtesting/balance (deadline tuning, payout curves, feel).
- Physical device testing: Android install/sign per docs/mobile.md (needs the
  /Volumes/ADATA toolchain mounted), iOS/Android touch behavior, performance
  on real hardware.
- Cross-browser matrix (Firefox/Safari) and limited-bandwidth checks on the
  live URL.
- App-store signing/distribution decisions (debug keystore is committed; do
  not ship it).

Everything code-side is implemented and automated-tested.

## Operator notes

- Build: bash tools/build_web.sh (stamps Version.gd with HEAD sha; export
  validated; build-info.json written). Serve web/build/ over HTTP, never file://.
- Deploy: vercel --prod from the repo (vercel.json serves web/build). Verify
  the live URL loads the stamped build and plays before calling it released.
- Never touch automated-newsletter or pitchforge/pitch-therapy.

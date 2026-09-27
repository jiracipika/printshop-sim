# Current handoff — reputation + stats + salvage (v0.5.0)

Read AGENTS.md and design/implementation-plan.md. Working copy:
/Users/rs-mac/.zcode/workspace/default/printshop-sim (canonical disk plan in
HANDOFF pointed at /Volumes/HARD previously; this workspace copy is the live
one for the v0.1.0 release). Private remote
https://github.com/jiracipika/printshop-sim, main. Public prototype
https://printshop-sim.vercel.app/.

## State at this checkpoint

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

Verification evidence (local): 19 Godot headless suites green — contract 255,
gen 24, features 31, upgrades 55, packing 58, touch 47, save 44, shop_art 51,
economy 54, day 36, parallel 23, prep 29, printer_visual 28, grab 26,
input_pause 23, menu 25, debug_panel 32, room 9, smoke 9 (859 checks, 0
failures, no SCRIPT ERROR); Python build pipeline 21 pytest; engine
screenshots confirm the HUD reputation stars, Stats panel and card due tags.

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

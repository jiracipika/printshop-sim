# Current handoff — full contract loop (v0.1.0)

Read AGENTS.md and design/implementation-plan.md. Working copy:
/Users/rs-mac/.zcode/workspace/default/printshop-sim (canonical disk plan in
HANDOFF pointed at /Volumes/HARD previously; this workspace copy is the live
one for the v0.1.0 release). Private remote
https://github.com/jiracipika/printshop-sim, main. Public prototype
https://printshop-sim.vercel.app/.

## State at this checkpoint

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

Verification evidence (local): 15 Godot headless suites green — contract 170,
packing 58, touch 47, save 44, shop_art 51, upgrades 51, economy 54, prep 29,
printer_visual 28, grab 26, input_pause 23, menu 25, debug_panel 32, room 9,
smoke 9 (656 checks, 0 failures, no SCRIPT ERROR); Python build pipeline 21
pytest; real Web export via tools/build_web.sh (all four artifacts served,
application/wasm correct); engine screenshots captured at 1280x720 (menu,
spawn, mid-print, holding part, packing table) confirm visuals and HUD.

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

## Next features (not started)

- Deadline/day tracking consequences (deadline_days shown in HUD, no
  consequence yet).
- Second printer as purchasable machine; multi-job parallelism.
- Day/night cycle, ambient occlusion, shader polish (Compatibility-safe).
- Physical iOS/Android device validation; browser matrix; performance profile.

## Operator notes

- Build: bash tools/build_web.sh (stamps Version.gd with HEAD sha; export
  validated; build-info.json written). Serve web/build/ over HTTP, never file://.
- Deploy: vercel --prod from the repo (vercel.json serves web/build). Verify
  the live URL loads the stamped build and plays before calling it released.
- Never touch automated-newsletter or pitchforge/pitch-therapy.

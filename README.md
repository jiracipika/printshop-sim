# Print Shop Sim

Browser-first first-person 3D printing workshop prototype. Built with Godot 4.7.1 and GDScript, using GL Compatibility rendering and a single-threaded Web export. The eventual target is a downloadable PC game; the browser build is the testing surface.

## Play Current Build

https://printshop-sim.vercel.app/

The deployed version may lag local development. Check the in-game version/build label. Repository: https://github.com/jiracipika/printshop-sim (private).

## Current Milestone

Complete playable contract loop with the shop day, true two-machine parallel
printing, a procedural contract board, a reputation system, a physical spool
economy with color demands, daily shop events, and guided first-run
objectives (v0.9.0). Filament is real: printers hold grams from loaded
spools, every print consumes its estimate, failed prints salvage half the
grams back, and new spools come from the crate ($12). Accept a job, pick an orientation, print it, carry
the part to the packing table, deliver, get paid — against the clock: days
pass, rent comes due each day, late deliveries pay half, and clients cancel
after two extra days. Both printers can hold and print separate contracts at
the same time; printer 2 is a purchasable Pro machine that prints 25% faster.
The contract board is generated fresh every shop morning (deterministic per
day) with rush work paying a premium for 1-2 day deadlines. Menu has a
How-to-play screen and a Stats panel (lifetime deliveries, earnings,
reputation). Reputation (0-5 stars, shown in the HUD) scales every payout
x0.8-x1.2: on-time deliveries raise it, late work, scrapped parts and
cancelled jobs cost it. Failed prints salvage half their filament back.
Eight upgrades now include the Textured PEI plate (unlocks flat-side
printing on tippy parts), filament dryer and print enclosure (stacking risk
reductions). The look includes glow, sun shadows (toggleable in Settings for
slow devices) and a soft vignette.

Working in local automated tests (15 suites, 656 checks):
- Workshop enclosure, collision walls, workbench, two FDM printers (frame, bed,
  gantry, oscillating nozzle), packing table, spool shelf, posters, rug, wall
  clock, props, ceiling lights, window, procedural sky with gentle fog.
- Procedural textures everywhere (plaster walls, plywood, tiled floor, brushed
  steel, cardboard) — no external assets; web-export safe.
- First-person WASD/mouse movement, click-to-play, Escape/focus pause, center
  reticle; full mobile touch overlay (stick, look, Interact, Pause).
- Full loop: E at a printer accepts a contract, E previews/cycles orientation
  (support %, material estimate, risk level), E confirms and consumes filament
  from the loaded spool, the print grows visibly on the bed, failed prints are
  cleared (half the grams salvaged), finished parts are carried to the packing
  table, graded A/B/C/F, delivered for a reputation-scaled grade payout.
  Exactly-once payouts in an integer-cents ledger.
- Spool economy (v0.6.0): buy spools at the crate, carry and load them into a
  printer (E while holding), printers show a shrinking coil, HUD shows grams
  per machine, filament persists in the save. Milestone achievements render
  in the Stats panel.
- Daily events (v0.7.0): each morning brings a deterministic event — filament
  sale ($8 spools), rush week (payouts +25%), power hiccups (riskier prints),
  rent holiday, or a quiet day. Day 1 always opens quiet.
- Color demands (v0.8.0): clients want Clay, Sage or Honey; the crate cycles
  colors (sign shows the next), the loaded spool's color shows on the machine,
  and a mismatch caps the grade at B — right color, top payout.
- Guided objectives (v0.9.0): a HUD checklist walks new players through
  accept → print → collect → deliver → spools → design computer → reputation,
  persists, and retires when done. Settings gained a two-press
  "Reset shop (new game)" button; collected prints free the printer
  immediately for the next job.
- Art pass (v0.10.0): 512px plaster/wood/floor with plank gaps, stains and
  scuffs; baseboards; pegboard with tools; wall calendar; printer build-plate
  grid and live LCD status screens; cables and power strip; windowsill;
  trash bin; packing-table tape and scale; pendant cords; second plant;
  design-computer screen glow.
- True parallel printing: each machine owns its sim, contract, prep state and
  printed part; both can print, fail, and deliver independently (v0.3.0).
- Risk-driven deterministic failures (bad orientation can lose the print),
  F-grade scrap path, printer hum and synthesized SFX (grab, place, beep,
  chime, cash, buzz) on a dedicated audio bus.
- Upgrades shop (heated bed, dual-gear extruder, stiffened frame, premium
  nozzle, Pro machine unlock for printer 2) with real sim effects; settings
  panel (look sensitivity, volume, invert Y); versioned save with corruption
  fallback covering balance, upgrades, settings and the shop day.
- Shop day: a 90-second day with day/night lighting, $4.00 daily rent (unpaid
  rent accrues as debt that payouts repay first), contract deadlines — late
  delivery pays half, two days overdue the client cancels.

Pending (human-only):
- Hands-on playtesting and balance passes; physical iOS/Android device
  validation (unsigned Android APK builds via docs/mobile.md); browser matrix
  beyond Chromium; app-store signing/distribution.

## Controls

Desktop: click to play/capture, WASD to move, mouse to look, E to interact
(accept job / cycle+confirm orientation / collect part / pack & deliver at the
packing table / grab & place props), Escape for the menu (Contracts, Upgrades,
Settings), F3 dev panel in debug builds.

Mobile: tap Resume, left stick to move, drag right side to look, Interact for
everything above, Pause for the menu. Simultaneous movement/look is supported.

## Run from scratch

Install Godot 4.7.1 and its matching export templates. Clone the private repository using an authenticated GitHub account, then from the repository directory:

    godot --editor --path .

To launch directly:

    godot --path .

Verification (all 15 suites must pass):

    godot --headless --path . --editor --import --quit
    for t in tests/*_test.gd tests/smoke.gd; do godot --headless --path . --script "$t"; done
    python3 -m pytest tests/test_build_web.py -q

Use bounded runners and inspect logs for script/parse errors as well as exit status. Headless checks do not prove browser pointer lock, rendering, or mobile touch behavior.

## Web export and deployment

Create web/build/ then export the Web preset:

    godot --headless --path . --export-release Web
    python3 -m http.server 8766 --directory web/build

Open http://localhost:8766/ in a WebGL 2-capable browser. Do not open index.html with file://. Generated exports are excluded from Git. Vercel serves web/build via vercel.json; deployment requires a fresh complete local export. Automated push-to-deploy is not yet established. A successful deployment is not acceptance until the live browser loads the engine and gameplay/input are verified.

## Architecture

- project.godot / scenes/Main.tscn: configuration and main scene.
- scripts/Main.gd: procedural workshop, player, full contract loop, HUD.
- scripts/PrintSim.gd: print simulation state (risk-driven deterministic
  failures, upgrade speed multiplier, full reset).
- scripts/PrepSystem.gd: orientation/support heuristics; Contract.gd / Ledger.gd /
  JobBoard.gd: contract state machine, integer-cents money, job rotation.
- scripts/PackingStation.gd + QualityCheck.gd: grading (A/B/C/F) and delivery.
- scripts/Upgrades.gd: catalog + exactly-once purchases + sim effect helpers.
- scripts/SaveSystem.gd + BrowserSave.gd: versioned payload, corruption fallback.
- scripts/ShopArt.gd: runtime-procedural textures (no external assets).
- scripts/Sfx.gd: synthesized audio streams + SFX bus; scripts/Clock.gd: wall clock.
- scripts/MainMenu.gd: menu, contract board, upgrades shop, settings.
- scripts/Version.gd: build identification (stamped at export).
- tests/: 15 headless behavioral suites + Python build-pipeline tests.
- web_shell/: browser loader shell; web/build/: generated release artifacts.
- design/: concept mockups (concepts, not gameplay captures).
- docs/HANDOFF.md and AGENTS.md: persistent continuation instructions.

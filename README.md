# Print Shop Sim

Browser-first first-person 3D printing workshop prototype. Built with Godot 4.7.1 and GDScript, using GL Compatibility rendering and a single-threaded Web export. The eventual target is a downloadable PC game; the browser build is the testing surface.

## Play Current Build

https://printshop-sim.vercel.app/

The deployed version may lag local development. Check the in-game version/build label. Repository: https://github.com/jiracipika/printshop-sim (private).

## Current Milestone

**Print Shop 3.0 — The Front Counter (v0.61.0)**. The shop has a street
presence now: a front counter you can actually work, walk-in customers,
a living shopfront, and a career ladder that pays.

The 3.0 overhaul (v0.58-v0.61) on top of the 1.0-rc loop:
- Front counter (v0.58): a counter island with a desk bell and slip pad.
  Ring it when nobody waits; the counter settles deliveries at a +10%
  premium (walk-in orders only pay here).
- Walk-in customers (v0.59): deterministic hashed arrivals (up to 2/day)
  step through the door, wait at the counter on a patience clock, and
  leave quietly when it runs out. Two-press slip accept onto the first
  idle printer; single-part jobs that never touch the board. Served and
  lost walk-ins persist in the lifetime stats.
- Shopfront atmosphere (v0.60): the entry door swings open and closed
  for every arrival and departure, a billboarded OPEN placard lights up
  inside the business window (and drops its glow at Low quality), a warm
  pendant hangs over the counter, clutter dresses the top, customers
  wear hashed caps and scarves, and the HUD wears the shop's ink/paper/
  clay/gold palette — all inside the strict draw-call budget.
- Shop rank (v0.61): five derived career levels (Sprout, Staple, Known,
  Fixture, Institution) from lifetime deliveries and a reputation
  high-water mark. Each level above Sprout adds +2% to every payout;
  level-ups announce once (toast, workshop log, chalkboard header) and
  the menu Stats panel tracks the next gate. Three rank milestones.

Below 3.0, the 1.0-rc loop still stands: accept jobs from a
deterministic procedural board, pick an orientation, print, carry the
part to the packing table, deliver, get paid — against the clock with
rent, deadlines, reputation and a filament economy.

Highlights of the 1.0-rc loop:
- Print farm (v0.13): rear extension with printers 3 & 4 behind a sealed
  door, unlocked by the farm kits; true parallel printing across 4 machines.
- Balance pass (v0.12) from a full economy audit: flattened payouts,
  real material charges, steeper rent, meaningful rush premiums.
- Board pressure (v0.14): first come, first served — rush and competing
  offers expire overnight (reputation cost); Reserve pins a job.
- Workshop log (v0.15): 30-event ring buffer with failure forensics
  ("support collapse at layer 34") in a Log menu panel.
- The radio (v0.16): runtime-synthesized lo-fi loop on its own Music bus,
  E-toggle radio prop, design-studio ducking, printer servo blips.
- Weather (v0.17): seasons paint the window — humid haze + rain streaks,
  cold-snap frost, golden booms; HUD weather icons.
- Multi-part orders (v0.18): ×2/×3 production runs with partial packs
  stacking on the table, reprint flow, and order-grade aggregation
  (single F caps at C, two F kill the order).
- Reputation tiers (v0.19): the board gates job difficulty by star tier,
  rush premiums scale +10%/tier, tier-ups announce once, new achievements.
- Hardening (v0.20): Low/Standard/High quality presets (shadows + glow),
  portrait-safe HUD reflow, draw-call budget, touch targets >= 48 px.

Filament is real: printers hold grams from loaded spools, every print
consumes its estimate, failed prints salvage half the grams back, and new
spools come from the crate ($12). Reputation (0-5 stars) scales every
payout x0.8-x1.2; missed board offers, late work, scrapped parts and
cancellations cost stars. Days pass (~90 s), rent comes due each morning,
late deliveries pay half, and clients cancel after two extra days.

Working in local automated tests (74 headless suites + 2 deterministic
bot harnesses — a full ladder run `bash tools/ladder.sh --bots` must end
`LADDER_DONE total=77 failed=0`, incl. a full delivery loop at Low
quality, walk-in/counter/rank behavior, portrait-HUD and draw-call
budget audits):

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

Open http://localhost:8766/ in a WebGL 2-capable browser. Do not open index.html with file://. web/build is tracked in Git because Vercel serves it straight, so a release commit includes the fresh export. Vercel serves web/build via vercel.json; deployment requires a fresh complete local export. Automated push-to-deploy is not yet established. A successful deployment is not acceptance until the live browser loads the engine and gameplay/input are verified.

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
- scripts/CounterStation.gd / CounterService.gd / CustomerActor.gd /
  ShopFront.gd: front counter island, walk-in arrival/patience logic,
  customer actors, shopfront dressing (Print Shop 3.0).
- scripts/ShopArt.gd: runtime-procedural textures (no external assets).
- scripts/Sfx.gd: synthesized audio streams + SFX bus; scripts/Clock.gd: wall clock.
- scripts/MainMenu.gd: menu, contract board, upgrades shop, settings.
- scripts/Version.gd: build identification (stamped at export).
- tests/: 74 headless behavioral suites + 2 deterministic bot harnesses
  (sim_playtest / sim_lategame) + Python build-pipeline tests; see
  tools/ladder.sh.
- web_shell/: browser loader shell; web/build/: generated release artifacts.
- design/: concept mockups (concepts, not gameplay captures).
- docs/HANDOFF.md and AGENTS.md: persistent continuation instructions.

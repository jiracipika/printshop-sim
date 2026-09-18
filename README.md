# Print Shop Sim

Browser-first first-person 3D printing workshop prototype. Built with Godot 4.7.1 and GDScript, using GL Compatibility rendering and a single-threaded Web export. The eventual target is a downloadable PC game; the browser build is the testing surface.

## Play Current Build

https://printshop-sim.vercel.app/

The deployed version may lag local development. Check the in-game version/build label. Repository: https://github.com/jiracipika/printshop-sim (private).

## Current Milestone

Workshop foundation. Not yet a complete tycoon or contract-delivery loop.

Working in local automated tests:
- Workshop enclosure, collision walls, workbench and two placeholder printers.
- First-person WASD/mouse movement.
- Click-to-play and Escape/focus-loss pause behavior.
- Printer interaction starts a queued job; simulation progress and material usage appear in the HUD.

- Mobile touchscreen movement, look, Interact and Pause controls (Chromium emulation checked; physical-device testing pending).

In progress:
- Release of the latest changes and physical-device validation.

Next:
- Grabbing and placement.
- Convincing printer geometry and visible print progression.
- Model preparation, meaningful failures, packaging and contract payouts.

## Controls

Desktop: click to play/capture, WASD to move, mouse to look, E near a printer to start a job, Escape to release/pause.

Mobile: tap Resume, use the left stick to move, drag the right side to look, tap Interact near a printer, and tap Pause to stop. Simultaneous movement/look is supported. Touch behavior is covered by headless tests and Chromium mobile emulation; physical iOS/Android testing remains pending.

## Run from scratch

Install Godot 4.7.1 and its matching export templates. Clone the private repository using an authenticated GitHub account, then from the repository directory:

    godot --editor --path .

To launch directly:

    godot --path .

Verification:

    godot --headless --path . --editor --import --quit
    godot --headless --path . --script tests/room_boot_test.gd
    godot --headless --path . --script tests/input_pause_test.gd
    godot --headless --path . --script tests/smoke.gd

Use bounded runners and inspect logs for script/parse errors as well as exit status. Headless checks do not prove browser pointer lock, rendering, or mobile touch behavior.

## Web export and deployment

Create web/build/ then export the Web preset:

    godot --headless --path . --export-release Web
    python3 -m http.server 8766 --directory web/build

Open http://localhost:8766/ in a WebGL 2-capable browser. Do not open index.html with file://. Generated exports are excluded from Git. Vercel serves web/build via vercel.json; deployment requires a fresh complete local export. Automated push-to-deploy is not yet established. A successful deployment is not acceptance until the live browser loads the engine and gameplay/input are verified.

## Architecture

- project.godot / scenes/Main.tscn: configuration and main scene.
- scripts/Main.gd: procedural workshop, player, interaction and HUD.
- scripts/PrintSim.gd: print simulation state.
- scripts/JobBoard.gd: prototype job queue.
- scripts/Version.gd: build identification.
- tests/: headless behavioral checks.
- web_shell/: browser loader shell; web/build/: generated release artifacts.
- design/: cover, menus, HUD and workshop concept mockups plus design specification. These are concepts, not gameplay captures.
- docs/HANDOFF.md and AGENTS.md: persistent continuation instructions and Astra/GLM ownership.

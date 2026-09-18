# Print Shop Sim — design pack

Astra / design and planning lead

## Open the pack

Open cover.html in a browser directly. Each HTML file is self-contained with inline CSS and SVG, system font fallbacks, and no external assets, CDNs or JavaScript. Navigation links only open other local mockups. No server or installation is required.

- cover.html — editorial cover with perspective open-frame printer and half-printed layered object. Explicitly a concept cover, not gameplay.
- menu-main.html — main menu composition; working local links to HUD and contracts. Continue/settings are honestly disabled.
- menu-contracts.html — later-game job board, preparation expectations, illustrative material/time/reward estimates. Acceptance is disabled, not a simulated transaction.
- hud.html — first-person HUD study with contextual interaction, printer state, progress, balance, and keyboard legend. Keys do not control the page.
- screenshot-workshop.html — wide perspective workshop illustration. Explicitly a concept mockup, not an engine capture.
- language.md — exact palette, typography, spacing, art direction, interactions, Godot UI mapping and browser rendering constraints.
- implementation-plan.md — bounded GLM 5.3 Flash task briefs, tests, initial room/movement/grabbing/printer milestone, single-thread Compatibility web gate, future approved GitHub/Vercel deployment and actual live-browser acceptance. Full contract loop follows later.

The initial prototype scope is deliberately smaller than the later-game UI shown here. Balances, contract IDs, timings and economy values are illustrative design fixtures. No playable Godot build is included.

## Verification

verify_pack.py is a standard-library, offline structural checker. Run:

    python3 /Volumes/HARD/projects/printshop-sim/design/verify_pack.py

It checks required files, basic HTML/SVG tag balance, duplicate IDs, inline styles/SVG, accessible SVG labels, local navigation targets, absence of external links/scripts, and concept provenance. This is not a standards validator or a visual browser review.

Each creation was confirmed by the file-writing tool. The initial environment-discovery command was blocked by the execution approval policy; no configuration was changed to override that policy. Browser rendering, screenshot comparison, Godot export, deployment and live gameplay have not been verified by this design task. Final response reports the structural check result if execution is available.

For later visual review: open each page at 1440×900 and 1280×720, plus a narrow 390 px window; check overflow, captions, keyboard focus and every local link. Desktop landscape remains the gameplay target. HTML illustrations are art targets, not runtime assets or evidence of engine performance.

## Scope and boundaries

All pack files are under /Volumes/HARD/projects/printshop-sim/design. No gameplay sources, global configuration, credentials, git state, deployments or commits were changed. No unrelated projects were accessed. No model was switched or invoked. Authentication/quota failures in future execution are stop conditions, not permission to switch providers.

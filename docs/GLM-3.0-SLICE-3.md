# GLM 3.0 slice 3 — atmosphere & presence pass (v0.60.0)

Model must be glm-5.3-flash via the zai coding plan; no fallback, no auth retry —
on routing failure stop and write the blocker into the worker doc. Work on main,
no commits/push/deploy before parent review. Slices 1-2 (counter + walk-ins,
v0.58.0/v0.59.0) are integrated — build on them.

Read FIRST: AGENTS.md, design/overhaul-3.0.md (binding plan + hazards + design
tokens), design/language.md (the visual language — warm industrial maker, token
table), docs/HANDOFF.md top sections, then source: scripts/WindowLife.gd
(deterministic actor + set_motion pattern), scripts/CustomerActor.gd (slice 2),
scripts/CounterStation.gd (slices 1), scripts/Main.gd: _build_room dressing
order, _apply_quality, _apply_calm_motion, _apply_season_visuals, _build_hud,
_update_hud, and the v020 budget audit test tests/v020_test.gd.

Scope: the shop must LOOK overhauled — customer entry door + swing, OPEN sign,
counter pendant lamp, customer outfit variety, counter clutter, HUD restyle per
the design tokens. Zero gameplay/economy changes: if a diff of yours changes
any payout, rep, stat, board or save key, revert it.

New files you own: scripts/ShopFront.gd, tests/atmosphere_test.gd,
docs/worker-atmosphere.md. Allowed edits: scripts/Main.gd (build call, quality/
calm gate hooks, HUD style block, two-press... nothing else), scripts/
CustomerActor.gd (outfit variety ONLY — same API), scripts/Version.gd (0.60.0).
Nothing else; record-and-stop otherwise.

ShopFront.gd (Node3D, WindowLife pattern — deterministic _advance seam +
set_motion gate):
1. ENTRY DOOR on the front wall at x = -1.9 (flush interior panel 1.0 x 2.1,
   honey with a slim glass slit, steel jamb; NO wall hole — the wall collision
   stays solid, actors ignore collision). Door swings open 75 deg over 0.6 s
   and closed after 1.2 s, driven by open_frame() state machine; Main swings it
   when a customer arrives/despawns (hook the same spawn/despawn points slice 2
   already has). set_motion(false) makes it SNAP open/closed with no animation
   (calm mode). Fully opaque fills only (user preference: no alpha-blended
   overlays beyond what exists).
2. OPEN sign: a small hanging placard on the door glass, emissive "OPEN" text
   (Label3D), lit during the walk-in business window (same frac source as
   slice 2), dim otherwise. Gate the emissive flip behind the existing quality
   gate pattern (_apply_quality Low hides season overlays — read it and follow;
   at Low the sign stays but non-emissive).
3. COUNTER PENDANT: a warm pendant lamp above the counter (cone shade + emissive
   bulb + OmniLight3D, NO shadows, energy 0.5, honey/steel palette), plus a
   slim light-strip emissive under the counter top lip. Light is NOT gated by
   quality (real light, cheap) but IS the only new real light.
4. COUNTER CLUTTER: slip stack, tiny plant, card-reader box on the counter top
   (3-5 meshes, reuse palette materials).
5. SHOPFRONT DRESSING outside the window is OUT OF SCOPE (the window view is
   v0.25 art — do not touch it).

CustomerActor outfit variety (same API, deterministic per (day, index) hash):
torso palette widens to 6 warm-maker colors, optional flat cap OR scarf (2-3
meshes) chosen + colored by hash; nothing above the head, no animations beyond
the existing bob. Slice-2 tests pin positions/APIs — they must stay green
unmodified.

HUD restyle in _build_hud ONLY (no structure/layout changes, no new nodes, no
removed nodes — label texts and positions stay exactly as they are): apply the
design tokens — status card panel StyleBoxFlat ink #202B2B at ~0.95 opacity,
corner radius 4, paper #EEE5D3 text, prompt clay #DA623B accent bar, toast gold
#F5CE80. Use one helper `_hud_panel_style()` so panels share a StyleBox.
Suites assert label .text via contains() — they must stay green unmodified;
if any suite pins a color/StyleBox, record it in the worker doc and leave that
node alone.

tests/atmosphere_test.gd (checks-format, house discipline): door exists at the
spec position with collision-free swing (no new collision), swing seam
determinism (advance N frames -> exact rotation angle; set_motion(false) ->
snap, no tween residue), door swings on customer arrival + despawn (drive a
walk-in through the slice-2 API), OPEN sign lit inside the window frac + dim
outside + non-emissive at Low quality, pendant light exists with shadow_enabled
false + energy in range + under-lip strip emissive, clutter present (node
count), customer outfit determinism (same (day,index) -> identical palette/
accessory set; different seeds differ), HUD style applied (status panel
StyleBox is StyleBoxFlat with the ink color; toast/prompt styled; label texts
unchanged vs a boot without the restyle — compare a pinned label's .text),
budget: with a walk-in active, visible MeshInstance3D count stays under the
v020 budget (read the audit's exact counting method in v020_test.gd and mirror
it; walk-in + door + pendant + clutter combined must fit 180 visible/400 total
— if they do not, reduce clutter meshes, not the audit). Target 24-32 checks.

Verification: new suite 3 consecutive green; bash tools/ladder.sh FULL
failed=0; ~/tools/venv/bin/python -m pytest tests/test_build_web.py -q; both
harnesses sequential, curves byte-identical to the slice-2 reference in
docs/worker-walkin.md (visual-only slice — any movement is a bug; paste both).
Version.gd 0.60.0. docs/worker-atmosphere.md (baseline, exact changes,
commands + results, curves, NOT-RUN list incl. screenshots/browser, blockers).
Stop — parent session reviews, integrates, commits.

Machine baseline (2026-10-30, this box, commit 1186ca3): full ladder 72/72 green incl. smoke; sim_playtest 17 deliveries / $1,749.64 day-8 (8/8 checks); sim_lategame 64 deliveries / $4,918.89 day-14 (16/16 checks). These two curves are the BYTE-IDENTICAL targets for slices 1-3 (slice 4 re-measures). GODOT is at $HOME/tools/godot; pytest is $HOME/tools/venv/bin/python -m pytest. Repo root: the directory containing this docs/ file.

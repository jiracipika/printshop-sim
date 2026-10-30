# Print Shop 3.0 — "The Front Counter" overhaul plan

Planning document authored by the planning/review session (GLM 5.3), 2026-10-30.
These are concept specifications, not claims about existing gameplay. Implementation
is delegated per docs/GLM-3.0-SLICE-{1..4}.md to GLM 5.3 Flash workers (zai coding
plan), one bounded slice at a time, parent session reviews/integrates/commits.

## Why this overhaul

v0.57.0 is a deep, deterministic, 71-suite-green tycoon loop — but the shop is a
sealed, lifeless back office. The board, radio, weather and milestones are all
 abstraction: the player has never seen a single customer. The 3.0 overhaul turns
the workshop into a living storefront while keeping every existing system and the
bot determinism discipline intact.

Headline changes (v0.58.0 → v0.61.0):

1. **The front counter** (v0.58.0): a service counter island on the front wall,
   desk bell, order-slip pad — the shop gains a front-of-house.
2. **Walk-in customers** (v0.59.0): deterministic customers arrive during business
   hours, wait at the counter with a patience meter, place while-you-wait orders
   that ride the existing accept → prep → print → collect → finish → deliver
   pipeline, pay a counter premium and a speed tip.
3. **Atmosphere & presence pass** (v0.60.0): customer entry door with swing,
   customer variety, warm counter pendant, OPEN sign, HUD/menu restyle per the
   design tokens — the game should LOOK overhauled.
4. **Shop rank career** (v0.61.0): five derived shop levels announced on the
   chalkboard with a +2%/level payout bonus and three new milestones.

Bot-safety contract: slices 1–3 must leave sim_playtest/sim_lategame curves
BYTE-IDENTICAL (walk-ins are opt-in service; unserved walk-ins never touch rep,
stats the bots read, the board, or money). Slice 4 deliberately shifts payouts
(+2%/level); both harnesses are re-measured and their floors re-verified.

## Geometry (verified against v0.57.0 source)

Room 7.0 × 6.0 × 3.0 (ROOM_W/D/H). Player spawns (0, 0.3, 1.8). Existing
front-of-room occupants: packing table (2.4, 0, 1.2), finishing bench (3.0, 0,
2.35, rot 225°), spool crate (-3.0, 0, 1.4, interact radius 1.6 m), grab_test's
placement corridor runs along x ≈ 0 in the front half. Farm doorway (back wall,
x 0.9–2.3). The front wall is currently SOLID — no player door exists.

**Counter placement: center (-1.9, 0, 2.55)**, an island counter parallel to the
front wall: honey plywood top 1.4 × 0.08 × 0.65 at height 1.0, sage fascia below,
steel legs, bell + slip pad on top. It spans x −2.6…−1.2 and z 2.22…2.87 — clear
of the grab corridor (x ≈ 0) and leaves ≈ 0.7 m to the crate's corner. Customers
stand BEHIND the counter (wall side, (-1.9, 0, 2.75), torso above the 1.0 m top);
they are scripted Node3D actors on fixed waypoints and never collide with the
player or furniture. Player serves from anywhere within `_near_counter()` radius
1.35 m of counter center — no behind-counter walking.

**Customer entry door: front wall at x = -1.9** (1.0 wide × 2.1 high panel, honey
with a small glass slit, steel frame) — hidden behind the counter, swings on
entry/exit (v0.60.0 adds the swing; v0.59.0 customers fade-step through a static
door). The wall needs a doorway cut ONLY visually if the door renders on the
interior face — do NOT rebuild the front wall (collision stays solid; actors
ignore collision). The door is a flush interior panel with a jamb, not a hole.

## Walk-in flow (v0.59.0 spec)

- **Arrivals**: business window = DayCycle day fraction 0.15–0.80. Deterministic:
  per (day, index i = 0,1): arrive if hash("walkin-%d-%d" % [day, i]) % 10 < 6,
  at time 0.25 + 0.22 × i + 0.03 × (hash % 4). Max 1 waiting (second arrival
  skipped while one waits). None while the boot menu is up (paused), none at
  night, none in the farm room.
- **The slip**: E empty-handed at the counter, press 1 shows the slip
  ("Mia — gear bracket, Sage, ~$41 at the counter, waits ~50 s"); press 2 within
  the arm window accepts. Armed state disarms on leaving radius or 8 s timeout
  (same two-press discipline as shop-code import).
- **The order**: `Contract.generate(day, 100 + arrival_index, cap)` with
  parts_total forced 1, deadline_day = day + 2 (never binding; patience governs),
  tagged walk-in (client name from the existing first-name pool). Auto-assigns
  to the FIRST idle, unlocked, contract-free printer (prompt "Sent to Printer 2").
  No free printer → polite refusal, slip stays armed. Reserve/board untouched:
  walk-ins never enter JobBoard queues.
- **The wait**: patience = 0.55 of a shop day from ACCEPT (~50 s at 90 s/day),
  shown on the HUD ("Counter: Mia waits — 32 s"). Print/prep/collect/finish all
  proceed exactly as board jobs (the machine owns the contract).
- **The handover**: hold the walk-in's part within the counter radius, E →
  counter delivery: same grading core as the packing table (grade snapshot →
  finishing bump → color cap), payout through `_finalize_payout` with the
  documented chain extended: grade → loyalty → reputation → season → event →
  **counter premium ×1.10** → late → same-day tip → shelf bonus. Rep +0.2
  (media-day rule applies), stats.delivered++, client memory updates — walk-ins
  can become regulars.
- **Patience expiry**: customer despawns; if a machine still holds the walk-in
  contract it is cancelled through the existing overnight-cancel teardown (sim
  reset, part discarded) — zero rep cost, stats.lost_walkins++ (new derived
  counter, persisted + validated). Bots never trigger or serve walk-ins, so
  curves are unchanged.
- **Persistence**: waiting walk-ins are NOT persisted (reload despawns, like
  unpersisted machine state — documented). New save keys this overhaul:
  stats.lost_walkins (validator: whole int ≥ 0), walkins_served (whole int ≥ 0)
  — both absence-tolerant for old saves.

## Shop rank (v0.61.0 spec)

Five levels, DERIVED ONLY (never persisted — computed like the tier system):
L1 Sprout (default), L2 Staple (15 delivered + 3.0★ high-water), L3 Known
(40 + 3.5), L4 Fixture (80 + 4.0), L5 Institution (150 + 4.5). High-water rep =
the existing announced_tier thresholds' rep values re-derived (do not add a new
persisted rep high-water; use `max(reputation, tier threshold for announced_tier)`
computed at read time). Level-up: one-time toast + chalkboard header line +
log entry (persisted announced_rank high-water int 1..5, absence-tolerant).
Payout: +2% × (level − 1) appended at the END of the _finalize_payout chain
(after the shelf bonus). Both harnesses re-measured; floors (≥ 8/$500 early,
≥ 60/$3000 late, rep ≥ 2.0) must still pass. Three milestones: "Counter
regular" (10 walk-ins served), "Face of the street" (reach L3), "Institution"
(reach L5).

## Slice briefs and file ownership

| Slice | Version | New files (worker-owned) | Main.gd touches (reviewed) |
| --- | --- | --- | --- |
| 1 Counter | v0.58.0 | scripts/CounterStation.gd, tests/counter_test.gd, docs/worker-counter.md | build call, _near_counter, E branch (before crate), HUD line |
| 2 Walk-ins | v0.59.0 | scripts/CounterService.gd, scripts/CustomerActor.gd, tests/walkin_test.gd, docs/worker-walkin.md | _try_interact branches, day tick hook, HUD line, save keys |
| 3 Atmosphere | v0.60.0 | scripts/ShopFront.gd, tests/atmosphere_test.gd, docs/worker-atmosphere.md | build call, quality/calm gates, HUD style block |
| 4 Rank | v0.61.0 | tests/rank_test.gd, docs/worker-rank.md | _finalize_payout tail, chalkboard, Stats block, milestones |

Rules: new-files-first; Main.gd edits are additive with exact insertion points
from the brief; no other existing file may be edited except Version.gd (bump),
SaveSystem.gd (validators, slice 2/4 only), tests named in the brief. The
grading-core extraction (slice 2) must be behavior-identical for board
contracts — packing_test (58), v018_test (55), v037_test and v034_test are the
pinning suites and must stay green unmodified.

## Definition of done (every slice)

- [ ] New suite green 3 consecutive runs; FULL ladder green via
      `bash tools/ladder.sh` (sequential, never concurrent — BrowserSave race)
- [ ] `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` green
- [ ] Both harnesses (sim_playtest, sim_lategame) byte-identical to the
      previous slice's reference (slices 1–3) / re-measured + floors pass (slice 4)
- [ ] Version.gd bumped; worker doc written; HANDOFF untouched (parent updates)
- [ ] Worker does NOT commit/push/deploy — parent session reviews, integrates,
      commits to main and deploys

## Hazards catalog (binding on every worker)

1. NEVER run two headless Godot processes at once (BrowserSave state race caused
   phantom boot failures). Ladder strictly sequential; no harness overlap.
2. rc 0 lies: a suite log must show no SCRIPT ERROR / Parse Error AND its
   `checks=` count must equal the checks it defines. A suite printing fewer
   checks than defined (or hanging) is a FAIL.
3. Typed-array traps: `Array[int]`/`Array[String]` — use `.assign([...])`, not
   array-literal assignment; `Array[String]` has NO `extend()` — use
   `append_array()`.
4. Test scripts must never name Main/MainMenu as compile-time classes —
   `load("res://scripts/Main.gd")` and instantiate.
5. E-press tests need `paused = false` + `captured = true` (or touch motion
   enabled) BEFORE interacting, and explicit yaw/pitch after teleports.
6. Simulated input needs settle frames (await 2–3 frames after focus grabs /
   menu opens) and RELEASE buttons before polling.
7. NEVER call _save_game before _load_save ran (_boot_ready gate).
8. New menu panels must be real `_build_*` functions in the boot build list —
   cloned code pasted mid-function goes dead.
9. Do not edit any repo file while a ladder is running.
10. Interact branch ORDER is load-bearing: the counter branch must precede the
    crate branch (counter sits inside the crate's 1.6 m radius) and the
    held-part counter-delivery branch must precede the generic `_try_place`.
11. Only the SETTINGS sheet lives inside Sheet/SheetScroll/SheetBox — every
    other panel keeps Sheet/SheetBox paths.
12. Draw-call budget is asserted by v020_test (180 visible / 400 total at boot):
    new meshes must be few and hide when idle.
13. Determinism: game logic uses hash-pinning (`hash("name-%d" % x)`), never
    randi/randi_seed. CustomerActor needs a deterministic `_advance` seam gated
    by `set_motion` so calm_mode freezes it (WindowLife pattern).
14. A parse error in Main.gd surfaces as nonsense downstream boot errors —
    check Main parses FIRST when suites fail weirdly.
15. Never touch .github/workflows (token lacks the scope — pushes fail),
    automated-newsletter, pitchforge or pitch-therapy. Repo work only.
16. Any new persisted key needs a SaveSystem validator + restore list entry +
    absence-tolerance for old saves; never widen an existing validator's range
    without checking every pinning suite.
17. Bots: nothing in slices 1–3 may change bot-observable state (money, rep,
    stats, board). Slice 4 changes payouts only via the documented chain tail.

# Print Shop Sim — roadmap (balance pass shipped; next: v0.13 → v0.20)

Planning document. Every slice follows the same definition of done (see the
bottom of this file) — the per-slice checklists below only list what is NEW.
Each slice ships as: features → tests (all suites green) → engine screenshots
→ commit/push → web export → Vercel deploy → live browser verify → docs.

Baseline at planning time: v0.11.0 (27e2b38), 26 suites / 1005 checks green.

A read-only balance audit (background research agent, 2026-09-27) found the
economy too generous: week-1 gross ~$4,120 at >90% margins, upright prep
unconditionally safe (bypassing the entire risk system), deadlines never
binding, and material_cost_cents generated but never charged. Its three
tuning recommendations shipped as Slice 0 below, BEFORE the print farm — at
the old rates the farm kits would have landed on day ~3. Sequencing note:
reputation tiers (Slice 8) gate nothing until competent play can lose stars,
so it stays late in the queue.

---

## Slice 1 — v0.12.0 "Balance pass" (SHIPPED 2026-09-27, from the audit)

- [x] Payout top flattened: GEN_BASE_PAYOUT[4] 15500 -> 9000, diff-4
      11600 -> 9800, payout cap 15000 -> 9500 (tier-5 jobs no longer a flat
      $150 on ~23% of slots)
- [x] Rush premium 1.4x -> 1.2x (it was unconditional free money)
- [x] Prep risk floor 0.4 -> 0.3: upright-with-overhangs carries a small
      real failure chance; risk-reduction upgrades matter again
- [x] material_cost_cents is charged at confirm again (was generated but
      never deducted)
- [x] Rent curve: $9 on day 1, +$2/day, capped at $25 (was flat $4)
- [x] Same-day tip 15% -> 10%
- [x] JobBoard capacity cached; crate rotation counter persisted
- [x] gen_test bounds updated (3000-9500, rush ratio 1.15-1.35); prep_test
      replicates the new failure floor; all 26 suites green, 1005 checks

## Slice 2 — v0.13.0 "The print farm" (second room, printers 3 & 4)

Goal: give late-game money somewhere to go and make parallel printing scale.

Feature checks:
- [ ] Back-room door on the back wall (visual frame + blocked collision) that
      opens when any farm printer is purchased
- [ ] `machines` array extends from 2 to 4; printers 3 and 4 placed in the
      back room on stands
- [ ] Printer 3 unlock: "Farm kit A" upgrade, $80; printer 4: "Farm kit B",
      $120 (Upgrades catalog, same exactly-once purchase rules)
- [ ] Farm printers ship empty (no filament) and unlocked once bought
- [ ] Locked farm printers show the LOCKED tag like printer 2 does today
- [ ] Back room lighting: at least one ceiling fixture + omni so prints are
      visible in there at night
- [ ] Upgrades panel refresh shows the new kit cards with owned/affordable
      state
- [ ] Pro machine speed bonus stays exclusive to printer 2 (farm printers run
      at base speed)

Test checks:
- [ ] machines.size() == 4 after both kits; locked before purchase
- [ ] buy flow charges, unlocks, grants no filament
- [ ] 4-machine simultaneous print smoke (two contracts + one prototype +
      one idle)
- [ ] all 26 existing suites stay green (machine-array code paths)
- [ ] door collision removed after purchase (physics query check)

Risk: medium — touches the machines array every loop depends on.

---

## Slice 3 — v0.14.0 "First come, first served" (board pressure) — SHIPPED

Goal: make the job board competitive instead of an infinite shelf.

Feature checks:
- [x] Rush contracts expire: unaccepted rush jobs leave the board at the next
      day rollover (replaced by a fresh generated job); calm jobs now CARRY
      OVER instead of being wiped
- [x] Expired jobs cost nothing but reduce reputation by 0.1 ("missed
      opportunity"); the morning prompt names what was missed
- [x] Some contracts show a competing-buyer marker ("2 waiting", ~30% of
      generated slots) — they expire overnight like rush jobs
- [x] Expiry is deterministic per (day, slot); the full board queue now
      persists in the save (board: day/cycle/jobs) so a reload reproduces it
      exactly, deal-cycle counter included
- [x] HUD board line notes expiring jobs ("2 expire overnight")
- [x] Chalkboard tracks "Missed: N" (also in the Stats panel)
- [x] Contracts menu Reserve buttons pin a job to the front of the queue —
      the next printer accept takes it (job selection per the audit)

Test checks:
- [x] rush/competing expiry at rollover: queue shrinks and refills correctly
- [x] no expiry for non-rush, non-competing contracts
- [x] reputation penalty applied exactly once per expired job
- [x] save/reload across a rollover night replays identically (board
      snapshot/restore, JSON round-trip, cycle continuation)
- [x] all 28 suites green (62 new checks in v014_test)

Risk: medium-low; touches JobBoard rotation and the rollover handler.

---

## Slice 4 — v0.15.0 "The workshop log" (history & forensics) — SHIPPED

Goal: players should be able to answer "what happened overnight?" and
"why did that print fail?"

Feature checks:
- [x] Ring buffer of the last 30 shop events (delivered/failed/expired/
      rent/upgrades/prototypes/scrap/cancel) with day stamp and one-line
      detail (scripts/WorkshopLog.gd, pure logic like Ledger)
- [x] Failure cause strings: PrintSim records the worst risk that triggered a
      failure ("support collapse at layer 34" / "came off the bed at layer N"
      / "part toppled at layer N") and the log shows it
- [x] New menu panel "Log" renders the buffer newest-first; failures,
      expiries and cancellations read terracotta
- [x] Buffer persists in the save (validated, capped at 30 entries)
- [x] DebugPanel action [7]: dumps the log to stdout for headless debugging

Test checks:
- [x] events append in order, cap at 30, oldest dropped
- [x] persistence round-trip preserves the buffer (incl. JSON round-trip
      and over-cap restore keeping the newest 30)
- [x] failure cause recorded for seeded and risk-driven failures
- [x] all suites green (50 new checks in v015_test)

Risk: low.

---

## Slice 5 — v0.16.0 "The radio" (ambient audio) — SHIPPED

Goal: fill the silence with a toggleable procedural soundtrack.

Feature checks:
- [x] Runtime-generated lo-fi loop (72 BPM, 4 bars, Dm7→G7→Cmaj7→Am7 chord
      swells over a vinyl-hiss floor, tail crossfade) built as an
      AudioStreamWAV at load — no external assets (Sfx._music_loop)
- [x] Separate "Music" bus + Music volume slider in Settings (persisted)
- [x] Music ducks to 30% automatically while the design computer is open
- [x] Printer servo blips while printing (subtle, rate-limited 0.7–1.4s per
      running machine, audible only near the farm)
- [x] Settings: "Music" checkbox + volume slider; default on at 0.35
- [x] Radio prop on the left-wall spool shelf (honey box, steel face, whip
      antenna); E within 1.0 m toggles playback — radius stays tight so it
      never collides with printer A's accept prompt

Test checks:
- [x] music stream builds (non-empty, loops, ~13 s at 72 BPM) headless
- [x] music bus exists and the slider changes its volume (incl. mute-at-zero)
- [x] duck on design-studio open/close; disabled checkbox stops the player
- [x] servo blips only while a machine is running; timer never re-arms idle
- [x] all 29 suites green (33 new checks in v016_test)

Risk: medium — subjective audio quality is unverifiable headless; kept the
loop extremely simple and quiet.

---

## Slice 6 — v0.17.0 "Weather in the windows" — SHIPPED

Goal: make seasons visible, not just numeric.

Feature checks:
- [x] Season visuals on the back-wall window via a SEASON_LOOK table: humid =
      hazier pane + denser fog; cold snap = icy pane tint + frost band across
      the lower glass + cooler sun; boom = warm pane glow + golden fog/sun;
      calm = byte-identical to the pre-v0.17 look
- [x] Rain streaks during humid weeks: 10 thin unshaded quads sliding down
      the pane only (window-local node, no room-wide particles), wrapping at
      the sill; dark against the bright glass so they read
- [x] Sky/sun tint shifts per season (_apply_daylight multiplies the
      time-of-day color by the season tint)
- [x] HUD season line gains a weather icon glyph (☔ / ☃ / ☀ — same symbol
      block as the existing ★☆ so the default font renders them)
- [x] All effects Compatibility-safe; the only added draw calls (rain +
      frost overlays) are gated behind the existing quality (shadows) toggle;
      the tint changes are free and always apply

Test checks:
- [x] per-season visual state flips when the season changes (pane material,
      fog color/density, overlay visibility — node/param probe)
- [x] overlays hidden when the quality toggle is off; tints stay
- [x] frame budget: 60 s of simulated rain ticks stay bounded, node count
      never grows, hidden rain does not animate
- [x] all 30 suites + smoke green (39 new checks in v017_test); pytest 21/21

Risk: medium — visual tuning is iterative; shipped conservative.

---

## Slice 7 — v0.18.0 "Multi-part orders" (contracts v2) — SHIPPED

Goal: deepen the core job into a small production run.

Feature checks:
- [x] Generated contracts can require 2-3 copies ("[×2 parts]" on the card,
      ~1 in 4 slots, deterministic as the LAST generator draw so every
      pre-v0.18 pinned (day, slot) value is untouched); fixture contracts
      stay single-part; payout/materials stay PER COPY
- [x] Each copy is a separate print on the order's machine; the contract
      tracks parts_packed + copy_grades; a new legal transition
      INSPECTION -> PREPARING re-enters prep for the next copy
- [x] Packing table accepts partial deliveries: packed copies stack on the
      table visually (max 3, PackingStation.set_stack_count), contract stays
      INSPECTION until all copies are packed
- [x] Payout, aggregate grade (average of copies), tips and deadlines all
      apply at the final completion, exactly once
- [x] Board card, HUD contract line ("parts 2/3"), collect/reprint prompts
      and the delivery log ("×3") reflect order progress
- [x] F-grade on any copy caps the whole order at C; a second F copy fails
      the order outright (rep hit, no payout); an F copy is scrapped (-0.15
      rep) and reprinted without killing the order

Test checks:
- [x] multi-part state machine: partial packs pay nothing, completion payout
      exactly once, deadline applies to the LAST copy (late + cancel paths)
- [x] grade aggregation rules (single F caps to C; two F = FAILED; averages
      floor conservatively)
- [x] cancel path discards the mid-order and its stack cleanly
- [x] board summaries + save payload carry parts_total; pre-v0.18 payloads
      restore as single-part
- [x] all 32 suites + smoke green (55 new checks in v018_test); pytest 21/21

Risk: high — shipped as one slice at ~340 changed lines; the deepest
regression surface (collect/pack/grade) is covered by the v018 e2e loop.

---

## Slice 8 — v0.19.0 "Reputation tiers" (progression gates) — SHIPPED

Goal: tie reputation to what the board offers.

Feature checks:
- [x] Board tiers: generated contracts cap difficulty at 2 below 3.0 rep,
      3 below 3.5, 4 below 4.25, anything at 4.25+ (Events.tier_for_rep /
      tier_max_difficulty; Contract.generate gains a max_difficulty param
      whose default keeps every pinned value; the morning board deals at the
      current tier via JobBoard.deal_day / rotate_day tier terms)
- [x] Tier-up moment announces itself ("The board is buzzing — bigger jobs
      available") once per tier, ever — high-water mark persisted in the
      save (tier_announced); pre-v0.19 saves adopt their current tier
      silently; fresh shops start AT tier 2 without announcing it
- [x] Rush premiums scale with tier (+10% per tier above the first, applied
      at deal time so Contract.generate stays pinned; calm payouts untouched)
- [x] Two new achievements: "Board regular" (3.5★), "Top of the market"
      (4.25★)
- [x] Stats panel shows the current tier (name + difficulty cap + rush
      premium) and what the next tier unlocks (threshold + terms)

Test checks:
- [x] tier table boundaries (exactly 3.0/3.5/4.25 count as the higher tier)
- [x] capped generation sweep respects every cap; default generate unchanged
- [x] deal_day/rotate_day deal terms: queue capped, rush payouts scale by
      exactly the tier multiplier (capped at the $95 payout ceiling)
- [x] tier-up announcement fires exactly once per threshold (log + prompt +
      save round-trip; re-crossing stays silent)
- [x] achievements + stats panel integration
- [x] all 33 suites + smoke green (32 new checks in v019_test); pytest 21/21

Risk: low-medium — the tier terms ride the existing deal pipeline; the one
regression found in testing (boot re-deal continuing the cycle counter
instead of restarting it) is fixed in deal_day and covered by day_test.

---

## Slice 9 — v0.20.0 "Hardening & release polish" — SHIPPED

Goal: performance, mobile confidence, and a clean 1.0-rc.

Feature checks:
- [x] Quality presets: Low / Standard / High (Low kills shadows + glow +
      season overlays, High boosts glow to 0.8; single Settings dropdown;
      the shadows checkbox stays in sync — checked = Standard, off = Low;
      persisted as settings.quality_preset, validator accepts Low/Standard/
      High)
- [x] Draw-call / instance budget audit: 135 visible / 341 total
      MeshInstance3D at boot against a 180/400 budget — no merging needed,
      the audit runs in v020_test so regressions trip the suite
- [x] Portrait-mode HUD validation: below 500 px the status card spans the
      viewport with a wrapping label (_apply_hud_layout on size_changed) and
      the prompt stays inside 390 px; wide windows keep the compact card
- [x] Touch targets: interact 96x96, pause 72x48, stick regions — asserted
      >= 48 px at 390x844 via TouchControls.layout_rects
- [x] Reset/first-run flow re-verified end to end: fresh boot (8 tier-capped
      jobs, $25, 1500 g) plus a FULL accept -> prep -> print -> collect ->
      pack -> deliver loop at Low quality with the preset held throughout
- [x] HANDOFF/README rewritten as a 1.0-rc summary

Test checks:
- [x] preset dropdown applies all underlying settings (shadows, glow, sync)
- [x] small-viewport HUD assertions (headless viewport resize 390x844)
- [x] full-loop end-to-end test at Low quality
- [x] all 34 suites green; python pipeline green; export artifacts validated
      by tests/test_build_web.py

Risk: closed — this was the last roadmap slice.

---

## Post-roadmap — v0.21.0 "Flavor & feel" — SHIPPED

With the 9-slice roadmap closed, these are incremental polish drops on top
of the 1.0-rc.

- [x] Three radio stations (Sfx.STATIONS: Lo-fi 72 BPM / Synthwave 100 BPM
      / Ambient 56 BPM) share one parameterized renderer with per-station
      partials, voice amps, hiss and swell; streams are cached per station
      and E at the radio cycles station -> station -> off -> back on.
      settings.radio_station persists; ducking + the Music bus apply to all
- [x] Milestone toasts: a gold top-center HUD toast announces a milestone
      the first frame it is true, logs "milestone" in the workshop log, and
      persists the toasted set (achv_toasted); boot silently adopts anything
      already earned so reloads never toast old news
- [x] Shop dressing: doormat under the door, coffee mug on the design
      bench, cardboard stack by the packing table; draw-call budget still
      holds (140 visible / 346 total vs 180/400)

Test checks:
- [x] 23 new checks in v021_test (station streams, cycling, persistence,
      toast lifecycle incl. the adopt-at-load rule, props, budget)
- [x] v016 updated to the station API; v015 freezes the shop before its
      save snapshot (async milestone saves shifted the expected log count)
- [x] all 35 suites + smoke green (1348 checks); pytest 21/21

---

## Post-roadmap — v0.22.0 "Presence pass" — SHIPPED

- [x] Footsteps: soft alternating step1/step2 thuds paced to the walk
      (STEP_INTERVAL 0.42 s, immediate first step, idle pre-charges half an
      interval, airborne/idle feet never step)
- [x] Morning bell: one soft two-partial ding at every live day rollover
      (DayCycle.restore never emits, so save-loads stay silent)
- [x] Radio star milestone: stations heard at least once persist (save key
      stations_heard, validator 0..2); the third unlock toasts like any
      milestone; boot marks the playing station without saving (see the
      boot-guard note in HANDOFF)

Test checks:
- [x] 21 new checks in v022_test (streams, pacing, alternation, bell,
      heard-set persistence + silent reload); v021's doormat check moved to
      the farm doorway; shop_art stream count 11 -> 14
- [x] all 36 suites + smoke green (1369 checks); pytest 21/21

---

## Post-roadmap — v0.23.0 "Operations pass" — SHIPPED

- [x] Photo mode: F2 hides the whole HUD layer for clean shots (prompt
      names the key; second press restores)
- [x] Two new milestones: "Full house" (all four printers running at once,
      derived live from the machine sims) and "Perfectionist" (five A-grade
      deliveries in a row; the last five order grades persist as save key
      recent_grades, validator rejects non-letters)
- [x] New daily event "Surplus stock" (spools $6, joins the deterministic
      pool; the crate sign follows) — existing day pins unaffected
      (events_test/day_test green untouched)
- [x] Chalkboard names the week and season icon ("Week 2 ☃")

Test checks:
- [x] 18 new checks in v023_test (photo toggle, full-house lifecycle,
      perfectionist streak + break, recent_grades persistence + validator,
      surplus rotation + crate sign, chalkboard week line)
- [x] all 37 suites + smoke green (1387 checks); pytest 21/21

---

## Post-roadmap — v0.24.0 "Studio & street pass" — SHIPPED

- [x] Design catalog grows to six shapes: Phone stand (prism wedge),
      Plant marker (paper-thin stake) and Drawer knob (dome) each with
      starter dims, mesh builders and material multipliers (stake < knob
      < stand at equal size); the prototype pipeline accepts them end to
      end
- [x] Weekly poster rotation: the left-wall poster's slogan cycles
      deterministically per shop week (POSTER_LINES, hash-pinned per week);
      the back-wall PRINT SHOP sign stays constant

Test checks:
- [x] 14 new checks in v024_test (normalization, mesh classes, gram
      ordering, template dims, prototype part, poster determinism +
      rotation across weeks)
- [x] all 38 suites + smoke green (1401 checks); pytest 21/21

---

## Post-roadmap — v0.25.0 "Outside the window" — SHIPPED

- [x] The window is a light box: the day pane gains a procedural day view
      (hazy sun, hill band, rooftop silhouettes) under the season tint; a
      night pane crossfades over it with the shop clock (stars fully on at
      the t=0 midnight boot, gone by noon)
- [x] Real constellations: one featured per REAL month (Orion in January,
      Leo in March, Scorpius in June, Lyra in July, Taurus in December...)
      drawn with star positions + connecting lines following the actual
      asterisms, over ~170 field stars; Ursa Major and a corner regular are
      always faintly present
- [x] The moon shows its REAL phase (anchored to the 2000-01-06 new moon;
      per-pixel terminator, waxing lit-right / waning lit-left)
- [x] Lit city skyline along the horizon; two cloud wisps drift in front of
      the glass for parallax and dim at night
- [x] Season-pane energy ownership combined: SEASON_LOOK.energy is the
      target, the clock scales it (noon lands exactly on the season value —
      v0.17 semantics preserved)

Test checks:
- [x] 19 new checks in v025_test (month table, constellation data soundness,
      texture caching/distinctness, moon-phase anchors, crossfade at
      midnight/noon, cloud drift + wrap, real-month texture binding)
- [x] all 39 suites + smoke green (1420 checks); pytest 21/21

---

## Post-roadmap — v0.26.0 "The playtest bot" — SHIPPED

The machine-side of the human-only queue: an automated player.

- [x] tests/sim_playtest.gd plays the shop for 8 in-game days with a
      simple policy — accepts the best affordable board job (difficulty <=
      3, no suicide rush), confirms the safest printable orientation,
      refills filament at the crate when the estimate would not fit,
      collects, packs, delivers, and reprints owed multi-part copies
- [x] Deterministic end to end (PrintSim has no RNG; board/events/seasons
      are hash-pinned) — the run replays exactly: 18 deliveries, $1,923
      balance, rep 4.7 by day 8, zero rent debt
- [x] Economy verdict: HEALTHY. A competent single-printer player earns
      from day 2 ($247 by day-2 end), never approaches a debt spiral, and
      reaches the top reputation tier in week one — no balance changes
      needed
- [x] Survival assertions: 8 deliveries minimum, day-8 balance >= $500,
      rep floor 2.0, debt < $60, never chronically late — starvation
      regressions fail the harness
- [x] Named OUTSIDE the tests/*_test.gd glob on purpose: the run
      simulates ~12 minutes of shop time (~15 s wall at 8x) and is a
      harness, not a unit suite; run it before balance-touching changes

---

## Post-roadmap — v0.28.0 "Couch menus" — SHIPPED

Completes the controller story: the UI is fully gamepad-navigable.

- [x] Boot focuses Play — a gamepad player can start with A immediately;
  A on Play resumes straight into gameplay without pointer lock (the
  mouse-click capture flow is unchanged for mouse users)
- [x] The menu row has an explicit focus chain (left/right along the row,
  wrap at both ends) — automatic neighbor discovery proved unreliable in
  this layout; the Settings panel has an explicit vertical chain
  (sliders -> checkboxes -> quality -> reset -> back)
- [x] Panels focus their first interactive control when shown
  (depth-first: tree order = creation order)
- [x] ui_up/down/left/right created at RUNTIME — the project's custom
  [input] section REPLACED Godot's built-in ui_* actions, which did not
  exist at all (arrows/d-pad/stick did nothing before); left stick + d-pad
  bound, A added to ui_accept, Enter kept
- [x] Closing the menu releases focus (no ghost focus while playing)

Test checks:
- [x] 11 checks in v028_test (boot focus, A-start unpaused, dpad focus
  move, A-activates-panel, slider focus + d-pad step, focus release,
  START reopen) — plus settle-frame discipline: focus grabs need a frame
  before navigation events flush
- [x] all 41 suites + playtest bot + pytest green (v027 trimmed to 9
  checks: its menu-toggle coverage moved to v028 where the couch-menu
  reality is testable)

---

## Post-roadmap — v0.29.0 "Atmosphere & onboarding" — SHIPPED

- [x] Snowfall outside the glass on cold-snap weeks: 12 white flakes,
      slower than the rain with a sideways sway, sill wrap, quality-gated
      like the rain/frost
- [x] Moonlight: a cool blue spill through the window at night — energy
      follows the same nightness curve as the starfield, no shadows
      (the cheapest possible atmosphere)
- [x] How-to-play gains an INPUTS section covering all three input
      methods (mouse + keyboard, touch, gamepad)

Test checks:
- [x] 15 new checks in v029_test (snow lifecycle: build/gate/fall/wrap/
      bounded/quality; moonlight curve noon-vs-midnight, no shadows;
      how-to input coverage)
- [x] all 42 suites + playtest bot + pytest green

---

## Post-roadmap — v0.30.0 "Customer voices & shop history" — SHIPPED

- [x] Client notes on job cards: ~45% of generated orders carry a
      deterministic handwritten flavor note (GEN_NOTES, the new last
      generator draw — every pinned (day, slot) field untouched); two
      fixture jobs carry hand-written notes; cards render the note in
      quotes under the title; notes ride summaries, board payloads
      (optional key — pre-v0.30 saves restore bare) and never affect
      gameplay
- [x] Chalkboard earnings history: the last 7 days' take persist
      (daily_earned + day_earned_today, validated), rollover banks the
      running day total, and the chalkboard renders a unicode-block
      sparkline scaled against the best day ("Last days: ▁▄▅█")

Test checks:
- [x] 18 new checks in v030_test (determinism, flavor-table membership,
      ~45% rate, fixture notes, summaries/JSON/old-save paths, card
      rendering, banking/cap/persistence/sparkline, validator rejects)
- [x] all 43 suites + playtest bot + pytest green

---

## Post-roadmap — v0.31.0 "Regulars" — SHIPPED

- [x] Client memory: completed orders count per client (client_orders,
      persisted + validated); deliveries build relationships
- [x] Loyalty notes: from their 2nd completed order on, a returning
      client's freshly dealt jobs carry deterministic loyalty lines
      (LOYALTY_NOTES, hash-pinned per job id, stamped at deal time so the
      persisted queue never flickers); 3+ orders = a "regular" in Stats
- [x] Stats panel counts regulars; new milestone "Neighborhood favorite"
      (serve 5 clients 3+ times each)
- [x] Flavor only — payouts, deadlines and grading untouched (the
      playtest bot's reference curve replays exactly)

Test checks:
- [x] 13 new checks in v031_test (memory increments per delivery, regular
      thresholds, loyalty stamping on a real dealt board vs generic pool,
      per-job-id determinism, persistence + reload incl. board regulars,
      validator rejects, stats + milestone thresholds)
- [x] all 44 suites + playtest bot + pytest green

---

## Post-roadmap — v0.32.0 "Loyalty & calm" — SHIPPED

- [x] Loyalty bonus: returning clients pay +5% per prior completed order,
      capped +15% (4th+ order) — applied inside the order base before
      reputation, surfaced on every delivery prompt branch as
      "returning client x1.05"; uses orders completed BEFORE the current
      one. The playtest bot's curve shifts slightly ($1,923 -> $1,884 with
      the deterministic re-roll) and stays healthy
- [x] New daily event "Steady hands": failure risk -0.10 for the day
      (rides the existing failure_delta plumbing), joins the rotation
      (now 10 entries)

Test checks:
- [x] 9 new checks in v032_test (multiplier table 1.0..1.15 with the cap,
      end-to-end second-delivery payout through the documented chain,
      prompt naming the bonus, before-count semantics, event rotation +
      delta)
- [x] all 45 suites + playtest bot + pytest green (v023's chalkboard-week
      assertion made week-agnostic after the pool shift)

---

## Definition of done (every slice)

- [ ] Feature checks above all ticked
- [ ] Test checks above all ticked; FULL suite green (no SCRIPT ERROR, no
      Parse Error, exit 0) — count grows, never shrinks
- [ ] `python3 -m pytest tests/test_build_web.py -q` green
- [ ] Engine screenshots of the new features captured and reviewed
- [ ] Commit message documents slice + test counts; pushed to main
- [ ] `bash tools/build_web.sh` clean (stamped sha, not dirty)
- [ ] `vercel --prod --yes` deployed; live build-info.json matches the push
- [ ] Live browser check: game boots, menu renders, new feature visible
- [ ] README milestone + HANDOFF updated; Version.gd bumped

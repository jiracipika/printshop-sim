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

## Slice 8 — v0.19.0 "Reputation tiers" (progression gates)

Goal: tie reputation to what the board offers.

Feature checks:
- [ ] Board tiers: generated contracts roll difficulty ≤ 2 below 3.0 rep,
      ≤ 3 below 3.5, ≤ 4 below 4.25, anything at 4.25+
- [ ] Tier-up moment announces itself ("The board is buzzing — bigger jobs
      available") once per tier
- [ ] Rush premiums scale with tier (+10% per tier above the first)
- [ ] Two new achievements: "Board regular" (3.5★), "Top of the market"
      (4.25★)
- [ ] Stats panel shows the current tier and what the next unlocks

Test checks:
- [ ] generated pool difficulty distribution per rep band (sweep)
- [ ] tier-up announcement fires exactly once per threshold
- [ ] achievements integration
- [ ] all suites green

Risk: low-medium.

---

## Slice 9 — v0.20.0 "Hardening & release polish"

Goal: performance, mobile confidence, and a clean 1.0-rc.

Feature checks:
- [ ] Quality presets: Low / Standard / High (shadows + 512px textures +
      glow mapped to presets; single dropdown replacing the lone checkbox,
      checkbox kept in sync)
- [ ] Draw-call / instance budget audit on the web export; props merged or
      trimmed if over budget
- [ ] Portrait-mode HUD validation: status card, prompt, touch controls all
      readable at 390×844; touch targets stay ≥ 48px
- [ ] Reset/first-run flow re-verified end to end after all v0.12-v0.18
      systems
- [ ] HANDOFF/README rewritten as a 1.0-rc summary

Test checks:
- [ ] preset dropdown applies all underlying settings
- [ ] small-viewport HUD assertions (headless viewport resize)
- [ ] full-loop end-to-end test at Low quality
- [ ] all suites green; python pipeline green; export artifacts validated

Risk: medium; mostly audit work.

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

# Worker doc — GLM 3.0 slice 4: shop rank career (v0.61.0)

Worker: glm-5.3-flash via zai coding plan. Date: 2026-10-30. Brief:
docs/GLM-3.0-SLICE-4.md. Base: commit d5b2ec1 (slice 3 integrated; machine
baseline from the brief: sim_playtest 17 / $1,749.64 day-8, sim_lategame
64 / $4,918.89 day-14, both byte-identical targets for slices 1-3 — slice 4
re-measures). No commits/push/deploy — parent reviews, integrates, commits.

## BLOCKER RAISED, THEN RESOLVED (atmosphere_test's stale version pin)

`bash tools/ladder.sh --bots` run 1: `LADDER_DONE total=77 failed=1:
tests/atmosphere_test.gd` — check 24 pins a LITERAL game version:
tests/atmosphere_test.gd:424 `load("res://scripts/Version.gd").VERSION ==
"0.60.0"`. The brief commands Version.gd -> "0.61.0" AND a full ladder
failed=0; atmosphere_test.gd is NOT in the allowed-edits list ("Nothing
else; record-and-stop otherwise"). Both gates could not hold within my
edit list, so I escalated instead of working around it.

**Parent decision (via escalation, this session): AUTHORIZED** — update the
stale literal. Applied as exactly one line: tests/atmosphere_test.gd:424
"0.60.0" -> "0.61.0" (check 24's expected VERSION value; everything else in
the file byte-identical, `git diff --stat` = 1 file, 1 insertion, 1
deletion). Recorded here as an authorized deviation: "atmosphere_test
version literal refreshed 0.60.0 -> 0.61.0, parent-approved via
escalation; rationale: refreshing a stale version pin is test plumbing,
not suite retuning (same category as the slice-1 parent-authorized
plumbing fixes)." Re-verified after the edit: atmosphere_test standalone
3 consecutive green runs (25/25 each), then the FULL ladder again ->
`LADDER_DONE total=77 failed=0` (run 2 below).

## The high-water question — derivation attempted, FALLBACK adopted

The brief's no-new-key option: `effective_hwm = max(reputation, Events tier
threshold for the persisted announced_tier)`. Read first, as instructed:

- scripts/Events.gd:192-198 `tier_for_rep`: tiers 1..4 over
  `TIER_THRESHOLDS: [3.0, 3.5, 4.25]`, inclusive (>= counts as the higher
  tier). `TIER_THRESHOLDS[i]` is where tier i+2 unlocks.
- announced_tier semantics (Main.gd): a persisted high-water of the BOARD
  tier, written ONLY inside `_rep_event` when `tier_for_rep(reputation)`
  exceeds it; restored or derived at `_load_save`; booted to the current
  tier silently (the boot mark).

Mapping threshold(t): t=1 -> 0.0 (no information), t=2 -> 3.0, t=3 -> 3.5,
t=4 -> 4.25. Soundness against the RANK bars (3.0 / 3.5 / 4.0 / 4.5):

- L2, L3 are sound: rep ever >= 3.0 / 3.5 implies announced_tier >= 2 / 3,
  so the derived value never drops below those bars.
- L4 is UNSOUND in the rep band [4.0, 4.25): tier_for_rep(4.0) = 3, so the
  derived floor is only 3.5. Rep drops exist and are routine in this game
  (`_rep_event(-0.4)` second-F failure, -0.2 late delivery, -0.15 missed
  day, -0.1 x expired offers, -0.6 client cancel) — after any drop below
  4.0 the derivation reads a shop that once held 4.0 stars as L3.
- L5 is UNSOUND in the band [4.5, 5.0]: tier 4's floor is 4.25 < 4.5, same
  mechanism.
- Also on the delivered side: delivered crosses 40/80/150 at delivery time;
  the level needs BOTH operands, and the derivation reads the CURRENT rep,
  not the historical max.

So the derivation is a lower bound, not the high-water, and the design
demand is explicitly monotonic levels ("thresholds are lifetime-delivered +
high-water on purpose"). Per the brief's own escape clause the slice
adopts the FALLBACK: one new persisted key `rep_high_water` (float 0..5,
absence-tolerant, updated on EVERY rep change), plus the brief's other new
key `announced_rank` (int 1..5, absence-tolerant, announced_tier pattern).

The derivation is not discarded — it survives as the boot SEED for
pre-v0.61 saves, which is the most it can honestly be: `_load_save`
bootstraps `rep_high_water = maxf(reputation, _rep_floor_for_tier(
announced_tier))` (Main.gd `_rep_floor_for_tier`), after which every
`_rep_event` keeps the persisted value exact forever.

## What shipped

### scripts/Main.gd (additive, 127 lines)

1. **Vars** (scripts/Main.gd:70-74): `rep_high_water := 0.0` (restored or
   bootstrapped in `_load_save`, seeded at the opening standing for fresh
   shops in the `_build_world` boot-mark block) and `announced_rank := 1`.
2. **Rank section** (scripts/Main.gd:4391-4451, right after `_rep_event`):
   `RANK_NAMES = ["Sprout", "Staple", "Known", "Fixture", "Institution"]`,
   `RANK_DELIVERED = [15, 40, 80, 150]`, `RANK_REP = [3.0, 3.5, 4.0, 4.5]`,
   `RANK_PAYOUT_PER_LEVEL := 0.02`; `shop_rank_level()` (derived on every
   read, never stored; >= boundary rule mirrors `tier_for_rep`);
   `rank_payout_mult()`; `_rep_floor_for_tier(tier)` (the Events mapping
   above); `_check_rank_announcement()` — once per level EVER: gold toast
   "Shop rank: <name>", one "rank" workshop-log entry, prompt, `_save_game`.
3. **`_rep_event` hook** (scripts/Main.gd:3979-3990): `rep_high_water =
   maxf(rep_high_water, reputation)` directly after the clamp (it is the
   single gameplay writer of reputation — the only other write is the
   `_load_save` restore), then `_check_rank_announcement()` mirroring the
   v0.19 tier block.
4. **Settle hook** (scripts/Main.gd:4386-4387): `_check_rank_announcement()`
   right after the `walkins_served` bookkeeping — both level operands only
   ever rise inside a settle (delivered here, rep in `_rep_event` above),
   so this is where a level-up lands; the `lvl <= announced_rank` guard
   makes the double site idempotent.
5. **Payout tail** (scripts/Main.gd:4360-4364): `+2% x (level - 1)` applied
   AFTER the shelf bonus, immediately before the int-cents return; the
   chain comment above `_finalize_payout` now documents the full extended
   order: grade x loyalty -> reputation -> season -> event -> counter
   premium x1.10 -> late half -> same-day tip -> showcase bonus -> shop
   rank +2%/level (FINAL factor). Fresh shops derive L1 and add nothing,
   which is why every pre-0.61 payout pin held.
6. **Chalkboard header** (scripts/Main.gd:4916-4918): the ledger text gains
   a `RANK: <name>` line directly under "SHOP LEDGER" (announcement makes
   it appear; it always shows the derived name).
7. **Stats RANK block** (scripts/Main.gd:380-391): after the BOARD TIER
   block, same shape — header `RANK (v0.61)`, current level + bonus %
   (`Known — payouts +4%`), next gate (`Next: Fixture at 80 delivered and
   4.00 stars`) or a top-rank line at L5.
8. **Three milestones appended** (scripts/Main.gd:558-564): "Counter
   regular" (walkins_served >= 10), "Face of the street" (rank >= 3),
   "Institution" (rank >= 5) — hints/toasts/boot adoption/Stats listing
   ride the existing `_check_milestone_toasts` + `_load_save` adoption loop.
9. **`_load_save`** (scripts/Main.gd:921-939): restores/ bootstraps
   rep_high_water, restores-or-derives announced_rank (both absence-
   tolerant; invalid announced_rank falls back to the derived level), and
   re-seeds nothing else — the boot never re-announces.
10. **`_build_save_payload`** (scripts/Main.gd:1065-1067): adds
    `announced_rank` and `rep_high_water` after `tier_announced`.

### scripts/SaveSystem.gd

Two validators in the walkins_served pattern, wired into `validate()`
(scripts/SaveSystem.gd:125-128, 274-300): `_announced_rank_valid` (absent =
fine; whole int 1..5) and `_rep_high_water_valid` (absent = fine; numeric
0..5). Restore-side handling is Main's `_load_save` block above. No
existing validator range was touched (hazard 16).

### scripts/Version.gd

VERSION "0.60.0" -> "0.61.0".

### New files (worker-owned)

- `tests/rank_test.gd`: **33 checks** (brief target 26-34), checks-format
  SceneTree suite, v057 pattern (`load()`-only class references per hazard
  4, BrowserSave cleared at start and end, prints "%d checks defined" for
  the ladder's defined-vs-reached gate). Sections: the full derived-level
  table at every boundary (14/15, 39/40, 79/80, 149/150 delivered; exact
  3.0/3.5/4.0/4.5 high-water counts as the higher level; a 2.99 high-water
  drops back down); payout pins through the documented chain on a
  controlled contract (multiplier 0.88, calm season, quiet day, no tip:
  L1 880, L2 898, L3 915, L4 933, L5 950) plus composition-order pins
  (counter x1.10 BEFORE rank -> 1017; shelf x1.02 BEFORE rank -> 934; late
  half BEFORE rank -> 458); the announcement lifecycle (cross, toast text,
  one "rank" entry, chalkboard header line, high-water survives a rep
  drop, once-per-level silence, save round-trip, pre-v0.61 old-save
  bootstrap); SaveSystem validators (accept + two rejects); the three
  milestones at their edges (9/10 served, L4 vs Face-of-the-street, L5
  Institution); the Stats RANK block content and its position after BOARD
  TIER.
- `docs/worker-rank.md`: this file.
- `tests/rank_test.gd.uid` via the headless `--import` rescan (repo
  convention; a temporary probe script used while debugging was deleted
  along with its .uid).

## Verification (all sequential this session — hazard 1)

1. `timeout 150 ~/tools/godot --headless --path . --script
   tests/rank_test.gd` — **3 consecutive green runs**: `checks=33
   failures=0`, rc 0, `33 checks defined` == `checks=33`, 0 SCRIPT ERROR /
   Parse Error (hazard 2 gate). Debug trail kept honest: run 1 failed 11
   checks — ALL test-side bugs, zero production bugs: (a) I passed
   `rep=1.0` to `_finalize_payout` believing it a reputation, but the
   rep>=0 branch takes the rep MULTIPLIER (v0.32 rule, Main.gd comment;
   probe: `with_rep_088=880` exact) — fixed to 0.88; (b) section C never
   set delivered=40 before the L3 crossing; (c) TOTAL said 34 for 33
   checks. Run 2 then failed exactly one check because the workshop log is
   itself persisted — a reload restores the two "rank" entries, so the
   assertion now pins count == 2 (restored, boot added none) instead of 0.
2. `bash tools/ladder.sh --bots` (FULL, sequential):
   - Run 1 (before the authorized pin refresh): `LADDER_DONE total=77
     failed=1: tests/atmosphere_test.gd` — 76 PASS including the new
     rank_test, both bots, economy/day/payout-pinning suites, walkin,
     counter, v018/packing/v037/v034. The single failure was the stale
     version literal (atmosphere check 24); every other atmosphere check
     passed.
   - Run 2 (FINAL, after the authorized one-line pin refresh):
     **`LADDER_DONE total=77 failed=0`** — 77 PASS, runner rc 0, no FAIL
     lines, 0 SCRIPT ERROR / Parse Error in any suite log. atmosphere_test
     standalone after the refresh: **3 consecutive green runs** (25/25
     each, rc 0).
3. `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` ->
   **21 passed in 0.41s**.

### NEW bot curves (slice-4 reference; floors all pass)

sim_playtest `checks=8 failures=0` (floors: >= 8 deliveries / >= $500 /
min rep >= 2.0):

    PLAYTEST: day 1 end: $151.05 · delivered 2 · rep 2.80 · debt $0.00
    PLAYTEST: day 2 end: $462.25 · delivered 5 · rep 3.20 · debt $0.00
    PLAYTEST: day 3 end: $625.12 · delivered 6 · rep 3.30 · debt $0.00
    PLAYTEST: day 4 end: $743.31 · delivered 7 · rep 3.40 · debt $0.00
    PLAYTEST: day 5 end: $657.39 · delivered 7 · rep 3.00 · debt $0.00
    PLAYTEST: day 6 end: $1024.43 · delivered 10 · rep 3.20 · debt $0.00
    PLAYTEST: day 7 end: $1377.80 · delivered 13 · rep 3.70 · debt $0.00
    PLAYTEST: day 8 end: $1665.79 · delivered 15 · rep 3.80 · debt $0.00
    PLAYTEST: day 9 end: $1753.13 · delivered 17 · rep 4.00 · debt $0.00

sim_lategame `checks=16 failures=0` (floors: >= 60 deliveries / >= $3000 /
min rep >= 2.0):

    LATE day 1 end: $2.29 · delivered 4 · rep 3.20 · upgrades 4
    LATE day 2 end: $818.81 · delivered 14 · rep 4.50 · upgrades 4
    LATE day 3 end: $1955.43 · delivered 23 · rep 4.80 · upgrades 4
    LATE day 4 end: $2654.56 · delivered 28 · rep 5.00 · upgrades 4
    LATE day 5 end: $2732.35 · delivered 30 · rep 4.80 · upgrades 4
    LATE day 6 end: $3581.18 · delivered 39 · rep 4.80 · upgrades 4
    LATE day 7 end: $4202.13 · delivered 49 · rep 4.50 · upgrades 4
    LATE day 8 end: $4473.09 · delivered 54 · rep 4.80 · upgrades 4
    LATE day 9 end: $4572.11 · delivered 55 · rep 4.80 · upgrades 4
    LATE day 10 end: $4543.11 · delivered 55 · rep 4.70 · upgrades 4
    LATE day 11 end: $5159.52 · delivered 62 · rep 4.70 · upgrades 4
    LATE day 12 end: $5130.52 · delivered 62 · rep 4.50 · upgrades 4
    LATE day 13 end: $5205.03 · delivered 64 · rep 4.70 · upgrades 4
    LATE day 14 end: $5081.71 · delivered 64 · rep 4.50 · upgrades 4
    LATE day 15 end: $6245.19 · delivered 74 · rep 4.70 · upgrades 4

Shift-vs-baseline reading (deliberate, per the brief): delivery COUNTS are
IDENTICAL to the 1186ca3 baseline (playtest 17; lategame 64 by day 14, 74
by the day-15 roll) — the bot's decisions do not depend on the final
payout — and only money moved: playtest day-9 roll $1,749.64 -> $1,753.13
(+$3.49 from the L2 +2% on the tail deliveries); lategame day-14
$4,918.89 -> $5,081.71 (+$162.82, ~+3.3%, consistent with L2/L3 bonuses
once delivered crossed 15/40 with rep high-water >= 3.5). Floors: playtest
got 17 >= 8, $1,753.13 >= $500, min rep 2.80 >= 2.0; lategame got 74 >= 60
(checks on the day-15 loop end), $6,245.19 >= $3,000, min rep 3.00 >= 2.0.

Economy/day/payout-pinning suites stayed green UNMODIFIED exactly as the
brief predicted: their shops sit at L1 by construction (delivered < 15 at
pin time), so the rank factor is exactly 1.0 on every pinned path. The ten
suites that call `_finalize_payout` (features, color, day, economy, v011,
v018, v032, v037, v040, v042) all pin through the same function they
exercise on a fresh or near-fresh shop — none shifted.

## Interpretation notes / deviations (for review)

1. **Fallback persistence adopted** (brief-anticipated): see the
   high-water section — the max() derivation is a lower bound, unsound in
   the [4.0, 4.25) and [4.5, 5.0] rep bands after any routine rep drop,
   and the level needs the true historical max. `rep_high_water` is
   persisted, validated, absence-tolerant, updated at the single rep
   writer; pre-v0.61 saves bootstrap it from the derivation seed.
2. **Two announcement trigger sites** (`_rep_event` + settle tail) instead
   of one: the tier precedent lives in `_rep_event` only, but rank has a
   second rising operand (delivered) that updates AFTER the payout math in
   the settle — a delivered-driven crossing (the common one: 15/40/80/150
   deliveries with the rep bar already met) would never announce from
   `_rep_event` alone, because `_rep_event` runs before
   `stats.delivered += 1`. The `lvl <= announced_rank` guard makes the
   pair idempotent (the crossing delivery saves twice — harmless, the tier
   pattern already double-saves).
3. **announced_rank invalid-value fallback**: a persisted announced_rank
   outside 1..5 falls back to the derived level (mirror of the tier's
   `tier_for_rep` fallback), on top of the validator rejecting it outright.
4. **Authorized deviation** (top of file): the atmosphere_test stale
   version literal refreshed 0.60.0 -> 0.61.0, parent-approved via
   escalation (one line, check 24's expected value only); the worker did
   not touch anything else outside the allowed-edits list.

## What I did NOT run

- Real Web export / browser gameplay checks — parent/integration owns
  them; pytest's test_build_web.py is mocked unit tests by design.
- Any second Godot process — never; the suite runs, the import rescan, the
  probe and the full ladder were strictly sequential (hazard 1).
- A second full ladder before the authorized pin refresh — run 2 above is
  that re-run, executed after the parent's escalation answer.

## Blockers

None remaining. The atmosphere_test version-literal conflict was escalated
and resolved parent-side (authorized one-line refresh, re-verified as
above). Routing worked (glm-5.3-flash via zai coding plan); no auth/quota
failures.

Stop — parent session reviews, integrates, commits.

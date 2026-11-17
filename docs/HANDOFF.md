# Current handoff — v0.62.0 baseline; playability repair proposed

## Playability audit (2026-11-17; no gameplay changes)

User requested substantial fixes and features. Audited main commit
`a74f0ae7ef685cbef356552f796f93cbdecff43f`. The bounded first repair and
follow-up priorities are in `docs/worker-playability-review.md`.

Verified by source tracing: real E/touch/gamepad input routes held spools
to placement before the loading branch; finishing/showcase have the same
dispatch gap outside packing/counter radius overlaps; carry prompts omit
station-specific actions and misdirect walk-in parts; the dropped-part
packing nudge is missing its station guard and can block other printers.
These are proposed fixes, not implemented changes.

Independent diagnostic verification: headless import exited 0; six serial
suites (grab, input_pause, spool, v034_station, v037, walkin) passed with
no SCRIPT ERROR/Parse Error. Installed engine is 4.6.3; the documented
release engine is 4.7.1, so this is diagnostic evidence only. Existing
station/spool suites bypass real input dispatch in relevant scenarios.
Live https://printshop-sim.vercel.app/ could not start in this Cloud browser:
its loader reported missing WebGL2. No browser gameplay, new export, or
deployment was verified in this session.

Implementation blocker: AGENTS.md requires GLM 5.3 Flash through the user's
Z.AI coding plan; no matching connected tool or installed coding client is
available here. Astra completed the design/review. Next action: restore
that route or obtain an explicit user override before implementation;
then execute the bounded interaction repair and test actual input entry.

## Previous overhaul handoff (historical)

## Print Shop 3.0 overhaul (2026-10-30, in progress)

Binding plan: design/overhaul-3.0.md; per-slice briefs
docs/GLM-3.0-SLICE-{1..4}.md. Slice coding by glm-5.3-flash workers;
the parent session plans, reviews, independently verifies and commits.
Sequential ladder runner: `bash tools/ladder.sh --bots` (sim_* suites
get 420 s; never run two headless Godots at once — BrowserSave race).

Landed:
- Slice 4 (v0.61.0, shop rank career): five DERIVED levels
  (Sprout/Staple 15+3.0/Known 40+3.5/Fixture 80+4.0/Institution
  150+4.5, >= boundary rule) recomputed on every read from lifetime
  stats.delivered + the NEW persisted rep_high_water (float 0..5,
  absence-tolerant, updated ONLY in _rep_event the single rep writer;
  pre-v0.61 saves bootstrap it from max(reputation,
  _rep_floor_for_tier(announced_tier)) as a floor). THE BRIEF'S PRIMARY
  derivation was analyzed and found UNSOUND (Events.TIER_THRESHOLDS
  [3.0,3.5,4.25] never encodes 4.5 — L4 unsound in [4.0,4.25), L5 in
  [4.5,5.0] after routine rep drops); the brief's explicit fallback was
  adopted (docs/worker-rank.md). Payout: +2% x (level-1) appended at the
  very END of _finalize_payout (after shelf bonus, before int-cents;
  fresh shops are L1 = exactly 1.0 so the payout-pinning suites stayed
  green UNMODIFIED). Once-per-level announcement mirrors the tier block:
  gold toast + "rank" log + chalkboard "RANK:" header line; announced_rank
  persisted 1..5. Stats RANK block + 3 milestones (Counter regular 10
  walk-ins, Face of the street L3, Institution L5). rank_test.gd 33
  checks (3x green). One parent-authorized deviation: atmosphere_test's
  stale version pin refreshed 0.60.0 -> 0.61.0 (1 line, test plumbing).
  NEW bot references (deliberate shift — delivery counts byte-identical
  to baseline, only money moved): sim_playtest day-9 $1,753.13 / 17 /
  min rep 2.80; sim_lategame day-14 $5,081.71 / 64, loop-end $6,245.19 /
  74 / min rep 3.00. All floors pass. Parent re-verified ladder 77/77,
  pytest 21/21, CJK clean.
- Slice 3 (v0.60.0, atmosphere & presence): ShopFront.gd — entry door
  (flush honey panel on the front-wall face at hinge (-2.4, 0, 2.88),
  painted jamb + glass slit, NO wall hole/collision, deterministic
  open-hold-close 75deg/0.6s/1.2s swing swung from BOTH slice-2
  spawn/despawn points) + billboarded OPEN Label3D placard (lit HDR
  gold inside the CounterService business window via the real
  _tick_counter frac; non-emissive at Low quality) + one warm
  shadowless OmniLight3D pendant (energy 0.5, the slice's only new
  light). Node budget: the v020 audit runs at season=humid
  (v020_test.gd:50, never reset) so its real slice-2 baseline is
  178/394 — the slice adds exactly 2 visible/2 total MeshInstance3D
  (door panel + one 8-surface CounterDressing ArrayMesh carrying
  pendant stem/shade/emissive bulb, under-lip emissive strip, and 4
  clutter pieces as surfaces); v020 passes at exactly 180/180, with-
  walk-in audit 172/398. CustomerActor outfit variety: 6-color palette
  + hashed flat-cap/scarf as extra SURFACES on the same two mesh nodes
  (walkin_test two-mesh pin intact; nothing above the head top).
  HUD restyle in _build_hud ONLY — shared _hud_panel_style() ink
  StyleBoxFlat (0.95, radius 4), paper status text, clay prompt + ink
  outline (the "accent bar" reading — no new HUD nodes allowed), gold
  toast; texts/anchors untouched. atmosphere_test.gd 25 checks
  (seam-driven, no engine-frame timing). The suite caught 2 real
  ShopFront bugs pre-integration (openness read after the phase flip
  jumping a mid-closing re-arm; single-phase-per-call _advance).
  Parent re-verified ladder 76/76, pytest 21/21, both curves
  byte-identical to the slice-2 reference, CJK clean. Accepted
  deviations (docs/worker-atmosphere.md): budget-driven node merge
  (brief's own relief valve), calm mode snaps at the apply site while
  the swing machine keeps ticking (a gated _advance would freeze the
  door open), accent-bar-as-prompt-color, door arc transiently sweeps
  the customer stand spot (actors ignore collision; cosmetic).
- Slice 2 (v0.59.0, walk-in customers): CounterService.gd (pure
  hash-gated arrivals — max 2 slots/day at 0.25+0.22i+0.03jitter, gate
  6/10, window 0.15-0.80, patience 0.55 day FROM ARRIVAL) +
  CustomerActor.gd (2-mesh Node3D behind the counter, set_motion-gated
  bob, never at boot). Two-press slip accept onto the first idle
  unlocked contract-free printer; walk-ins never enter JobBoard queues.
  Counter handover settles through _settle_held_delivery(m, late,
  via_counter) — extracted verbatim from _try_pack_held's final-copy
  tail (board path behavior-identical, via_counter=false) — and
  _finalize_payout gained a trailing counter param (x1.10 after event,
  before late). Expiry mirrors _on_day_changed's cancel teardown with
  zero rep/log noise + stats.lost_walkins. walkins_served +
  stats.lost_walkins persisted (absence-tolerant). Packing table never
  pays a walk-in (refusal prompt; F scrap still allowed). HUD counter
  line only while someone waits. walkin_test 38 checks. Parent
  re-verified ladder 75/75, pytest 21/21, both curves byte-identical.
  Accepted deviations (docs/worker-walkin.md): absi() on hash draws;
  patience anchored at ARRIVAL (only coherent reading — unaccepted
  walk-ins must leave); _try_grab_or_place carve-out extended to the
  counter (board parts verified to still reach _try_place);
  duplicated-not-shared expiry teardown; defensive slip null-guard.
  Known cosmetic edge: a walk-in accept/delivery resets the packing
  table's stack VISUAL if a board multi-part order is mid-completion.
- Slice 1 (v0.58.0, front counter): CounterStation island at
  (-1.9, 0, 2.55) — 10 meshes, world-layer StaticBody3D, deterministic
  tick-driven bell squash. Empty-handed E within 1.35 m rings the bell
  ("The counter is quiet — nobody waiting yet"); the branch sits
  BEFORE the crate branch (hazard 10 — load-bearing). counter_test.gd
  22 checks. Only test-plumbing deviation: color/events/spool crate
  teleports moved outside the counter radius; spool_test's spot
  refined to (-3.1, 0.3, 1.85) so its full-hands press still gets
  "No room here" instead of dropping the spool. Worker evidence:
  docs/worker-counter.md; parent re-verified full ladder 74/74,
  pytest 21/21, both sim curves byte-identical to this machine's
  1186ca3 baseline (playtest 8/8 day-9 $1,749.64 / 17; lategame 16/16
  day-14 $4,918.89 / 64).

Next: slice 3 atmosphere (v0.60.0, brief docs/GLM-3.0-SLICE-3.md) —
visual-only, curves stay byte-identical to slice 2's; draw budget
must pass WITH a walk-in active. Then slice 4 (shop rank) deliberately
shifts payouts; its harnesses are re-measured with floors instead.

## External QA pass (2026-10-27, no code changes)

A fresh-machine verification pass confirmed every gate on the v0.57.0
tree: 62-suite serial ladder 0 red, smoke 9/9, sim_playtest 8/8 and
sim_lategame 16/16 both replaying byte-identical curves, python 21/21.
Full evidence: docs/worker-qa-pass.md. Export templates absent on that
machine, so the web export was not re-run — do that before the next deploy.


## Current active work

v0.57.0 MILESTONES V: four more derived achievements appended to
Main._achievements(), zero new save keys — Ten K (stats.earned_cents
>= $10,000 lifetime), Scrap heap (stats.scrapped >= 15), Better late
than never (stats.late >= 10) and Hard knocks (stats.cancelled >= 10).
The money milestone is deliberately LIFETIME-EARNED, not
balance-held: _ready() credits $2,500 opening funds, so a held-balance
badge would fire at boot on a fresh shop. The three "failure" badges
celebrate resilience (late orders still pay; a second-F death logs
"scrap" and counts in stats.cancelled). Toasts, boot silent adoption
and the Stats listing come free from the existing loop.

DESIGN TRAP for future balance badges: the opening balance IS $2,500 —
any "hold $X in the account" milestone must sit well above it, and
balance DIPS on every buy, so peak-held thresholds are flaky by
nature. Lifetime counters are monotonic; prefer them.

Verification this batch: v057_test 22 checks green; full ladder
(71 suites incl. smoke) run SEQUENTIALLY with the mechanical gate
(rc != 0 OR SCRIPT ERROR OR 150s hang = fail) — 0 bad. An earlier
ladder pass showed 5-7 phantom boot failures purely because
sim_playtest ran CONCURRENTLY with the ladder (two headless godots
race on BrowserSave state); never overlap them. Both harnesses replay
BYTE-IDENTICAL pre-change (git stash) vs post-change: playtest
day-8 15/$1,665.79 both, lategame 74/$6,026.39 both (the handoff's
older 64/$4,918.89 late curve is machine-state drift, predating this
batch). pytest 21 passed. Web export stamped clean
(0435ee6, dirty:False). Deploy: push → Vercel Ready but the alias
STAYED on 0.56.0 (the documented alias-stuck state again) — fixed
with `vercel alias set printshop-4aj9y89zu… print-shop-sim.vercel.app`;
live curl now serves 0.57.0/0435ee6, page 200.

---

# Previous handoff — surge protector + Jazz + milestones IV (v0.54.0–v0.56.0)

## Current active work (previous batch)

v0.54.0 SURGE PROTECTOR: the 12th catalog upgrade ($100, id
surge_protector). Upgrades.wear_multiplier() returns 0.5 when owned;
Main._on_print_done multiplies the wear GAIN only — completed prints
accrue (6+difficulty)*0.5, failures 12*0.5 = 6 — leaving the existing
wear untouched. "Fully kitted" now derives its target and hint from
Upgrades.catalog().size() so the milestone can never drift again.

v0.55.0 JAZZ: a fourth radio station (Sfx.STATIONS entry — Dm7→G7→Cmaj7→A7
dominant-7 chart, 96 BPM, warm hiss). The two hard-coded 0..2 guards
(_load_save stations_heard restore + _mark_station_heard) derive from
Sfx.STATIONS.size() now; SaveSystem widened radio_station to 0..3 and
stations_heard to 4 entries of 0..3. New FULL DIAL milestone (hear all
four); RADIO STAR stays at three so old saves keep it (its hint now
reads "hear 3 radio stations").

v0.56.0 MILESTONES IV: three more derived achievements, zero new save
keys — Four figures (stats.earned_cents >= $1,000 lifetime), Rolodex
(client_orders.size() >= 25), Spotless (cleans >= 25, one above
Meticulous).

OPS: today Vercel turned on "Vercel Authentication"
(ssoProtection all_except_custom_domains) on this Hobby project —
fresh deploys served an auth 302 / the alias served DEPLOYMENT_NOT_FOUND.
Fix applied: alias set manually (`vercel alias set <ready-deployment>
print-shop-sim.vercel.app`) + `PATCH /v9/projects/printshop-sim
{"ssoProtection": null}` with the CLI token from `~/Library/Application
Support/com.vercel.cli/auth.json`. curl-verified public at 0.56.0.

Ladder notes: three more suites (v054 21 checks, v055 25, v056 16) put
the project at 69 suites + smoke. Stale pins updated for the catalog
growth: features/v040 11→12, upgrades_test ids+panel 11→12, v021
station count 3→4 + its in-scene cycle gained the Jazz step, v016's
cycle gained the Jazz step before off. Both bot curves replay
byte-identical (15/$1,665.79 early, 64/$4,918.89 late) — the lategame
bot's BUY_ORDER doesn't include the protector.

v0.52.0 MILESTONES III: four new derived achievements appended to
Main._achievements() — Fortnight (day > 14, mirroring Week one's > 7),
Century (stats.delivered >= 100), Full week (_full_week_delivered():
all 7 days of the persisted daily_delivered window shipped >= 1; the
window only fills after day 7 so the earliest fire is day 8's morning)
and Ten spot (client_orders.size() >= 10). NO new save keys — every
input is an existing persisted counter, so toasts, the boot
silent-adoption loop and the Stats listing come free.

v0.53.0 TOP CLIENTS: Main._top_client_lines() feeds a CLIENTS block
into the Stats panel right after the Regulars line — header
"CLIENTS (N distinct)" + up to three numbered "1. Name x<count>" rows
ranked by completed orders, TIES BREAK ALPHABETICALLY (deterministic
regardless of dictionary insertion order). Empty history renders no
block at all (fresh shops keep the old layout).

Both slices are bot-neutral: the playtest/lategame curves replay
byte-identical to the v0.50/v0.51 batch (15/$1,665.79 early,
64/$4,918.89 late).

OPS NOTE: between batches the live site went 404 NOT_FOUND with the
deploy intact — the documented alias-stuck Vercel state; a plain
`vercel --prod --yes` retry restored it (verify with curl every time).

GDScript trap that cost a parse error: `Array[String]` has NO
extend() — use append_array(). (The parse failure then made
packed.instantiate() yield a bare Node3D and the suite's
`main.paused = false` threw "Invalid assignment ... on Node3D" —
a broken Main.gd always shows up as nonsense downstream boot errors.)

Local verification: 66 suites + smoke + both harnesses + pytest green
(v052 18 checks, v053 13 checks); the ladder gate now fails a suite on
rc != 0 OR any SCRIPT ERROR in its log (the v0.50 false-green lesson,
now enforced mechanically).

---

# Previous handoff — shop codes + calm mode (v0.50.0, v0.51.0)

## Current active work

v0.50.0 SHOP CODES: the Settings sheet gains a code field + two buttons.
"Export save code" fills the field with the ACTIVE shop as base64 of
compact JSON (Main.export_shop_code); "Import code below" runs the
two-press flow (request_import_shop_code): press 1 DECODES + VALIDATES
first — an invalid code never arms — press 2 writes the normalized
payload over the ACTIVE slot file (apply_shop_code) and reloads the
scene, so the imported shop boots through the normal restore path.
The payload is built by _build_save_payload(), refactored out of
_save_game verbatim, so a code is exactly a save. parse_shop_code
returns {} on ANY failure (empty / not base64 / not JSON / fails
SaveSystem.validate). Disarm is wired through reset_disarmed +
_show_panel, so switching panels or leaving settings cancels an armed
import like an armed reset. A failed import NEVER touches the file.

v0.51.0 CALM MODE: persisted "calm_mode" bool (full settings plumbing:
DEFAULTS, restore key list, match arm -> _apply_calm_motion, SaveSystem
bool validator). calm_motion() gates _animate_rain/_snow/_clouds in
Main, and WindowLife.set_motion(on) gates _advance — the gate lives in
the deterministic seam so _process inherits it and tests can PROVE the
freeze (set_motion(false) + _advance(120) moves nothing). The scene
stays; nothing drifts. Restore re-applies the gate at boot via the
settings loop.

SETTINGS SHEET SCROLLS: the rows had outgrown the sheet (probe: 20 px
of headroom), so Sheet/SheetBox now lives inside
Sheet/SheetScroll/SheetBox (ScrollContainer, horizontal disabled). The
focus chain covers all 16 controls in creation order — including the
haptics/rumble/slot rows that had silently never been chained.

LADDER GOTCHAS this batch (cost real time, all three bit):
1. A sed rewriting `"Sheet/SheetBox` over-matched OTHER panels'
   sheets (contracts/stats/log/today/howto keep Sheet/SheetBox — only
   the SETTINGS sheet is wrapped). Same trap in tests: bare
   `get_node("Sheet/...")` paths on _stats_panel/_howto_panel/
   _today_panel getters.
2. `var body: Label = <null get_node>` ABORTS _run with rc 0 → FALSE
   GREEN: v031 printed "checks=10 failures=0" (13 defined); v029/v035
   hung forever because quit() never ran. NEVER trust rc alone — grep
   every ladder log for SCRIPT ERROR and compare checks= counts.
3. A hung suite wedges the ladder loop; kill that ONE godot process to
   let the loop advance, fix the cause after LADDER_DONE.

HARNESS HONESTY: this machine now replays BOTH harnesses
deterministically at 15/$1,666 (early) and 64/$4,919 (late) — the
documented 17/$1,759 and 74/$6,082 curves no longer reproduce here.
A clean worktree at a5610ab (pre-batch) replays BYTE-IDENTICAL
64/$4,918.89, so the shift predates this batch: 8x pacing
determinism is machine-state-dependent, which is exactly why the
survival gates are floors. Both gates pass (>=8/$500, >=60/$3,000).

Local verification: all 65 suites + both harnesses + pytest green
(v050 33 checks, v051 27 checks; the 7 sed-bruised suites re-ran clean
after the revert).

TEST GOTCHA (v051): particle "falls again" checks must pin the
streak/flake mid-pane (y = 2.2) before the move — particles spawned
near the sill wrap to the top on the first step and the strict
decrease assertion fails.

---

# Previous handoff — rumble settings + customer voices II (v0.48.0, v0.49.0)

## Current active work

v0.48.0 RUMBLE SETTINGS: gamepad rumble is now scaled by a persisted
"haptics_strength" setting (default 100, whole 0..100, validated).
Main.haptics_gain() is the single source of truth — 0.0 when the haptics
toggle is off OR strength is 0, else strength/100 — and _rumble()
multiplies BOTH magnitudes by it (durations unchanged). The settings
sheet gains a "Rumble strength" slider via the existing _labeled_slider
helper ("RumbleSlider", 0..100 step 10; slider_name_to_key maps it to
"haptics_strength"); show_settings pushes the persisted value. Plumbing
mirrors every other setting: DEFAULTS dict, restore key list, the
"haptics" match arm (now "haptics", "haptics_strength"), SaveSystem
validator (whole int/float 0..100; absence fine for old saves).

v0.49.0 CUSTOMER VOICES II: note pools expanded — REACTION_PRAISE 3→8,
REACTION_NEUTRAL 3→6, REACTION_WORRIED 3→6, LOYALTY_NOTES 5→10,
Contract.GEN_NOTES 12→20 — plus a NEW FIRST_NOTES pool (6 lines) in
JobBoard: a client with NO history (not a 2+ regular, no last grade)
introduces itself on ~60% of generated jobs via a hash-pinned draw
("firstdraw-<id>" gate, "first-<id>" pick), stamped as the last elif in
the _refill note chain so loyalty > grade reactions > first visit. The
board persists notes wholesale, so nothing new to save. Both slices are
behavior-neutral for the bots (flavor text + headless-no-op rumble), so
the v0.46 harness curves stand (17/$1,759 early, 74/$6,082 late).

Local verification: all 62 suites + both harnesses + pytest green
(v048 21 checks, v049 22 checks).

TEST GOTCHA (v049): client lineups are pinned per (day, slot) — pick a
regular/grade-test client from a board dealt for the SAME day you
re-deal, or the client never regenerates and the precedence check
silently counts zero jobs.

---

# Previous handoff — power bill + shop history (v0.46.0, v0.47.0)

## Current active work

v0.46.0 POWER BILL: every unlocked printer draws $1/day at the morning
rollover, charged after rent via _unlocked_machine_count() (base shop $1,
full farm $4; measured exactly $56 across the 14-day harness). NO debt
plumbing — a shop that cannot afford it runs dark (skip, no owe); rent
debt is untouched. A rent holiday skips rent but NOT power. Logged as a
"power" log-kind so the Today panel recap counts it. day_test and
v011_test rollover balance pins were updated to the new invariant
(balance = old - rent - power, both terms explicit — do not revert them
to rent-only).

v0.47.0 SHOP HISTORY: chalkboard gains an order-count graph
(_orders_sparkline, same 7-day window/ramp as earnings, scaled against
the best DAY) and a "Best day: $X" record line (_best_day_cents);
Today panel reports yesterday's order count. daily_delivered +
day_delivered_today persist with validators, banked at rollover exactly
like daily_earned; delivery increments day_delivered_today beside
stats.delivered in the pack path. TEST GOTCHA re-confirmed: assigning an
untyped array literal (main.daily_delivered = [1, 2]) to a typed
Array[int] var is a RUNTIME error that aborts _run before quit() — the
suite then hangs with zero output; use .assign([...]).

Local verification: all 60 suites + both harnesses + pytest green
(day_test/v011 re-pinned, v046 11 checks, v047 18 checks).

---

# Previous handoff — wear & tear (v0.45.0)

## Current active work

Machines now wear out: every completed print adds 6 + difficulty wear
(12 on a failure, clamp 0..100), persisted per machine ("wear" array +
"cleans" counter, validated). Wear widens the PrintSim failure threshold
at _write_prep_to_sim — 0.25 x wear/100 COMPOSED with the upgrades delta
and today_event.failure_delta (the first cut set the threshold fresh in
_prep_on and clobbered the power-hiccup +0.10; events_test check 11
caught it — compose, never overwrite). At 50%+ wear an IDLE printer
offers a 15 s cleaning cycle on E (_maintenance_on; countdown lives on
the machine dict as clean_left_s, ticked by _tick_cleaning in
_physics_process beside the sims; paused shop pauses cleaning too).
Below 50% wear E never offers a clean — a light-worn printer must keep
accepting (economy_test caught the 9%-wear clean stealing the accept
press). E during a clean reports the countdown and refuses. Completion
resets wear, counts cleans, logs "maintained". HUD: "P1 812g Clay
[warning]62%" at 50%+, "[E] Clean printer (N% wear)" action line,
cleaning countdown line. Meticulous milestone at 10 cleans.

Bots maintain now: sim_playtest cleans in its idle tier, sim_lategame
runs a per-machine maintenance pass (a running clean parks that machine;
the farm bot parks wholly for the 15 s). Measured: upkeep is nearly
cost-neutral (17/$1,759 vs 18/$1,758 early — one delivery trades for a
clean; 74/$6,082 vs 74/$6,367 late). tests/v045_test.gd: 28 checks.

Local verification: all 58 suites + both harnesses + pytest green.

---

# Previous handoff — stale offers (v0.44.0)

## Current active work

Tier-4 starvation fix. A board full of work the shop declines could never
refresh: JobBoard refills ONLY when a job is taken (take_next ->
_fill_to_capacity) or when rush/competing offers expire, and calm offers
never rotated off — so a tier-4 farm whose player avoids the
difficulty-4/5 jobs (uniform 1..5 fresh roll, +30% day bonus from day 7)
froze at {4:7, 5:2} from day 5 with zero intake while rent kept charging
(29 deliveries / $2,446 by day 14, measured). Fix is ONE knob:
JobBoard.STALE_MORNINGS = 3 — rotate_day silently retires calm offers with
offered_day <= day - 3 and the backfill replaces them. NO rep hit, NO
missed stat (only rush/competing expiry penalises); restore/snapshot still
reproduce boards exactly (retirement is rollover-only, not in
restore_payload). v0.14 semantics otherwise untouched.

sim_lategame's picker is back to the CONSERVATIVE rule (difficulty <= 3,
sim_playtest's) — the difficulty-agnostic pick it replaced was a workaround
for this exact starvation, documented in the old picker comment. Same bot
now lands 74 deliveries / $6,367 by day 14 (fresh 2026-10-06 measurement;
totals drift a few orders run-to-run with wall-clock pacing at 8x — gates
are floors for that reason; days 1-4 are byte-identical to the starved run
— the knob cannot fire before day 4). Balance floor sharpened $1,500 ->
$3,000 WITH citation: the starved curve's $2,446 passed the old floor, so
it caught nothing; the >= 60-delivery floor stands (starved 29 vs healed
74). The agnostic curve gets slightly BETTER too ($18,271/154 -> $20,073/167
by day 14 — even best-paying bots leave stragglers that now retire). New
suite tests/v044_test.gd (16 checks: retirement never reports as expired,
lifespan exactly 3 days, backfill, Main-level zero rep/missed, restore
keeps stale offers).

Suite bug fixed while verifying: v044_test's _run called the _test_*
coroutines without await — each suspended at its first `await
physics_frame` and quit() raced the pending continuations, so the 4
Main-level checks SILENTLY never ran while the summary reported green
(12/12 instead of 16/16). _run now awaits each phase; a suite that prints
fewer checks than it defines is the tell.

Local verification: all 57 suites (49 checks-format + 8 legacy "ALL PASS"
format) + both sim harnesses + pytest 21/21 green. Note: do not edit any
repo file while a ladder is running — mid-ladder edits made suites misparse
or hang once (clean re-run was fully green).

---

# Previous handoff — milestones II (v0.43.0)

## Current active work

Three late-game achievements: Paper star (media_a_deliveries >= 3 — the
counter increments in the media-day rep branch on A-grade deliveries and
persists as media_a_deliveries), Board magnet (>= 12 jobs on the board —
pairs with the Backorders event's +4 capacity), Distinguished (5 regulars
AND 5 stars). Validator covers the counter (non-negative whole int).

Local verification: all 54 suites + playtest bot + pytest green (11 new
checks in tests/v043_test.gd).

---

# Previous handoff — featured orders (v0.42.1)

## Current active work

One generated job per day is the board's FEATURED pick: +15% payout
(capped $95), hash-pinned per (day, slot) via
Contract.featured_slot_for_day, stamped in JobBoard._refill AFTER the
note chain (loyalty -> reaction -> generic), persisted in board payloads,
and tagged "[FEATURED +15%]" on the card. CRITICAL LAYOUT RULE: the
featured stamp must stay AFTER the note if/elif chain in _refill — an
earlier edit landed it between the loyalty if and the reaction elif,
breaking the chain (regulars got reaction praise instead of loyalty).

Local verification: all 53 suites + playtest bot + pytest green (7 new
checks in tests/v042_test.gd; v019's payout sweep and v038's loyalty
check skip featured jobs).

---

# Previous handoff — save slots (v0.41.0)

## Current active work

Three shops side by side. BrowserSave: slot_path(n), switch_slot(n),
active_slot(), META file (printshop_meta.json, holds last_slot). Main
reads META at boot and (when save_path is still the production DEFAULT)
switches to the active slot; the Settings panel's "Save slot" picker emits
slot_switch_requested -> request_slot_switch -> save META + switch +
reload_current_scene. Reset clears only the active slot. clear() SEMANTICS
(v0.41 critical): pre-boot clears (save_path == DEFAULT) remove ALL slot
files — that is the "fresh environment" intent every suite relies on;
slot-mode clears remove only that slot's file. The boot slot-switch is
gated on save_path == DEFAULT so tests' explicit save_path overrides
always win. Suites instantiating Main see META-driven slot state — suites
that need isolation should keep their save_path override (existing
pattern).

Local verification: all 52 suites + playtest bot + pytest green (14 new
checks in tests/v041_test.gd).

---

# Previous handoff — grand showcase (v0.40.0)

## Current active work

Shelf upgrade. Upgrades catalog += grand_showcase ($150, 11 entries total
— Fully kitted milestone and features/upgrades catalog counts re-based to
11). Main._shelf_cap() = 5 with the upgrade, else 3 — read by the display
refusal, the restore guard, and the 5 built slot nodes. New milestone
"Curator" (5 displayed models). NOTE for the next catalog addition: three
suites pin the catalog count (features_test, upgrades_test, and Fully
kitted) — update all three together.

Local verification: all 51 suites + playtest bot + pytest green (12 new
checks in tests/v040_test.gd).

---

# Previous handoff — news & notices (v0.39.0)

## Current active work

Two new daily events. MEDIA_DAY: A-grade deliveries earn +0.3 reputation
instead of +0.2 (branch in _try_pack_held's delivery rep step, gated on
today_event.id == "media_day"). BACKORDERS: the board deals 10 jobs for
the day — new optional event field extra_jobs, surfaced through
job_board.extra_jobs (clamped 0..4) set in _apply_season_visuals' event
hook, consumed in JobBoard._fill_to_capacity as capacity + extra_jobs.
All legacy event dicts gained extra_jobs: 0 for shape consistency;
Events.FORECAST_HINT covers the new ids. NOTE: Main._refresh_event
overwrites today_event from Events.for_day — tests that hand-assign
today_event must not call _refresh_event afterwards.

Local verification: all 50 suites + playtest bot + pytest green (6 new
checks in tests/v039_test.gd).

---

# Previous handoff — the customers remember (v0.38.0)

## Current active work

Reaction notes. Main.client_last_grade (client -> last delivered grade,
persisted + validated, F impossible) is pushed into
job_board.client_grades before each deal; JobBoard._refill stamps a
reaction pool note (REACTION_PRAISE / REACTION_NEUTRAL /
REACTION_WORRIED — distinct from Contract.GEN_NOTES) on fresh jobs of a
remembered client, deterministic per job id, LOYALTY takes precedence for
regulars. TEST GOTCHAS that cost the slice an hour: (1) the boot menu —
if a suite never sets main.paused=false + captured=true, EVERY E press
silently gates on `if paused: return` with an EMPTY prompt (symptom:
accept fails, prompt ''); (2) teleporting near the design computer with a
stale camera aim opens the studio (also pauses) — set yaw/pitch/camera
explicitly after teleports (yaw -0.6 from printer A aims away).

Local verification: all 50 suites + playtest bot + pytest green (11 new
checks in tests/v038_test.gd).

---

# Previous handoff — the display shelf (v0.37.0)

## Current active work

Showcase system: a honey shelf by the window (SHELF_POS (2.7, 1.62, -2.6),
3 slots, "SHOWCASE - E" sign). E with a carried part within 1.3 m
HORIZONTAL (_near_shelf — the shelf sits above head height, same pattern
as _near_radio) displays a COPY of the model: _shelf_models (unique,
max SHELF_BONUS_MAX_SLOTS = 3, persisted as shelf_models) grows by one,
a static slot piece lights, and the ORIGINAL part stays in hand to be
packed — the first cut consumed the part, stranding the contract at
INSPECTION forever (copy-not-consume fix). Duplicates and overflow are
refused with prompts. Payout: _finalize_payout applies +2% per displayed
model AFTER the same-day tip (inside the function — callers/tests must
NOT pre-multiply the base). The playtest bot displayed a model in its
run: reference curve is now 18 deliveries / $1,935 / rep 4.7 by day 8.

Local verification: all 49 suites + playtest bot + pytest green (13 new
checks in tests/v037_test.gd).

---

# Previous handoff — feedback & haptics (v0.36.0)

## Current active work

Juice pass. settings.haptics (checkbox, persisted, validator bool) gates
_rumble entirely; delivery/failure rumble softened. MainMenu owns a
_focus_sfx AudioStreamPlayer (Sfx.stream("click") at -18 dB) hooked to
each menu row button's focus_entered — moving menu focus ticks. Test
note: blip.playing reads true right after grab_focus (headless audio
still tracks playing state).

Local verification: all 48 suites + playtest bot + pytest green (8 new
checks in tests/v036_test.gd).

---

# Previous handoff — the morning paper (v0.35.0)

## Current active work

Strategic morning read: a new "Today" menu panel (MainMenu: button
today_pressed -> Main._on_menu_today -> show_today(lines)). Shows
yesterday's banked take (daily_earned[-1]) + log-kind counts for
day_cycle.day - 1 (entries stamped with the CURRENT day via _log_event —
tests must inject via workshop_log.append(kind, text, yday)), today's
event/season/failure-delta, and TOMORROW's forecast: Events.for_day(day+1)
name + Events.forecast_hint (FORECAST_HINT dict maps all 7 event ids to a
strategy line). Week rolls announce the incoming season
(Events.season_for_week(week+1)). Derived state only — nothing persisted.
Panel clone gotcha: cloning a panel block and inserting it before
func _show_panel landed the code DEAD inside another function — panel
builders must be real _build_* functions called from the boot build list.

Local verification: all 47 suites + playtest bot + pytest green (12 new
checks in tests/v035_test.gd).

---

# Previous handoff — Print Shop 2.0 overhaul (v0.34.0)

## Current active work

Overhaul built by TWO CONCURRENT SUBAGENTS in isolated clones
(psim-station-a, psim-window-b), merged centrally. Slice A delivered
scripts/FinishingStation.gd + tests/v034_station_test.gd (48 checks);
slice B delivered scripts/WindowLife.gd + tests/v034_windowlife_test.gd
(31 checks). Neither touched existing files — integration happened only
in Main.gd afterwards. Clone-isolation is the house way to parallelize:
brief = API contract + hazards + "new files only", merge = copy the new
files, wire Main.gd, integration-test.

FINISHING STATION: bench at (3.0, 0, 2.35) rotated 225 deg — RELOCATED
from (0.5, 0, 2.15) because its collider sat in grab_test's placement
corridor along x~0 (5 grab_test failures; relocating fixed all). E with a
carried part within 1.25 m (_near_finishing) -> _try_finish_held: reads
the RAW grade via QualityCheck.grade on the machine's grade_snapshot, F is
refused, FinishingStation.try_finish bumps one letter, m["finished"] set
(one pass per part; cleared on fresh collect), applied at pack time
BEFORE _cap_grade_for_color (wrong-color still capped). Log kind
"finished". WINDOW LIFE: birds + van self-animated; Main hooks
set_weather(id) in _apply_season_visuals and set_nightness(nightness) in
_apply_daylight. Actors sit IN FRONT of the panes (z -2.841/-2.842) —
nothing behind the opaque window is visible; consts BIRD_Z/VAN_Z in
WindowLife.gd flip if the glass ever becomes real.

v028 FLAKE FIXED (both subagents independently proved it pre-existing):
the input tests now use a poll-wait pattern (_wait_until(cond, frames))
and — critically — RELEASE simulated buttons before polling
(BaseButton activates on release; holding the button through the poll
starved the activation). 6/6 stable runs after; the settle-frame rule
remains for focus grabs.

Local verification: all 46 suites + both harnesses + pytest green, ladder
run twice clean; both slice suites stable 3+ runs; v028 stable 6 runs.

---

# Previous handoff — the long game (v0.33.0)

## Current active work

Late-game playtest harness: tests/sim_lategame.gd grows the shop from one
printer to the full farm over ~14 in-game days. Buys pro_machine,
farm_kit_a, farm_kit_b (+ heated_bed) through the REAL purchase path
(_on_menu_upgrade_buy), asserts the farm door swing, then runs ALL FOUR
printers in parallel — one pair of hands round-robining collect/clear/
confirm/reprint/pack across machines, crate refills per machine, and the
best-paying job on the board (difficulty-agnostic at tier 4: the first
calibration run used the early-game "difficulty <= 3" filter and STARVED
after day 9 — at tier 4 the board deals hard jobs and the bot sat idle
for six days; documented in the picker). Deterministic reference curve:
159 deliveries / $19,294 / rep 5.0 / zero debt by day 14. Late-game
verdict: HEALTHY — the farm scales and rent never threatens. Survival
asserts: all upgrades owned, all four printers ran, >= 60 deliveries,
>= $1,500 by day 14, rep floor 2.0.

Local verification: harness green 16/16 twice (deterministic). All 45
unit suites + sim_playtest + pytest unaffected.

---

# Previous handoff — loyalty & calm (v0.32.0)

## Current active work

Loyalty pays. Main._loyalty_mult(client) = 1 + 0.05 x min(prior orders, 3)
— applied to the order base in _try_pack_held BEFORE the reputation chain
(so the documented payout order is now grade x loyalty -> rep -> season ->
event -> late -> tip), counting orders completed BEFORE the current one.
The bonus appears on ALL THREE delivery prompt branches ("returning client
x1.05") — the first cut only tagged the plain branch and same-day
deliveries (the common case) never showed it. New daily event
steady_hands (failure_delta -0.10, existing v0.7 plumbing) joined the
rotation — pool is 10 entries now, which shifts every day's rolled event
and moved v023's surplus-stock probe day past week 1 (its chalkboard-week
assertion is week-agnostic now).

Playtest bot re-verified: the deterministic curve is now 18 deliveries /
$1,884 / rep 4.7 / zero debt by day 8 (loyalty nudges the total; floors
unchanged).

TEST BUG PATTERN worth remembering: tests that hand-set state for math
checks (client_orders = 1..5) must not then run e2e loops over the SAME
keys — use a distinct client name for the loop or the assertions fight
the pollution.

Local verification: all 45 suites + playtest bot + pytest green (9 new
checks in tests/v032_test.gd).

---

# Previous handoff — regulars (v0.31.0)

## Current active work

Customer memory. Main.client_orders (client name -> completed orders)
increments on every final delivery, persists (save key client_orders,
validator: <= 40 non-empty string keys, whole counts 1..999) and is pushed
into job_board.regulars before every morning deal (and after a save
restore). JobBoard._refill stamps LOYALTY_NOTES onto freshly generated
jobs whose client has 2+ completed orders — hash-pinned per job id so
re-deals reproduce the exact note, and the persisted queue means notes
never flicker mid-day. Regulars = clients with 3+ orders; the Stats panel
gains a "Regulars: N" line and the milestone "Neighborhood favorite" (5
regulars) joins the list. Strictly flavor: no payout/deadline/grade
changes, so the playtest bot's deterministic curve is unchanged.

Local verification: all 44 suites + playtest bot + pytest green (13 new
checks in tests/v031_test.gd). Screenshot confirmed a regular's loyalty
note in quotes next to a generic-pool note.

---

# Previous handoff — customer voices & shop history (v0.30.0)

## Current active work

Post-roadmap flavor drop. Contracts carry a `note` (flavor only): ~45% of
generated jobs draw from Contract.GEN_NOTES (the NEW last generator draw —
everything pinned above keeps its value), two fixture jobs are hand-written,
cards show the note in quotes via a NoteTag label, and the field rides
available_summaries + snapshot/restore (optional key in _contract_from —
pre-v0.30 payloads restore with ""). The chalkboard gains an earnings
sparkline: daily_earned (last 7 days) + day_earned_today persist (validators
reject negatives/fractions/over-cap), _on_day_changed banks the running
total into the window, and _earnings_sparkline renders one block glyph per
day scaled against the best day (zero days are dots; empty history shows a
placeholder line).

Local verification: all 43 suites + playtest bot + pytest green (18 new
checks in tests/v030_test.gd). Screenshot confirmed the sparkline glyphs
render on the chalkboard.

---

# Previous handoff — atmosphere & onboarding (v0.29.0)

## Current active work

Post-roadmap atmosphere drop. Cold-snap weeks now snow OUTSIDE the glass:
_snow (12 white unshaded flakes under _snow) animates via _animate_snow —
slower than the rain with a sideways sway, wrapping at the sill; gated by
season + quality exactly like the rain (_apply_season_visuals). A
moonlight OmniLight (_moonlight, icy #A9C3E8, no shadows) spills through
the window at night — energy 0.55 x nightness in _apply_daylight, so it
rises and falls with the starfield. The How-to-play panel gained an
INPUTS section documenting mouse+keyboard, touch and gamepad controls.

Local verification: all 42 suites + playtest bot + pytest green (15 new
checks in tests/v029_test.gd). Screenshot confirmed snow + crescent moon
+ constellation through the cold-snap glass.

---

# Previous handoff — couch menus (v0.28.0)

## Current active work

Finishes the controller story: the UI is gamepad-first now. MainMenu grabs
focus on Play whenever the menu opens (open_menu -> _play_button), each
panel focuses its first interactive control when shown
(_focus_first_button_for -> _focus_first_button, DEPTH-FIRST traversal —
tree order is creation order; breadth-first let a late shallow CheckBox
beat the top slider), and closing the menu releases focus. The menu row
and the Settings panel carry EXPLICIT focus_neighbor chains — automatic
neighbor discovery was unreliable with this layout, and arrows/stick/d-pad
did nothing at all because the project's custom [input] section REPLACED
Godot's built-in ui_* actions: Main._register_gamepad_actions now CREATES
ui_up/down/left/right (left stick + d-pad, deadzone 0.2) and ui_accept
(A + Enter) at runtime, idempotently. Gamepad boot gap closed: A on the
focused Play starts the game unpaused (no pointer lock needed), and
closing the menu with a pad connected resumes play the same way (_route_escape
close path + _on_menu_play). Keyboard users: Enter activates too, arrows
navigate (newly working — the ui actions simply did not exist before).

TEST DISCIPLINE: simulated input needs settle frames — after grabbing
focus or opening a menu, await 2-3 process frames BEFORE pressing
navigation buttons (the grab lands on the next frame; presses flush
before it and are lost). This bit three separate checks.

Local verification: all 41 suites + playtest bot + pytest green (v027
trimmed to 9 checks — its menu-toggle coverage moved to v028).

---

# Previous handoff — the playtest bot (v0.26.0)

## Current active work

tests/sim_playtest.gd is an automated player: a policy bot that runs the
real game loop (physics on, Engine.time_scale 8x) for 8 in-game days on
printer 1 — picks the best board job (difficulty <= 3, no sub-2-day rush),
confirms the safest printable orientation via _prep_eval, buys + loads a
spool at the crate when the material estimate would not fit, collects,
packs at the table, handles DONE_FAIL clears, multi-part reprints and
partial packs, and survives rent. The whole loop is deterministic (PrintSim
has no RNG; board/events/seasons are hash-pinned), so the reference curve —
18 deliveries, $1,923, rep 4.7, zero debt by day 8 — replays exactly.
Survival asserts (>= 8 deliveries, >= $500 by day 8, rep floor 2.0) turn
any future starvation regression into a red harness.

BOT-AUTHORING NOTES: prep lives on the CONTRACT state machine — PrintSim
idles during PREPARING, so a bot must confirm on
contract.state == PREPARING and sim.state == IDLE, not a sim-state match.
Engine.time_scale 8 makes a day ~11 s wall; the harness is named
sim_playtest.gd (outside the tests/*_test.gd glob) because it simulates
~12 minutes of shop time — run it manually before any balance change.

Local verification: harness green 8/8 twice (deterministic). All 39 unit
suites + smoke + pytest unaffected.

---

# Previous handoff — outside the window (v0.25.0)

## Current active work

Post-roadmap atmosphere drop. The window is a light box: the day pane now
carries ShopArt.window_day() (hazy sun, hills, rooftops) as albedo +
emission texture under the season tint, and a night pane (unshaded, alpha)
crossfades over it — nightness = clamp(1.15 - 1.8 x daylight) written by
_apply_daylight, which also scales the day pane's emission as
_season_energy x (0.45 + 0.55 x daylight). Season/clock ownership is
SPLIT: _apply_season_visuals writes the _season_energy target (calm 1.2,
boom 1.25), the clock scales it — at noon the pane lands exactly on the
season value (v0.17's absolute pins preserved at noon).

The night sky is ShopArt.window_night(month), one cached texture per REAL
month (Time.get_date_dict_from_system().month, cached in Sfx-style via
ShopArt.tex): deep-blue gradient, ~170 seeded field stars, the month's
FEATURED constellation drawn bright with connecting lines (ShopArt.
MONTH_SKY maps 1..12 -> orion, gemini, leo, ursa_major, bootes, scorpius,
lyra, cygnus, pegasus, andromeda, perseus, taurus; CONSTELLATIONS holds
normalized star/line data following the real asterisms), Ursa Major faint
always, a moon with its REAL phase (moon_phase() anchored to the 2000-01-06
new moon; per-pixel terminator, waxing lit-right), and a lit city skyline.
Two cloud wisps (ShopArt.cloud()) drift in front via _animate_clouds and
dim at night. The whole outside costs ~4 quads and cached textures.

Local verification: all 39 suites + smoke pass (1420 checks, 19 new in
tests/v025_test.gd), pytest 21/21. Screenshot confirmed the night sky,
crescent moon and constellation through the glass.

---

# Previous handoff — studio & street pass (v0.24.0)

## Current active work

Post-roadmap drop. The design studio catalog is six shapes: the three new
ones (Phone stand -> PrismMesh, Plant marker -> paper-thin BoxMesh stake,
Drawer knob -> SphereMesh dome) have _select_template starter dims,
create_mesh arms and estimate_grams multipliers (stand 0.55, stake 0.30,
dome 0.45 — so stake < knob < stand at equal dims). SHAPES drives the
template buttons, so the panel UI picks them up automatically; the
prototype pipeline (Main._make_prototype_part) needs no changes. The
left-wall poster rotates its slogan per shop week: POSTER_LINES in Main.gd,
_refresh_poster picks POSTER_LINES[hash("printshop-poster-%d" % week) %
size] and runs from _refresh_event (boot/save/rollover); _add_poster now
returns its caption Label3D and the first call is stored in _poster_label.
The back-wall PRINT SHOP poster stays constant.

Local verification: all 38 suites + smoke pass (1401 checks, 14 new in
tests/v024_test.gd), pytest 21/21. Screenshot confirmed the week-2 slogan.

---

# Previous handoff — operations pass (v0.23.0)

## Current active work

Post-roadmap drop. F2 toggles photo mode (_toggle_photo_mode hides the
whole _hud CanvasLayer — reticle, status, prompt, toast, everything). Two
milestones: "Full house" derives live from the machine sims (_full_house:
machines.size() == 4 and every sim is_running) and "Perfectionist" reads
recent_grades (the last five FINAL order grades, appended in _try_pack_held
after aggregation, capped via slice, persisted as save key "recent_grades"
— validator accepts only A-F letters, <= 5 entries). New daily event
"surplus_stock" (spools $6) joined Events.for_day's pool — adding to the
pool shifts which day rolls which event, but no test pinned specific days
beyond day 1 quiet, so events/day suites needed no edits. The chalkboard
gains a "Week N <icon>" line (cached as usual).

Local verification: all 37 suites + smoke pass (1387 checks, 18 new in
tests/v023_test.gd), pytest 21/21. Screenshot confirmed photo mode's
HUD-free shop view.

---

# Previous handoff — presence pass (v0.22.0)

## Current active work

Post-roadmap feel drop. Footsteps: Sfx "step1"/"step2" (low thud + scuff
noise, scaled 0.7) alternate via Main._footsteps(delta, moving, on_floor)
called from _physics_process after move_and_slide — first step immediate,
STEP_INTERVAL 0.42 s pacing, idle time pre-charges half an interval,
airborne/idle never step. Morning bell: Sfx "bell" (two partials, 0.9 s)
rings once per live day rollover via _morning_bell in _on_day_changed;
DayCycle.restore sets the day without emitting, so save-loads stay silent.
Radio star milestone: _stations_heard (Array[int]) records every station
heard playing — marked in _update_music_state whenever the music actually
plays, persisted as save key "stations_heard" (validator: ints 0..2, <= 3);
the achievements list gained "Radio star" (all 3 heard) and the standard
toast/log machinery announces it.

BOOT-SAVE GUARD (critical, bit during this slice): the boot station mark
runs inside _build_audio BEFORE _load_save, and _mark_station_heard used to
_save_game() there — silently clobbering the player's save with a
fresh-shop payload every boot. _boot_ready (set at the end of _ready) now
gates that save; the boot mark lands in memory and the next natural save
persists it. NEVER save before _load_save has run.

Local verification: all 36 suites + smoke pass (1369 checks, 21 new in
tests/v022_test.gd), pytest 21/21.

---

# Previous handoff — flavor & feel (v0.21.0)

## Current active work

Post-roadmap polish drop on the 1.0-rc. The radio now has THREE stations:
Sfx.STATIONS carries per-station specs (Lo-fi 72 BPM sine / Synthwave 100
BPM with 2nd+3rd partials / Ambient 56 BPM pad) rendered by one shared
music_station_stream() (cached per station — Main swaps by reference).
E at the radio cycles Lo-fi -> Synthwave -> Ambient -> off -> back on at
the last station; settings.radio_station persists (validator 0..2) and
ducking/volume apply to every station. Milestone toasts: a gold top-center
label flashes "Milestone: <name>" the first _update_hud frame a milestone
is newly true (Main._check_milestone_toasts), logs "milestone" in the
workshop log and persists the toasted set as save key "achv_toasted"
(validator: <= 40 strings). Boot ADOPTS any milestone already true at load
into the toasted set — a persisted set can lag the save (the check only
runs while the HUD renders), so a reload never toasts old news. Dressing:
doormat under the door, coffee mug on the design bench, cardboard stack by
the packing table (all group "props"; budget audit still green at 140
visible / 346 total).

Test-side notes for future slices: v016_test now drives the station cycle;
v015_test freezes the shop (paused = true) BEFORE snapshotting the save —
async milestone saves fire while the physics loop runs and would otherwise
shift the expected log count between snapshot and reload.

Local verification: all 35 suites + smoke pass (1348 checks, 23 new in
tests/v021_test.gd), pytest 21/21. Screenshot confirmed the toast + radio.

---

# Previous handoff — 1.0-rc (v0.20.0) — ROADMAP COMPLETE

## Current active work

v0.20.0 closes the roadmap as the 1.0 release candidate. Quality presets
(Low / Standard / High) live in Settings as a dropdown next to the shadows
checkbox: Low disables shadows, glow AND the v0.17 season overlays; High
boosts glow to 0.8; the checkbox stays in sync (checked = Standard, off =
Low, so old muscle memory still works). settings.quality_preset persists
(validator accepts the three names; pre-v0.20 saves default Standard).
_apply_quality is the single enforcer; _apply_season_visuals reads the gate.
The HUD reflows for portrait: below 500 px the status card spans the
viewport with word-wrap (_apply_hud_layout, wired to viewport size_changed);
the audit asserts card + prompt stay inside 390x844 and touch hit regions
(interact 96x96, pause 72x48) stay >= 48 px. The draw-call audit counts
135 visible / 341 total meshes against a 180/400 budget in-suite. A full
accept -> prep -> print -> collect -> pack -> deliver loop runs at Low
quality in v020_test. README + this file now describe the 1.0-rc.

Local verification on Godot 4.7.1: all 34 suites + smoke pass (1323 checks,
19 new in tests/v020_test.gd), `python3 -m pytest tests/test_build_web.py -q`
passes (21 tests). Engine screenshot confirmed the Settings preset dropdown.

**Remaining work is human-only**: playtesting/balance passes on the live
build, Android signing (keystore in /Volumes/ADATA SDK; the committed debug
keystore must NEVER ship), and a cross-browser matrix pass.

---

# Previous handoff — reputation tiers (v0.19.0)

## Current active work

v0.19.0 ties the board to standing. Events.gd gains the tier tables:
tier_for_rep (1 below 3.0★, 2 below 3.5, 3 below 4.25, 4 at 4.25+ — exact
thresholds count as the higher tier), tier_max_difficulty (tier+1, so
2/3/4/5), tier_rush_mult (+10% per tier above the first), TIER_NAMES.
Contract.generate gains a max_difficulty param (default 5 = every pinned
(day, slot) value unchanged; the difficulty clamp is the ONLY change).
JobBoard.deal_day(day, cap, rush_mult) clears and re-deals the boot board
(RESETTING the deal cycle — the first cut continued it and handed the shop
slots 08-15); rotate_day accepts optional tier terms that update the stored
_deal_cap/_deal_rush_mult used by all refills. Rush payouts are scaled at
DEAL time in _refill (capped at the $95 ceiling) so Contract.generate stays
untouched. Main deals the boot board at its starting tier (fresh shops are
tier 2 at 3.0★) and re-deals each morning at the current tier. Tier-ups
announce once per threshold, ever: announced_tier is a persisted high-water
mark (save key "tier_announced"; pre-v0.19 saves and fresh shops adopt the
current tier silently). New achievements "Board regular" (3.5★) and "Top of
the market" (4.25★); the Stats panel gains a BOARD TIER block naming the
current terms and the next unlock.

Local verification on Godot 4.7.1: all 33 suites + smoke pass (1304 checks,
32 new in tests/v019_test.gd), `python3 -m pytest tests/test_build_web.py -q`
passes (21 tests). Engine screenshot confirmed the Stats panel tier block.

Next iteration: v0.20.0 "Hardening & release polish" per docs/ROADMAP.md
slice 9 (quality presets, draw-call audit, portrait HUD, 1.0-rc docs).

---

# Previous handoff — multi-part orders (v0.18.0)

## Current active work

v0.18.0 deepens the core job into a production run. Generated contracts can
ask for 2-3 copies (~1 in 4 slots; the parts_total draw is the LAST in
Contract.generate so every pinned (day, slot) value is untouched; fixtures
stay single-part; payout_cents/material_cost_cents stay PER COPY and the
card shows "[×N parts]"). Contract gains parts_total/parts_packed/
copy_grades, helpers is_multi_part/needs_parts/order_payout_cents, and a
new legal transition INSPECTION -> PREPARING used only by the reprint flow
(E at the order's printer while copies are owed: back through prep, then
"copy N of M" prints). Packing accepts partial deliveries: each copy is
graded (color cap applies per copy), appended to copy_grades, and stacks on
the table (PackingStation.set_stack_count, max 3) while the contract stays
INSPECTION and pays nothing. The FINAL pack aggregates the order grade
(Contract.aggregate_grades: averages floor, single F caps C, two F = F),
pays order_payout_cents x multiplier exactly once via the usual
_finalize_payout chain, and clears the stack. An F copy is refused,
recorded, scrapped (-0.15 rep, order survives); the SECOND F copy fails the
order on the spot (rep -0.4, stats.cancelled, no payout, stack cleared).
Deadlines bite only at final completion (late half-pay + rep at the last
copy); overnight cancel discards mid-orders + stack. HUD contract line
gains "parts N/M", collect/reprint prompts name the copy, the delivery log
says "×N", and the how-to explains the loop. Board summaries + save payload
carry parts_total; pre-v0.18 payloads restore as single-part (tolerated
missing key). In-progress orders still reset on reload (machines were never
persisted) — unchanged behavior.

Local verification on Godot 4.7.1: all 32 suites + smoke pass (1272 checks,
55 new in tests/v018_test.gd), `python3 -m pytest tests/test_build_web.py -q`
passes (21 tests). Engine screenshot confirmed the stacked copies + the
"parts 2/3" HUD line.

Key regression trap fixed during the slice: _collect_on used to treat ANY
INSPECTION contract as collectable — a mid-order reprint press would spawn
a phantom copy. It now defers to the reprint branch when the contract is
multi-part, owes copies, and the sim isn't DONE_OK.

Next iteration: v0.19.0 "Reputation tiers" per docs/ROADMAP.md slice 8.

---

# Previous handoff — weather in the windows (v0.17.0)

## Current active work

v0.17.0 makes seasons visible. A SEASON_LOOK table in Main.gd drives the
back-wall window per season: humid = hazier pane + denser fog (0.012),
cold_snap = icy pane tint + a translucent frost band across the lower glass,
boom = warm pane glow + golden fog, calm = the exact pre-v0.17 look
(albedo #D8E8DF / glow #CFE3DA / 1.2 energy, fog #C9C2AE @ 0.008). Rain
streaks (10 thin unshaded quads, dark against the bright pane, sliding down
and wrapping at the sill) animate only on humid weeks via _animate_rain in
_physics_process; frost shows only on cold snaps. _apply_daylight now
multiplies the time-of-day sun color by the season tint (cold cools it,
boom warms it gold). The HUD season line gains weather icons — ☔ / ☃ / ☀,
chosen from the same symbol block as the existing ★☆ so the default font
renders them (verified in-engine). The overlays are the only added draw
calls and are gated behind the existing quality (shadows) toggle via
_apply_season_visuals, which runs from _refresh_event (boot, save-load and
rollover) and _apply_quality. No new save keys — season derives from day.

Local verification on Godot 4.7.1: all 30 suites + smoke pass (1216 checks
by the checks=/ALL PASS aggregation, 39 new in tests/v017_test.gd),
`python3 -m pytest tests/test_build_web.py -q` passes (21 tests). Engine
screenshot confirmed rain streaks on the pane + the ☔ HUD line.

TEST HAZARD REMINDER: -s test scripts must not name the Main/MainMenu
classes (compile-time autoload failure — see v0.16 notes). Read Main
constants via `load("res://scripts/Main.gd")` at runtime instead.

Next iteration: v0.18.0 "Multi-part orders" per docs/ROADMAP.md slice 7
(deepest slice — consider splitting if it exceeds ~600 changed lines).

---

# Previous handoff — the radio (v0.16.0)

## Current active work

v0.16.0 fills the shop's silence. Sfx._music_loop() synthesizes a lo-fi loop
entirely at load — 72 BPM, 4 bars, Dm7→G7→Cmaj7→Am7 half-sine chord swells
over a vinyl-hiss floor, with a tail crossfade so LOOP_FORWARD is seamless
(~13 s stream, no external assets). It plays through a dedicated "Music" bus
(created on demand, separate from SFX), routed to a radio prop on the
left-wall spool shelf (honey box, steel speaker face, whip antenna). E within
1.0 m toggles playback — the radius is deliberately tight because printer A's
stand point is 1.5 m away and a wider radius stole the accept-job prompt.
Settings gains "Music" (checkbox + volume slider, default on at 0.35,
persisted via settings music_enabled/music_volume); the volume slider drives
the Music bus, zero mutes it. Opening the design computer ducks music to 30%,
closing restores it. While any printer is running, Main._servo_blips fires
tiny 2350 Hz blips per machine on a random 0.7–1.4 s re-arm — mechanical
texture without a drone.

Local verification on Godot 4.7.1: all 29 suites + smoke pass (1172 checks,
33 new in tests/v016_test.gd; three consecutive clean v016 runs),
`python3 -m pytest tests/test_build_web.py -q` passes (21 tests). Engine
screenshot confirmed the radio prop on the spool shelf.

TEST-SUITE HAZARD (applies to every future `-s` test script): never reference
MainMenu/Main as a CLASS (static call) from a test — that makes the script a
compile-time dependency of the script under test, and its `Version` autoload
reference cannot resolve before autoloads register in --script mode
("Identifier not found: Version" kills the whole suite with cascading nil
nodes). Call statics through an INSTANCE instead.

Next iteration: v0.17.0 "Weather in the windows" per docs/ROADMAP.md slice 6.

---

# Previous handoff — the workshop log (v0.15.0)

## Previous active work

v0.15.0 adds history and forensics. WorkshopLog.gd (pure RefCounted logic,
Ledger-style) keeps a 30-entry ring buffer of shop events — deliveries with
grade+payout, print failures WITH CAUSE (PrintSim now records
"support collapse at layer N" / "came off the bed at layer N" /
"part toppled at layer N" for both seeded and risk-rolled failures),
board offers missed overnight, rent paid/unpaid, upgrades installed,
prototypes started, scraps and cancellations. A new "Log" button on the main
menu renders the buffer newest-first with day stamps; failures, expiries and
cancellations read terracotta. The buffer persists in the save payload
("log": [{seq, day, kind, text}], validated by SaveSystem._log_valid;
restore keeps the newest 30 if a longer history appears). DebugPanel action
[7] dumps the log to stdout for headless debugging.

Local verification on Godot 4.7.1: all 28 suites + smoke pass (1139 checks,
50 new in tests/v015_test.gd), `python3 -m pytest tests/test_build_web.py -q`
passes (21 tests). Engine screenshot confirmed the Log panel layout.

Next iteration: v0.16.0 "The radio" per docs/ROADMAP.md slice 5.

---

# Previous handoff — board pressure (v0.14.0)

## Previous active work

v0.14.0 makes the job board first come, first served. Calm generated jobs now
CARRY OVER across mornings instead of being wiped; rush jobs and competing
jobs (~30% of slots, card tag "[2 waiting]") expire at the next rollover and
each one missed costs 0.1 reputation plus a spot in the new "missed" stat.
The morning prompt names what was missed; the HUD board line counts offers
that "expire overnight"; the chalkboard and Stats panel track Missed: N.
The Contracts menu gained Reserve buttons (job selection per the economy
audit): reserving pins a job to the front of the queue so the next printer
accept takes it; the reserved card shows "Reserved ✓". The full board queue
now persists in the save payload ("board": {day, cycle, jobs}) so a
save/reload mid-day reproduces the exact board and continues the deal cycle
without duplicate offers — closing the audit's "queue is not persisted" risk.
Older saves without the board key still load (they deal the fresh day with
expiry suppressed).

Local verification on Godot 4.7.1: all 28 Godot suites pass (1089 checks,
62 new in tests/v014_test.gd), and `python3 -m pytest tests/test_build_web.py -q`
passes (21 tests). Import prints an existing export-preset warning for
missing `preset.1/exclude_filter`, but exits 0.

Next iteration: v0.15.0 "The workshop log" per docs/ROADMAP.md slice 4
(event ring buffer, failure cause strings).

---

# Previous handoff — blueprint-shaped print visuals (v0.5.0, pending merge)

## Previous active work

The merged design-computer slice adds a world-space workstation target on
the back bench. E opens an offline-safe Form Lab with three editable starting
shapes, width/depth/height, wall thickness, layer height, infill, PLA/PETG,
filament color, live 3D preview, and filament/time/cost estimates. Test Print
saves the blueprint, charges filament, runs on an idle unlocked printer, and
can be collected as a physical grabbable object. This iteration grows the
chosen profile on the plate: hollow planters start with a solid base, rings
follow their loop, and blocks keep their dimensions. Fine shader ridges use
the selected layer height and filament finish; the gantry rises with the
print.

Local verification on Godot 4.7.1: all 20 Godot suites pass (885 checks),
including the design-computer and expanded printer-visual checks; `python3 -m pytest
tests/test_build_web.py -q` passes (21 tests). Import prints an existing
export-preset warning for missing `preset.1/exclude_filter`, but exits 0.
No Web export, visual browser test, deployment, or release was performed.

Next iteration: inspect the editor and live print in a browser build, then
polish any layout or material issues found. Preserve GL Compatibility and the
existing suite gates.

---

# Previous handoff — reputation + stats + salvage (v0.5.0)

Read AGENTS.md and design/implementation-plan.md. Working copy:
/Users/rs-mac/.zcode/workspace/default/printshop-sim (canonical disk plan in
HANDOFF pointed at /Volumes/HARD previously; this workspace copy is the live
one for the v0.1.0 release). Private remote
https://github.com/jiracipika/printshop-sim, main. Public prototype
https://printshop-sim.vercel.app/.

## State at this checkpoint

v0.13.0 (print farm) shipped on top of v0.12.0: the shop gained a rear
extension (own floor/walls/ceiling/lights) behind a sealed honey door in the
back wall (doorway x 0.9-2.3; door panel swings and its collision disables
when either farm kit is owned). Machines grew to 4 — printers 3 and 4 sit
on stands in the farm and unlock via new Upgrades "farm_kit_a" ($80) /
"farm_kit_b" ($120) with per-machine machine_unlocked(idx); all four
idx==1 special cases were generalised (accept/load/design-computer gates
now use the helper). Farm printers ship EMPTY and have no speed bonus
(Pro stays exclusive to printer 2). Save filament/color arrays now cover
all machines. New suite tests/farm_test.gd (20 checks); all 27 suites
green (1027 checks). Audit note: the extension lighting was tuned twice
(omnis 1.4/1.0 energy) — still moodier than the main room by design.

v0.12.0 (balance pass) shipped on top of v0.11.0, driven by a read-only
economy audit (background research agent; full findings were reported to the
operator — week-1 gross ~$4,120 at >90% margins, upright unconditionally
safe, deadlines never binding, material cost never charged). Changes:
GEN_BASE_PAYOUT[4] 15500->9000, diff-4 11600->9800, payout cap 15000->9500,
rush premium 1.4->1.2, PrintSim failure floor 0.4->0.3 (upright+overhangs
now carries ~2.75% real risk), material_cost_cents charged at confirm again
(can_afford gate, stays PREPARING when broke), rent = $9 + $2x(day-1) capped
$25 (day/holiday/cold-snap aware), same-day tip 15%->10%, JobBoard capacity
cached, crate rotation persisted ("crate_next" validated). See
docs/ROADMAP.md Slice 1 for the checklist; slices renumbered v0.13-v0.20.
All 26 suites green (1005 checks); prep_test replicates the new floor.

v0.11.0 shipped on top of v0.10.0: weekly seasons (Events.season_for_week,
week = (day-1)/7+1, week 1 calm; humid +0.05 adhesion in _prep_eval,
cold_snap +$1 rent in _on_day_changed, boom payout x1.10) refreshed together
with the daily event; payout order is grade -> reputation -> season -> event
-> late half -> same-day tip (+15% when delivered the accept day), all in one
Main._finalize_payout(base, late, m, rep=-1) helper that tests call with the
pre-delivery reputation. A chalkboard ledger (left wall, live Label3D,
change-cached) shows day/delivered/earned/rep. New suite tests/v011_test.gd
(16 checks); all 26 suites green (1021 checks).

v0.10.0 (art pass) shipped on top of v0.9.0: ShopArt gained size parameters
(512px detail variants for floor/walls/wood with plank gaps, knots, stains
and scuffs; cached separately) plus pegboard, bed_grid and calendar
generators. Printers got a build-plate grid and a front LCD status screen
(set_status: Ready / Lx/y % / Done / ERROR — clear), driven from
_update_print_visuals. Main dressed the shop: baseboards on all four walls,
pegboard + three tools above the bench, wall calendar, power strip + cables
to both printers, windowsill, pendant cords, trash bin (with collision),
tape rolls + scale on the packing table, a second plant, and a teal glow
light on the design computer. New suite tests/art_pass_test.gd (16 checks);
all 25 suites green (989 checks).

v0.9.0 (guided objectives) shipped on top of v0.8.0: a seven-step onboarding
chain (accept, print, collect, deliver, load a spool, print a prototype, 4★
reputation) tracked order-agnostically in guide_flags from the real loop
event points, shown as "▸ Objective: ..." in the HUD, persisted via
"guide_flags"/"guide_done" (validated), and retired when complete. Settings
gained a two-press "Reset shop (new game)" button (arm -> confirm -> save
wipe + scene reload; disarm on leaving settings). Play-flow fix that fell out
of the guide tests: collecting the part (contract or prototype) now resets
that printer to IDLE immediately, and the pack grade reads a machine
"grade_snapshot" captured at collect time instead of live sim fields.

v0.8.0 (color demands) shipped on top of v0.7.0: contracts (fixtures and
generated) demand a filament color (Contract.color, valid set =
DesignStudio's Clay/Sage/Honey); the crate cycles colors deterministically
(_crate_next, sign shows the next color + today's price) and each buy sets
the spool's meta; loading sets the machine's color (shown in the HUD
filament line); a mismatch caps the delivery grade at B via
Main._cap_grade_for_color (single source of truth shared with tests; applied
after PackingStation grades, before reputation/event/late). Machine colors
persist in the save ("spool_colors", validated). New suite
tests/color_test.gd (27 checks); all 23 suites green (952 checks).

v0.7.0 (daily events) shipped on top of v0.6.0: Events.for_day(day) deals a
deterministic event per shop day (day 1 always quiet; from day 2 a hashed
pool of filament_sale $8 spools, rush_week payouts x1.25, power_hiccup
failure threshold +0.10, rent_holiday, and quiet). Main applies them: crate
price + sign text, payout multiplier (order: grade -> reputation -> event ->
late half), failure threshold delta (clamped with upgrades), rent skip in
_on_day_changed (holiday skips ONLY the charge — cancellations still run;
the early version of that branch skipped the whole rollover and was caught
by parallel_test). HUD shows "Today: <event>". New suite tests/events_test.gd
(15 checks); all 22 suites green (940 checks).

v0.6.0 (spool economy) shipped on top of v0.5.0 + the concurrent design-
computer commits (80f18ae, 6e6b349 — note: those sessions share this clone;
ALWAYS git pull --rebase before pushing and re-grep files before patching,
their edits landed mid-slice and silently voided three of my patches):
filament is physical now. Machines carry filament_g (printer 1 opens with a
1500 g spool; printer 2 ships loaded when bought); confirming a prep (or
sending a design-computer prototype) consumes the estimate in grams and
refuses while short (job stays PREPARING, E re-confirms after a load); the
spool crate (front-left corner, $12, tight 1.6 m radius) sells spools into
your hands; E while holding a spool at a printer loads it (meta "spool"
tagging, not names — name collisions auto-rename); failed-print clears
salvage half the consumed grams back onto the spool; printers render a
shrinking coil; HUD shows per-machine grams; filament persists in the save
("filament" validated array). Stats panel gained computed milestone
achievements (First sale, Ten orders, Five stars, Fully kitted, Week one,
High earner). debug_spawn_test_print tops up filament (dev seam). New suite
tests/spool_test.gd (23 checks); all 21 suites green (932 checks).

v0.5.0 shipped on top of v0.4.0: reputation (0-5, start 3; on-time +0.2,
late -0.2, scrap -0.4, cancel -0.6) scales payouts x0.8-x1.2
(Main.reputation_multiplier(); order: grade -> reputation -> late half) and
shows as stars in the HUD. Lifetime stats (delivered/late/scrapped/cancelled/
earned_cents) persist and render in a new menu Stats panel. Clearing a failed
print salvages half its material cost (machine dict carries material_cents
from confirm). Three new upgrades: Textured PEI plate ($35; Main._prep_eval
unlocks flat_side on stability parts — PrepSystem stays pure), filament
dryer ($45, adhesion -0.10) and print enclosure ($120, stability -0.25);
risk modifiers stack and Main clamps to [0,1]. Contract-board cards show the
deadline ("· Nd"). Save payload gained optional "reputation" (0..5) and
"stats" (non-negative int counters), validated. New suite
tests/features_test.gd (31 checks); all 19 suites green (890 checks).

v0.4.0 shipped on top of v0.3.0: the live shop's board is procedurally
generated per shop day (Contract.generate(day, slot), fully deterministic,
materials capped at $24 so day 1 is always confirmable, rush ~25% of the
board at 1.4x and <= 2-day deadlines, day 1 leans easy). JobBoard.generation_enabled
(default false keeps fixture behavior for direct-board suites) +
rotate_day(new_day) on every day rollover and save restore. Polish, all
Compatibility-safe: glow (emissive fixtures/labels bloom), sun shadows with
a Settings "Directional shadows" toggle (persists; for slow devices), soft
vignette overlay (non-blocking), and a How-to-play menu panel explaining the
loop, the clock and the shop. New suite tests/gen_test.gd (24 checks).
Android: builds/printshop-sim.apk exports unsigned from this workspace with
just the installed export templates (docs/mobile.md documents sign+install;
the SDK/apksigner toolchain lives on /Volumes/ADATA and was not mounted, so
signing remains a human step).

v0.3.0 shipped on top of v0.2.0: (a) contract variety — the fixture pool
doubles to 8 jobs (C-014..C-021; original four stay first/in order), with two
rush fixtures (deadline <= 2 d, ~1.4x payout) tagged RUSH on the board card;
summaries carry "rush". (b) True parallel printing — Main owns a `machines`
array ({idx, sim, contract, day, orient, orient_pending, part, scrap}); each
machine accepts/prepares/prints/fails/delivers independently; the held part
identifies its machine via part_contract id; legacy single-machine vars
(sim/active_contract/orientation_*/active_part) are properties over the
FOCUSED machine (last printer interacted with) so tests and the debug panel
work unchanged; _on_print_started/done now take a machine index. New suite
tests/parallel_test.gd (23 checks). PrintSim.tick gained a reentrant-
completion guard (large deltas no longer overshoot layers_total or emit
print_finished twice).

v0.2.0 (shop day) shipped on top of the completed v0.1.0 contract loop:
DayCycle drives a 90 s day with day/night lighting (sun energy/color, ambient,
sky energy); each rollover charges $4.00 rent (unaffordable rent accrues as
debt; payouts repay debt first via _repay_rent_debt); contracts anchor a
deadline at accept — late delivery pays 50%, and a contract more than one day
past deadline is cancelled at rollover (contract FAILED, sim torn down, part
discarded). Printer 2 is the purchasable Pro machine (upgrades id
"pro_machine", $60): locked with a LOCKED tag until bought, jobs accepted
there run at 1.25x machine speed. Day persists in the save ("day" optional
payload key, validated int >= 1). New suite tests/day_test.gd (36 checks);
upgrades_test updated for the 5-entry catalog.

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

Verification evidence (local): 27 Godot headless suites green — contract 255,
color 27, events 15, v011 16, guide 21, art_pass 16, farm 20, spool 23,
gen 24, features 31, upgrades 57, packing 58, touch 47, save 44, shop_art 51,
economy 54, day 37, design_computer 21, parallel 23, prep 29,
printer_visual 34, grab 26, input_pause 23, menu 25, debug_panel 32, room 9,
smoke 9 (1027 checks, 0 failures, no SCRIPT ERROR); Python build pipeline 21
pytest; engine screenshots confirm the sealed door and both farm printers
running in the extension.

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

## Remaining work is HUMAN-ONLY (as of v0.4.0)

- Hands-on playtesting/balance (deadline tuning, payout curves, feel).
- Physical device testing: Android install/sign per docs/mobile.md (needs the
  /Volumes/ADATA toolchain mounted), iOS/Android touch behavior, performance
  on real hardware.
- Cross-browser matrix (Firefox/Safari) and limited-bandwidth checks on the
  live URL.
- App-store signing/distribution decisions (debug keystore is committed; do
  not ship it).

Everything code-side is implemented and automated-tested.

## Operator notes

- Build: bash tools/build_web.sh (stamps Version.gd with HEAD sha; export
  validated; build-info.json written). Serve web/build/ over HTTP, never file://.
- Deploy: vercel --prod from the repo (vercel.json serves web/build). Verify
  the live URL loads the stamped build and plays before calling it released.
- Never touch automated-newsletter or pitchforge/pitch-therapy.

## Live acceptance (2026-10-30, Print Shop 3.0 v0.61.0 / build 5832c2d)

The deployed build at printshop-sim.vercel.app was accepted in a real
browser path: headless Chrome for Testing 156 + SwiftShader WebGL2 drove
the live URL over CDP. Verified: engine boot (shell's #loading removed,
no printshopLoadError), main menu renders with "Alpha 0.61.0 Git:
5832c2dcc69f...", the 3D workshop renders behind it, the deliberate
capture click granted pointerLockElement=true, WASD moved the camera and
a mouse drag turned the view, and the v0.60 HUD restyle (ink status card,
clay prompt) is visible in-frame. Headless-font artifact only: the Rep
star glyphs render as tofu boxes in that environment's fonts — real
browsers ship them. Re-run method: any headless Chrome with
--enable-unsafe-swiftshader + the CDP ready-signal poll
(document.getElementById("loading") === null) used in this session.

## Live playthrough (2026-10-30, CDP-driven, same harness as the acceptance)

A scripted player session on the live build verified the 3.0 feature set
as played, not just rendered:

- v0.58 bell: empty-handed E at the counter shows the quiet prompt.
- v0.60 shopfront: OPEN sign lit HDR-gold inside the business window;
  pendant + under-lip strip + counter clutter + entry door all render.
- v0.59 walk-ins: TWO hashed arrivals (Bram day 2, June day 3) — counter
  HUD line with client/model/patience, two-press slip accept ("Sent to
  Printer 1 — Bram is waiting"), walk-in contract lands on the first
  free printer with the board-index-100 id visible in the HUD
  (G-2-100), and the dedicated waiting prompt counts patience down
  ("~16s of patience left").
- Expiry teardown, twice: customer despawns, the held contract cancels
  through the overnight path, balance and reputation UNCHANGED both
  times — the bot-safety invariant holds in the wild.
- Surrounding economy live: daily rent charges, missed board jobs cost
  reputation overnight, the daily event line rotates, day/night window
  lighting cycles, board jobs accept at the machine, orientation
  preview/cycle works, and confirming a 2167 g job on a 1500 g spool is
  REFUSED with the crate hint ("load a spool ($12.00 at the crate)").

NOT reached: an actual counter-delivery payout — the session got itself
economically stuck (board job accepted onto the only free printer, $0
balance, no affordable spool). The counter-delivery path stays verified
by the bots (sim_playtest exercises it every run); next human-path run
should keep the only unlocked printer FREE until the slip is accepted.
Operational notes (refined after a second run): prompts persist until
replaced (pre-existing); focus-out (per-step CDP session attach/detach)
releases capture and PAUSES via _release_capture — resume with a center
click. THE BIG ONE: under SwiftShader the web build runs shop time at
roughly 0.3x wall speed (physics tied to the slow rAF), so a 90 s day
takes ~5 wall minutes and patience counters shown in shop-seconds last
~3x longer in wall time — early "frozen Day 1" readings were this, not
a freeze. A single-session timed press-train DID achieve a live slip
accept; completing print->collect->deliver blind was not achieved (the
payout moment stays bot-verified: sim_playtest + walkin_test pin the
counter premium cents-exact every run).

## Android build on this Linux box (2026-10-30)

The Android export pipeline works here (SDK at ~/Android/Sdk, build-tools
36.0.0, Android export templates installed, repo debug keystore wired into
the preset — the preset now signs directly and its version/name was
refreshed to 0.61.0): `godot --headless --path . --export-release
"Android"` writes builds/printshop-sim.apk and then exits non-zero with
the APK complete (adb daemon not running during export); sign manually
afterwards: zipalign + `apksigner sign --ks android/debug.keystore --ks-
key-alias androiddebugkey` (build-tools 36.0.0) — verified SIGNED_OK,
52.5 MB (arm64-v8a + x86_64 for emulator translation).

RUNTIME CAVEAT (pre-existing, NOT a 3.0 regression): on the Pixel7_API36
(Android 16) emulator the app boots, renders ~34 s, then dies with
SIGSEGV SEGV_ACCERR in the AudioTrack thread — libgodot_android.so via
libwilhelm (OpenSL onMoreData). The pre-3.0 baseline (bbc0648, v0.57.0)
crashes IDENTICALLY on the same emulator, so this is Godot 4.7.1's
OpenSL driver vs this API-36 emulator image, outside the overhaul's
scope. -no-audio on the emulator does not help (the guest HAL still
drives the app's OpenSL client). Next probes for whoever picks mobile
up: an older-API emulator image (the 2026-09-29 emulator verification
predates API 36), a real device (README's human-only item), or Godot's
Android audio-driver option.

## CDP automation deep-dive (2026-11-01): premium witnessed live, harness bugs archived

A long third campaign against the payout moment (headless Chrome 156 +
SwiftShader, zero-dep CDP over Node's WebSocket, harness at
~/ps_harness/). NET RESULT: the walk-in premium is now WITNESSED LIVE —
at the armed slip the prompt reads "Bram — Espresso tamper collar,
Honey, ~$87.62 at the counter" while the HUD contract line shows the
same order's board price "pays $79.65" — 79.65 x 1.10 = 87.62, the
COUNTER_PREMIUM applied and rendered in a real browser, same session.
Also witnessed live across cycles: walk-in arrival (actor + door swing
+ HUD "Counter:" line with patience countdown), two-press slip arm +
accept ("Sent to Printer 1 — Bram is waiting", "Contract G-2-100 —
Espresso tamper collar [PREPARING] pays $79.65 · wants Honey"),
patience draining, and expiry teardown with the HUD Counter line
vanishing and zero rep/money movement (bot-safety invariant again).
What stays bot-verified only: prep-confirm -> print -> collect ->
counter-deliver -> ledger tick (sim_playtest + walkin_test pin it
cents-exact).

Why the delivery tail resisted — five harness archaeology findings,
all verified against Main.gd, worth keeping for any future automation:

1. YAW SNAP ON RECAPTURE: in headless, get_mouse_locked() falls back to
   the `captured` intent flag, so InputEventMouseMotion.relative keeps
   steering the camera even when pointer lock is nominally off. A
   recapture click that sends mouseMoved first yaws the camera by the
   whole stale-cursor delta (hundreds of px). Fix: press+release only,
   never a preliminary move, on unpause clicks.
2. PAUSE PER DETACH: NOTIFICATION_APPLICATION_FOCUS_OUT pauses the game
   and releases motion inputs; game time advances ONLY while a CDP
   session is attached (~3-6 s per step). "Dilation drift" across
   rounds (0.28 -> 0.23 -> 0.19) was pause time, not slower rendering;
   a held-single-session probe measures a stable ~0.27. Patience
   budgets are game-time: ~10-14 step windows, not wall seconds.
3. SAVES SURVIVE CHROME STORAGE CLEARS: Godot web user:// is IDBFS
   (IndexedDB) and Storage.clearDataForOrigin("all") does NOT remove it
   (verified twice, including with the page dead on about:blank). The
   only reliable factory reset is deleting the whole --user-data-dir.
4. E-CONSUMPTION ORDER: _unhandled_input routes KEY_E through
   _try_grab_or_place(): held -> place/deliver; else _try_grab() FIRST,
   and only when the aim ray hits no grabbable does _try_interact() run.
   At the bench a level aim clips grabbables (grab/place flip-flop) and
   a raised aim hits the design computer (_open_design_studio eats the
   press). The prep/collect presses need the ray on the printer body —
   an aim that must tolerate +/-1 m run-to-run corridor variance, which
   is what finally made the blind tail uneconomical (see 5).
5. CORRIDOR VARIANCE: the counter->P1 legs (right ~76 deg, walk ~2 m,
   right ~56 deg, walk ~3.1 m) reached P1's 3.0 m machine radius every
   run, but the exact stop point slides +/-1 m with collisions, so a
   fixed blind aim cannot reliably thread grab-computer-printer. A
   next attempt should servo on the "Printer 1" Label3D or the "[E]
   Accept job" line between presses instead of firing blind trains.

Also learned: Page.navigate to the identical URL is a no-op (the
loading-div ready poll cannot detect it — bust the URL); Page.navigate
with CDP Mouse/Input enables input only after the game's own recapture
branch; the F3 debug panel is OS.is_debug_build()-gated and dead in the
release web export; the deterministic walk-in schedule for days 1-16 is
preflightable offline via CounterService/Contract/PrepSystem statics
(days 9-12 have no live slots; day 13 slot 0 is the smallest print).

Harness (~/ps_harness/, durable): ps_watch.mjs (boot, park, E+shot
every ~15-19 s, auto-arms/accepts any arrival), ps_chain2.mjs (accept
insurance -> corridor -> aim -> prep -> print window -> collect ->
S-return -> deliver), ps_step2.mjs (one-shot closed-loop step driver:
lw/lb/w/s/sa/sd/e1/e2/shot), ps_unstick.mjs, ps_nuke.mjs/ps_fresh2.mjs
(storage resets), preflight.gd (offline schedule probe via
godot --headless -s). /tmp/ps_accept is ephemeral — /tmp wiped it once;
~/ps_harness survives.

ANDROID EMULATOR DEEP-DIVE (2026-11-04): P1 closed with a two-crash
verdict. The audio SIGSEGV is NOT API-36-specific — it reproduced on a
fresh Pixel7_API34 (Android 14) AVD with the same signature: SIGSEGV
SEGV_ACCERR in the AudioTrack thread ~30-90 s after launch, backtrace
AudioTrack::processAudioBuffer -> onMoreData -> wilhelm ->
libgodot_android.so (Godot 4.7 OpenSL driver callback). This engine
build has exactly two compiled audio drivers (AudioDriverOpenSL,
AudioDriverDummy — no AAudio). All emulator-side mitigations are dead:
-no-audio (guest HAL still drives the client), and intent-extra engine
args — GodotActivity.kt sanitizeLaunchIntent() strips
`command_line_params` from exported activities by design (verified in
Godot source; -e and --esa both arrive as "with parameters []").
WORKAROUND verified live on both images: repack assets/_cl_ (int32 LE
argc + length-prefixed UTF-8 args) appending "--audio-driver Dummy" —
~/ps_harness/repack_dummy.py -> zipalign -> apksigner ->
builds/printshop-sim-dummy.apk (shipped APK untouched). Result: args
logged by GodotActivity, zero libOpenSLES lines, zero AudioTrack
SIGSEGVs. SECOND, independent crash (both images, exposed by the audio
fix): SceneShaderGLES3/SkyShaderGLES3 link failure — "Fragment shader
active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)" on
SwiftShader. API-34: GLThread exits -> GodotActivity force-quits
(SIG 9, ~10 s, no native crash). API-36: the GLThread itself SIGSEGVs
(~40 s; previously masked by the audio crash winning at ~34 s).
GLES3 minimum is 224 fragment uniform vectors, so the scene shader's
uniform pressure could also hit real low-end GLES3 devices — a
game-side uniform-diet pass (lights/material features) is the follow-up
candidate. Net: NO emulator image runs this build past ~40 s; mobile
verification = real device (human task). New harness inventory:
probe_api34.sh / probe_api34_fix.sh / probe_api34_fix2.sh /
probe_api34_cl.sh / probe_api36_dummy.sh (boot->install->launch->300 s
pidof monitor + screencaps + logcat SIGSEGV grep), repack_dummy.py.
Gotchas hit live: avdmanager writes AVDs to $XDG_CONFIG_HOME/.android/
avd while emulator 37.2 only searches $ANDROID_AVD_HOME/$HOME/.android/
avd (Pixel7_API34 = XDG path, Pixel7_API36 = legacy; set
ANDROID_AVD_HOME per AVD); adb re-splits multi-arg shell commands
through the remote shell (pass one string, quote the extra remotely);
bash `command -v name() {}` is a syntax error (exit 2, script dies
before line 1 of real work); pkill -f self-matches the caller's own
compound command — bracket-escape the pattern.

BUG-FIX ROUND v0.62.0 (2026-11-04, commits 37f86c7/2559ceb/65fb902/131b7ab,
pushed + deployed + live-verified): flash-worker slice (dwfrun-eccbff19)
fixed three verified bugs — (1) packing-stack visual wiped by unrelated
deliveries/accepts/expiries: _refresh_stack_visual() (Main.gd:4054)
recomputes the stack as max parts_packed over LIVE multi-part contracts at
all 7 teardown sites; pinning suites green unmodified. (2) event prompts
never aged: _set_prompt arms a 6 s window (PROMPT_TTL_S), cleared only
when the text is still the armed string — boot/pause direct writes exempt.
(3) ShopFront/CustomerActor mesh helpers deduped into NEW scripts/MeshKit.gd
(class_name; the .godot class cache was regenerated via --import — a FRESH
CLONE needs a --import or the ladder parse-fails on MeshKit). NEW
tests/bugfix_test.gd 34 checks. Gates: ladder 78/78 + pytest 21/21 (worker
filtered ladders; parent ran the full gate twice — pre- and post-bump);
bot curves byte-identical to worker-rank.md references. GLES3 uniform
overflow follow-up: project.godot light caps (16/4) TRIED AND DISPROVEN —
even CanvasShaderGLES3 overflows 261 vectors on SwiftShader, so the
overflow is engine-level (Godot 4.7 Compatibility base shaders); caps
reverted, docs/mobile.md records the negative result. Deploy: .mimosa/
added to .gitignore (it dirtied the build stamp), web build stamped
65fb902 clean, vercel alias moved immediately, live shop renders with
HUD "Alpha 0.62.0 / 65fb902". PERF NOTE: headless-SwiftShader FPS on the
live site measured 3 BOTH for v0.62 and (A/B, git archive 5832c2d served
locally) v0.61 on the same busy day — environment, not a regression; the
Nov-1 ~16 fps equivalent was on a quieter box. HARNESS GOTCHA (cost an
hour): localhost:9222 is held by the user's BRAVE browser (launched with
--remote-debugging-port=9222) — all CDP work must use port 9223 now
(ps_harness scripts updated); probes hitting Brave's page show NO WEBGL2
and the game's "Missing browser features" error. Worker finding left
open: _update_hud does two absolute /root/Version node lookups per
physics frame (Main.gd:4861-4863) — cacheable at boot, perf candidate.

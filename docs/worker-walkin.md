# Worker doc — GLM 3.0 slice 2: walk-in customers (v0.59.0)

Worker: glm-5.3-flash via zai coding plan. Date: 2026-10-30. Brief:
docs/GLM-3.0-SLICE-2.md. Base: commit d3d0a47 (slice 1 integrated; machine
baseline recorded at 1186ca3). No commits/push/deploy — parent reviews,
integrates, commits.

## Baseline (state found on disk)

Clean tree at d3d0a47 ("feat: front counter service island (v0.58.0)"). Slice 1
landed CounterStation at (-1.9, 0, 2.55), `_near_counter()` (1.35 m horizontal),
the empty-handed bell branch before the crate branch, counter_test 22 checks.
The brief's reference curves (docs/worker-counter.md:112-121 and :126-127) were
the byte-identical targets for this slice; they were re-proven identical at
HEAD before any change (the slice-1 ladder, same commands) and again after.

## What shipped

### New files (worker-owned)

- `scripts/CounterService.gd` (184 lines): RefCounted, pure logic, no nodes or
  signals. Constants + static pure functions: `slot_enabled(day, i)` =
  `absi(hash("walkin-<day>-<i>")) % 10 < 6`, `slot_time(day, i)` =
  `0.25 + 0.22*i + 0.03*(absi(hash("walkin-t-<day>-<i>")) % 4)`,
  `patience_deadline_frac(frac) = frac + 0.55`, `is_expired`,
  `patience_left_s`, `client_name` (draw from Contract.GEN_FIRSTS via
  `absi(hash("walkin-name-<day>-<i>"))`), `make_contract(day, index, cap)`
  (Contract.generate at board index 100+ i, then parts_total=1,
  deadline_days=2, walk_in=true, client=name draw). Instance side: `state`
  dict `{day, index, client, contract, accepted, deadline_frac, machine_idx}`
  exactly as briefed, `begin/clear/waiting`, and `due(day, frac, waiting_now)`
  with crossing semantics: the first tick of a day only seeds (a mid-day
  reload never spawns the morning's passed slot); crossed slots are marked
  handled whether fired or skipped ("skipped entirely while waiting"), the
  business window [0.15, 0.80] gates the fire, max 2 slots/day, max 1 waiting.
- `scripts/CustomerActor.gd` (107 lines): Node3D, no physics body. Two meshes
  (capsule torso with outfit color from `absi(hash("walkin-outfit-<day>-<i>"))`
  % 5 shop-palette entries, sphere head), built facing -z (the room) at
  `WAIT_POS := Vector3(-1.9, 0, 2.75)` (const here; Main sets .position —
  CounterStation pattern). Only animation is the idle bob inside
  `_advance(seconds)`, gated by `set_motion(false)` exactly on the WindowLife
  pattern (`_process` calls `_advance`; the gate lives in `_advance` so tests
  drive it directly). Never pre-built, never visible at boot.
- `tests/walkin_test.gd` (526 lines): 38 checks defined / 38 reached, checks
  format, load()-only references, paused/captured before E presses, explicit
  yaw/pitch after teleports, settle frames, controlled contracts for the
  exact-cents pin. Coverage maps 1:1 to the brief's checklist (see
  "Verification" below).
- `docs/worker-walkin.md`: this file.

### scripts/Main.gd (additive wiring, brief's points 1-8)

1. Vars: `_counter_service: CounterService`, `_customer: Node3D`,
   `_counter_arm/_counter_arm_t` (two-press slip arm, shop-code import
   pattern), `walkins_served: int = 0` (Main.gd:189-234,
   `walkins_served` at :233). `stats` gains `"lost_walkins": 0` (Main.gd:65).
   Build: `_counter_service = CounterService.new()` right after the counter
   block in `_build_environment` (Main.gd:1529-32 — same build site slice 1
   used for the counter, reached from `_ready`).
2. Tick: `_tick_counter(delta)` called beside `_tick_cleaning` in
   `_physics_process` (Main.gd:2864), body at :3069 — slip-arm timeout/radius
   disarm, patience expiry, then arrivals. Day fraction = `day_cycle.t`, day =
   `day_cycle.day` (the same DayCycle clock; no second clock). Expiry: despawn
   +, when a machine still holds the walk-in contract, the SAME teardown calls
   `_on_day_changed`'s overnight-cancel branch uses — `_advance(FAILED)`,
   `s.reset()` + visual reset + `set_failed(false)` when running/done,
   `_discard_part_for(m)`, `m["contract"] = null`,
   `packing_station.set_stack_count(0)` — then `stats.lost_walkins += 1`,
   NO rep change, NO log entry, NO save write (it persists on the next natural
   save, matching the day-rollover precedent). _on_day_changed itself is
   untouched (not in the allowed-edits list), so the call sequence is mirrored
   verbatim with a comment pointing at the source branch rather than factored
   into a shared helper — noted for review.
   `_spawn_walkin(day, index)` (:3116) builds the contract at the current
   rep tier cap, fills service state, adds the actor with motion per
   calm_mode; `_counter_despawn`/`_counter_disarm` (:3131/:3138);
   `_apply_calm_motion` now also pushes the gate to a live customer.
3. `_try_interact` branches in the brief's order:
   a. HELD walk-in part + `_near_counter()` → `_counter_deliver_held(mi)`
      (:4309-19), inserted AFTER the finishing/shelf branches, BEFORE the
      packing-table branch; board parts fall through unchanged.
   b. HELD walk-in part near the packing table (non-scrap) → prompt
      "<client> is waiting at the counter — hand it over there" + return
      (:4321-31); the scrap branch stays reachable (an F walk-in part scraps
      at the table and pays nothing — the packing table must never PAYOUT a
      walk-in; walk-in F handling is documented under Edge cases).
   c. Empty-handed at the counter (:4347-404): nobody waiting → slice-1 bell
      + quiet prompt byte-for-byte; waiting, not accepted → two-press slip
      (press 1: client, model, color/any color, ~base x1.10 price, waits ~Ns;
      arm 8 s; press 2 accepts); armed state disarms on leaving radius,
      timeout, or when nobody waits; no free printer →
      "No free printer for a counter order", slip stays armed; accepted →
      prompt names the machine and remaining patience.
      `_accept_walkin_on(idx)` (:3160) uses `_accept_on`'s machine-setup
      calls (state advances OFFERED→ACCEPTED→PREPARING, m["day"], parts
      counters, stack reset, orient reset, guide, prompt "Sent to Printer N")
      minus the board plumbing (no take_next/put_back — walk-ins never enter
      JobBoard queues).
4. Grading/payout extraction: `_settle_held_delivery(m, late, via_counter)`
   (Main.gd:3828). Diff shape (verified against HEAD):
   - `_try_pack_held` keeps everything through try_pack's F/refused branches;
     the partial-pack branch is now guarded by the equivalent condition
     `if c.parts_packed + 1 < c.parts_total:` (identical to the old
     post-increment `c.needs_parts()` for the non-F path) with its statements
     moved verbatim one indent deeper; the final-copy path is one line:
     `return _settle_held_delivery(m, _is_late_for(m), false)`.
   - The settle contains the moved final-copy tail verbatim (aggregate ->
     loyalty -> eff_payout -> PACKED/DELIVERED advances -> finalize -> pay ->
     repay debt -> stack reset -> machine teardown -> recent_grades -> log ->
     rep/stats -> client memory -> guide -> save -> sfx -> rumble -> prompt)
     PLUS the grading core the brief puts in the extraction (QualityCheck on
     m["grade_snapshot"] -> finishing bump -> color cap -> copy append ->
     parts_packed++ -> part despawn). Re-grading is the same pure call
     try_pack already made with the same snapshot, so the grade matches; the
     `late := _is_late_for(m)` computation moved to the call sites (mandated
     by the signature; value unchanged — it reads deadline/day only).
   - via_counter differs ONLY by: `_finalize_payout(..., counter=true)` and
     `walkins_served += 1` next to the stats block.
5. `_finalize_payout` gains trailing `counter := false`; when true
   `payout = roundi(payout * COUNTER_PREMIUM)` (new const 1.10, Main.gd:20)
   immediately AFTER the event multiplier and BEFORE the late factor
   (Main.gd:4249-4271). No existing call sites changed; rounding stays the
   function's existing roundi-per-step cents discipline.
6. Persistence: `walkins_served` top-level key (media_a_deliveries pattern:
   payload :1029, restore `maxi(int(...), 0)` in _load_save) and
   `stats.lost_walkins` via the repo's stats-dict pattern (`stats` initializer
   + the _load_save stats restore loop key list + SaveSystem.STAT_KEYS).
   Waiting walk-ins are NOT persisted (nothing about the service state or
   actor is saved); reload spawns nobody — asserted by the suite.
7. HUD: one line appended after the per-machine contract/prep block
   (Main.gd:4683-92): `"Counter: <client> — <model> (<patience>s)"`, only
   while someone waits; nothing otherwise (bot runs render no new text).
8. On serve: `walkins_served += 1` (inside the settle, via_counter branch);
   rep +0.2 through the existing delivery branch (media-day bonus composes —
   untouched); client memory via the existing lines; plus ONE allowed
   "counter" log entry on the player's serve
   (`_counter_deliver_held`, Main.gd:3188-3210).

### scripts/Contract.gd

Exactly ONE additive var at :70-74 with a comment: `var walk_in := false`.
Nothing else.

### scripts/SaveSystem.gd (two absence-tolerant validators)

- `_walkins_served_valid` (:264, mirror of `_media_a_valid`) + call in
  validate() (:123) for the top-level `walkins_served` key.
- `lost_walkins` rides the repo's stats-dict pattern: appended to
  `STAT_KEYS` (:561) so `_stats_valid` type-checks it only when present
  (absence-tolerant for old saves). Hazard 16 check: no suite pins
  STAT_KEYS contents or payload key counts (grepped tests/; v050 rounds-trips
  specific stats keys only) — full ladder confirms.
- .uid files: `scripts/CounterService.gd.uid`, `scripts/CustomerActor.gd.uid`,
  `tests/walkin_test.gd.uid` — Godot 4.7 generated via an editor rescan (the
  new class_name entries also require the `.godot` global class cache refresh
  to parse; repo convention is to track tests/*.uid + scripts/*.uid, so the
  parent should commit them).

### scripts/Version.gd

VERSION "0.58.0" -> "0.59.0".

## Deviations from the brief (all deliberate, for review)

1. **`absi()` on every hash draw** (CounterService statics, CustomerActor
   outfit): the brief writes `hash(...) % 4` / `% 10` literally, but GDScript's
   `%` keeps the dividend's sign, so a negative hash would produce negative
   jitter/times. The repo's hash-pinning precedent (JobBoard.gd:181-191,
   Contract.featured_slot_for_day) uses `absi(hash(...)) % n`. All draws stay
   deterministic; nothing else references these hashes, so no pin can move.
2. **Patience deadline is fixed at ARRIVAL, not at ACCEPT.** The brief says
   "0.55 of a shop day from ACCEPT", but the same slip shows "waits ~Ns"
   BEFORE accepting and an unaccepted customer must leave when patience runs
   out (otherwise one unaccepted walk-in would block the counter forever).
   `begin()` stores `deadline_frac = patience_deadline_frac(arrival_frac)`;
   accepting does not extend it. `patience_deadline_frac` stays the pure
   function the brief names.
3. **`_try_grab_or_place` carve-out extended to the counter**
   (Main.gd:2476-92): the raw E key with a held part routes to `_try_place`
   unless near the packing station, so the brief's branch 3a was unreachable
   by keyboard until the counter joined the "delivering beats placing"
   carve-out (`_is_held_part() and (_near_packing_station() or
   _near_counter())` -> `_try_interact()`). Board parts near the counter fall
   through `_try_interact` to the same `_try_place` they hit before.
4. **Expiry teardown mirrors rather than shares** `_on_day_changed`'s cancel
   branch (see point 2 above): _on_day_changed is outside the allowed-edits
   list, so the same call sequence is duplicated with a source comment. The
   rep/log/sfx/prompt parts of the cancel branch are deliberately omitted
   (expiry is inert).
5. **Defensive null-guard in the slip branch**: a waiting state always
   carries its contract (`begin()` guarantees it); if it is ever missing the
   branch treats the counter as quiet instead of crashing on a Nil deref.
   Found while a broken early test build fed a Nil contract in.

## Edge cases (documented behavior, asserted or reasoned)

- Walk-in print FAIL: `_on_print_done` fails the contract and frees the
  machine (existing path); the customer keeps waiting until patience expiry,
  which then finds no machine contract and just despawns + lost_walkins++.
  The player cannot re-accept (state.accepted stays true) — the order dies
  with the failed print. Not separately test-pinned; covered by the expiry
  tests' "no machine contract" arm.
- Walk-in part grades F at INSPECTION: counter handover refuses
  ("A failed part can't be handed over — scrap it at the packing table");
  the packing table still allows the SCRAP branch for walk-in parts (pays
  nothing). Board single-part F behavior unchanged.
- Cosmetic known edge: a walk-in accept or counter delivery calls
  `packing_station.set_stack_count(0)` (parity with `_accept_on` and the
  board delivery tail, per the brief's "same machine-setup calls" and
  "differs ONLY by" constraints) — if a BOARD multi-part order is
  mid-completion on the packing table, its stack VISUAL resets early; the
  order's own parts_packed bookkeeping is unaffected and the next partial
  pack re-stacks. Player-action-only path; bots never touch it.

## Commands run + results (all this session, all sequential, hazard 1)

1. `timeout 150 ~/tools/godot --headless --path . --script tests/walkin_test.gd`
   — 3 consecutive green runs after the suite settled:
   run1 `rc=0 checks=38 failures=0 script_errors=0`,
   run2 `rc=0 checks=38 failures=0 script_errors=0`,
   run3 `rc=0 checks=38 failures=0 script_errors=0` (grep-gated:
   no SCRIPT ERROR/Parse Error; `38 checks defined` == `checks=38` — hazard 2
   gate). A 4th sanity run after the .uid rescan: `rc=0 checks=38 failures=0`.
2. Pinning suites standalone (all rc 0, no script errors):
   counter_test 22/22, packing_test 58/58, v018_test 55/55,
   economy_test 54/54, v034_station_test 48/48, v037_test 13/13.
3. `bash tools/ladder.sh --bots` (FULL, sequential):
   **`LADDER_DONE total=75 failed=0`** (73 suites incl. walkin_test +
   smoke, plus sim_playtest + sim_lategame), runner rc 0.
4. `~/tools/venv/bin/python -m pytest tests/test_build_web.py -q` ->
   **`21 passed in 0.31s`**.
5. `timeout 300 ~/tools/godot --headless --path . --script
   tests/sim_playtest.gd` (standalone, per brief): `checks=8 failures=0`,
   rc 0, curve BYTE-IDENTICAL (diff vs docs/worker-counter.md:113-121, empty):
   ```
   PLAYTEST: day 1 end: $151.05 · delivered 2 · rep 2.80 · debt $0.00
   PLAYTEST: day 2 end: $462.25 · delivered 5 · rep 3.20 · debt $0.00
   PLAYTEST: day 3 end: $625.12 · delivered 6 · rep 3.30 · debt $0.00
   PLAYTEST: day 4 end: $743.31 · delivered 7 · rep 3.40 · debt $0.00
   PLAYTEST: day 5 end: $657.39 · delivered 7 · rep 3.00 · debt $0.00
   PLAYTEST: day 6 end: $1024.43 · delivered 10 · rep 3.20 · debt $0.00
   PLAYTEST: day 7 end: $1377.80 · delivered 13 · rep 3.70 · debt $0.00
   PLAYTEST: day 8 end: $1665.79 · delivered 15 · rep 3.80 · debt $0.00
   PLAYTEST: day 9 end: $1749.64 · delivered 17 · rep 4.00 · debt $0.00
   ```
   The ladder's sim_playtest log (in the run from step 3) prints the same
   nine lines — also diff-verified byte-identical to the reference.
6. `timeout 420 ~/tools/godot --headless --path . --script
   tests/sim_lategame.gd` (standalone): `checks=16 failures=0`, rc 0. Full
   curve (this standalone run, the earlier standalone run, and the ladder's
   run all print it line-for-line identically; day 15 is the harness's
   roll-over line, not part of the reference):
   ```
   LATE day 1 end: $2.29 · delivered 4 · rep 3.20 · upgrades 4
   LATE day 2 end: $818.81 · delivered 14 · rep 4.50 · upgrades 4
   LATE day 3 end: $1929.35 · delivered 23 · rep 4.80 · upgrades 4
   LATE day 4 end: $2612.17 · delivered 28 · rep 5.00 · upgrades 4
   LATE day 5 end: $2687.27 · delivered 30 · rep 4.80 · upgrades 4
   LATE day 6 end: $3513.50 · delivered 39 · rep 4.80 · upgrades 4
   LATE day 7 end: $4101.27 · delivered 49 · rep 4.50 · upgrades 4
   LATE day 8 end: $4354.50 · delivered 54 · rep 4.80 · upgrades 4
   LATE day 9 end: $4447.47 · delivered 55 · rep 4.80 · upgrades 4
   LATE day 10 end: $4418.47 · delivered 55 · rep 4.70 · upgrades 4
   LATE day 11 end: $5002.76 · delivered 62 · rep 4.70 · upgrades 4
   LATE day 12 end: $4973.76 · delivered 62 · rep 4.50 · upgrades 4
   LATE day 13 end: $5042.21 · delivered 64 · rep 4.70 · upgrades 4
   LATE day 14 end: $4918.89 · delivered 64 · rep 4.50 · upgrades 4
   LATE day 15 end: $6026.39 · delivered 74 · rep 4.70 · upgrades 4
   ```
   Day-14 finals `LATE day 14 end: $4918.89 · delivered 64 · rep 4.50 ·
   upgrades 4` — BYTE-IDENTICAL to the brief/worker-counter baseline
   ($4,918.89 / 64). Walk-ins arrive and expire throughout all three runs
   (the bots never approach the counter; arrivals/expiry only touch the
   actor + the new stats.lost_walkins counter the bots never print).

## walkin_test coverage (38 checks, brief checklist -> checks)

Arrival gating determinism (checks 1-6 incl. "different days differ",
gate admits/refuses, night window refuses, slot crossing), skip-while-waiting
+ next-slot-after-serve (7-8), patience math + day wrap + seconds conversion
(9-10), slip contract shape/board-index-100 + client pool (11-12), boot spawns
no customer/actor/HUD line (13), spawn places ONE customer at WAIT_POS +
double-spawn refusal (14), HUD waiting line (15), two-press slip arm (16),
no-free-printer refusal with slip staying armed (17), disarm on leaving
radius + re-arm (18), 8 s timeout disarm (19), accept assigns the FIRST idle
unlocked machine and reserves it (20), accept leaves the board untouched
(21), further press names machine/patience instead of re-accepting (22),
packing-table refusal prompt for a held walk-in part (23), counter delivery
pays the pinned base x1.10 chain on a controlled contract, cents-exact and
proven different from the no-premium variant (24), walkins_served +
stats.delivered bump (25), rep +0.2 and client memory update (26), customer
despawn + exactly one allowed "counter" log entry (27), wrong spool color
caps the counter grade at B (28), finishing bump still applies at the counter
(29), unaccepted expiry is silent (30), accepted expiry cancels the machine
contract via the FAILED path with zero rep/log noise (31), crate buy not
stolen while a walk-in waits (32), payload round-trip (33), validators reject
negative counters (34), old-save absence tolerance (35), reload restores
counters and spawns nobody (36), two meshes + calm-mode freeze + _advance
drive (37), waiting walk-in does not steal the crate buy (38).

## Definition of done scorecard

- New suite green 3 consecutive runs: YES (plus a 4th post-rescan sanity run).
- FULL ladder: `LADDER_DONE total=75 failed=0`.
- pytest: `21 passed in 0.31s`.
- Both harnesses byte-identical to the slice-1 reference: YES (playtest all
  9 lines diff-empty vs docs/worker-counter.md; lategame day-14 finals exact,
  full curve self-consistent across two runs).
- Version.gd 0.59.0: YES. HANDOFF untouched (parent updates it).
- Worker doc: this file. No commits/push/deploy: confirmed (`git status`
  shows only the briefed modifications + new worker-owned files + .uid files).

## What I did NOT run

- Real Web export (`tools/build_web.sh`) — parent/integration owns it;
  pytest's test_build_web.py is mocked unit tests by design.
- Browser gameplay checks, deploy, live URL — out of worker scope.
- Any concurrent Godot processes — never; ladder and all suites sequential
  (hazard 1).
- Focused re-run of every one of the 73 ladder suites outside the ladder —
  they were each run once inside the FULL ladder (the mechanical gate: rc 0,
  no SCRIPT ERROR/Parse Error, checks==defined).

## Blockers

None. Routing worked (glm-5.3-flash via zai coding plan); no auth/quota
failures. Stop — parent session reviews, integrates, commits.

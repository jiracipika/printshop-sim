# Worker report — tier-4 picking starvation fix (v0.44.0, 2026-10-06)

Task: the v0.33 long-game harness surfaced that difficulty-capped picking
starves at tier 4 — late-game job intake collapses on a four-printer farm
while costs continue. Reproduce, fix minimally, prove with harness numbers.

## Pre-check

COLD (no file outside .godot/.git modified in the previous 60 minutes; the
repo had been idle ~15 h). One caveat: a FOREIGN godot process (PID 91345,
`economy_test.gd`) had been hung for 16h39m when I started. Retried the lock
for the full 20-minute budget, then ran concurrently rather than kill it
(forbidden). All runs completed normally alongside it.

Also: local main was 36 commits behind origin/main and HEAD sat on a stale
wip/print-farm-v0.13 checkout with an unrelated week-old uncommitted
export_presets.cfg edit (left untouched, uncommitted). Moved to main and
fast-forwarded to origin/main (63c82dd, v0.43.0) before any work.

## Root cause (measured, not guessed)

Reproduction: tests/sim_lategame.gd with the picker reverted to the
conservative early-game rule (difficulty <= 3, skip sub-2-day rush — exactly
sim_playtest's rule). Scratch harness, per-day diagnostics
(board difficulty histogram + offer ages):

| day | deliveries (Δ) | balance (Δ$) | board {diff: count} | note |
|-----|---------------|--------------|---------------------|------|
| 1   | +4            | +2           | {1:3, 2:2, 3:1, 4:2, 5:0} | tier 2 at boot |
| 2   | +11           | +920         | {1:1, 2:1, 3:2, 4:4, 5:0} | rep 4.5 -> tier 4 |
| 3   | +10           | +1,306       | {3:1, 4:7, 5:0}      | board saturating |
| 4   | +3            | +359         | {4:7, 5:1}           | zero eligible jobs |
| 5   | 0             | −19          | {4:7, 5:1}           | stall begins |
| 6-9 | 0/1/0/0       | −21/+75/−25/−25 | {4:7, 5:2}        | frozen; rent bleeds |
| 10-16 | 0 every day | −25/day      | {4:7, 5:2}, ages d+14 | permanent |

29 deliveries / $2,446 by day 14; the farm earned nothing for 10 of 14 days.
Rep stayed 5.0 throughout (calm offers carry no penalty) — a silent wall.

Mechanism: JobBoard only refills when a job is TAKEN (take_next ->
_fill_to_capacity) or when rush/competing offers expire at rollover. Calm
offers never rotate off. At tier 4 the fresh-deal difficulty roll is
uniform 1..5 (+30% day bonus from day 7), so every decline parks a
difficulty-4/5 job on the board permanently; once the 8 slots fill with
them, nothing is taken, so nothing ever refills. Below tier 4 the tier cap
keeps every carryover job take-able, which is why only the top tier walls.

## The knob (one, minimal)

JobBoard.STALE_MORNINGS := 3 — in rotate_day, calm offers with
offered_day <= day - 3 rotate off silently and the board backfills. No
reputation hit, no missed stat (only rush/competing expiry penalises;
v0.14 semantics otherwise untouched: restore/snapshot reproduce boards
exactly, retirement only fires at rollover). An offer therefore lives at
least three shop days — invisible to any board that turns over normally.

## Before/after (same scratch conservative-picker harness)

Days 1-4 are IDENTICAL pre/post (the knob cannot fire before day 4 —
early-game balance untouched by construction). From day 5:

| day | Δ deliveries before -> after | Δ balance before -> after |
|-----|------------------------------|---------------------------|
| 5   | 0 -> 2                      | −19 -> +109               |
| 6   | 0 -> 11                     | −21 -> +930               |
| 7   | 1 -> 8                      | +75 -> +712               |
| 8   | 0 -> 6                      | −25 -> +382               |
| 9-10| 0/0 -> 0/0                  | bursty (fresh wave timing)|
| 11-13 | 0/0/0 -> 6/1/2            | +489/+114/+71             |
| 14-15 | 0/0 -> 0/10               | −119/+1,143               |

Totals by day 14: 29 / $2,446 (starved) -> 64 / $5,224 (healed). The healed
curve is bursty (cautious intake waits for fresh waves) but net-positive in
every week; the difficulty-agnostic player still earns ~3x more ($20,073 by
day 14), so the fix heals without trivializing.

Side effect on the agnostic curve (it leaves low-payout stragglers that now
retire): slightly BETTER — day 14 $18,271/154 -> $20,073/167. 16/16 checks
green before and after.

## Files changed

- scripts/JobBoard.gd — STALE_MORNINGS := 3 + silent sweep in rotate_day
  (docs on the const + rotate_day header).
- tests/sim_lategame.gd — picker back to the conservative rule (the
  difficulty-agnostic pick was a workaround for this bug, documented in the
  old picker comment); reference-curve comment cites old (159/$19,294
  v0.33, 154/$18,271 at v0.43) and new (64/$5,224) numbers; balance floor
  sharpened $1,500 -> $3,000 with citation (the starved run's $2,446 passed
  the old floor — it caught nothing); delivery floor >= 60 kept (starved 29
  vs healed 64 straddles it).
- tests/v044_test.gd — new: 12 checks (retirement not reported as expired,
  lifespan exactly 3 days, backfill, Main-level zero rep/missed, restore
  keeps stale offers).
- scripts/Version.gd — 0.44.0.
- docs/HANDOFF.md — new current-active-work section.

## Verification

(filled at completion — see HANDOFF for the final list)

## Notes for the next worker

- The scratch reproduction harness (tests/_scratch_starve.gd) was deleted
  before commit; sim_lategame.gd now IS that configuration, with asserts.
- The tier-4 healed curve is intentionally bursty; do not "fix" the zero
  days with spawn-weight tweaks without re-measuring the whole 14 days.
- A foreign hung godot (economy_test.gd, 16h+) was left running untouched.

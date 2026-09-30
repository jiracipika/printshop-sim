# Current handoff — couch menus (v0.28.0)

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

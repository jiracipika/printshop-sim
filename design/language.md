# Print Shop Sim — visual and interaction language

Owner: Astra, design and planning lead. These are concept specifications, not claims about existing gameplay. All mockup balances, jobs, rates, dates, and timers are illustrative. No external assets, fonts, scripts or CDNs are required by the HTML.

## Premise and composition

A first-person Godot / GDScript workshop tycoon, browser-first. Begin with one room, one cheap open-frame printer, and objects you can handle. Later: accept a contract, orient a model, choose supports, print, inspect, package, deliver, collect money, and upgrade.

Warm industrial maker, not sterile laboratory or neon factory. Matte sage walls, worn honey plywood, dark steel frames, terracotta filament, paper job slips. Keep the workshop legible: preparation at the back bench, printer on the right, packing by a warm desk lamp. Frame a close, large printer against quieter rear-wall detail; use floor seams, converging bench edges, visible side planes, and occlusion to establish depth. Shelf reels and tools provide scale, not clutter.

Cover: stacked editorial title left, perspective printer right, generous dark negative space. Workshop screenshot: eye-level first-person composition with a close right-hand printer and a clear central walking lane. Both are explicitly labeled concept mockups, not engine screenshots. SVG perspective is art direction rather than a camera calibration reference.

Half-printed object: visible horizontal deposition bands, contrasting hollow top rim, nozzle above the latest layer, and a quiet dashed outline of the unprinted target. The outline is a planning aid, never material already produced. Actual 3D implementation should grow geometry from the build plate, not scale the whole model upward from its center.

## Concrete tokens

| Token | Hex | Use |
| --- | --- | --- |
| Ink / steel | #202B2B | Full-screen menu ground, HUD backing, main text on paper |
| Paper | #EEE5D3 | Primary text on ink, contract detail surface |
| Fired clay | #DA623A | Primary action, selection border, printed PLA |
| Mint | #A8C8AC | Ready state, secondary links, telemetry |
| Sage wall | #738771 | Workshop wall midtone |
| Honey ply | #C3A076 | Workbench top |
| Wood shadow | #8B6948 | Bench fascia and carton shadow |
| Muted light | #C2CCBA | Secondary text on dark surfaces |
| Focus amber | #F5CE80 | Keyboard focus ring, caution icon |
| Failure red | #AE493E | Fault stripe/icon, never sole error communication |

Orange buttons use ink text, not small white text. Failure copy uses paper text on ink next to the red marker. Ready, warning, and failure always carry words/icons as well as color. Validate rendered contrast in implementation; token selection alone is not a WCAG certification.

## Typography and spacing

HTML stacks: Arial, Helvetica, sans-serif for titles/body; monospace for data. No remote fonts. Cover title 70–142 px, weight 700, line-height .88, tracking -4 to -7 px; menu title 60–112 px. In-game section title 24–32 px; body 16 px; supporting labels 12–14 px; money 28–32 px monospace. Tiny 10–11 px HTML provenance captions are concept-sheet annotations, not a target for essential game text.

Godot starts with ThemeDB fallback font for an offline, reproducible build. Create local SystemFont resources with Arial/Helvetica and Menlo/Consolas/monospace names only as optional preferences, retaining the fallback when a browser platform cannot resolve them. Test metric differences in exported web UI. Do not fetch a font at runtime. If a bundled font is later approved, include its license and test its web payload.

Spacing grid: 4 px base; 8/12/16/24/32/48 steps. Panel padding 20–24 px; HUD safe area 24–32 px at 1440×900; button minimum target 44 px; corner radius 0–4 px. Dark HUD panels near 95% opacity prevent world textures destroying contrast. Target 1280×720 and 1440×900 desktop landscape; scale and wrap for smaller browser windows. Mobile/touch gameplay is not the initial milestone.

## Godot UI mapping

| HTML / intent | Godot 4 mapping |
| --- | --- |
| Shared ink/paper panels | Theme resource + StyleBoxFlat with explicit content margins |
| Main menu split view | Control root, HBoxContainer, VBoxContainer, TextureRect or real 3D background |
| Primary/secondary buttons | Button with normal/hover/pressed/disabled/focus overrides |
| Contract board list | ScrollContainer + VBoxContainer; focusable Button rows |
| Selected contract sheet | PanelContainer + VBoxContainer; GridContainer for requirements |
| Model preparation preview | SubViewportContainer / SubViewport with isolated Camera3D and simple mesh |
| Balance and job tracker | CanvasLayer / Control with top-left and top-right anchors |
| Print fill | ProgressBar with explicit textual percent and state |
| Crosshair | CenterContainer and small mouse-filter-ignore Control |
| Context prompt | Center-bottom PanelContainer, Label, input-action glyph labels |
| Printer telemetry | Bottom-right PanelContainer; status Label with icon + words |
| Pause and settings | Full-rect Control modal, focus captured; world input disabled |
| Notifications | VBoxContainer queue with capped items and accessible text duration |

Set decorative controls to MOUSE_FILTER_IGNORE. Capture input only for menus; opening a modal releases mouse capture, blocks movement/interact actions, and assigns initial keyboard focus. Closing with Esc returns to a paused overlay; explicit Resume click reacquires browser pointer lock. Do not assume browser Esc can be canceled. Read glyphs from InputMap rather than hard-coding keys in game.

## Interaction and states

WASD moves; mouse looks; E is a single context action (grab when empty-handed, place when holding, inspect when aiming at printer). A center ray within 2.2 m selects one visible target; walls occlude targets. Highlight a legal target with a slim mint outline and noun/verb prompt. Invalid placement says why. Grabbed objects follow a stable hold point without jitter, cannot push the player or pass through walls, and cannot be placed inside machinery. A running printer is inspect-only.

Printer state machine: empty → loaded → ready → printing → complete; printing may enter failed; completion/failure requires removal/cleanup before ready. Prompt and status always derive from that same state. Faults later use seeded simulation with visible preparation/material causes, not unexplained random punishment. Failure retains a clear recovery action and material accounting.

Later preparation exposes upright/side orientation presets, supports on/off, bed-fit status, material estimate and duration before commitment. Overhang/support rules may be coarse but deterministic and documented; this is not a real slicer. Later progression: Benchmate (small PLA bed), Workhorse (larger/faster bed), Enclosed Pro (temperature-sensitive materials). Prices and unlock thresholds are tuning data, not commitments from the mockup board.

Packaging requires a completed, accepted-quality object at the packing station, a box, and final confirmation. Payout happens once, only after delivery. Separate available balance, estimated job cost, consumed material, and realized payout; use integer cents. Avoid time-pressure failure during onboarding.

## 3D and browser constraints

Low-poly bevelled forms, restrained roughness variation, warm single directional light and inexpensive ambient fill. No dependency on screen-space reflections, volumetric fog, or expensive post-processing. Use baked/static light where it survives Compatibility web export; retain an unbaked fallback. Use primitive/procedural meshes for the initial milestone. Represent printed layers by simple repeated rings or a Compatibility-tested material, not thousands of separate nodes. Clamp all subdivision counts and instance counts.

Use one Camera3D around 1.65 m height, initial 70° FOV, accessible sensitivity slider, no forced head bob. Initial room approximately 7×6 m, bench approximately .9 m high, 1 m clear walkways. Treat these as starting metrics and test interaction reach in-engine. The SVG is not a scale drawing.

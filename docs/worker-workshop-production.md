# Workshop production overhaul (0.64.0)

The new main menu uses the workshop as its backdrop and groups the primary
actions into a keyboard, controller, and touch-friendly grid. The browser
canvas fills portrait and landscape viewports. The workshop uses charcoal
tile, copper-accented equipment, cooler walls, and a production bench sign.

Production lists unlocked printers, stock, wear, print progress, due dates,
and the existing forecast and recap. Unstarted board orders can be released
with confirmation and a 0.1 reputation cost. The action frees the machine,
records the cancellation, and saves the result. Running jobs, walk-ins,
and orders with production already started are protected.

Contract cards show per-part material charges. Preparation feedback shows
the stock shortfall or available cash before confirmation. Refill prompts
use the current day's spool price. The gameplay overlay keeps the first-sale
guide, competing-offer warnings, and counter timetables.

## Verification

- Source c53dbc5f561d58d92491cccb76f5d20a6772b9c2 was imported and exported with Godot 4.7.1. The non-threaded Web export records its source commit and the 0.64.0 version.
- Six targeted suites at the final source checked workshop art, atmosphere, room boot, touch controls, portrait layout and Production. All passed. The preceding touch and UI revision passed 16 targeted suites. The build-pipeline tests passed 21/21.
- Chromium with software WebGL 2 verified the desktop menu and Production panel, pointer lock, movement and accepting a job. A 390 × 844 touch viewport verified that Play starts gameplay in one tap. Physical phone and controller checks remain outstanding.

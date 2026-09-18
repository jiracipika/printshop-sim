# Current handoff — integrated mobile workshop update

Read AGENTS.md and design/implementation-plan.md. Repo /Volumes/HARD/projects/printshop-sim; private remote https://github.com/jiracipika/printshop-sim, main. Existing public prototype https://printshop-sim.vercel.app/. User authorized main commit/push and Vercel release; design-only document approval/PR language is superseded.

Roles: Astra designs/plans/reviews; explicit GLM 5.3 Flash via Z.AI Coding Plan handles bounded background coding. Pin GLM_BASE_URL=https://api.z.ai/api/coding/paas/v4 and --provider zai --model glm-5.3-flash. Do not use default delegation (previously routed exhausted GLM5.2), do not retry quota/auth or silently switch models. Never touch automated-newsletter or pitchforge/pitch-therapy.

Completed locally: workshop walls/bench/palette; click-to-play/Escape/focus pause; mobile overlay and multi-touch movement/look/Interact/Pause; reproducible export stamping/restoration and artifact freshness checks. Parent review caught and fixed hidden overlay, synthetic touch-to-mouse capture, and a desktop-only physics gate that blocked touch movement. Tests must exercise integrated physics, not only input handlers.

Parent verification: Godot import clean; touch 47 checks, desktop pause 21, room 9, simulation 9; Python build pipeline 21 tests. Actual Web export passed. Chromium mobile emulation (844x390, 5 touch points) loaded WASM/PCK and rendered controls; touch resume, move+look, Interact starting print and pause observed; pointer lock remained false. Physical iOS/Android, browser matrix, performance targets, portrait gameplay and full tycoon loop remain unverified. Browser screenshots /tmp/printshop-mobile-moving.png and /tmp/printshop-mobile-print-paused.png are local transient evidence.

Release in progress at this checkpoint: commit reviewed source, clean export bash tools/build_web.sh, push main, Vercel production deploy, read live build-info.json and verify live browser. Never assume this checkpoint itself proves deployment. Parent final reply/remote metadata provides actual released commit.

Next features: grabbing/placement, recognizable printer geometry and visible print deposition, preparation/supports/failure/packaging/economy. Current printers are placeholder boxes; print state appears in HUD. Do not call full contract loop complete.

Continue via independent bounded CLI workers (not parent-context-only delegation), disjoint file ownership, required checkpoint files and Astra review boundaries. Disk plan survives context resets; indefinite autonomous continuation is not configured.

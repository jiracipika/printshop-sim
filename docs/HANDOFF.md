# Durable project handoff

## Resume entrypoint
Read AGENTS.md, this file, then design/implementation-plan.md when available. Inspect git status and live worker state before writing anything. Do not rely on prior chat context. Do not duplicate a running worker. Update this document at every completed task, failure, or handoff.

## Roles
Astra / gpt-6-astra: designs, implementation plan, architecture, review and acceptance. GLM 5.3 Flash via Z.AI coding plan: bounded background coding tasks after Astra review. Never silently substitute GLM 5.2 or a paid API route. Stop on quota/auth failure; no retry loop.

## Verified checkpoint
Checkout: /Volumes/HARD/projects/printshop-sim. Branch initialized as main. Last inspection: all source untracked; no git remote configured. Scripts present: Main.gd, JobBoard.gd, PrintSim.gd, DebugPanel.gd, Version.gd and UID files; scenes and tests directories exist. Their runtime correctness is NOT verified by this checkpoint. No design files existed at last inspection. No verified playable URL, Web export, commit, or deployment.

Tools previously verified: Godot 4.7.1, matching export templates, GitHub CLI account jiracipika, Vercel CLI account jiracipika. Recheck before use.

## Worker ledger
- Earlier delegate_task workers used GLM 5.2 and failed with HTTP 429 insufficient balance; do not reuse this unverified default delegation route.
- Standalone Codex gpt-6-astra process proc_fbc322bf6b71 failed with 401 refresh-token-already-used. Do not change or copy credentials.
- Replacement design worker: terminal process proc_d7b4314a0296, PID 83373 at launch. Explicit invocation: hermes chat --provider openai-codex --model gpt-6-astra --ignore-rules --toolsets terminal,file --oneshot --max-turns 35 --run-budget 900. Status at handoff: launched, completion/auth success not yet verified. Owns design/ only. Process IDs can be stale; check before taking action.
- No GLM coding worker has been launched by this checkpoint.

## Design deliverables / first next action
Collect and independently inspect design/language.md, cover.html, menu-main.html, menu-contracts.html, hud.html, screenshot-workshop.html, README.md, implementation-plan.md. Label concept imagery honestly. If worker fails, record exact failure and let Astra produce/review designs without silently switching providers. User wants cover, menus and gameplay-screenshot-like concepts.

## Milestones
1. Reviewed visual direction and actionable design/implementation-plan.md.
2. First browser foundation: workshop room, movement, grabbing, workbench, interactive printer; GDScript, GL Compatibility, simple single-thread export.
3. Actual GitHub repository and verified Vercel playable URL as early as milestone 2. Configure remote before pull; never invent remote or overwrite dirty source. Private is the default for unpublished creative work.
4. Full browser vertical slice: accept contract, prepare orientation/supports, start print, visible progressive print, meaningful success/failure, remove object, package, fulfill, receive money, repeat.
5. Repeatable deployment and only then CI automation.

## Coding handoff contract
Astra writes docs/GLM-NEXT-SLICE.md before launching coding. Include exact owned files, integration interfaces, RED/GREEN test cases, commands, acceptance criteria, and exclusions. Use explicit provider zai/model glm-5.3-flash after confirming coding-plan routing. No nested default delegate_task. Use independent bounded CLI workers with terminal background=true/notify=true, not process-local delegation for continuity. Workers read this file and AGENTS.md explicitly because ignore-rules skips auto-injection. Each worker checkpoints changes, actual test output, remaining steps and blockers in docs/worker-<task>.md before exiting. No simultaneous ownership. No unsupervised commit/deploy; Astra review still required.

## Verification ladder
Inspect actual tests/tools to select real commands; do not invent test filenames. Godot headless import, bounded runtime test (scan output for SCRIPT ERROR/Parse Error, not just exit code), affected-feature tests, Web export, local browser gameplay/input verification, review, meaningful commit/push, Vercel deploy, live browser WASM/PCK/engine/main-scene/input verification. Publish commit and playable URL only when verified. Preserve build ID/version, generated export separation, browser-safe simulation and save abstraction.

## Continuity limits
Repo-local files survive context compaction and session restart. Independent CLI workers can continue their bounded task without the parent's token context, but this does not guarantee survival across application/process shutdown, machine restart, authentication failure, or exhausted quota. No automatic indefinite supervisor exists yet. At a review boundary workers must checkpoint and stop rather than self-approve. A resumed Astra reads this file to review and dispatch the next slice.

## Exclusions
Never touch automated-newsletter or pitchforge/pitch-therapy. Work only in this project. Do not change global model configuration or credentials.

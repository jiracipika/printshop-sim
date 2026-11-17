# Print Shop Sim — agent roles and delivery requirements

## Continuity
- Start or resume by reading docs/HANDOFF.md and design/implementation-plan.md when present.
- Check existing worker state before launching replacements. Never duplicate file ownership.
- Save task results, actual verification evidence, next steps and blockers to docs/worker-<task>.md at every bounded task boundary; update docs/HANDOFF.md before stopping.
- Background coding workers may complete their assigned slice independently of parent context, but must stop at the allowed reviewer's acceptance boundaries. Never claim automatic indefinite continuation or deployment approval.

## Model ownership (user override, 2026-11-17)
- The user explicitly authorized this project's implementation to continue using the current session's coding model instead of the previously required GLM route.
- Use only GPT-6.1 Terra (`gpt-6.1-terra`) or GPT-6 Luna (`gpt-6-luna`) for evaluation, review, and acceptance. Do not use Astra for review.
- If GLM 5.3 Flash is explicitly requested again, verify the user's Z.AI coding-plan routing; do not silently switch models, providers, or billing routes after an authentication/quota failure.
- Give workers bounded tasks and non-overlapping file ownership. An allowed reviewer independently verifies changes before integration. Run Godot tests serially to avoid shared BrowserSave races.

## Project requirements
- Godot GDScript, GL Compatibility renderer, browser-first development. Prefer a simple single-threaded Web export initially.
- GitHub is the source of truth; Vercel hosts the playable testing build.
- First playable milestone: room, movement, grabbing, workbench, interactive printer, working Web deployment.
- Design mockups must be labeled as concepts, not actual gameplay screenshots.
- A playable milestone is not done until runtime tests, Web export, browser gameplay checks, commit/push, deployment, and live verification pass. Report the commit and playable URL honestly.
- Keep generated Web exports separate from source. Identify deployed builds by version and source commit.

## Scope
- Work only on this project. Never touch automated-newsletter or pitchforge/pitch-therapy.

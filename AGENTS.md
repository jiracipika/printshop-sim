# Print Shop Sim — agent roles and delivery requirements

## Continuity
- Start or resume by reading docs/HANDOFF.md and design/implementation-plan.md when present.
- Check existing worker state before launching replacements. Never duplicate file ownership.
- Save task results, actual verification evidence, next steps and blockers to docs/worker-<task>.md at every bounded task boundary; update docs/HANDOFF.md before stopping.
- Background coding workers may complete their assigned slice independently of parent context, but must stop at Astra review boundaries. Never claim automatic indefinite continuation or deployment approval.

## Model ownership
- Astra (gpt-6-astra via the user's ChatGPT/Codex subscription) owns design, mockups, planning, architecture, review, and acceptance.
- Once the design and implementation plan are reviewed, use GLM 5.3 Flash (`glm-5.3-flash`, provider `zai`) through the user's Z.AI coding plan for background implementation workers.
- Verify the coding-plan routing before implementation. Do not silently substitute GLM 5.2, another model, or a pay-as-you-go endpoint. Stop and report authentication/quota failures.
- Give workers bounded tasks and non-overlapping file ownership. Astra reviews changes and independently runs verification before integration.

## Project requirements
- Godot GDScript, GL Compatibility renderer, browser-first development. Prefer a simple single-threaded Web export initially.
- GitHub is the source of truth; Vercel hosts the playable testing build.
- First playable milestone: room, movement, grabbing, workbench, interactive printer, working Web deployment.
- Design mockups must be labeled as concepts, not actual gameplay screenshots.
- A playable milestone is not done until runtime tests, Web export, browser gameplay checks, commit/push, deployment, and live verification pass. Report the commit and playable URL honestly.
- Keep generated Web exports separate from source. Identify deployed builds by version and source commit.

## Scope
- Work only on this project. Never touch automated-newsletter or pitchforge/pitch-therapy.

---
name: auto-goal-grill
description: Default Auto-Goal and Auto-Grill workflow for LAYERS-Agentic. Use automatically on bug reports, audits, open-ended requests, or new features to derive verifiable Goal Contracts, ask only real UX/scope forks via ask_question, and run the closed verification loop.
---

# Auto-Goal & Auto-Grill Workflow

Follow this 3-part loop whenever tackling bugs, audits, feature requests, or open-ended prompts in `LAYERS-Agentic`.

## 1. Auto-Goal: Self-Derive & Rank the Target
1. Inspect read-only evidence first: run `./scripts/verify_loop.sh --fast`, check `test/`, `functions/index.js`, `lib/`, and run headless Godot `4.7.2` probes (see `godot-headless-loop`) when Godot plugin behavior is involved.
2. When the user prompt is broad or open-ended (e.g., *"audit LAYERS"* or a wide symptom), score candidate fixes by `(User Impact × Reliability Gain) / Blast Radius` and pick the **#1 highest-impact safe goal**. Execute that #1 loop immediately rather than stopping on a backlog picker menu.
3. Frame the work using the 3-part Goal Contract:
   - **Goal**: One plain-English sentence stating what is being changed and why.
   - **In Scope**: Exact files, tests, and systems touched.
   - **Done When**: Objective, machine-checked commands/assertions that must pass (`./scripts/verify_loop.sh`, failing regression test turning green, Godot headless probe printing `OK`).

## 2. Auto-Grill: Clarify Only Real UX/Scope Forks
1. Solve engineering, data-structure, and Godot/Flutter API questions internally by reading code or running fast probes—never burden the user with technical trivia.
2. If genuine product, UX, or scope trade-offs exist (multiple valid user behaviors or destructive scope choices), call `ask_question` upfront with 1–3 crisp multiple-choice questions (`(Recommended)` option first) before editing code.
3. **Execution Gate**:
   - **Clear / Small-to-Medium Tasks, Bug Fixes & `/goal` Runs**: Skip `implementation_plan.md` pauses once any Auto-Grill fork is answered (or immediately when unambiguous) and move straight to Step 3.
   - **Major UI Redesigns & Core Architecture Changes**: Present `implementation_plan.md` (`Goal`, `In Scope`, `Affected Files`, `Done When`) and wait for explicit user approval before editing.

## 3. Closed Verification Loop
1. **Reproduce First (Red)**: Add or run a failing unit/widget test in `test/` or headless Godot probe in `scripts/godot_plugin_smoke.gd` proving the bug or missing contract. Keep external `/Users/henry/Godot/Projects/*` game files strictly read-only (`addons/layers/*` only if explicitly syncing the plugin).
2. **Iterate Autonomously (Green)**: Loop `Edit → ./scripts/verify_loop.sh → Self-Repair` (pass `--fix-zip` if `godot_plugin/` changed) without stopping between edits until all checks exit `0`.
3. **Hand Back / Re-Plan Only When Blocked**: Stop and escalate only if a verification gate contradicts the spec or an assumed architecture detail breaks.

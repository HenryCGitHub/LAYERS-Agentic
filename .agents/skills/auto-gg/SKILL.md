---
name: auto-gg
description: Automated Auto-Goal + Auto-Grill (Auto GG) continuous loop workflow for LAYERS-Agentic. Activate whenever the user types /auto-gg, "Auto GG", or asks to run an automated goal-discovery and grill-me loop.
---

# Auto GG (`/auto-gg`) — Continuous Goal + Grill Loop

Run this 4-phase loop continuously until canceled or stopped.

## Phase 1 — Automated Goal Discovery
1. Run signal discovery from the repo root:
   ```bash
   python3 .agents/skills/auto-gg/scripts/discover_signals.py
   ```
   (Pass an optional focus phrase after the script if the user gave a focus, e.g. `/auto-gg godot`.)
2. Read `1–3` top candidate files across `godot_plugin/addons/layers/`, `functions/index.js`, or `lib/` and rank `2–3` concrete, playable/verifiable LAYERS goals by `(User Impact × Reliability Gain) / Blast Radius`.

## Phase 2 — Auto-Grill (`ask_question`)
Call `ask_question` with `2–3` concise multiple-choice questions (`(Recommended)` option first on each):
1. **Goal Choice**: `#1` highest-impact safe goal (`(Recommended)`) plus `1–2` alternatives from Phase 1.
2. **UX / Scope Forks (`1–2` questions)**: Only genuine product, UX, or scope trade-offs for the recommended goal—never ask engineering trivia.

## Phase 3 — Closed Verification Loop (`Red → Green → Commit`)
1. Once `ask_question` returns answers, lock the 3-part Goal Contract (**Goal**, **In Scope**, **Done When**).
2. If in Plan Mode, call `exit_plan_mode` with the concrete file/test plan (ending with `enter_plan_mode` hand-back for the next round) unless the chosen goal is a major UI redesign or core architecture rewrite requiring `implementation_plan.md` review.
3. Add or update a failing unit/widget test (`test/`) or headless Godot probe (`scripts/godot_plugin_smoke.gd`) first.
4. Implement the fix/feature (keeping `/Users/henry/Godot/Projects/*` game files strictly read-only; sync `addons/layers/*` only when explicitly verifying), run `./scripts/verify_loop.sh` (`--fix-zip` if `godot_plugin/` changed) until exit `0`, and commit cleanly to `main`.

## Phase 4 — Perpetual Next-Round Handoff
1. Immediately call `enter_plan_mode` with a 2-line summary of the shipped commit so the Planning model reports the completed round, runs `discover_signals.py`, and pops up **Round `N+1`'s `ask_question` Goal + Grill** automatically.
2. Exit the loop immediately whenever the user cancels `ask_question` or types `stop`, `pause`, `done`, or `exit auto gg`.

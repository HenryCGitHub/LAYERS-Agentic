---
name: auto-gg
description: Automated 2-Step Goal-then-Grill continuous loop workflow for LAYERS-Agentic. Composes auto-goal discovery first (Goal Choice only), then runs auto-grill strictly on the chosen goal.
---

# Auto GG (`/auto-gg`) — Continuous 2-Step Goal + Grill Loop

Compose [`auto-goal`](../auto-goal/SKILL.md) and [`auto-grill`](../auto-grill/SKILL.md) in two separate gates so UX questions are **only** asked for the goal the user actually chose.

## Step 1 — Auto-Goal Discovery & 1-Question Goal Pitch (`select_goal`)
1. Run repository telemetry from the workspace root:
   ```bash
   PYTHONDONTWRITEBYTECODE=1 python3 .agents/skills/auto-goal/scripts/discover_signals.py
   ```
   Pass any optional focus phrase after the script (e.g. `/auto-gg stage 2`).
2. Read `1–3` candidate files and rank the top `3` concrete LAYERS goals by `(User Impact × Reliability Gain) / Blast Radius`.
3. Call `ask_question` with **exactly 1 question** (`Goal Choice`), listing the `#1` safest high-impact goal (`(Recommended)`) plus `1–2` clear alternatives with a 1-line payoff each.
   - Never bundle speculative UX questions in Step 1.

## Step 2 — Auto-Grill the Chosen Goal (`grill_chosen`)
1. Inspect only the files affected by the goal the user selected in Step 1.
2. Apply [`auto-grill`](../auto-grill/SKILL.md):
   - If the chosen goal has genuine UX, layout, or scope forks, ask `1–2` targeted `ask_question` follow-ups (`(Recommended)` first).
   - If the chosen goal has zero UX ambiguity (pure bug fix, test hardening, or internal bridge contract fix), skip Step 2's `ask_question` and lock the Goal Contract directly.

## Step 3 — Closed Verification Loop (`Red → Verify → Commit`)
1. Lock the 3-part Goal Contract (**Goal**, **In Scope**, **Done When**) and call `exit_plan_mode`.
2. Write/update a failing test or smoke probe first, implement the change, run `./scripts/verify_loop.sh` (`--fix-zip` if `unreal_plugin/` changed) until exit `0`, and commit cleanly to `main`.

## Step 4 — Perpetual Next-Round Handoff
1. Immediately call `enter_plan_mode` with `reason` prefixed by `[round-complete]` and a 2-line summary of the shipped commit so Round `N+1` automatically enters Step 1 (`select_goal`).
2. Stop immediately whenever the user cancels any `ask_question` or types `stop`, `pause`, `done`, or `stop auto gg`.

---
name: auto-grill
description: High-signal LAYERS UX and scope interviewer for user-specified features or design targets. Activate whenever the user runs /auto-grill or asks to grill UX/scope decisions before building a target change once.
---

# Auto-Grill (`/auto-grill`) — Targeted Design & Scope Interview

Use this standalone for a user-supplied feature/target (single-pass), or as the reusable Phase 2 module for `/auto-gg` and `/auto-goal`.

## Phase 1 — Grounded Code Inspection (No Repo Telemetry Backlog)
1. Do **not** run `discover_signals.py` or pitch unrelated goals when running standalone `/auto-grill <target>`.
2. Read `1–3` affected files across `lib/`, `functions/`, or `godot_plugin/addons/layers/` directly relevant to the target request.
3. Separate settled engineering facts (data contracts, Godot Context schemas, existing tests) from genuine product, UX, or scope trade-offs.

## Phase 2 — High-Signal `ask_question` Grill
1. Call `ask_question` with `1–3` focused multiple-choice questions (`(Recommended)` option first on every question):
   - Only ask about real UX placement, workflow ergonomics, visual density, or scope boundaries.
   - Never ask engineering trivia (variable names, private helpers, test structure, serialization keys).
2. If zero genuine UX or scope ambiguity exists after inspecting the code, skip `ask_question` cleanly and explain why.

## Phase 3 — Lock Goal Contract & Execute Once
1. Lock the 3-part Goal Contract (**Goal**, **In Scope**, **Done When**) incorporating the user's answers.
2. Unless the task is a major UI redesign or core architecture overhaul needing `implementation_plan.md` sign-off, call `exit_plan_mode`, add/update a failing test script first, implement the change, and run `./scripts/verify_loop.sh` (`--fix-zip` if `godot_plugin/` changed) until exit `0`.
3. Deliver a concise summary with clickable `file:///` links and stop cleanly (single-pass).

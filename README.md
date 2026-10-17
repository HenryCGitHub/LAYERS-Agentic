# LAYERS-Agentic

An Antigravity-style **Interview → Plan Gate → Autonomous Execution** Game Production Workstation built with Flutter.

## 3-Stage Agentic Workflow (One Release at a Time)
1. **Stage 1: Initial Project Concept Creation (`ProjectPitchScreen` + `ProjectConceptAgent`)**
   - **Step 1A (The Spark)**: Enter a 1-sentence game idea.
   - **Step 1B (Concept Interview)**: Answer 2–3 tailored multiple-choice questions (Perspective/Controls, Core 30-Second Loop, First Milestone Scope Target).
   - **Step 1C (Project Blueprint & Release Train)**: Review the structured `Goal`, `In Scope` (Core 30s Loop), `Out of Scope` (Hard Exclusions), `Done When`, and sequential Release Train roadmap.
2. **Stage 2: The Release Plan Gate (`ReleasePlanGateScreen` + `ReleasePlannerAgent`)**
   - Review the proposed Release Blueprint for the active release (`v0.1`), answer 1–2 clarifying scope questions, toggle individual Features in/out of scope (unchecked features automatically defer to `Out of Scope`), and click **`Approve & Build Release ✦`**.
3. **Stage 3: Active Release Workbench (`ReleaseWorkbenchScreen` + `ReleaseExecutorAgent`)**
   - Autonomously constructs the entire active Release (`Release → Core Loop Beats → Features → Spec + 60/40 Playable Checkpoints`) and drops you straight into Checkpoint 1:
     - **Left Column (`60%`)**: Actionable Checklist Tasks.
     - **Right Column (`40%`)**: Playtest Smoke Test Criteria, Absorbed Scope Deliverables, Tuning Parameters, and Edge Cases & Safeguards.

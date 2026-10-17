# LAYERS-Agentic

An Antigravity-style **Turn-by-Turn Co-Design Chat → Plan Gate → Autonomous Execution** Game Production Workstation built with Flutter.

- **Live Web App**: [https://henrycgithub.github.io/LAYERS-Agentic/](https://henrycgithub.github.io/LAYERS-Agentic/)
- **GitHub Repository**: [https://github.com/HenryCGitHub/LAYERS-Agentic](https://github.com/HenryCGitHub/LAYERS-Agentic)

## Dual-Model AI Architecture (`thinkingLevel: LOW`)
- **Conversation & Co-Design Chat (`gemini-flash-latest` · `LOW`)**: Powers fast, snappy turn-by-turn co-design conversations and tailored clarifying questions.
- **Architecture & Release Planning (`gemini-4-argon` · `LOW`)**: Powers deep game-design synthesis, Core Loop Beats, Features, physics Tuning parameters, Edge Cases, and 60/40 Playable Checkpoints.

## 3-Stage Agentic Workflow (One Release at a Time)
1. **Stage 1: Turn-by-Turn Co-Design Chat + Live Project Blueprint (`lib/screens/project_pitch_screen.dart` + `lib/agents/project_concept_agent.dart`)**
   - **Left Pane (Co-Design Chat)**: Pitch a 1-sentence game idea and take turns chatting with Antigravity (clicking quick-reply chips or typing any adjustment).
   - **Right Pane (Live Blueprint Artifact)**: Watch your `Title`, `Goal`, `In Scope (30s Core Loop Beats)`, `Out of Scope (Hard Exclusions)`, `Done When`, and `Release Train` update live on every turn until you click **`Approve Concept & Plan v0.1 Release ✦`**.
2. **Stage 2: The Release Plan Gate (`lib/screens/release_plan_gate_screen.dart` + `lib/agents/release_planner_agent.dart`)**
   - Review the proposed Release Blueprint for the active release (`v0.1`), chat with Argon to refine Beats/Features, toggle individual Features in/out of scope (unchecked features automatically defer to `Out of Scope`), and click **`Approve & Build Release ✦`**.
3. **Stage 3: Active Release Workbench (`lib/screens/release_workbench_screen.dart` + `ReleaseExecutorAgent`)**
   - Autonomously constructs the entire active Release (`Release → Core Loop Beats → Features → Spec + 60/40 Playable Checkpoints`) and drops you straight into Checkpoint 1:
     - **Left Column (`60%`)**: Actionable Checklist Tasks.
     - **Right Column (`40%`)**: Playtest Smoke Test Criteria, Absorbed Scope Deliverables, Tuning Parameters, and Edge Cases & Safeguards.

## Commands
- **Run Static Analysis & Tests**: `dart analyze && flutter test`
- **Deploy to GitHub Pages (`gh-pages`)**: `./scripts/deploy.sh`

# Workspace Rules for LAYERS-Agentic

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Deploy Command**: Run `./scripts/deploy.sh` from the project root (automatically encodes `$GEMINI_API_KEY` into base64 `--dart-define=GEMINI_API_KEY_B64=...` so GitHub Push Protection never blocks `gh-pages` pushes).
- **Dual-Model AI Routing (`lib/agents/gemini_agent_client.dart` & `lib/providers/workbench_provider.dart`)**:
  - **Conversation & Concept Blueprint Model (Stage 1)**: `gemini-flash-latest` with `thinkingLevel: "LOW"` for fast turn-by-turn co-design chat and live Project Concept Blueprint updates.
  - **Release Architecture Model (Stage 2)**: `gemini-4-argon` with `thinkingLevel: "LOW"` for Release Plan Gate blueprint generation and multi-release evolution (`v0.1` → `v0.2` → `v1.0+`).
- **3-Stage Antigravity Workflow (One Release at a Time)**:
  1. **Stage 1 — Turn-by-Turn Co-Design Chat + Live Project Blueprint (`lib/screens/project_pitch_screen.dart` & `lib/agents/project_concept_agent.dart`)**:
     - 50/50 split view: Turn-by-turn conversational chat on the left (`gemini-flash-latest`) and a live-updating **Project Concept & Release Train** artifact on the right (`Tech & Perspective`, `Goal`, `Load-Bearing Design Pillars`, `Trade-Offs (X over Y)`, `In Scope: 30s Core Loop Beats`, `Out of Scope: Hard Exclusions`, `Done When`, `Release Train`).
  2. **Stage 2 — Antigravity Release Plan Gate (`lib/screens/release_plan_gate_screen.dart` & `lib/agents/release_planner_agent.dart`)**:
     - Proposes an evolving single-Release Blueprint (`ReleaseBlueprint`) using `gemini-4-argon` with a conversational refinement chat bar and Beat/Feature keep/defer checkboxes. Supports 4 Feature Lifecycle states across releases: `NEW`, `UPGRADING (v0.1 → v0.2)`, `STABLE ✓`, and `SUPERSEDED` (retiring temporary greybox testbeds).
  3. **Stage 3 — Focus Mode Active Release Workbench (`lib/screens/release_workbench_screen.dart` & `ReleaseExecutorAgent`)**:
     - Non-destructively merges Beats, Features, and version-stamped `60/40 Playable Checkpoints` (`v0.1`, `v0.2`, etc.). Defaults to **Focus Mode** (spotlighting 1 Active Feature and 1 Active Checkpoint at a time, dimming sibling items, auto-collapsing verified checkpoints, providing a 1-click `Continue to Next Feature →` banner, and a compact Left-Rail Release Dropdown).

## 1. Mandatory Planning & Confirmation Gate
- **NEVER** edit, create, or modify any project code files (using `replace_file_content`, `write_to_file`, or modifying commands) without first presenting an `implementation_plan.md` artifact and waiting for explicit user confirmation.
- **Strict Workflow for all requests involving changes**:
  1. **Research Phase**: Use read-only tools (`view_file`, `grep_search`, `find_by_name`, `list_dir`) to thoroughly investigate the codebase.
  2. **Plan Phase**: Create or update `implementation_plan.md` detailing the problem, proposed changes, affected files, and verification plan.
  3. **STOP & Wait**: Do not call any modification tools. End turn and request explicit user confirmation on the plan.
  4. **Execution Phase**: Only after the user confirms/approves the plan, proceed to edit files, run tests (`flutter test`, `dart analyze`), and commit/push changes.

## 2. Testing & Quality Assurance
- Always run `dart analyze` and `flutter test` before committing any code changes.
- Ensure 0 static analysis errors and 100% passing tests on every commit.

## 3. Communication Style
- Keep responses concise and focused.
- Create clickable `file:///` links for referenced files and code symbols.

## 4. Pure KISS, DRY, and YAGNI Principles (Codebase & App)

### 1. KISS (Keep It Simple & Playable)
- **Codebase**: Write the simplest, most direct working Flutter code. Avoid complex state machines, micro-factories, or multi-step prompt pipelines when simple Provider mixins and single-pass prompts work.
- **App & AI**:
  - **The Playtest Rule**: If a player or QA tester cannot see, hear, or feel it on screen during gameplay, rephrase it into an observable deliverable.
  - **Cohesive Playable Units**: Group mechanics and game feel (controls, physics, SFX, animations, particle cues) into single, unified cards. Do NOT split a feature into artificial technical micro-tickets.
  - **Plain Functional Titles (No Thematic / Lore Wording)**: Keep card titles short and literal (2–4 plain everyday game-dev words). Name the actual gameplay mechanic or system (e.g., *Crop Farming & Storage*, *Shop Buy & Sell*, *Shotgun Firing & Reload*) — NEVER use flowery, archaic, or roleplay/lore words (e.g., *Homestead Husbandry*, *Expedition Prep*, *Adrenaline Crop Buffs*).
  - **Load-Bearing Design Pillars vs. Trade-Offs**:
    - **Design Pillars (3–4 statements)**: Name the core experiences the game must create and how it should make the player feel—NOT how it is built, NOT a feature (*"has a skill tree"*), and NOT a genre (*"a roguelike"*), but the experience those things exist to hold up (*"Every run teaches you something new"*).
    - **Trade-Offs (2–3 `X over Y` rules)**: Practical engineering/design boundaries used to resolve conflicts (e.g., *"Immediate arcade movement over realistic physics inertia"*).

### 2. DRY (Don't Repeat Yourself / Single Source of Truth)
- **Codebase**:
  - Centralize shared tokens (theme, tier colors, prompts).
  - **Rule of Three**: Only create shared abstractions after writing the exact same logic three times.
- **App & AI**:
  - **Single Source of Truth (Evolving Live Tree)**: Every permanent mechanic lives under a single Feature card across the entire life of the project (`v0.1` → `v0.2` → `v1.0+`), accumulating version-stamped Checkpoints rather than duplicating cards across releases.
  - **Automatic Rollups**: Hours, checklist counts, and progress rollup dynamically from Feature Checklist Steps and Playable Stages all the way up to Project (Tier 1) without manual duplicate entry.

### 3. YAGNI (You Aren't Gonna Need It / Scope Discipline)
- **Codebase**: Build strictly what the immediate feature requires today. Strip out hypothetical future-proofing, extra database columns, or unneeded packages before writing code.
- **App & AI**:
  - **Milestone Scope Discipline**: Breakdowns generate *only* the immediate next-step deliverables suited for the active release scope (Prototype, MVP, Vertical Slice, Standard).
  - **Focus Mode**: Spotlight only the 1 active Feature and 1 active Checkpoint at a time; dim sibling features and collapse completed/queued checkpoints to prevent overwhelm during production.

## 5. Scope & Goal Formatting Rule
Whenever writing or revising any Scope, Goal, or Objective section (across Epics, PRDs, task tickets, or design docs), follow these constraints:
- **No Paragraphs**: Never write scope or goals as dense narrative text. Always use this structured 3-part layout:
  - **Goal**: Exactly one plain-English sentence stating what is being built/done and why.
  - **In Scope**: A concise bulleted list of the specific systems, features, or assets included.
  - **Done When**: Clear, practical conditions for when the work is considered complete.
- **Tone**: Write like a practical developer talking to a teammate. Keep it direct, literal, and natural.
- **Non-Thematic / Literal Wording**: Describe mechanics in plain engineering/design terms (e.g., *"Spawn 3 enemy waves in the arena and drop ore on kill"* instead of *"Pit the player against aggressive demon waves in an out-of-town wasteland"*).
- **Banned Jargon & Archaic Words**: Never use corporate filler or vague buzzwords (*leverage*, *unified*, *end-to-end loop*, *staging*, *validate*, *verified*, *deliver*, *synergy*, *seamlessly*) or flowery/archaic lore synonyms (*husbandry*, *homestead*, *expedition*, *ordinance*). State the actual concrete action instead.



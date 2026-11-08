# Workspace Rules for LAYERS-Agentic

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Automated CI/CD Deployment**: Pushes to `main` automatically trigger GitHub Actions ([`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)) which runs `dart analyze`, `flutter test`, web compilation, and deploys to `gh-pages`.
- **Manual / Local Deploy**: `./scripts/deploy.sh` from project root (base64-encodes `$GEMINI_API_KEY` into `--dart-define=GEMINI_API_KEY_B64=...` so GitHub Push Protection never blocks `gh-pages`).
- **AI Model (`lib/agents/gemini_agent_client.dart` & `lib/providers/workbench_provider.dart`)**:
  - **Standard Model Across Entire App**: `gemini-flash-latest` with `thinkingLevel: "LOW"` for Stage 1 Concept Blueprint co-design and Stage 2 Release Workbench planning and synthesis.
  - **Active Pricing Rates**: Gemini 3.8 Flash rates of **$0.75 / 1M input tokens** and **$3.75 / 1M output tokens** (including reasoning/thinking tokens).
  - **Accumulative Session Token Tracker**: Live token tracking badge in the Studio top bar and AI Settings dialog tracking input tokens, output tokens, and accumulative estimated session cost ($USD) with 1-click reset.
- **2-Stage Antigravity Workflow (`1. Concept` → `2. Workbench`)**:
  1. **Stage 1 — Concept Blueprint (`1. Concept` in `lib/screens/project_pitch_screen.dart` & `lib/agents/project_concept_agent.dart`)**:
     - Structure-first Dynamic UI stepper (`01 Goal`, `02 Game Spec`, `03 Tech Spec`, `04 Design Pillars`, `05 Trade-Offs`, `06 Core Loop`, `07 Out of Scope`, `08 Done When`) paired with a section-scoped Agent Console (`gemini-flash-latest`), followed by Step `09 · Full Concept Review`. Clicking **`Approve & Build v0.1 →`** generates `v0.1` and transitions directly into **`2. Workbench`**.
  2. **Stage 2 — Streamlined 2-Surface Open-Canvas Release Workbench (`2. Workbench` in `lib/screens/release_workbench_screen.dart` & `ReleasePlannerAgent` / `ReleaseExecutorAgent`)**:
     - **2-Surface Open-Canvas Architecture**: Recessed Left Outliner Rail (`#0C0E12`) showing Epics (`E01`, `E02`, ...) and **Singular-Focused Features** (`Weapon Equip`, `Player Dash`, `Enemy Wave Spawner`, `Loot Pickup`, `Wave Reset`) + Open Workspace (`#12151B`).
     - **Full-Width vs. Half-Width**: Full-Width (`>= 1040px`) places the fixed-order Step List (`STEPS (X/Y)`) on the left of the workspace and the Active Step (`Do` → `Copy` → `Verify`) on the right. Half-Width (`< 1040px`) collapses into a 1-line floating context bar (`E01 · Epic › Feature ▾` + `Step X/Y ▾ | ‹ ›`).
     - **Progressive AI Releases (`v0.1` → `v0.2` → `v0.3+`)**: Clicking **`+ New Release (v0.2) ✦`** inside the Workbench opens the **Progressive AI Release Co-Pilot** (`gemini-flash-latest`) with 1-click AI direction presets, `UPGRADE` / `NEW` checkboxes, and non-destructive live-tree merging (`NEW`, `UPGRADING`, `STABLE ✓`, `SUPERSEDED`).
     - **Act 2 · Full Production Blueprint (`lib/agents/full_production_blueprint_agent.dart` & `lib/screens/workbench_full_production_blueprint_part.dart`)**: After `03 · Vertical Slice`, **Next Release** opens the 6-section Full Production Blueprint (`01 v1.0 Goal`, `02 Content & World Scale`, `03 Full-Game Loop`, `04 Promoted Systems`, `05 Permanent Cuts`, `06 v1.0 Done When`). Approving builds the `v0.N` **Full-Game Skeleton** (new Full Production Epics tagged `act: fullProduction`, core Epics `STABLE ✓`), followed by **Production Passes** (1–2 Full Production Epics per release), the **`v1.0` Launch Release** (Release Build Export + `0` open `[FIX]`), then `v1.1+` Post-Launch.

## 1. Mandatory Planning, Testing & Push Gates
- **NEVER** edit, create, or modify any project code files (using `replace_file_content`, `write_to_file`, or modifying commands) without first presenting an `implementation_plan.md` artifact and waiting for explicit user confirmation.
- **Strict 5-Step Workflow for all changes**:
  1. **Research Phase**: Use read-only tools (`view_file`, `grep_search`, `find_by_name`, `list_dir`) to thoroughly investigate the codebase.
  2. **Plan Phase**: Create or update `implementation_plan.md` detailing the problem, proposed changes, affected files, and verification plan.
  3. **STOP & Wait**: Do not call any modification tools. End turn and request explicit user confirmation on the plan.
  4. **Execution Phase**: Only after the user confirms/approves the plan, proceed to edit files, run local checks, and execute tests (`flutter test`, `dart analyze`). Keep all intermediate edits local.
  5. **Batch & Ship Gate (Determining When to Push)**:
     - **NEVER push after micro-edits or intermediate steps**. Do not trigger GitHub Actions deployments for minor tweaks.
     - **When to Push to `main`**: Push **ONLY** when:
       a. A cohesive deliverable (full Feature, complete screen overhaul, or end-to-end bug fix) is 100% finished.
       b. Static analysis and test suites pass with 0 errors.
       c. The **Playtest Gate** is passed (observable verification on screen or via tests).
       d. The user is presented with a summary of the batch and gives explicit confirmation to push.
     - **Two-Tier Push Strategy (Remote VM Safety)**:
       - *Small/Single-turn work*: Keep commits local until ready for the confirmation gate, then push to `main`.
       - *Multi-turn / Large Systems*: Push intermediate WIP commits to a feature branch (`feat/*` or `dev`) to back up code against VM restarts without triggering a `gh-pages` deployment.
     - **`[skip ci]` Protocol**: Always append `[skip ci]` to commit messages for documentation, workspace rules (`GEMINI.md`), or notes to avoid running redundant CI build minutes.

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
  - **Design Pillars vs. Trade-Offs**:
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

## 6. Canonical LAYERS Text Format Style Guide (`STYLE_GUIDE.md` & `lib/constants/text_style_guide.dart`)
- **Single Source of Truth**: Always consult [`STYLE_GUIDE.md`](STYLE_GUIDE.md) and reference [`LayersTextStyleGuide`](lib/constants/text_style_guide.dart) across Stage 1 and Stage 2 prompts and Gemini tool schemas so the AI emits the exact target format on the first pass (zero 2-step post-formatting token waste):
  1. **BLUF (`[2–4 Word Payoff] — [Scope]`)**: Used for Progressive Release `GOAL:` lines, `EPICS` Option Cards, and Stage 1 `01 · Goal` / `04 · Design Pillars` / `06 · Core Loop`.
  2. **Causal `Trigger → Result` (`[Player Action] → [Observable Screen Result]`, `<= 14 words`)**: Used for `✓ END GOAL:` (`doneWhen`), `VERIFY IN ENGINE` (`verifyResult`), and Feature `doneWhen` / `playtestCriteria`.
  3. **Changelog / Delta-Diff (`+Delta`, `5–10 words`)**: Used for Progressive Release Feature Rows (`☑ Title — +delta1, +delta2 [UPGRADE]`), Workbench Feature Goal subtitles, and `inScope` bullets (never start feature goals with `"Build/Upgrade <Feature> into/with..."`).
  4. **Imperative Runbook (`Verb + Object + Value`)**: Used for Child Sub-Step Titles (`3–4` Title-Case words without `"STEP X.Y ·"` prefix, e.g. `"Spawn 6 Pellet Raycasts"`) and `DO` instructions (`1` imperative sentence `<= 18 words` naming the exact node/script and tuning value).
  5. **Telegraphic Component / Micro-Labels (`2–4` Title-Case Words)**: Used for Parent Task Group Titles (`tasks[].title` in `01 STEPS`, e.g. `"Collision Layer & Flags"`, `"Impulse & Window Timer"`, `"Ghost Trail & SFX"` — no verbs, no 3-item lists, no `"while/when"` clauses, no `(2h)` tags), Epic/Feature titles, Stage 1 `02 Game Spec` / `03 Tech Spec` cells (`2–5` words), `05 Trade-Offs` (`2–4` words per side), `07 Out of Scope` (`"No [2–4 word system]"`), and `[STATE GUARD]` chips.

## 7. Meta-LAYERS Pair Programming Protocol (Dogfooding the App)
When designing and building LAYERS-Agentic, treat the app itself with the exact same rigor that LAYERS applies to game production:

### 1. Epics & Singular-Focused Features
- Map major app systems as **Epics** (`E01 · Concept Studio`, `E02 · Workbench Canvas`, `E03 · CI/CD & Deploy Engine`).
- Map tasks as **Singular Features** with observable deliverables (`Token Tracker Badge`, `Playtest Bug Drawer`, `Batch Push Gate`). Never create abstract micro-tickets.

### 2. The 3-Part Scope Rule for App Tasks
Every non-trivial plan, PRD, or task proposal must follow the canonical LAYERS 3-part layout:
- **Goal**: Exactly one plain-English sentence stating what is being built/fixed and why (BLUF).
- **In Scope**: A concise bulleted list of `+delta` additions/changes.
- **Done When**: A causal `Trigger → Result` test condition (`[Action] → [Observable Screen / State Result]`).

### 3. Design Pillars & Trade-Offs for App Decisions
- When evaluating design decisions for the app, frame them as explicit **Trade-Offs (`X over Y`)**:
  - *Immediate local iteration over remote runner latency.*
  - *Batch milestone pushes over continuous deploy noise.*
  - *Deterministic single-pass prompts over chatty multi-step agents.*

### 4. The Playtest Gate (App QA)
- Never declare a feature or milestone complete based on code edits alone.
- In app development, passing the **Playtest Gate** requires:
  1. **Zero Failures**: `dart analyze` reports 0 errors and `flutter test` passes 100%.
  2. **Observable Screen Verification**: Verifying the UI behavior on screen, via unit/widget tests, or via interactive preview widgets.
  3. **Inline Fixes**: If any defect is found during review, log and resolve it before completing the task.

### 5. Milestone Batch Release Gate
- Only propose pushing to `main` when a full deliverable passes the Playtest Gate.
- Use `[skip ci]` in commit messages for documentation, rules, and non-deploy commits.

## 8. Adaptive Model & Thinking Routing Protocol (Session & Subagent Automation)
The assistant automatically classifies every task across 3 complexity tiers to determine the optimal model and thinking budget across **BOTH** the **Planning Phase** and the **Implementation Phase**:

### 1. Classification Rubric (Planning & Implementation)
- **The 3-System Rule**: If solving or implementing a task requires reasoning about $\ge 3$ interconnected systems, state providers, or multi-file contracts simultaneously, it automatically routes to **Argon (Pro)** for both planning and implementation.
- **The Low Thinking Sweet Spot**: 80% of harder coding tasks (multi-file refactors, release plans, test suites) are handled with **Argon `LOW` thinking** for 3–6s latency with zero drift.
- **High Thinking Escalation**: Reserved for elusive root-cause debugging, flaky asynchronous race conditions, and complex state machine loops during either planning or implementation.
- **User Override Authority**: Explicit user requests for a specific model or thinking level unconditionally override automated routing.

### 2. Autonomous Phase & Tier Action Matrix
1. **Tier 1 (Fast Execution · Flash Low)**:
   - *Planning*: Lightweight task breakdown or direct bug isolation.
   - *Implementation*: Local UI styling, isolated widget tweaks, git/bash commands, straightforward unit tests $\rightarrow$ Executed with **Gemini 3.8 Flash · Thinking Low**.
2. **Tier 2 (Architectural & Multi-System · Argon Pro Low)**:
   - *Planning*: Release planning, cross-module architecture, state provider design $\rightarrow$ Planned with **Argon Pro · Thinking Low**.
   - *Implementation*: Multi-file refactors touching $\ge 3$ files/providers, API contract shifts, complex schema migrations $\rightarrow$ Implemented with **Argon Pro · Thinking Low** (utilizing `pro` subagent or structured high-rigor tool execution) to eliminate regression risk.
3. **Tier 3 (Deep Bug & Concurrency · Argon Pro High)**:
   - *Planning*: Root-cause analysis of intermittent race conditions, deadlocks, or ambiguous protocol bugs $\rightarrow$ Diagnosed with **Argon Pro · Thinking High**.
   - *Implementation*: Surgical fix implementation and concurrency regression testing $\rightarrow$ Implemented with **Argon Pro · Thinking High**.

### 3. Dynamic In-Flight Escalation
If an initially light implementation task reveals coupling across $\ge 3$ systems or encounters unexpected test failures during execution, automatically halt code modifications, escalate implementation to Tier 2 (Argon Pro · Thinking Low) or Tier 3 (Argon Pro · Thinking High), and notify the user with a rationale.

### 4. Transparency Badge
Whenever an operation is routed or escalated to Tier 2 or Tier 3 during either planning or implementation, prefix the turn or plan summary with:
`[Auto-Route: Argon Pro · Thinking Low (Planning)]` / `[Auto-Route: Argon Pro · Thinking Low (Implementation)]` or `[Auto-Route: Argon Pro · Thinking High (Planning/Implementation)]`.



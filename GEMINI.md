# Workspace Rules for LAYERS-Agentic

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Deploy Command**: Run `./scripts/deploy.sh` from the project root (automatically encodes `$GEMINI_API_KEY` into base64 `--dart-define=GEMINI_API_KEY_B64=...` so GitHub Push Protection never blocks `gh-pages` pushes).
- **AI Model (`lib/agents/gemini_agent_client.dart` & `lib/providers/workbench_provider.dart`)**:
  - **Standard Model Across Entire App**: `gemini-4-hydrogen` (with automatic `gemini-flash-latest` failover) and `thinkingLevel: "LOW"` default (`LOW` / `MEDIUM` / `HIGH`) for Stage 1 Concept Blueprint co-design and Stage 2 Release Workbench planning and synthesis.
  - **Active Pricing Rates**: Gemini 4 Hydrogen rates of **$1.50 / 1M input tokens** and **$7.50 / 1M output tokens** (including reasoning/thinking tokens).
  - **Accumulative Session Token Tracker**: Live token tracking badge in the Studio top bar and AI Settings dialog tracking input tokens, output tokens, and accumulative estimated session cost ($USD) with 1-click reset.
- **2-Stage Antigravity Workflow (`1. Concept` → `2. Workbench`)**:
  1. **Stage 1 — Concept Blueprint (`1. Concept` in `lib/screens/project_pitch_screen.dart` & `lib/agents/project_concept_agent.dart`)**:
     - Structure-first Dynamic UI stepper (`01 Goal`, `02 Game Spec`, `03 Tech Spec`, `04 Design Pillars`, `05 Trade-Offs`, `06 Core Loop`, `07 Out of Scope`, `08 Done When`) paired with a section-scoped Agent Console (`gemini-4-hydrogen` with automatic `gemini-flash-latest` failover), followed by Step `09 · Full Concept Review`. Clicking **`Approve & Build v0.1 →`** generates `v0.1` and transitions directly into **`2. Workbench`**.
  2. **Stage 2 — Streamlined Feature-First Open-Canvas Release Workbench (`2. Workbench` in `lib/screens/release_workbench_screen.dart` & `ReleasePlannerAgent` / `ReleaseExecutorAgent`)**:
     - **2-Surface Open-Canvas Architecture**: Recessed Left Outliner Rail (`#0C0E12`) showing Epics (`E01`, `E02`, ...) and **Singular-Focused Features** (`Weapon Equip`, `Player Dash`, `Enemy Wave Spawner`, `Loot Pickup`, `Wave Reset`) + Open Workspace (`#12151B`).
     - **Feature-First Ticket Depth (Highest Ticket = Feature)**: Stops strictly at **Feature** level (zero AI micro-steps, zero `tasks[]`, zero hidden `.gd` synthesis). Full-Width (`>= 1040px`) pairs the Left Outliner Rail (`Queued`, `In Progress · N%`, `Issues (N)`, `Passed ✓`) with the unified **Feature Specification & Playtest Gate** workspace (`Goal`, `In Scope`, `Tuning Variables`, interactive `[STATE GUARD]` / `[PLAYTEST GUARD]` checkboxes, `[FIX]` Playtest Issues, `Done When` gate, and `Copy AI Prompt`). Half-Width (`< 1040px`) collapses navigation into a 1-line floating context bar (`E01 · Epic › Feature ▾`).
     - **Progressive AI Releases (`v0.1` → `v0.2` → `v0.3+`)**: Clicking **`+ New Release (v0.2) ✦`** inside the Workbench opens the **Progressive AI Release Co-Pilot** (`gemini-4-hydrogen`) with 1-click AI direction presets, `UPGRADE` / `NEW` checkboxes, and non-destructive live-tree merging (`NEW`, `UPGRADING`, `STABLE ✓`, `SUPERSEDED`).
     - **Act 2 · Full Production Blueprint (`lib/agents/full_production_blueprint_agent.dart` & `lib/screens/workbench_full_production_blueprint_part.dart`)**: After `03 · Vertical Slice`, **Next Release** opens the 6-section Full Production Blueprint (`01 v1.0 Goal`, `02 Content & World Scale`, `03 Full-Game Loop`, `04 Promoted Systems`, `05 Permanent Cuts`, `06 v1.0 Done When`). Approving builds the `v0.N` **Full-Game Skeleton** (new Full Production Epics tagged `act: fullProduction`, core Epics `STABLE ✓`), followed by **Production Passes** (1–2 Full Production Epics per release), the **`v1.0` Launch Release** (Release Build Export + `0` open `[FIX]`), then `v1.1+` Post-Launch.
  3. **Native Godot 4 Split-Workflow Dock (`godot_plugin/addons/layers/*`, `v3.0.2`)**:
     - **Division of Labor**: Web Studio owns **Planning & Scope** (Concept, Releases, Epic/Feature specs); the native `260px` Godot 4 Dock owns **In-Engine Focus & Playtest Sign-Off** on the single active Epic.
     - **4 Core Jobs Only (Pure KISS/YAGNI)**: (1) Read-only Active Feature Spec (`Goal`, `In Scope`, `Tuning Variables`, interactive `Playtest Guards`, `Done When`), (2) **`Copy Context`** bridging the LAYERS Feature spec + live local Godot `.tscn` trees, `.gd` scripts, `InputMap`, and recent Debugger/Output errors to the clipboard, (3) **`Playtest Scene (F6)`** + real-file `Open Scene` / `Open Script` + automatic runtime error capture (`Log Issue` / `:line` jump), and (4) **2-Way Gate Sync** (`/godotLink/epic` & `/godotLink/update` via `lyr_...` token) + `Open Web Studio ↗` deep-link. Never add AI code generation, `.tscn`/`.gd` file mutation, or multi-Epic roadmap management inside the Godot plugin.

## 1. Default Auto-Goal & Auto-Grill Loop Workflow
- **Automated `Auto GG` Continuous Loop (`/auto-gg` or `"Auto GG"`)**:
  - Typing `/auto-gg [optional focus]` or `"Auto GG"` launches [SKILL.md](.agents/skills/auto-gg/SKILL.md) + [auto_gg_hook.py](.agents/hooks/auto_gg_hook.py), which automatically scans live repo/Godot signals (`discover_signals.py`), pitches top concrete Goals + grills UX forks via `ask_question`, builds & verifies (`./scripts/verify_loop.sh`), commits, and auto-advances to the next Goal + Grill round until canceled or told `stop` / `pause`.
- **Opt-In `SEA` Lens (`/sea` or `"SEA"` — Subtract, Enhance, Add)**:
  - Activate [SKILL.md](.agents/skills/sea/SKILL.md) **only** when `/sea` or `SEA` is explicitly written in the prompt (including `auto gg SEA ...`) to audit, grill, and execute strictly in **Subtract → Enhance → Add** order.
- **Auto-Goal (Self-Derived Goal Contracts — Always On)**:
  - On any symptom report, audit request, or open-ended prompt, inspect the codebase, tests, and headless Godot probes first to derive a concrete **Goal Contract** (`Goal`, `In Scope`, and machine-verifiable `Done When` checks).
  - When a prompt is open-ended (e.g., *"audit LAYERS"* or a broad symptom with multiple gaps), automatically select the **#1 highest-impact safe goal** and run its verification loop immediately rather than pausing on a backlog menu.
- **Auto-Grill (Upfront Clarification via `ask_question` — Only on Real UX/Scope Forks)**:
  - Resolve pure engineering, data-structure, and Godot API trade-offs internally against the codebase and headless probes—never ask the user technical minutiae.
  - When genuine product, UX, or scope trade-offs exist, ask 1–3 concise multiple-choice questions upfront using `ask_question` (`(Recommended)` option first) before editing.
- **Execution Gate (When to Pause vs. Loop Immediately)**:
  - **Clear / Small-to-Medium Tasks, Bug Fixes & `/goal` Runs**: Once Auto-Grill resolves any ambiguity (or immediately if unambiguous), write/run a failing test or headless Godot probe first, then iterate autonomously (`Edit → ./scripts/verify_loop.sh → Self-Repair`) to `0` errors without an extra `implementation_plan.md` pause.
  - **Major UI Redesigns & Core Architecture Changes**: Present a concise `implementation_plan.md` (`Goal`, `In Scope`, `Affected Files`, `Done When`) and wait for explicit user approval before editing project code files.
- **External User Godot Projects (`/Users/henry/Godot/Projects/*`)**:
  - User game files (`project.godot`, `scenes/*`, `scripts/*`) are strictly **read-only** reference fixtures (enforced by `.agents/hooks.json`). Always fix LAYERS's plugin/agent instead, syncing only `addons/layers/*` when explicitly verifying in Godot.

## 2. Multi-Stack Verification & Loop Gate
- Run `./scripts/verify_loop.sh` (pass `--fix-zip` if `godot_plugin/` changed) before committing.
- Passing requires `0` errors across: `node --check functions/index.js`, `web/layers_godot_plugin.zip` byte parity, headless Godot `4.7.2` plugin smoke probes (`scripts/godot_plugin_smoke.gd`), `dart analyze`, and `100%` passing `flutter test` (enforced automatically on turn completion by `.agents/hooks.json`).

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
  - **Automatic Rollups**: Progress and gate counts roll up dynamically from Feature Playtest Guards (0–50% pre-pass) and Playtest Gates (100% on Pass) all the way up to Project (Tier 1) without manual duplicate entry.

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
  2. **Causal `Trigger → Result` (`[Player Action] → [Observable Screen Result]`, `<= 14 words`)**: Used for `✓ END GOAL:` (`doneWhen`) and Feature Playtest Gate (`doneWhen` / `playtestCriteria`).
  3. **Changelog / Delta-Diff (`+Delta`, `5–10 words`)**: Used for Progressive Release Feature Rows (`☑ Title — +delta1, +delta2 [UPGRADE]`), Workbench Feature Goal subtitles, and `inScope` bullets (never start feature goals with `"Build/Upgrade <Feature> into/with..."`).
  4. **Telegraphic Micro-Labels & Tuning/Guard Chips (`2–4` Title-Case Words)**: Used for Epic/Feature titles, Stage 1 `02 Game Spec` / `03 Tech Spec` cells (`2–4` words), `05 Trade-Offs` (`2–4` words per side), `07 Out of Scope` (`"No [2–4 word system]"`), `Tuning Variables` (`"paramName: numericValue unit"`), and `[STATE GUARD]` / `[PLAYTEST GUARD]` chips.




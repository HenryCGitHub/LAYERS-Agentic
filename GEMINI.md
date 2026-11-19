# Workspace Rules for LAYERS-Agentic

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Deploy Command**: Run `./scripts/deploy.sh` from the project root (packages [`web/layers_godot_plugin.zip`](web/layers_godot_plugin.zip), builds release Flutter Web, and pushes `origin/gh-pages`).
- **AI Model ([`lib/agents/gemini_agent_client.dart`](lib/agents/gemini_agent_client.dart) & [`lib/providers/workbench_provider.dart`](lib/providers/workbench_provider.dart))**:
  - **Standard Model Across Entire App**: `gemini-4-hydrogen` (with automatic `gemini-flash-latest` failover) and `thinkingLevel: "LOW"` default (`LOW` / `MEDIUM` / `HIGH`) for Stage 1 Project Spec co-design, Stage 2 Progressive Release planning, and In-Dock Godot 4 Builder (`build_epic`).
  - **Active Pricing Rates**: Gemini 4 Hydrogen rates of **$1.50 / 1M input tokens** and **$7.50 / 1M output tokens** (including reasoning/thinking tokens).
  - **Accumulative Session Token Tracker**: Live token tracking badge in the Studio top bar and AI Settings dialog tracking input tokens, output tokens, and accumulative estimated session cost ($USD) with 1-click reset.
- **2-Stage Godot 4 (`3D` + `2D`) 4-Tier Structured Game Planner (`1. Project Spec` → `2. Release Workbench`)**:
  - **Strict 4-Tier Hierarchy (`Project -> Release -> Epic -> Feature`)**: Designed exclusively for Godot 4 (`3D`: `1 unit = 1 m` | `2D`: `px`), producing clean high-level design specs that compile directly into Godot Build Contexts—zero `Task` or `Step` sub-tickets, zero AI implementation micro-steps, zero Unreal/Unity leakage (`.uasset`, `.uproject`, `Blueprint`, `ACharacter`, `UMG`, `cm/s`), and zero field overlap between **Epics (Large Domains)** and **Features (30–90 min Playable Slices)**.
  1. **Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))**:
     - Spark intake (custom prompt or starter presets: `shellbreaker`, `railjack`, `emberkeep`) paired with auto-detected & toggleable `3D (m, m/s)` / `2D (px, px/s)` dimension pills (`stage1_dim_3d` / `stage1_dim_2d`), camera decision fork (`cameraOptions[]`), bottom Co-Designer bar, and **Clean Spec Document** (`PROJECT_SPEC.md`) vs **Raw `ROOT_GODOT_CONTEXT.md`** view across `§01`–`§05` (seeded `v0.1` Large-Domain Epics previewing initial `F01–F0N` slices in `§05`). Clicking **`Approve & Launch`** seeds `v0.1` and enters **`2. Release Workbench`**.
  2. **Stage 2 — Release Workbench (`2. Release Workbench` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart), [`lib/models/epic_spec.dart`](lib/models/epic_spec.dart), & [`lib/utils/godot_context_builder.dart`](lib/utils/godot_context_builder.dart))**:
     - **Expandable Left Outliner + Breadcrumbs**: Expandable `Epic -> Feature` tree with release switcher pills (`v0.1` / `v0.2+` / `+ New Release`) and clickable Breadcrumbs (`Project / Release / Epic [/ Feature]`).
     - **Non-Overlapping Epic Domain Sheet vs. Feature Spec Sheet**:
       - **Epic Domain Sheet (`selectedFeatureId == null`)**: `§01 Domain Scope` (`Goal`, `In Scope`, `Done When`), `§02 Shared Scene & Script Ownership`, `§03 Shared State & Interrupt Rules`, `§04 Domain Out-of-Scope Cuts`, and `§05 Child Features` + `+ Add Feature Slice`.
       - **Feature Slice Spec Sheet**: `§01 Feature Scope`, `§02 Input Actions (InputMap)`, `§03 Exposed Tuning (@export GDScript Vars)`, `§04 Viewport, UI & Audio Cues`, `§05 Playtest Gate & [FIX] Notes`, plus locked `[v0.1]` baseline banner (`Open in v0.1 →`) when viewing prior-shipped slices in `v0.2+`.
     - **AI Build Prompt & Live Playtest Loop**: Switching to **`AI Build Prompt`** or clicking **`Copy Build Prompt`** bundles **Project Contract + Parent Epic Architecture + Active Feature Spec** ([`GodotContextBuilder.buildFeatureContext`](lib/utils/godot_context_builder.dart)); editing `§03` `@export` tuning updates the prompt immediately; logging a `[FIX]` switches execution mode to `FOCUSED [FIX] PASS`; resolving fixes and clicking `Pass Feature ✓` rolls up Epic progress and advances to the next open Feature (`reopenFeature` restores it).
     - **Progressive AI Releases (`v0.1` → `v0.2` → `v0.3+` via [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))**: Clicking **`+ New Release`** opens the Progressive Release Co-Pilot with AI direction presets, `[+DELTA]` upgrade checkboxes targeting existing Features, `[+NEW]` Feature slice checkboxes attached directly inside existing permanent Epics without duplicating cards, and `[NEW]` candidate Epics.
  3. **Pure-GDScript LAYERS Godot 4 Editor Plugin ([`godot_plugin/addons/layers/`](godot_plugin/addons/layers/plugin.cfg), `v4.0.1`, packaged as [`web/layers_godot_plugin.zip`](web/layers_godot_plugin.zip))**:
     - **Division of Labor**: Web Studio owns **Project Spec, Release Planning & Epic/Feature Design**; the in-editor Godot 4 Dock owns **live `.tscn`/`.gd`/`InputMap` snapshot capture, 1-click In-Dock Cloud Gemini Builder (`⚡ Build E01` / `🔧 Fix E01`), compile-error self-heal, Undo/Play, and Playtest sync**.
     - **Modules**: [`plugin.cfg`](godot_plugin/addons/layers/plugin.cfg), [`layers_plugin.gd`](godot_plugin/addons/layers/layers_plugin.gd), [`layers_dock.gd`](godot_plugin/addons/layers/layers_dock.gd), [`layers_sync_client.gd`](godot_plugin/addons/layers/layers_sync_client.gd) (`TCPServer` `127.0.0.1` Google Sign-In loopback + `/godotLink/*` + GitHub self-update), and [`layers_step_executor.gd`](godot_plugin/addons/layers/layers_step_executor.gd).
     - **2-Way Cloud Functions Sync & Agent ([`functions/index.js`](functions/index.js) & [`firestore.rules`](firestore.rules))**: Token provisioning (`/godotLink/token`), live project snapshot injection & active Epic context pull (`/godotLink/epic`), and Playtest check / tuning / `[FIX]` / Pass / Reopen / Cloud Gemini build (`build_epic` & `fix_epic`) push (`/godotLink/update`) via `lyr_...` tokens stored server-only in `godot_links`. Note `workbench_godot_mixin.dart` keeps `activeEpicGodotContext` backwards-compatible alongside 4-tier `activeGodotSyncContext`.

## 1. Composable `Auto-Goal`, `Auto-Grill`, and 2-Step `Auto GG` Workflows
- **Bounded Hands-Off `Auto-Goal` (`/auto-goal [N] [focus]` or `"auto goal [N]"`)**:
  - Launches [`.agents/skills/auto-goal/SKILL.md`](.agents/skills/auto-goal/SKILL.md) + [`.agents/hooks/auto_gg_hook.py`](.agents/hooks/auto_gg_hook.py) (`mode: "goal"`, `phase: "discovering"`, **default `N = 3`** rounds when omitted, or `1..50`).
  - Runs [`discover_signals.py`](.agents/skills/auto-goal/scripts/discover_signals.py), skips `ask_question`, auto-selects the `#1` highest-confidence bug, Stage 1/2/Godot Dock parity gap, or test coverage target (never inventing speculative UI features), prints a 1-line `[Round k/N Goal]` banner, executes `Red → ./scripts/verify_loop.sh → Commit`, calls `enter_plan_mode(reason='[round-complete] ...')`, and automatically stops with a `1..N` changelog after Round `N/N` (or earlier on `stop` / `"finish ... and pause"`).
- **Standalone Targeted `Auto-Grill` (`/auto-grill <target>`)**:
  - Launches [`.agents/skills/auto-grill/SKILL.md`](.agents/skills/auto-grill/SKILL.md) (`mode: "grill"`).
  - Skips `discover_signals.py`, inspects affected files directly, asks `1–3` high-signal UX/scope questions via `ask_question` (`(Recommended)` first, or skips if zero UX ambiguity), locks the Goal Contract, executes & verifies once, and stops cleanly.
- **Interactive 2-Step `Auto GG` Loop (`/auto-gg [N] [focus]` or `"Auto GG"`)**:
  - Launches [`.agents/skills/auto-gg/SKILL.md`](.agents/skills/auto-gg/SKILL.md) (`mode: "gg"`), open-ended by default (`maxRounds: 0`, gated per round by `ask_question`) or bounded when `[N]` is provided: **Step 1** (`select_goal`) runs [`discover_signals.py`](.agents/skills/auto-goal/scripts/discover_signals.py) and asks **1 Goal Choice question** (`PreToolUse` denies premature `exit_plan_mode`); **Step 2** (`grill_chosen`) applies `Auto-Grill` strictly to the chosen goal (skipping if zero UX forks); then executes, verifies, commits, and advances via `[round-complete]` until canceled, stopped, or Round `N/N` completes.
- **Opt-In `SEA` Lens (`/sea` or `"SEA"` — Subtract, Enhance, Add)**:
  - Activate [SKILL.md](.agents/skills/sea/SKILL.md) **only** when `/sea` or `SEA` is explicitly written in the prompt (including `auto gg SEA ...`) to audit, grill, and execute strictly in **Subtract → Enhance → Add** order.
- **Auto-Goal (Self-Derived Goal Contracts — Always On)**:
  - On any symptom report, audit request, or open-ended prompt, inspect the codebase, tests, and headless Godot/Cloud/workflow test scripts (`scripts/godot_plugin_test.gd`, `scripts/godot_cloud_test.py`, `scripts/workflow_hook_test.py`) first to derive a concrete **Goal Contract** (`Goal`, `In Scope`, and machine-verifiable `Done When` checks).
  - When a prompt is open-ended (e.g., *"audit LAYERS"* or a broad symptom with multiple gaps), automatically select the **#1 highest-impact safe goal** and run its verification loop immediately rather than pausing on a backlog menu.
- **Auto-Grill (Upfront Clarification via `ask_question` — Only on Real UX/Scope Forks)**:
  - Resolve pure engineering, data-structure, and Godot Context contract trade-offs internally against the codebase and headless tests—never ask the user technical minutiae.
  - When genuine product, UX, or scope trade-offs exist, ask 1–3 concise multiple-choice questions upfront using `ask_question` (`(Recommended)` option first) before editing.
- **Execution Gate (When to Pause vs. Loop Immediately)**:
  - **Clear / Small-to-Medium Tasks, Bug Fixes & `/goal` Runs**: Once Auto-Grill resolves any ambiguity (or immediately if unambiguous), write/run a failing test first, then iterate autonomously (`Edit → ./scripts/verify_loop.sh → Self-Repair`) to `0` errors without an extra `implementation_plan.md` pause.
  - **Major UI Redesigns & Core Architecture Changes**: Present a concise `implementation_plan.md` (`Goal`, `In Scope`, `Affected Files`, `Done When`) and wait for explicit user approval before editing project code files.
- **External User Game Projects Strictly Read-Only**:
  - External user game projects (such as `/Users/henry/Godot/Projects/*`) are strictly **read-only** reference fixtures (enforced by `.agents/hooks.json`). Always fix LAYERS's own app/plugin code instead.

## 2. Multi-Stack Verification & Loop Gate
- Run `./scripts/verify_loop.sh` (pass `--fix-zip` if `godot_plugin/addons/layers/` changed) before committing.
- Passing requires `0` errors across: `node --check functions/index.js`, `web/layers_godot_plugin.zip` byte parity, headless Godot `4.7.2` plugin test (`godot_plugin_test.gd` -> `GODOT_PLUGIN_TEST_OK`), Cloud test (`scripts/godot_cloud_test.py` -> `GODOT_CLOUD_TEST_OK`), workflow hook test (`scripts/workflow_hook_test.py` -> `WORKFLOW_HOOK_TEST_OK`), `dart analyze`, and `100%` passing `flutter test` (enforced automatically on turn completion by `.agents/hooks.json`).

## 3. Communication Style
- Keep responses concise and focused.
- Create clickable `file:///` links for referenced files and code symbols.

## 4. Pure KISS, DRY, and YAGNI Principles (Codebase & App)

### 1. KISS (Keep It Simple & Playable)
- **Codebase**: Write the simplest, most direct working Flutter and GDScript code. Avoid complex state machines, micro-factories, or multi-step prompt pipelines when simple Provider mixins and single-pass prompts work.
- **App & AI**:
  - **The Playtest Rule**: If a player or QA tester cannot see, hear, or feel it on screen in Godot Playtest, rephrase it into an observable deliverable.
  - **Large-Domain Epics -> 30–90 Min Playable Features**: **Epics** hold domain architecture (`goal`, `inScope`, `doneWhen`, `sceneOwnership`, `stateFlow`, `interruptRules`, `outOfScope`) once without duplicating slice inputs or variables; child **Features** hold playable slice contracts (`InputMap` bindings, `@export` tuning in `m`/`px`, visual/audio cues, and Playtest checks). Do NOT generate `Task` tickets or AI step lists.
  - **Plain Functional Titles (No Thematic / Lore Wording)**: Keep Epic & Feature titles short and literal (2–5 plain everyday game-dev words). Name the actual gameplay system (e.g., *Player Movement & Camera*, *Armored Claw Dash*) — NEVER use flowery, archaic, or roleplay/lore words (e.g., *Homestead Husbandry*, *Expedition Prep*, *Adrenaline Crop Buffs*).
  - **Design Pillars vs. Trade-Offs**:
    - **Design Pillars (3–4 statements)**: Name the core experiences the game must create and how it should make the player feel—NOT how it is built, NOT a feature (*"has a skill tree"*), and NOT a genre (*"a roguelike"*), but the experience those things exist to hold up (*"Every dash commits"*).
    - **Trade-Offs (2–3 `<prefer> OVER <avoid>` rules)**: Practical engineering/design boundaries used to resolve conflicts (e.g., *`Snappy Arcade Response OVER Momentum Simulation`*).

### 2. DRY (Don't Repeat Yourself / Single Source of Truth)
- **Codebase**:
  - Centralize shared tokens (theme, tier colors, prompts, [`GodotSpecGuard`](lib/utils/godot_spec_guard.dart), [`GodotContextBuilder`](lib/utils/godot_context_builder.dart)).
  - **Rule of Three**: Only create shared abstractions after writing the exact same logic three times.
- **App & AI**:
  - **Single Source of Truth (Evolving Live Release Tree)**: Every permanent mechanic lives under a single `Project -> Release -> Epic -> Feature` lineage across `v0.1` → `v0.2` → `v1.0+`, carrying locked `[v0.1]` baselines and attaching `[+NEW]` Features and `[+DELTA]` upgrades inside existing permanent Epics without duplicating cards across releases.
  - **Automatic Rollups**: Epic Feature passed/total counts (`passed/total`), open `[FIX]` counts, and execution mode (`FULL FEATURE BUILD` vs `FOCUSED [FIX] PASS`) derive dynamically from child `FeatureSpec` lists without duplicate manual entry.

### 3. YAGNI (You Aren't Gonna Need It / Scope Discipline)
- **Codebase**: Build strictly what the immediate feature requires today. Strip out hypothetical future-proofing, extra database columns, or unneeded packages before writing code.
- **App & AI**:
  - **Strict `v0.1` Prototype Gate**: Stage 1 `§05` and initial `v0.1` Epics/Features contain *only* playable prototype mechanics; `v0.2+` waves, progression, and meta layers wait for Progressive Releases.
  - **Focus Mode**: Spotlight only 1 active Release and 1 active Epic or Feature slice at a time so `Copy Build Prompt` and Godot Dock outputs stay crisp and uncluttered.

## 5. Scope & Goal Formatting Rule
Whenever writing or revising any Scope, Goal, or Objective section (across Epics, PRDs, specs, or design docs), follow these constraints:
- **No Paragraphs**: Never write scope or goals as dense narrative text. Always use this structured 3-part layout:
  - **Goal**: Exactly one plain-English sentence stating what is being built/done and why.
  - **In Scope**: A concise bulleted list of the specific systems, features, or assets included.
  - **Done When**: Clear, practical conditions for when the work is considered complete.
- **Tone**: Write like a practical developer talking to a teammate. Keep it direct, literal, and natural.
- **Non-Thematic / Literal Wording**: Describe mechanics in plain engineering/design terms (e.g., *"Spawn 3 enemy waves in arena_proto.tscn and break shell armor on claw dash"* instead of *"Pit the player against aggressive demon waves in an out-of-town wasteland"*).
- **Banned Jargon & Archaic Words**: Never use corporate filler or vague buzzwords (*leverage*, *unified*, *end-to-end loop*, *staging*, *validate*, *verified*, *deliver*, *synergy*, *seamlessly*) or flowery/archaic lore synonyms (*husbandry*, *homestead*, *expedition*, *ordinance*). State the actual concrete action instead.

## 6. Canonical LAYERS Text Format Style Guide (`STYLE_GUIDE.md` & `lib/constants/text_style_guide.dart`)
- **Single Source of Truth**: Always consult [`STYLE_GUIDE.md`](STYLE_GUIDE.md) and reference [`LayersTextStyleGuide`](lib/constants/text_style_guide.dart) + [`GodotSpecGuard`](lib/utils/godot_spec_guard.dart) across Stage 1 and Stage 2 prompts and Gemini tool schemas so AI output emits Godot-native high-level design specs on the first pass:
  1. **BLUF (`[2–4 Word Payoff] — [Scope]`)**: Used for Stage 1 `pitch` (`§01`) and Progressive Release presets/goals.
  2. **Causal Playtest Gate (`[Player Action] -> [Observable Viewport Result]`, `<= 14 words`)**: Used for `releaseDoneWhen` (`§05`) and Feature Playtest `checks[]` (`§05`).
  3. **Changelog / Delta-Diff (`+Delta`, `5–10 words`)**: Used for Progressive Release `[+DELTA]` upgrades atop locked `v0.1` baselines and `[+NEW]` Feature slices.
  4. **Godot 4 Scale & Telegraphic Micro-Labels (`3D: m` | `2D: px`)**: Used for Epic/Feature titles (`2–5` words), `§02` Camera/Scale/Input contracts, `§04` Hard Scope Cuts (`"No [2–5 word system]"`), and Feature `§03` Exposed Tuning (`snake_case` `@export` vars in `m`, `m/s`, `px`, `px/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`).

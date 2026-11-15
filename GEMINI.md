# Workspace Rules for LAYERS-Agentic

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Deploy Command**: Run `./scripts/deploy.sh` from the project root (automatically encodes `$GEMINI_API_KEY` into base64 `--dart-define=GEMINI_API_KEY_B64=...` so GitHub Push Protection never blocks `gh-pages` pushes).
- **AI Model ([`lib/agents/gemini_agent_client.dart`](lib/agents/gemini_agent_client.dart) & [`lib/providers/workbench_provider.dart`](lib/providers/workbench_provider.dart))**:
  - **Standard Model Across Entire App**: `gemini-4-hydrogen` (with automatic `gemini-flash-latest` failover) and `thinkingLevel: "LOW"` default (`LOW` / `MEDIUM` / `HIGH`) for Stage 1 Project Spec co-design and Stage 2 Progressive Release planning.
  - **Active Pricing Rates**: Gemini 4 Hydrogen rates of **$1.50 / 1M input tokens** and **$7.50 / 1M output tokens** (including reasoning/thinking tokens).
  - **Accumulative Session Token Tracker**: Live token tracking badge in the Studio top bar and AI Settings dialog tracking input tokens, output tokens, and accumulative estimated session cost ($USD) with 1-click reset.
- **2-Stage Unreal-Only Design Spec Workflow (`1. Project Spec` → `2. Epic Specs`)**:
  - **Strict 3-Tier Hierarchy (`Project -> Release -> Epic`)**: Designed exclusively for Unreal Engine (`1 UU = 1 cm`), producing clean high-level design specs that compile directly into Unreal MCP context payloads—zero `Feature` or `Task` sub-tickets, zero AI implementation micro-steps, and zero Godot concepts (`.tscn`, `.gd`, `px/s`).
  1. **Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))**:
     - Spark intake (custom prompt or Unreal starter presets: `shellbreaker`, `railjack`, `emberkeep`) paired with a `UE 5.9 MCP` / `UE6 Verse` architecture toggle, camera decision fork (`cameraOptions[]`), bottom Co-Designer bar, and **Clean Spec Document** (`PROJECT_SPEC.md`) vs **Raw `ROOT_MCP_CONTEXT.md`** view across `§01`–`§05` (`v0.1` Prototype Epics only in `§05`). Clicking **`Approve & Launch Unreal Workbench →`** seeds `v0.1` and enters **`2. Epic Specs`**.
  2. **Stage 2 — Epic Specs Workbench (`2. Epic Specs` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart), [`lib/models/epic_spec.dart`](lib/models/epic_spec.dart), & [`lib/utils/unreal_mcp_payload_builder.dart`](lib/utils/unreal_mcp_payload_builder.dart))**:
     - **2-View Inspector**: Recessed Left Outliner Rail (Epics `E01`, `E02`, ...) paired with **Clean Epic Spec** (`§01 System Intent & Actor Links`, `§02 Controls`, `§03 State Flow & Interrupt Rules`, `§04 Spatial & Exposed Tuning (1 UU = 1 cm)`, `§05 Viewport, UMG & Audio Cues`, `§06 Test Level Staging & PIE Acceptance Gate`) and **Exact Unreal MCP Payload**.
     - **Live Tuning & PIE Loop**: Editing `§04` tuning values updates the Unreal MCP payload immediately; flagging a `[FIX]` switches the payload from `FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK` to `FOCUSED PIE REVISION PASS`; resolving fixes and clicking `Pass Epic ✓` advances to the next Epic (`reopenEpic` restores it if needed).
     - **Progressive AI Releases (`v0.1` → `v0.2` → `v0.3+` via [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))**: Clicking **`+ New Release`** opens the Progressive Release Co-Pilot with AI direction presets, `[UPGRADE]` delta checkboxes on baseline Epics, `[NEW]` candidate Epics, and non-destructive baseline preservation (`EpicLifecycle.stable`, `upgrading`, `newEpic`, `active`, `passed`).
  3. **Pure-Python `LayersBridge` Unreal Editor Plugin ([`unreal_plugin/LayersBridge/`](unreal_plugin/LayersBridge/LayersBridge.uplugin), `v1.0.0`, packaged as [`web/layers_unreal_plugin.zip`](web/layers_unreal_plugin.zip))**:
     - **Division of Labor**: Web Studio owns **Project Spec, Release Planning & Epic Design**; `LayersBridge` inside Unreal Editor owns **live `.uproject` inspection, Unreal MCP toolset exposure, and PIE verification sync**.
     - **Modules**: `LayersBridge.uplugin`, [`init_unreal.py`](unreal_plugin/LayersBridge/Content/Python/init_unreal.py), [`layers_toolset.py`](unreal_plugin/LayersBridge/Content/Python/layers_toolset.py) (`LayersToolset` registering `layers_get_active_epic_spec`, `layers_log_pie_fix`, `layers_resolve_pie_fix`, `layers_pass_active_epic` inside Epic's `ModelContextProtocol` on `http://127.0.0.1:8000/mcp`), [`layers_sync_client.py`](unreal_plugin/LayersBridge/Content/Python/layers_sync_client.py), [`layers_project_probe.py`](unreal_plugin/LayersBridge/Content/Python/layers_project_probe.py), and [`layers_pie_dock.py`](unreal_plugin/LayersBridge/Content/Python/layers_pie_dock.py).
     - **2-Way Cloud Functions Sync ([`functions/index.js`](functions/index.js) & [`firestore.rules`](firestore.rules))**: Token provisioning (`/unrealLink/token`), live `.uproject` snapshot injection & active Epic MCP payload pull (`/unrealLink/epic`), and PIE check / tuning / `[FIX]` / Pass / Reopen push (`/unrealLink/update`) via `lyr_...` tokens stored server-only in `unreal_links`.

## 1. Composable `Auto-Goal`, `Auto-Grill`, and 2-Step `Auto GG` Workflows
- **Standalone Continuous `Auto-Goal` (`/auto-goal [focus]`)**:
  - Launches [`.agents/skills/auto-goal/SKILL.md`](.agents/skills/auto-goal/SKILL.md) + [`.agents/hooks/auto_gg_hook.py`](.agents/hooks/auto_gg_hook.py) (`mode: "goal"`).
  - Runs [`discover_signals.py`](.agents/skills/auto-goal/scripts/discover_signals.py), auto-locks the `#1` safest high-impact 3-part Goal Contract without pitching alternatives, calls `ask_question` *only* if a real UX fork exists, runs `Red → ./scripts/verify_loop.sh → Commit`, and calls `enter_plan_mode(reason='[round-complete] ...')` to loop continuously until told `stop`.
- **Standalone Targeted `Auto-Grill` (`/auto-grill <target>`)**:
  - Launches [`.agents/skills/auto-grill/SKILL.md`](.agents/skills/auto-grill/SKILL.md) (`mode: "grill"`).
  - Skips `discover_signals.py`, inspects affected files directly, asks `1–3` high-signal UX/scope questions via `ask_question` (`(Recommended)` first, or skips if zero UX ambiguity), locks the Goal Contract, executes & verifies once, and stops cleanly.
- **Automated 2-Step `Auto GG` Continuous Loop (`/auto-gg [focus]` or `"Auto GG"`)**:
  - Launches [`.agents/skills/auto-gg/SKILL.md`](.agents/skills/auto-gg/SKILL.md) (`mode: "gg"`), composing `Auto-Goal` then `Auto-Grill`: **Step 1** (`select_goal`) runs [`discover_signals.py`](.agents/skills/auto-goal/scripts/discover_signals.py) and asks **1 Goal Choice question**; **Step 2** (`grill_chosen`) applies `Auto-Grill` strictly to the chosen goal (skipping if zero UX forks); then executes, verifies, commits, and advances via `[round-complete]` until canceled or told `stop` / `pause`.
- **Opt-In `SEA` Lens (`/sea` or `"SEA"` — Subtract, Enhance, Add)**:
  - Activate [SKILL.md](.agents/skills/sea/SKILL.md) **only** when `/sea` or `SEA` is explicitly written in the prompt (including `auto gg SEA ...`) to audit, grill, and execute strictly in **Subtract → Enhance → Add** order.
- **Auto-Goal (Self-Derived Goal Contracts — Always On)**:
  - On any symptom report, audit request, or open-ended prompt, inspect the codebase, tests, and headless Unreal/workflow smoke probes (`scripts/unreal_plugin_smoke.py`, `scripts/workflow_hook_smoke.py`) first to derive a concrete **Goal Contract** (`Goal`, `In Scope`, and machine-verifiable `Done When` checks).
  - When a prompt is open-ended (e.g., *"audit LAYERS"* or a broad symptom with multiple gaps), automatically select the **#1 highest-impact safe goal** and run its verification loop immediately rather than pausing on a backlog menu.
- **Auto-Grill (Upfront Clarification via `ask_question` — Only on Real UX/Scope Forks)**:
  - Resolve pure engineering, data-structure, and Unreal MCP contract trade-offs internally against the codebase and headless smoke probes—never ask the user technical minutiae.
  - When genuine product, UX, or scope trade-offs exist, ask 1–3 concise multiple-choice questions upfront using `ask_question` (`(Recommended)` option first) before editing.
- **Execution Gate (When to Pause vs. Loop Immediately)**:
  - **Clear / Small-to-Medium Tasks, Bug Fixes & `/goal` Runs**: Once Auto-Grill resolves any ambiguity (or immediately if unambiguous), write/run a failing test or smoke probe first, then iterate autonomously (`Edit → ./scripts/verify_loop.sh → Self-Repair`) to `0` errors without an extra `implementation_plan.md` pause.
  - **Major UI Redesigns & Core Architecture Changes**: Present a concise `implementation_plan.md` (`Goal`, `In Scope`, `Affected Files`, `Done When`) and wait for explicit user approval before editing project code files.
- **External User Game Projects Strictly Read-Only**:
  - External user game projects (such as `/Users/henry/Godot/Projects/*` or external `.uproject` directories) are strictly **read-only** reference fixtures (enforced by `.agents/hooks.json`). Always fix LAYERS's own app/plugin code instead.

## 2. Multi-Stack Verification & Loop Gate
- Run `./scripts/verify_loop.sh` (pass `--fix-zip` if `unreal_plugin/LayersBridge/` changed) before committing.
- Passing requires `0` errors across: `node --check functions/index.js`, `web/layers_unreal_plugin.zip` byte parity, headless Unreal bridge + workflow hook smoke tests (`PYTHONDONTWRITEBYTECODE=1 python3 scripts/unreal_plugin_smoke.py` -> `UNREAL_SMOKE_OK` and `PYTHONDONTWRITEBYTECODE=1 python3 scripts/workflow_hook_smoke.py` -> `WORKFLOW_SMOKE_OK`), `dart analyze`, and `100%` passing `flutter test` (enforced automatically on turn completion by `.agents/hooks.json`).

## 3. Communication Style
- Keep responses concise and focused.
- Create clickable `file:///` links for referenced files and code symbols.

## 4. Pure KISS, DRY, and YAGNI Principles (Codebase & App)

### 1. KISS (Keep It Simple & Playable)
- **Codebase**: Write the simplest, most direct working Flutter code. Avoid complex state machines, micro-factories, or multi-step prompt pipelines when simple Provider mixins and single-pass prompts work.
- **App & AI**:
  - **The Playtest Rule**: If a player or QA tester cannot see, hear, or feel it on screen in PIE during gameplay, rephrase it into an observable deliverable.
  - **Cohesive High-Level Epics**: Group controls, state flow, spatial tuning (`1 UU = 1 cm`), visual/audio cues, and PIE acceptance checks into single Epic Spec documents. Do NOT split Epics into artificial `Feature` tickets or implementation micro-steps—Unreal MCP owns asset/Blueprint/Verse synthesis.
  - **Plain Functional Titles (No Thematic / Lore Wording)**: Keep Epic titles short and literal (2–5 plain everyday game-dev words). Name the actual gameplay system (e.g., *Player Mech Movement & Claw Dash*, *Claw Shotgun & Hitstop*) — NEVER use flowery, archaic, or roleplay/lore words (e.g., *Homestead Husbandry*, *Expedition Prep*, *Adrenaline Crop Buffs*).
  - **Design Pillars vs. Trade-Offs**:
    - **Design Pillars (3–4 statements)**: Name the core experiences the game must create and how it should make the player feel—NOT how it is built, NOT a feature (*"has a skill tree"*), and NOT a genre (*"a roguelike"*), but the experience those things exist to hold up (*"Every dash commits"*).
    - **Trade-Offs (2–3 `<prefer> OVER <avoid>` rules)**: Practical engineering/design boundaries used to resolve conflicts (e.g., *`Snappy Arcade Response OVER Momentum Simulation`*).

### 2. DRY (Don't Repeat Yourself / Single Source of Truth)
- **Codebase**:
  - Centralize shared tokens (theme, tier colors, prompts, `UnrealSpecGuard`, `UnrealMcpPayloadBuilder`).
  - **Rule of Three**: Only create shared abstractions after writing the exact same logic three times.
- **App & AI**:
  - **Single Source of Truth (Evolving Live Release Tree)**: Every permanent mechanic lives under a single `Project -> Release -> Epic` lineage across `v0.1` → `v0.2` → `v1.0+`, carrying stable baselines and accumulating `+Delta` upgrades without duplicating cards across releases.
  - **Automatic Rollups**: PIE check progress, open `[FIX]` counts, and Unreal MCP execution mode (`FULL-EPIC AUTONOMOUS BUILD` vs `FOCUSED PIE REVISION PASS`) derive dynamically from the active `EpicSpec` without duplicate manual entry.

### 3. YAGNI (You Aren't Gonna Need It / Scope Discipline)
- **Codebase**: Build strictly what the immediate feature requires today. Strip out hypothetical future-proofing, extra database columns, or unneeded packages before writing code.
- **App & AI**:
  - **Strict `v0.1` Prototype Gate**: Stage 1 `§05` and initial `v0.1` Epics contain *only* playable prototype mechanics; `v0.2+` waves, progression, and meta layers wait for Progressive Releases.
  - **Focus Mode**: Spotlight only 1 active Release and 1 active Epic at a time so Unreal MCP receives crisp, uncluttered context.

## 5. Scope & Goal Formatting Rule
Whenever writing or revising any Scope, Goal, or Objective section (across Epics, PRDs, specs, or design docs), follow these constraints:
- **No Paragraphs**: Never write scope or goals as dense narrative text. Always use this structured 3-part layout:
  - **Goal**: Exactly one plain-English sentence stating what is being built/done and why.
  - **In Scope**: A concise bulleted list of the specific systems, features, or assets included.
  - **Done When**: Clear, practical conditions for when the work is considered complete.
- **Tone**: Write like a practical developer talking to a teammate. Keep it direct, literal, and natural.
- **Non-Thematic / Literal Wording**: Describe mechanics in plain engineering/design terms (e.g., *"Spawn 3 enemy waves across L_Arena_Proto and shatter armor on claw dash"* instead of *"Pit the player against aggressive demon waves in an out-of-town wasteland"*).
- **Banned Jargon & Archaic Words**: Never use corporate filler or vague buzzwords (*leverage*, *unified*, *end-to-end loop*, *staging*, *validate*, *verified*, *deliver*, *synergy*, *seamlessly*) or flowery/archaic lore synonyms (*husbandry*, *homestead*, *expedition*, *ordinance*). State the actual concrete action instead.

## 6. Canonical LAYERS Text Format Style Guide (`STYLE_GUIDE.md` & `lib/constants/text_style_guide.dart`)
- **Single Source of Truth**: Always consult [`STYLE_GUIDE.md`](STYLE_GUIDE.md) and reference [`LayersTextStyleGuide`](lib/constants/text_style_guide.dart) + [`UnrealSpecGuard`](lib/utils/unreal_spec_guard.dart) across Stage 1 and Stage 2 prompts and Gemini tool schemas so AI output emits Unreal-native high-level design specs on the first pass:
  1. **BLUF (`[2–4 Word Payoff] — [Scope]`)**: Used for Stage 1 `pitch` (`§01`) and Progressive Release presets/goals.
  2. **Causal PIE Gate (`[Player Action] -> [Observable PIE Screen Result]`, `<= 14 words`)**: Used for `releaseDoneWhen` (`§05`) and Epic `checks[]` (`§06`).
  3. **Changelog / Delta-Diff (`+Delta`, `5–10 words`)**: Used for Progressive Release `[UPGRADE]` deltas atop locked `v0.1` baselines.
  4. **Unreal Scale & Telegraphic Micro-Labels (`1 UU = 1 cm`)**: Used for Epic titles (`2–5` words), `§02` Camera/Scale/Input contracts, `§04` Hard Scope Cuts (`"No [2–5 word system]"`), and `§04` Spatial & Exposed Tuning (`cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`).

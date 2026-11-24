# Workspace Rules for LAYERS-Agentic (Unreal Engine 5 + Ultimate Engine CoPilot)

## 0. Project Architecture & Context (Quick Onboarding for New Agent Sessions)
- **Repository**: `https://github.com/HenryCGitHub/LAYERS-Agentic`
- **Live Web App (GitHub Pages)**: `https://henrycgithub.github.io/LAYERS-Agentic/`
- **Deploy Command**: Run `./scripts/deploy.sh` from the project root (builds release Flutter Web and pushes `origin/gh-pages`). Only deploy when the user asks.
- **AI Model ([`lib/agents/gemini_agent_client.dart`](lib/agents/gemini_agent_client.dart) & [`lib/providers/workbench_provider.dart`](lib/providers/workbench_provider.dart))**:
  - **Dual-Tier Gemini 4 Routing**:
    - **Architect Planner Model (`Stage 1 Spark` & `Stage 2 + New Release`)**: `gemini-4-argon` (`thinkingLevel: "MEDIUM"` default; automatic failover `gemini-4-argon` → `gemini-4-hydrogen` → `gemini-flash-latest`).
    - **Fast Refine Model (`Stage 1 & Stage 2 Floating AI Refine Dock`)**: `gemini-4-hydrogen` (`thinkingLevel: "LOW"` default; automatic failover → `gemini-flash-latest`).
  - **Active Pricing Rates (per 1M input / output tokens, including reasoning/thinking tokens)**:
    - `gemini-4-argon`: **`$2.00 / $10.00`**
    - `gemini-4-neon`: **`$3.00 / $15.00`**
    - `gemini-4-hydrogen`: **`$1.50 / $7.50`**
  - **Accumulative Session Token Tracker**: Live token tracking badge in the Studio top bar and AI Settings dialog tracking input tokens, output tokens, and accumulative estimated session cost (`USD`) with 1-click reset.
- **Cloud-AI-Backed 2-Stage Unreal Engine 5 (`Blueprint-First` + `C++ & BP Hybrid`) 4-Tier Structured Game Planner (`1. Plan` → `2. Build`)**:
  - **Flight Deck Desktop Workstation Chrome ([`StudioTopBar`](lib/screens/shell/studio_top_bar.dart), `46px`)**: Project Switcher, `1. Plan` | `2. Build` stage pills, **`Link Local GDD`** (`showSaveFilePicker` + IndexedDB handle persistence in [`LocalGddSyncService`](lib/services/local_gdd_sync_service.dart) writing deltas only, with download fallback on non-Chromium browsers), **`⚡ Inspect GDD`** modal ([`showGddInspectorDialog`](lib/screens/shell/gdd_inspector_dialog.dart)), Export menu, Cloud Vault, Model/Token pills, and Theme toggle.
  - **Strict 4-Tier Hierarchy (`Project -> Release -> Epic -> Feature`)**: Designed exclusively for **Unreal Engine 5** (`cm` / `cm/s` scale — never label UI headers with `(1 UU = 1 cm)` or `1 UU` clutter) and **Ultimate Engine CoPilot** handoff prompts inside the Unreal Editor—zero `Task` or `Step` sub-tickets, zero Godot/Unity leakage (`.tscn`, `.tres`, `.gd`, `.prefab`, `res://`, `GDScript`, `InputMap`, `CharacterBody3D`, `@export`, `GameObject`), and zero field overlap between **Epics (Large Domains)** and **Features (30–90 min Playable Slices)**.
  1. **Stage 1 — Project Spec (`1. Plan` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart), [`stage1_spec_document.dart`](lib/screens/stage1/stage1_spec_document.dart), [`stage1_epic_preview_section.dart`](lib/screens/stage1/stage1_epic_preview_section.dart), & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))**:
     - Spark intake (custom prompt or starter presets: `shellbreaker`, `railjack`, `emberkeep`) paired with auto-detected & toggleable `Blueprint-First` / `C++ & BP Hybrid` architecture pills (`stage1_mode_blueprint` / `stage1_mode_cpp_hybrid`), vague-spark clarification forks, camera decision fork (`cameraOptions[]`), bottom [`FloatingAiRefineDock`](lib/screens/workbench/floating_ai_refine_dock.dart) (`patch_unreal_root_spec`) with Undo history & updated section badges, inline editing across Title, `§01` Pitch, `§02` UE5 Contracts, `§03` Pillars & Trade-Offs, `§04` Scope Cuts, and `§05` Feature slices, plus dynamic header CTA (**`Approve & Launch v0.1`** → **`Sync Spec & Return to v0.X`**).
  2. **Stage 2 — Release Workbench (`2. Build` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart), [`epic_domain_sheet.dart`](lib/screens/workbench/epic_domain_sheet.dart), [`feature_spec_sheet.dart`](lib/screens/workbench/feature_spec_sheet.dart), [`workbench_spec_edit_mixin.dart`](lib/providers/workbench_spec_edit_mixin.dart), [`workbench_stage2_refine_mixin.dart`](lib/providers/workbench_stage2_refine_mixin.dart), & [`stage2_refine_agent.dart`](lib/agents/stage2_refine_agent.dart))**:
     - **Expandable Left Outliner + Breadcrumbs + Release Complete Banner**: Expandable `Epic -> Feature` tree with release switcher pills (`v0.1` / `v0.2+` / `+ New Release`), clickable Breadcrumbs (`Project / Release / Epic [/ Feature]`), and emerald `Release Complete` progression banner when every slice passes.
     - **Non-Overlapping Epic Domain Sheet vs. Feature Spec Sheet (Full Inline Edits + Stage 2 AI Dock & Undo)**:
       - **Epic Domain Sheet (`selectedFeatureId == null`)**: `§01 Domain Scope` (`Edit Scope` inline editor), `§02 Shared Blueprint, Level & Class Ownership` (inline `+ Add Owner` / edit / delete), `§03 Shared State & Interrupt Rules` (inline `Edit Rules` updating child prompts live), `§04 Domain Out-of-Scope Cuts` (inline `+ Add Cut` / `✕`), `§05 Child Features` + `+ Add Feature Slice`. Header omits primary `Copy Epic Brief` (displays `Auto-included in F01–F0N prompts — no separate Epic copy needed.`, primary **`Start/Continue F0X →`** CTA, optional Architecture Brief in `⋯`).
       - **Feature Slice Spec Sheet**: Full inline CRUD (zero sliders) across `§01 Feature Scope` (`Edit Scope`), `§02 Input Actions` (`+ Add Input` / edit / delete), `§03 Exposed Tuning` (plain `Key | Value | Unit` rows + `+ Add Variable` / `✕`), `§04 Viewport, UI & Audio Cues` (`+ Add Cue` / `✕`), `§05 Playtest Gate & [FIX] Notes` (`+ Add Check` / `✕`), plus locked `[v0.1]` baseline banner (`Open in v0.1 →`) when viewing prior-shipped slices in `v0.2+`.
       - **Bottom Floating AI Dock**: Unlocked Epics & Features mount [`FloatingAiRefineDock`](lib/screens/workbench/floating_ai_refine_dock.dart) routed through `Stage2RefineAgent` (`patch_unreal_epic_spec` / `patch_unreal_feature_spec` on `gemini-4-hydrogen` `LOW`, with deterministic offline fallback & multi-step Undo).
     - **Ultimate Engine CoPilot Handoff (`copy_copilot_prompt_btn` / `preview_copilot_prompt_btn` / Top Bar `⚡ Inspect GDD`)**:
       - `⚡ Inspect GDD` & `Link Local GDD` inspect/sync heading-indexed `*_copilot_gdd.md` (`UnrealContextBuilder.buildCoPilotGddMarkdown`).
       - Each Feature slice renders **`⚡ Copy CoPilot Prompt`** (or **`🔧 Copy CoPilot [FIX] Prompt (N)`** / **`⚡ Copy CoPilot Delta Prompt`**) emitting compact `@TAG` DSL with self-healing `create missing @OWNERS if absent, else extend existing` execution instructions; `Preview` offers **`Compact DSL | Readable View`** with **`Paste size: ~N tok · -X% vs MD`** (`Compiled locally in memory (0 AI tokens spent by LAYERS)`).
     - **Progressive AI Releases (`v0.1` → `v0.2` → `v0.3+` via [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))**: Clicking **`+ New Release`** opens the Progressive Release Co-Pilot with AI direction presets, `[+DELTA]` upgrade checkboxes targeting existing Features, `[+NEW]` Feature slice checkboxes attached directly inside existing permanent Epics without duplicating cards, and `[NEW]` candidate Epics.
  3. **Cloud Functions Backend ([`functions/index.js`](functions/index.js) & [`firestore.rules`](firestore.rules))**:
     - Pure Web Studio backend providing Gemini API proxy routes (`geminiProxy`), Google Sign-In/Collab invite flows, and Cloud Vault Firestore sync—zero UE5 editor link-token routes (`/godotLink/*` & `/unrealLink/*` are omitted intentionally).

## 1. Goal-Oriented Planning & Autonomous Routing

Work backward from the desired outcome before writing any code. Keep planning concise and execution hands-free unless a real UX or scope fork requires a user decision.

### Phase 1: Goal Contract (Silent Planning)
Before editing files, define a 3-part Goal Contract in your internal plan (using Section 5's Goal / In Scope / Done When format):
1. **End-State Goal:** One plain-English sentence naming the exact user or system outcome.
2. **Measurable Done Criteria:** 2–4 concrete checks proving the goal is met (anchored to `./scripts/verify_loop.sh` plus targeted test, build, or CLI/UI output).
3. **Critical Path & Independence:** Separate tightly coupled edits from independent sub-goals with zero file overlap.

- **Open-Ended Prompts / Audits:** Run `PYTHONDONTWRITEBYTECODE=1 python3 scripts/discover_signals.py [focus]` first to ground the Goal Contract in live repo signals (`leakageHits`, `untestedModules`, `monolithHotspots`, `cloudProxyTest`), and pick the `#1` highest-impact safe target without inventing speculative UI.
- **Clarification Policy (Smart Hands-Off):** Never pause for engineering trivia (helpers, data structures, tests, CoPilot prompt internals). Execute autonomously on bugs, tests, refactors, CI, and clear specs. Ask `1–2` focused multiple-choice questions (`ask_question`, `(Recommended)` first) **only** on genuine unresolved UX or scope forks—or present a concise `implementation_plan.md` before major UI redesigns or core architecture overhauls.

### Phase 2: Hands-Free Execution Routing
Select execution topology from the Goal Contract's dependency graph (using native tools):
- **Single-Thread Default:** Coupled edits—even across 4–8 related Dart files (model + provider + screen)—run sequentially in the main thread (`Red test -> Edit -> ./scripts/verify_loop.sh`).
- **Background Offload (`invoke_subagent` `research`):** Offload broad read-only discovery, multi-file audits (>5 files), or large log triage so noisy output stays out of the main context window.
- **Selective Parallel Swarm (`swarm` tool):** Spawn parallel workers (`workspace: "share"` for authors, `"inherit"` for read-only auditors) **only** when the goal splits into **2+ truly independent tracks with strict non-overlapping file ownership** (e.g., CI/Docs + Tests + Read-Only Audit, or Cloud Functions + Flutter UI + Tests). Always land worker commits onto `main` and pass `./scripts/verify_loop.sh` before killing workers.
- **2-Strike Root-Cause Escalation (`enter_plan_mode`):** If any Done Criterion fails after 2 fix attempts, stop patching blindly—hand back to Plan Mode via `enter_plan_mode` for root-cause diagnosis (and suggest `/boost` to the user when deep multi-perspective redesign is warranted).

### Phase 3: Goal Proof & Handoff
- Code written is not done—a task is complete only when every **Measurable Done Criterion** passes in observed terminal/test output (enforced on dirty code by `.agents/hooks/stop_verify_gate.py` + `./scripts/verify_loop.sh`).
- Conclude with a brief **Goal Summary** mapping each Done Criterion to its observed proof and listing changed files with clickable `file:///` links.
- **External Game Projects Strictly Read-Only:** Enforced by `.agents/hooks/pre_tool_guard.py`. Always fix LAYERS-Agentic workspace code instead.
- **Built-In Modes:** Suggest native Antigravity commands when a special mode fits (`/goal` for long autonomous runs, `/grill-me` for interactive design interviews, `/teamwork` for large parallel projects, `/boost` for deep debugging).

## 2. Multi-Stack Verification & Loop Gate
- Run `./scripts/verify_loop.sh` before committing.
- Passing requires `0` errors across: `node --check functions/index.js`, Cloud Proxy test (`scripts/cloud_proxy_test.py` -> `CLOUD_PROXY_TEST_OK`), workflow hook test (`scripts/workflow_hook_test.py` -> `WORKFLOW_HOOK_TEST_OK`), `dart analyze`, and `100%` passing `flutter test` (enforced automatically on turn completion by `.agents/hooks.json`).

## 3. Communication Style
- Keep responses concise and focused.
- Create clickable `file:///` links for referenced files and code symbols.

## 4. Pure KISS, DRY, and YAGNI Principles (Codebase & App)

### 1. KISS (Keep It Simple & Playable)
- **Codebase**: Write the simplest, most direct working Flutter and Node.js code. Avoid complex state machines, micro-factories, or multi-step prompt pipelines when simple Provider mixins and single-pass prompts work.
- **App & AI**:
  - **The Playtest Rule**: If a player or QA tester cannot see, hear, or feel it on screen in PIE (Play In Editor), rephrase it into a concrete observable output.
  - **Large-Domain Epics -> 30–90 Min Playable Features**: **Epics** hold domain architecture (`goal`, `inScope`, `doneWhen`, `sceneOwnership`, `stateFlow`, `interruptRules`, `outOfScope`) once without duplicating slice inputs or variables; child **Features** hold playable slice contracts (`Enhanced Input` `IA_*`/`IMC_*` bindings, `PascalCase` tuning in `cm`/`cm/s`, visual/audio cues, and Playtest checks). Do NOT generate `Task` tickets or AI step lists.
  - **Plain Functional Titles (No Thematic / Lore Wording)**: Keep Epic & Feature titles short and literal (2–5 plain everyday game-dev words). Name the actual gameplay system (e.g., *Player Movement & Camera*, *Armored Claw Dash*) — NEVER use flowery, archaic, or roleplay/lore words (e.g., *Homestead Husbandry*, *Expedition Prep*, *Adrenaline Crop Buffs*).
  - **Design Pillars vs. Trade-Offs**:
    - **Design Pillars (3–4 statements)**: Name the core experiences the game must create and how it should make the player feel—NOT how it is built, NOT a feature (*"has a skill tree"*), and NOT a genre (*"a roguelike"*), but the experience those things exist to hold up (*"Every dash commits"*).
    - **Trade-Offs (2–3 `<prefer> OVER <avoid>` rules)**: Practical engineering/design boundaries used to resolve conflicts (e.g., *`Snappy Arcade Response OVER Momentum Simulation`*).

### 2. DRY (Don't Repeat Yourself / Single Source of Truth)
- **Codebase**:
  - Centralize shared tokens (theme, tier colors, prompts, [`UnrealSpecGuard`](lib/utils/unreal_spec_guard.dart), [`UnrealContextBuilder`](lib/utils/unreal_context_builder.dart)).
  - **Rule of Three**: Only create shared abstractions after writing the exact same logic three times.
- **App & AI**:
  - **Single Source of Truth (Evolving Live Release Tree)**: Every permanent mechanic lives under a single `Project -> Release -> Epic -> Feature` lineage across `v0.1` → `v0.2` → `v1.0+`, carrying locked `[v0.1]` baselines and attaching `[+NEW]` Features and `[+DELTA]` upgrades inside existing permanent Epics without duplicating cards across releases.
  - **Automatic Rollups**: Epic Feature passed/total counts (`passed/total`), open `[FIX]` counts, and execution mode (`FULL FEATURE SLICE` vs `FOCUSED [FIX] PASS`) derive dynamically from child `FeatureSpec` lists without duplicate manual entry.

### 3. YAGNI (You Aren't Gonna Need It / Scope Discipline)
- **Codebase**: Build strictly what the immediate feature requires today. Strip out hypothetical future-proofing, extra database columns, or unneeded packages before writing code.
- **App & AI**:
  - **Strict `v0.1` Prototype Gate**: Stage 1 `§05` and initial `v0.1` Epics/Features contain *only* playable prototype mechanics; `v0.2+` waves, progression, and meta layers wait for Progressive Releases.
  - **Focus Mode**: Spotlight only 1 active Release and 1 active Epic or Feature slice at a time so Web Studio and CoPilot prompts stay crisp and focused.

## 5. Scope & Goal Formatting Rule
Whenever writing or revising any Scope, Goal, or Objective section (across Epics, PRDs, specs, or design docs), follow these constraints:
- **No Paragraphs**: Never write scope or goals as dense narrative text. Always use this structured 3-part layout:
  - **Goal**: Exactly one plain-English sentence stating what is being built/done and why.
  - **In Scope**: A concise bulleted list of the specific systems, features, or assets included.
  - **Done When**: Clear, practical conditions for when the work is considered complete.
- **Tone**: Write like a practical developer talking to a teammate. Keep it direct, literal, and natural.
- **Non-Thematic / Literal Wording**: Describe mechanics in plain engineering/design terms (e.g., *"Spawn 3 enemy waves in `/Game/Maps/Lvl_ArenaProto.umap` and break shell armor on claw dash"* instead of *"Pit the player against aggressive demon waves in an out-of-town wasteland"*).
- **Banned Jargon & Archaic Words**: Never use corporate filler or vague buzzwords (*leverage*, *unified*, *end-to-end loop*, *staging*, *validate*, *verified*, *deliver*, *synergy*, *seamlessly*) or flowery/archaic lore synonyms (*husbandry*, *homestead*, *expedition*, *ordinance*). State the actual concrete action instead.

## 6. Canonical LAYERS Text Format Style Guide (`STYLE_GUIDE.md` & `lib/constants/text_style_guide.dart`)
- **Single Source of Truth**: Always consult [`STYLE_GUIDE.md`](STYLE_GUIDE.md) and reference [`LayersTextStyleGuide`](lib/constants/text_style_guide.dart) + [`UnrealSpecGuard`](lib/utils/unreal_spec_guard.dart) across Stage 1 and Stage 2 prompts and Gemini tool schemas so AI output emits Unreal-native high-level design specs on the first pass:
  1. **BLUF (`[2–4 Word Payoff] — [Scope]`)**: Used for Stage 1 `pitch` (`§01`) and Progressive Release presets/goals.
  2. **Causal Playtest Gate (`[Player Action] -> [Observable Viewport Result]`, `<= 14 words`)**: Used for `releaseDoneWhen` (`§05`) and Feature Playtest `checks[]` (`§05`).
  3. **Changelog / Delta-Diff (`+Delta`, `5–10 words`)**: Used for Progressive Release `[+DELTA]` upgrades atop locked `v0.1` baselines and `[+NEW]` Feature slices.
  4. **Unreal 5 Scale & Telegraphic Micro-Labels**: Used for Epic/Feature titles (`2–5` words), `§02` Camera/Scale/Input contracts, `§04` Hard Scope Cuts (`"No [2–5 word system]"`), and Feature `§03` Exposed Tuning (`PascalCase` variables in `cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`).

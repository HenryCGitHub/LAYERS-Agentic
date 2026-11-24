# LAYERS-Agentic

An Unreal Engine 5 **Flight Deck Web Studio** built with Flutter for structured **2-Stage Game Planning** (`1. Plan` -> `2. Build`) and token-efficient **Ultimate Engine CoPilot** `@TAG` handoff prompts.

- **Live Web App**: [https://henrycgithub.github.io/LAYERS-Agentic/](https://henrycgithub.github.io/LAYERS-Agentic/)
- **GitHub Repository**: [https://github.com/HenryCGitHub/LAYERS-Agentic](https://github.com/HenryCGitHub/LAYERS-Agentic)
- **Spec Formatting Rules**: [`STYLE_GUIDE.md`](STYLE_GUIDE.md)

## Dual-Tier Gemini 4 Models ([`gemini_agent_client.dart`](lib/agents/gemini_agent_client.dart))

- **Architect Planner (`gemini-4-argon` · `MEDIUM` thinking)**: Drafts initial Unreal Engine 5 root specs and `v0.1` Epics from Stage 1 Spark prompts ([`project_concept_agent.dart`](lib/agents/project_concept_agent.dart)) and plans Stage 2 Progressive Releases (`v0.2+`, [`release_planner_agent.dart`](lib/agents/release_planner_agent.dart)), with automatic failover (`gemini-4-argon` -> `gemini-4-hydrogen` -> `gemini-flash-latest`).
- **Fast Refine Dock (`gemini-4-hydrogen` · `LOW` thinking)**: Powers surgical JSON patches in the bottom [`FloatingAiRefineDock`](lib/screens/workbench/floating_ai_refine_dock.dart) across both Stage 1 (`patch_unreal_root_spec`) and Stage 2 Epics/Features (`patch_unreal_epic_spec`, `patch_unreal_feature_spec` in [`stage2_refine_agent.dart`](lib/agents/stage2_refine_agent.dart)), with automatic failover to `gemini-flash-latest`.
- **Session Token Tracker & Cloud Proxy ([`functions/index.js`](functions/index.js))**: Live top-bar token and estimated USD cost badge supporting local Gemini API keys in AI Settings or signed-in Google proxy routing via `geminiProxy`.

## Flight Deck Top Bar ([`studio_top_bar.dart`](lib/screens/shell/studio_top_bar.dart))

- **Project, Release & Stage Navigation**: Project switcher (`+ New Project`, rename, duplicate, delete, `.json` export/import), release switcher (`v0.1` / `v0.2+`), and `1. Plan` | `2. Build` stage pills.
- **`Link Local GDD` ([`local_gdd_sync_service.dart`](lib/services/local_gdd_sync_service.dart))**: Binds `*_copilot_gdd.md` to disk via the browser File System Access API (`showSaveFilePicker` + IndexedDB handle persistence) and auto-writes deltas only, falling back to download on non-Chromium browsers.
- **`Inspect GDD` ([`gdd_inspector_dialog.dart`](lib/screens/shell/gdd_inspector_dialog.dart))**: Opens the heading-indexed `*_copilot_gdd.md` inspector modal (`⚡ Inspect GDD`) with live sync status, token count, copy, and download controls.
- **Export, Cloud Vault & Theme**: Export menu (`Export CoPilot GDD (.md)`, `Copy Full Project Spec (.md)`, `.layers.json` backup export/import), Cloud Vault sync, AI Settings, and Light/Dark theme toggle.

## 2-Stage Unreal Engine 5 Planner (`Project -> Release -> Epic -> Feature`)

Built strictly for **Unreal Engine 5** (`Blueprint-First` and `C++ & BP Hybrid`, using `cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, and `bool` units via [`unreal_spec_guard.dart`](lib/utils/unreal_spec_guard.dart)) with zero `Task` or `Step` sub-tickets.

1. **Stage 1 — `1. Plan` Project Spec ([`project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart), [`stage1_spec_document.dart`](lib/screens/stage1/stage1_spec_document.dart))**:
   - Start from a custom Spark or starter preset (`shellbreaker`, `railjack`, `emberkeep`), toggle `Blueprint-First` vs `C++ & BP Hybrid`, and answer any vague-spark or camera choices.
   - Edit Title and `§01–§05` directly inline (Vision & 30s Loop, Global UE5 Contracts, Pillars & Trade-Offs, Hard Scope Cuts, and seeded `v0.1` Epics & Features) or patch sections via the bottom AI Refine Dock with Undo history, then launch `v0.1`.
2. **Stage 2 — `2. Build` Release Workbench ([`release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart))**:
   - **Outliner & Breadcrumbs**: Expandable `Epic -> Feature` tree, release switcher, clickable breadcrumbs, and `Release Complete` progression banner when every slice passes.
   - **Epic Domain Sheet ([`epic_domain_sheet.dart`](lib/screens/workbench/epic_domain_sheet.dart))**: Direct inline editing across `§01 Domain Scope`, `§02 Shared Blueprint, Level & Class Ownership` (`/Game/...` assets or `Source/` C++ classes), `§03 Shared State & Interrupt Rules`, `§04 Domain Out-of-Scope Cuts`, and `§05 Child Features` (`+ Add Feature Slice`), plus bottom AI Refine Dock and Undo history.
   - **Feature Slice Spec Sheet ([`feature_spec_sheet.dart`](lib/screens/workbench/feature_spec_sheet.dart))**: Full direct inline manual editing (zero sliders) across `§01 Feature Scope`, `§02 Input Actions` (`Enhanced Input` `IA_*` / `IMC_*`), `§03 Exposed Tuning` (`Key | Value | Unit` rows), `§04 Viewport, UI & Audio Cues`, and `§05 Playtest Gate & [FIX] Notes`, plus bottom AI Refine Dock and multi-step Undo history ([`workbench_spec_edit_mixin.dart`](lib/providers/workbench_spec_edit_mixin.dart), [`workbench_stage2_refine_mixin.dart`](lib/providers/workbench_stage2_refine_mixin.dart)). Unmodified prior-release slices display a locked `[v0.1]` baseline banner.
   - **Ultimate Engine CoPilot `@TAG` Handoff Prompts ([`unreal_context_builder.dart`](lib/utils/unreal_context_builder.dart), [`unreal_prompt_compactor.dart`](lib/utils/unreal_prompt_compactor.dart))**: Every Feature slice compiles a self-healing `@TAG` prompt (`@PROJECT`, `@EPIC`, `@OWNERS`, `@STATES`, `@SIBLINGS`, `@CUTS`, `@SLICE`, `@INPUT`, `@VARS`, `@CUES`, `@PIE_GATE`, `@EXEC`) in `BUILD`, `DELTA`, or `FIX` mode, with a local `Preview` toggle (`Compact DSL | Readable View`, `0` AI tokens spent by LAYERS).
   - **Progressive Releases (`v0.1` -> `v0.2+`, [`progressive_release_modal.dart`](lib/screens/workbench/progressive_release_modal.dart))**: `+ New Release` generates direction presets, `[+DELTA]` Feature upgrades, `[+NEW]` Feature slices attached inside existing permanent Epics without duplicating cards, and `[NEW]` candidate Epics.

## Commands

- **Run Full Multi-Stack Check**: `./scripts/verify_loop.sh`
- **Run Static Analysis & Flutter Tests**: `dart analyze && flutter test`
- **Deploy to GitHub Pages (`gh-pages`)**: `./scripts/deploy.sh`

# LAYERS Godot 4 Spec Style Guide (Source-First, Zero 2-Step Token Waste)

> **Golden Rule (Source-First Generation)**: Every Stage 1 and Stage 2 AI prompt and Gemini tool schema references [`lib/constants/text_style_guide.dart`](lib/constants/text_style_guide.dart) (`LayersTextStyleGuide`) and passes sanitization through [`GodotSpecGuard`](lib/utils/godot_spec_guard.dart) so Gemini emits exact Godot 4 high-level design specs on the first pass (`Project -> Release -> Epic -> Feature`, `3D: 1 unit = 1 m` | `2D: px`).
>
> **Strict Zero-Overlap Boundary**:
> - **Epics (Large Domains)** own cross-slice `Goal` / `In Scope` / `Done When`, `sceneOwnership` (`res://` paths + roles), `stateFlow`, `interruptRules`, `outOfScope` cuts, and child Feature slices (`F01–F0N`).
> - **Features (30–90 min Playable Slices)** own `InputMap` bindings, live GDScript `@export` tuning variables (`m`/`px`), viewport/UI/audio cues, Playtest Gate checkboxes, `[FIX]` revisions, and 1-click **Godot 4 Cloud AI** builds (`v4.2.0` `multi_turn_v1` 6-turn read-only discovery, targeted `.gd` patches, automatic instanced-scene/custom-asset/collision protection on build, and up to `3x` auto-repair).
> - Never emit implementation micro-steps, `Task`/`Step` tickets, file trees, or non-Godot engine terms (`.uasset`, `.uproject`, `Blueprint`, `ACharacter`, `UMG`, `GameObject`, `Prefab`, `cm/s`).

---

## 1. The 4 Canonical Text Styles

| # | Style Name | Formula | Max Length | Where Used | Canonical Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **BLUF (Bottom Line Up Front)** | **`[2–4 Word Payoff] — [Compact Godot 4 Scope]`** | `<= 14 words` | • Stage 1 `pitch` (`§01 Core Fantasy & 30s Loop`)<br>• Stage 2 Progressive Release Co-Pilot presets & goals | `Claw Arena Skirmisher — Top-down 3D crab mech dash-shooter across 3 arena waves.` |
| **2** | **Causal Playtest Gate (`Trigger -> Result`)** | **`[Player Action] -> [Observable Viewport Result]`** | `<= 14 words` | • Stage 1 `releaseDoneWhen` (`§05`)<br>• Stage 2 Feature `checks[]` (`§05 Playtest Gate & [FIX] Notes`) | `Press Space dash into guard -> Shield shatters + thruster flash plays in viewport` |
| **3** | **Changelog / Delta-Diff (`+Delta`)** | **`+mechanic delta`** *(Upgrades)*<br>**`Direct noun summary`** *(New)* | `5–10 words` | • Progressive Release Co-Pilot `[+DELTA]` & `[+NEW]` checkboxes<br>• Feature `releaseDelta` & Epic `upgradeDeltas[]` atop locked `v0.1` baseline | `+55ms Hit-Stop freeze & radial shockwave ring` |
| **4** | **Godot 4 Scale & Telegraphic Micro-Labels** | **`2–5 Title-Case Words`** / **`snake_case: Value unit`** (`3D: m` \| `2D: px`) | `2–6 words` | • Epic & Feature titles (`E0# · Title`, `F0# · Title`)<br>• `§02` Camera/Scale/Input contracts & `res://` ownership<br>• Feature `§03 Exposed Tuning (@export GDScript Vars)`<br>• `§04` Hard Scope Cuts (`"No [2–5 word system]"`) | • **Epic**: `Player Movement & Camera`<br>• **Feature**: `Armored Claw Dash`<br>• **Scale**: `dash_impulse: 18.5 m/s`<br>• **Cut**: `No main menu or save slots` |

---

## 2. Surface-by-Surface Mapping (Stage 1 & Stage 2)

### A. Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))
Displays the Clean Spec Document (`PROJECT_SPEC.md`) with a `3D (m, m/s)` / `2D (px, px/s)` dimension toggle and full `.md` export in the top `Export ▾` menu:

| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Core Fantasy & 30s Loop** | `pitch`, `coreLoop[]` | **1. BLUF** + Verb Beats | `1` plain pitch sentence + `2–4` chronological `"Verb -> Result"` beats | `Move & Aim -> Burst Fire -> Claw Dash -> Wave Reset` |
| **`§02` Global Godot 4 Scale & Architecture** | `cameraOptions[]`, `cameraContract`, `characterScale`, `inputContract`, `assetPolicy` | **4. Godot 4 Contract** | Concrete Godot 4 nodes + `m` / `m/s` (3D) or `px` / `px/s` (2D) + `deg` units | `SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, smoothing 9.0` |
| **`§03` Design Pillars & Conflict Trade-Offs** | `pillars[]`, `tradeOffs[]` | **1. BLUF Pillar** + **`OVER` Rule** | `"Pillar Name: experiential reason"` + `<prefer> OVER <avoid>` | `Snappy Arcade Response OVER Momentum Simulation` |
| **`§04` Hard Scope Cuts (Do Not Build)** | `outOfScope[]` | **4. Micro-Label Cut** | Always starts with `"No [2–5 word system]"` | `No main menu or save slots` |
| **`§05` Seeded Epics & Initial `v0.1` Feature Slices** | `releaseDoneWhen`, `initialEpics[]`, `features[]` | **2. Causal Playtest Gate** + Domain/Slice Preview | Strictly `v0.1` Epics holding `2–3` initial `F0#` slices (zero `v0.2+` bloat); `releaseDoneWhen` uses `Trigger -> Result` | `E01 · Player Movement & Camera (F01, F02)` |

---

### B. Stage 2 — Progressive Release Co-Pilot (`+ New Release` in [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))

| Surface | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Direction Presets** | `presets[]` | **1. BLUF** | `2–4` word preset label + crisp release focus goal | `Combat Juice Pass` |
| **Feature Delta Upgrades** | `upgradesByLineageKey` (`targetFeatureCode`) | **3. Changelog `+Delta`** | `[+DELTA F0#] +mechanic delta` attached directly to an existing Feature slice | `[+DELTA F02] +55ms hitstop freeze & shockwave ring` |
| **New Child Feature Slices** | `candidateNewFeaturesByLineageKey` | **3. Changelog `+NEW`** | `[+v0.2 NEW F0#] Title` attached directly inside an existing permanent Epic without duplicating cards | `[+v0.2 NEW F07] Chain Dash on Shell Break` |
| **New Domain Epics** | `candidateNewEpics[]` | **4. Micro-Label** + Slices | `[NEW] E0# · Title` + concise 1-sentence goal & child Feature slices | `[NEW] E04 · Wave Escalation & Arena Reset` |
| **Unmodified Baseline** | `isLockedBaselineInRelease` | **Lock Badge** | Prior-release Features without deltas stay read-only (`v0.1 ✓ BASELINE LOCKED`) | `F01 · 8-Way Walk & Iso Camera [v0.1 ✓]` |

---

### C. Stage 2 — Release Workbench (`2. Release Workbench` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart)) & Godot 4 Dock ([`godot_plugin/addons/layers/`](godot_plugin/addons/layers/plugin.cfg))

#### Epic Domain Sheet (`selectedFeatureId == null` -> `GodotContextBuilder.buildEpicArchitectureContext`)
| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Domain Scope** | `goal`, `inScope[]`, `doneWhen[]` | **1. BLUF** + Structured 3-Part | 1-sentence Domain Goal + concise bullets (zero duplicated Feature inputs/vars) | `Goal: Own mech planar locomotion & dash commitments.` |
| **`§02` Shared Scene & Script Ownership** | `sceneOwnership[]` (`path`, `role`) | **4. `res://` Contract** | Authoritative `.tscn` / `.gd` paths & responsibilities owned by this Epic | `res://scripts/player_mech.gd — Movement state & @export physics` |
| **`§03` Shared State & Interrupt Rules** | `stateFlow[]`, `interruptRules[]` | **4. State Transition** | Cross-slice state graph + interrupt precedence | `Idle -> Walk -> ClawDash -> Recover` |
| **`§04` Domain Out-of-Scope Cuts** | `outOfScope[]` | **4. Micro-Label Cut** | Explicit `"No ..."` boundaries for the Epic domain | `No wall jumping or ledge vaulting` |
| **`§05` Child Features** | `features[]`, `+ Add Feature Slice` | **Rollup Cards** | Live `passed/total` Feature rollups + inline creation of new slices | `F02 · Armored Claw Dash (60 min)` |

#### Feature Slice Spec Sheet (`selectedFeatureId != null` -> synced to Godot 4 Cloud AI `v4.2.0` `multi_turn_v1` via `functions/index.js`)
| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Feature Scope** | `goal`, `inScope[]`, `doneWhen[]`, `releaseDelta` | **1. BLUF** + Delta Banner | Playable `30–90 min` slice scope + link to parent Epic | `Goal: Launch a 5.5 m forward dash on 1.1 s cooldown.` |
| **`§02` Input Actions (`InputMap`)** | `controls[]` (`action`, `trigger`, `rule`) | **4. Godot Control Rule** | `snake_case` `project.godot` InputMap action + binding + unit-bound rule | `claw_dash \| Just Pressed (Space) \| Launch 5.5 m over 0.16s` |
| **`§03` Exposed Tuning (`@export`)** | `tuning[]` (`key`, `value`, `unit`) | **4. Live Tuning Input** | `snake_case` `@export` var + canonical Godot unit (`m`, `m/s`, `px`, `px/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`) | `dash_distance: 5.5 m` |
| **`§04` Viewport, UI & Audio Cues** | `cues[]` | **1. Observable Cue** | Camera punch, GPUParticles/StandardMaterial3D flash, Control HUD arc, or audio cue | `Orange emissive thruster ribbon fires for 0.16 s` |
| **`§05` Playtest Gate & `[FIX]` Notes** | `checks[]`, `releaseDeltaChecks[]`, `fixes[]`, `status` | **2. Causal Playtest Gate** + **`[FIX]`** | Interactive Playtest checks + live `Flag [FIX]` switching Godot 4 Dock & Cloud AI between `⚡ Build F0#` and `🔧 Fix F0#` | `Press Space -> Mech crosses 5.5 m cleanly` |

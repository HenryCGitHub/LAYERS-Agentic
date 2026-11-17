# LAYERS Godot 4 Spec Style Guide (Source-First, Zero 2-Step Token Waste)

> **Golden Rule (Source-First Generation)**: Every Stage 1 and Stage 2 AI prompt and Gemini tool schema must reference [`lib/constants/text_style_guide.dart`](lib/constants/text_style_guide.dart) (`LayersTextStyleGuide`) and pass validation via [`GodotSpecGuard`](lib/utils/godot_spec_guard.dart) so Gemini emits exact Godot 4 high-level design specs on the first pass (`Project -> Release -> Epic`, `3D: 1 unit = 1 m` | `2D: px`).
>
> **Strict High-Level Boundary**: Never emit implementation micro-steps, file trees, `Feature`/`Task` sub-tickets, or non-Godot engine terms (`.uasset`, `.uproject`, `Blueprint`, `ACharacter`, `UMG`, `GameObject`, `Prefab`, `cm/s`).

---

## 1. The 4 Canonical Text Styles

| # | Style Name | Formula | Max Length | Where Used | Canonical Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **BLUF (Bottom Line Up Front)** | **`[2–4 Word Payoff] — [Compact Godot 4 Scope]`** | `<= 14 words` | • Stage 1 `pitch` (`§01 Core Fantasy & 30s Loop`)<br>• Stage 2 Progressive Release Co-Pilot presets & goals | `Claw Arena Skirmisher — Top-down 3D crab mech dash-shooter across 3 arena waves.` |
| **2** | **Causal Playtest Gate (`Trigger -> Result`)** | **`[Player Action] -> [Observable Viewport Result]`** | `<= 14 words` | • Stage 1 `releaseDoneWhen` (`§05`)<br>• Stage 2 Epic `checks[]` (`§06 Test Scene Staging & Playtest Acceptance Gate`) | `Press Space dash into guard -> Shield shatters + thruster flash plays in viewport` |
| **3** | **Changelog / Delta-Diff (`+Delta`)** | **`+mechanic delta`** *(Upgrades)*<br>**`Direct noun summary`** *(New)* | `5–10 words` | • Progressive Release Co-Pilot `[UPGRADE]` checkboxes & `[NEW]` cards<br>• Epic `upgradeDeltas[]` atop locked `v0.1` baseline | `+55ms Hit-Stop freeze & radial shockwave ring` |
| **4** | **Godot 4 Scale & Telegraphic Micro-Labels** | **`2–5 Title-Case Words`** / **`snake_case: Value unit`** (`3D: m` \| `2D: px`) | `2–6 words` | • Epic titles (`E0# · Title`)<br>• `§02` Camera/Scale/Input contracts<br>• `§04 Spatial & Exposed Tuning (@export GDScript Var)`<br>• `§04` Hard Scope Cuts (`"No [2–5 word system]"`) | • **Epic**: `Player Mech Movement & Claw Dash`<br>• **Scale**: `dash_impulse: 18.5 m/s`<br>• **Cut**: `No main menu or save slots` |

---

## 2. Surface-by-Surface Mapping (Stage 1 & Stage 2)

### A. Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))
Toggleable between **Clean Spec Document** (`PROJECT_SPEC.md`) and **Raw `ROOT_GODOT_CONTEXT.md`** (rendered by [`GodotContextBuilder.buildRootGodotContext`](lib/utils/godot_context_builder.dart)), plus a `3D (m, m/s)` / `2D (px, px/s)` dimension toggle:

| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Core Fantasy & 30s Loop** | `pitch`, `coreLoop[]` | **1. BLUF** + Verb Beats | `1` plain pitch sentence + `2–4` chronological `"Verb -> Result"` beats | `Move & Aim -> Burst Fire -> Claw Dash -> Wave Reset` |
| **`§02` Global Godot 4 Scale & Architecture** | `cameraOptions[]`, `cameraContract`, `characterScale`, `inputContract`, `assetPolicy` | **4. Godot 4 Contract** | Concrete Godot 4 nodes + `m` / `m/s` (3D) or `px` / `px/s` (2D) + `deg` units | `SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, smoothing 9.0` |
| **`§03` Design Pillars & Conflict Trade-Offs** | `pillars[]`, `tradeOffs[]` | **1. BLUF Pillar** + **`OVER` Rule** | `"Pillar Name: experiential reason"` + `<prefer> OVER <avoid>` | `Snappy Arcade Response OVER Momentum Simulation` |
| **`§04` Hard Scope Cuts (Do Not Build)** | `outOfScope[]` | **4. Micro-Label Cut** | Always starts with `"No [2–5 word system]"` | `No main menu or save slots` |
| **`§05` Initial Release (`v0.1` Prototype Epics Only)** | `releaseDoneWhen`, `initialEpics[]` | **2. Causal Playtest Gate** + Epic Cards | Strictly `v0.1` Epics (zero `v0.2+` bloat); `releaseDoneWhen` uses `Trigger -> Result` | `E01 · v0.1 — Player Mech Movement & Claw Dash` |

---

### B. Stage 2 — Progressive Release Co-Pilot (`+ New Release v0.X ✦` in [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))

| Surface | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Direction Presets** | `presets[]` | **1. BLUF** | `2–4` word preset label + crisp release focus goal | `Wave Escalation & Armor Break` |
| **Baseline Evolution** | `upgradesByLineageKey` | **3. Changelog `+Delta`** | `[UPGRADE] +mechanic delta` attached to existing `v0.1` Epics | `[UPGRADE] +Enemy stagger buildup & shield crack particles` |
| **New Scope Candidates** | `candidateNewEpics[]` | **4. Micro-Label** + Summary | `[NEW] E0# · Title` + concise 1-sentence goal | `[NEW] E04 · Arena Hazard Vents` |
| **Unmodified Baseline** | `baselineEpics` | **Lock Badge** | Carried untouched as `Baseline ✓` (`EpicLifecycle.stable`) | `E01 · Player Mech Movement & Claw Dash [Baseline ✓]` |

---

### C. Stage 2 — Epic Specs (`2. Epic Specs` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart)) & Godot 4 Dock ([`godot_plugin/addons/layers/`](godot_plugin/addons/layers/plugin.cfg))
Strictly 3-tier hierarchy (`Project -> Release -> Epic`). Toggleable between **Clean Epic Spec** and **Exact Godot Build Context** (`GodotContextBuilder.buildEpicGodotContext`):

| Section / Surface | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` System Intent & Scene Links** | `goal`, `links[]`, `outOfScope[]` | **1. BLUF** + Contract Links | Direct mechanic intent + explicit `res://` scene/script links + `No ...` cuts | `res://scenes/player.tscn -> res://scenes/arena.tscn` |
| **`§02` Controls (`InputMap Actions`)** | `controls[]` (`action`, `trigger`, `rule`) | **4. Godot Control Rule** | `snake_case` `project.godot` InputMap action + trigger + unit-bound rule | `claw_dash | Just Pressed (Space) | Launch 5.5 m over 0.16s` |
| **`§03` State Flow & Interrupt Rules** | `states[]`, `interrupts[]` | **4. State Transition** | Explicit state graph + interrupt precedence | `Ready -> Dashing -> Cooldown`, `Dash cancels Recovery` |
| **`§04` Spatial & Exposed Tuning (`@export`)** | `tuning[]` (`key`, `value`, `unit`) | **4. Live Tuning Input** | `snake_case` `@export` var + canonical Godot unit (`m`, `m/s`, `px`, `px/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`) | `dash_distance: 5.5 m` |
| **`§05` Viewport, UI & Audio Cues** | `feedback[]` | **1. Observable Cue** | Camera punch, GPUParticles/StandardMaterial3D flash, Control HUD arc, or audio cue | `GPUParticles3D thruster trail + radial HUD cooldown arc` |
| **`§06` Test Scene Staging & Playtest Gate** | `levelStaging`, `checks[]`, `fixes[]`, `lifecycle` | **2. Causal Playtest Gate** + **`[FIX]`** | Interactive Playtest checks + live `Flag [FIX]` switching context between `FULL-EPIC AUTONOMOUS BUILD` and `FOCUSED PLAYTEST REVISION PASS`, synced 2-way with 1-click In-Dock Cloud Gemini Builder | `Press claw_dash -> Mech crosses 5.5 m floor marker cleanly` |

# LAYERS Unreal Spec Style Guide (Source-First, Zero 2-Step Token Waste)

> **Golden Rule (Source-First Generation)**: Every Stage 1 and Stage 2 AI prompt and Gemini tool schema must reference [`lib/constants/text_style_guide.dart`](lib/constants/text_style_guide.dart) (`LayersTextStyleGuide`) and pass validation via [`UnrealSpecGuard`](lib/utils/unreal_spec_guard.dart) so Gemini emits exact Unreal Engine high-level design specs on the first pass (`Project -> Release -> Epic`, `1 UU = 1 cm`).
>
> **Strict High-Level Boundary**: Never emit implementation micro-steps, file trees, `Feature`/`Task` sub-tickets, or legacy Godot terms (`.tscn`, `.gd`, `GDScript`, `CharacterBody3D`, `px/s`).

---

## 1. The 4 Canonical Text Styles

| # | Style Name | Formula | Max Length | Where Used | Canonical Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **BLUF (Bottom Line Up Front)** | **`[2–4 Word Payoff] — [Compact Unreal Scope]`** | `<= 14 words` | • Stage 1 `pitch` (`§01 Core Fantasy & 30s Loop`)<br>• Stage 2 Progressive Release Co-Pilot presets & goals | `Claw Arena Skirmisher — Top-down crab mech dash-shooter across 3 arena waves.` |
| **2** | **Causal PIE Gate (`Trigger -> Result`)** | **`[Player Action] -> [Observable PIE Screen Result]`** | `<= 14 words` | • Stage 1 `releaseDoneWhen` (`§05`)<br>• Stage 2 Epic `checks[]` (`§06 Test Level Staging & PIE Acceptance Gate`) | `Hold IA_Dash into enemy guard -> Shield shatters + 55ms hit-stop plays in PIE` |
| **3** | **Changelog / Delta-Diff (`+Delta`)** | **`+mechanic delta`** *(Upgrades)*<br>**`Direct noun summary`** *(New)* | `5–10 words` | • Progressive Release Co-Pilot `[UPGRADE]` checkboxes & `[NEW]` cards<br>• Epic `upgradeDeltas[]` atop locked `v0.1` baseline | `+55ms Hit-Stop freeze & radial shockwave ring` |
| **4** | **Unreal Scale & Telegraphic Micro-Labels** | **`2–5 Title-Case Words`** / **`Key: Value unit`** (`1 UU = 1 cm`) | `2–6 words` | • Epic titles (`E0# · Title`)<br>• `§02` Camera/Scale/Input contracts<br>• `§04 Spatial & Exposed Tuning (1 UU = 1 cm)`<br>• `§04` Hard Scope Cuts (`"No [2–5 word system]"`) | • **Epic**: `Player Mech Movement & Claw Dash`<br>• **Scale**: `DashImpulse: 1850 cm/s`<br>• **Cut**: `No main menu or save slots` |

---

## 2. Surface-by-Surface Mapping (Stage 1 & Stage 2)

### A. Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))
Toggleable between **Clean Spec Document** (`PROJECT_SPEC.md`) and **Raw `ROOT_MCP_CONTEXT.md`** (rendered by [`UnrealMcpPayloadBuilder.buildRootMcpContext`](lib/utils/unreal_mcp_payload_builder.dart)), plus a `UE 5.9 MCP` / `UE6 Verse` architecture switch:

| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Core Fantasy & 30s Loop** | `pitch`, `coreLoop[]` | **1. BLUF** + Verb Beats | `1` plain pitch sentence + `2–4` chronological `"Verb -> Result"` beats | `Move & Aim -> Burst Fire -> Claw Dash -> Wave Reset` |
| **`§02` Global Unreal Scale & Architecture (`1 UU = 1 cm`)** | `cameraOptions[]`, `cameraContract`, `characterScale`, `inputContract`, `assetPolicy` | **4. Unreal Contract** | Concrete UE types + `cm` / `cm/s` / `deg` units | `SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0` |
| **`§03` Design Pillars & Conflict Trade-Offs** | `pillars[]`, `tradeOffs[]` | **1. BLUF Pillar** + **`OVER` Rule** | `"Pillar Name: experiential reason"` + `<prefer> OVER <avoid>` | `Snappy Arcade Response OVER Momentum Simulation` |
| **`§04` Hard Scope Cuts (Do Not Build)** | `outOfScope[]` | **4. Micro-Label Cut** | Always starts with `"No [2–5 word system]"` | `No main menu or save slots` |
| **`§05` Initial Release (`v0.1` Prototype Epics Only)** | `releaseDoneWhen`, `initialEpics[]` | **2. Causal PIE Gate** + Epic Cards | Strictly `v0.1` Epics (zero `v0.2+` bloat); `releaseDoneWhen` uses `Trigger -> Result` | `E01 · v0.1 — Player Mech Movement & Claw Dash` |

---

### B. Stage 2 — Progressive Release Co-Pilot (`+ New Release v0.X ✦` in [`lib/agents/release_planner_agent.dart`](lib/agents/release_planner_agent.dart))

| Surface | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Direction Presets** | `presets[]` | **1. BLUF** | `2–4` word preset label + crisp release focus goal | `Wave Escalation & Armor Break` |
| **Baseline Evolution** | `upgradesByLineageKey` | **3. Changelog `+Delta`** | `[UPGRADE] +mechanic delta` attached to existing `v0.1` Epics | `[UPGRADE] +Enemy stagger buildup & shield crack VFX` |
| **New Scope Candidates** | `candidateNewEpics[]` | **4. Micro-Label** + Summary | `[NEW] E0# · Title` + concise 1-sentence goal | `[NEW] E04 · Arena Hazard Vents` |
| **Unmodified Baseline** | `baselineEpics` | **Lock Badge** | Carried untouched as `Baseline ✓` (`EpicLifecycle.stable`) | `E01 · Player Mech Movement & Claw Dash [Baseline ✓]` |

---

### C. Stage 2 — Epic Specs (`2. Epic Specs` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart)) & `LayersBridge` (`unreal_plugin/LayersBridge/`)
Strictly 3-tier hierarchy (`Project -> Release -> Epic`). Toggleable between **Clean Epic Spec** and **Exact Unreal MCP Payload** (`UnrealMcpPayloadBuilder.buildEpicMcpPayload`):

| Section / Surface | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` System Intent & Actor Links** | `goal`, `links[]`, `outOfScope[]` | **1. BLUF** + Contract Links | Direct mechanic intent + explicit UE asset/system links + `No ...` cuts | `BP_CrabPlayer -> IMC_Combat / GM_Arena` |
| **`§02` Controls** | `controls[]` (`action`, `trigger`, `rule`) | **4. Unreal Rule** | Enhanced Input action + trigger + unit-bound rule (`cm`, `cm/s`, `s`) | `IA_Dash | Started | Burst impulse 1850 cm/s for 0.18 s` |
| **`§03` State Flow & Interrupt Rules** | `states[]`, `interrupts[]` | **4. State Transition** | Explicit state graph + interrupt precedence | `Ready -> Dashing -> Cooldown`, `Dash cancels Recovery` |
| **`§04` Spatial & Exposed Tuning (`1 UU = 1 cm`)** | `tuning[]` (`key`, `value`, `unit`) | **4. Live Tuning Input** | Numeric scalar + canonical UE unit (`cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`) | `DashDistance: 550 cm` |
| **`§05` Viewport, UMG & Audio Cues** | `feedback[]` | **1. Observable Cue** | Camera shake, Niagara/material flash, UMG readout, or audio cue | `Niagara thruster trail + 40ms camera punch` |
| **`§06` Test Level Staging & PIE Acceptance Gate** | `levelStaging`, `checks[]`, `fixes[]`, `lifecycle` | **2. Causal PIE Gate** + **`[FIX]`** | Interactive PIE checks + live `Flag [FIX]` switching MCP payload between `FULL-EPIC AUTONOMOUS BUILD` and `FOCUSED PIE REVISION PASS`, synced 2-way with `LayersBridge` | `Press IA_Dash -> Pawn crosses 550 cm arena marker cleanly` |

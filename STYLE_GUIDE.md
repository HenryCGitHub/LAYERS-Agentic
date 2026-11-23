# LAYERS Unreal Engine 5 + CoPilot Spec Style Guide (Source-First, Zero 2-Step Token Waste)

> **Golden Rule (Source-First Generation)**: Every Stage 1 and Stage 2 AI prompt and Gemini tool schema references [`lib/constants/text_style_guide.dart`](lib/constants/text_style_guide.dart) (`LayersTextStyleGuide`) and passes sanitization through [`UnrealSpecGuard`](lib/utils/unreal_spec_guard.dart) so Gemini emits Unreal Engine 5 high-level design specs on the first pass (`Project -> Release -> Epic -> Feature`).
>
> **Strict Zero-Overlap Boundary**:
> - **Epics (Large Domains)** own cross-slice `Goal` / `In Scope` / `Done When`, `sceneOwnership` (`/Game/...` assets or `Source/` C++ classes + roles), `stateFlow`, `interruptRules`, `outOfScope` cuts, and child Feature slices (`F01–F0N`).
> - **Features (30–90 min Playable Slices)** own Enhanced Input bindings (`IA_*`, `IMC_*`), live exposed `PascalCase` tuning variables (`cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`), viewport/UI/audio cues, Playtest Gate checkboxes, `[FIX]` revisions, and 1-click **Ultimate Engine CoPilot** prompts (`⚡ Copy CoPilot Prompt`, `🔧 Copy CoPilot [FIX] Prompt`, `Preview`).
> - Never emit implementation micro-steps, `Task`/`Step` tickets, file trees, or non-Unreal engine terms (`.tscn`, `.tres`, `.gd`, `.prefab`, `res://`, `GDScript`, `InputMap`, `CharacterBody3D`, `@export`, `GameObject`, `MonoBehaviour`).

---

## 1. The 4 Canonical Text Styles

| # | Style Name | Formula | Max Length | Where Used | Canonical Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **BLUF (Bottom Line Up Front)** | **`[2–4 Word Payoff] — [Compact UE5 Scope]`** | `<= 14 words` | • Stage 1 `pitch` (`§01 Core Fantasy & 30s Loop`)<br>• Stage 2 Progressive Release Co-Pilot presets & goals | `Claw Arena Skirmisher — Top-down 3D crab mech dash-shooter across 3 arena waves.` |
| **2** | **Causal Playtest Gate (`Trigger -> Result`)** | **`[Player Action] -> [Observable Viewport Result]`** | `<= 14 words` | • Stage 1 `releaseDoneWhen` (`§05`)<br>• Stage 2 Feature `checks[]` (`§05 Playtest Gate & [FIX] Notes`) | `Press Space dash into guard -> Shield shatters + Niagara spark burst plays in PIE` |
| **3** | **Changelog / Delta-Diff (`+Delta`)** | **`+mechanic delta`** *(Upgrades)*<br>**`Direct noun summary`** *(New)* | `5–10 words` | • Progressive Release Co-Pilot `[+DELTA]` & `[+NEW]` checkboxes<br>• Feature `releaseDelta` & Epic `upgradeDeltas[]` atop locked `v0.1` baseline | `+55ms Hit-Stop freeze & radial shockwave ring` |
| **4** | **Unreal 5 Scale & Telegraphic Micro-Labels** | **`2–5 Title-Case Words`** / **`PascalCase: Value unit`** (`cm`, `cm/s`, `deg`, `s`) | `2–6 words` | • Epic & Feature titles (`E0# · Title`, `F0# · Title`)<br>• `§02` Camera/Scale/Input contracts & `/Game/...` ownership<br>• Feature `§03 Exposed Tuning`<br>• `§04` Hard Scope Cuts (`"No [2–5 word system]"`) | • **Epic**: `Player Movement & Camera`<br>• **Feature**: `Armored Claw Dash`<br>• **Scale**: `DashImpulseCmPerSec: 1850 cm/s`<br>• **Cut**: `No main menu or save slots` |

---

## 2. Surface-by-Surface Mapping (Stage 1 & Stage 2)

### A. Stage 1 — Project Spec (`1. Project Spec` in [`lib/screens/project_pitch_screen.dart`](lib/screens/project_pitch_screen.dart) & [`lib/agents/project_concept_agent.dart`](lib/agents/project_concept_agent.dart))
Displays the Clean Spec Document (`PROJECT_SPEC.md`) with a `Blueprint-First` / `C++ & BP Hybrid` architecture toggle (`UnrealArchitectureToggle`) and full `.md` + `⚡ CoPilot GDD` export in the top bar:

| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Core Fantasy & 30s Loop** | `pitch`, `coreLoop[]` | **1. BLUF** + Verb Beats | `1` plain pitch sentence + `2–4` chronological `"Verb -> Result"` beats | `Move & Aim -> Burst Fire -> Claw Dash -> Wave Reset` |
| **`§02` Global Unreal Engine 5 Scale & Architecture** | `cameraOptions[]`, `cameraContract`, `characterScale`, `inputContract`, `assetPolicy` | **4. UE5 Contract** | Concrete UE5 classes + `cm` / `cm/s` + `deg` units | `USpringArmComponent 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0` |
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

### C. Stage 2 — Release Workbench (`2. Release Workbench` in [`lib/screens/release_workbench_screen.dart`](lib/screens/release_workbench_screen.dart)) & CoPilot Prompt Export ([`lib/utils/unreal_context_builder.dart`](lib/utils/unreal_context_builder.dart))

#### Epic Domain Sheet (`selectedFeatureId == null` -> `UnrealContextBuilder.buildEpicArchitectureContext`)
| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Domain Scope** | `goal`, `inScope[]`, `doneWhen[]` | **1. BLUF** + Structured 3-Part | 1-sentence Domain Goal + concise bullets (zero duplicated Feature inputs/vars) | `Goal: Own mech planar locomotion & dash commitments.` |
| **`§02` Shared Blueprint, Level & Class Ownership** | `sceneOwnership[]` (`path`, `role`), `+ Add Owner` inline editor | **4. `/Game/...` & `Source/` Contract** | Editable authoritative `/Game/...` assets or `Source/` C++ classes & roles flowing directly into child prompts | `/Game/Blueprints/BP_PlayerMech.uasset — Movement state & Exposed BP tuning` |
| **`§03` Shared State & Interrupt Rules** | `stateFlow[]`, `interruptRules[]`, `Edit Rules` inline editor | **4. State Transition** | Editable cross-slice state graph + interrupt precedence (`@STATES:` in child prompts) | `Idle -> Walk -> ClawDash -> Recover` |
| **`§04` Domain Out-of-Scope Cuts** | `outOfScope[]` | **4. Micro-Label Cut** | Explicit `"No ..."` boundaries for the Epic domain | `No wall jumping or ledge vaulting` |
| **`§05` Child Features** | `features[]`, `+ Add Feature Slice` | **Rollup Cards** | Live `passed/total` Feature rollups + inline creation of new slices | `F02 · Armored Claw Dash (60 min)` |

#### Feature Slice Spec Sheet (`selectedFeatureId != null` -> `UnrealContextBuilder.buildCoPilotFeaturePrompt`)
| Section | Fields | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **`§01` Feature Scope** | `goal`, `inScope[]`, `doneWhen[]`, `releaseDelta` | **1. BLUF** + Delta Banner | Playable `30–90 min` slice scope + link to parent Epic | `Goal: Launch a 550 cm forward dash on 1.1 s cooldown.` |
| **`§02` Input Actions (`Enhanced Input`)** | `controls[]` (`action`, `trigger`, `rule`) | **4. UE5 Control Rule** | `IA_*` Enhanced Input action + trigger/key + unit-bound rule | `IA_ClawDash \| Triggered (Space) \| Launch 550 cm over 0.16s` |
| **`§03` Exposed Tuning (`Exposed BP Var` / `UPROPERTY(EditAnywhere)`)** | `tuning[]` (`key`, `value`, `unit`) | **4. Live Tuning Input** | `PascalCase` variable + canonical UE5 unit (`cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`) | `DashDistanceCm: 550 cm` |
| **`§04` Viewport, UI & Audio Cues** | `cues[]` | **1. Observable Cue** | Camera shake, `UNiagaraComponent`/emissive material flash, `WBP_*` HUD widget, or audio cue | `Orange emissive thruster ribbon fires for 0.16 s` |
| **`§05` Playtest Gate & `[FIX]` Notes** | `checks[]`, `releaseDeltaChecks[]`, `fixes[]`, `status` | **2. Causal Playtest Gate** + **`[FIX]`** | Interactive PIE checks + live `Flag [FIX]` switching Stage 2 CoPilot CTA between `⚡ Copy CoPilot Prompt` and `🔧 Copy CoPilot [FIX] Prompt` | `Press Space -> Mech crosses 550 cm cleanly` |

---

## 3. Dual-Format Output (Human-Readable Studio vs. Token-Efficient CoPilot DSL)

1. **Web Studio UI & `Copy Full Project Spec (.md)`**: Structured human-readable Markdown (`compact: false`) for team reading, spec reviews, and archival exports.
2. **Heading-Indexed `*_copilot_gdd.md` (`⚡ CoPilot GDD`)**: Clean `#` / `##` / `###` Markdown headings with telegraphic bullets so Ultimate Engine CoPilot `V2.0+` splits and searches sections on demand.
3. **CoPilot Chat Prompts ([`UnrealPromptCompactor`](lib/utils/unreal_prompt_compactor.dart), `compact: true`)**: Default output for `⚡ Copy CoPilot Prompt`, `🔧 Copy CoPilot [FIX] Prompt`, `⚡ Copy CoPilot Delta Prompt`, and `Copy Epic Brief`. Uses telegraphic `@TAG` headers (`[UE5_COPILOT TASK=BUILD|FIX|DELTA|EPIC_BRIEF]`, `@CTX`, `@EPIC`, `@OWNERS`, `@STATES`, `@FEATURE`, `@INPUT`, `@TUNE`, `@CUES`, `@CHECKS`, `@FIX_NOW`, `@CUTS`), keeps exact `/Game/...`, `Source/...`, `IA_*`/`IMC_*`, `PascalCase`, and `cm`/`cm/s` tokens, and collapses passed PIE checks during `[FIX]` passes (`~35–55%` fewer tokens).
4. **Live Preview Toggle (`Compact DSL | Readable View`)**: Both Feature Prompt and Epic Brief `Preview` dialogs show the live `~N tok · -X% vs MD` badge and toggle between `Compact DSL` and `Readable View` without altering clipboard defaults.

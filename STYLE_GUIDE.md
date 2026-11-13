# LAYERS Text Format Style Guide (Source-First, Zero 2-Step Token Waste)

> **Golden Rule (Source-First Generation)**: Every Stage 1 and Stage 2 AI prompt and tool schema must reference [`lib/constants/text_style_guide.dart`](lib/constants/text_style_guide.dart) (`LayersTextStyleGuide`) so Gemini generates these exact formats natively on the first pass—never ask the model for verbose sentences only to regex-strip them afterward.

---

## 1. The 5 Canonical Text Styles

| # | Style Name | Formula | Max Length | Where Used | Canonical Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **BLUF (Bottom Line Up Front)** | **`[2–4 Word Payoff] — [Scope / Action]`** | `<= 14 words` | • Progressive Release `GOAL:` line<br>• Progressive `EPICS` Option Cards<br>• Stage 1 `01 · Goal`, `04 · Design Pillars`, `06 · Core Loop` | `3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.` |
| **2** | **Causal `Trigger → Result`** | **`[Player Action] → [Observable Screen Result]`** | `<= 14 words` | • `✓ END GOAL:` (`doneWhen`)<br>• `VERIFY IN ENGINE` (`verifyResult`)<br>• Feature `doneWhen` / `playtestCriteria` / `playtestGate` | `Press Fire within 4m of target → 6 pellets fan out + push enemy back 2.5m` |
| **3** | **Changelog / Delta-Diff (`+Delta`)** | **`+delta1, +delta2`** *(Upgrades)*<br>**`Direct noun summary`** *(New)* | `5–10 words` (`2–4 words` per delta) | • Progressive Release Feature Rows (`v0.2+`)<br>• Workbench Feature Goal subtitle<br>• Feature `inScope` bullets | • `[UPGRADE]`: `+6-pellet cone spread, +knockback impulse`<br>• `[NEW]`: `Magnetic ore shard spawn on enemy kill` |
| **4** | **Imperative Runbook** | **`Verb + Object + Value`** | • Step Title: `3–4 words`<br>• Instruction: `<= 18 words` | • Child Sub-Step Titles (`01 · ...` inside task)<br>• Active Step `DO` instruction (`02 STEP X OF Y`) | • **Step Title**: `Spawn 6 Pellet Raycasts`<br>• **Instruction**: `Cast 6 raycasts across an 18° cone from MuzzlePoint and apply knockbackForce (14.0) to hit bodies.` |
| **5** | **Telegraphic Component / Micro-Label** | **`2–4 Title-Case Words`** *(no verbs, no articles `a/an/the`)* | `2–4 words` (`<= 32 chars`) | • Parent Task Group Titles (`01 · ...` in `01 STEPS`)<br>• Epic & Feature Titles<br>• Stage 1 `02 Game Spec`, `03 Tech Spec`, `05 Trade-Offs`, `07 Out of Scope`<br>• `[STATE GUARD]` chips | • **Task Group**: `Collision Layer & Flags`, `Impulse & Window Timer`, `Ghost Trail & SFX`<br>• **Feature**: `Shotgun Spread & Recoil`<br>• **Guard**: `[STATE GUARD] Block dash while cooldown active` |

---

## 2. Surface-by-Surface Mapping (Stage 1 & Stage 2)

### A. Stage 1 — Concept Blueprint (`1. Concept` in `lib/agents/project_concept_agent.dart`)

| Section | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Spark Intake** | `workingTitle` | **5. Micro-Label** | `2–3` Title-Case words naming setting/mechanic | `Scrap Dome Siege` |
| **Spark Intake** | `baseSummary` | **1. BLUF Pitch** | `2` natural sentences (premise + repeatable loop) | `Pilot a salvage rig inside a sealed dome...` |
| **`01 · Goal`** | `goal` | **1. BLUF Goal** | `1` direct sentence: `"Build a playable [Title] prototype where you [action 1], [action 2], and [action 3]."` (No `"Strategy Label:"` prefix on `goal`) | `Build a playable Scrap Dome Siege prototype where you cut debris, haul ore, and upgrade turrets.` |
| **`02 · Game Spec`** | `cameraView`, `controls`, `playerMode`, `arenaStructure` | **5. Micro-Label** | `2–5` telegraphic words per cell | `2D Top-Down` · `WASD + Mouse Aim` · `Singleplayer` · `Single-Screen Arena` |
| **`03 · Tech Spec`** | `engine`, `platform`, `assetPipeline`, `saveMode` | **5. Micro-Label** | Concrete engine enum + `2–5` telegraphic words per cell | `Godot 4 (GDScript)` · `PC Desktop` · `2D Sprites + Particles` · `Local JSON Save` |
| **`04 · Design Pillars`** | `pillarName` + `playerExperience` | **1. BLUF** | `2–3` word Title-Case Pillar Name + `1` sentence player feeling (never a feature or genre) | `Every Second Counts: Constant oxygen drain turns every salvage cut into a tense risk.` |
| **`05 · Trade-Offs`** | `priorityX` over `overAlternativeY` | **5. Micro-Label** | `2–4` words per side (no `"Prioritize"` or `"for v0.1"`) | `Immediate arcade dash` over `Realistic momentum inertia` |
| **`06 · Core Loop`** | `coreLoopBeats[]` | **1. BLUF + Causal** | `"2–3 Word Beat Name: Observable player action and system response"` | `Cut & Collect: Slice hull plates with the laser cutter → collect magnetic ore shards` |
| **`07 · Out of Scope`** | `exclusions[]` | **5. Micro-Label** | `"No [2–4 word excluded system]"` (no `"in v0.1 prototype"` tail) | `No online multiplayer`, `No branching dialogue` |
| **`08 · Done When`** | `doneWhen` | **2. Causal `Trigger → Result`** | `"[Player Action Sequence] → [Observable Loop Resolution]"` (no FPS targets) | `Spawn in arena, clear 3 waves, spend ore at shop → start Wave 4 cleanly` |

---

### B. Stage 2 — Progressive Release Co-Pilot (`+ New Release v0.X ✦` in `lib/agents/release_planner_agent.dart`)

| Surface | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Header Badge & Title** | `releaseTitle` | **5. Micro-Label** | `"vX.Y: 2–4 Word Focus Title"` | `v0.3: Shotgun & Arena Waves` |
| **Step 1 · `EPICS` Cards** | `questions[0].options[]` | **1. BLUF + `+Delta`** | `"E0# + E0# · 2–4 Word Title — +delta1 + +delta2 + +delta3"` | `E02 + E03 · Shotgun & Waves (★ REC) — 6-pellet spread + 2.0s floor spikes + 3 enemy waves` |
| **Step 1 · `GOAL:` Line** | `goal` | **1. BLUF** | `"[2–4 Word Payoff] — Complete E0# [System] and E0# [System] for [Phase]."` | `GOAL: 3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.` |
| **Step 1 · `✓ END GOAL:`** | `doneWhen` | **2. Causal `Trigger → Result`** | `"[Player Action] → [Observable Screen Result]"` (`<= 14 words`) | `✓ END GOAL: Clear 3 enemy waves around active floor spikes → collect dropped ore shards` |
| **Step 2 · Feature Rows** | `features[].title` + `inScope` / `goal` | **3. Changelog `+Delta`** | • `UPGRADE`: `Title — +delta1, +delta2 [UPGRADE]`<br>• `NEW`: `Title — direct 5–8 word summary [NEW]` | • `☑ Shotgun Spread & Recoil — +6-pellet cone spread, +knockback impulse [UPGRADE]`<br>• `☑ Ore Drop Pickup — Magnetic ore shard spawn on enemy kill [NEW]` |

---

### C. Stage 2 — Release Workbench (`2. Workbench` in `lib/providers/workbench_release_mixin.dart`)

| Surface | Field | Assigned Style | Exact Format Rule | Example |
| :--- | :--- | :--- | :--- | :--- |
| **Left Outliner Epic Row** | `beat.title` | **5. Micro-Label** | `E0# · 2–4 Title-Case Words` naming gameplay system | `E01 · Top-Down Traversal & Dash` |
| **Left Outliner Feature Row** | `feature.title` | **5. Micro-Label** | `2–3 Title-Case Words` naming 1 observable action/object (no `"System"`, `"Controller"`, `"Manager"`) | `Dash Burst Evade`, `Shotgun Spread`, `Ore Drop Pickup` |
| **Workspace Feature Subtitle** | `feature.goal` | **3. Changelog `+Delta`** | `5–10` words stating the concrete mechanics/deltas directly (no `"Build a playable..."` or `"Upgrade <Feature> into..."` preambles) | `+I-frame invulnerability window, +ghost trail VFX, +cooldown tuning` |
| **`BUILD QUEUE` · Unified Steps (`01..0N`)** | `steps[].title` | **4. Imperative Runbook (`Verb + Object`)** | **`3–4 Title-Case Words`** starting with a command verb + concrete target, ordered once per Feature Checkpoint by Godot dock (`SCENE` -> `INSP` -> `CODE` -> `WIRE`). Emit **without** `"STEP X.Y ·"` prefix and **never** nest inside `T1..T3` parent tasks. | • `01 · SCENE · Build Player Dash Nodes`<br>• `02 · INSP · Set Layers & Exports`<br>• `03 · CODE · Code Dash Impulse`<br>• `04 · WIRE · Connect DashTimer Signal` |
| **`ACTIVE STEP` · Breadcrumb** | `steps[].stepPath` | **5. Micro-Label** | Telegraphic dock/file path | `res://scenes/player.tscn` · `res://scripts/player.gd` |
| **`ACTIVE STEP` · `DO` Instruction** | `steps[].instruction` | **4. Imperative Runbook (`Verb + Object + Value`)** | **`1–3` crisp micro-actions (`<= 18 words` each)** starting with a command verb + exact node/script and tuning value (no `"In the Inspector, ..."` preamble) | `Cast 6 raycasts across an 18° cone from MuzzlePoint and apply knockbackForce (14.0) to hit bodies.` |
| **`ACTIVE STEP` · `CHECK IN EDITOR` / `VERIFY IN ENGINE`** | `steps[].verifyMode` + `steps[].verifyResult` | **Dual-Mode Check (`editor` vs. `playtest`)** | • **`editor` (`EDITOR CHECK:`):** Literal Hierarchy/Inspector/Compiler check (`<= 14 words`, no `"Press Play"`) when runtime wiring isn't connected yet.<br>• **`playtest` (`PLAYTEST CHECK:`):** **`[Player Action] → [Observable Screen Result]`** (`<= 14 words`) on runnable & final steps. | • `editor`: `Player shows DashTimer child node + 0 script errors`<br>• `playtest`: `Press Fire within 4m of target → 6 pellets fan out + push enemy back 2.5m` |
| **`F6 · PLAYTEST GATE` · Guards & Tuning** | `tuningParams[]` & `edgeCases[]` | **5. Micro-Label** | • Tuning (`INSP` Sheet): `"paramName: numericValue unit"`<br>• Guard (`F6` Gate): `"[STATE GUARD] <3–6 word telegraphic rule without a/an/the>"` | • `dashSpeed: 650.0 px/s`<br>• `[STATE GUARD] Block dash while cooldown active` |

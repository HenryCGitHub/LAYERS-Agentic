/// Central Single Source of Truth for the 5-Style LAYERS Text Format Guide
/// (documented in `STYLE_GUIDE.md` and `GEMINI.md`).
///
/// Referenced directly across Stage 1 (`ProjectConceptAgent`) and Stage 2
/// (`ReleasePlannerAgent`, `WorkbenchReleaseMixin`, `GeminiAgentClient`)
/// tool schemas and prompts so Gemini generates the exact target format on
/// the first pass without 2-step post-formatting token waste.
class LayersTextStyleGuide {
  const LayersTextStyleGuide._();

  /// Shared compact style rules injected across Stage 1 & Stage 2 prompts.
  static const String compactStyleRules = '''
RULES (LAYERS 5-STYLE FORMAT GUIDE — GENERATE DIRECTLY AT SOURCE):
- Feature & Epic Titles (Micro-Label): 2-3 plain Title-Case game-dev words naming 1 observable player/world action or object (e.g. "Truck Steering", "Shotgun Spread", "Ore Drop Pickup"). NEVER use code-architecture suffixes ("Controller", "System", "Mechanic", "Manager", "Component", "Handler") or roleplay/archaic lore ("Husbandry", "Homestead", "Expedition") or buzzwords ("canonical", "deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly").
- Release Goals (BLUF): "[2-4 Word Payoff] — [Scope]" (e.g. "3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.").
- Feature Goals & In-Scope (Changelog +Delta): Direct 5-10 word summary of concrete mechanics/deltas (e.g. "+6-pellet cone spread, +knockback impulse" for upgrades; "Magnetic ore shard spawn on enemy kill" for new features). NEVER start feature goals with "Build a playable..." or "Upgrade <Feature> into/with..." and NEVER copy-paste raw user instructions verbatim.
- Done When, Playtest Gates & Verify (Causal Trigger -> Result): "[Player Action] -> [Observable Screen Result]" (<= 14 words, e.g. "Press Fire within 4m of target -> 6 pellets fan out + push enemy back 2.5m"). NEVER use FPS/60fps targets.
- Parent Task Group Titles (tasks[].title): Strictly 2-4 Title-Case words naming 1-2 concrete components (e.g. "Collision Layer & Flags", "Impulse & Window Timer", "Ghost Trail & SFX"). NO verbs (Setup, Code, Write, Create, Trigger, Implement), NO 3-item lists (A, B, & C), NO "while/when" clauses, NO "(2h)" tags.
- Sub-Step Titles & Instructions (Imperative Runbook): subSteps[].title = 3-4 Title-Case "Verb + Object" words (e.g. "Spawn 6 Pellet Raycasts", NO "STEP X.Y" prefix); instruction = 1 imperative sentence (<= 18 words) starting with a command verb + exact node/script and tuning value.''';

  // ── Stage 1: Concept Blueprint Schema Descriptions ────────────────────────

  static const String stage1TitleSchemaDesc =
      'Short 2-3 word plain Title-Case game title.';

  static const String stage1GoalSchemaDesc =
      '1 direct sentence: "Build a playable [Title] prototype where you [action 1], [action 2], and [action 3]." (No "Strategy Label:" prefix on goal).';

  static const String specCellSchemaDesc =
      'Telegraphic 2-5 word phrase (e.g. "2D Top-Down", "WASD + Mouse Aim", "Singleplayer", "Single-Screen Arena").';

  static const String pillarNameSchemaDesc =
      '2-3 Title-Case Word Pillar Name';

  static const String pillarExperienceSchemaDesc =
      'Concise 1-sentence player feeling or emotional tension (never a feature or genre).';

  static const String tradeOffPrioritySchemaDesc =
      '2-4 words naming what we prioritize (e.g. "Arcade dash response")';

  static const String tradeOffAlternativeSchemaDesc =
      '2-4 words naming what we sacrifice (e.g. "Momentum inertia")';

  static const String coreLoopBeatSchemaDesc =
      '2-3 Word Beat Name: Concise observable player action and system response.';

  static const String exclusionItemSchemaDesc =
      'No [2-4 word excluded system/content] (never use "Cut/Defer" or "in v0.1 prototype").';

  // ── Stage 2: Release Plan, Progressive Release & Workbench Descriptions ───

  static const String epicTitleSchemaDesc =
      '2-4 Title-Case game-dev words naming the gameplay system or body of engineering work (never copy a 06 Core Loop beat title word-for-word).';

  static const String featureTitleSchemaDesc =
      '2-3 Title-Case words naming 1 observable action or object (no "System"/"Controller"/"Manager" or "&").';

  static const String blufReleaseGoalSchemaDesc =
      'BLUF style: "[2-4 Word Payoff] — Complete E0# [System] and E0# [System] for [Phase]." (e.g. "3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.").';

  static const String progressiveEpicOptionSchemaDesc =
      'BLUF + Telegraphic +Delta option: "E0# + E0# · 2-4 Word Title — +delta1 + +delta2 + +delta3" (Option 1 prefixed with "(Recommended) ").';

  static const String progressiveMissingGapSchemaDesc =
      'Telegraphic 4-8 word gap prefixed with "E0#: " naming what is lacking right now.';

  static const String causalTriggerResultSchemaDesc =
      'Causal Trigger -> Result style ("<Player Action> -> <Observable Screen Result>", <= 14 words, no FPS targets).';

  static const String changelogDeltaGoalSchemaDesc =
      'Changelog +Delta style (5-10 words): "+delta1, +delta2" for upgrades (e.g. "+6-pellet cone spread, +knockback impulse") or direct noun summary for new features (e.g. "Magnetic ore shard spawn on enemy kill"). NO "Build/Upgrade <Feature> with" preambles.';

  static const String changelogDeltaInScopeSchemaDesc =
      '2-3 telegraphic 2-4 word changelog deltas without articles a/an/the (prefix upgrades with "+", e.g. "+6-pellet cone spread", "+knockback impulse").';

  static const String taskGroupTitleSchemaDesc =
      'Strictly 2-4 Title-Case words naming 1-2 concrete components (e.g. "Collision Layer & Flags", "Impulse & Window Timer", "Ghost Trail & SFX"). NO verbs (Setup/Code/Create/Trigger/Implement), NO 3-item lists, NO "while/when" clauses, NO "(2h)" duration tags.';

  static const String tuningParamSchemaDesc =
      'paramName: numericValue unit (e.g. "dashSpeed: 14.0 m/s")';

  static const String stateGuardSchemaDesc =
      'Telegraphic state guard formatted as "[STATE GUARD] <3-6 word rule without articles a/an/the>" (e.g. "[STATE GUARD] Block dash while cooldown active").';

  static const String playtestGuardSchemaDesc =
      'Telegraphic guard formatted as "[PLAYTEST GUARD] <3-6 word rule without articles a/an/the>"';

  static const String runbookStepTitleSchemaDesc =
      '3-4 Title-Case Imperative Runbook words (Verb + Object, e.g. "Spawn 6 Pellet Raycasts", "Add Hazard Detection Component", drop articles a/an/the). Do NOT include "STEP X.Y" prefix.';

  static const String runbookStepPathSchemaDesc =
      'Telegraphic editor panel/menu/inspector/script breadcrumb separated by " > "';

  static const String runbookInstructionSchemaDesc =
      '1 Imperative Runbook sentence (<= 18 words) starting with a command verb (Create, Bind, Spawn, Clamp, Set) + exact node/script and tuning value.';
}

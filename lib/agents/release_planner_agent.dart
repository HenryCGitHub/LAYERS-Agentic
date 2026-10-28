import 'dart:convert';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and synthesizes a single-Release Blueprint (`ReleaseBlueprint`) using Gemini AI (`gemini-4-argon`).
/// Contains zero hardcoded archetypes and zero offline minimal scaffolds.
/// Returns `null` (or `false`) whenever the app is offline or Gemini AI is unreachable.
class ReleasePlannerAgent {
  static final RegExp _releaseVersionRegex =
      RegExp(r'(v\d+\.\d+(?:\.\d+)?)', caseSensitive: false);
  static final RegExp _mvpEpicNumRegex =
      RegExp(r'MVP Epic\s*(\d+)', caseSensitive: false);

  static String extractReleaseVersionTag(String releaseTitle) {
    final match = _releaseVersionRegex.firstMatch(releaseTitle);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'v0.1';
  }

  /// Synthesizes a `ReleaseBlueprint` for `releaseDoc` via Gemini AI (`gemini-4-argon`).
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ReleaseBlueprint?> planRelease({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    List<TierDocument> completedReleases = const [],
    List<TierDocument> existingBeats = const [],
    Map<String, List<TierDocument>> existingFeaturesByBeat = const {},
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    String apiKey = '',
    String modelName = 'gemini-4-argon',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final preset = releaseDoc.releaseScope;
    final versionTag = extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = releaseDoc.sections['phase'] ?? '';
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = _mvpEpicNumRegex.firstMatch(releaseDoc.title);
    final int? targetMvpEpicIndex = isAgentReasoned
        ? null
        : (rawTargetEpicIdx != null
            ? int.tryParse(rawTargetEpicIdx)
            : (mvpEpicMatch != null
                ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
                : null));

    final isSubsequentRelease = existingBeats.isNotEmpty ||
        completedReleases.isNotEmpty ||
        versionTag != 'v0.1';
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText = projectDoc.sections['game_spec'] ?? '';
    final techSpecText = projectDoc.sections['tech_spec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ?? '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ?? '';

    final String schemaPhaseHint =
        releasePhase.isNotEmpty ? releasePhase : 'mvp';
    final bool isPhaseLocked =
        releaseDoc.sections['phaseLockedByUser'] == 'true' ||
        releasePhase == ProductionPhase.verticalSlice.name ||
        releasePhase == ProductionPhase.fullProduction.name;

    final String phaseInstruction;
    if (prototypePart == '1' && !isSubsequentRelease) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 1 OF 2 — CONTROLS & PRIMARY MECHANICS): Only plan the first ${(coreLoopItems.length / 2).ceil()} Core Loop Beats in `v0.1` so the developer can prove primary controls and core mechanics first (the remaining Beats are reserved for `v0.2` Prototype Part 2).';
    } else if (prototypePart == '2' ||
        (releasePhase == ProductionPhase.prototype.name &&
            isSubsequentRelease &&
            !isPhaseLocked)) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 2 OF 2 — FULL CORE LOOP): Keep all existing `v0.1` Beats & Features `"lifecycle": "stable"` (0h, empty checkpoints) and add the remaining Stage 1 Core Loop Beats as `"lifecycle": "new"` so the complete greybox loop connects end-to-end.';
    } else if (isAgentReasoned ||
        (releasePhase == ProductionPhase.mvp.name &&
            targetMvpEpicIndex == null)) {
      final phaseTargetDirective = releasePhase ==
              ProductionPhase.verticalSlice.name
          ? '  1. TARGET PHASE IS `"verticalSlice"` (GOLD STANDARD POLISH PASS): Set `"releasePhase": "verticalSlice"` and a descriptive `"releaseTitle"` (`"$versionTag: <Polish & Feel Focus>"`). Focus upgrades on visual/material polish, SFX/VFX & camera/hit-stop feel cues, HUD readability, and state/frame guards across the proven Core Loop Beats.'
          : (releasePhase == ProductionPhase.fullProduction.name
              ? '  1. TARGET PHASE IS `"fullProduction"` (CONTENT & BACKLOG EXPANSION): Set `"releasePhase": "fullProduction"` and a descriptive `"releaseTitle"` (`"$versionTag: <Content & Expansion Focus>"`). Scale content/encounter variety and promote deferred backlog systems while honoring active exclusions.'
              : '  1. Choose `"releasePhase"` (`"mvp"`, `"verticalSlice"`, or `"fullProduction"`) and a specific, descriptive `"releaseTitle"` (`"$versionTag: <Concrete Release Focus>"`):\n'
                  '     * Choose `"mvp"` while any Stage 1 Core Loop Beat is still missing functional mechanics or existing features still need functional depth/interaction to fulfill the Core Loop and Design Pillars.\n'
                  '     * Choose `"verticalSlice"` once all Stage 1 Core Loop Beats are functionally playable end-to-end and the game is ready for a cohesive Polish Pass (final art/material swap, SFX/VFX, camera/hit-stop feel, HUD readability, and state/frame guards).\n'
                  '     * Choose `"fullProduction"` once the Vertical Slice polish pass has already been verified and the focus shifts to scaling content/encounter variety and promoting deferred Out-of-Scope backlog systems.');
      phaseInstruction =
          '- AGENT-REASONED PROGRESSIVE RELEASE ($versionTag): You are the Lead Game Architect deciding what "${projectDoc.title}" needs next in $versionTag by evaluating the Existing Live Game Tree against the Stage 1 Design Pillars, Trade-Offs, Core Loop Beats, and Out-of-Scope Backlog:\n'
          '$phaseTargetDirective\n'
          '  2. Decide which existing Features need an `"upgrade"` vs. which remain `"stable"`, and what `"new"` Features to introduce across ANY of the Core Loop Beats—with zero artificial count limits: include whatever set of `"upgrade"` and `"new"` Features across whichever Beats are required to make $versionTag a complete, cohesive playable milestone.\n'
          '  3. DELTA-ONLY JSON OUTPUT (DO NOT REPEAT STABLE FEATURES): In `beats`, output ONLY the Beats and Features receiving active work in $versionTag (`"lifecycle": "upgrade"` or `"lifecycle": "new"`). Use the exact Beat `id` (e.g. `"beat_1"`) and Feature `id`/`title` from the Existing Live Game Tree when upgrading. Do NOT output untouched `"stable"` features in JSON—all omitted existing Beats and Features are automatically preserved as `STABLE ✓` (`0h`).\n'
          '  4. Strictly enforce the Project Exclusions: NEVER include or promote any feature that violates an Exclusion, even if it was previously queued or requested.';
    } else if (releasePhase == ProductionPhase.mvp.name ||
        targetMvpEpicIndex != null) {
      final epicNum = (targetMvpEpicIndex ?? 0) + 1;
      phaseInstruction =
          '- PHASE 2 PER-EPIC MVP RELEASE (TARGET: EPIC $epicNum ONLY): Upgrade ONLY Beat/Epic #$epicNum from greybox to MVP (`"lifecycle": "upgrade"` with delta MVP checkpoints, plus any queued deferred features for Epic #$epicNum). Keep all other Epics (`!= $epicNum`) strictly `"lifecycle": "stable"` (0h, empty checkpoints).';
    } else if (releasePhase == ProductionPhase.verticalSlice.name ||
        preset == ReleaseScope.verticalSlice) {
      phaseInstruction =
          '- PHASE 3 VERTICAL SLICE (GOLD STANDARD LEVEL): Combine all completed MVP Epics into 1 polished Gold Standard showcase level by upgrading the primary feature in EVERY Beat/Epic (`"lifecycle": "upgrade"`) with a Vertical Slice polish checkpoint (Final Art & Material Swap, SFX/VFX & Camera Feel Cues, HUD Readability & Frame Guard).';
    } else if (releasePhase == ProductionPhase.fullProduction.name ||
        preset == ReleaseScope.fullProduction) {
      phaseInstruction =
          '- PHASE 4 FULL PRODUCTION (CONTENT, LEVELS & DEFERRED SYSTEMS): Bring the rest of the project up to the Vertical Slice bar by upgrading Epics with Content/Level/Wave roster scaling checkpoints (`"lifecycle": "upgrade"`) and promoting previously deferred Out-of-Scope systems into `"lifecycle": "new"` playable features.';
    } else {
      phaseInstruction =
          '- Map each Stage 1 Beat (`BEAT-01..BEAT-${coreLoopItems.length.toString().padLeft(2, '0')}`) 1-to-1 to a Beat entry in `beats`.';
    }

    bool conflictsWithExclusions(String featureTitle) {
      final cleanFeat = featureTitle
          .toLowerCase()
          .replaceFirst(RegExp(r'^no\s+'), '')
          .trim();
      if (cleanFeat.isEmpty) return false;
      for (final ex in projectExclusions) {
        final cleanEx = ex
            .toLowerCase()
            .replaceFirst(RegExp(r'^\[cut\]\s*'), '')
            .replaceFirst(RegExp(r'^no\s+'), '')
            .trim();
        if (cleanEx.isNotEmpty &&
            (cleanEx.contains(cleanFeat) || cleanFeat.contains(cleanEx))) {
          return true;
        }
      }
      return false;
    }

    final existingTreeSummary = StringBuffer();
    if (existingBeats.isNotEmpty) {
      existingTreeSummary
          .writeln('Existing Live Game Tree (completed in prior releases):');
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final b = existingBeats[bIdx];
        existingTreeSummary.writeln('- Beat "${b.title}" (${b.id}):');
        final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
        for (final f in feats) {
          final states = FeatureStateNode.getStatesForDocument(f);
          final originVer = f.sections['originVersion'] ?? 'v0.1';
          final cpSummaries = <String>[];
          final allTuning = <String>{};
          final allFixesAndGuards = <String>{};
          for (final s in states) {
            final taskNames =
                s.checklist.map((t) => t.text).take(4).join(', ');
            cpSummaries.add('${s.releaseVersion} "${s.cleanStageTitle}" [$taskNames]');
            allTuning.addAll(s.tuningParams);
            for (final g in s.edgeCases) {
              allFixesAndGuards.add(g);
            }
          }
          existingTreeSummary.writeln(
            '  * Feature "${f.title}" [id: ${f.id}, origin: $originVer, ${states.length} checkpoints verified: ${cpSummaries.join(' -> ')}]'
            '${allTuning.isNotEmpty ? ' | Live Variables: ${allTuning.take(5).join(', ')}' : ''}'
            '${allFixesAndGuards.isNotEmpty ? ' | Playtest Guards: ${allFixesAndGuards.take(3).join('; ')}' : ''}',
          );
        }
        final queuedDeferred =
            deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[];
        for (final df in queuedDeferred) {
          if (conflictsWithExclusions(df.title)) continue;
          existingTreeSummary.writeln(
            '  * QUEUED FROM PRIOR RELEASE FOR $versionTag: "${df.title}" (${df.estimatedHours}h) — ${df.goal}',
          );
        }
      }
    }

    final numberedCoreLoopSummary = coreLoopItems.isNotEmpty
        ? [
            for (int i = 0; i < coreLoopItems.length; i++)
              '  BEAT-${(i + 1).toString().padLeft(2, '0')}: ${coreLoopItems[i]}',
          ].join('\n')
        : '  (Decompose the project goal into sequential playable loop beats)';

    final projectGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final prompt = '''
You are the Antigravity Release Planner Agent (`gemini-4-argon`) planning Release: "${releaseDoc.title}" ($versionTag, ${preset.label}).
Project: "${projectDoc.title}" | Goal: "$projectGoal"
Game Spec: $gameSpecText | Tech Spec: $techSpecText
Pillars: $pillarsText
Trade-Offs: $tradeOffsText
Exclusions: ${projectExclusions.join(' | ')}

Approved Stage 1 Core Loop Beats (${coreLoopItems.length} Beats):
$numberedCoreLoopSummary
${existingTreeSummary.isNotEmpty ? existingTreeSummary.toString() : 'First Release (v0.1): No prior features exist yet.'}

${GeminiAgentClient.compactStyleRules}
$phaseInstruction
- ARCHITECTURAL DIAGNOSTIC ("builtSoFar" & "missingGaps"):
  * `"builtSoFar"`: List 2–4 concise 2–5 word phrases summarizing the core mechanics already built and verified in prior releases (e.g., `["Slide & Air Strafe", "Rocket & Gib Shatter", "Room Clear & Pedestals"]`).
  * `"missingGaps"`: List 2–4 concise 1-line statements naming the exact playable gaps in the current build prefixed with the Beat tag (e.g., `["E01: No incoming enemy projectiles to dodge while air-strafing", "E02: Missing rapid-fire plasma weapon", "E05: Single room only — no multi-room chain or boss"]`).
  * `"agentReasoning"`: 1–2 concise summary sentences tying the gaps to $versionTag's focus.
- BESPOKE GAME-SPECIFIC STRATEGIC OPTIONS ("questions"): In `questions[0]`, ask 1 architectural priority question for $versionTag with 3 concrete options tailored specifically to "${projectDoc.title}"'s actual mechanics (Option 1 prefixed with `(Recommended)` matching your primary plan; Options 2 and 3 offering distinct, game-specific alternative angles for $versionTag).
- IMPACT-FIRST BUILD ORDER (FASTEST PATH TO PLAYABLE PROGRESS): Order Epics and Features by Playable Developer Impact—start Epic 1 (`beat_1`) with the Core Toy & Primary Control (e.g., Player Movement/Traversal, Vehicle Handling, or Primary Board/Interaction Control), followed by Primary Action & Reactive Targets (Combat, Enemies, Hazards), Loop Closure (Drops, Objectives, Reset), and place Pre-Match Staging/Loadout Prep or Menus later in the loop.
- Break each active Beat into the focused Playable Features (`"included": true`) needed for ${releaseDoc.title} to be genuinely playable on screen (do NOT generate pre-unchecked `"included": false` filler features).
- PLAYABLE BEAT COMPLETENESS (NO ORPHANED MECHANICS): Never leave a weapon, turret, or defense without a reactive enemy/threat/target feature to test it against, and ensure the final Beat covers both the reward/upgrade payoff and continuing or resetting into the next run/route so the prototype loop never dead-ends.
- PLAIN ACTION FEATURE TITLES (NO CODE SUFFIXES): Every Feature must name 1 observable gameplay action (`2–3` plain game-dev words, e.g. `"Truck Steering"`, `"Roof Turret Fire"`, `"Raider Ambush"`, `"Crate Pickup"`). NEVER use code-architecture nouns (`"Controller"`, `"System"`, `"Mechanic"`, `"Manager"`, `"Component"`, `"Handler"`) and NEVER combine two mechanics with `"&"` or `"and"` in a Feature title.
- RIGHT-SIZED GREYBOX FEATURES: Keep individual `v0.1` greybox features focused on unpolished playable functionality buildable in one sitting rather than lumping an entire physics or combat architecture into a single monolithic ticket.
- Keep temporary greybox testbeds in a separate Feature from permanent mechanics.
- FOUNDATION-FIRST, CUMULATIVE TASKS ON ONE SHARED ASSET: Keep each entry in `tasks` a short 2–3 word singular-focused title plus duration tag following a strict Foundation-First build dependency sequence on ONE shared asset:
  * `Task 1` (Foundation / Asset & Component Setup): Create or open the canonical playable asset (`"Character Setup (2h)"` for player movement/control features, or `"Actor Setup (2h)"` for world/combat mechanics), configure its components, and place/possess it in the level. NEVER start `Task 1` with `"Input Mapping"` before a Character/Pawn/Actor exists to attach it to.
  * `Task 2` (Input & Core Mechanic Logic): Bind the Input Action (`IA_...`, `IMC_Default`) or trigger event and wire the core movement/velocity/state logic onto `Task 1`'s asset (e.g., `"Input & Velocity Logic (2h)"`, `"Input Mapping (2h)"`, or `"State Logic (2h)"`).
  * `Task 3` (Physics Tuning, Feel & Guard): Layer physics curves, friction/capsule blends, and edge-case guards onto that same asset (e.g., `"Physics Tuning (2h)"`, `"Friction Tuning (2h)"`, or `"State Guard (1h)"`) — never create duplicate Pawn/Character setup tasks or repeat the Beat/Feature name inside a task title.
- `lifecycle`: `"new"` for v0.1; for v0.2+, output only `"upgrade"` (delta hours/checkpoints only), `"new"`, or `"superseded"` (omit untouched `"stable"` features from JSON).

Return ONLY valid JSON (checkpoints inherit `coveredScope`, `tuningParams`, and `edgeCases` from their Feature automatically):
{
  "releasePhase": "$schemaPhaseHint",
  "releaseTitle": "$versionTag: Concrete Release Focus",
  "builtSoFar": ["Slide & Air Strafe", "Rocket & Gib Shatter", "Room Clear & Pedestals"],
  "missingGaps": ["E01: No incoming enemy fire to dodge", "E02: Missing rapid-fire plasma weapon", "E05: Single room only — no boss room"],
  "agentReasoning": "1-2 concise sentences explaining why these $versionTag features are recommended next.",
  "goal": "Build... goal of ${releaseDoc.title}",
  "doneWhen": "Concrete playtest completion condition",
  "explicitExclusions": ["Excluded mechanic", "..."],
  "questions": [
    {
      "id": "rel_q_1",
      "question": "How should we focus $versionTag for ${projectDoc.title}?",
      "options": ["(Recommended) Specific Focus A: 1-sentence game-specific description", "Specific Focus B: ...", "Specific Focus C: ..."]
    }
  ],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Beat Title",
      "goal": "Literal beat goal",
      "doneWhen": "Literal beat completion criteria",
      "features": [
        {
          "id": "feat_1_1",
          "title": "Plain Feature Title",
          "goal": "Literal feature goal",
          "doneWhen": "Literal feature doneWhen",
          "estimatedHours": 6,
          "included": true,
          "lifecycle": "new",
          "inScope": ["Scope item"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["paramOne: 10.0 m/s"],
          "edgeCases": ["[TAG] Specific edge case behavior"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "tasks": ["Task (2h)"]
            }
          ]
        }
      ]
    }
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
    );

    if (json == null) return null;

    final parsed = _parseDynamicReleaseBlueprint(
      json: json,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      fallbackExclusions: projectExclusions,
    );
    if (parsed == null) return null;

    return reconcileReleaseBlueprintWithPhaseRules(
      parsed: parsed,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      existingBeats: existingBeats,
      existingFeaturesByBeat: existingFeaturesByBeat,
      deferredByBeatIndex: deferredByBeatIndex,
      projectExclusions: projectExclusions,
      allCoreLoopItems: coreLoopItems,
    );
  }

  /// Ensures checkpoint tasks follow a strict Foundation-First progression (`01` Asset/Character Setup ->
  /// `02` Input & Core Logic -> `03` Physics/Tuning/Guards) so a developer never starts with Input Mapping
  /// before creating the Character/Actor it attaches to.
  static List<String> normalizeFoundationFirstTasks(
    List<String> rawTasks, {
    required String featureTitle,
    required String beatTitle,
    bool isFirstFeatureOfRelease = false,
  }) {
    if (rawTasks.length < 2) return rawTasks;
    final tasks = List<String>.from(rawTasks);
    final durationRe = RegExp(r'\(\s*\d+(?:\.\d+)?\s*[hm]\s*\)\s*$');

    bool isPureInputTask(String t) {
      final l = t.toLowerCase();
      return (l.contains('input') || l.contains('mapping') || l.contains('keybind')) &&
          !l.contains('character') &&
          !l.contains('pawn') &&
          !l.contains('actor') &&
          !l.contains('vehicle') &&
          !l.contains('velocity') &&
          !l.contains('physics');
    }

    bool isEntityFoundationTask(String t) {
      final l = t.toLowerCase();
      if (l.contains('character') ||
          l.contains('pawn') ||
          l.contains('actor') ||
          l.contains('player') ||
          l.contains('vehicle') ||
          l.contains('controller') ||
          l.contains('spawner') ||
          l.contains('turret') ||
          l.contains('weapon') ||
          l.contains('hitbox')) {
        return true;
      }
      return l.contains('setup') &&
          !l.contains('input') &&
          !l.contains('mapping') &&
          !l.contains('physics') &&
          !l.contains('velocity') &&
          !l.contains('friction') &&
          !l.contains('animation') &&
          !l.contains('blend');
    }

    if (!isPureInputTask(tasks[0])) {
      return tasks;
    }

    // 1. If a Character/Pawn/Actor setup task was placed at index 1 or 2, move it to index 0 (Task 1)
    final entityTaskIdx = tasks.indexWhere(isEntityFoundationTask);
    if (entityTaskIdx > 0) {
      final foundationTask = tasks.removeAt(entityTaskIdx);
      tasks.insert(0, foundationTask);
      return tasks;
    }

    // 2. Otherwise, if Task 1 is "Input Mapping" and no Character/Actor setup task exists in the list,
    // establish Foundation Setup as Task 1 and merge Input into Task 2 so Task 1 creates the entity first.
    final corpus = '$featureTitle $beatTitle'.toLowerCase();
    final isCharacterFeature = isFirstFeatureOfRelease ||
        corpus.contains('player') ||
        corpus.contains('character') ||
        corpus.contains('pawn') ||
        corpus.contains('sprint') ||
        corpus.contains('slide') ||
        corpus.contains('dash') ||
        corpus.contains('move') ||
        corpus.contains('locomotion') ||
        corpus.contains('traversal') ||
        corpus.contains('parkour') ||
        corpus.contains('jump') ||
        corpus.contains('run');
    final task0Dur = durationRe.firstMatch(tasks[0])?.group(0)?.trim() ?? '(2h)';
    final task1Dur = durationRe.firstMatch(tasks[1])?.group(0)?.trim() ?? '(2h)';
    final task1Core = tasks[1]
        .replaceFirst(durationRe, '')
        .replaceFirst(RegExp(r'\bsetup\b', caseSensitive: false), 'Logic')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    tasks[0] =
        '${isCharacterFeature ? "Character Setup" : "Actor Setup"} $task0Dur';
    if (!task1Core.toLowerCase().contains('input')) {
      tasks[1] = 'Input & $task1Core $task1Dur';
    }
    return tasks;
  }

  static ReleaseBlueprint? _parseDynamicReleaseBlueprint({
    required Map<String, dynamic> json,
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<String> fallbackExclusions,
    bool capV01Checkpoints = true,
  }) {
    final rawBeats = json['beats'];
    if (rawBeats is! List || rawBeats.isEmpty) return null;

    final questions = <AgentQuestion>[];
    final rawQs = json['questions'];
    if (rawQs is List) {
      for (int i = 0; i < rawQs.length; i++) {
        final item = rawQs[i];
        if (item is Map) {
          final qText = (item['question'] ?? '').toString().trim();
          final rawOpts = item['options'];
          final opts = rawOpts is List
              ? rawOpts
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : <String>[];
          if (qText.isNotEmpty && opts.length >= 2) {
            questions.add(
              AgentQuestion(
                id: (item['id'] ?? 'rel_q_${i + 1}').toString(),
                question: qText,
                options: opts,
              ),
            );
          }
        }
      }
    }

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < rawBeats.length; bIdx++) {
      final bMap = rawBeats[bIdx];
      if (bMap is! Map) continue;
      final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
        (bMap['title'] ?? 'Epic ${bIdx + 1}').toString().trim(),
        beatIndex: bIdx,
      );
      final bGoal = (bMap['goal'] ?? '').toString().trim();
      final bDone = (bMap['doneWhen'] ?? '').toString().trim();
      final rawFeats = bMap['features'];
      if (rawFeats is! List || rawFeats.isEmpty) continue;

      final features = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < rawFeats.length; fIdx++) {
        final fMap = rawFeats[fIdx];
        if (fMap is! Map) continue;
        final fTitle = MechanicArchetypeProfile.concreteFeatureTitleForBeat(
          (fMap['title'] ?? 'Feature ${fIdx + 1}').toString().trim(),
          beatTitle: bTitle,
          beatGoal: bGoal,
          beatIndex: bIdx,
        );
        final fGoal = (fMap['goal'] ?? '').toString().trim();
        final fDone = (fMap['doneWhen'] ?? '').toString().trim();

        final rawLifecycle =
            (fMap['lifecycle'] ?? 'new').toString().toLowerCase().trim();
        FeatureLifecycleStatus lifecycle = FeatureLifecycleStatus.newFeature;
        if (rawLifecycle.contains('stable') || rawLifecycle.contains('keep')) {
          lifecycle = FeatureLifecycleStatus.stable;
        } else if (rawLifecycle.contains('upgrade') ||
            rawLifecycle.contains('expand')) {
          lifecycle = FeatureLifecycleStatus.upgrade;
        } else if (rawLifecycle.contains('supersed') ||
            rawLifecycle.contains('archiv')) {
          lifecycle = FeatureLifecycleStatus.superseded;
        }

        final hours = lifecycle == FeatureLifecycleStatus.stable
            ? 0
            : ((fMap['estimatedHours'] is num)
                ? (fMap['estimatedHours'] as num).round().clamp(0, 24)
                : 4);
        final included = lifecycle == FeatureLifecycleStatus.superseded
            ? false
            : (fMap['included'] is bool ? fMap['included'] as bool : true);
        final originVersion =
            (fMap['originVersion'] ?? versionTag).toString().trim();
        final supersedesTitle =
            fMap['supersedesFeatureTitle']?.toString().trim();

        List<String> toStrList(dynamic v) => v is List
            ? v
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];

        final inScope = toStrList(fMap['inScope']);
        final outOfScope = toStrList(fMap['outOfScope']);
        final tuning = toStrList(fMap['tuningParams']);
        final edges = toStrList(fMap['edgeCases']);

        final checkpoints = <ProposedCheckpointBlueprint>[];
        final rawCps = fMap['checkpoints'];
        if (rawCps is List) {
          for (int cIdx = 0; cIdx < rawCps.length; cIdx++) {
            final cMap = rawCps[cIdx];
            if (cMap is! Map) continue;
            final cpTitle =
                (cMap['title'] ?? 'Stage ${cIdx + 1}').toString().trim();
            final cpCriteria = (cMap['playtestCriteria'] ?? fDone)
                .toString()
                .trim();
            final cpVer = versionTag;
            final cpTasks = normalizeFoundationFirstTasks(
              toStrList(cMap['tasks']),
              featureTitle: fTitle,
              beatTitle: bTitle,
              isFirstFeatureOfRelease: bIdx == 0 && fIdx == 0 && cIdx == 0,
            );
            checkpoints.add(
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: cpVer,
                tasks: cpTasks,
                coveredScope: toStrList(cMap['coveredScope']).isNotEmpty
                    ? toStrList(cMap['coveredScope'])
                    : inScope,
                tuningParams: toStrList(cMap['tuningParams']).isNotEmpty
                    ? toStrList(cMap['tuningParams'])
                    : tuning,
                edgeCases: toStrList(cMap['edgeCases']).isNotEmpty
                    ? toStrList(cMap['edgeCases'])
                    : edges,
              ),
            );
          }
        }

        if (capV01Checkpoints && versionTag == 'v0.1' && checkpoints.length > 1) {
          checkpoints.removeRange(1, checkpoints.length);
        }

        features.add(
          ProposedFeatureBlueprint(
            id: (fMap['id'] ?? 'feat_${bIdx + 1}_${fIdx + 1}').toString(),
            title: fTitle,
            goal: fGoal,
            doneWhen: fDone,
            estimatedHours: hours,
            included: included,
            lifecycle: lifecycle,
            originVersion: originVersion.isNotEmpty ? originVersion : versionTag,
            supersedesFeatureTitle:
                (supersedesTitle != null && supersedesTitle.isNotEmpty)
                    ? supersedesTitle
                    : null,
            inScope: inScope,
            outOfScope: outOfScope,
            tuningParams: tuning,
            edgeCases: edges,
            checkpoints: checkpoints,
          ),
        );
      }

      if (features.isNotEmpty) {
        beats.add(
          ProposedBeatBlueprint(
            id: (bMap['id'] ?? 'beat_${bIdx + 1}').toString(),
            title: bTitle,
            goal: bGoal,
            doneWhen: bDone,
            features: features,
          ),
        );
      }
    }

    if (beats.isEmpty) return null;

    final rawEx = json['explicitExclusions'];
    final exclusions = rawEx is List
        ? rawEx
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : fallbackExclusions;
    final rawBuiltSoFar = json['builtSoFar'];
    final builtSoFar = rawBuiltSoFar is List
        ? rawBuiltSoFar
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    final rawMissingGaps = json['missingGaps'];
    final missingGaps = rawMissingGaps is List
        ? rawMissingGaps
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];

    final rawReasoning =
        (json['agentReasoning'] ?? json['lastAgentReply'] ?? '')
            .toString()
            .trim();
    final activeFeatureNames = <String>[
      for (final b in beats)
        for (final f in b.features)
          if (f.included && f.lifecycle != FeatureLifecycleStatus.stable)
            f.title,
    ];
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    var effectivePreset = preset;
    if (isAgentReasoned && releaseDoc.sections['phaseLockedByUser'] != 'true') {
      final currentDocPhase = releaseDoc.sections['phase'] ?? '';
      final rawPhase =
          (json['releasePhase'] ?? json['phase'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      if (rawPhase.contains('full') || rawPhase.contains('production')) {
        releaseDoc.sections['phase'] = ProductionPhase.fullProduction.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.fullProduction.name;
        effectivePreset = ReleaseScope.fullProduction;
      } else if ((rawPhase.contains('vertical') ||
              rawPhase.contains('slice') ||
              rawPhase.contains('polish')) &&
          currentDocPhase != ProductionPhase.fullProduction.name) {
        releaseDoc.sections['phase'] = ProductionPhase.verticalSlice.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.verticalSlice.name;
        effectivePreset = ReleaseScope.verticalSlice;
      } else if (rawPhase.contains('mvp') &&
          currentDocPhase != ProductionPhase.verticalSlice.name &&
          currentDocPhase != ProductionPhase.fullProduction.name) {
        releaseDoc.sections['phase'] = ProductionPhase.mvp.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.mvp.name;
        effectivePreset = ReleaseScope.mvp;
      }
    }
    final rawRelTitle = (json['releaseTitle'] ?? '').toString().trim();
    String effectiveReleaseTitle = releaseDoc.title;
    if (rawRelTitle.isNotEmpty) {
      effectiveReleaseTitle = rawRelTitle.startsWith('$versionTag:')
          ? rawRelTitle
          : '$versionTag: ${rawRelTitle.replaceFirst(RegExp(r'^v\d+\.\d+\s*[:\-–—]?\s*', caseSensitive: false), '')}';
      releaseDoc.title = effectiveReleaseTitle;
    } else if (isAgentReasoned && activeFeatureNames.isNotEmpty) {
      effectiveReleaseTitle =
          '$versionTag: ${activeFeatureNames.take(2).join(' & ')}';
      releaseDoc.title = effectiveReleaseTitle;
    }
    final effectiveReasoning = rawReasoning.isNotEmpty
        ? rawReasoning
        : (activeFeatureNames.isNotEmpty
            ? 'Based on your verified build state and Stage 1 Design Pillars, $versionTag focuses on ${activeFeatureNames.take(3).join(', ')} so the next playable loop milestone connects cleanly.'
            : 'Synthesized $versionTag release plan for $effectiveReleaseTitle.');

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: effectiveReleaseTitle,
      releaseVersionTag: versionTag,
      preset: effectivePreset,
      goal: (json['goal'] ?? '').toString().trim(),
      doneWhen: (json['doneWhen'] ?? '').toString().trim(),
      questions: questions,
      beats: beats,
      explicitExclusions: exclusions,
      builtSoFar: builtSoFar,
      missingGaps: missingGaps,
      lastAgentReply: effectiveReasoning,
    );
  }

  /// Builds an immediate, phase-accurate `ReleaseBlueprint` for `releaseDoc` (`v0.2+`)
  /// from the existing Vault tree before the async `gemini-4-argon` HTTP call completes
  /// (and as a safety net if the network request times out), ensuring `_releaseBlueprint`
  /// never retains a stale prior release (`v0.4`) while planning `v0.5`.
  static ReleaseBlueprint? buildImmediateProgressiveBaselineBlueprint({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
  }) {
    if (existingBeats.isEmpty) return null;
    final preset = releaseDoc.releaseScope;
    final versionTag = extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = releaseDoc.sections['phase'] ?? '';
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = _mvpEpicNumRegex.firstMatch(releaseDoc.title);
    final int? targetMvpEpicIndex = rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : (mvpEpicMatch != null
            ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
            : null);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final eb = existingBeats[bIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final isTargetEpic = targetMvpEpicIndex != null
          ? bIdx == targetMvpEpicIndex
          : (releasePhase == ProductionPhase.verticalSlice.name ||
                  releasePhase == ProductionPhase.fullProduction.name
              ? true
              : bIdx == 0);

      final proposedFeats = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < existingFeats.length; fIdx++) {
        final ef = existingFeats[fIdx];
        final shouldUpgrade = isTargetEpic &&
            (targetMvpEpicIndex != null || fIdx == 0);
        if (shouldUpgrade) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal:
                  'Upgrade ${ef.title} for $versionTag (${releaseDoc.title}).',
              doneWhen:
                  'Playtester verifies the $versionTag ${ef.title} upgrade in the level.',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.upgrade,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const ['responseMultiplier: 1.25x'],
              edgeCases: const ['[STATE GUARD] Verify clean transition in playtest'],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: '${ef.title} ($versionTag Upgrade)',
                  playtestCriteria:
                      'Trigger ${ef.title} -> verify $versionTag upgrade behavior',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Actor Setup (2h)',
                    'State Logic (1h)',
                    'State Guard (1h)',
                  ],
                ),
              ],
            ),
          );
        } else {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: true,
              lifecycle: FeatureLifecycleStatus.stable,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
        }
      }

      final deferredList = deferredByBeatIndex[bIdx];
      if (deferredList != null) {
        for (final defFeat in deferredList) {
          defFeat.included = true;
          defFeat.lifecycle = FeatureLifecycleStatus.newFeature;
          defFeat.originVersion = versionTag;
          proposedFeats.add(defFeat);
        }
      }

      beats.add(
        ProposedBeatBlueprint(
          id: eb.id,
          title: eb.title,
          goal: SectionTextUtils.resolveGoal(eb.sections),
          doneWhen: SectionTextUtils.resolveDoneWhen(eb.sections),
          features: proposedFeats,
        ),
      );
    }

    final relGoal = SectionTextUtils.resolveGoal(releaseDoc.sections);
    final relDone = SectionTextUtils.resolveDoneWhen(releaseDoc.sections);
    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: relGoal.isNotEmpty
          ? relGoal
          : 'Build and verify $versionTag (${releaseDoc.title}).',
      doneWhen: relDone.isNotEmpty
          ? relDone
          : 'All $versionTag active features pass playtest verification.',
      questions: const [],
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Analyzing your completed release tree, tuning variables, and Stage 1 Design Pillars to recommend the highest-impact $versionTag scope...',
    );
  }

  /// Reconciles a live LLM `ReleaseBlueprint` against existing Vault Beat/Feature IDs
  /// so upgrades in `v0.2+` attach to existing feature documents in-place without duplication.
  static ReleaseBlueprint reconcileReleaseBlueprintWithPhaseRules({
    required ReleaseBlueprint parsed,
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
    required List<String> projectExclusions,
    required List<String> allCoreLoopItems,
  }) {
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final isSubsequentRelease =
        existingBeats.isNotEmpty || versionTag != 'v0.1';

    if (!isSubsequentRelease) {
      if (prototypePart == '1' && allCoreLoopItems.length >= 2) {
        final halfCount = (allCoreLoopItems.length / 2).ceil();
        if (parsed.beats.length > halfCount) {
          return ReleaseBlueprint(
            releaseDocId: parsed.releaseDocId,
            releaseTitle: parsed.releaseTitle,
            releaseVersionTag: parsed.releaseVersionTag,
            preset: parsed.preset,
            goal: parsed.goal,
            doneWhen: parsed.doneWhen,
            questions: parsed.questions,
            beats: parsed.beats.take(halfCount).toList(),
            explicitExclusions: parsed.explicitExclusions,
          );
        }
      }
      return parsed;
    }

    if (existingBeats.isEmpty) return parsed;

    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final matchedLlmBeatByExistingId = <String, ProposedBeatBlueprint>{};
    final unmatchedNewLlmBeats = <ProposedBeatBlueprint>[];

    for (int bIdx = 0; bIdx < parsed.beats.length; bIdx++) {
      final llmBeat = parsed.beats[bIdx];
      final cleanLlmTitle = llmBeat.title.toLowerCase().trim();
      TierDocument? matchedBeatDoc;

      // 1. Exact ID or exact title match
      for (final eb in existingBeats) {
        if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
        if (eb.id == llmBeat.id ||
            eb.title.toLowerCase().trim() == cleanLlmTitle) {
          matchedBeatDoc = eb;
          break;
        }
      }
      // 2. Substring title match
      if (matchedBeatDoc == null && cleanLlmTitle.isNotEmpty) {
        for (final eb in existingBeats) {
          if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
          final cleanEbTitle = eb.title.toLowerCase().trim();
          if (cleanEbTitle.contains(cleanLlmTitle) ||
              cleanLlmTitle.contains(cleanEbTitle)) {
            matchedBeatDoc = eb;
            break;
          }
        }
      }
      // 3. Positional fallback only when all existing beats were returned in full
      if (matchedBeatDoc == null &&
          parsed.beats.length == existingBeats.length &&
          bIdx < existingBeats.length &&
          !matchedLlmBeatByExistingId.containsKey(existingBeats[bIdx].id)) {
        matchedBeatDoc = existingBeats[bIdx];
      }

      if (matchedBeatDoc != null) {
        matchedLlmBeatByExistingId[matchedBeatDoc.id] = llmBeat;
      } else {
        unmatchedNewLlmBeats.add(llmBeat);
      }
    }

    final reconciledBeats = <ProposedBeatBlueprint>[];
    for (int ebIdx = 0; ebIdx < existingBeats.length; ebIdx++) {
      final eb = existingBeats[ebIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final llmBeat = matchedLlmBeatByExistingId[eb.id] ??
          ProposedBeatBlueprint(
            id: eb.id,
            title: eb.title,
            goal: SectionTextUtils.resolveGoal(eb.sections),
            doneWhen: SectionTextUtils.resolveDoneWhen(eb.sections),
            features: <ProposedFeatureBlueprint>[],
          );

      llmBeat.id = eb.id;
      final matchedByExistingId = <String, ProposedFeatureBlueprint>{};
      final unmatchedNewFeats = <ProposedFeatureBlueprint>[];
      final cleanVer = versionTag.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      for (int fIdx = 0; fIdx < llmBeat.features.length; fIdx++) {
        final lf = llmBeat.features[fIdx];
        final normLfTitle = lf.title.toLowerCase().trim();
        TierDocument? matchedEf;
        for (final ef in existingFeats) {
          if (matchedByExistingId.containsKey(ef.id)) continue;
          final normEfTitle = ef.title.toLowerCase().trim();
          final titleMatches =
              normEfTitle.isNotEmpty && normEfTitle == normLfTitle;
          final idMatchesNonNew =
              lf.lifecycle != FeatureLifecycleStatus.newFeature &&
              ef.id == lf.id;
          if (titleMatches || idMatchesNonNew) {
            matchedEf = ef;
            break;
          }
        }
        if (matchedEf != null) {
          lf.id = matchedEf.id;
          lf.originVersion = matchedEf.sections['originVersion'] ?? 'v0.1';
          matchedByExistingId[matchedEf.id] = lf;
        } else {
          final existingIdCollision = existingFeats.any((e) => e.id == lf.id) ||
              lf.id.startsWith('feat_1_') ||
              lf.id.startsWith('feat_2_') ||
              lf.id.startsWith('feat_3_') ||
              lf.id.startsWith('feat_4_') ||
              lf.id.startsWith('feat_5_');
          if (existingIdCollision || lf.id.trim().isEmpty) {
            lf.id =
                'feat_${eb.id}_${cleanVer}_new_${unmatchedNewFeats.length + 1}';
          }
          unmatchedNewFeats.add(lf);
        }
      }

      // Preserve canonical existing feature order first (UPGRADE or STABLE ✓), followed by genuinely NEW features
      final orderedFeatures = <ProposedFeatureBlueprint>[];
      for (final ef in existingFeats) {
        final matchedLf = matchedByExistingId[ef.id];
        if (matchedLf != null) {
          orderedFeatures.add(matchedLf);
        } else {
          orderedFeatures.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: true,
              lifecycle: FeatureLifecycleStatus.stable,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
        }
      }
      orderedFeatures.addAll(unmatchedNewFeats);
      llmBeat.features = orderedFeatures;

      final deferredList = deferredByBeatIndex[ebIdx];
      if (!isAgentReasoned && deferredList != null && deferredList.isNotEmpty) {
        final combinedExclusions = <String>{
          ...projectExclusions,
          ...parsed.explicitExclusions,
        };
        for (final defFeat in deferredList) {
          final cleanDef = defFeat.title
              .toLowerCase()
              .replaceFirst(RegExp(r'^no\s+'), '')
              .trim();
          final isExcluded = combinedExclusions.any((ex) {
            final cleanEx = ex
                .toLowerCase()
                .replaceFirst(RegExp(r'^\[cut\]\s*'), '')
                .replaceFirst(RegExp(r'^no\s+'), '')
                .trim();
            return cleanEx.isNotEmpty &&
                cleanDef.isNotEmpty &&
                (cleanEx.contains(cleanDef) || cleanDef.contains(cleanEx));
          });
          if (isExcluded) continue;
          final alreadyPresent = llmBeat.features.any(
            (f) =>
                f.id == defFeat.id ||
                f.title.toLowerCase().trim() ==
                    defFeat.title.toLowerCase().trim(),
          );
          if (!alreadyPresent) {
            defFeat.included = true;
            defFeat.lifecycle = FeatureLifecycleStatus.newFeature;
            defFeat.originVersion = versionTag;
            llmBeat.features.add(defFeat);
          }
        }
      }

      reconciledBeats.add(llmBeat);
    }

    reconciledBeats.addAll(unmatchedNewLlmBeats);
    parsed.beats = reconciledBeats;

    return parsed;
  }

  /// Turn-by-turn Release Plan Gate Chat: Takes the user's message, updates
  /// the live `ReleaseBlueprint` in place via Gemini AI, and sets `lastAgentReply`.
  /// Returns `false` if offline or if Gemini AI cannot be reached.
  static Future<bool> sendReleasePlanChatTurn({
    required ReleaseBlueprint blueprint,
    required String userMessage,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

    final currentBeatsSummary = blueprint.beats
        .map(
          (b) => '- ${b.id} "${b.title}" (${b.goal}): '
              '${b.features.map((f) => '"${f.title}" [${f.included ? "IN" : "DEFERRED"}, ${f.activeDeltaHours}h]').join(', ')}',
        )
        .join('\n');

    final prompt = '''
You are the Antigravity Release Planner Agent updating "${blueprint.releaseTitle}" (${blueprint.releaseVersionTag}).
Current Plan:
- Goal: "${blueprint.goal}"
- Done When: "${blueprint.doneWhen}"
- Exclusions: ${blueprint.explicitExclusions.join(', ')}
- Beats:
$currentBeatsSummary

Developer Request: "$cleanMsg"
${GeminiAgentClient.compactStyleRules}
- DELTA-ONLY BEATS: In `beats`, return ONLY the specific Beat(s) that were modified or added by the developer's request (untouched Beats are preserved automatically).

Return ONLY valid JSON:
{
  "reply": "1-2 sentence confirmation of the changes made",
  "goal": "Updated release goal (or existing if unchanged)",
  "doneWhen": "Updated release doneWhen (or existing if unchanged)",
  "explicitExclusions": ["Exclusion 1", "Exclusion 2"],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Beat Title",
      "goal": "1-sentence literal beat goal",
      "doneWhen": "1-sentence literal beat completion criteria",
      "features": [
        {
          "id": "feat_1_1",
          "title": "Plain Feature Title",
          "goal": "1-sentence literal feature goal",
          "doneWhen": "1-sentence literal feature doneWhen",
          "estimatedHours": 6,
          "included": true,
          "lifecycle": "new",
          "inScope": ["Scope item"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["paramOne: 10.0 m/s"],
          "edgeCases": ["[TAG] Specific edge case behavior"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "tasks": ["Task 1 (2h)", "Task 2 (2h)"]
            }
          ]
        }
      ]
    }
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
    );

    if (json == null) return false;

    final dummyDoc = TierDocument(
      id: blueprint.releaseDocId,
      title: blueprint.releaseTitle,
      tier: TierType.release,
    );
    final updatedBp = _parseDynamicReleaseBlueprint(
      json: json,
      releaseDoc: dummyDoc,
      preset: blueprint.preset,
      versionTag: blueprint.releaseVersionTag,
      fallbackExclusions: blueprint.explicitExclusions,
      capV01Checkpoints: false,
    );
    if (updatedBp == null) return false;

    if (updatedBp.goal.isNotEmpty) blueprint.goal = updatedBp.goal;
    if (updatedBp.doneWhen.isNotEmpty) blueprint.doneWhen = updatedBp.doneWhen;
    final mergedBeats = List<ProposedBeatBlueprint>.from(blueprint.beats);
    for (final deltaBeat in updatedBp.beats) {
      final idx = mergedBeats.indexWhere(
        (b) =>
            b.id == deltaBeat.id ||
            b.title.toLowerCase().trim() ==
                deltaBeat.title.toLowerCase().trim(),
      );
      if (idx != -1) {
        mergedBeats[idx] = deltaBeat;
      } else {
        mergedBeats.add(deltaBeat);
      }
    }
    blueprint.beats = mergedBeats;
    blueprint.explicitExclusions = updatedBp.explicitExclusions;
    final reply = json['reply']?.toString().trim() ??
        'Updated the Release Plan Blueprint with your changes!';
    blueprint.lastAgentReply = reply;
    return true;
  }
}

/// Stage 3 Executor Agent: Takes the user-approved `ReleaseBlueprint` from the
/// Confirmation Gate and constructs or evolves the active Release hierarchy:
/// - Non-destructively merges existing Core Loop Beats & Features so completed
///   checkpoints from `v0.1` remain intact when re-planning or evolving to `v0.2+`.
/// - Stamps newly added Checkpoints (`FeatureStateNode`) with `releaseVersion`.
class ReleaseExecutorAgent {
  static final RegExp _bulletStripRegex = RegExp(r'^[•\-\*\s]+');
  static final RegExp _recommendedPrefixRegex = RegExp(r'^\(Recommended\)\s*');
  static Future<List<TierDocument>> executeBlueprint({
    required TierDocument releaseDoc,
    required ReleaseBlueprint blueprint,
    Map<String, TierDocument> existingDocuments = const {},
    void Function(String stepMessage)? onProgress,
  }) async {
    final createdOrUpdatedDocs = <TierDocument>[];
    final beatTitles = <String>[];
    final versionTag = blueprint.releaseVersionTag;

    onProgress?.call(
      'Locking in ${blueprint.releaseTitle} ($versionTag) scope & exclusions...',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final isInitialPrototypeRelease = versionTag == 'v0.1' &&
        (releaseDoc.sections['prototypePart'] ?? '') != '2';

    final validReleaseIds = <String>{releaseDoc.id};
    final parentProjId = releaseDoc.parentId;
    if (parentProjId != null) {
      final projDoc = existingDocuments[parentProjId];
      if (projDoc != null) {
        validReleaseIds.addAll(projDoc.childrenIds);
      }
      for (final doc in existingDocuments.values) {
        if (doc.tier == TierType.release && doc.parentId == parentProjId) {
          validReleaseIds.add(doc.id);
        }
      }
    }
    final validBeatIds = <String>{};
    for (final relId in validReleaseIds) {
      final rDoc = existingDocuments[relId];
      if (rDoc != null) {
        validBeatIds.addAll(rDoc.childrenIds);
      }
    }
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic &&
          doc.parentId != null &&
          validReleaseIds.contains(doc.parentId)) {
        validBeatIds.add(doc.id);
      }
    }

    final projectScopedDocs = <String, TierDocument>{};
    final existingBeatsByTitle = <String, TierDocument>{};
    final existingFeaturesByTitle = <String, TierDocument>{};
    final existingFeaturesByBeatAndTitle = <String, TierDocument>{};
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic && validBeatIds.contains(doc.id)) {
        projectScopedDocs[doc.id] = doc;
        existingBeatsByTitle[doc.title.toLowerCase().trim()] = doc;
      } else if (doc.tier == TierType.feature &&
          doc.parentId != null &&
          validBeatIds.contains(doc.parentId)) {
        projectScopedDocs[doc.id] = doc;
        final normTitle = doc.title.toLowerCase().trim();
        existingFeaturesByTitle[normTitle] = doc;
        existingFeaturesByBeatAndTitle['${doc.parentId}::$normTitle'] = doc;
      }
    }

    releaseDoc.childrenIds.clear();

    for (int bIdx = 0; bIdx < blueprint.beats.length; bIdx++) {
      final beatBp = blueprint.beats[bIdx];
      final includedFeats = beatBp.includedFeatures;
      if (includedFeats.isEmpty) continue;

      final concreteBeatTitle =
          MechanicArchetypeProfile.concreteBeatDisplayTitle(
        beatBp.title,
        beatIndex: bIdx,
      );
      beatTitles.add(concreteBeatTitle);
      onProgress?.call(
        'Syncing Core Loop Epic ${bIdx + 1}: $concreteBeatTitle...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final existingBeat = projectScopedDocs[beatBp.id] ??
          existingBeatsByTitle[concreteBeatTitle.toLowerCase().trim()] ??
          existingBeatsByTitle[beatBp.title.toLowerCase().trim()];
      final beatId = existingBeat?.id ?? 'epic_${releaseDoc.id}_${bIdx + 1}';

      final featTitlesForBeat = includedFeats
          .map(
            (f) =>
                '• ${MechanicArchetypeProfile.concreteFeatureTitleForBeat(f.title, beatTitle: concreteBeatTitle, beatGoal: beatBp.goal, beatIndex: bIdx)}: ${f.goal}',
          )
          .join('\n');
      final deferredForBeat =
          beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

      final beatDoc = existingBeat ??
          TierDocument(
            id: beatId,
            title: concreteBeatTitle,
            tier: TierType.epic,
            parentId: releaseDoc.id,
          );
      beatDoc.title = concreteBeatTitle;
      beatDoc.parentId = releaseDoc.id;
      beatDoc.estimatedDuration = '${beatBp.totalIncludedHours}h';
      beatDoc.sections['scope'] = 'Goal: ${beatBp.goal}\n\n'
          'In Scope:\n$featTitlesForBeat\n\n'
          '${deferredForBeat.isNotEmpty ? 'Out of Scope:\n$deferredForBeat\n\n' : ''}'
          'Done When: ${beatBp.doneWhen}';
      beatDoc.childrenIds.clear();

      releaseDoc.childrenIds.add(beatDoc.id);
      createdOrUpdatedDocs.add(beatDoc);

      for (final supFeat in beatBp.features.where(
        (f) => f.lifecycle == FeatureLifecycleStatus.superseded,
      )) {
        final existingSup = projectScopedDocs[supFeat.id] ??
            existingFeaturesByTitle[supFeat.title.toLowerCase().trim()];
        if (existingSup != null) {
          existingSup.sections['lifecycle'] =
              FeatureLifecycleStatus.superseded.name;
          existingSup.sections['supersededByRelease'] = versionTag;
          createdOrUpdatedDocs.add(existingSup);
        }
      }

      final allocatedFeatIds = <String>{};
      for (int fIdx = 0; fIdx < includedFeats.length; fIdx++) {
        final featBp = includedFeats[fIdx];
        onProgress?.call(
          'Syncing Build Tasks, Tuning & Guards for "${featBp.title}"...',
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        if (featBp.supersedesFeatureTitle != null) {
          final oldDoc = existingFeaturesByTitle[
              featBp.supersedesFeatureTitle!.toLowerCase().trim()];
          if (oldDoc != null) {
            oldDoc.sections['lifecycle'] =
                FeatureLifecycleStatus.superseded.name;
            oldDoc.sections['supersededByRelease'] = versionTag;
            oldDoc.sections['supersededByFeature'] = featBp.title;
            createdOrUpdatedDocs.add(oldDoc);
          }
        }

        final concreteFeatTitle =
            MechanicArchetypeProfile.concreteFeatureTitleForBeat(
          featBp.title,
          beatTitle: beatBp.title,
          beatGoal: beatBp.goal,
          beatIndex: bIdx,
        );
        final normConcreteTitle = concreteFeatTitle.toLowerCase().trim();
        final normRawTitle = featBp.title.toLowerCase().trim();
        final candidateById = projectScopedDocs[featBp.id];
        final canMatchById = candidateById != null &&
            !allocatedFeatIds.contains(candidateById.id) &&
            (candidateById.parentId == null ||
                candidateById.parentId == beatDoc.id) &&
            (featBp.lifecycle != FeatureLifecycleStatus.newFeature ||
                candidateById.title.toLowerCase().trim() == normConcreteTitle ||
                candidateById.title.toLowerCase().trim() == normRawTitle);
        final candidateByTitle =
            existingFeaturesByBeatAndTitle['${beatDoc.id}::$normConcreteTitle'] ??
                existingFeaturesByBeatAndTitle['${beatDoc.id}::$normRawTitle'];
        final existingFeat = canMatchById
            ? candidateById
            : (candidateByTitle != null &&
                    !allocatedFeatIds.contains(candidateByTitle.id)
                ? candidateByTitle
                : null);

        String featId;
        if (existingFeat != null) {
          featId = existingFeat.id;
        } else {
          final defaultId = 'feat_${beatId}_${fIdx + 1}';
          if (!existingDocuments.containsKey(defaultId) &&
              !projectScopedDocs.containsKey(defaultId) &&
              !allocatedFeatIds.contains(defaultId)) {
            featId = defaultId;
          } else {
            final cleanVer =
                versionTag.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
            int seq = fIdx + 1;
            String candidateId = 'feat_${beatId}_${cleanVer}_$seq';
            while (existingDocuments.containsKey(candidateId) ||
                projectScopedDocs.containsKey(candidateId) ||
                allocatedFeatIds.contains(candidateId)) {
              seq++;
              candidateId = 'feat_${beatId}_${cleanVer}_$seq';
            }
            featId = candidateId;
          }
        }
        allocatedFeatIds.add(featId);
        featBp.id = featId;

        if (!isInitialPrototypeRelease &&
            featBp.lifecycle == FeatureLifecycleStatus.stable &&
            existingFeat != null) {
          existingFeat.parentId = beatDoc.id;
          existingFeat.sections['lifecycle'] =
              FeatureLifecycleStatus.stable.name;
          existingFeat.sections['activeReleaseVersion'] = versionTag;
          existingFeat.sections['lastVerifiedVersion'] =
              existingFeat.sections['originVersion'] ?? 'v0.1';
          final stableStates =
              FeatureStateNode.getStatesForDocument(existingFeat);
          if (stableStates.isNotEmpty) {
            for (final s in stableStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final c in t.children) {
                  c.completed = true;
                }
              }
            }
            FeatureStateNode.saveStatesToDocument(existingFeat, stableStates);
          }
          if (!beatDoc.childrenIds.contains(existingFeat.id)) {
            beatDoc.childrenIds.add(existingFeat.id);
          }
          createdOrUpdatedDocs.add(existingFeat);
          continue;
        }

        final existingStates =
            (!isInitialPrototypeRelease && existingFeat != null)
                ? FeatureStateNode.getStatesForDocument(existingFeat)
                    .where((s) => s.releaseVersion != versionTag)
                    .toList()
                : <FeatureStateNode>[];
        if (existingStates.isNotEmpty) {
          for (final s in existingStates) {
            for (final t in s.checklist) {
              t.completed = true;
              for (final c in t.children) {
                c.completed = true;
              }
            }
          }
        }

        final mergedInScope = <String>{
          if (existingFeat != null)
            ...SectionTextUtils.resolveInScope(existingFeat.sections),
          ...featBp.inScope,
        }.toList();

        final mergedOutScope = <String>{
          ...featBp.outOfScope,
        }.toList();

        final existingTuning = existingFeat != null
            ? (existingFeat.sections['tuning'] ?? '')
                .split('\n')
                .map((s) => s.replaceFirst(_bulletStripRegex, '').trim())
                .where((s) => s.isNotEmpty)
            : const Iterable<String>.empty();
        final mergedTuning = <String>{
          ...existingTuning,
          ...featBp.tuningParams,
        }.toList();

        final existingEdges = existingFeat != null
            ? (existingFeat.sections['edge_cases'] ?? '')
                .split('\n')
                .map((s) => s.replaceFirst(_bulletStripRegex, '').trim())
                .where((s) => s.isNotEmpty)
            : const Iterable<String>.empty();
        final mergedEdges = <String>{
          ...existingEdges,
          ...featBp.edgeCases,
        }.toList();

        final inScopeText = mergedInScope.map((s) => '• $s').join('\n');
        final outScopeText = mergedOutScope.map((s) => '• $s').join('\n');
        final tuningText = mergedTuning.map((t) => '• $t').join('\n');
        final edgeText = mergedEdges.map((e) => '• $e').join('\n');

        final originVer = existingFeat?.sections['originVersion'] ??
            (featBp.originVersion.isNotEmpty
                ? featBp.originVersion
                : versionTag);
        final resolvedLifecycle = existingFeat != null &&
                featBp.lifecycle == FeatureLifecycleStatus.newFeature &&
                existingStates.isNotEmpty
            ? FeatureLifecycleStatus.upgrade
            : featBp.lifecycle;

        final featDoc = existingFeat ??
            TierDocument(
              id: featId,
              title: concreteFeatTitle,
              tier: TierType.feature,
              parentId: beatDoc.id,
            );

        featDoc.title = concreteFeatTitle;
        featDoc.parentId = beatDoc.id;
        featDoc.estimatedDuration = '${featBp.activeDeltaHours}h';
        featDoc.sections['originVersion'] = originVer;
        featDoc.sections['activeReleaseVersion'] = versionTag;
        featDoc.sections['lifecycle'] = resolvedLifecycle.name;
        featDoc.sections['scope'] = 'Goal: ${featBp.goal}\n\n'
            'In Scope:\n$inScopeText\n\n'
            '${outScopeText.isNotEmpty ? 'Out of Scope:\n$outScopeText\n\n' : ''}'
            'Done When: ${featBp.doneWhen}';
        featDoc.sections['variables'] = tuningText;
        featDoc.sections['tuning'] = tuningText;
        featDoc.sections['edge_cases'] = edgeText;

        final stateNodes = <FeatureStateNode>[
          ...existingStates,
        ];
        final existingSameVerCpTitles = existingStates
            .where((s) => s.releaseVersion == versionTag)
            .map((s) => s.cleanStageTitle.toLowerCase().trim())
            .toSet();

        final effectiveCheckpoints = featBp.checkpoints.isNotEmpty
            ? featBp.checkpoints
            : <ProposedCheckpointBlueprint>[
                ProposedCheckpointBlueprint(
                  title: '$concreteFeatTitle ($versionTag)',
                  playtestCriteria: featBp.doneWhen.isNotEmpty
                      ? featBp.doneWhen
                      : 'Trigger $concreteFeatTitle -> verify $versionTag behavior in playtest',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Actor Setup (2h)',
                    'State Logic (1h)',
                    'State Guard (1h)',
                  ],
                  coveredScope: featBp.inScope,
                  tuningParams: featBp.tuningParams,
                  edgeCases: featBp.edgeCases,
                ),
              ];

        for (int cIdx = 0; cIdx < effectiveCheckpoints.length; cIdx++) {
          final cpBp = effectiveCheckpoints[cIdx];
          if (existingSameVerCpTitles
              .contains(cpBp.title.toLowerCase().trim())) {
            continue;
          }
          final nextOrder = stateNodes.length;
          final cpNumber = nextOrder + 1;
          final effectiveTasks = cpBp.tasks.isNotEmpty
              ? cpBp.tasks
              : const [
                  'Actor Setup (2h)',
                  'State Logic (1h)',
                  'State Guard (1h)',
                ];
          final checklist = <Subtask>[
            for (int tIdx = 0; tIdx < effectiveTasks.length; tIdx++)
              Subtask(
                id: '${featId}_${versionTag}_cp${cpNumber}_t${tIdx + 1}',
                text: effectiveTasks[tIdx],
                completed: false,
              ),
          ];

          stateNodes.add(
            FeatureStateNode(
              id: '${featId}_${versionTag}_cp_$cpNumber',
              name: 'Checkpoint $cpNumber: ${cpBp.title}',
              trigger: 'Playtest: ${cpBp.playtestCriteria}',
              order: nextOrder,
              checklist: checklist,
              coveredScope: List<String>.from(cpBp.coveredScope),
              tuningParams: List<String>.from(cpBp.tuningParams),
              edgeCases: List<String>.from(cpBp.edgeCases),
              parameters: {
                'releaseVersion': versionTag,
              },
            ),
          );
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        if (!beatDoc.childrenIds.contains(featDoc.id)) {
          beatDoc.childrenIds.add(featDoc.id);
        }
        createdOrUpdatedDocs.add(featDoc);
      }
    }

    final focusAnswer = blueprint.questions.isNotEmpty
        ? blueprint.questions.first.effectiveAnswer
            .replaceFirst(_recommendedPrefixRegex, '')
        : '';
    final effectiveGoal = focusAnswer.isNotEmpty
        ? '${blueprint.goal} (Playtest Focus: $focusAnswer)'
        : blueprint.goal;

    final inScopeBeats = beatTitles.map((t) => '• $t').join('\n');
    final outScopeItems =
        blueprint.effectiveOutOfScope.map((o) => '• $o').join('\n');

    releaseDoc.title = blueprint.releaseTitle;
    releaseDoc.sections['releaseScope'] = blueprint.preset.name;
    releaseDoc.sections['versionTag'] = versionTag;
    releaseDoc.sections['release_blueprint_json'] =
        jsonEncode(blueprint.toJson());
    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['scope'] = 'Goal: $effectiveGoal\n\n'
        'In Scope:\n$inScopeBeats\n\n'
        'Out of Scope:\n$outScopeItems\n\n'
        'Done When: ${blueprint.doneWhen}';

    onProgress?.call(
      'Release ${blueprint.releaseTitle} ready for development!',
    );
    return createdOrUpdatedDocs;
  }
}

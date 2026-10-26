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
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = RegExp(r'MVP Epic\s*(\d+)', caseSensitive: false)
        .firstMatch(releaseDoc.title);
    final int? targetMvpEpicIndex = rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : (mvpEpicMatch != null
            ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
            : null);

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

    final String phaseInstruction;
    if (prototypePart == '1' && !isSubsequentRelease) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 1 OF 2 — CONTROLS & PRIMARY MECHANICS): Only plan the first ${(coreLoopItems.length / 2).ceil()} Core Loop Beats in `v0.1` so the developer can prove primary controls and core mechanics first (the remaining Beats are reserved for `v0.2` Prototype Part 2).';
    } else if (prototypePart == '2' ||
        (releasePhase == ProductionPhase.prototype.name &&
            isSubsequentRelease)) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 2 OF 2 — FULL CORE LOOP): Keep all existing `v0.1` Beats & Features `"lifecycle": "stable"` (0h, empty checkpoints) and add the remaining Stage 1 Core Loop Beats as `"lifecycle": "new"` so the complete greybox loop connects end-to-end.';
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

    final existingTreeSummary = StringBuffer();
    if (existingBeats.isNotEmpty) {
      existingTreeSummary
          .writeln('Existing Live Game Tree (from prior release):');
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final b = existingBeats[bIdx];
        existingTreeSummary.writeln('- Beat "${b.title}" (${b.id}):');
        final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
        for (final f in feats) {
          final states = FeatureStateNode.getStatesForDocument(f);
          final originVer = f.sections['originVersion'] ?? 'v0.1';
          existingTreeSummary.writeln(
            '  * Feature "${f.title}" [id: ${f.id}, origin: $originVer, ${states.length} checkpoints verified]',
          );
        }
        final queuedDeferred =
            deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[];
        for (final df in queuedDeferred) {
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
- IMPACT-FIRST BUILD ORDER (FASTEST PATH TO PLAYABLE PROGRESS): Order Epics and Features by Playable Developer Impact—start Epic 1 (`beat_1`) with the Core Toy & Primary Control (e.g., Player Movement/Traversal, Vehicle Handling, or Primary Board/Interaction Control), followed by Primary Action & Reactive Targets (Combat, Enemies, Hazards), Loop Closure (Drops, Objectives, Reset), and place Pre-Match Staging/Loadout Prep or Menus later in the loop.
- Under each active Beat, generate `1–2` Singular-Focused Playable Features (`"included": true`) needed for ${releaseDoc.title} (do NOT generate pre-unchecked `"included": false` filler features).
- SINGULAR-FOCUSED FEATURE TITLES: Every Feature must represent 1 concrete mechanic (`2–3` plain game-dev words). NEVER combine two mechanics with `"&"` or `"and"` in a Feature title.
- Keep temporary greybox testbeds in a separate Feature from permanent mechanics.
- SINGULAR-FOCUSED TASKS: Keep each entry in `tasks` a short 2–3 word singular-focused title plus duration tag (e.g. `"Actor Setup (2h)"`, `"State Logic (2h)"`, `"State Guard (1h)"`) — never write a full sentence or repeat the Beat/Feature name inside a task title.
- `lifecycle`: `"new"` for v0.1; for v0.2+, use `"stable"` (0h, empty checkpoints), `"upgrade"` (delta hours/checkpoints only), `"new"`, or `"superseded"`.

Return ONLY valid JSON (checkpoints inherit `coveredScope`, `tuningParams`, and `edgeCases` from their Feature automatically):
{
  "goal": "Build... goal of ${releaseDoc.title}",
  "doneWhen": "Concrete playtest completion condition",
  "explicitExclusions": ["Excluded mechanic", "..."],
  "questions": [
    {
      "id": "rel_q_1",
      "question": "Release priority question?",
      "options": ["(Recommended) Title: 1-sentence description", "Title 2: ...", "Title 3: ..."]
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
      final bTitle = (bMap['title'] ?? 'Epic ${bIdx + 1}').toString().trim();
      final bGoal = (bMap['goal'] ?? '').toString().trim();
      final bDone = (bMap['doneWhen'] ?? '').toString().trim();
      final rawFeats = bMap['features'];
      if (rawFeats is! List || rawFeats.isEmpty) continue;

      final features = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < rawFeats.length; fIdx++) {
        final fMap = rawFeats[fIdx];
        if (fMap is! Map) continue;
        final fTitle =
            (fMap['title'] ?? 'Feature ${fIdx + 1}').toString().trim();
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
            final cpVer =
                (cMap['releaseVersion'] ?? versionTag).toString().trim();
            final cpTasks = toStrList(cMap['tasks']);
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

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: (json['goal'] ?? '').toString().trim(),
      doneWhen: (json['doneWhen'] ?? '').toString().trim(),
      questions: questions,
      beats: beats,
      explicitExclusions: exclusions,
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

    // Bind existing Beat/Feature Vault IDs where titles or IDs match
    for (int bIdx = 0; bIdx < parsed.beats.length; bIdx++) {
      final llmBeat = parsed.beats[bIdx];
      TierDocument? matchedBeatDoc;
      for (final eb in existingBeats) {
        if (eb.id == llmBeat.id ||
            eb.title.toLowerCase().trim() ==
                llmBeat.title.toLowerCase().trim()) {
          matchedBeatDoc = eb;
          break;
        }
      }
      if (matchedBeatDoc == null && bIdx < existingBeats.length) {
        matchedBeatDoc = existingBeats[bIdx];
      }
      if (matchedBeatDoc != null) {
        final existingFeats =
            existingFeaturesByBeat[matchedBeatDoc.id] ?? const <TierDocument>[];
        for (int fIdx = 0; fIdx < llmBeat.features.length; fIdx++) {
          final lf = llmBeat.features[fIdx];
          for (final ef in existingFeats) {
            if (ef.id == lf.id ||
                ef.title.toLowerCase().trim() ==
                    lf.title.toLowerCase().trim()) {
              lf.originVersion = ef.sections['originVersion'] ?? 'v0.1';
              break;
            }
          }
        }
      }
      final deferredList = deferredByBeatIndex[bIdx];
      if (deferredList != null && deferredList.isNotEmpty) {
        for (final defFeat in deferredList) {
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
    }

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

      beatTitles.add(beatBp.title);
      onProgress?.call(
        'Syncing Core Loop Epic ${bIdx + 1}: ${beatBp.title}...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final existingBeat = projectScopedDocs[beatBp.id] ??
          existingBeatsByTitle[beatBp.title.toLowerCase().trim()];
      final beatId = existingBeat?.id ?? 'epic_${releaseDoc.id}_${bIdx + 1}';

      final featTitlesForBeat =
          includedFeats.map((f) => '• ${f.title}: ${f.goal}').join('\n');
      final deferredForBeat =
          beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

      final beatDoc = existingBeat ??
          TierDocument(
            id: beatId,
            title: beatBp.title,
            tier: TierType.epic,
            parentId: releaseDoc.id,
          );
      beatDoc.title = beatBp.title;
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
        final existingById = projectScopedDocs[featBp.id];
        final existingFeat = (existingById != null &&
                (existingById.parentId == null ||
                    existingById.parentId == beatDoc.id))
            ? existingById
            : (existingFeaturesByBeatAndTitle[
                    '${beatDoc.id}::${concreteFeatTitle.toLowerCase().trim()}'] ??
                existingFeaturesByBeatAndTitle[
                    '${beatDoc.id}::${featBp.title.toLowerCase().trim()}']);
        final featId = existingFeat?.id ?? 'feat_${beatId}_${fIdx + 1}';

        if (!isInitialPrototypeRelease &&
            featBp.lifecycle == FeatureLifecycleStatus.stable &&
            existingFeat != null) {
          existingFeat.parentId = beatDoc.id;
          existingFeat.sections['lifecycle'] =
              FeatureLifecycleStatus.stable.name;
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
          beatDoc.childrenIds.add(existingFeat.id);
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
              title: featBp.title,
              tier: TierType.feature,
              parentId: beatDoc.id,
            );

        featDoc.title = featBp.title;
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
        final existingCpTitles = existingStates
            .map((s) => s.cleanStageTitle.toLowerCase().trim())
            .toSet();

        for (int cIdx = 0; cIdx < featBp.checkpoints.length; cIdx++) {
          final cpBp = featBp.checkpoints[cIdx];
          if (existingCpTitles.contains(cpBp.title.toLowerCase().trim())) {
            continue;
          }
          final nextOrder = stateNodes.length;
          final cpNumber = nextOrder + 1;
          final checklist = <Subtask>[
            for (int tIdx = 0; tIdx < cpBp.tasks.length; tIdx++)
              Subtask(
                id: '${featId}_${versionTag}_cp${cpNumber}_t${tIdx + 1}',
                text: cpBp.tasks[tIdx],
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
                'releaseVersion': cpBp.releaseVersion.isNotEmpty
                    ? cpBp.releaseVersion
                    : versionTag,
              },
            ),
          );
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        beatDoc.childrenIds.add(featDoc.id);
        createdOrUpdatedDocs.add(featDoc);
      }
    }

    final focusAnswer = blueprint.questions.isNotEmpty
        ? blueprint.questions.first.effectiveAnswer
            .replaceFirst(RegExp(r'^\(Recommended\)\s*'), '')
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

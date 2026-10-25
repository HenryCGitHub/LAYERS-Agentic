import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and proposes a single-Release Blueprint (`ReleaseBlueprint`) with:
/// - Clarifying scope questions
/// - Core Loop Beats (`ProposedBeatBlueprint`)
/// - Cohesive Playable Features (`ProposedFeatureBlueprint`) with pre-mapped
///   60/40 Playable Checkpoints, Scope, Tuning Parameters, and Edge Cases.
class ReleasePlannerAgent {
  static final RegExp _releaseVersionRegex =
      RegExp(r'(v\d+\.\d+(?:\.\d+)?)', caseSensitive: false);
  static final RegExp _bulletStripRegex = RegExp(r'^[•\-\*\s]+');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  static String extractReleaseVersionTag(String releaseTitle) {
    final match = _releaseVersionRegex.firstMatch(releaseTitle);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'v0.1';
  }

  static Future<ReleaseBlueprint> planRelease({
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

    final isSubsequentRelease =
        existingBeats.isNotEmpty || completedReleases.isNotEmpty || versionTag != 'v0.1';
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
        (releasePhase == ProductionPhase.prototype.name && isSubsequentRelease)) {
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
      existingTreeSummary.writeln('Existing Live Game Tree (from prior release):');
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

    if (GeminiAgentClient.hasKey(apiKey)) {
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
- Under each active Beat, generate `1–2` Singular-Focused Playable Features (`"included": true`) needed for ${releaseDoc.title} (do NOT generate pre-unchecked `"included": false` filler features).
- SINGULAR-FOCUSED FEATURE TITLES: Every Feature must represent 1 concrete mechanic (`2–3` plain game-dev words, e.g., `"Weapon Equip"`, `"Player Dash"`, `"Enemy Wave Spawner"`, `"Loot Pickup"`, `"Wave Reset"`). NEVER combine two mechanics with `"&"` or `"and"` in a Feature title.
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

      if (json != null) {
        final parsed = _parseDynamicReleaseBlueprint(
          json: json,
          releaseDoc: releaseDoc,
          preset: preset,
          versionTag: versionTag,
          fallbackExclusions: projectExclusions,
        );
        if (parsed != null) {
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
      }
    }

    if (isSubsequentRelease && existingBeats.isNotEmpty) {
      return _buildDeterministicSubsequentRelease(
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

    final fullLoopItems = coreLoopItems.isNotEmpty
        ? coreLoopItems
        : <String>[
            'Player Controls & Entry: Spawn in the test arena and execute primary movement controls',
            'Core Mechanic & Target Interaction: Engage active targets and hazards with clear feedback',
            'Loop Resolution & Instant Reset: Complete round objective, tally results, and reset cleanly',
          ];
    final effectiveLoopItems =
        (prototypePart == '1' && fullLoopItems.length >= 2)
            ? fullLoopItems.take((fullLoopItems.length / 2).ceil()).toList()
            : fullLoopItems;

    final questions = <AgentQuestion>[
      AgentQuestion(
        id: 'rel_q_feel',
        question: 'For ${releaseDoc.title}, what should we prioritize during greybox playtesting?',
        options: [
          '(Recommended) Controls & Mechanic Feel: Crisp input responsiveness, core mechanic feel, and clean state transitions',
          'Combat Hit & Telegraphs: Target hit confirmation, visual/audio telegraphs, and impact feedback cues',
          'Full Loop & Upgrade Flow: Complete loop progression, reward/upgrade selection, and instant restart flow',
        ],
      ),
      AgentQuestion(
        id: 'rel_q_scope',
        question: 'How strict should our hour budget be for ${releaseDoc.title}?',
        options: [
          '(Recommended) Lean Core Loop Prototype: Cover all ${effectiveLoopItems.length} Core Loop Beats in greybox with zero filler',
          'Expanded Bonus Scope: Include optional time-trial medals and secondary bonus challenges in $versionTag',
          'Minimal Mechanic Slice: Focus strictly on primary movement and combat beats first',
        ],
      ),
    ];

    final beats = <ProposedBeatBlueprint>[];
    for (int i = 0; i < effectiveLoopItems.length; i++) {
      final rawBeat = effectiveLoopItems[i];
      final beatNum = i + 1;
      final beatTitle = _extractBeatTitle(
        rawBeat,
        fallback: 'Core Loop Beat $beatNum',
      );
      final beatDesc = rawBeat.contains(':')
          ? rawBeat.substring(rawBeat.indexOf(':') + 1).trim()
          : rawBeat.trim();
      final archetype = MechanicArchetypeProfile.fromFeatureTitle(
        '$beatTitle Mechanics & Controls',
        beatTitle: beatTitle,
        beatDescription: beatDesc,
      );

      final beatFeatures = <ProposedFeatureBlueprint>[
        ProposedFeatureBlueprint(
          id: 'feat_${beatNum}_1',
          title: '$beatTitle Mechanics & Controls',
          goal: archetype.goal,
          doneWhen: archetype.doneWhen,
          estimatedHours: 5,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: versionTag,
          inScope: archetype.inScope,
          outOfScope: archetype.outOfScope,
          tuningParams: archetype.tuningParams,
          edgeCases: archetype.edgeCases,
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: '$beatTitle Core Implementation & Playtest',
              playtestCriteria: archetype.cp1Playtest,
              releaseVersion: versionTag,
              tasks: const [
                'Actor & Base Properties (2h)',
                'State Logic & Player Input (2h)',
                'Feedback Cues & State Guard (1h)',
              ],
              coveredScope: archetype.inScope,
              tuningParams: archetype.tuningParams,
              edgeCases: archetype.edgeCases,
            ),
          ],
        ),
        if (i == 0)
          ProposedFeatureBlueprint(
            id: 'feat_${beatNum}_2',
            title: '$beatTitle Camera & HUD Feedback',
            goal: 'Provide clear camera tracking and immediate HUD state readout during $beatTitle.',
            doneWhen: 'Camera and HUD indicators update in sync with player actions without jitter.',
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
            inScope: [
              'Camera follow smoothing and active state indicator for $beatTitle',
            ],
            outOfScope: [
              'Custom HUD skin themes',
            ],
            tuningParams: [
              'cameraFollowLerp: 14.0',
            ],
            edgeCases: [
              '[BOUNDARY CLAMP] Camera clamps cleanly at arena bounds without snapping',
            ],
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: 'Camera Follow & State Readout',
                playtestCriteria: 'Trigger $beatTitle near arena boundary -> camera tracks smoothly and HUD updates state.',
                releaseVersion: versionTag,
                tasks: const [
                  'Camera Rig & HUD Container (1h)',
                  'Follow Smoothing & Bound Clamp (2h)',
                  'State Readout & Viewport Test (1h)',
                ],
                coveredScope: [
                  'Camera follow smoothing and active state indicator for $beatTitle',
                ],
                tuningParams: const [
                  'cameraFollowLerp: 14.0',
                ],
                edgeCases: const [
                  '[BOUNDARY CLAMP] Camera clamps cleanly at arena bounds without snapping',
                ],
              ),
            ],
          ),
      ];

      final isLegacyCircularBeatDesc =
          beatDesc.toLowerCase().startsWith('execute ');
      beats.add(
        ProposedBeatBlueprint(
          id: 'beat_$beatNum',
          title: beatTitle,
          goal: (beatDesc.isNotEmpty && !isLegacyCircularBeatDesc)
              ? beatDesc
              : archetype.goal,
          doneWhen: archetype.doneWhen,
          features: beatFeatures,
        ),
      );
    }

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: 'Build and playtest the complete ${projectDoc.title} core loop across all ${beats.length} beats in a greybox arena.',
      doneWhen: 'A playtester can complete the full ${projectDoc.title} core loop cycle and reset cleanly 3 times in a row.',
      questions: questions,
      beats: beats,
      explicitExclusions: projectExclusions.isNotEmpty
          ? projectExclusions
          : const ['Online multiplayer', 'Skill trees & inventory menus'],
    );
  }

  /// Deterministic evolution blueprint for v0.2+ across all 4 Production Phases:
  /// - Phase 1 Split Prototype Part 2 (`prototypePart == '2'`): Keeps v0.1 Beats STABLE and adds remaining Core Loop Beats.
  /// - Phase 2 Per-Epic MVP (`MVP Epic N`): Upgrades ONLY Epic `N` from greybox to MVP while keeping all other Epics STABLE (0h).
  /// - Phase 3 Vertical Slice (`Gold Standard Level`): Upgrades primary feature in EVERY Epic with a Vertical Slice polish checkpoint.
  /// - Phase 4 Full Production (`Full Production`): Scales content/level rosters across Epics and promotes deferred Out-of-Scope systems.
  static ReleaseBlueprint _buildDeterministicSubsequentRelease({
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    required List<String> projectExclusions,
    List<String> allCoreLoopItems = const [],
  }) {
    final beats = <ProposedBeatBlueprint>[];
    final releasePhase = releaseDoc.sections['phase'] ?? '';
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = RegExp(r'MVP Epic\s*(\d+)', caseSensitive: false)
        .firstMatch(releaseDoc.title);
    final int? parsedMvpEpicIdx = rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : (mvpEpicMatch != null
            ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
            : null);

    final isSplitPrototypePart2 = prototypePart == '2' ||
        (releasePhase == ProductionPhase.prototype.name &&
            allCoreLoopItems.length > existingBeats.length);
    final isVerticalSlicePhase =
        releasePhase == ProductionPhase.verticalSlice.name ||
            preset == ReleaseScope.verticalSlice;
    final isFullProductionPhase =
        releasePhase == ProductionPhase.fullProduction.name ||
            preset == ReleaseScope.fullProduction;
    final isTargetedMvpEpic = !isSplitPrototypePart2 &&
        !isVerticalSlicePhase &&
        !isFullProductionPhase &&
        parsedMvpEpicIdx != null;
    final targetMvpEpicIdx =
        (parsedMvpEpicIdx ?? 0).clamp(0, existingBeats.length - 1);

    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final beatDoc = existingBeats[bIdx];
      final existingFeats =
          existingFeaturesByBeat[beatDoc.id] ?? const <TierDocument>[];
      final proposedFeats = <ProposedFeatureBlueprint>[];

      for (int fIdx = 0; fIdx < existingFeats.length; fIdx++) {
        final fDoc = existingFeats[fIdx];
        final originVer = fDoc.sections['originVersion'] ?? 'v0.1';
        final archetype = MechanicArchetypeProfile.fromFeatureTitle(
          fDoc.title,
          beatTitle: beatDoc.title,
        );

        if (isSplitPrototypePart2) {
          // Split Prototype Part 2: Keep all v0.1 features STABLE (0h) while we append the remaining Beats below
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: fDoc.id,
              title: fDoc.title,
              goal: SectionTextUtils.resolveGoal(fDoc.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(fDoc.sections),
              estimatedHours: 0,
              included: true,
              lifecycle: FeatureLifecycleStatus.stable,
              originVersion: originVer,
              checkpoints: const [],
            ),
          );
        } else if (isVerticalSlicePhase) {
          // Phase 3 Vertical Slice: Upgrade primary feature in EVERY Epic with a Gold Standard Polish checkpoint
          if (fIdx == 0) {
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal:
                    'Bring ${fDoc.title} to Vertical Slice Gold Standard visual, audio, and game-feel quality.',
                doneWhen:
                    '${fDoc.title} runs with final art/materials, synced SFX/VFX cues, and zero frame hitches in the showcase level.',
                estimatedHours: 5,
                included: true,
                lifecycle: FeatureLifecycleStatus.upgrade,
                originVersion: originVer,
                inScope: [
                  'Final art, shader/material swap, and synced SFX/VFX impact cues for ${fDoc.title}',
                ],
                tuningParams: archetype.tuningParams,
                edgeCases: [
                  '[FRAME GUARD] Visual & particle cues pool cleanly without frame-time spikes',
                ],
                checkpoints: [
                  ProposedCheckpointBlueprint(
                    title: '${fDoc.title} Visual, Audio & Feel Polish',
                    playtestCriteria:
                        'Trigger ${fDoc.title} in the Gold Standard level -> verify final art, SFX/VFX cues, and 60fps stability.',
                    releaseVersion: versionTag,
                    tasks: const [
                      'Final Art & Material Pass (2h)',
                      'SFX, VFX & Camera Feel Cues (2h)',
                      'HUD Polish & Frame-Time Guard (1h)',
                    ],
                    coveredScope: [
                      'Final art, shader/material swap, and synced SFX/VFX impact cues for ${fDoc.title}',
                    ],
                    tuningParams: archetype.tuningParams,
                    edgeCases: const [
                      '[FRAME GUARD] Visual & particle cues pool cleanly without frame-time spikes',
                    ],
                  ),
                ],
              ),
            );
          } else {
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal: SectionTextUtils.resolveGoal(fDoc.sections),
                doneWhen: SectionTextUtils.resolveDoneWhen(fDoc.sections),
                estimatedHours: 0,
                included: true,
                lifecycle: FeatureLifecycleStatus.stable,
                originVersion: originVer,
                checkpoints: const [],
              ),
            );
          }
        } else if (isFullProductionPhase) {
          // Phase 4 Full Production: Expand content roster, levels/waves, and progression across Epics
          if (fIdx == 0) {
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal:
                    'Scale ${fDoc.title} across full production content rosters, multi-level encounters, and save state.',
                doneWhen:
                    '${fDoc.title} loads multi-stage content data tables and persists state cleanly across full runs.',
                estimatedHours: 5,
                included: true,
                lifecycle: FeatureLifecycleStatus.upgrade,
                originVersion: originVer,
                inScope: [
                  'Data-driven content roster, level/wave scaling, and save-state hooks for ${fDoc.title}',
                ],
                tuningParams: archetype.tuningParams,
                edgeCases: [
                  '[CONTENT BOUNDS GUARD] Invalid or missing roster IDs fall back to default entry safely',
                ],
                checkpoints: [
                  ProposedCheckpointBlueprint(
                    title: '${fDoc.title} Content Roster & Progression Scaling',
                    playtestCriteria:
                        'Run through multiple levels/waves -> verify ${fDoc.title} scales from the content table and persists state.',
                    releaseVersion: versionTag,
                    tasks: const [
                      'Content Roster & Data Table Expansion (2h)',
                      'Multi-Level / Wave Progression Scaling (2h)',
                      'Save State & Edge Guard Verification (1h)',
                    ],
                    coveredScope: [
                      'Data-driven content roster, level/wave scaling, and save-state hooks for ${fDoc.title}',
                    ],
                    tuningParams: archetype.tuningParams,
                    edgeCases: const [
                      '[CONTENT BOUNDS GUARD] Invalid or missing roster IDs fall back to default entry safely',
                    ],
                  ),
                ],
              ),
            );
          } else {
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal: SectionTextUtils.resolveGoal(fDoc.sections),
                doneWhen: SectionTextUtils.resolveDoneWhen(fDoc.sections),
                estimatedHours: 0,
                included: true,
                lifecycle: FeatureLifecycleStatus.stable,
                originVersion: originVer,
                checkpoints: const [],
              ),
            );
          }
        } else if (isTargetedMvpEpic) {
          // Phase 2 Per-Epic MVP: Upgrade ONLY the target Epic (bIdx == targetMvpEpicIdx); keep all other Epics STABLE (0h)
          if (bIdx == targetMvpEpicIdx && fIdx == 0) {
            final isEpic0 = bIdx == 0;
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal: isEpic0
                    ? 'Expand ${fDoc.title} with $versionTag air-dash chain and stamina recovery.'
                    : 'Upgrade ${fDoc.title} from greybox to full MVP depth with ${archetype.cp2Title}.',
                doneWhen: isEpic0
                    ? 'Player chains ground burst into air-dash with clean stamina recharge.'
                    : archetype.doneWhen,
                estimatedHours: 4,
                included: true,
                lifecycle: FeatureLifecycleStatus.upgrade,
                originVersion: originVer,
                inScope: isEpic0
                    ? const ['Air-dash chain impulse and cooldown indicator']
                    : archetype.inScope,
                tuningParams: isEpic0
                    ? const ['airDashMultiplier: 1.25 x']
                    : archetype.tuningParams,
                edgeCases: isEpic0
                    ? const [
                        '[LEDGE CANCEL] Air-dash into ledge mantle preserves horizontal speed',
                      ]
                    : archetype.edgeCases,
                checkpoints: [
                  ProposedCheckpointBlueprint(
                    title: isEpic0
                        ? 'Air-Dash Chain & Cooldown HUD'
                        : archetype.cp2Title,
                    playtestCriteria: isEpic0
                        ? 'Trigger burst in mid-air -> verify 1.25x air-dash impulse and cooldown pip recharge.'
                        : archetype.cp2Playtest,
                    releaseVersion: versionTag,
                    tasks: isEpic0
                        ? const [
                            'Add mid-air burst chain state and airDashMultiplier (2h)',
                            'Bind stamina pip recharge bar on reticle HUD (2h)',
                          ]
                        : archetype.cp2Tasks,
                    coveredScope: isEpic0
                        ? const ['Air-dash chain impulse and cooldown indicator']
                        : archetype.inScope,
                    tuningParams: isEpic0
                        ? const ['airDashMultiplier: 1.25 x']
                        : archetype.tuningParams,
                    edgeCases: isEpic0
                        ? const [
                            '[LEDGE CANCEL] Air-dash into ledge mantle preserves horizontal speed',
                          ]
                        : archetype.edgeCases,
                  ),
                ],
              ),
            );
          } else {
            proposedFeats.add(
              ProposedFeatureBlueprint(
                id: fDoc.id,
                title: fDoc.title,
                goal: SectionTextUtils.resolveGoal(fDoc.sections),
                doneWhen: SectionTextUtils.resolveDoneWhen(fDoc.sections),
                estimatedHours: 0,
                included: true,
                lifecycle: FeatureLifecycleStatus.stable,
                originVersion: originVer,
                checkpoints: const [],
              ),
            );
          }
        } else if (bIdx == 0 && fIdx == 0) {
          // Generic v0.2 evolution fallback
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: fDoc.id,
              title: fDoc.title,
              goal: 'Expand ${fDoc.title} with $versionTag air-dash chain and stamina recovery.',
              doneWhen: 'Player chains ground burst into air-dash with clean stamina recharge.',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.upgrade,
              originVersion: originVer,
              inScope: [
                'Air-dash chain impulse and cooldown indicator',
              ],
              tuningParams: [
                'airDashMultiplier: 1.25 x',
              ],
              edgeCases: [
                '[LEDGE CANCEL] Air-dash into ledge mantle preserves horizontal speed',
              ],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: 'Air-Dash Chain & Cooldown HUD',
                  playtestCriteria: 'Trigger burst in mid-air -> verify 1.25x air-dash impulse and cooldown pip recharge.',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Add mid-air burst chain state and airDashMultiplier (2h)',
                    'Bind stamina pip recharge bar on reticle HUD (2h)',
                  ],
                  coveredScope: const [
                    'Air-dash chain impulse and cooldown indicator',
                  ],
                  tuningParams: const [
                    'airDashMultiplier: 1.25 x',
                  ],
                  edgeCases: const [
                    '[LEDGE CANCEL] Air-dash into ledge mantle preserves horizontal speed',
                  ],
                ),
              ],
            ),
          );
        } else {
          // Keep other existing features STABLE (0h delta, untouched!)
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: fDoc.id,
              title: fDoc.title,
              goal: SectionTextUtils.resolveGoal(fDoc.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(fDoc.sections),
              estimatedHours: 0,
              included: true,
              lifecycle: FeatureLifecycleStatus.stable,
              originVersion: originVer,
              checkpoints: const [],
            ),
          );
        }
      }

      if (isFullProductionPhase && bIdx == existingBeats.length - 1) {
        // Phase 4 Full Production: Promote deferred Out-of-Scope system into an active NEW feature
        final promotedRaw = projectExclusions.isNotEmpty
            ? projectExclusions.first
            : 'Persistent Save & Meta-Progression';
        final promotedTitle = promotedRaw.length <= 36
            ? promotedRaw
            : 'Persistent Save & Meta-Unlocks';
        if (!proposedFeats.any(
          (pf) => pf.title.toLowerCase() == promotedTitle.toLowerCase(),
        )) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: 'feat_${versionTag}_fullprod_promoted',
              title: promotedTitle,
              goal:
                  'Promote "$promotedRaw" into Full Production at Vertical Slice quality.',
              doneWhen:
                  'Playtester completes a full run and verifies "$promotedTitle" persists cleanly across sessions.',
              estimatedHours: 5,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: [
                'Full production implementation and UI integration for $promotedTitle',
              ],
              tuningParams: const [
                'saveFlushIntervalSec: 2.0 s',
              ],
              edgeCases: const [
                '[SAVE INTEGRITY GUARD] Interrupted write falls back to prior verified snapshot',
              ],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: '$promotedTitle Integration & Polish',
                  playtestCriteria:
                      'Complete run and reload session -> verify $promotedTitle state restores with zero data loss.',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Content Roster & Data Table Expansion (2h)',
                    'Multi-Level / Wave Progression Scaling (2h)',
                    'Save State & Edge Guard Verification (1h)',
                  ],
                  coveredScope: [
                    'Full production implementation and UI integration for $promotedTitle',
                  ],
                  tuningParams: const [
                    'saveFlushIntervalSec: 2.0 s',
                  ],
                  edgeCases: const [
                    '[SAVE INTEGRITY GUARD] Interrupted write falls back to prior verified snapshot',
                  ],
                ),
              ],
            ),
          );
        }
      } else if (!isSplitPrototypePart2 &&
          !isVerticalSlicePhase &&
          !isFullProductionPhase &&
          ((isTargetedMvpEpic && bIdx == targetMvpEpicIdx) ||
              (!isTargetedMvpEpic && bIdx == existingBeats.length - 1))) {
        // Promote a new MVP feature in the target MVP Epic (or last beat in generic v0.2)
        if (!isTargetedMvpEpic || bIdx == existingBeats.length - 1) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: 'feat_${versionTag}_medals',
              title: 'Bonus Time-Trial Medals',
              goal: 'Award Bronze/Silver/Gold speed medals at the end of an arena clear.',
              doneWhen: 'Clearing under target thresholds displays medal icon on summary card.',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: const [
                'Gold/Silver/Bronze time threshold evaluation and badge popup',
              ],
              tuningParams: const [
                'goldTimeThreshold: 25.0 s',
              ],
              edgeCases: const [
                '[TIMER OVERFLOW] Runs over 59:59 clamp display string safely',
              ],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: 'Medal Threshold Evaluation',
                  playtestCriteria: 'Clear arena in under 25s -> Gold medal badge animates on clear screen.',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Compare final elapsed time against goldTimeThreshold and render badge (2h)',
                    'Add personal-best split delta indicator on clear banner (2h)',
                  ],
                  coveredScope: const [
                    'Gold/Silver/Bronze time threshold evaluation and badge popup',
                  ],
                  tuningParams: const [
                    'goldTimeThreshold: 25.0 s',
                  ],
                  edgeCases: const [
                    '[TIMER OVERFLOW] Runs over 59:59 clamp display string safely',
                  ],
                ),
              ],
            ),
          );
        }
      }

      // Carry over any features that the developer explicitly deferred (unchecked) in the prior release for this Beat!
      final priorDeferred =
          deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[];
      for (final df in priorDeferred) {
        if (!proposedFeats.any(
          (pf) => pf.title.toLowerCase() == df.title.toLowerCase(),
        )) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: df.id,
              title: df.title,
              goal: df.goal,
              doneWhen: df.doneWhen,
              estimatedHours: df.estimatedHours > 0 ? df.estimatedHours : 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: List<String>.from(df.inScope),
              outOfScope: List<String>.from(df.outOfScope),
              tuningParams: List<String>.from(df.tuningParams),
              edgeCases: List<String>.from(df.edgeCases),
              checkpoints: [
                for (final cp in df.checkpoints)
                  ProposedCheckpointBlueprint(
                    title: cp.title,
                    playtestCriteria: cp.playtestCriteria,
                    tasks: List<String>.from(cp.tasks),
                    coveredScope: List<String>.from(cp.coveredScope),
                    tuningParams: List<String>.from(cp.tuningParams),
                    edgeCases: List<String>.from(cp.edgeCases),
                    releaseVersion: versionTag,
                  ),
              ],
            ),
          );
        }
      }

      beats.add(
        ProposedBeatBlueprint(
          id: beatDoc.id,
          title: beatDoc.title,
          goal: SectionTextUtils.resolveGoal(beatDoc.sections),
          doneWhen: SectionTextUtils.resolveDoneWhen(beatDoc.sections),
          features: proposedFeats,
        ),
      );
    }

    // If this is Split Prototype Part 2 (`v0.2`), append the remaining Stage 1 Core Loop Beats as NEW greybox Epics!
    if (isSplitPrototypePart2 && allCoreLoopItems.length > existingBeats.length) {
      for (int i = existingBeats.length; i < allCoreLoopItems.length; i++) {
        final rawBeat = allCoreLoopItems[i];
        final beatNum = i + 1;
        final beatTitle = _extractBeatTitle(
          rawBeat,
          fallback: 'Core Loop Beat $beatNum',
        );
        final beatDesc = rawBeat.contains(':')
            ? rawBeat.substring(rawBeat.indexOf(':') + 1).trim()
            : rawBeat.trim();
        final archetype = MechanicArchetypeProfile.fromFeatureTitle(
          '$beatTitle Mechanics & Controls',
          beatTitle: beatTitle,
          beatDescription: beatDesc,
        );
        beats.add(
          ProposedBeatBlueprint(
            id: 'beat_$beatNum',
            title: beatTitle,
            goal: beatDesc.isNotEmpty ? beatDesc : archetype.goal,
            doneWhen: archetype.doneWhen,
            features: [
              ProposedFeatureBlueprint(
                id: 'feat_${beatNum}_1',
                title: '$beatTitle Mechanics & Controls',
                goal: archetype.goal,
                doneWhen: archetype.doneWhen,
                estimatedHours: 5,
                included: true,
                lifecycle: FeatureLifecycleStatus.newFeature,
                originVersion: versionTag,
                inScope: archetype.inScope,
                outOfScope: archetype.outOfScope,
                tuningParams: archetype.tuningParams,
                edgeCases: archetype.edgeCases,
                checkpoints: [
                  ProposedCheckpointBlueprint(
                    title: '$beatTitle Core Implementation & Playtest',
                    playtestCriteria: archetype.cp1Playtest,
                    releaseVersion: versionTag,
                    tasks: const [
                      'Actor & Base Properties (2h)',
                      'State Logic & Player Input (2h)',
                      'Feedback Cues & State Guard (1h)',
                    ],
                    coveredScope: archetype.inScope,
                    tuningParams: archetype.tuningParams,
                    edgeCases: archetype.edgeCases,
                  ),
                ],
              ),
            ],
          ),
        );
      }
    }

    final String resolvedGoal;
    final String resolvedDoneWhen;
    if (isSplitPrototypePart2) {
      resolvedGoal =
          'Complete the remaining Core Loop Epics in $versionTag while keeping verified v0.1 mechanics STABLE.';
      resolvedDoneWhen =
          'Playtester completes the full end-to-end prototype loop across all ${beats.length} Epics.';
    } else if (isVerticalSlicePhase) {
      resolvedGoal =
          'Combine all completed MVP Epics into 1 polished Gold Standard Vertical Slice level with final art, audio, and game-feel.';
      resolvedDoneWhen =
          'Playtester completes the Gold Standard showcase level at shippable visual, audio, and 60fps quality.';
    } else if (isFullProductionPhase) {
      resolvedGoal =
          'Expand the verified Vertical Slice template across new levels, content rosters, and promoted systems in $versionTag.';
      resolvedDoneWhen =
          'Playtester completes multi-level runs with expanded content rosters and persistent state verified.';
    } else if (isTargetedMvpEpic) {
      final targetBeatTitle = existingBeats[targetMvpEpicIdx].title;
      resolvedGoal =
          'Upgrade Epic ${targetMvpEpicIdx + 1} ($targetBeatTitle) from greybox to full MVP depth while keeping other Epics STABLE.';
      resolvedDoneWhen =
          'Epic ${targetMvpEpicIdx + 1} ($targetBeatTitle) is playable end-to-end at MVP depth inside the representative level.';
    } else {
      resolvedGoal =
          'Expand the verified v0.1 core loop with $versionTag upgrades while keeping stable features untouched.';
      resolvedDoneWhen =
          'Playtester completes the expanded $versionTag loop with all new and upgraded checkpoints verified.';
    }

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: resolvedGoal,
      doneWhen: resolvedDoneWhen,
      questions: [
        AgentQuestion(
          id: 'rel_q_evolve',
          question: 'How should we handle existing v0.1 features during ${releaseDoc.title}?',
          options: const [
            '(Recommended) Keep Verified Features Stable: Keep verified features STABLE (0h) and only add delta checkpoints where needed',
            'Re-Tune Movement & Combat: Re-tune all v0.1 movement parameters alongside new v0.2 content',
            'Expand All Epics Equally: Add one new polish checkpoint to every existing Epic in v0.2',
          ],
        ),
      ],
      beats: beats,
      explicitExclusions: projectExclusions,
    );
  }

  static ReleaseBlueprint? _parseDynamicReleaseBlueprint({
    required Map<String, dynamic> json,
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<String> fallbackExclusions,
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
        final fTitle = (fMap['title'] ?? 'Feature ${fIdx + 1}').toString().trim();
        final fGoal = (fMap['goal'] ?? '').toString().trim();
        final fDone = (fMap['doneWhen'] ?? '').toString().trim();

        final rawLifecycle = (fMap['lifecycle'] ?? 'new').toString().toLowerCase().trim();
        FeatureLifecycleStatus lifecycle = FeatureLifecycleStatus.newFeature;
        if (rawLifecycle.contains('stable') || rawLifecycle.contains('keep')) {
          lifecycle = FeatureLifecycleStatus.stable;
        } else if (rawLifecycle.contains('upgrade') || rawLifecycle.contains('expand')) {
          lifecycle = FeatureLifecycleStatus.upgrade;
        } else if (rawLifecycle.contains('supersed') || rawLifecycle.contains('archiv')) {
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
        final supersedesTitle = fMap['supersedesFeatureTitle']?.toString().trim();

        List<String> toStrList(dynamic v) => v is List
            ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
            : <String>[];

        final archetype = MechanicArchetypeProfile.fromFeatureTitle(
          fTitle,
          beatTitle: bTitle,
          beatDescription: bGoal,
        );
        final rawInScope = toStrList(fMap['inScope']);
        final rawOutOfScope = toStrList(fMap['outOfScope']);
        final rawTuning = toStrList(fMap['tuningParams']);
        final rawEdges = toStrList(fMap['edgeCases']);

        final inScope = rawInScope.isNotEmpty ? rawInScope : archetype.inScope;
        final outOfScope =
            rawOutOfScope.isNotEmpty ? rawOutOfScope : archetype.outOfScope;
        final tuning =
            rawTuning.isNotEmpty ? rawTuning : archetype.tuningParams;
        final edges = rawEdges.isNotEmpty ? rawEdges : archetype.edgeCases;

        final checkpoints = <ProposedCheckpointBlueprint>[];
        final rawCps = fMap['checkpoints'];
        if (rawCps is List) {
          for (int cIdx = 0; cIdx < rawCps.length; cIdx++) {
            final cMap = rawCps[cIdx];
            if (cMap is! Map) continue;
            final cpTitle =
                (cMap['title'] ?? 'Stage ${cIdx + 1}').toString().trim();
            final cpCriteria = (cMap['playtestCriteria'] ??
                    (fDone.isNotEmpty ? fDone : archetype.cp1Playtest))
                .toString()
                .trim();
            final cpVer =
                (cMap['releaseVersion'] ?? versionTag).toString().trim();
            final cpTasks = toStrList(cMap['tasks']);
            final resolvedTasks = cpTasks.length >= 2
                ? cpTasks
                : (cIdx == 0 ? archetype.cp1Tasks : archetype.cp2Tasks);
            checkpoints.add(
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: cpVer,
                tasks: resolvedTasks,
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

        if (checkpoints.isEmpty &&
            lifecycle != FeatureLifecycleStatus.stable &&
            lifecycle != FeatureLifecycleStatus.superseded) {
          checkpoints.add(
            ProposedCheckpointBlueprint(
              title: archetype.cp1Title,
              playtestCriteria:
                  fDone.isNotEmpty ? fDone : archetype.cp1Playtest,
              releaseVersion: versionTag,
              tasks: archetype.cp1Tasks,
              coveredScope: inScope,
              tuningParams: tuning,
              edgeCases: edges,
            ),
          );
        }

        features.add(
          ProposedFeatureBlueprint(
            id: (fMap['id'] ?? 'feat_${bIdx + 1}_${fIdx + 1}').toString(),
            title: fTitle,
            goal: fGoal.isNotEmpty ? fGoal : archetype.goal,
            doneWhen: fDone.isNotEmpty ? fDone : archetype.doneWhen,
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
        ? rawEx.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : fallbackExclusions;

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: (json['goal'] ??
              'Build and playtest the complete core gameplay loop in one greybox test arena.')
          .toString()
          .trim(),
      doneWhen: (json['doneWhen'] ??
              'A playtester can play, clear, and reset the arena 3 times in a row.')
          .toString()
          .trim(),
      questions: questions,
      beats: beats,
      explicitExclusions: exclusions,
    );
  }

  /// Reconciles a live LLM `ReleaseBlueprint` against existing Vault Beat/Feature IDs
  /// and enforces the 4-Phase Release Train invariants (Split Prototype Part 1/2,
  /// Per-Epic MVP single-Epic targeting, Vertical Slice polish, and Full Production promotion).
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

    // Phase 1 Split Prototype Part 1 (v0.1): Clamp beats to the first half of the Core Loop
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

    // Build canonical subsequent release structure to anchor Vault IDs & 4-Phase lifecycle rules
    final canonical = _buildDeterministicSubsequentRelease(
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      existingBeats: existingBeats,
      existingFeaturesByBeat: existingFeaturesByBeat,
      deferredByBeatIndex: deferredByBeatIndex,
      projectExclusions: projectExclusions,
      allCoreLoopItems: allCoreLoopItems,
    );

    final reconciledBeats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < canonical.beats.length; bIdx++) {
      final canonBeat = canonical.beats[bIdx];
      final isCanonBeatAllStable = canonBeat.features.isNotEmpty &&
          canonBeat.features.every(
            (f) => f.lifecycle == FeatureLifecycleStatus.stable,
          );

      // If this Beat is locked STABLE in the active Phase (e.g. Part 1 Epics in Split Prototype Part 2,
      // or non-target Epics in Phase 2 Per-Epic MVP), preserve the canonical STABLE Beat untouched.
      if (isCanonBeatAllStable) {
        reconciledBeats.add(canonBeat);
        continue;
      }

      // Find the matching LLM Beat by ID, normalized title, index, or single-Epic response
      ProposedBeatBlueprint? llmBeat;
      for (final b in parsed.beats) {
        if (b.id == canonBeat.id ||
            b.title.toLowerCase().trim() ==
                canonBeat.title.toLowerCase().trim()) {
          llmBeat = b;
          break;
        }
      }
      llmBeat ??= (bIdx < parsed.beats.length)
          ? parsed.beats[bIdx]
          : (parsed.beats.length == 1 ? parsed.beats.first : null);

      if (llmBeat == null || llmBeat.features.isEmpty) {
        reconciledBeats.add(canonBeat);
        continue;
      }

      // If this is a brand-new Beat added in Split Prototype Part 2 (`bIdx >= existingBeats.length`)
      if (bIdx >= existingBeats.length) {
        final newFeats = llmBeat.features.map((f) {
          return ProposedFeatureBlueprint(
            id: f.id,
            title: f.title,
            goal: f.goal.isNotEmpty ? f.goal : canonBeat.features.first.goal,
            doneWhen: f.doneWhen.isNotEmpty
                ? f.doneWhen
                : canonBeat.features.first.doneWhen,
            estimatedHours: f.estimatedHours > 0 ? f.estimatedHours : 5,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
            inScope: f.inScope.isNotEmpty
                ? f.inScope
                : canonBeat.features.first.inScope,
            outOfScope: f.outOfScope,
            tuningParams: f.tuningParams.isNotEmpty
                ? f.tuningParams
                : canonBeat.features.first.tuningParams,
            edgeCases: f.edgeCases.isNotEmpty
                ? f.edgeCases
                : canonBeat.features.first.edgeCases,
            checkpoints: f.checkpoints.isNotEmpty
                ? f.checkpoints
                : canonBeat.features.first.checkpoints,
          );
        }).toList();
        reconciledBeats.add(
          ProposedBeatBlueprint(
            id: canonBeat.id,
            title: canonBeat.title,
            goal: llmBeat.goal.isNotEmpty ? llmBeat.goal : canonBeat.goal,
            doneWhen: llmBeat.doneWhen.isNotEmpty
                ? llmBeat.doneWhen
                : canonBeat.doneWhen,
            features: newFeats,
          ),
        );
        continue;
      }

      // Existing Beat receiving upgrades / new features in Phase 2, 3, or 4:
      // Bind existing Feature Vault IDs so upgrades evolve existing cards in-place without duplication!
      final mergedFeats = <ProposedFeatureBlueprint>[];
      final usedLlmFeatIndices = <int>{};

      for (final canonFeat in canonBeat.features) {
        if (canonFeat.lifecycle == FeatureLifecycleStatus.stable ||
            canonFeat.lifecycle == FeatureLifecycleStatus.superseded) {
          mergedFeats.add(canonFeat);
          continue;
        }
        if (canonFeat.lifecycle == FeatureLifecycleStatus.upgrade) {
          int matchIdx = -1;
          for (int i = 0; i < llmBeat.features.length; i++) {
            if (usedLlmFeatIndices.contains(i)) continue;
            final lf = llmBeat.features[i];
            if (lf.id == canonFeat.id ||
                lf.title.toLowerCase().trim() ==
                    canonFeat.title.toLowerCase().trim()) {
              matchIdx = i;
              break;
            }
          }
          if (matchIdx < 0) {
            for (int i = 0; i < llmBeat.features.length; i++) {
              if (!usedLlmFeatIndices.contains(i) &&
                  llmBeat.features[i].lifecycle !=
                      FeatureLifecycleStatus.stable) {
                matchIdx = i;
                break;
              }
            }
          }
          if (matchIdx >= 0) {
            usedLlmFeatIndices.add(matchIdx);
            final lf = llmBeat.features[matchIdx];
            mergedFeats.add(
              ProposedFeatureBlueprint(
                id: canonFeat.id,
                title: canonFeat.title,
                goal: lf.goal.isNotEmpty ? lf.goal : canonFeat.goal,
                doneWhen:
                    lf.doneWhen.isNotEmpty ? lf.doneWhen : canonFeat.doneWhen,
                estimatedHours: lf.estimatedHours > 0
                    ? lf.estimatedHours
                    : canonFeat.estimatedHours,
                included: true,
                lifecycle: FeatureLifecycleStatus.upgrade,
                originVersion: canonFeat.originVersion,
                inScope:
                    lf.inScope.isNotEmpty ? lf.inScope : canonFeat.inScope,
                outOfScope: lf.outOfScope.isNotEmpty
                    ? lf.outOfScope
                    : canonFeat.outOfScope,
                tuningParams: lf.tuningParams.isNotEmpty
                    ? lf.tuningParams
                    : canonFeat.tuningParams,
                edgeCases: lf.edgeCases.isNotEmpty
                    ? lf.edgeCases
                    : canonFeat.edgeCases,
                checkpoints: lf.checkpoints.isNotEmpty
                    ? lf.checkpoints
                    : canonFeat.checkpoints,
              ),
            );
          } else {
            mergedFeats.add(canonFeat);
          }
        }
      }

      // Append any genuinely new features from the LLM (or fallback to canonical new features)
      bool addedNewFromLlm = false;
      for (int i = 0; i < llmBeat.features.length; i++) {
        if (usedLlmFeatIndices.contains(i)) continue;
        final lf = llmBeat.features[i];
        if (lf.lifecycle == FeatureLifecycleStatus.newFeature) {
          mergedFeats.add(lf);
          addedNewFromLlm = true;
        }
      }
      if (!addedNewFromLlm) {
        for (final canonFeat in canonBeat.features) {
          if (canonFeat.lifecycle == FeatureLifecycleStatus.newFeature) {
            mergedFeats.add(canonFeat);
          }
        }
      }

      reconciledBeats.add(
        ProposedBeatBlueprint(
          id: canonBeat.id,
          title: canonBeat.title,
          goal: llmBeat.goal.isNotEmpty ? llmBeat.goal : canonBeat.goal,
          doneWhen:
              llmBeat.doneWhen.isNotEmpty ? llmBeat.doneWhen : canonBeat.doneWhen,
          features: mergedFeats,
        ),
      );
    }

    return ReleaseBlueprint(
      releaseDocId: parsed.releaseDocId,
      releaseTitle: parsed.releaseTitle,
      releaseVersionTag: parsed.releaseVersionTag,
      preset: parsed.preset,
      goal: parsed.goal.isNotEmpty ? parsed.goal : canonical.goal,
      doneWhen:
          parsed.doneWhen.isNotEmpty ? parsed.doneWhen : canonical.doneWhen,
      questions:
          parsed.questions.isNotEmpty ? parsed.questions : canonical.questions,
      beats: reconciledBeats,
      explicitExclusions: parsed.explicitExclusions.isNotEmpty
          ? parsed.explicitExclusions
          : canonical.explicitExclusions,
    );
  }

  /// Turn-by-turn Release Plan Gate Chat: Takes the user's message, updates
  /// the live `ReleaseBlueprint` in place, and appends the AI's reply.
  static Future<ReleaseBlueprint> sendReleasePlanChatTurn({
    required ReleaseBlueprint blueprint,
    required String userMessage,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty) return blueprint;

    if (GeminiAgentClient.hasKey(apiKey)) {
      final currentBeatsSummary = blueprint.beats
          .map(
            (b) => '- ${b.id} "${b.title}" (${b.goal}): '
                '${b.features.map((f) => '"${f.title}" [${f.included ? "IN" : "DEFERRED"}, ${f.activeDeltaHours}h]').join(', ')}',
          )
          .join('\n');

      // Delta-Beat JSON Prompt (~70% fewer output tokens: only return modified/added Beats)
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

      if (json != null) {
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
        );
        if (updatedBp != null) {
          if (updatedBp.goal.isNotEmpty) blueprint.goal = updatedBp.goal;
          if (updatedBp.doneWhen.isNotEmpty) blueprint.doneWhen = updatedBp.doneWhen;
          // Merge delta Beats onto existing blueprint.beats so untouched Epics stay intact
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
          return blueprint;
        }
      }
    }

    // Offline / deterministic fallback: also support "Add <Feature> [to Beat/Epic N]" commands
    final addMatch = RegExp(
      r'^(?:add|include|create)\s+(?:a\s+|an\s+)?(.+?)(?:\s+feature)?(?:\s+(?:to|in)\s+(?:beat|epic)\s*(\d+))?$',
      caseSensitive: false,
    ).firstMatch(cleanMsg);

    String replyText = 'Updated the Release Plan goal and scope to reflect "$cleanMsg".';
    if (addMatch != null && blueprint.beats.isNotEmpty) {
      final rawFeatTitle = addMatch.group(1)!.trim();
      final beatNumStr = addMatch.group(2);
      final targetBeatIdx = beatNumStr != null
          ? ((int.tryParse(beatNumStr) ?? 1) - 1).clamp(0, blueprint.beats.length - 1)
          : 0;
      final targetBeat = blueprint.beats[targetBeatIdx];
      final archetype = MechanicArchetypeProfile.fromFeatureTitle(
        rawFeatTitle,
        beatTitle: targetBeat.title,
        beatDescription: targetBeat.goal,
      );
      final newFeatId =
          'feat_${targetBeat.id}_${targetBeat.features.length + 1}_chat';
      targetBeat.features.add(
        ProposedFeatureBlueprint(
          id: newFeatId,
          title: rawFeatTitle,
          goal: archetype.goal,
          doneWhen: archetype.doneWhen,
          estimatedHours: 4,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: blueprint.releaseVersionTag,
          inScope: archetype.inScope,
          outOfScope: archetype.outOfScope,
          tuningParams: archetype.tuningParams,
          edgeCases: archetype.edgeCases,
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: archetype.cp1Title,
              playtestCriteria: archetype.cp1Playtest,
              releaseVersion: blueprint.releaseVersionTag,
              tasks: archetype.cp1Tasks,
              coveredScope: [archetype.inScope.first],
              tuningParams: archetype.tuningParams,
              edgeCases: [archetype.edgeCases.first],
            ),
            ProposedCheckpointBlueprint(
              title: archetype.cp2Title,
              playtestCriteria: archetype.cp2Playtest,
              releaseVersion: blueprint.releaseVersionTag,
              tasks: archetype.cp2Tasks,
              coveredScope: archetype.inScope.length > 1
                  ? [archetype.inScope[1]]
                  : archetype.inScope,
              tuningParams: archetype.tuningParams,
              edgeCases: archetype.edgeCases.length > 1
                  ? [archetype.edgeCases[1]]
                  : archetype.edgeCases,
            ),
          ],
        ),
      );
      replyText =
          'Added "$rawFeatTitle" to ${targetBeat.title} with 2 playable checkpoints and ${archetype.tuningParams.length} tuning parameters.';
    } else {
      blueprint.goal = '${blueprint.goal} (Adjusted: $cleanMsg)';
    }

    blueprint.lastAgentReply = replyText;
    return blueprint;
  }

  static String _extractBeatTitle(String rawBullet, {required String fallback}) {
    final cleaned = rawBullet.replaceFirst(_bulletStripRegex, '').trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.contains(':')) {
      final prefix = cleaned.split(':')[0].trim();
      if (prefix.length >= 4 && prefix.length <= 36) {
        return prefix;
      }
    }
    final words = cleaned.split(_whitespaceRegex).take(4).join(' ');
    return words.isNotEmpty ? words : fallback;
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

    onProgress?.call('Locking in ${blueprint.releaseTitle} ($versionTag) scope & exclusions...');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    // Index any existing Beats and Features by ID and normalized title for non-destructive merge
    final existingBeatsByTitle = <String, TierDocument>{};
    final existingFeaturesByTitle = <String, TierDocument>{};
    final existingFeaturesByBeatAndTitle = <String, TierDocument>{};
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic) {
        existingBeatsByTitle[doc.title.toLowerCase().trim()] = doc;
      } else if (doc.tier == TierType.feature) {
        final normTitle = doc.title.toLowerCase().trim();
        existingFeaturesByTitle[normTitle] = doc;
        if (doc.parentId != null) {
          existingFeaturesByBeatAndTitle['${doc.parentId}::$normTitle'] = doc;
        }
      }
    }

    releaseDoc.childrenIds.clear();

    for (int bIdx = 0; bIdx < blueprint.beats.length; bIdx++) {
      final beatBp = blueprint.beats[bIdx];
      // Keep both included features and superseded features (marked archived) if they already existed
      final includedFeats = beatBp.includedFeatures;
      if (includedFeats.isEmpty) continue;

      beatTitles.add(beatBp.title);
      onProgress?.call('Syncing Core Loop Epic ${bIdx + 1}: ${beatBp.title}...');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final existingBeat = existingDocuments[beatBp.id] ??
          existingBeatsByTitle[beatBp.title.toLowerCase().trim()];
      final beatId = existingBeat?.id ?? 'epic_${releaseDoc.id}_${bIdx + 1}';

      final featTitlesForBeat = includedFeats.map((f) => '• ${f.title}: ${f.goal}').join('\n');
      final deferredForBeat = beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

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

      // Handle any explicitly superseded features in this beat
      for (final supFeat in beatBp.features.where(
        (f) => f.lifecycle == FeatureLifecycleStatus.superseded,
      )) {
        final existingSup = existingDocuments[supFeat.id] ??
            existingFeaturesByTitle[supFeat.title.toLowerCase().trim()];
        if (existingSup != null) {
          existingSup.sections['lifecycle'] = FeatureLifecycleStatus.superseded.name;
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

        // If this new feature supersedes an old v0.1 testbed by title, mark the old one superseded
        if (featBp.supersedesFeatureTitle != null) {
          final oldDoc = existingFeaturesByTitle[
              featBp.supersedesFeatureTitle!.toLowerCase().trim()];
          if (oldDoc != null) {
            oldDoc.sections['lifecycle'] = FeatureLifecycleStatus.superseded.name;
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
        final existingById = existingDocuments[featBp.id];
        final existingFeat = (existingById != null &&
                (existingById.parentId == null ||
                    existingById.parentId == beatDoc.id))
            ? existingById
            : (existingFeaturesByBeatAndTitle[
                    '${beatDoc.id}::${concreteFeatTitle.toLowerCase().trim()}'] ??
                existingFeaturesByBeatAndTitle[
                    '${beatDoc.id}::${featBp.title.toLowerCase().trim()}']);
        final featId = existingFeat?.id ?? 'feat_${beatId}_${fIdx + 1}';

        // If STABLE and already exists in vault, preserve its existing document & mark prior checkpoints verified!
        if (featBp.lifecycle == FeatureLifecycleStatus.stable &&
            existingFeat != null) {
          existingFeat.parentId = beatDoc.id;
          existingFeat.sections['lifecycle'] = FeatureLifecycleStatus.stable.name;
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

        // Merge scope, tuning, and edge cases with any existing feature data
        final existingStates = existingFeat != null
            ? FeatureStateNode.getStatesForDocument(existingFeat)
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
            (featBp.originVersion.isNotEmpty ? featBp.originVersion : versionTag);
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
                'releaseVersion':
                    cpBp.releaseVersion.isNotEmpty ? cpBp.releaseVersion : versionTag,
              },
            ),
          );
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        beatDoc.childrenIds.add(featDoc.id);
        createdOrUpdatedDocs.add(featDoc);
      }
    }

    // Update Release Scope with approved Goal, Beats, Deferred Out of Scope, and Done When
    final focusAnswer = blueprint.questions.isNotEmpty
        ? blueprint.questions.first.effectiveAnswer
            .replaceFirst(RegExp(r'^\(Recommended\)\s*'), '')
        : '';
    final effectiveGoal = focusAnswer.isNotEmpty
        ? '${blueprint.goal} (Playtest Focus: $focusAnswer)'
        : blueprint.goal;

    final inScopeBeats = beatTitles.map((t) => '• $t').join('\n');
    final outScopeItems = blueprint.effectiveOutOfScope.map((o) => '• $o').join('\n');

    releaseDoc.title = blueprint.releaseTitle;
    releaseDoc.sections['releaseScope'] = blueprint.preset.name;
    releaseDoc.sections['versionTag'] = versionTag;
    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['scope'] = 'Goal: $effectiveGoal\n\n'
        'In Scope:\n$inScopeBeats\n\n'
        'Out of Scope:\n$outScopeItems\n\n'
        'Done When: ${blueprint.doneWhen}';

    onProgress?.call('Release ${blueprint.releaseTitle} ready for development!');
    return createdOrUpdatedDocs;
  }
}

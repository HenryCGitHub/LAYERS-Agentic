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
- Map each Stage 1 Beat (`BEAT-01..BEAT-${coreLoopItems.length.toString().padLeft(2, '0')}`) 1-to-1 to a Beat entry in `beats`.
- Under each Beat, generate `1–2` In-Scope Playable Features (`"included": true`) and `1` Next-Release Candidate Feature (`"included": false`).
- Keep temporary greybox testbeds in a separate Feature from permanent mechanics.
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
          return parsed;
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
      );
    }

    final effectiveLoopItems = coreLoopItems.isNotEmpty
        ? coreLoopItems
        : <String>[
            'Player Controls & Entry: Spawn in the test arena and execute primary movement controls',
            'Core Mechanic & Target Interaction: Engage active targets and hazards with clear feedback',
            'Loop Resolution & Instant Reset: Complete round objective, tally results, and reset cleanly',
          ];

    final questions = <AgentQuestion>[
      AgentQuestion(
        id: 'rel_q_feel',
        question: 'For ${releaseDoc.title}, what should we prioritize during greybox playtesting?',
        options: [
          '(Recommended) Controls & Mechanic Feel: Crisp input responsiveness, core mechanic feel, and state transitions at 60 FPS',
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
      final isLastBeat = i == effectiveLoopItems.length - 1;
      final archetype = MechanicArchetypeProfile.fromFeatureTitle(
        '$beatTitle Mechanics & Controls',
        beatTitle: beatTitle,
        beatDescription: beatDesc,
      );

      final beatFeatures = <ProposedFeatureBlueprint>[
        ProposedFeatureBlueprint(
          id: 'feat_${beatNum}_1',
          title: '$beatTitle Mechanics & Controls',
          goal: 'Build the playable mechanics and feedback for $beatTitle ($beatDesc).',
          doneWhen: 'Playtester can execute $beatTitle reliably at 60 FPS with clear visual and audio cues.',
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
              playtestCriteria: 'Execute $beatTitle in the test arena -> verify "$beatDesc" responds immediately on screen.',
              releaseVersion: versionTag,
              tasks: [
                'Create actor/node structure and base properties for $beatTitle (2h)',
                'Implement core state transitions and player interaction for $beatTitle (2h)',
                'Hook visual/audio feedback cues and transition guard for $beatTitle (1h)',
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
                  'Create camera rig and HUD state readout container (1h)',
                  'Implement camera follow smoothing and boundary clamp (2h)',
                  'Wire active state readout indicator and viewport test (1h)',
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
        if (isLastBeat)
          ProposedFeatureBlueprint(
            id: 'feat_${beatNum}_2',
            title: 'Bonus Time-Trial Medals',
            goal: 'Award Bronze/Silver/Gold performance medals at the end of a completed loop.',
            doneWhen: 'Completing the loop under target thresholds displays medal icon on summary card.',
            estimatedHours: 4,
            included: false, // Pre-unchecked to demonstrate YAGNI toggle -> Out of Scope
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
            inScope: const [
              'Gold/Silver/Bronze threshold evaluation and badge popup',
            ],
            tuningParams: const [
              'goldMedalThreshold: 1000 pts',
            ],
            edgeCases: const [
              '[SCORE CLAMP] Simultaneous completion events award medal exactly once',
            ],
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: 'Medal Threshold Evaluation',
                playtestCriteria: 'Complete loop above target threshold -> Gold medal badge animates on summary screen.',
                releaseVersion: versionTag,
                tasks: const [
                  'Compare round performance against goldMedalThreshold and render badge (2h)',
                ],
                coveredScope: const [
                  'Gold/Silver/Bronze threshold evaluation and badge popup',
                ],
                tuningParams: const [
                  'goldMedalThreshold: 1000 pts',
                ],
                edgeCases: const [
                  '[SCORE CLAMP] Simultaneous completion events award medal exactly once',
                ],
              ),
            ],
          )
        else
          _buildNextReleaseCandidateFeature(
            beatNum: beatNum,
            beatTitle: beatTitle,
            beatDesc: beatDesc,
            versionTag: versionTag,
            featId: 'feat_${beatNum}_${i == 0 ? 3 : 2}',
          ),
      ];

      beats.add(
        ProposedBeatBlueprint(
          id: 'beat_$beatNum',
          title: beatTitle,
          goal: beatDesc.isNotEmpty
              ? beatDesc
              : 'Execute $beatTitle with responsive controls and clear feedback.',
          doneWhen: 'Playtester completes $beatTitle and transitions cleanly to the next beat.',
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

  /// Deterministic evolution blueprint for v0.2+ when running offline / in tests.
  /// Demonstrates how existing v0.1 features either stay STABLE (0h delta) or
  /// UPGRADE with new v0.2 checkpoints, while new v0.2 features join the tree.
  static ReleaseBlueprint _buildDeterministicSubsequentRelease({
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    required List<String> projectExclusions,
  }) {
    final beats = <ProposedBeatBlueprint>[];

    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final beatDoc = existingBeats[bIdx];
      final existingFeats = existingFeaturesByBeat[beatDoc.id] ?? const <TierDocument>[];
      final proposedFeats = <ProposedFeatureBlueprint>[];

      for (int fIdx = 0; fIdx < existingFeats.length; fIdx++) {
        final fDoc = existingFeats[fIdx];
        final originVer = fDoc.sections['originVersion'] ?? 'v0.1';

        if (bIdx == 0 && fIdx == 0) {
          // Upgrade the first feature with a new v0.2 checkpoint!
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

      if (bIdx == existingBeats.length - 1) {
        // Promote a new feature in the last beat for v0.2
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

      // Carry over any features that the developer deferred (unchecked) in the prior release for this Beat!
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

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: 'Expand the verified v0.1 core loop with $versionTag upgrades while keeping stable features untouched.',
      doneWhen: 'Playtester completes the expanded $versionTag loop with all new and upgraded checkpoints verified.',
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
            final cpCriteria =
                (cMap['playtestCriteria'] ?? fDone).toString().trim();
            final cpVer =
                (cMap['releaseVersion'] ?? versionTag).toString().trim();
            final cpTasks = toStrList(cMap['tasks']);
            checkpoints.add(
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: cpVer,
                tasks: cpTasks.isNotEmpty
                    ? cpTasks
                    : ['Implement $cpTitle (${(hours / 2).ceil().clamp(1, 8)}h)'],
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
              title: fTitle,
              playtestCriteria: fDone,
              releaseVersion: versionTag,
              tasks: ['Implement $fTitle (${hours > 0 ? hours : 4}h)'],
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
        if (!features.any((f) => !f.included)) {
          features.add(
            _buildNextReleaseCandidateFeature(
              beatNum: bIdx + 1,
              beatTitle: bTitle,
              beatDesc: bGoal,
              versionTag: versionTag,
              featId: 'feat_${bIdx + 1}_${features.length + 1}_deferred',
            ),
          );
        }
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

  /// Turn-by-turn Release Plan Gate Chat: Takes the user's message, updates
  /// the live `ReleaseBlueprint` in place, and appends the AI's reply.
  static Future<ReleaseBlueprint> sendReleasePlanChatTurn({
    required ReleaseBlueprint blueprint,
    required String userMessage,
    String apiKey = '',
    String modelName = 'gemini-4-argon',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty) return blueprint;

    blueprint.chatHistory.add(
      AgentChatMessage(
        id: 'rel_msg_user_${blueprint.chatHistory.length}',
        role: 'user',
        text: cleanMsg,
      ),
    );

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
          blueprint.chatHistory.add(
            AgentChatMessage(
              id: 'rel_msg_ai_${blueprint.chatHistory.length}',
              role: 'assistant',
              modelUsed: modelName,
              text: reply,
              updatedFields: const ['Release Plan Updated'],
            ),
          );
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

    blueprint.chatHistory.add(
      AgentChatMessage(
        id: 'rel_msg_ai_${blueprint.chatHistory.length}',
        role: 'assistant',
        modelUsed: modelName,
        text: replyText,
        updatedFields: const ['Release Plan Updated'],
      ),
    );
    return blueprint;
  }

  /// Builds an Epic-specific Out-of-Scope / Next-Release Candidate Feature (`included: false`)
  /// so every Epic (`E01..E0N`) in Stage 2 displays both its In-Scope release features and
  /// a concrete stretch/next-release feature that the user can toggle in or keep queued for next release.
  static ProposedFeatureBlueprint _buildNextReleaseCandidateFeature({
    required int beatNum,
    required String beatTitle,
    required String beatDesc,
    required String versionTag,
    required String featId,
  }) {
    final cat = MechanicArchetypeProfile.inferCategory('$beatTitle $beatDesc');
    final String candidateTitle;
    switch (cat) {
      case 'grapple':
        candidateTitle = '$beatTitle Multi-Anchor Zipline';
        break;
      case 'movement':
        candidateTitle = '$beatTitle Air-Dash & Vault Cancel';
        break;
      case 'combat':
        candidateTitle = '$beatTitle Alt-Fire & Parry Counter';
        break;
      case 'farming':
        candidateTitle = '$beatTitle Auto-Watering Sprinklers';
        break;
      case 'economy':
        candidateTitle = '$beatTitle Loadout Presets & Reroll';
        break;
      case 'building':
        candidateTitle = '$beatTitle Multi-Tile Blueprint Copy';
        break;
      case 'ui':
        candidateTitle = '$beatTitle Split-Time Delta Overlay';
        break;
      default:
        const suffixes = <String>[
          'Loadout Presets & Quick-Swap',
          'Combo Chain & Speed Boost',
          'Secondary Hazard & Counter',
          'Bonus Multiplier & Risk Tier',
          'Upgrade Reroll & Compare',
          'Mastery Challenge & Split Timer',
        ];
        final suffix = suffixes[(beatNum - 1) % suffixes.length];
        candidateTitle = '$beatTitle: $suffix';
    }

    final archetype = MechanicArchetypeProfile.fromFeatureTitle(
      candidateTitle,
      beatTitle: beatTitle,
      beatDescription: beatDesc,
    );

    return ProposedFeatureBlueprint(
      id: featId,
      title: candidateTitle,
      goal: archetype.goal,
      doneWhen: archetype.doneWhen,
      estimatedHours: 4,
      included: false,
      lifecycle: FeatureLifecycleStatus.newFeature,
      originVersion: versionTag,
      inScope: archetype.inScope,
      outOfScope: archetype.outOfScope,
      tuningParams: archetype.tuningParams,
      edgeCases: archetype.edgeCases,
      checkpoints: [
        ProposedCheckpointBlueprint(
          title: archetype.cp1Title,
          playtestCriteria: archetype.cp1Playtest,
          releaseVersion: versionTag,
          tasks: archetype.cp1Tasks,
          coveredScope: [archetype.inScope.first],
          tuningParams: archetype.tuningParams,
          edgeCases: [archetype.edgeCases.first],
        ),
      ],
    );
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
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic) {
        existingBeatsByTitle[doc.title.toLowerCase().trim()] = doc;
      } else if (doc.tier == TierType.feature) {
        existingFeaturesByTitle[doc.title.toLowerCase().trim()] = doc;
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

        final existingFeat = existingDocuments[featBp.id] ??
            existingFeaturesByTitle[featBp.title.toLowerCase().trim()];
        final featId = existingFeat?.id ?? 'feat_${beatId}_${fIdx + 1}';

        // If STABLE and already exists in vault, preserve its existing document & checkpoints untouched!
        if (featBp.lifecycle == FeatureLifecycleStatus.stable &&
            existingFeat != null) {
          existingFeat.parentId = beatDoc.id;
          existingFeat.sections['lifecycle'] = FeatureLifecycleStatus.stable.name;
          existingFeat.sections['lastVerifiedVersion'] =
              existingFeat.sections['originVersion'] ?? 'v0.1';
          beatDoc.childrenIds.add(existingFeat.id);
          createdOrUpdatedDocs.add(existingFeat);
          continue;
        }

        // Merge scope, tuning, and edge cases with any existing feature data
        final existingStates = existingFeat != null
            ? FeatureStateNode.getStatesForDocument(existingFeat)
            : <FeatureStateNode>[];

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

import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and proposes a single-Release Blueprint (`ReleaseBlueprint`) with:
/// - 1-2 clarifying scope questions
/// - 2-3 Core Loop Beats (`ProposedBeatBlueprint`)
/// - Cohesive Playable Features (`ProposedFeatureBlueprint`) with pre-mapped
///   60/40 Playable Checkpoints, Scope, Tuning Parameters, and Edge Cases.
class ReleasePlannerAgent {
  static Future<ReleaseBlueprint> planRelease({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    List<TierDocument> completedReleases = const [],
  }) async {
    final preset = releaseDoc.releaseScope;
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );

    final questions = <AgentQuestion>[
      AgentQuestion(
        id: 'rel_q_feel',
        question: 'For ${releaseDoc.title}, what should we prioritize during greybox playtesting?',
        options: [
          '(Recommended) Crisp input responsiveness, velocity tuning, and collision recovery',
          'Target hit-stop, screen shake, and audio/visual combat telegraphing',
          'Full round timer, scoring loop, and instant restart flow',
        ],
      ),
      AgentQuestion(
        id: 'rel_q_scope',
        question: 'How strict should our hour budget be for ${releaseDoc.title}?',
        options: [
          '(Recommended) Lean Prototype (~16–24h across 2–3 core beats)',
          'Standard Milestone (~32–40h including secondary polish features)',
        ],
      ),
    ];

    final beat1Title = coreLoopItems.isNotEmpty
        ? _extractBeatTitle(coreLoopItems[0], fallback: 'Core Movement & Control Feel')
        : 'Core Movement & Control Feel';
    final beat2Title = coreLoopItems.length > 1
        ? _extractBeatTitle(coreLoopItems[1], fallback: 'Target Interaction & Challenge')
        : 'Target Interaction & Challenge';
    final beat3Title = coreLoopItems.length > 2
        ? _extractBeatTitle(coreLoopItems[2], fallback: 'Loop Resolution & Arena Reset')
        : 'Loop Resolution & Arena Reset';

    final beats = <ProposedBeatBlueprint>[
      ProposedBeatBlueprint(
        id: 'beat_1',
        title: beat1Title,
        goal: 'Player controls character movement with immediate velocity, camera, and audio feedback.',
        doneWhen: 'Player traverses the test arena cleanly with zero wall-clipping or input delay.',
        features: [
          ProposedFeatureBlueprint(
            id: 'feat_1_1',
            title: 'Primary Locomotion & Burst',
            goal: 'Deliver responsive directional movement and burst impulse with FOV kick.',
            doneWhen: 'Player chains 3 burst impulses across gaps at 60 FPS.',
            estimatedHours: 6,
            included: true,
            inScope: [
              'Directional acceleration and ground/air velocity curve',
              'Burst impulse trigger with camera FOV kick and whoosh SFX',
            ],
            outOfScope: [
              'Unlockable elemental dash upgrades',
            ],
            tuningParams: [
              'maxMoveSpeed: 12.0 m/s',
              'burstImpulse: 18.5 m/s',
              'coyoteTimeWindow: 0.12 s',
            ],
            edgeCases: [
              '[WALL CLIP] High-speed burst into acute corner clamps velocity cleanly',
              '[INPUT BUFFER] Queued jump/burst within 100ms before landing fires on touchdown',
            ],
            checkpoints: [
              const ProposedCheckpointBlueprint(
                title: 'Velocity Curve & Input Buffer',
                playtestCriteria: 'Sprint and trigger burst off a ledge -> verify 0.12s coyote window and 100ms landing buffer.',
                tasks: [
                  'Implement directional acceleration & maxMoveSpeed clamp (2h)',
                  'Add 100ms input buffer and coyoteTimeWindow check (2h)',
                ],
                coveredScope: [
                  'Directional acceleration and ground/air velocity curve',
                ],
                tuningParams: [
                  'maxMoveSpeed: 12.0 m/s',
                  'coyoteTimeWindow: 0.12 s',
                ],
                edgeCases: [
                  '[INPUT BUFFER] Queued jump/burst within 100ms before landing fires on touchdown',
                ],
              ),
              const ProposedCheckpointBlueprint(
                title: 'Burst Impulse & Corner Deflection',
                playtestCriteria: 'Trigger burst into a 45-degree wall corner -> character slides along surface without clipping.',
                tasks: [
                  'Hook burstImpulse velocity vector with camera FOV kick & SFX (1h)',
                  'Add capsule sweep deflection against steep wall normals (1h)',
                ],
                coveredScope: [
                  'Burst impulse trigger with camera FOV kick and whoosh SFX',
                ],
                tuningParams: [
                  'burstImpulse: 18.5 m/s',
                ],
                edgeCases: [
                  '[WALL CLIP] High-speed burst into acute corner clamps velocity cleanly',
                ],
              ),
            ],
          ),
          ProposedFeatureBlueprint(
            id: 'feat_1_2',
            title: 'Momentum Slide & Recovery',
            goal: 'Allow player to preserve burst speed down slopes and transition smoothly out of landings.',
            doneWhen: 'Landing into a slide preserves momentum and decelerates predictably on flat ground.',
            estimatedHours: 5,
            included: true,
            inScope: [
              'Slope-aware slide speed multiplier and friction decay',
              'Camera tilt and particle dust trail while sliding',
            ],
            outOfScope: [
              'Slide enemy disarm skill',
            ],
            tuningParams: [
              'slideEntrySpeed: 14.0 m/s',
              'flatFrictionDecel: 6.5 m/s²',
            ],
            edgeCases: [
              '[CEILING STAND] Uncrouching under low geometry stays in crouched state until clear',
            ],
            checkpoints: [
              const ProposedCheckpointBlueprint(
                title: 'Slide Entry & Friction Decay',
                playtestCriteria: 'Enter slide on flat vs sloped ramp -> verify speed boost on incline and smooth stop on flat.',
                tasks: [
                  'Apply slideEntrySpeed impulse and slope dot-product multiplier (2h)',
                  'Add flatFrictionDecel curve, camera roll tilt, and dust VFX (2h)',
                  'Guard uncrouch state transition with vertical capsule clearance raycast (1h)',
                ],
                coveredScope: [
                  'Slope-aware slide speed multiplier and friction decay',
                  'Camera tilt and particle dust trail while sliding',
                ],
                tuningParams: [
                  'slideEntrySpeed: 14.0 m/s',
                  'flatFrictionDecel: 6.5 m/s²',
                ],
                edgeCases: [
                  '[CEILING STAND] Uncrouching under low geometry stays in crouched state until clear',
                ],
              ),
            ],
          ),
        ],
      ),
      ProposedBeatBlueprint(
        id: 'beat_2',
        title: beat2Title,
        goal: 'Player engages active targets in the arena with clear telegraphing, hit-stop, and knockback.',
        doneWhen: 'Player can defeat 3 arena targets in a row with readable hit confirmation.',
        features: [
          ProposedFeatureBlueprint(
            id: 'feat_2_1',
            title: 'Target Strike & Hit Feedback',
            goal: 'Connect player attacks against targets with crisp hit-stop, knockback, and damage flash.',
            doneWhen: 'Every strike registers hit-stop, audio cue, and health reduction without ghost hits.',
            estimatedHours: 6,
            included: true,
            inScope: [
              'Attack hitbox sweep and target hurtbox registration',
              '60ms hit-stop freeze, material flash, and directional knockback',
            ],
            outOfScope: [
              'Elemental status effect stacking',
            ],
            tuningParams: [
              'attackRange: 3.2 m',
              'hitStopDuration: 0.06 s',
              'knockbackForce: 11.0 N',
            ],
            edgeCases: [
              '[MULTI HIT] Single attack swing only damages the same target ID once per active frame window',
            ],
            checkpoints: [
              const ProposedCheckpointBlueprint(
                title: 'Hitbox Sweep & Single-Hit Guard',
                playtestCriteria: 'Strike a cluster of 2 targets -> each takes damage exactly once per swing.',
                tasks: [
                  'Build active hitbox sweep and per-swing hit target ID set (2h)',
                  'Apply knockbackForce impulse along impact normal (1h)',
                ],
                coveredScope: [
                  'Attack hitbox sweep and target hurtbox registration',
                ],
                tuningParams: [
                  'attackRange: 3.2 m',
                  'knockbackForce: 11.0 N',
                ],
                edgeCases: [
                  '[MULTI HIT] Single attack swing only damages the same target ID once per active frame window',
                ],
              ),
              const ProposedCheckpointBlueprint(
                title: 'Hit-Stop & Visual Impact Cues',
                playtestCriteria: 'Land a direct hit -> verify 60ms hit-stop frame pause, white flash, and impact SFX.',
                tasks: [
                  'Trigger hitStopDuration time-scale pause and target emissive flash (2h)',
                  'Hook impact spark particles and hit confirmation SFX (1h)',
                ],
                coveredScope: [
                  '60ms hit-stop freeze, material flash, and directional knockback',
                ],
                tuningParams: [
                  'hitStopDuration: 0.06 s',
                ],
              ),
            ],
          ),
        ],
      ),
      ProposedBeatBlueprint(
        id: 'beat_3',
        title: beat3Title,
        goal: 'Close the 30-second gameplay loop with objective completion, round summary, and instant reset.',
        doneWhen: 'Clearing all arena targets displays clear completion feedback and resets in 1 button press.',
        features: [
          ProposedFeatureBlueprint(
            id: 'feat_3_1',
            title: 'Arena Clear & Instant Reset',
            goal: 'Track remaining targets, celebrate arena completion, and reset the loop in under 1 second.',
            doneWhen: 'Defeating the last target triggers clear banner and R-key resets all actors cleanly.',
            estimatedHours: 4,
            included: true,
            inScope: [
              'Active target counter and arena clear banner with run timer',
              'Instant 1-key arena state reset without reloading scene assets',
            ],
            outOfScope: [
              'Global online leaderboards',
            ],
            tuningParams: [
              'resetFadeDuration: 0.25 s',
            ],
            edgeCases: [
              '[SIMULTANEOUS KO] Player dying on the same frame as last target prioritizes failure reset cleanly',
            ],
            checkpoints: [
              const ProposedCheckpointBlueprint(
                title: 'Clear Tracker & Instant Loop Reset',
                playtestCriteria: 'Eliminate final target -> banner appears -> press Reset -> player and targets restore in 0.25s.',
                tasks: [
                  'Wire active target count listener and run timer HUD (2h)',
                  'Implement pool-based actor reset and simultaneous KO guard (2h)',
                ],
                coveredScope: [
                  'Active target counter and arena clear banner with run timer',
                  'Instant 1-key arena state reset without reloading scene assets',
                ],
                tuningParams: [
                  'resetFadeDuration: 0.25 s',
                ],
                edgeCases: [
                  '[SIMULTANEOUS KO] Player dying on the same frame as last target prioritizes failure reset cleanly',
                ],
              ),
            ],
          ),
          ProposedFeatureBlueprint(
            id: 'feat_3_2',
            title: 'Bonus Time-Trial Medals',
            goal: 'Award Bronze/Silver/Gold speed medals at the end of an arena clear.',
            doneWhen: 'Clearing under target thresholds displays medal icon on summary card.',
            estimatedHours: 4,
            included: false, // Pre-unchecked to demonstrate YAGNI toggle -> Out of Scope
            inScope: [
              'Gold/Silver/Bronze time threshold evaluation and badge popup',
            ],
            tuningParams: [
              'goldTimeThreshold: 25.0 s',
            ],
            edgeCases: [
              '[TIMER OVERFLOW] Runs over 59:59 clamp display string safely',
            ],
            checkpoints: [
              const ProposedCheckpointBlueprint(
                title: 'Medal Threshold Evaluation',
                playtestCriteria: 'Clear arena in under 25s -> Gold medal badge animates on clear screen.',
                tasks: [
                  'Compare final elapsed time against goldTimeThreshold and render badge (2h)',
                ],
                coveredScope: [
                  'Gold/Silver/Bronze time threshold evaluation and badge popup',
                ],
                tuningParams: [
                  'goldTimeThreshold: 25.0 s',
                ],
                edgeCases: [
                  '[TIMER OVERFLOW] Runs over 59:59 clamp display string safely',
                ],
              ),
            ],
          ),
        ],
      ),
    ];

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      preset: preset,
      goal: 'Prove the 30-second playable core loop in one greybox arena with responsive controls and instant reset.',
      doneWhen: 'A playtester can play, clear, and reset the greybox arena 3 times in a row with zero debug intervention.',
      questions: questions,
      beats: beats,
      explicitExclusions: projectExclusions.isNotEmpty
          ? projectExclusions
          : const ['Online multiplayer', 'Skill trees & inventory menus'],
    );
  }

  static String _extractBeatTitle(String rawBullet, {required String fallback}) {
    final cleaned = rawBullet.replaceFirst(RegExp(r'^[•\-\*\s]+'), '').trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.contains(':')) {
      final prefix = cleaned.split(':')[0].trim();
      if (prefix.length >= 4 && prefix.length <= 36) {
        return prefix;
      }
    }
    final words = cleaned.split(RegExp(r'\s+')).take(4).join(' ');
    return words.isNotEmpty ? words : fallback;
  }
}

/// Stage 3 Executor Agent: Takes the user-approved `ReleaseBlueprint` from the
/// Confirmation Gate and constructs the entire active Release hierarchy:
/// - Updates the `Release` document (`scope` with Goal, In Scope Beats, Out of Scope exclusions, Done When)
/// - Creates each `Core Loop Beat` (`TierType.epic`)
/// - Creates each `Feature` (`TierType.feature`) with its `scope`, `tuning`, `edge_cases`,
///   and `Playable Checkpoints` (`FeatureStateNode`) pre-bound for the 60/40 Workbench.
class ReleaseExecutorAgent {
  static Future<List<TierDocument>> executeBlueprint({
    required TierDocument releaseDoc,
    required ReleaseBlueprint blueprint,
    void Function(String stepMessage)? onProgress,
  }) async {
    final createdDocs = <TierDocument>[];
    final beatTitles = <String>[];

    onProgress?.call('Locking in ${blueprint.releaseTitle} scope & exclusions...');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    releaseDoc.childrenIds.clear();

    for (int bIdx = 0; bIdx < blueprint.beats.length; bIdx++) {
      final beatBp = blueprint.beats[bIdx];
      final includedFeats = beatBp.includedFeatures;
      if (includedFeats.isEmpty) continue;

      beatTitles.add(beatBp.title);
      onProgress?.call('Creating Core Loop Beat ${bIdx + 1}: ${beatBp.title}...');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final beatId = 'epic_${releaseDoc.id}_${bIdx + 1}';
      final featTitlesForBeat = includedFeats.map((f) => '• ${f.title}: ${f.goal}').join('\n');
      final deferredForBeat = beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

      final beatDoc = TierDocument(
        id: beatId,
        title: beatBp.title,
        tier: TierType.epic,
        parentId: releaseDoc.id,
        estimatedDuration: '${beatBp.totalIncludedHours}h',
        sections: {
          'scope': 'Goal: ${beatBp.goal}\n\n'
              'In Scope:\n$featTitlesForBeat\n\n'
              '${deferredForBeat.isNotEmpty ? 'Out of Scope:\n$deferredForBeat\n\n' : ''}'
              'Done When: ${beatBp.doneWhen}',
        },
      );

      releaseDoc.childrenIds.add(beatDoc.id);
      createdDocs.add(beatDoc);

      for (int fIdx = 0; fIdx < includedFeats.length; fIdx++) {
        final featBp = includedFeats[fIdx];
        onProgress?.call(
          'Building 60/40 Checkpoints & Spec Context for "${featBp.title}"...',
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        final featId = 'feat_${beatId}_${fIdx + 1}';
        final inScopeText = featBp.inScope.map((s) => '• $s').join('\n');
        final outScopeText = featBp.outOfScope.map((s) => '• $s').join('\n');
        final tuningText = featBp.tuningParams.map((t) => '• $t').join('\n');
        final edgeText = featBp.edgeCases.map((e) => '• $e').join('\n');

        final featDoc = TierDocument(
          id: featId,
          title: featBp.title,
          tier: TierType.feature,
          parentId: beatDoc.id,
          estimatedDuration: '${featBp.estimatedHours}h',
          sections: {
            'scope': 'Goal: ${featBp.goal}\n\n'
                'In Scope:\n$inScopeText\n\n'
                '${outScopeText.isNotEmpty ? 'Out of Scope:\n$outScopeText\n\n' : ''}'
                'Done When: ${featBp.doneWhen}',
            'variables': tuningText,
            'tuning': tuningText,
            'edge_cases': edgeText,
          },
        );

        final stateNodes = <FeatureStateNode>[];
        for (int cIdx = 0; cIdx < featBp.checkpoints.length; cIdx++) {
          final cpBp = featBp.checkpoints[cIdx];
          final checklist = <Subtask>[
            for (int tIdx = 0; tIdx < cpBp.tasks.length; tIdx++)
              Subtask(
                id: '${featId}_cp${cIdx + 1}_t${tIdx + 1}',
                text: cpBp.tasks[tIdx],
                completed: false,
              ),
          ];

          stateNodes.add(
            FeatureStateNode(
              id: '${featId}_cp_${cIdx + 1}',
              name: 'Checkpoint ${cIdx + 1}: ${cpBp.title}',
              trigger: 'Playtest: ${cpBp.playtestCriteria}',
              order: cIdx,
              checklist: checklist,
              coveredScope: List<String>.from(cpBp.coveredScope),
              tuningParams: List<String>.from(cpBp.tuningParams),
              edgeCases: List<String>.from(cpBp.edgeCases),
            ),
          );
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        beatDoc.childrenIds.add(featDoc.id);
        createdDocs.add(featDoc);
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
    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['scope'] = 'Goal: $effectiveGoal\n\n'
        'In Scope:\n$inScopeBeats\n\n'
        'Out of Scope:\n$outScopeItems\n\n'
        'Done When: ${blueprint.doneWhen}';

    onProgress?.call('Release ${blueprint.releaseTitle} ready for development!');
    return createdDocs;
  }
}

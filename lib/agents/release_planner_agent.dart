import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and proposes a single-Release Blueprint (`ReleaseBlueprint`) with:
/// - 1-2 clarifying scope questions
/// - 2-3 Core Loop Beats (`ProposedBeatBlueprint`)
/// - Cohesive Playable Features (`ProposedFeatureBlueprint`) with pre-mapped
///   60/40 Playable Checkpoints, Scope, Tuning Parameters, and Edge Cases.
class ReleasePlannerAgent {
  static String extractReleaseVersionTag(String releaseTitle) {
    final match = RegExp(r'(v\d+\.\d+(?:\.\d+)?)', caseSensitive: false)
        .firstMatch(releaseTitle);
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
    final techSpecText = projectDoc.sections['tech_spec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ?? '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ?? '';

    final existingTreeSummary = StringBuffer();
    if (existingBeats.isNotEmpty) {
      existingTreeSummary.writeln('Existing Live Game Tree (from prior release):');
      for (final b in existingBeats) {
        existingTreeSummary.writeln('- Beat "${b.title}" (${b.id}):');
        final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
        for (final f in feats) {
          final states = FeatureStateNode.getStatesForDocument(f);
          final originVer = f.sections['originVersion'] ?? 'v0.1';
          existingTreeSummary.writeln(
            '  * Feature "${f.title}" [id: ${f.id}, origin: $originVer, ${states.length} checkpoints verified]',
          );
        }
      }
    }

    if (GeminiAgentClient.hasKey(apiKey)) {
      final prompt = '''
You are the Antigravity Release Planner Agent (`gemini-4-argon`) for a game studio.
We are planning milestone Release: "${releaseDoc.title}" (Version Tag: $versionTag, Scope Preset: ${preset.label} — ${preset.description}).

Project Title: "${projectDoc.title}"
Tech & Perspective: $techSpecText
Load-Bearing Design Pillars (Core Player Experience):
$pillarsText
Trade-Offs (Prioritize X over Y):
$tradeOffsText
Project Concept Scope:
${projectDoc.sections['scope'] ?? ''}

${existingTreeSummary.isNotEmpty ? existingTreeSummary.toString() : 'First Release (v0.1): No prior features exist yet.'}

STRICT NAMING & ARCHITECTURE RULES:
1. PLAIN FUNCTIONAL GAME-DEV TITLES (NO THEMATIC / LORE / ARCHAIC WORDING):
   - Every Beat, Feature, and Checkpoint `title` MUST use 2 to 4 plain, everyday game-dev words that state the literal mechanic or system (e.g., "Crop Farming & Storage", "Planting & Harvesting", "Grid Building", "Shop Buy & Sell", "Shotgun Arena Combat", "Greybox Test Room").
   - NEVER use flowery, archaic, poetic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition Prep", "Wasteland", "Adrenaline", "Ordinance").
2. PERMANENT MECHANICS vs. TEMPORARY TESTBEDS:
   - Keep permanent mechanics (movement, weapons, farming, AI, UI) in their own Features so they evolve cleanly from $versionTag onward.
   - Keep temporary greybox test rooms or debug spawners in a separate testbed Feature so they can be marked `"lifecycle": "superseded"` in later releases without throwing away core mechanics.
3. FEATURE LIFECYCLE STATUS (`lifecycle`):
   - For v0.1 (first release): all features use `"lifecycle": "new"`.
   - For v0.2+ (subsequent releases evolving an existing tree):
     * `"stable"` — Existing feature from a prior release that works and needs 0 new hours (`"estimatedHours": 0`, `"checkpoints": []`). Leave it alone!
     * `"upgrade"` — Existing feature getting new $versionTag checkpoints, scope items, or tuning parameters (`"estimatedHours"` = ONLY the new delta hours for $versionTag, and `"checkpoints"` = ONLY the new $versionTag checkpoints).
     * `"new"` — Brand new feature added in $versionTag (or promoted from prior Out of Scope).
     * `"superseded"` — Temporary v0.1 testbed replaced by a real level/arena in $versionTag (`"included": false`, `"supersedesFeatureTitle"` set on the new replacement feature).
4. BANNED CORPORATE JARGON:
   - Never use words like "deliver", "verified", "validate", "leverage", "unified", "end-to-end", "staging", "synergy", or "seamlessly". Start goals with concrete verbs like "Build...", "Add...", or "Connect...".

Return ONLY a JSON object with this exact schema:
{
  "goal": "One plain-English sentence starting with 'Build...' or 'Expand...' stating the goal of ${releaseDoc.title}",
  "doneWhen": "One concrete playtest condition for when ${releaseDoc.title} is ready to ship",
  "explicitExclusions": ["Exclusion 1", "Exclusion 2", "Exclusion 3"],
  "questions": [
    {
      "id": "rel_q_1",
      "question": "Specific release question 1 in plain dev terms?",
      "options": ["(Recommended) Option A", "Option B", "Option C"]
    },
    {
      "id": "rel_q_2",
      "question": "Specific release question 2 in plain dev terms?",
      "options": ["(Recommended) Option A", "Option B"]
    }
  ],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Functional Beat Title",
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
          "originVersion": "$versionTag",
          "inScope": ["Scope item 1", "Scope item 2"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["paramOne: 10.0 m/s", "paramTwo: 0.15 s"],
          "edgeCases": ["[TAG] Specific edge case behavior"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "releaseVersion": "$versionTag",
              "tasks": ["Task 1 (2h)", "Task 2 (2h)"],
              "coveredScope": ["Scope item 1"],
              "tuningParams": ["paramOne: 10.0 m/s"],
              "edgeCases": ["[TAG] Specific edge case behavior"]
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
        projectExclusions: projectExclusions,
      );
    }

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
            goal: 'Build responsive directional movement and burst impulse with FOV kick.',
            doneWhen: 'Player chains 3 burst impulses across gaps at 60 FPS.',
            estimatedHours: 6,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
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
              ProposedCheckpointBlueprint(
                title: 'Velocity Curve & Input Buffer',
                playtestCriteria: 'Sprint and trigger burst off a ledge -> verify 0.12s coyote window and 100ms landing buffer.',
                releaseVersion: versionTag,
                tasks: const [
                  'Implement directional acceleration & maxMoveSpeed clamp (2h)',
                  'Add 100ms input buffer and coyoteTimeWindow check (2h)',
                ],
                coveredScope: const [
                  'Directional acceleration and ground/air velocity curve',
                ],
                tuningParams: const [
                  'maxMoveSpeed: 12.0 m/s',
                  'coyoteTimeWindow: 0.12 s',
                ],
                edgeCases: const [
                  '[INPUT BUFFER] Queued jump/burst within 100ms before landing fires on touchdown',
                ],
              ),
              ProposedCheckpointBlueprint(
                title: 'Burst Impulse & Corner Deflection',
                playtestCriteria: 'Trigger burst into a 45-degree wall corner -> character slides along surface without clipping.',
                releaseVersion: versionTag,
                tasks: const [
                  'Hook burstImpulse velocity vector with camera FOV kick & SFX (1h)',
                  'Add capsule sweep deflection against steep wall normals (1h)',
                ],
                coveredScope: const [
                  'Burst impulse trigger with camera FOV kick and whoosh SFX',
                ],
                tuningParams: const [
                  'burstImpulse: 18.5 m/s',
                ],
                edgeCases: const [
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
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
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
              ProposedCheckpointBlueprint(
                title: 'Slide Entry & Friction Decay',
                playtestCriteria: 'Enter slide on flat vs sloped ramp -> verify speed boost on incline and smooth stop on flat.',
                releaseVersion: versionTag,
                tasks: const [
                  'Apply slideEntrySpeed impulse and slope dot-product multiplier (2h)',
                  'Add flatFrictionDecel curve, camera roll tilt, and dust VFX (2h)',
                  'Guard uncrouch state transition with vertical capsule clearance raycast (1h)',
                ],
                coveredScope: const [
                  'Slope-aware slide speed multiplier and friction decay',
                  'Camera tilt and particle dust trail while sliding',
                ],
                tuningParams: const [
                  'slideEntrySpeed: 14.0 m/s',
                  'flatFrictionDecel: 6.5 m/s²',
                ],
                edgeCases: const [
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
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
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
              ProposedCheckpointBlueprint(
                title: 'Hitbox Sweep & Single-Hit Guard',
                playtestCriteria: 'Strike a cluster of 2 targets -> each takes damage exactly once per swing.',
                releaseVersion: versionTag,
                tasks: const [
                  'Build active hitbox sweep and per-swing hit target ID set (2h)',
                  'Apply knockbackForce impulse along impact normal (1h)',
                ],
                coveredScope: const [
                  'Attack hitbox sweep and target hurtbox registration',
                ],
                tuningParams: const [
                  'attackRange: 3.2 m',
                  'knockbackForce: 11.0 N',
                ],
                edgeCases: const [
                  '[MULTI HIT] Single attack swing only damages the same target ID once per active frame window',
                ],
              ),
              ProposedCheckpointBlueprint(
                title: 'Hit-Stop & Visual Impact Cues',
                playtestCriteria: 'Land a direct hit -> verify 60ms hit-stop frame pause, white flash, and impact SFX.',
                releaseVersion: versionTag,
                tasks: const [
                  'Trigger hitStopDuration time-scale pause and target emissive flash (2h)',
                  'Hook impact spark particles and hit confirmation SFX (1h)',
                ],
                coveredScope: const [
                  '60ms hit-stop freeze, material flash, and directional knockback',
                ],
                tuningParams: const [
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
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
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
              ProposedCheckpointBlueprint(
                title: 'Clear Tracker & Instant Loop Reset',
                playtestCriteria: 'Eliminate final target -> banner appears -> press Reset -> player and targets restore in 0.25s.',
                releaseVersion: versionTag,
                tasks: const [
                  'Wire active target count listener and run timer HUD (2h)',
                  'Implement pool-based actor reset and simultaneous KO guard (2h)',
                ],
                coveredScope: const [
                  'Active target counter and arena clear banner with run timer',
                  'Instant 1-key arena state reset without reloading scene assets',
                ],
                tuningParams: const [
                  'resetFadeDuration: 0.25 s',
                ],
                edgeCases: const [
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
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
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
              ProposedCheckpointBlueprint(
                title: 'Medal Threshold Evaluation',
                playtestCriteria: 'Clear arena in under 25s -> Gold medal badge animates on clear screen.',
                releaseVersion: versionTag,
                tasks: const [
                  'Compare final elapsed time against goldTimeThreshold and render badge (2h)',
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
        ],
      ),
    ];

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
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

  /// Deterministic evolution blueprint for v0.2+ when running offline / in tests.
  /// Demonstrates how existing v0.1 features either stay STABLE (0h delta) or
  /// UPGRADE with new v0.2 checkpoints, while new v0.2 features join the tree.
  static ReleaseBlueprint _buildDeterministicSubsequentRelease({
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
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
            '(Recommended) Keep verified features STABLE (0h) and only add delta checkpoints where needed',
            'Re-tune all v0.1 movement parameters alongside new v0.2 content',
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
      final bTitle = (bMap['title'] ?? 'Beat ${bIdx + 1}').toString().trim();
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
              'Prove the core 30-second playable loop in one greybox test arena.')
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
            (b) => '- Beat "${b.title}" (${b.goal}):\n'
                '${b.features.map((f) => '  * Feature "${f.title}" [${f.included ? "IN SCOPE" : "DEFERRED"}, lifecycle: ${f.lifecycle.name}] (${f.activeDeltaHours}h): ${f.goal}').join('\n')}',
          )
          .join('\n');

      final prompt = '''
You are the Antigravity Release Planner Agent pair-planning "${blueprint.releaseTitle}" (${blueprint.releaseVersionTag}) with a game developer.
Current Release Blueprint:
- Goal: "${blueprint.goal}"
- Done When: "${blueprint.doneWhen}"
- Explicit Exclusions: ${blueprint.explicitExclusions.join(', ')}
- Beats & Features:
$currentBeatsSummary

Developer's Latest Chat Message: "$cleanMsg"

STRICT NAMING & WORDING RULES:
- Use PLAIN, LITERAL, NON-THEMATIC game-dev words for all Beat, Feature, and Checkpoint titles (2-4 everyday words like "Crop Farming & Storage", "Shop Buy & Sell", "Shotgun Arena Combat").
- NEVER use flowery, archaic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition", "Wasteland", "Adrenaline").
- NEVER use corporate buzzwords ("deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly").

Task:
Apply the developer's requested changes to the Release Blueprint and reply conversationally in 1-2 sentences confirming what you changed.
Return ONLY a JSON object with this schema:
{
  "reply": "1-2 sentence confirmation of the changes made to the Release Plan",
  "goal": "Updated release goal starting with 'Build...'",
  "doneWhen": "Updated release doneWhen",
  "explicitExclusions": ["Exclusion 1", "Exclusion 2"],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Functional Beat Title",
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
          "originVersion": "${blueprint.releaseVersionTag}",
          "inScope": ["Scope item 1", "Scope item 2"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["paramOne: 10.0 m/s", "paramTwo: 0.15 s"],
          "edgeCases": ["[TAG] Specific edge case behavior"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "releaseVersion": "${blueprint.releaseVersionTag}",
              "tasks": ["Task 1 (2h)", "Task 2 (2h)"],
              "coveredScope": ["Scope item 1"],
              "tuningParams": ["paramOne: 10.0 m/s"],
              "edgeCases": ["[TAG] Specific edge case behavior"]
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
          blueprint.goal = updatedBp.goal;
          blueprint.doneWhen = updatedBp.doneWhen;
          blueprint.beats = updatedBp.beats;
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

    // Offline / deterministic fallback
    blueprint.goal = '${blueprint.goal} (Adjusted: $cleanMsg)';
    blueprint.chatHistory.add(
      AgentChatMessage(
        id: 'rel_msg_ai_${blueprint.chatHistory.length}',
        role: 'assistant',
        modelUsed: modelName,
        text: 'Updated the Release Plan goal and scope to reflect "$cleanMsg".',
        updatedFields: const ['Release Plan Updated'],
      ),
    );
    return blueprint;
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
/// Confirmation Gate and constructs or evolves the active Release hierarchy:
/// - Non-destructively merges existing Core Loop Beats & Features so completed
///   checkpoints from `v0.1` remain intact when re-planning or evolving to `v0.2+`.
/// - Stamps newly added Checkpoints (`FeatureStateNode`) with `releaseVersion`.
class ReleaseExecutorAgent {
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
      onProgress?.call('Syncing Core Loop Beat ${bIdx + 1}: ${beatBp.title}...');
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
          'Syncing 60/40 Checkpoints & Spec Context for "${featBp.title}"...',
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
                .map((s) => s.replaceFirst(RegExp(r'^[•\-\*\s]+'), '').trim())
                .where((s) => s.isNotEmpty)
            : const Iterable<String>.empty();
        final mergedTuning = <String>{
          ...existingTuning,
          ...featBp.tuningParams,
        }.toList();

        final existingEdges = existingFeat != null
            ? (existingFeat.sections['edge_cases'] ?? '')
                .split('\n')
                .map((s) => s.replaceFirst(RegExp(r'^[•\-\*\s]+'), '').trim())
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

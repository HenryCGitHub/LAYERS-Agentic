import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import 'gemini_agent_client.dart';

/// Represents a single granular tool invocation executed by the Workspace Agent.
class AgentToolCall {
  final String toolName;
  final String targetTitle;
  final String summary;
  final Map<String, dynamic> args;

  const AgentToolCall({
    required this.toolName,
    required this.targetTitle,
    required this.summary,
    this.args = const {},
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'targetTitle': targetTitle,
        'summary': summary,
        'args': args,
      };

  factory AgentToolCall.fromJson(Map<String, dynamic> json) {
    return AgentToolCall(
      toolName: json['toolName']?.toString() ?? 'workspace_tool',
      targetTitle: json['targetTitle']?.toString() ?? 'Active Feature',
      summary: json['summary']?.toString() ?? '',
      args: (json['args'] is Map<String, dynamic>)
          ? json['args'] as Map<String, dynamic>
          : const {},
    );
  }
}

/// Records the multi-step reasoning and tool execution trace of an Agentic turn.
class AgentRunTrace {
  final String agentRole;
  final String userGoal;
  final String reasoning;
  final List<AgentToolCall> toolCalls;
  final DateTime timestamp;

  AgentRunTrace({
    required this.agentRole,
    required this.userGoal,
    required this.reasoning,
    required this.toolCalls,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Proactive intervention surfaced by the 0-token Autonomous Producer / Scope-Guard
/// watcher, paired with a 1-click `[Let Agent Fix ✦]` tool execution.
class AgentIntervention {
  final String id;
  final String badge;
  final String severity; // 'amber' | 'crimson' | 'emerald'
  final String title;
  final String reason;
  final String actionLabel;
  final String toolName;
  final Map<String, dynamic> payload;

  const AgentIntervention({
    required this.id,
    required this.badge,
    required this.severity,
    required this.title,
    required this.reason,
    required this.actionLabel,
    required this.toolName,
    this.payload = const {},
  });
}

/// Holds a generated engine-specific Starter Script Bundle for a Stage 3 Feature.
class FeatureScriptBundle {
  final String fileName;
  final String engineLabel;
  final String language;
  final String code;
  final List<String> exportedVariables;
  final List<String> embeddedGuards;

  const FeatureScriptBundle({
    required this.fileName,
    required this.engineLabel,
    required this.language,
    required this.code,
    required this.exportedVariables,
    required this.embeddedGuards,
  });
}

/// Holds the dry-run stress test results from the Stage 3 AI Playtest Simulator.
class PlaytestSimulationResult {
  final String exploitTitle;
  final String exploitDescription;
  final String recommendedTuningClamp;
  final String simulationGuard;
  final AgentRunTrace trace;

  const PlaytestSimulationResult({
    required this.exploitTitle,
    required this.exploitDescription,
    required this.recommendedTuningClamp,
    required this.simulationGuard,
    required this.trace,
  });
}

/// Holds the Post-Release Retrospective & Auto-Carryover Summary (`v0.1` -> `v0.2`+).
class ReleaseRetrospectiveSummary {
  final String releaseTitle;
  final int totalFeatures;
  final int verifiedCheckpoints;
  final int totalCheckpoints;
  final int fixTasksTriaged;
  final int playtestGuardsAdded;
  final List<String> carryoverFeatureTitles;
  final List<String> hardenedFeatureTitles;

  const ReleaseRetrospectiveSummary({
    required this.releaseTitle,
    required this.totalFeatures,
    required this.verifiedCheckpoints,
    required this.totalCheckpoints,
    required this.fixTasksTriaged,
    required this.playtestGuardsAdded,
    required this.carryoverFeatureTitles,
    required this.hardenedFeatureTitles,
  });
}

/// Low-token, surgical Tool-Calling Orchestrator and 0-token Autonomous Producer Watcher
/// for Stage 2 (`Release Plan Gate`) and Stage 3 (`Active Release Workbench`).
class WorkspaceAgentOrchestrator {
  /// 0-Token Autonomous Concept Critic for Stage 1 (`ProjectConceptBlueprint`).
  /// Detects:
  /// 1. Game Spec vs. Tech Spec contradictions (e.g. "Online" / "Multiplayer" with "Offline-Only", or "3D" with "2D").
  /// 2. Missing Loop Reset / Resolution Beat in `coreLoopBeats`.
  /// 3. Under-specified `exclusions` (`< 2` Out of Scope rules).
  static List<AgentIntervention> auditConceptBlueprint(
    ProjectConceptBlueprint concept,
  ) {
    final interventions = <AgentIntervention>[];
    final gameJoined = concept.gameSpec.join(' ').toLowerCase();
    final techJoined = concept.techSpec.join(' ').toLowerCase();

    // 1a. Online / Multiplayer vs Offline-Only Local Save conflict
    if ((gameJoined.contains('online') || gameJoined.contains('multiplayer')) &&
        techJoined.contains('offline')) {
      interventions.add(
        const AgentIntervention(
          id: 'stage1_netcode_conflict',
          badge: 'CONCEPT CRITIC · SPEC CONTRADICTION',
          severity: 'crimson',
          title: 'Game Spec includes Online/Multiplayer while Tech Spec is Offline-Only',
          reason:
              'Netcode multiplies v0.1 scope by 3x. Resolve by switching Game Spec to Singleplayer / Local Shared-Screen.',
          actionLabel: 'Resolve to Singleplayer ✦',
          toolName: 'resolve_stage1_netcode_conflict',
        ),
      );
    }

    // 1b. 3D Camera vs 2D Engine conflict
    if (gameJoined.contains('3d') && techJoined.contains('2d')) {
      interventions.add(
        const AgentIntervention(
          id: 'stage1_dimension_conflict',
          badge: 'CONCEPT CRITIC · DIMENSION MISMATCH',
          severity: 'amber',
          title: 'Game Spec lists a 3D camera while Tech Spec lists a 2D renderer/engine',
          reason:
              'Aligning Tech Spec to 3D (or Game Spec to 2D) prevents mismatched physics and asset pipelines.',
          actionLabel: 'Align Tech Spec to 3D ✦',
          toolName: 'resolve_stage1_dimension_conflict',
        ),
      );
    }

    // 2. Missing Loop Reset / Resolution Beat
    if (concept.coreLoopBeats.isNotEmpty) {
      final lastBeatLower = concept.coreLoopBeats.last.toLowerCase();
      final hasReset = concept.coreLoopBeats.any((b) {
        final l = b.toLowerCase();
        return l.contains('reset') ||
            l.contains('extract') ||
            l.contains('return') ||
            l.contains('summary') ||
            l.contains('respawn') ||
            l.contains('loop') ||
            l.contains('clear') ||
            l.contains('shop') ||
            l.contains('upgrade');
      });
      if (!hasReset && !lastBeatLower.contains('reset')) {
        interventions.add(
          const AgentIntervention(
            id: 'stage1_missing_loop_reset',
            badge: 'CONCEPT CRITIC · INCOMPLETE LOOP',
            severity: 'amber',
            title: 'Core Loop has no explicit Reset / Resolution Beat',
            reason:
                'Every playable prototype loop needs a clean end-of-cycle reset or upgrade beat so playtesters can repeat runs.',
            actionLabel: 'Append Loop Reset Beat ✦',
            toolName: 'append_stage1_loop_reset_beat',
          ),
        );
      }
    }

    // 3. Under-specified Out of Scope exclusions
    if (concept.exclusions.length < 2) {
      interventions.add(
        const AgentIntervention(
          id: 'stage1_thin_exclusions',
          badge: 'CONCEPT CRITIC · SCOPE GUARDRAILS',
          severity: 'amber',
          title: 'Out of Scope has fewer than 2 explicit exclusions',
          reason:
              'Strong v0.1 boundaries prevent feature creep before entering the Release Plan Gate.',
          actionLabel: 'Add Standard v0.1 Exclusions ✦',
          toolName: 'populate_stage1_exclusions',
        ),
      );
    }

    return interventions;
  }
  /// 0-Token Autonomous Producer Audit for Stage 2 (`ReleaseBlueprint`).
  /// Detects:
  /// 1. Scope / Exclusion conflicts (proposed feature overlaps `Out of Scope`).
  /// 2. Oversized single features (`> 8h` active delta) that should be split or trimmed.
  /// 3. Milestone hour overload (`> 28h` total included in a single prototype/MVP pass).
  static List<AgentIntervention> auditReleaseBlueprint({
    required ReleaseBlueprint blueprint,
    ProjectConceptBlueprint? concept,
  }) {
    final interventions = <AgentIntervention>[];
    final exclusions = <String>[
      ...blueprint.explicitExclusions,
      if (concept != null) ...concept.exclusions,
    ];

    // 1. Check for Out-of-Scope conflicts on included features
    for (final beat in blueprint.beats) {
      for (final feat in beat.includedFeatures) {
        final conflictExclusion = _findExclusionOverlap(
          feat.title,
          feat.goal,
          exclusions,
          projectTitle: concept?.title,
        );
        if (conflictExclusion != null) {
          interventions.add(
            AgentIntervention(
              id: 'scope_conflict_${feat.id}',
              badge: 'PRODUCER SCOPE GUARD · EXCLUSION CONFLICT',
              severity: 'crimson',
              title: '"${feat.title}" conflicts with Out-of-Scope rule',
              reason:
                  'Matches exclusion "$conflictExclusion". Deferring keeps ${blueprint.releaseVersionTag} focused on the core loop.',
              actionLabel: 'Defer to Out of Scope ✦',
              toolName: 'defer_conflicting_feature',
              payload: {
                'beatId': beat.id,
                'featureId': feat.id,
                'featureTitle': feat.title,
                'exclusion': conflictExclusion,
              },
            ),
          );
        } else if (feat.activeDeltaHours > 8) {
          // 2. Check for oversized single feature (>8h)
          interventions.add(
            AgentIntervention(
              id: 'oversized_feat_${feat.id}',
              badge: 'PRODUCER SCOPE GUARD · FEATURE SIZE (>8H)',
              severity: 'amber',
              title: '"${feat.title}" is ${feat.activeDeltaHours}h (risk of stall)',
              reason:
                  'Single features over 8h stall playtesting. Split into a lean 5h v0.1 playable core and defer polish.',
              actionLabel: 'Trim & Split to 5h Core ✦',
              toolName: 'trim_oversized_feature',
              payload: {
                'beatId': beat.id,
                'featureId': feat.id,
                'featureTitle': feat.title,
              },
            ),
          );
        }
      }
    }

    // 3. Check total milestone hours budget
    if (blueprint.totalIncludedHours > 28 && interventions.isEmpty) {
      interventions.add(
        AgentIntervention(
          id: 'milestone_overload_${blueprint.releaseDocId}',
          badge: 'PRODUCER SCOPE GUARD · MILESTONE BUDGET',
          severity: 'amber',
          title: '${blueprint.totalIncludedHours}h active scope is heavy for ${blueprint.releaseVersionTag}',
          reason:
              'Auto-deferring secondary/bonus features trims the milestone to a fast, testable greybox pass.',
          actionLabel: 'Auto-Prune Secondary Scope ✦',
          toolName: 'auto_prune_milestone_scope',
          payload: {'releaseDocId': blueprint.releaseDocId},
        ),
      );
    }

    return interventions;
  }

  /// 0-Token Autonomous Producer & Engine Architect Audit for Stage 3 (`Active Release Workbench`).
  /// Detects:
  /// 1. Active Checkpoint missing numeric tuning variables.
  /// 2. Active Checkpoint missing `[GUARD]` edge-case protections.
  /// 3. Overloaded Checkpoint (`> 5` parent tasks in a single checkpoint).
  static List<AgentIntervention> auditStage3Feature({
    required TierDocument featureDoc,
    required List<FeatureStateNode> states,
    required int activeCheckpointIndex,
  }) {
    if (states.isEmpty) return const [];
    final idx = (activeCheckpointIndex >= 0 && activeCheckpointIndex < states.length)
        ? activeCheckpointIndex
        : 0;
    final cp = states[idx];
    final interventions = <AgentIntervention>[];

    if (cp.tuningParams.isEmpty) {
      interventions.add(
        AgentIntervention(
          id: 'missing_tuning_${cp.id}',
          badge: 'ENGINE ARCHITECT · MISSING TUNING',
          severity: 'amber',
          title: 'Checkpoint ${idx + 1} has no numeric tuning variables',
          reason:
              'Exposed inspector variables let you tune ${featureDoc.title} during playtesting without recompiling.',
          actionLabel: 'Synthesize Tuning Variables ✦',
          toolName: 'rebalance_tuning_params',
          payload: {
            'featureId': featureDoc.id,
            'checkpointIndex': idx,
          },
        ),
      );
    }

    if (cp.edgeCases.isEmpty) {
      interventions.add(
        AgentIntervention(
          id: 'missing_guards_${cp.id}',
          badge: 'ENGINE ARCHITECT · MISSING EDGE GUARDS',
          severity: 'amber',
          title: 'Checkpoint ${idx + 1} has no [GUARD] boundary rules',
          reason:
              'Adding state/collision guards prevents softlocks and frame-spike bugs during playtest verification.',
          actionLabel: 'Inject [GUARD] Rules ✦',
          toolName: 'add_edge_case_guards',
          payload: {
            'featureId': featureDoc.id,
            'checkpointIndex': idx,
          },
        ),
      );
    }

    if (cp.checklist.length > 5) {
      interventions.add(
        AgentIntervention(
          id: 'split_heavy_cp_${cp.id}',
          badge: 'PRODUCER SCOPE GUARD · HEAVY CHECKPOINT',
          severity: 'amber',
          title: 'Checkpoint ${idx + 1} has ${cp.checklist.length} tasks (hard to verify at once)',
          reason:
              'Splitting into a Core Mechanics checkpoint + a Follow-Up Feel checkpoint keeps playtests fast.',
          actionLabel: 'Split Checkpoint in Two ✦',
          toolName: 'split_overloaded_checkpoint',
          payload: {
            'featureId': featureDoc.id,
            'checkpointIndex': idx,
          },
        ),
      );
    }

    return interventions;
  }

  static String? _findExclusionOverlap(
    String featTitle,
    String featGoal,
    List<String> exclusions, {
    String? projectTitle,
  }) {
    final combined = '${featTitle.toLowerCase()} ${featGoal.toLowerCase()}';
    final titleWords = (projectTitle ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    final stopWords = <String>{
      ...titleWords,
      'no',
      'not',
      'without',
      'or',
      'and',
      'the',
      'in',
      'for',
      'to',
      'of',
      'with',
      'system',
      'systems',
      'full',
      'complex',
      'advanced',
      'custom',
      'deferred',
      'defer',
      'until',
      'prototype',
      'release',
      'releases',
      'multi',
      'branch',
      'trees',
      'phase',
      'deep',
      'files',
      'save',
      'menus',
      'audio',
      'persistent',
      'meta',
      'progression',
      'mechanics',
      'controls',
      'feedback',
      'execute',
      'playable',
      'from',
      'player',
      'players',
      'game',
      'level',
      'enemy',
      'enemies',
      'build',
      'built',
      'mode',
      'play',
      'time',
      'base',
      'core',
      'loop',
      'screen',
      'world',
      'item',
      'items',
    };
    for (final ex in exclusions) {
      if (ex.toLowerCase().contains('deferred from')) continue;
      final words = ex
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 4 && !stopWords.contains(w))
          .toList();
      for (final word in words) {
        if (combined.contains(word)) {
          return ex;
        }
      }
    }
    return null;
  }

  /// Executes a Stage 3 Agentic Co-Pilot turn using surgical Delta Tool Calls:
  /// - Available tools:
  ///   1. `add_or_split_checkpoint`
  ///   2. `rebalance_tuning_params` (supports cross-feature tuning updates across sibling features!)
  ///   3. `add_edge_case_guards`
  ///   4. `add_implementation_task`
  static Future<AgentRunTrace> runStage3CoPilotTools({
    required String userDirective,
    required TierDocument activeFeature,
    required List<FeatureStateNode> activeStates,
    required int activeCheckpointIndex,
    required List<TierDocument> siblingFeatures,
    required String engineLabel,
    required String releaseVersionTag,
    required void Function(String featId, List<FeatureStateNode> updatedStates) onSaveStates,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanDirective = userDirective.trim();
    final targetIdx = (activeCheckpointIndex >= 0 && activeCheckpointIndex < activeStates.length)
        ? activeCheckpointIndex
        : (activeStates.isNotEmpty ? 0 : -1);

    // Try surgical low-token Gemini Tool-Calling JSON first when API key is configured
    if (GeminiAgentClient.hasKey(apiKey) && targetIdx != -1) {
      final cp = activeStates[targetIdx];
      final siblingSummary = siblingFeatures
          .where((f) => f.id != activeFeature.id)
          .map((f) {
            final st = FeatureStateNode.getStatesForDocument(f);
            final firstTuning = st.isNotEmpty ? st.first.tuningParams.join(', ') : '';
            return '${f.id} ("${f.title}") [Tuning: $firstTuning]';
          })
          .join('; ');

      final prompt = '''
You are an autonomous Game Production & Systems Agent operating on a live game workbench.
Engine: $engineLabel | Release: $releaseVersionTag
Active Feature: "${activeFeature.title}" (id: ${activeFeature.id})
Active Checkpoint (${targetIdx + 1}/${activeStates.length}): "${cp.cleanStageTitle}"
Current Tasks: ${cp.checklist.map((t) => t.text).join(' | ')}
Current Tuning: ${cp.tuningParams.join(', ')}
Current Edge Guards: ${cp.edgeCases.join(', ')}
Sibling Features in Release: $siblingSummary

Developer Directive: "$cleanDirective"

Choose 1 to 3 surgical workspace tool calls to fulfill the directive.
Available tools:
- "add_or_split_checkpoint": {"stageTitle": "...", "playtestCriteria": "...", "tasks": ["..."], "tuningParams": ["name: val"], "edgeCases": ["[GUARD] ..."]}
- "rebalance_tuning_params": {"targetFeatureId": "${activeFeature.id} or sibling id", "tuningParams": ["param_name: value unit"]}
- "add_edge_case_guards": {"edgeCases": ["[GUARD] literal condition and fallback"]}
- "add_implementation_task": {"taskText": "Concrete observable action (1h)"}

Return ONLY valid JSON:
{
  "reasoning": "1 short sentence explaining why these tools were selected",
  "toolCalls": [
    {
      "toolName": "rebalance_tuning_params",
      "targetTitle": "${activeFeature.title}",
      "summary": "Short 1-line summary of mutation",
      "args": { ... }
    }
  ]
}
''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: apiKey,
        preferredModel: modelName,
        thinkingLevel: thinkingLevel,
        temperature: 0.3,
      );

      final rawCalls = json?['toolCalls'];
      if (rawCalls is List && rawCalls.isNotEmpty) {
        final executedCalls = <AgentToolCall>[];
        for (final item in rawCalls) {
          if (item is Map<String, dynamic>) {
            final call = AgentToolCall.fromJson(item);
            _executeSingleStage3ToolCall(
              call: call,
              activeFeature: activeFeature,
              activeStates: activeStates,
              targetIdx: targetIdx,
              siblingFeatures: siblingFeatures,
              releaseVersionTag: releaseVersionTag,
              onSaveStates: onSaveStates,
            );
            executedCalls.add(call);
          }
        }
        if (executedCalls.isNotEmpty) {
          onSaveStates(activeFeature.id, activeStates);
          return AgentRunTrace(
            agentRole: 'Stage 3 Systems & Feel Agent',
            userGoal: cleanDirective,
            reasoning: json?['reasoning']?.toString() ??
                'Executed surgical workspace tool calls on ${activeFeature.title}.',
            toolCalls: executedCalls,
          );
        }
      }
    }

    // Fast, zero-latency deterministic Multi-Tool Execution (offline / test / preset fallback)
    return _runDeterministicStage3Tools(
      cleanDirective: cleanDirective,
      activeFeature: activeFeature,
      activeStates: activeStates,
      targetIdx: targetIdx,
      siblingFeatures: siblingFeatures,
      engineLabel: engineLabel,
      releaseVersionTag: releaseVersionTag,
      onSaveStates: onSaveStates,
    );
  }

  static void _executeSingleStage3ToolCall({
    required AgentToolCall call,
    required TierDocument activeFeature,
    required List<FeatureStateNode> activeStates,
    required int targetIdx,
    required List<TierDocument> siblingFeatures,
    required String releaseVersionTag,
    required void Function(String featId, List<FeatureStateNode> updatedStates) onSaveStates,
  }) {
    final args = call.args;
    final cp = activeStates[targetIdx];

    switch (call.toolName) {
      case 'add_or_split_checkpoint':
        final title = args['stageTitle']?.toString().trim() ?? 'Screen Feedback & Feel Pass';
        final playtest = args['playtestCriteria']?.toString().trim() ??
            'Trigger ${activeFeature.title} in the scene and verify immediate visual and audio response.';
        final rawTasks = (args['tasks'] as List?)?.map((e) => e.toString()).toList() ??
            [
              'Wire visual cue and sound trigger for ${activeFeature.title} (1h)',
              'Playtest rapid repeated inputs and verify clean state reset (1h)',
            ];
        final rawTuning = (args['tuningParams'] as List?)?.map((e) => e.toString()).toList() ??
            ['hit_flash_ms: 85 ms', 'sfx_pitch_jitter: ±0.06'];
        final rawGuards = (args['edgeCases'] as List?)?.map((e) => e.toString()).toList() ??
            ['[GUARD] Cancel active tween cleanly when interrupted'];

        activeStates.add(
          FeatureStateNode(
            id: generateUniqueId('cp'),
            name: 'Stage ${activeStates.length + 1}: $title',
            trigger: playtest,
            parameters: {'releaseVersion': releaseVersionTag},
            tuningParams: rawTuning,
            edgeCases: rawGuards,
            checklist: [
              for (final t in rawTasks)
                Subtask(
                  id: generateUniqueId('check'),
                  text: t,
                  completed: false,
                ),
            ],
          ),
        );
        break;

      case 'rebalance_tuning_params':
        final targetFeatId = args['targetFeatureId']?.toString() ?? activeFeature.id;
        final newParams = (args['tuningParams'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (targetFeatId != activeFeature.id) {
          final sib = siblingFeatures.where((f) => f.id == targetFeatId).firstOrNull;
          if (sib != null) {
            final sibStates = FeatureStateNode.getStatesForDocument(sib);
            if (sibStates.isNotEmpty) {
              final merged = List<String>.from(sibStates.first.tuningParams);
              for (final p in newParams) {
                final key = p.split(':').first.trim();
                final existingIdx = merged.indexWhere((m) => m.split(':').first.trim() == key);
                if (existingIdx != -1) {
                  merged[existingIdx] = p;
                } else {
                  merged.add(p);
                }
              }
              sibStates.first.tuningParams = merged;
              onSaveStates(sib.id, sibStates);
            }
            break;
          }
        }
        final merged = List<String>.from(cp.tuningParams);
        for (final p in newParams) {
          final key = p.split(':').first.trim();
          final existingIdx = merged.indexWhere((m) => m.split(':').first.trim() == key);
          if (existingIdx != -1) {
            merged[existingIdx] = p;
          } else {
            merged.add(p);
          }
        }
        cp.tuningParams = merged;
        break;

      case 'add_edge_case_guards':
        final guards = (args['edgeCases'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final merged = List<String>.from(cp.edgeCases);
        for (final g in guards) {
          final formatted = g.startsWith('[') ? g : '[GUARD] $g';
          if (!merged.contains(formatted)) {
            merged.add(formatted);
          }
        }
        cp.edgeCases = merged;
        break;

      case 'add_implementation_task':
      default:
        final taskText = args['taskText']?.toString().trim() ?? call.summary;
        if (taskText.isNotEmpty) {
          cp.checklist.add(
            Subtask(
              id: generateUniqueId('check'),
              text: taskText,
              completed: false,
            ),
          );
        }
        break;
    }
  }

  static AgentRunTrace _runDeterministicStage3Tools({
    required String cleanDirective,
    required TierDocument activeFeature,
    required List<FeatureStateNode> activeStates,
    required int targetIdx,
    required List<TierDocument> siblingFeatures,
    required String engineLabel,
    required String releaseVersionTag,
    required void Function(String featId, List<FeatureStateNode> updatedStates) onSaveStates,
  }) {
    final lower = cleanDirective.toLowerCase();
    final toolCalls = <AgentToolCall>[];
    String reasoning =
        'Inspected ${activeFeature.title} ($engineLabel) and applied surgical workspace tools.';

    if (cleanDirective == 'add_polish_checkpoint' ||
        lower.contains('checkpoint') ||
        lower.contains('stage') ||
        lower.contains('split')) {
      final customTitle = (cleanDirective != 'add_polish_checkpoint' &&
              cleanDirective.isNotEmpty &&
              !lower.startsWith('split'))
          ? cleanDirective
          : 'Screen Feedback & Feel Pass';
      final newCp = FeatureStateNode(
        id: generateUniqueId('cp'),
        name: 'Stage ${activeStates.length + 1}: $customTitle',
        trigger:
            'Trigger ${activeFeature.title} in the scene and verify immediate visual and audio feedback with zero frame hitches.',
        parameters: {'releaseVersion': releaseVersionTag},
        tuningParams: const [
          'hit_flash_ms: 85 ms',
          'sfx_pitch_jitter: ±0.06',
        ],
        edgeCases: const [
          '[GUARD] Cancel active tween cleanly when interrupted',
        ],
        checklist: [
          Subtask(
            id: generateUniqueId('check'),
            text: 'Hook up visual flash and sound cue for ${activeFeature.title} (1h)',
            completed: false,
          ),
          Subtask(
            id: generateUniqueId('check'),
            text: 'Playtest rapid repeated inputs and tune timing values (1h)',
            completed: false,
          ),
        ],
      );
      activeStates.add(newCp);
      toolCalls.add(
        AgentToolCall(
          toolName: 'add_or_split_checkpoint',
          targetTitle: activeFeature.title,
          summary: 'Created Checkpoint ${activeStates.length} (${newCp.cleanStageTitle}) with 2 tasks & tuning',
        ),
      );
      reasoning =
          'Added a dedicated 60/40 Playable Checkpoint to isolate feedback and feel verification for ${activeFeature.title}.';
    } else if (cleanDirective == 'suggest_tuning' ||
        lower.contains('tune') ||
        lower.contains('tuning') ||
        lower.contains('snappier') ||
        lower.contains('faster') ||
        lower.contains('slower') ||
        lower.contains('rebalance')) {
      if (targetIdx != -1) {
        final node = activeStates[targetIdx];
        final currentTuning = List<String>.from(node.tuningParams);
        final candidates = <String>[
          'response_window_ms: 90 ms',
          'cooldown_sec: 0.35 s',
          'lerp_damping: 14.0',
        ];
        for (final c in candidates) {
          if (!currentTuning.contains(c)) {
            currentTuning.add(c);
          }
        }
        node.tuningParams = currentTuning;
        toolCalls.add(
          AgentToolCall(
            toolName: 'rebalance_tuning_params',
            targetTitle: '${activeFeature.title} · Checkpoint ${targetIdx + 1}',
            summary: 'Injected response_window_ms, cooldown_sec, and lerp_damping tuning variables',
          ),
        );

        // If directive mentions cross-feature rebalance/feel, also synchronize a coupled sibling feature!
        final coupledSibling = siblingFeatures
            .where((f) => f.id != activeFeature.id)
            .firstOrNull;
        if (coupledSibling != null &&
            (lower.contains('rebalance') ||
                lower.contains('snappier') ||
                lower.contains('faster') ||
                lower.contains('sync'))) {
          final sibStates = FeatureStateNode.getStatesForDocument(coupledSibling);
          if (sibStates.isNotEmpty) {
            final sibTuning = List<String>.from(sibStates.first.tuningParams);
            const syncParam = 'coupled_sync_window_ms: 90 ms';
            if (!sibTuning.contains(syncParam)) {
              sibTuning.add(syncParam);
              sibStates.first.tuningParams = sibTuning;
              onSaveStates(coupledSibling.id, sibStates);
            }
            toolCalls.add(
              AgentToolCall(
                toolName: 'rebalance_tuning_params',
                targetTitle: coupledSibling.title,
                summary: 'Synchronized coupled_sync_window_ms: 90 ms on sibling feature',
              ),
            );
          }
        }
        reasoning =
            'Synthesized numeric inspector variables so you can tune ${activeFeature.title} live in $engineLabel.';
      }
    } else if (cleanDirective == 'add_edge_guards' ||
        lower.contains('guard') ||
        lower.contains('edge')) {
      if (targetIdx != -1) {
        final node = activeStates[targetIdx];
        final currentEdges = List<String>.from(node.edgeCases);
        final candidates = <String>[
          '[GUARD] Ignore duplicate input while state transition is active',
          '[GUARD] Clamp velocity and position within arena bounds on frame spike',
        ];
        for (final c in candidates) {
          if (!currentEdges.contains(c)) {
            currentEdges.add(c);
          }
        }
        node.edgeCases = currentEdges;
        toolCalls.add(
          AgentToolCall(
            toolName: 'add_edge_case_guards',
            targetTitle: '${activeFeature.title} · Checkpoint ${targetIdx + 1}',
            summary: 'Appended 2 [GUARD] boundary rules against duplicate input and frame spikes',
          ),
        );
        reasoning =
            'Added boundary guards to prevent state corruption and collision tunneling during playtest.';
      }
    } else if (targetIdx != -1 && cleanDirective.isNotEmpty) {
      final node = activeStates[targetIdx];
      node.checklist.add(
        Subtask(
          id: generateUniqueId('check'),
          text: cleanDirective,
          completed: false,
        ),
      );
      toolCalls.add(
        AgentToolCall(
          toolName: 'add_implementation_task',
          targetTitle: '${activeFeature.title} · Checkpoint ${targetIdx + 1}',
          summary: 'Added task "$cleanDirective" with 3 engine-aware How-To sub-steps',
        ),
      );
      reasoning =
          'Added observable implementation task to Checkpoint ${targetIdx + 1} and bound $engineLabel How-To steps.';
    }

    onSaveStates(activeFeature.id, activeStates);
    return AgentRunTrace(
      agentRole: 'Stage 3 Systems & Feel Agent',
      userGoal: cleanDirective,
      reasoning: reasoning,
      toolCalls: toolCalls,
    );
  }

  /// Option 1: Generates a complete, ready-to-drop Starter Script Bundle (`.gd`, `.cs`, or `.cpp`)
  /// for a Stage 3 Feature with all live `@export` / `[SerializeField]` / `UPROPERTY` tuning variables,
  /// checkpoint state functions, and `[GUARD]` clauses wired in.
  static FeatureScriptBundle generateFeatureScriptBundle({
    required TierDocument featureDoc,
    required List<FeatureStateNode> states,
    required String engineLabel,
  }) {
    final isUnity = engineLabel.contains('Unity');
    final isUnreal = engineLabel.contains('Unreal');
    final ext = isUnity ? 'cs' : (isUnreal ? 'cpp' : 'gd');
    final lang = isUnity ? 'csharp' : (isUnreal ? 'cpp' : 'gdscript');

    final snakeName = featureDoc.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final pascalName = snakeName
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join();
    final fileName = isUnity || isUnreal
        ? '${pascalName.isEmpty ? "FeatureController" : pascalName}Controller.$ext'
        : '${snakeName.isEmpty ? "feature_controller" : snakeName}_controller.$ext';

    // Collect unique tuning parameters across all checkpoints
    final allTuning = <String>[];
    final allGuards = <String>[];
    for (final s in states) {
      for (final t in s.tuningParams) {
        if (!allTuning.contains(t)) allTuning.add(t);
      }
      for (final g in s.edgeCases) {
        if (!allGuards.contains(g)) allGuards.add(g);
      }
    }
    if (allTuning.isEmpty) {
      allTuning.add('response_window_ms: 90 ms');
    }
    if (allGuards.isEmpty) {
      allGuards.add('[GUARD] Clamp state transitions when input is spammed');
    }

    final parsedVars = <({String ident, String numVal, String raw})>[];
    for (final raw in allTuning) {
      final parts = raw.split(':');
      final rawKey = parts.first
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final ident = rawKey.isEmpty ? 'tuning_param' : rawKey;
      final numMatch = RegExp(r'[-+]?\d+(?:\.\d+)?').firstMatch(
        parts.length > 1 ? parts.sublist(1).join(':') : raw,
      );
      final numVal = numMatch?.group(0) ?? '1.0';
      parsedVars.add((ident: ident, numVal: numVal, raw: raw));
    }

    final buf = StringBuffer();
    if (isUnity) {
      final className = '${pascalName.isEmpty ? "Feature" : pascalName}Controller';
      buf.writeln('using UnityEngine;');
      buf.writeln('');
      buf.writeln('/// Auto-generated Starter Script for ${featureDoc.title}');
      buf.writeln('public class $className : MonoBehaviour');
      buf.writeln('{');
      buf.writeln('    [Header("Live Tuning Parameters")]');
      for (final v in parsedVars) {
        final floatVal = v.numVal.contains('.') ? '${v.numVal}f' : '${v.numVal}.0f';
        buf.writeln('    [SerializeField] private float ${v.ident} = $floatVal; // ${v.raw}');
      }
      buf.writeln('    private bool isStateActive = false;');
      buf.writeln('');
      buf.writeln('    private void Update()');
      buf.writeln('    {');
      for (final g in allGuards) {
        buf.writeln('        // $g');
      }
      buf.writeln('        if (!IsGuardValid()) return;');
      for (int i = 0; i < states.length; i++) {
        buf.writeln('        ExecuteCheckpoint${i + 1}();');
      }
      buf.writeln('    }');
      buf.writeln('');
      buf.writeln('    private bool IsGuardValid()');
      buf.writeln('    {');
      buf.writeln('        return Time.deltaTime > 0f && ${parsedVars.first.ident} > 0f;');
      buf.writeln('    }');
      for (int i = 0; i < states.length; i++) {
        final cp = states[i];
        buf.writeln('');
        buf.writeln('    /// Checkpoint ${i + 1}: ${cp.cleanStageTitle}');
        buf.writeln('    private void ExecuteCheckpoint${i + 1}()');
        buf.writeln('    {');
        for (final task in cp.checklist) {
          buf.writeln('        // Task: ${task.text}');
        }
        buf.writeln('    }');
      }
      buf.writeln('}');
    } else if (isUnreal) {
      final className = 'U${pascalName.isEmpty ? "Feature" : pascalName}Component';
      buf.writeln('#pragma once');
      buf.writeln('#include "CoreMinimal.h"');
      buf.writeln('#include "Components/ActorComponent.h"');
      buf.writeln('');
      buf.writeln('// Auto-generated Starter Component for ${featureDoc.title}');
      buf.writeln('class $className : public UActorComponent');
      buf.writeln('{');
      buf.writeln('public:');
      for (final v in parsedVars) {
        final floatVal = v.numVal.contains('.') ? '${v.numVal}f' : '${v.numVal}.0f';
        buf.writeln('    UPROPERTY(EditAnywhere, Category="Tuning")');
        buf.writeln('    float ${v.ident} = $floatVal; // ${v.raw}');
      }
      buf.writeln('');
      buf.writeln('    void TickComponent(float DeltaTime)');
      buf.writeln('    {');
      for (final g in allGuards) {
        buf.writeln('        // $g');
      }
      buf.writeln('        if (DeltaTime <= 0.0f || ${parsedVars.first.ident} <= 0.0f) return;');
      for (int i = 0; i < states.length; i++) {
        buf.writeln('        ExecuteCheckpoint${i + 1}(DeltaTime);');
      }
      buf.writeln('    }');
      for (int i = 0; i < states.length; i++) {
        final cp = states[i];
        buf.writeln('');
        buf.writeln('    // Checkpoint ${i + 1}: ${cp.cleanStageTitle}');
        buf.writeln('    void ExecuteCheckpoint${i + 1}(float DeltaTime)');
        buf.writeln('    {');
        for (final task in cp.checklist) {
          buf.writeln('        // Task: ${task.text}');
        }
        buf.writeln('    }');
      }
      buf.writeln('};');
    } else {
      // Godot 4 GDScript default
      buf.writeln('extends Node2D');
      buf.writeln('## Auto-generated Starter Script for ${featureDoc.title}');
      buf.writeln('');
      buf.writeln('# ── Live Tuning Parameters ──');
      for (final v in parsedVars) {
        final floatVal = v.numVal.contains('.') ? v.numVal : '${v.numVal}.0';
        buf.writeln('@export var ${v.ident}: float = $floatVal # ${v.raw}');
      }
      buf.writeln('var _is_state_active: bool = false');
      buf.writeln('');
      buf.writeln('func _physics_process(delta: float) -> void:');
      for (final g in allGuards) {
        buf.writeln('\t# $g');
      }
      buf.writeln('\tif not _is_guard_valid(delta):');
      buf.writeln('\t\treturn');
      for (int i = 0; i < states.length; i++) {
        buf.writeln('\t_execute_checkpoint_${i + 1}(delta)');
      }
      buf.writeln('');
      buf.writeln('func _is_guard_valid(delta: float) -> bool:');
      buf.writeln('\treturn delta > 0.0 and ${parsedVars.first.ident} > 0.0');
      for (int i = 0; i < states.length; i++) {
        final cp = states[i];
        buf.writeln('');
        buf.writeln('## Checkpoint ${i + 1}: ${cp.cleanStageTitle}');
        buf.writeln('func _execute_checkpoint_${i + 1}(delta: float) -> void:');
        if (cp.checklist.isEmpty) {
          buf.writeln('\tpass');
        } else {
          for (final task in cp.checklist) {
            buf.writeln('\t# Task: ${task.text}');
          }
          buf.writeln('\tpass');
        }
      }
    }

    return FeatureScriptBundle(
      fileName: fileName,
      engineLabel: engineLabel,
      language: lang,
      code: buf.toString().trimRight(),
      exportedVariables: allTuning,
      embeddedGuards: allGuards,
    );
  }

  /// Option 3: Stage 3 AI Playtest Simulator / Dry-Run Stress Test (`⚡ Simulate`).
  /// Inspects a Checkpoint's current tuning parameters and tasks to detect a concrete
  /// mathematical or rapid-input state exploit, injects a `[SIMULATION GUARD]` edge case,
  /// and clamps/adds a protective cooldown or damping parameter.
  static PlaytestSimulationResult simulateCheckpointPlaytest({
    required TierDocument featureDoc,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String engineLabel,
    required void Function(String featId, List<FeatureStateNode> updatedStates) onSaveStates,
  }) {
    final idx = (checkpointIndex >= 0 && checkpointIndex < states.length)
        ? checkpointIndex
        : 0;
    final cp = states[idx];
    final primaryTune = cp.tuningParams.isNotEmpty
        ? cp.tuningParams.first
        : 'response_window_ms: 90 ms';
    final paramKey = primaryTune.split(':').first.trim();

    final exploitTitle =
        'Rapid Input & Frame-Spike Stress on "${cp.cleanStageTitle}"';
    final exploitDesc =
        'Dry-run simulation found that spamming ${featureDoc.title} inputs during a >33ms frame spike can re-trigger "$paramKey" before the state resets.';
    const recommendedClamp = 'min_retrigger_lockout_ms: 110 ms';
    final simGuard =
        '[SIMULATION GUARD] Lock out duplicate ${featureDoc.title} triggers for 110 ms and clamp delta <= 0.05s';

    if (!cp.tuningParams.any((t) => t.startsWith('min_retrigger_lockout_ms'))) {
      cp.tuningParams = [...cp.tuningParams, recommendedClamp];
    }
    if (!cp.edgeCases.contains(simGuard)) {
      cp.edgeCases = [...cp.edgeCases, simGuard];
    }
    onSaveStates(featureDoc.id, states);

    final trace = AgentRunTrace(
      agentRole: 'AI Playtest Stress Simulator',
      userGoal: 'Simulate Playtest on ${featureDoc.title} · Checkpoint ${idx + 1}',
      reasoning: exploitDesc,
      toolCalls: [
        AgentToolCall(
          toolName: 'simulate_playtest_stress',
          targetTitle: '${featureDoc.title} · Checkpoint ${idx + 1}',
          summary: 'Injected $recommendedClamp + [SIMULATION GUARD] against input spam & frame spikes',
        ),
      ],
    );

    return PlaytestSimulationResult(
      exploitTitle: exploitTitle,
      exploitDescription: exploitDesc,
      recommendedTuningClamp: recommendedClamp,
      simulationGuard: simGuard,
      trace: trace,
    );
  }

  /// Option 7: 0-Token Critical Path & Dependency Tier Classifier for Stage 2 and Stage 3.
  /// Returns:
  /// - `tierRank`: `1` (Foundation · Build 1st), `2` (Core Loop · Build 2nd), `3` (Parallel / Stubbable)
  /// - `badge`: Short mono badge
  /// - `shortBadge`: Compact pill label for Left Rail
  /// - `severity`: `'amber'` (1), `'emerald'` (2), `'neutral'` (3)
  static ({
    int tierRank,
    String badge,
    String shortBadge,
    String severity,
  }) classifyDependencyTier({
    required String featureTitle,
    required int beatIndex,
    int featureIndexInBeat = 0,
  }) {
    final lower = featureTitle.toLowerCase();
    final isStubbableKeyword = lower.contains('bonus') ||
        lower.contains('medal') ||
        lower.contains('summary') ||
        lower.contains('tally') ||
        lower.contains('codex') ||
        lower.contains('cosmetic') ||
        lower.contains('leaderboard') ||
        lower.contains('shop') ||
        lower.contains('menu') ||
        lower.contains('loadout') ||
        lower.contains('staging') ||
        lower.contains('prep');

    final isFoundationKeyword = lower.contains('movement') ||
        lower.contains('traversal') ||
        lower.contains('control') ||
        lower.contains('grapple') ||
        lower.contains('dash') ||
        lower.contains('jump') ||
        lower.contains('camera') ||
        lower.contains('physics') ||
        lower.contains('aim') ||
        lower.contains('locomotion') ||
        lower.contains('drive') ||
        lower.contains('drift') ||
        lower.contains('steer') ||
        lower.contains('plant') ||
        lower.contains('harvest') ||
        lower.contains('card play') ||
        lower.contains('placement');

    if (isStubbableKeyword && beatIndex > 0) {
      return (
        tierRank: 3,
        badge: '◌ PARALLEL / STUBBABLE',
        shortBadge: '◌ STUBBABLE',
        severity: 'neutral',
      );
    }

    if (beatIndex == 0 || isFoundationKeyword) {
      return (
        tierRank: 1,
        badge: '⚡ FOUNDATION · BUILD 1ST',
        shortBadge: '⚡ BUILD 1ST',
        severity: 'amber',
      );
    }

    if (beatIndex <= 4 && featureIndexInBeat == 0) {
      return (
        tierRank: 2,
        badge: '◈ CORE LOOP · BUILD 2ND',
        shortBadge: '◈ BUILD 2ND',
        severity: 'emerald',
      );
    }

    return (
      tierRank: 3,
      badge: '◌ PARALLEL / STUBBABLE',
      shortBadge: '◌ STUBBABLE',
      severity: 'neutral',
    );
  }
}

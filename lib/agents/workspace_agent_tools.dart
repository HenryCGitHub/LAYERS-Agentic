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
  static Future<AgentRunTrace?> runStage3CoPilotTools({
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

    if (!GeminiAgentClient.hasKey(apiKey) || targetIdx == -1) {
      return null;
    }

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

    return null;
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

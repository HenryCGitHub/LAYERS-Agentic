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

/// Low-token, surgical Tool-Calling Orchestrator and 0-token Autonomous Producer Watcher
/// for Stage 2 (`Release Plan Gate`) and Stage 3 (`Active Release Workbench`).
class WorkspaceAgentOrchestrator {
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
        final conflictExclusion = _findExclusionOverlap(feat.title, feat.goal, exclusions);
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
    List<String> exclusions,
  ) {
    final combined = '${featTitle.toLowerCase()} ${featGoal.toLowerCase()}';
    final stopWords = <String>{
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
      'from',
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
}

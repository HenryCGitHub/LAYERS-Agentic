import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and synthesizes a single-Release Blueprint (`ReleaseBlueprint`) using Gemini AI (`gemini-flash-latest`).
/// Contains zero hardcoded archetypes and zero offline minimal scaffolds.
/// Returns `null` (or `false`) whenever the app is offline or Gemini AI is unreachable.
class ReleasePlannerAgent {
  static final RegExp _releaseVersionRegex =
      RegExp(r'(v\d+\.\d+(?:\.\d+)?)', caseSensitive: false);
  static final RegExp _mvpEpicNumRegex =
      RegExp(r'MVP Epic\s*(\d+)', caseSensitive: false);
  static final RegExp _noPrefixRegex = RegExp(r'^no\s+');
  static final RegExp _cutPrefixRegex = RegExp(r'^\[cut\]\s*');
  static final RegExp _durationRegex =
      RegExp(r'\(\s*\d+(?:\.\d+)?\s*[hm]\s*\)\s*$');
  static final RegExp _setupWordRegex =
      RegExp(r'\bsetup\b', caseSensitive: false);
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-zA-Z0-9]');
  static final RegExp _nonAlphaNumSpaceRegex = RegExp(r'[^a-zA-Z0-9\s]');
  static final RegExp _tagPrefixRegex =
      RegExp(r'^\[TAG\]\s*', caseSensitive: false);
  static final RegExp _versionPrefixStripRegex =
      RegExp(r'^v\d+\.\d+\s*[:\-–—]?\s*', caseSensitive: false);

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty && s != '...')
        .toList();
  }

  /// Extracts a dynamic list of checkpoint task strings from either a unified `{role, title}`
  /// tool-call `tasks` array or a plain string `tasks` array, ordering tasks by role
  /// (`entity_and_collision_foundation` -> `1..N core_action_and_math` -> `feedback_and_boundary_guard`).
  static List<String> extractCheckpointTasksFromMap(Map cMap) {
    final rawTasks = cMap['tasks'];
    if (rawTasks is List && rawTasks.isNotEmpty) {
      final foundations = <String>[];
      final actions = <String>[];
      final guards = <String>[];
      final plainStrings = <String>[];
      for (final item in rawTasks) {
        if (item is Map) {
          final title =
              (item['title'] ?? item['task'] ?? item['text'] ?? '')
                  .toString()
                  .trim();
          if (title.isEmpty || title == '...') continue;
          final goal =
              (item['goal'] ?? item['scope'] ?? '').toString().trim();
          final combined = (goal.isNotEmpty &&
                  goal != '...' &&
                  !title.contains(' — ') &&
                  title.toLowerCase() != goal.toLowerCase())
              ? '$title — $goal'
              : title;
          final role = (item['role'] ?? '').toString().trim().toLowerCase();
          if (role.contains('foundation') || role.contains('entity')) {
            foundations.add(combined);
          } else if (role.contains('guard') ||
              role.contains('feedback') ||
              role.contains('boundary')) {
            guards.add(combined);
          } else {
            actions.add(combined);
          }
        } else {
          final str = item.toString().trim();
          if (str.isNotEmpty && str != '...') {
            plainStrings.add(str);
          }
        }
      }
      final roleOrdered = <String>[...foundations, ...actions, ...guards];
      if (roleOrdered.isNotEmpty) {
        return [...roleOrdered, ...plainStrings];
      }
      if (plainStrings.isNotEmpty) {
        return plainStrings;
      }
    }
    final t1 =
        (cMap['task1_entityAndCollisionFoundation'] ?? '').toString().trim();
    final t2 = (cMap['task2_coreActionAndMath'] ?? '').toString().trim();
    final t3 = (cMap['task3_feedbackAndBoundaryGuard'] ?? '').toString().trim();
    final extra = _parseStringList(cMap['additionalTasks']);
    return <String>[
      if (t1.isNotEmpty) t1,
      if (t2.isNotEmpty) t2,
      if (t3.isNotEmpty) t3,
      ...extra,
    ];
  }

  /// Extracts optional inline `subSteps` (`Do -> Copy -> Verify`) attached to `tasks[]` in `commit_release_plan`.
  static Map<int, List<Map<String, String>>> extractCheckpointTaskSubStepsFromMap(
    Map cMap,
  ) {
    final rawTasks = cMap['tasks'];
    if (rawTasks is! List || rawTasks.isEmpty) return const {};
    final foundations = <List<Map<String, String>>>[];
    final actions = <List<Map<String, String>>>[];
    final guards = <List<Map<String, String>>>[];
    for (final item in rawTasks) {
      if (item is! Map) continue;
      final title =
          (item['title'] ?? item['task'] ?? item['text'] ?? '')
              .toString()
              .trim();
      if (title.isEmpty || title == '...') continue;
      final parsedSteps = <Map<String, String>>[];
      final rawSubSteps = item['subSteps'];
      if (rawSubSteps is List) {
        for (final sub in rawSubSteps) {
          if (sub is Map) {
            parsedSteps.add({
              for (final kv in sub.entries)
                kv.key.toString(): kv.value?.toString().trim() ?? '',
            });
          }
        }
      }
      final role = (item['role'] ?? '').toString().trim().toLowerCase();
      if (role.contains('foundation') || role.contains('entity')) {
        foundations.add(parsedSteps);
      } else if (role.contains('guard') ||
          role.contains('feedback') ||
          role.contains('boundary')) {
        guards.add(parsedSteps);
      } else {
        actions.add(parsedSteps);
      }
    }
    final ordered = <List<Map<String, String>>>[
      ...foundations,
      ...actions,
      ...guards,
    ];
    final result = <int, List<Map<String, String>>>{};
    for (int i = 0; i < ordered.length; i++) {
      if (ordered[i].isNotEmpty) {
        result[i] = ordered[i];
      }
    }
    return result;
  }

  /// Native Gemini Tool Declaration for `planRelease` (`commit_release_plan`).
  /// Enforces 100% dynamic counts for Epics (`beats`), Features (`features`), and Checkpoint Tasks (`tasks`),
  /// while enforcing Foundation-First task role progression (`entity_and_collision_foundation` ->
  /// `1..N core_action_and_math` -> `feedback_and_boundary_guard`) at the schema level.
  static const Map<String, dynamic> commitReleasePlanTool = {
    'name': 'commit_release_plan',
    'description':
        'Commits the structured Epic and Feature Release Plan Blueprint with dynamic Epic, Feature, and Task counts.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'releasePhase': {'type': 'STRING'},
        'releaseTitle': {'type': 'STRING'},
        'builtSoFar': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'missingGaps': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'agentReasoning': {'type': 'STRING'},
        'questions': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'id': {'type': 'STRING'},
              'question': {'type': 'STRING'},
              'options': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
              },
            },
            'required': ['question', 'options'],
          },
        },
        'goal': {'type': 'STRING'},
        'doneWhen': {'type': 'STRING'},
        'explicitExclusions': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'beats': {
          'type': 'ARRAY',
          'description':
              'Dynamic list of Epics required to build the game loop end-to-end (zero artificial Epic count limits).',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'id': {'type': 'STRING'},
              'title': {'type': 'STRING'},
              'goal': {'type': 'STRING'},
              'doneWhen': {'type': 'STRING'},
              'features': {
                'type': 'ARRAY',
                'description':
                    'Dynamic list of singular-focused Playable Features required to complete this Epic end-to-end.',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'id': {'type': 'STRING'},
                    'title': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.featureTitleSchemaDesc,
                    },
                    'goal': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
                    },
                    'doneWhen': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.causalTriggerResultSchemaDesc,
                    },
                    'estimatedHours': {'type': 'INTEGER'},
                    'included': {
                      'type': 'BOOLEAN',
                      'description':
                          'Whether this feature is checked/active in the current release scope (defaults to true).',
                    },
                    'lifecycle': {
                      'type': 'STRING',
                      'enum': ['new', 'upgrade', 'stable', 'superseded'],
                    },
                    'supersedesFeatureTitle': {
                      'type': 'STRING',
                      'description':
                          'Optional title of an earlier feature that this feature replaces/supersedes.',
                    },
                    'primarySharedScriptOrScene': {
                      'type': 'STRING',
                      'description':
                          'Optional shared script, scene, prefab, or Blueprint asset for this feature.',
                    },
                    'inScope': {
                      'type': 'ARRAY',
                      'description':
                          LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
                      'items': {'type': 'STRING'},
                    },
                    'tuningParams': {
                      'type': 'ARRAY',
                      'items': {
                        'type': 'STRING',
                        'description':
                            LayersTextStyleGuide.tuningParamSchemaDesc,
                      },
                    },
                    'edgeCases': {
                      'type': 'ARRAY',
                      'description': LayersTextStyleGuide.stateGuardSchemaDesc,
                      'items': {'type': 'STRING'},
                    },
                    'checkpoints': {
                      'type': 'ARRAY',
                      'items': {
                        'type': 'OBJECT',
                        'properties': {
                          'title': {'type': 'STRING'},
                          'playtestCriteria': {
                            'type': 'STRING',
                            'description': LayersTextStyleGuide
                                .causalTriggerResultSchemaDesc,
                          },
                          'tasks': {
                            'type': 'ARRAY',
                            'description':
                                'Dynamic list of sequential tasks required to build and verify this checkpoint on one shared asset. Start with entity_and_collision_foundation, include as many core_action_and_math tasks as the mechanic requires, and finish with feedback_and_boundary_guard.',
                            'items': {
                              'type': 'OBJECT',
                              'required': ['role', 'title'],
                              'properties': {
                                'role': {
                                  'type': 'STRING',
                                  'enum': [
                                    'entity_and_collision_foundation',
                                    'core_action_and_math',
                                    'feedback_and_boundary_guard',
                                  ],
                                },
                                'title': {
                                  'type': 'STRING',
                                  'description': LayersTextStyleGuide
                                      .taskGroupTitleSchemaDesc,
                                },
                                'goal': {
                                  'type': 'STRING',
                                  'description': LayersTextStyleGuide
                                      .taskGroupGoalSchemaDesc,
                                },
                                'subSteps': {
                                  'type': 'ARRAY',
                                  'description':
                                      'Optional inline engine-specific Do / Copy / Verify sub-steps for this task.',
                                  'items': {
                                    'type': 'OBJECT',
                                    'required': [
                                      'title',
                                      'stepPath',
                                      'instruction',
                                      'codeFormula',
                                      'verifyResult',
                                    ],
                                    'properties': {
                                      'title': {'type': 'STRING'},
                                      'stepPath': {'type': 'STRING'},
                                      'instruction': {'type': 'STRING'},
                                      'area1Hierarchy': {'type': 'STRING'},
                                      'area2Inspector': {'type': 'STRING'},
                                      'codeFormula': {'type': 'STRING'},
                                      'verifyResult': {'type': 'STRING'},
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                        'required': ['title', 'playtestCriteria', 'tasks'],
                      },
                    },
                  },
                  'required': [
                    'id',
                    'title',
                    'goal',
                    'doneWhen',
                    'estimatedHours',
                    'lifecycle',
                    'tuningParams',
                    'edgeCases',
                    'checkpoints',
                  ],
                },
              },
            },
            'required': ['id', 'title', 'goal', 'doneWhen', 'features'],
          },
        },
      },
      'required': ['releaseTitle', 'goal', 'doneWhen', 'beats'],
    },
  };

  /// Native Gemini Tool Declaration for Phase 1 of Section-by-Section Workbench Build (`commit_release_system_epics`).
  /// Synthesizes ONLY the System Epics (`E01`..`EN` — major gameplay systems / bodies of work) needed to accomplish the Core Loop.
  static const Map<String, dynamic> commitReleaseSystemEpicsTool = {
    'name': 'commit_release_system_epics',
    'description':
        'Commits the ordered System Epics (E01..EN) representing the major gameplay systems, mechanics, and engineering bodies of work required to make the Concept Blueprint Core Loop work (never word-for-word loop beat copies).',
    'parameters': {
      'type': 'OBJECT',
      'required': ['releaseTitle', 'goal', 'doneWhen', 'epics'],
      'properties': {
        'releaseTitle': {'type': 'STRING'},
        'goal': {'type': 'STRING'},
        'doneWhen': {'type': 'STRING'},
        'epics': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['id', 'title', 'goal', 'doneWhen'],
            'properties': {
              'id': {'type': 'STRING'},
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.epicTitleSchemaDesc,
              },
              'goal': {'type': 'STRING'},
              'doneWhen': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for Phase 2 of Section-by-Section Workbench Build (`commit_epic_features`).
  /// Synthesizes the playable Features (and their tasks, tuning parameters, and guards) for a SINGLE System Epic.
  static const Map<String, dynamic> commitEpicFeaturesTool = {
    'name': 'commit_epic_features',
    'description':
        'Commits the ordered playable Features (1..M) needed to build a single System Epic in engineering build-dependency order.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['features'],
      'properties': {
        'features': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': [
              'title',
              'goal',
              'doneWhen',
              'estimatedHours',
              'inScope',
              'tuningParams',
              'edgeCases',
              'checkpointTitle',
              'playtestCriteria',
              'tasks',
            ],
            'properties': {
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.featureTitleSchemaDesc,
              },
              'goal': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
              },
              'doneWhen': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
              'estimatedHours': {'type': 'INTEGER'},
              'primarySharedScriptOrScene': {'type': 'STRING'},
              'inScope': {
                'type': 'ARRAY',
                'description':
                    LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
                'items': {'type': 'STRING'},
              },
              'tuningParams': {
                'type': 'ARRAY',
                'items': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.tuningParamSchemaDesc,
                },
              },
              'edgeCases': {
                'type': 'ARRAY',
                'description': LayersTextStyleGuide.stateGuardSchemaDesc,
                'items': {'type': 'STRING'},
              },
              'checkpointTitle': {'type': 'STRING'},
              'playtestCriteria': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
              'tasks': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': ['role', 'title'],
                  'properties': {
                    'role': {
                      'type': 'STRING',
                      'enum': [
                        'entity_and_collision_foundation',
                        'core_action_and_math',
                        'feedback_and_boundary_guard',
                      ],
                    },
                    'title': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.taskGroupTitleSchemaDesc,
                    },
                    'goal': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.taskGroupGoalSchemaDesc,
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for Pass 1 of Section-by-Section Progressive Release (`commit_progressive_release_focus`).
  /// Synthesizes ONLY Section 1 (`releaseTitle`, `goal`, `doneWhen`, `missingGaps`, 3 Strategic Options, and `targetEpicNumbers`)
  /// so Section 1 renders in ~1.5 seconds before Section 2 streams Epic-by-Epic.
  static const Map<String, dynamic> commitProgressiveReleaseFocusTool = {
    'name': 'commit_progressive_release_focus',
    'description':
        'Commits Section 1 of the Progressive Release Plan (Release Title, Goal, Done When, Lacking Now gaps, 3 Strategic Focus Options, and Target Epic Numbers).',
    'parameters': {
      'type': 'OBJECT',
      'required': [
        'releasePhase',
        'releaseTitle',
        'goal',
        'doneWhen',
        'missingGaps',
        'questions',
        'targetEpicNumbers',
      ],
      'properties': {
        'releasePhase': {'type': 'STRING'},
        'releaseTitle': {'type': 'STRING'},
        'builtSoFar': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'missingGaps': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.progressiveMissingGapSchemaDesc,
          'items': {'type': 'STRING'},
        },
        'agentReasoning': {'type': 'STRING'},
        'goal': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.blufReleaseGoalSchemaDesc,
        },
        'doneWhen': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.causalTriggerResultSchemaDesc,
        },
        'targetEpicNumbers': {
          'type': 'ARRAY',
          'description':
              '1-based Epic numbers (1..N) that this release will upgrade or add new features to.',
          'items': {'type': 'INTEGER'},
        },
        'questions': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['question', 'options'],
            'properties': {
              'id': {'type': 'STRING'},
              'question': {'type': 'STRING'},
              'options': {
                'type': 'ARRAY',
                'description':
                    LayersTextStyleGuide.progressiveEpicOptionSchemaDesc,
                'items': {'type': 'STRING'},
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for Pass 2 of Section-by-Section Progressive Release (`commit_progressive_epic_changes`).
  /// Synthesizes the `upgrade` and `new` Features for a SINGLE target Epic in the Progressive Release Co-Pilot.
  static const Map<String, dynamic> commitProgressiveEpicChangesTool = {
    'name': 'commit_progressive_epic_changes',
    'description':
        'Commits the active UPGRADE and NEW features for a single target Epic in the Progressive Release Co-Pilot.',
    'parameters': {
      'type': 'OBJECT',
      'required': ['features'],
      'properties': {
        'features': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': [
              'title',
              'lifecycle',
              'goal',
              'doneWhen',
              'estimatedHours',
              'inScope',
              'tuningParams',
              'edgeCases',
              'checkpointTitle',
              'playtestCriteria',
              'tasks',
            ],
            'properties': {
              'id': {'type': 'STRING'},
              'title': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.featureTitleSchemaDesc,
              },
              'lifecycle': {
                'type': 'STRING',
                'enum': ['upgrade', 'new', 'superseded'],
              },
              'goal': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
              },
              'doneWhen': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
              'estimatedHours': {'type': 'INTEGER'},
              'primarySharedScriptOrScene': {'type': 'STRING'},
              'inScope': {
                'type': 'ARRAY',
                'description':
                    LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
                'items': {'type': 'STRING'},
              },
              'tuningParams': {
                'type': 'ARRAY',
                'items': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.tuningParamSchemaDesc,
                },
              },
              'edgeCases': {
                'type': 'ARRAY',
                'description': LayersTextStyleGuide.stateGuardSchemaDesc,
                'items': {'type': 'STRING'},
              },
              'checkpointTitle': {'type': 'STRING'},
              'playtestCriteria': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalTriggerResultSchemaDesc,
              },
              'tasks': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'required': ['role', 'title'],
                  'properties': {
                    'role': {
                      'type': 'STRING',
                      'enum': [
                        'entity_and_collision_foundation',
                        'core_action_and_math',
                        'feedback_and_boundary_guard',
                      ],
                    },
                    'title': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.taskGroupTitleSchemaDesc,
                    },
                    'goal': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.taskGroupGoalSchemaDesc,
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  };

  /// Native Gemini Tool Declaration for `sendReleasePlanChatTurn` (`mutate_release_plan`).
  static const Map<String, dynamic> mutateReleasePlanTool = {
    'name': 'mutate_release_plan',
    'description':
        'Applies delta updates to the Release Plan Blueprint in response to a developer request or strategic focus selection.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'reply': {'type': 'STRING'},
        'goal': {'type': 'STRING'},
        'doneWhen': {'type': 'STRING'},
        'explicitExclusions': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'beats': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'id': {'type': 'STRING'},
              'title': {'type': 'STRING'},
              'goal': {'type': 'STRING'},
              'doneWhen': {'type': 'STRING'},
              'features': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'id': {'type': 'STRING'},
                    'title': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.featureTitleSchemaDesc,
                    },
                    'goal': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.changelogDeltaGoalSchemaDesc,
                    },
                    'doneWhen': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.causalTriggerResultSchemaDesc,
                    },
                    'estimatedHours': {'type': 'INTEGER'},
                    'included': {'type': 'BOOLEAN'},
                    'lifecycle': {
                      'type': 'STRING',
                      'enum': ['new', 'upgrade', 'stable', 'superseded'],
                    },
                    'supersedesFeatureTitle': {'type': 'STRING'},
                    'primarySharedScriptOrScene': {'type': 'STRING'},
                    'inScope': {
                      'type': 'ARRAY',
                      'description':
                          LayersTextStyleGuide.changelogDeltaInScopeSchemaDesc,
                      'items': {'type': 'STRING'},
                    },
                    'tuningParams': {
                      'type': 'ARRAY',
                      'items': {
                        'type': 'STRING',
                        'description':
                            LayersTextStyleGuide.tuningParamSchemaDesc,
                      },
                    },
                    'edgeCases': {
                      'type': 'ARRAY',
                      'description': LayersTextStyleGuide.stateGuardSchemaDesc,
                      'items': {'type': 'STRING'},
                    },
                    'checkpoints': {
                      'type': 'ARRAY',
                      'items': {
                        'type': 'OBJECT',
                        'properties': {
                          'title': {'type': 'STRING'},
                          'playtestCriteria': {
                            'type': 'STRING',
                            'description': LayersTextStyleGuide
                                .causalTriggerResultSchemaDesc,
                          },
                          'tasks': {
                            'type': 'ARRAY',
                            'description':
                                'Dynamic list of sequential tasks for this checkpoint ordered from entity_and_collision_foundation -> core_action_and_math (1..N) -> feedback_and_boundary_guard.',
                            'items': {
                              'type': 'OBJECT',
                              'required': ['role', 'title'],
                              'properties': {
                                'role': {
                                  'type': 'STRING',
                                  'enum': [
                                    'entity_and_collision_foundation',
                                    'core_action_and_math',
                                    'feedback_and_boundary_guard',
                                  ],
                                },
                                'title': {
                                  'type': 'STRING',
                                  'description': LayersTextStyleGuide
                                      .taskGroupTitleSchemaDesc,
                                },
                                'goal': {
                                  'type': 'STRING',
                                  'description': LayersTextStyleGuide
                                      .taskGroupGoalSchemaDesc,
                                },
                                'subSteps': {
                                  'type': 'ARRAY',
                                  'description':
                                      'Optional inline engine-specific Do / Copy / Verify sub-steps for this task.',
                                  'items': {
                                    'type': 'OBJECT',
                                    'required': [
                                      'title',
                                      'stepPath',
                                      'instruction',
                                      'codeFormula',
                                      'verifyResult',
                                    ],
                                    'properties': {
                                      'title': {'type': 'STRING'},
                                      'stepPath': {'type': 'STRING'},
                                      'instruction': {'type': 'STRING'},
                                      'area1Hierarchy': {'type': 'STRING'},
                                      'area2Inspector': {'type': 'STRING'},
                                      'codeFormula': {'type': 'STRING'},
                                      'verifyResult': {'type': 'STRING'},
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      'required': ['reply', 'beats'],
    },
  };

  static String extractReleaseVersionTag(String releaseTitle) {
    final match = _releaseVersionRegex.firstMatch(releaseTitle);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'v0.1';
  }

  /// Synthesizes a `ReleaseBlueprint` for `releaseDoc` via Gemini AI (`gemini-flash-latest`).
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ReleaseBlueprint?> planRelease({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    List<TierDocument> completedReleases = const [],
    List<TierDocument> existingBeats = const [],
    Map<String, List<TierDocument>> existingFeaturesByBeat = const {},
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
    FullProductionBlueprint? fullProductionBlueprint,
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
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
    final gameSpecText =
        projectDoc.sections['game_spec'] ?? projectDoc.sections['gameSpec'] ?? '';
    final techSpecText =
        projectDoc.sections['tech_spec'] ?? projectDoc.sections['techSpec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ??
        projectDoc.sections['designPillars'] ??
        '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ??
        projectDoc.sections['tradeOffs'] ??
        '';

    final bool isPhaseLocked =
        releaseDoc.sections['phaseLockedByUser'] == 'true';

    final mvpVerTags = <String>{
      for (final r in completedReleases)
        if ((r.sections['phase'] ?? '') == ProductionPhase.mvp.name ||
            r.releaseScope == ReleaseScope.mvp)
          extractReleaseVersionTag(
            r.sections['versionTag']?.isNotEmpty == true
                ? r.sections['versionTag']!
                : r.title,
          ).toLowerCase(),
    };
    final vsVerTags = <String>{
      for (final r in completedReleases)
        if ((r.sections['phase'] ?? '') == ProductionPhase.verticalSlice.name ||
            r.releaseScope == ReleaseScope.verticalSlice)
          extractReleaseVersionTag(
            r.sections['versionTag']?.isNotEmpty == true
                ? r.sections['versionTag']!
                : r.title,
          ).toLowerCase(),
    };

    final uncoveredMvpBeats = <String>[];
    final unupgradedProtoFeatures = <String>[];
    final unpolishedVsBeats = <String>[];
    final unpolishedVsFeatures = <String>[];

    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final b = existingBeats[bIdx];
      if (b.isFullProductionEpic) continue;
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = (existingFeaturesByBeat[b.id] ?? const <TierDocument>[])
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      bool beatHasMvp = false;
      bool beatHasVs = false;
      for (final f in feats) {
        final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
        final states = FeatureStateNode.getStatesForDocument(f);
        final hasMvpCp = mvpVerTags.contains(originVer) ||
            states.any((s) => mvpVerTags.contains(s.releaseVersion.toLowerCase()));
        final hasVsCp = vsVerTags.contains(originVer) ||
            states.any((s) => vsVerTags.contains(s.releaseVersion.toLowerCase()));
        if (hasMvpCp) beatHasMvp = true;
        if (hasVsCp) {
          beatHasVs = true;
        } else {
          unpolishedVsFeatures.add('$eTag "${f.title}"');
        }
        if (originVer == 'v0.1') {
          final upgradedPostV01 = states.any(
            (s) => s.releaseVersion.toLowerCase() != 'v0.1',
          );
          if (!upgradedPostV01 && !hasMvpCp) {
            unupgradedProtoFeatures.add('$eTag "${f.title}"');
          }
        }
      }
      if (!beatHasMvp) {
        uncoveredMvpBeats.add('$eTag "${b.title}"');
      }
      if (!beatHasVs) {
        unpolishedVsBeats.add('$eTag "${b.title}"');
      }
    }

    final isFpSkeleton = releaseDoc.sections['fpSkeleton'] == 'true';
    final String phaseInstruction;
    if (isFpSkeleton) {
      phaseInstruction =
          '- ACT 2 FULL-GAME SKELETON ($versionTag · FIRST FULL PRODUCTION RELEASE): The Vertical Slice is finished. Every existing Beat/Feature in the Existing Live Game Tree stays `"stable"` (omit them from JSON). Read the ENTIRE Full Production Blueprint (01–06) and create as many brand-new Beats/Epics (unique `"id"` values like `"fp_beat_1"`, titles that do NOT reuse existing Beat titles) and `"lifecycle": "new"` Features as the full v1.0 game needs, as a rough playable pass so the full game connects from launch to credits. Model added content (enemy types, bosses, biomes, items) as separate NEW Features that plug into the existing core scripts listed in the tree instead of rebuilding them. Order Epics and Features by engineering build dependency and honor `05 Permanent Cuts`. Loop beats are NOT Epics—decide the Epic breakdown yourself.';
    } else if (prototypePart == '1' && !isSubsequentRelease) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 1 OF 2 — CONTROLS & PRIMARY MECHANICS): Only plan the first ${(coreLoopItems.length / 2).ceil()} Core Loop Beats in `v0.1` so the developer can prove primary controls and core mechanics first (the remaining Beats are reserved for `v0.2` Prototype Part 2).';
    } else if (prototypePart == '2' ||
        (releasePhase == ProductionPhase.prototype.name &&
            isSubsequentRelease &&
            !isPhaseLocked)) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 2 OF 2 — FULL CORE LOOP): Output ONLY the remaining Stage 1 Core Loop Beats as `"lifecycle": "new"` so the complete greybox loop connects end-to-end (omit untouched `v0.1` Beats & Features from JSON—they are automatically preserved as `STABLE ✓` (`0h`)).';
    } else if (isAgentReasoned ||
        (releasePhase == ProductionPhase.mvp.name &&
            targetMvpEpicIndex == null)) {
      final mvpCoverageHint = (uncoveredMvpBeats.isNotEmpty ||
              unupgradedProtoFeatures.isNotEmpty)
          ? '\n     * Still-Greybox v0.1 Epics needing MVP coverage: ${uncoveredMvpBeats.isNotEmpty ? uncoveredMvpBeats.join(', ') : 'All Epics touched once'}\n'
              '     * Still-Greybox v0.1 Features awaiting MVP upgrade: ${unupgradedProtoFeatures.isNotEmpty ? unupgradedProtoFeatures.join(', ') : 'None'}\n'
              '     * Prioritize upgrading the next cohesive batch of these still-greybox v0.1 Epics & Features (and adding any missing functional mechanics for them) rather than re-upgrading features that already received an MVP pass.'
          : '';
      final vsCoverageHint = (unpolishedVsBeats.isNotEmpty ||
              unpolishedVsFeatures.isNotEmpty)
          ? '\n     * Unpolished Epics needing Vertical Slice pass: ${unpolishedVsBeats.isNotEmpty ? unpolishedVsBeats.join(', ') : 'All Epics touched once'}\n'
              '     * Features awaiting Vertical Slice polish: ${unpolishedVsFeatures.take(8).join(', ')}\n'
              '     * Prioritize bringing the next cohesive batch of these unpolished Epics & Features up to Gold Standard polish rather than re-polishing already-polished features.'
          : '';
      final phaseTargetDirective = releasePhase ==
              ProductionPhase.postLaunch.name
          ? '  1. TARGET PHASE IS `"postLaunch"` (POST-LAUNCH & LIVE OPS — $versionTag): Set `"releasePhase": "postLaunch"` and a descriptive `"releaseTitle"` (`"$versionTag: <Live Ops / Content / Balance Focus>"`). Focus on shipping post-launch content expansions, live tuning balance passes, and playtest `[GUARD]` hardening without breaking `v1.0` save compatibility.'
          : (releasePhase == ProductionPhase.verticalSlice.name
              ? '  1. TARGET PHASE IS `"verticalSlice"` (MULTI-RELEASE VERTICAL SLICE POLISH TRACK): Set `"releasePhase": "verticalSlice"` and a descriptive `"releaseTitle"` (`"$versionTag: <Polish & Feel Focus>"`). Focus upgrades on visual/material polish, SFX/VFX & camera/hit-stop feel cues, HUD readability, and state/frame guards across unpolished Core Loop Beats.$vsCoverageHint'
              : (releasePhase == ProductionPhase.fullProduction.name
                  ? '  1. TARGET PHASE IS `"fullProduction"` (FULL PRODUCTION PASS): Set `"releasePhase": "fullProduction"` and a descriptive `"releaseTitle"` (`"$versionTag: <Full Production Focus>"`). Upgrade only Full Production Epics (Beats tagged [FULL PRODUCTION EPIC]) to the Vertical Slice quality bar (content depth + feel polish in one pass); core Concept Epics stay `"stable"`.'
                  : '  1. TARGET PHASE IS `"mvp"` (MULTI-RELEASE MVP TRACK): Set `"releasePhase": "mvp"` and a specific, descriptive `"releaseTitle"` (`"$versionTag: <Concrete MVP Focus>"`). Bring the next cohesive group of greybox prototype mechanics up to functional MVP depth across the Core Loop and Design Pillars.$mvpCoverageHint'));
      phaseInstruction =
          '- AGENT-REASONED PROGRESSIVE RELEASE ($versionTag): You are the Lead Game Architect deciding what "${projectDoc.title}" needs next in $versionTag by evaluating the Existing Live Game Tree against the Stage 1 Design Pillars, Trade-Offs, Core Loop Beats, and Out-of-Scope Backlog:\n'
          '$phaseTargetDirective\n'
          '  2. Decide which existing Features need an `"upgrade"` vs. which remain `"stable"`, and what `"new"` Features to introduce across ANY of the Core Loop Beats—with zero artificial count limits: include whatever set of `"upgrade"` and `"new"` Features across whichever Beats are required to make $versionTag a complete, cohesive playable milestone.\n'
          '  3. DELTA-ONLY JSON OUTPUT (DO NOT REPEAT STABLE FEATURES): In `beats`, output ONLY the Beats and Features receiving active work in $versionTag (`"lifecycle": "upgrade"` or `"lifecycle": "new"`). Use the exact Beat `id` (e.g. `"beat_1"`) and Feature `id`/`title` from the Existing Live Game Tree when upgrading. Do NOT output untouched `"stable"` features in JSON—all omitted existing Beats and Features are automatically preserved as `STABLE ✓` (`0h`).\n'
          '  4. Strictly enforce the Project Exclusions active for this phase: NEVER include or promote any feature that violates a permanent Exclusion (`[NEVER]` / `[CUT]`), while early-phase deferred exclusions (`"in v0.1"`, `"in prototype"`, `"in greybox"`, `[DEFERRED]`) are now unlocked for promotion in Vertical Slice / Full Production.';
    } else if (releasePhase == ProductionPhase.postLaunch.name) {
      phaseInstruction =
          '- PHASE 5 POST-LAUNCH & LIVE OPS ($versionTag): Expand live content rosters, balance tuning parameters, and harden `[PLAYTEST GUARD]` rules on top of the shipped `v1.0` build without breaking save compatibility.';
    } else if (releasePhase == ProductionPhase.mvp.name ||
        targetMvpEpicIndex != null) {
      final epicNum = (targetMvpEpicIndex ?? 0) + 1;
      phaseInstruction =
          '- PHASE 2 PER-EPIC MVP RELEASE (TARGET: EPIC $epicNum ONLY): Output ONLY Beat/Epic #$epicNum with its `"lifecycle": "upgrade"` delta MVP checkpoints and any queued `"lifecycle": "new"` features for Epic #$epicNum (omit untouched Epics `!= $epicNum` from JSON—they are automatically preserved as `STABLE ✓` (`0h`)).';
    } else if (releasePhase == ProductionPhase.verticalSlice.name ||
        preset == ReleaseScope.verticalSlice) {
      phaseInstruction =
          '- PHASE 3 VERTICAL SLICE (GOLD STANDARD LEVEL): Combine all completed MVP Epics into 1 polished Gold Standard showcase level by upgrading the primary feature in EVERY Beat/Epic (`"lifecycle": "upgrade"`) with a Vertical Slice polish checkpoint (Final Art & Material Swap, SFX/VFX & Camera Feel Cues, HUD Readability & Frame Guard).';
    } else if (releasePhase == ProductionPhase.fullProduction.name ||
        preset == ReleaseScope.fullProduction) {
      phaseInstruction =
          '- PHASE 4 FULL PRODUCTION PASS: Upgrade 1–2 Full Production Epics (Beats tagged [FULL PRODUCTION EPIC]) to the Vertical Slice quality bar with `"lifecycle": "upgrade"` checkpoints (content depth + feel polish in one pass). Core Concept Epics stay `"stable"` (omit them from JSON).';
    } else {
      phaseInstruction =
          '- PHASE 1 PLAYABLE PROTOTYPE (`v0.1` GREYBOX CORE LOOP): Organize `beats` into the exact number of Epics required to build ${releaseDoc.title} end-to-end across the Concept Blueprint (`01 Goal` through `08 Done When`), breaking each Epic into as many singular-focused greybox Features as its mechanics genuinely require.';
    }

    final targetPhase = switch (releasePhase) {
      'postLaunch' => ProductionPhase.postLaunch,
      'fullProduction' => ProductionPhase.fullProduction,
      'verticalSlice' => ProductionPhase.verticalSlice,
      'mvp' => ProductionPhase.mvp,
      'prototype' => ProductionPhase.prototype,
      _ => isSubsequentRelease
          ? ProductionPhase.mvp
          : ProductionPhase.prototype,
    };

    bool conflictsWithExclusions(String featureTitle) {
      final cleanFeat = featureTitle
          .toLowerCase()
          .replaceFirst(_noPrefixRegex, '')
          .trim();
      if (cleanFeat.isEmpty) return false;
      for (final ex in projectExclusions) {
        if (!ReleaseBlueprint.isExclusionActiveForPhase(ex, targetPhase)) {
          continue;
        }
        final cleanEx = ex
            .toLowerCase()
            .replaceFirst(_cutPrefixRegex, '')
            .replaceFirst(_noPrefixRegex, '')
            .trim();
        if (cleanEx.isNotEmpty &&
            (cleanEx.contains(cleanFeat) || cleanFeat.contains(cleanEx))) {
          return true;
        }
      }
      return false;
    }

    final existingTreeSummary = StringBuffer();
    if (completedReleases.isNotEmpty) {
      existingTreeSummary.writeln(
        'Completed Prior Releases History (all previous releases in chronological order):',
      );
      for (final priorRel in completedReleases) {
        final pVer = extractReleaseVersionTag(
          priorRel.sections['versionTag']?.isNotEmpty == true
              ? priorRel.sections['versionTag']!
              : priorRel.title,
        );
        final pPhase =
            priorRel.sections['phase'] ?? priorRel.releaseScope.name;
        final pGoal = SectionTextUtils.resolveGoal(priorRel.sections);
        final touchedFeats = <String>[];
        for (final b in existingBeats) {
          final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
          for (final f in feats) {
            final states = FeatureStateNode.getStatesForDocument(f);
            final originVer = f.sections['originVersion'] ?? 'v0.1';
            if (originVer.toLowerCase() == pVer.toLowerCase() ||
                states.any(
                  (s) => s.releaseVersion.toLowerCase() == pVer.toLowerCase(),
                )) {
              touchedFeats.add(f.title);
            }
          }
        }
        existingTreeSummary.writeln(
          '- $pVer [$pPhase] "${priorRel.title}": ${pGoal.isNotEmpty ? pGoal : "Completed milestone"}'
          '${touchedFeats.isNotEmpty ? " | Built/Upgraded: ${touchedFeats.join(", ")}" : ""}',
        );
      }
    }
    if (existingBeats.isNotEmpty) {
      existingTreeSummary.writeln(
        'Existing Live Game Tree (all Epics, Features, and completed Checkpoints across prior releases):',
      );
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final b = existingBeats[bIdx];
        existingTreeSummary.writeln(
          '- Beat "${b.title}" (${b.id})${b.isFullProductionEpic ? ' [FULL PRODUCTION EPIC]' : ''}:',
        );
        final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
        for (final f in feats) {
          if (f.sections['lifecycle'] ==
              FeatureLifecycleStatus.superseded.name) {
            final pivotNote = (f.sections['pivotReason'] ??
                    f.sections['pivot_reason'] ??
                    '')
                .trim();
            existingTreeSummary.writeln(
              '  * SUPERSEDED / ARCHIVED TESTBED: "${f.title}" [id: ${f.id}${pivotNote.isNotEmpty ? ', reason: $pivotNote' : ''}] — Propose a `"lifecycle": "new"` replacement mechanic in this Beat if needed.',
            );
            continue;
          }
          final states = FeatureStateNode.getStatesForDocument(f);
          final originVer = f.sections['originVersion'] ?? 'v0.1';
          final allTuning = <String>{};
          final allFixesAndGuards = <String>{};
          for (final s in states) {
            allTuning.addAll(s.tuningParams);
            allFixesAndGuards.addAll(s.edgeCases);
          }
          final latestCp = states.isNotEmpty
              ? '${states.last.releaseVersion} "${states.last.cleanStageTitle}"'
              : originVer;
          final fullCheckpointChain = states.isNotEmpty
              ? states.map((s) {
                  final tasksText = s.checklist
                      .map((t) => t.text.replaceAll(_durationRegex, '').trim())
                      .where((t) => t.isNotEmpty)
                      .take(4)
                      .join(', ');
                  return '${s.releaseVersion} "${s.cleanStageTitle}"${tasksText.isNotEmpty ? " (tasks: $tasksText)" : ""}';
                }).join(' -> ')
              : originVer;
          final primaryAsset = (f.sections['primary_asset'] ?? '').trim();
          existingTreeSummary.writeln(
            '  * Feature "${f.title}" [id: ${f.id}, origin: $originVer, ${states.length} checkpoints (latest: $latestCp | history: $fullCheckpointChain)]'
            '${primaryAsset.isNotEmpty ? ' | Primary Asset: $primaryAsset' : ''}'
            '${allTuning.isNotEmpty ? ' | Live Variables: ${allTuning.take(3).join(', ')}' : ''}'
            '${allFixesAndGuards.isNotEmpty ? ' | Guards: ${allFixesAndGuards.take(2).join('; ')}' : ''}',
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
    final projectDoneWhen =
        SectionTextUtils.resolveDoneWhen(projectDoc.sections);
    final effectiveModel = modelName.contains('argon')
        ? 'gemini-flash-latest'
        : modelName;
    final progressiveDiagnosticInstructions = isSubsequentRelease
        ? '''
- ARCHITECTURAL DIAGNOSTIC ("builtSoFar" & "missingGaps"):
  * `"builtSoFar"`: List 2–4 concise 2–5 word phrases summarizing the core mechanics already built and verified in prior releases (e.g., `["Slide & Air Strafe", "Rocket & Gib Shatter", "Room Clear & Pedestals"]`).
  * `"missingGaps"`: List 2–4 concise 1-line statements naming the exact playable gaps in the current build prefixed with the Beat tag (e.g., `["E01: No incoming enemy projectiles to dodge while air-strafing", "E02: Missing rapid-fire plasma weapon", "E05: Single room only — no multi-room chain or boss"]`).
  * `"agentReasoning"`: 1–2 concise summary sentences tying the gaps to $versionTag's focus.
- BESPOKE GAME-SPECIFIC STRATEGIC OPTIONS ("questions"): In `questions[0]`, ask 1 architectural priority question for $versionTag with 3 concrete options tailored specifically to "${projectDoc.title}"'s actual mechanics (Option 1 prefixed with `(Recommended)` matching your primary plan; Options 2 and 3 offering distinct, game-specific alternative angles for $versionTag).'''
        : '';
    final prompt = '''
You are the Antigravity Release Planner Agent (`$effectiveModel`) planning Release: "${releaseDoc.title}" ($versionTag, ${preset.label}).
Full Concept Blueprint (01–08):
- 01 Goal: "$projectGoal" (Project: "${projectDoc.title}")
- 02 Game Spec: $gameSpecText
- 03 Tech Spec: $techSpecText
- 04 Design Pillars: $pillarsText
- 05 Trade-Offs: $tradeOffsText
- 06 Core Loop:
$numberedCoreLoopSummary
- 07 Out of Scope (Exclusions): ${projectExclusions.join(' | ')}
- 08 Done When: "$projectDoneWhen"
${fullProductionBlueprint != null ? '${fullProductionBlueprint.toPromptBlock()}\n' : ''}${existingTreeSummary.isNotEmpty ? existingTreeSummary.toString() : 'First Release (v0.1): No prior features exist yet.'}

${GeminiAgentClient.compactStyleRules}
$phaseInstruction
$progressiveDiagnosticInstructions
- STRICT ENGINEERING BUILD DEPENDENCY ORDER (FEATURE N DEPENDS ONLY ON 1..N-1): Stage 1 Core Loop Beats are chronological, but Stage 2 Epics & Features MUST be ordered by **Engineering Build Dependency** so every Feature `N` can be built and playtested in the engine using only scenes, physics bodies, and actions already created in Features `1..N-1`:
  * `Dependency Rule 1 (Surface / Space Before Actor)`: In Epic 1 (`beat_1`), always place the Greybox Level/Arena/Corridor Blockout feature at `Feature #1` BEFORE Player/Vehicle Locomotion at `Feature #2` (so a gravity-enabled body does not fall into the void).
  * `Dependency Rule 2 (Target Entity Before Tool / Tether / Resolver)`: Inside any Epic, always build the physical Target Object, Pickup Body, Container, or Enemy Spawner (`"Scrap Core Physics"`, `"Sentry Drone Spawner"`, `"Water Tank Container"`, `"Cargo Crate"`) BEFORE the Tether, Harpoon, Raycast, Weapon Impact, or Delivery Zone (`"Harpoon Tow Cable"`, `"Drone Projectile Impact"`, `"Winch Docking Zone"`) that attaches to or acts on it. Never put a tether or interaction before the object it hooks onto!
  * `Dependency Rule 3 (Base Mechanic Before Lock / Gate / Constraint)`: Always build the core playable action (`"Mature Crop Harvest"`, `"Heat Cannon Fire"`) BEFORE adding the lock, pressure seal, or overheat gate (`"Tank Seal Depressurize"`, `"Reactor Steam Vent"`) that restricts it.
- THOROUGH MULTI-FEATURE EPIC DECOMPOSITION: Break each Epic into the exact number of cohesive Playable Features (`"included": true`) needed to complete that Epic end-to-end for ${releaseDoc.title}. Group closely related controls, physics, and feedback into cohesive playable units; split into separate Feature cards inside an Epic whenever they represent distinct mechanics (e.g., planting vs. harvesting, or target spawner vs. weapon fire)!
- ZERO ARTIFICIAL COUNT LIMITS ON EPICS, FEATURES, OR TASKS: Never merge distinct features just to hit a smaller number, and never drop a mechanic mentioned in `01 Goal`, `02 Game Spec`, `04 Pillars`, `05 Trade-Offs`, `06 Core Loop`, or `08 Done When`.
- PLAYABLE BEAT COMPLETENESS (NO ORPHANED MECHANICS): Never leave a weapon, turret, or defense without a reactive enemy/threat/target feature to test it against, never leave a resource/crop system without both planting/spawning and harvesting/pickup features, and ensure the final Epic covers both the specific reward/upgrade payoff and starting the next cycle/run.
- PLAIN ACTION FEATURE TITLES (NO CODE OR FILLER SUFFIXES & NEVER CLONE EPIC TITLE): Every Feature must name 1 observable gameplay action or interactive world object (`2–3` plain game-dev words, e.g. `"Greybox Arena Layout"`, `"Player Dash"`, `"Enemy Wave Spawner"`, `"Loot Pickup"`, `"Upgrade Terminal"`). NEVER name a child Feature identical to its parent Epic (`beat.title`)—each Feature inside an Epic must name the specific playable action, tool, or object inside that Epic. NEVER use code-architecture or filler nouns (`"Controller"`, `"System"`, `"Mechanic"`, `"Manager"`, `"Component"`, `"Handler"`, `"Action"`, `"Loop"`) and NEVER combine two mechanics with `"&"` or `"and"` in a Feature title.
- RIGHT-SIZED GREYBOX FEATURES: Keep individual `v0.1` greybox features focused on unpolished playable functionality buildable in one sitting rather than lumping an entire physics or combat architecture into a single monolithic ticket.
- Keep temporary greybox testbeds in a separate Feature from permanent mechanics.
- MANDATORY TUNING PARAMETERS ON EVERY FEATURE (NEVER EMPTY): Every single Feature in `beats[].features[]` MUST include `2` to `3` concrete numeric tuning parameters in `"tuningParams"` formatted as `"paramName: value unit"` (e.g., `"moveSpeed: 6.0 m/s"`, `"dashCooldown: 0.8 s"`, `"pickupRadius: 1.5 m"`). NEVER return an empty `"tuningParams": []` array on any feature.
- DYNAMIC, CONCRETE TASKS ON ONE SHARED ASSET (NO REPETITIVE "SETUP / LOGIC / GUARD" SUFFIXES): Give each Feature checkpoint the exact number of concrete, mechanic-specific tasks (`2–4` words + duration tag) that its complexity genuinely requires—without mechanically ending every task in the words `"Setup"`, `"Logic"`, or `"Guard"`:
  * `entity_and_collision_foundation` (First Task): Create or place the specific playable Character, Greybox Room, Emitter, or Interactive Prop and its collision/ports in the level (e.g., `"Capsule Body & Camera (2h)"`, `"Arena Floor & Walls (2h)"`). NEVER put the words `"Input"`, `"Mapping"`, or `"Keybind"` in the foundation task's title.
  * `core_action_and_math` (`1..N` Middle Tasks): Wire the specific interaction, movement, or simulation behaviors onto that same shared asset (use 1 task for a simple action or multiple `core_action_and_math` tasks for a multi-step mechanic, e.g., `"WASD Velocity & Look (2h)"`, `"Burst Impulse & Trail (2h)"`).
  * `feedback_and_boundary_guard` (Final Task): Hook the visible/audible cue and physical clamp/limit onto that asset (e.g., `"Wall Slide & Pitch Clamp (1h)"`, `"Cooldown Lock & Flash (1h)"`).
- `lifecycle`: `"new"` for v0.1; for v0.2+, output only `"upgrade"` (delta hours/checkpoints only), `"new"`, or `"superseded"` (omit untouched `"stable"` features from JSON).
- THINKING VERIFICATION BEFORE EMITTING JSON:
  1. 100% Concept Coverage: Verify every action in `01 Goal`, `04 Pillars`, `05 Trade-Offs`, `06 Core Loop`, and `08 Done When` has a dedicated Feature while honoring `07 Out of Scope`.
  2. Strict Build Dependency Order: Verify `beat_1` starts with Greybox Level/Arena Blockout before Character Movement, and every target entity is built before its tool/tether/gate.
  3. Concrete Tuning & Guards: Verify every Feature has 2–3 `"paramName: value unit"` entries in `tuningParams` and `[TAG]` edge-case guards.
  4. Progressive Delta Integrity: For v0.2+, verify `"upgrade"` checkpoints extend existing v0.1 features in-place without duplicating v0.1 tasks.

Call `commit_release_plan` with the structured release blueprint.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: effectiveModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: const [commitReleasePlanTool],
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

  /// Phase 1 of Section-by-Section Workbench Build:
  /// Determines the major **Gameplay Systems, Mechanics, and Bodies of Engineering Work (`E01`..`EN`)**
  /// needed to make the Concept Blueprint's `06 Core Loop` work (never copying loop beats word-for-word).
  static Future<ReleaseBlueprint?> planReleaseSystemEpics({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;
    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText = (projectDoc.sections['game_spec'] ??
            projectDoc.sections['gameSpec'] ??
            '')
        .trim();
    final techSpecText = (projectDoc.sections['tech_spec'] ??
            projectDoc.sections['techSpec'] ??
            '')
        .trim();
    final pillarsText = (projectDoc.sections['design_pillars'] ??
            projectDoc.sections['designPillars'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final tradeOffsText = (projectDoc.sections['trade_offs'] ??
            projectDoc.sections['tradeOffs'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final projectGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final projectDoneWhen =
        SectionTextUtils.resolveDoneWhen(projectDoc.sections);
    final loopBeatTitlesLower = <String>{
      for (final item in coreLoopItems)
        item.split(':').first.trim().toLowerCase(),
    };
    final numberedCoreLoopSummary = coreLoopItems.isNotEmpty
        ? [
            for (int i = 0; i < coreLoopItems.length; i++)
              '  Loop Step ${(i + 1).toString().padLeft(2, '0')}: ${coreLoopItems[i]}',
          ].join('\n')
        : '  (Decompose the project goal into engineering systems)';

    final effectiveModel = modelName.contains('argon')
        ? 'gemini-flash-latest'
        : modelName;
    final prompt = '''
You are the Principal Game Architect (`$effectiveModel`) planning the top-level **Engineering Systems / Mechanics / Epics (`E01`..`EN`)** for "${projectDoc.title}" ($versionTag).
Concept Blueprint (01–08):
- 01 Goal: "$projectGoal"
- 02 Game Spec: $gameSpecText
- 03 Tech Spec: $techSpecText
- 04 Design Pillars: $pillarsText
- 05 Trade-Offs: $tradeOffsText
- 06 Player Core Loop (What the player experiences):
$numberedCoreLoopSummary
- 07 Out of Scope: ${projectExclusions.join(' | ')}
- 08 Done When: "$projectDoneWhen"

${GeminiAgentClient.compactStyleRules}
- EPICS ARE SYSTEMS / MECHANICS / BIG BODIES OF WORK (NEVER COPY LOOP BEATS WORD-FOR-WORD):
  * `06 Core Loop` describes chronological player actions, whereas Workbench Epics (`E01`..`EN`) MUST be the **underlying gameplay systems, mechanics, and bodies of engineering work** needed to make that loop work in the engine!
  * NEVER copy the `06 Core Loop` step headers (${loopBeatTitlesLower.map((t) => '"$t"').join(', ')}) word-for-word as Epic titles.
  * Instead, name the concrete engineering/gameplay systems (`2–4` plain game-dev words each, e.g., `"Arena Grid & Traversal"`, `"Hydroponic Pipe Network"`, `"Crop Growth & Harvest"`, `"Cargo Market & Upgrades"`) ordered by engineering build dependency:
    1. `E01` MUST be the Greybox Space/Level/Grid & Primary Player/Tool Control system so the player can move and interact in the world first.
    2. Middle Epics (`E02`..`E_{N-1}`) cover the core simulation, target/hazard entities, resource processing, or combat mechanics needed to drive the loop.
    3. Final Epic (`EN`) covers the loop payoff, economy/upgrade terminal, and next-cycle reset so the loop connects end-to-end.
- ZERO ARTIFICIAL COUNT LIMITS: Create the exact number of System Epics (`epics`) that "${projectDoc.title}" genuinely needs to accomplish the full `06 Core Loop` and `08 Done When`.

Call `commit_release_system_epics` with the structured system epics.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: effectiveModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: const [commitReleaseSystemEpicsTool],
    );
    final rawEpics = json?['epics'] ?? json?['beats'];
    if (rawEpics is! List || rawEpics.isEmpty) return null;

    final beats = <ProposedBeatBlueprint>[];
    for (int i = 0; i < rawEpics.length; i++) {
      final item = rawEpics[i];
      if (item is! Map) continue;
      var rawTitle = (item['title'] ?? '').toString().trim();
      if (rawTitle.isEmpty) continue;
      if (loopBeatTitlesLower.contains(rawTitle.toLowerCase())) {
        rawTitle = i == 0
            ? '$rawTitle & Control'
            : '$rawTitle Mechanics';
      }
      final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
        rawTitle,
        beatIndex: i,
      );
      final bGoal = (item['goal'] ?? '').toString().trim();
      final bDone = (item['doneWhen'] ?? '').toString().trim();
      beats.add(
        ProposedBeatBlueprint(
          id: 'beat_${i + 1}',
          title: bTitle,
          goal: bGoal.isNotEmpty
              ? bGoal
              : 'Build the $bTitle gameplay system in the greybox arena.',
          doneWhen: bDone.isNotEmpty
              ? bDone
              : 'Playtester verifies $bTitle in Play mode.',
          features: <ProposedFeatureBlueprint>[],
        ),
      );
    }
    if (beats.isEmpty) return null;

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle:
          (json?['releaseTitle'] ?? releaseDoc.title).toString().trim(),
      releaseVersionTag: versionTag,
      preset: preset,
      goal: (json?['goal'] ?? projectGoal).toString().trim(),
      doneWhen: (json?['doneWhen'] ?? projectDoneWhen).toString().trim(),
      questions: const <AgentQuestion>[],
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Architected ${beats.length} System Epics for ${projectDoc.title}.',
    );
  }

  /// Phase 2 of Section-by-Section Workbench Build:
  /// Determines the `1..M` playable Features (plus tasks, tuning parameters, and edge-case guards)
  /// needed for a SINGLE System Epic (`epicBlueprint`) in engineering build-dependency order.
  static Future<List<ProposedFeatureBlueprint>> planFeaturesForSingleEpic({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required ProposedBeatBlueprint epicBlueprint,
    required int epicIndex,
    required List<ProposedBeatBlueprint> allEpics,
    required List<String> alreadyPlannedFeatures,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText = (projectDoc.sections['game_spec'] ??
            projectDoc.sections['gameSpec'] ??
            '')
        .trim();
    final techSpecText = (projectDoc.sections['tech_spec'] ??
            projectDoc.sections['techSpec'] ??
            '')
        .trim();
    final pillarsText = (projectDoc.sections['design_pillars'] ??
            projectDoc.sections['designPillars'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final tradeOffsText = (projectDoc.sections['trade_offs'] ??
            projectDoc.sections['tradeOffs'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final projectGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final epicNum = (epicIndex + 1).toString().padLeft(2, '0');
    final allEpicsOverview = [
      for (int i = 0; i < allEpics.length; i++)
        'E${(i + 1).toString().padLeft(2, '0')} · ${allEpics[i].title}',
    ].join('\n');

    final effectiveModel = modelName.contains('argon')
        ? 'gemini-flash-latest'
        : modelName;
    final prompt = '''
You are the Systems Designer (`$effectiveModel`) planning the playable **Features (`1..M`)** inside **Epic E$epicNum · ${epicBlueprint.title}** for "${projectDoc.title}" ($versionTag).
Project Goal: "$projectGoal"
Game Spec: $gameSpecText
Tech Spec: $techSpecText
Design Pillars: $pillarsText
Trade-Offs: $tradeOffsText
Core Loop Context: ${coreLoopItems.join(' -> ')}
Out of Scope (DO NOT BUILD): ${projectExclusions.join(' | ')}

All Release System Epics (Stay strictly inside E$epicNum's responsibility):
$allEpicsOverview
${alreadyPlannedFeatures.isNotEmpty ? 'Already Planned in Earlier Epics (DO NOT DUPLICATE): ${alreadyPlannedFeatures.join(', ')}' : ''}

TARGET EPIC TO BREAK DOWN INTO PLAYABLE FEATURES:
- Epic E$epicNum: "${epicBlueprint.title}"
- System Goal: "${epicBlueprint.goal}"
- System Done When: "${epicBlueprint.doneWhen}"

${GeminiAgentClient.compactStyleRules}
- DETERMINE THE PLAYABLE FEATURES NEEDED FOR E$epicNum:
  * Break E$epicNum ("${epicBlueprint.title}") into the exact number of cohesive, singular-focused Playable Features (`1..M`) needed to build this system end-to-end.
  * NEVER name a Feature identical to the Epic title ("${epicBlueprint.title}"). Each Feature must name a specific playable mechanic, tool, or interactive object inside E$epicNum (`2–3` plain game-dev words, e.g., `"Greybox Dome Floor"`, `"Player Walk & Aim"`, `"Laser Debris Cutter"`).
  * Order Features by strict **Engineering Build Dependency**:
    ${epicIndex == 0 ? '1. Feature #1 in E01 MUST be the Greybox Level/Arena/Grid Blockout & Collision surface BEFORE Player/Tool movement at Feature #2.' : '1. Place any target entity, container, or spawner BEFORE the tool, tether, projectile, or UI that acts on it.'}
    2. Place the base playable action BEFORE any cooldown, pressure lock, or boundary gate that restricts it.
- MANDATORY TUNING & GUARDS ON EVERY FEATURE:
  * Include 2–3 concrete `"paramName: numericValue unit"` entries in `tuningParams` and 1–2 `[TAG]` guard rules in `edgeCases`.
  * Include foundation-first `tasks` (`entity_and_collision_foundation` -> `core_action_and_math` -> `feedback_and_boundary_guard`).

Call `commit_epic_features` with the ordered playable features.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: effectiveModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: const [commitEpicFeaturesTool],
    );
    final rawFeatures = json?['features'];
    if (rawFeatures is List && rawFeatures.isNotEmpty) {
      final parsedFeatures = <ProposedFeatureBlueprint>[];
      final usedTitlesLower = <String>{
        epicBlueprint.title.trim().toLowerCase(),
        for (final prev in alreadyPlannedFeatures) prev.trim().toLowerCase(),
      };
      for (int fIdx = 0; fIdx < rawFeatures.length; fIdx++) {
        final fMap = rawFeatures[fIdx];
        if (fMap is! Map) continue;
        final rawTitle = (fMap['title'] ?? '').toString().trim();
        if (rawTitle.isEmpty) continue;
        final fGoal = (fMap['goal'] ?? '').toString().trim();
        var cleanTitle = disambiguateFeatureTitleFromBeat(
          rawTitle,
          beatTitle: epicBlueprint.title,
          featureGoal: fGoal,
          beatIndex: epicIndex,
        );
        if (usedTitlesLower.contains(cleanTitle.toLowerCase())) {
          cleanTitle = '$cleanTitle ${fIdx + 1}';
        }
        usedTitlesLower.add(cleanTitle.toLowerCase());

        final fDone = (fMap['doneWhen'] ?? '').toString().trim();
        final estHours =
            (int.tryParse(fMap['estimatedHours']?.toString() ?? '') ?? 4)
                .clamp(2, 16);
        final primaryAsset =
            (fMap['primarySharedScriptOrScene'] ?? '').toString().trim();
        final inScope = (fMap['inScope'] is List)
            ? (fMap['inScope'] as List)
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[fGoal.isNotEmpty ? fGoal : cleanTitle];
        var tuning = (fMap['tuningParams'] is List)
            ? (fMap['tuningParams'] as List)
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[];
        if (tuning.isEmpty) {
          tuning = _defaultTuningParamsForFeature(cleanTitle, fGoal);
        }
        var guards = (fMap['edgeCases'] is List)
            ? (fMap['edgeCases'] as List)
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[];
        if (guards.isEmpty) {
          guards = <String>[
            '[STATE GUARD] Prevent invalid state transition on $cleanTitle',
          ];
        }
        final cpTitle =
            (fMap['checkpointTitle'] ?? '$cleanTitle Core').toString().trim();
        final cpCriteria = (fMap['playtestCriteria'] ??
                (fDone.isNotEmpty
                    ? fDone
                    : 'Trigger $cleanTitle in Play mode -> verify immediate response on screen'))
            .toString()
            .trim();
        final rawTaskList = extractCheckpointTasksFromMap(fMap);
        final tasks = normalizeFoundationFirstTasks(
          rawTaskList.isNotEmpty
              ? rawTaskList
              : <String>[
                  '$cleanTitle Body & Collision (2h)',
                  '$cleanTitle Action & Math (1h)',
                  '$cleanTitle Cue & Clamp (1h)',
                ],
          featureTitle: cleanTitle,
          beatTitle: epicBlueprint.title,
          isFirstFeatureOfRelease: epicIndex == 0 && fIdx == 0,
        );

        parsedFeatures.add(
          ProposedFeatureBlueprint(
            id: 'feat_${epicIndex + 1}_${fIdx + 1}',
            title: cleanTitle,
            goal: fGoal.isNotEmpty
                ? fGoal
                : 'Build $cleanTitle inside ${epicBlueprint.title}.',
            doneWhen: fDone.isNotEmpty
                ? fDone
                : 'Playtester verifies $cleanTitle in Play mode.',
            estimatedHours: estHours,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: versionTag,
            primarySharedScriptOrScene:
                primaryAsset.isNotEmpty ? primaryAsset : null,
            inScope: inScope,
            outOfScope: const <String>[],
            tuningParams: tuning,
            edgeCases: guards,
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: versionTag,
                tasks: tasks,
                coveredScope: inScope,
                tuningParams: tuning,
                edgeCases: guards,
              ),
            ],
          ),
        );
      }
      if (parsedFeatures.isNotEmpty) {
        return enforceIntraEpicBuildDependencies(
          parsedFeatures,
          epicIndex: epicIndex,
        );
      }
    }

    return decomposeBeatIntoDynamicFeatures(
      beatNumber: epicIndex + 1,
      beatIndex: epicIndex,
      beatTitle: epicBlueprint.title,
      rawBeatLine: '${epicBlueprint.title}: ${epicBlueprint.goal}',
      rawDescPart: epicBlueprint.goal,
      versionTag: versionTag,
    );
  }

  /// Step 0 (`0ms`) of Section-by-Section Progressive Release:
  /// Builds an instant in-memory `ReleaseBlueprint` shell containing the existing `E01..EN` Epics,
  /// `STABLE` built features, and `projectExclusions` so the 3-Step Progressive Release modal opens
  /// immediately at `0ms` while Section 1 (Focus & 3 Options) and Section 2 (Epic Changes) stream in.
  static ReleaseBlueprint? buildProgressiveLiveTreeSkeletonBlueprint({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
  }) {
    if (existingBeats.isEmpty) return null;
    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final eb = existingBeats[bIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final proposedFeats = <ProposedFeatureBlueprint>[];
      for (final ef in existingFeats) {
        final isSuperseded =
            ef.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;
        final existingAsset = (ef.sections['primary_asset'] ?? '').trim();
        proposedFeats.add(
          ProposedFeatureBlueprint(
            id: ef.id,
            title: ef.title,
            goal: SectionTextUtils.resolveGoal(ef.sections),
            doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
            estimatedHours: 0,
            included: !isSuperseded,
            lifecycle: isSuperseded
                ? FeatureLifecycleStatus.superseded
                : FeatureLifecycleStatus.stable,
            originVersion: ef.sections['originVersion'] ?? 'v0.1',
            primarySharedScriptOrScene:
                existingAsset.isNotEmpty ? existingAsset : null,
            inScope: SectionTextUtils.resolveInScope(ef.sections),
            outOfScope: const [],
            tuningParams: const [],
            edgeCases: const [],
            checkpoints: const [],
          ),
        );
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

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: '',
      doneWhen: '',
      questions: const <AgentQuestion>[],
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Synthesizing Section 1: Analyzing completed features and Design Pillars to recommend $versionTag focus & options...',
    );
  }

  /// Pass 1 (`~1.5s`) of Section-by-Section Progressive Release:
  /// Synthesizes ONLY Section 1 (`releaseTitle`, `goal`, `doneWhen`, `missingGaps`, 3 Strategic Options,
  /// and `targetEpicIndices`) using fast `gemini-flash-latest` (`thinkingLevel: "LOW"`).
  /// If the responder returns a full `beats` payload (e.g. in unit tests), returns `fullBlueprint` directly.
  static Future<({
    ReleaseBlueprint? fullBlueprint,
    String releasePhase,
    String releaseTitle,
    String goal,
    String doneWhen,
    List<String> builtSoFar,
    List<String> missingGaps,
    String agentReasoning,
    List<AgentQuestion> questions,
    List<int> targetEpicIndices,
  })?> planProgressiveReleaseFocusSection({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    List<TierDocument> completedReleases = const [],
    List<TierDocument> existingBeats = const [],
    Map<String, List<TierDocument>> existingFeaturesByBeat = const {},
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey) || existingBeats.isEmpty) {
      return null;
    }

    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = (releaseDoc.sections['phase'] ?? 'mvp').trim();
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = _mvpEpicNumRegex.firstMatch(releaseDoc.title);
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final int? explicitTargetEpicIdx = isAgentReasoned
        ? null
        : (rawTargetEpicIdx != null
            ? int.tryParse(rawTargetEpicIdx)
            : (mvpEpicMatch != null
                ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
                : null));

    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText =
        projectDoc.sections['game_spec'] ?? projectDoc.sections['gameSpec'] ?? '';
    final techSpecText =
        projectDoc.sections['tech_spec'] ?? projectDoc.sections['techSpec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ??
        projectDoc.sections['designPillars'] ??
        '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ??
        projectDoc.sections['tradeOffs'] ??
        '';
    final projectGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final projectDoneWhen =
        SectionTextUtils.resolveDoneWhen(projectDoc.sections);

    final historyAndTree = StringBuffer();
    final mvpVerTags = <String>{};
    final vsVerTags = <String>{};
    if (completedReleases.isNotEmpty) {
      historyAndTree.writeln(
        'Completed Prior Releases History (chronological):',
      );
      for (final priorRel in completedReleases) {
        final pVer = extractReleaseVersionTag(
          priorRel.sections['versionTag']?.isNotEmpty == true
              ? priorRel.sections['versionTag']!
              : priorRel.title,
        );
        final pPhase =
            priorRel.sections['phase'] ?? priorRel.releaseScope.name;
        final pPhaseLower = pPhase.toLowerCase();
        if (pPhaseLower.contains('vertical') || pPhaseLower.contains('slice')) {
          vsVerTags.add(pVer.toLowerCase());
        } else if (pPhaseLower.contains('mvp')) {
          mvpVerTags.add(pVer.toLowerCase());
        }
        final pGoal = SectionTextUtils.resolveGoal(priorRel.sections);
        historyAndTree.writeln(
          '- $pVer [$pPhase] "${priorRel.title}": ${pGoal.isNotEmpty ? pGoal : "Completed milestone"}',
        );
      }
    }
    historyAndTree.writeln(
      'Existing Live Game Tree (Epics E01..E${existingBeats.length.toString().padLeft(2, '0')}):',
    );
    final isVsTarget = releasePhase == ProductionPhase.verticalSlice.name ||
        preset == ReleaseScope.verticalSlice;
    final isFpTarget = releasePhase == ProductionPhase.fullProduction.name;
    final unupgradedEpicNums = <int>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final b = existingBeats[bIdx];
      final eNum = bIdx + 1;
      final eCode = 'E${eNum.toString().padLeft(2, '0')}';
      final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
      // Act 2: core Concept Epics are locked STABLE in Full Production; only FP Epics are targetable.
      bool allFeaturesInEpicCoveredForPhase =
          feats.isNotEmpty || (isFpTarget && !b.isFullProductionEpic);
      final featSummaries = <String>[];
      for (final f in feats) {
        if (f.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name) {
          featSummaries.add('${f.title} [SUPERSEDED]');
          continue;
        }
        final states = FeatureStateNode.getStatesForDocument(f);
        final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
        final bool coveredInPhase;
        if (isFpTarget) {
          coveredInPhase = !b.isFullProductionEpic ||
              states.any((s) => s.releaseVersion.toLowerCase() != originVer);
        } else if (isVsTarget) {
          coveredInPhase = vsVerTags.contains(originVer) ||
              states.any(
                (s) => vsVerTags.contains(s.releaseVersion.toLowerCase()),
              );
        } else {
          coveredInPhase = originVer != 'v0.1' ||
              mvpVerTags.contains(originVer) ||
              states.any((s) => s.releaseVersion.toLowerCase() != 'v0.1');
        }
        if (!coveredInPhase) {
          allFeaturesInEpicCoveredForPhase = false;
        }
        final cpChain = states.isNotEmpty
            ? states.map((s) => s.releaseVersion).join('->')
            : originVer;
        featSummaries.add('${f.title} ($cpChain)');
      }
      if (!allFeaturesInEpicCoveredForPhase) {
        unupgradedEpicNums.add(eNum);
      }
      final epicPhaseTag = allFeaturesInEpicCoveredForPhase
          ? '[COMPLETE IN ${releasePhase.toUpperCase()} ✓]'
          : '[INCOMPLETE IN ${releasePhase.toUpperCase()} — Needs full Epic pass]';
      historyAndTree.writeln(
        '- Epic $eNum ($eCode · "${b.title}", id: ${b.id})${b.isFullProductionEpic ? ' [FULL PRODUCTION EPIC]' : ''} $epicPhaseTag: ${featSummaries.join(', ')}',
      );
    }

    final phaseFocusDirective = isVsTarget
        ? 'Phase 3 · Vertical Slice (Gold Standard Polish Pass): Select 1–2 incomplete Epics in "targetEpicNumbers" (${unupgradedEpicNums.isNotEmpty ? unupgradedEpicNums.map((n) => "E${n.toString().padLeft(2, '0')}").join(', ') : 'E01, E02'}) to polish completely with observable VFX/particles, SFX audio cues, hit-stop/camera feedback, animation states, and HUD readability.'
        : (releasePhase == ProductionPhase.fullProduction.name
            ? 'Phase 4 · Full Production Pass: Select 1–2 incomplete Full Production Epics in "targetEpicNumbers" (${unupgradedEpicNums.isNotEmpty ? unupgradedEpicNums.map((n) => "E${n.toString().padLeft(2, '0')}").join(', ') : 'any Full Production Epic'}) to bring up to the Vertical Slice quality bar (content depth + feel polish in one pass). NEVER target core Concept Epics—they stay STABLE.'
            : (releasePhase == ProductionPhase.postLaunch.name
                ? 'Phase 5 · Post-Launch & Live Ops: Select 1–2 Epics in "targetEpicNumbers" for live balance tuning, [FIX] resolution, and modular content drops.'
                : 'Phase 2 · MVP (Whole-Epic Functional Upgrade): Select 1–2 incomplete Epics in "targetEpicNumbers" (${unupgradedEpicNums.isNotEmpty ? unupgradedEpicNums.map((n) => "E${n.toString().padLeft(2, '0')}").join(', ') : 'E01, E02'}) to upgrade completely from v0.1 greybox to functional MVP.'));

    final prompt = '''
You are the Lead Game Architect planning **Section 1 (Focus & Strategic Options)** for Progressive Release "$versionTag" (${releaseDoc.title}, Phase: $releasePhase) of "${projectDoc.title}".
Concept Blueprint:
- 01 Goal: "$projectGoal"
- 02 Game Spec: $gameSpecText
- 03 Tech Spec: $techSpecText
- 04 Design Pillars: $pillarsText
- 05 Trade-Offs: $tradeOffsText
- 06 Core Loop: ${coreLoopItems.join(' -> ')}
- 07 Out of Scope: ${projectExclusions.join(' | ')}
- 08 Done When: "$projectDoneWhen"
$historyAndTree
- PHASE DIRECTIVE: $phaseFocusDirective
${GeminiAgentClient.compactStyleRules}
- Return ONLY Section 1 of the $versionTag Progressive Release Plan:
  1. `"releasePhase"`: `"$releasePhase"`
  2. `"releaseTitle"`: `"$versionTag: <2-5 Word Concrete Focus>"`
  3. `"goal"`: BLUF format (`"<2-4 Word Payoff> — Complete E0# <System> and E0# <System> for $releasePhase."`).
  4. `"doneWhen"`: Causal `Trigger → Result` format (`"<Player Action> → <Observable Screen Result>"`).
  5. `"builtSoFar"`: 2–4 short phrases summarizing what is already built.
  6. `"missingGaps"`: 2–4 concise 1-line statements prefixed with `E0#:` naming what is lacking right now.
  7. `"targetEpicNumbers"`: Array of 1-based Epic numbers (`1..${existingBeats.length}`) that $versionTag will upgrade or add features to (e.g. `[2, 3]`).
  8. `"questions"`: 1 question with 3 Epic-driven options naming the available incomplete Epic codes (`E0#`) and telegraphic `+`-joined deliverables (Option 1 prefixed with `(Recommended)`).

Call `commit_progressive_release_focus` with Section 1 of the progressive release plan.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: 'gemini-flash-latest',
      thinkingLevel: 'LOW',
      temperature: 0.35,
      functionDeclarations: const [commitProgressiveReleaseFocusTool],
    );
    if (json == null) return null;

    // Backward-compatible fast path: if a mock or model returned a full `beats` array, parse & reconcile immediately
    final rawBeats = json['beats'];
    if (rawBeats is List && rawBeats.isNotEmpty) {
      final parsed = _parseDynamicReleaseBlueprint(
        json: json,
        releaseDoc: releaseDoc,
        preset: preset,
        versionTag: versionTag,
        fallbackExclusions: projectExclusions,
      );
      if (parsed != null) {
        final reconciled = reconcileReleaseBlueprintWithPhaseRules(
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
        return (
          fullBlueprint: reconciled,
          releasePhase: releasePhase,
          releaseTitle: reconciled.releaseTitle,
          goal: reconciled.goal,
          doneWhen: reconciled.doneWhen,
          builtSoFar: reconciled.builtSoFar,
          missingGaps: reconciled.missingGaps,
          agentReasoning: reconciled.lastAgentReply ?? '',
          questions: reconciled.questions,
          targetEpicIndices: const <int>[],
        );
      }
    }

    final questions = <AgentQuestion>[];
    final rawQs = json['questions'];
    if (rawQs is List) {
      for (int i = 0; i < rawQs.length; i++) {
        final item = rawQs[i];
        if (item is Map) {
          final qText = (item['question'] ?? '').toString().trim();
          final opts = _parseStringList(item['options']);
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

    final rawTargetNums = json['targetEpicNumbers'];
    final targetIndices = <int>[];
    if (explicitTargetEpicIdx != null &&
        explicitTargetEpicIdx >= 0 &&
        explicitTargetEpicIdx < existingBeats.length) {
      targetIndices.add(explicitTargetEpicIdx);
    } else if (rawTargetNums is List) {
      for (final item in rawTargetNums) {
        final n = int.tryParse(item.toString().trim());
        if (n != null && n >= 1 && n <= existingBeats.length) {
          final idx = n - 1;
          if (!targetIndices.contains(idx)) {
            targetIndices.add(idx);
          }
        }
      }
    }
    final missingGaps = _parseStringList(json['missingGaps']);
    if (targetIndices.isEmpty && missingGaps.isNotEmpty) {
      final eRegex = RegExp(r'\bE0?(\d+)\b', caseSensitive: false);
      for (final gap in missingGaps) {
        final m = eRegex.firstMatch(gap);
        if (m != null) {
          final n = int.tryParse(m.group(1)!);
          if (n != null && n >= 1 && n <= existingBeats.length) {
            final idx = n - 1;
            if (!targetIndices.contains(idx)) {
              targetIndices.add(idx);
            }
          }
        }
      }
    }
    if (isFpTarget && existingBeats.any((b) => b.isFullProductionEpic)) {
      targetIndices.removeWhere((i) => !existingBeats[i].isFullProductionEpic);
    }
    if (targetIndices.isEmpty) {
      if (unupgradedEpicNums.isNotEmpty) {
        for (final n in unupgradedEpicNums.take(2)) {
          targetIndices.add(n - 1);
        }
      } else if (isFpTarget) {
        final firstFp = existingBeats.indexWhere((b) => b.isFullProductionEpic);
        targetIndices.add(firstFp >= 0 ? firstFp : 0);
      } else {
        targetIndices.add(0);
      }
    }

    final rawTitle = (json['releaseTitle'] ?? '').toString().trim();
    final effectiveTitle = rawTitle.isNotEmpty
        ? (rawTitle.startsWith('$versionTag:')
            ? rawTitle
            : '$versionTag: ${rawTitle.replaceFirst(_versionPrefixStripRegex, '')}')
        : releaseDoc.title;

    return (
      fullBlueprint: null,
      releasePhase: (json['releasePhase'] ?? releasePhase).toString().trim(),
      releaseTitle: effectiveTitle,
      goal: (json['goal'] ?? '').toString().trim(),
      doneWhen: (json['doneWhen'] ?? '').toString().trim(),
      builtSoFar: _parseStringList(json['builtSoFar']),
      missingGaps: missingGaps,
      agentReasoning: (json['agentReasoning'] ?? '').toString().trim(),
      questions: questions,
      targetEpicIndices: targetIndices,
    );
  }

  /// Pass 2 (Epic-by-Epic) of Section-by-Section Progressive Release:
  /// Synthesizes the `upgrade` and `new` Features for a SINGLE target Epic (`existingBeats[epicIndex]`)
  /// and reconciles them with that Epic's existing `STABLE` features.
  static Future<ProposedBeatBlueprint?> planProgressiveEpicChanges({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required TierDocument epicDoc,
    required int epicIndex,
    required int totalEpicsCount,
    required List<TierDocument> existingFeaturesInEpic,
    required List<ProposedFeatureBlueprint> queuedDeferredInEpic,
    required String section1Goal,
    required String section1DoneWhen,
    required List<String> missingGaps,
    required List<String> alreadyPlannedChanges,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;
    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = (releaseDoc.sections['phase'] ?? 'mvp').trim();
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText =
        projectDoc.sections['game_spec'] ?? projectDoc.sections['gameSpec'] ?? '';
    final techSpecText =
        projectDoc.sections['tech_spec'] ?? projectDoc.sections['techSpec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ??
        projectDoc.sections['designPillars'] ??
        '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ??
        projectDoc.sections['tradeOffs'] ??
        '';
    final epicCode = 'E${(epicIndex + 1).toString().padLeft(2, '0')}';

    final existingFeatLines = <String>[];
    for (final f in existingFeaturesInEpic) {
      if (f.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name) {
        existingFeatLines.add(
          '- SUPERSEDED: "${f.title}" [id: ${f.id}]',
        );
        continue;
      }
      final states = FeatureStateNode.getStatesForDocument(f);
      final latestCp = states.isNotEmpty
          ? '${states.last.releaseVersion} "${states.last.cleanStageTitle}"'
          : (f.sections['originVersion'] ?? 'v0.1');
      final tuning = <String>{
        for (final s in states) ...s.tuningParams,
      };
      final asset = (f.sections['primary_asset'] ?? '').trim();
      existingFeatLines.add(
        '- Existing Feature: "${f.title}" [id: "${f.id}", latest: $latestCp${asset.isNotEmpty ? ', asset: $asset' : ''}${tuning.isNotEmpty ? ', vars: ${tuning.take(3).join(", ")}' : ''}]',
      );
    }

    final phaseUpgradeDirective = releasePhase ==
            ProductionPhase.verticalSlice.name
        ? 'Phase 3 · Vertical Slice Polish: Upgrade EVERY existing feature in Epic $epicCode with observable VFX/particles, SFX audio cues, camera shake/hit-stop, animation states, and HUD readability.'
        : (releasePhase == ProductionPhase.fullProduction.name
            ? 'Phase 4 · Full Production Pass: Upgrade EVERY existing feature in Full Production Epic $epicCode to the Vertical Slice quality bar (full content depth + VFX/SFX/HUD feel polish in one pass), reusing the core scripts already built.'
            : (releasePhase == ProductionPhase.postLaunch.name
                ? 'Phase 5 · Post-Launch & Live Ops: Upgrade EVERY existing feature in Epic $epicCode with live balance tuning, [FIX] resolutions, and modular content depth.'
                : 'Phase 2 · MVP Functional Depth: Upgrade EVERY existing v0.1 greybox feature in Epic $epicCode into a complete functional MVP mechanic.'));

    final prompt = '''
You are the Systems Designer planning the **$versionTag (`$releasePhase`) COMPLETE EPIC UPGRADE** inside **Epic $epicCode · ${epicDoc.title}** for "${projectDoc.title}".
Section 1 Release Focus:
- Release Goal: "$section1Goal"
- Release Done When: "$section1DoneWhen"
${missingGaps.isNotEmpty ? '- Identified Gaps: ${missingGaps.join(" | ")}\n' : ''}- Game & Tech Spec: $gameSpecText | $techSpecText
- Design Pillars & Trade-Offs: $pillarsText | $tradeOffsText
- Out of Scope (DO NOT BUILD): ${projectExclusions.join(' | ')}
${alreadyPlannedChanges.isNotEmpty ? '- Already Planned in Earlier Epics for $versionTag (DO NOT DUPLICATE): ${alreadyPlannedChanges.join(", ")}\n' : ''}
Target Epic $epicCode ("${epicDoc.title}", id: "${epicDoc.id}"):
${existingFeatLines.isNotEmpty ? existingFeatLines.join('\n') : '(No existing features)'}

- PHASE DIRECTIVE: $phaseUpgradeDirective
${GeminiAgentClient.compactStyleRules}
- WHOLE-EPIC COMPLETION RULE (NO PARTIAL EPICS):
  * Because **Epic $epicCode · ${epicDoc.title}** was chosen for $versionTag, you MUST return an `"upgrade"` entry for **EVERY** existing non-superseded feature listed above in Epic $epicCode (using its EXACT `"id"` and `"title"`), describing its $versionTag delta upgrade in `"goal"`, `"inScope"`, and `"tasks"`, so the **entire Epic $epicCode** is completed in $versionTag.
  * You may also add a brand-new feature in Epic $epicCode (`"lifecycle": "new"`) if a missing mechanic is required to complete the Epic.
  * Include 2–3 `"paramName: numericValue unit"` entries in `"tuningParams"`, 1–2 `[STATE GUARD]` rules in `"edgeCases"`, and foundation-first `"tasks"` (`entity_and_collision_foundation` -> `core_action_and_math` -> `feedback_and_boundary_guard`).

Call `commit_progressive_epic_changes` with the active UPGRADE and NEW features for Epic $epicCode.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: 'gemini-flash-latest',
      thinkingLevel: 'LOW',
      temperature: 0.35,
      functionDeclarations: const [commitProgressiveEpicChangesTool],
    );
    final rawFeatures = json?['features'];
    if (rawFeatures is! List || rawFeatures.isEmpty) {
      return ensureCompleteEpicUpgradedForBeat(
        beatBp: null,
        epicDoc: epicDoc,
        existingFeaturesInEpic: existingFeaturesInEpic,
        queuedDeferredInEpic: queuedDeferredInEpic,
        versionTag: versionTag,
        releasePhase: releasePhase,
      );
    }

    final singleBeatJson = <String, dynamic>{
      'releasePhase': releasePhase,
      'releaseTitle': releaseDoc.title,
      'goal': section1Goal,
      'doneWhen': section1DoneWhen,
      'beats': [
        {
          'id': epicDoc.id,
          'title': epicDoc.title,
          'goal': SectionTextUtils.resolveGoal(epicDoc.sections),
          'doneWhen': SectionTextUtils.resolveDoneWhen(epicDoc.sections),
          'features': [
            for (final item in rawFeatures)
              if (item is Map)
                {
                  ...item,
                  if (item['checkpoints'] == null)
                    'checkpoints': [
                      {
                        'title': item['checkpointTitle'] ??
                            '${item['title'] ?? 'Feature'} ($versionTag)',
                        'playtestCriteria': item['playtestCriteria'] ??
                            item['doneWhen'] ??
                            'Verify in Play mode',
                        'tasks': item['tasks'] ?? const [],
                      },
                    ],
                },
          ],
        },
      ],
    };

    final parsedSingle = _parseDynamicReleaseBlueprint(
      json: singleBeatJson,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      fallbackExclusions: projectExclusions,
      capV01Checkpoints: false,
    );
    if (parsedSingle == null || parsedSingle.beats.isEmpty) {
      return ensureCompleteEpicUpgradedForBeat(
        beatBp: null,
        epicDoc: epicDoc,
        existingFeaturesInEpic: existingFeaturesInEpic,
        queuedDeferredInEpic: queuedDeferredInEpic,
        versionTag: versionTag,
        releasePhase: releasePhase,
      );
    }

    final reconciledSingle = reconcileReleaseBlueprintWithPhaseRules(
      parsed: parsedSingle,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      existingBeats: <TierDocument>[epicDoc],
      existingFeaturesByBeat: <String, List<TierDocument>>{
        epicDoc.id: existingFeaturesInEpic,
      },
      deferredByBeatIndex: <int, List<ProposedFeatureBlueprint>>{
        if (queuedDeferredInEpic.isNotEmpty) 0: queuedDeferredInEpic,
      },
      projectExclusions: projectExclusions,
      allCoreLoopItems: const <String>[],
    );
    return ensureCompleteEpicUpgradedForBeat(
      beatBp: reconciledSingle.beats.firstOrNull,
      epicDoc: epicDoc,
      existingFeaturesInEpic: existingFeaturesInEpic,
      queuedDeferredInEpic: queuedDeferredInEpic,
      versionTag: versionTag,
      releasePhase: releasePhase,
    );
  }

  /// Guarantees that when a target Epic (`epicDoc`) is selected for a progressive release (`versionTag`),
  /// EVERY existing non-superseded feature in that Epic is upgraded together (`lifecycle: upgrade`)
  /// so an Epic is never left only partially upgraded in a progressive release.
  static ProposedBeatBlueprint ensureCompleteEpicUpgradedForBeat({
    required ProposedBeatBlueprint? beatBp,
    required TierDocument epicDoc,
    required List<TierDocument> existingFeaturesInEpic,
    required List<ProposedFeatureBlueprint> queuedDeferredInEpic,
    required String versionTag,
    required String releasePhase,
  }) {
    final isVs = releasePhase == ProductionPhase.verticalSlice.name;
    final isFullProd = releasePhase == ProductionPhase.fullProduction.name;
    final isPostLaunch = releasePhase == ProductionPhase.postLaunch.name;
    final stageSuffix = isVs
        ? 'Slice Polish'
        : (isFullProd
            ? 'Production Pass'
            : (isPostLaunch ? 'Live Ops' : 'MVP Upgrade'));

    final baseFeatures = beatBp != null
        ? List<ProposedFeatureBlueprint>.from(beatBp.features)
        : <ProposedFeatureBlueprint>[
            for (final ef in existingFeaturesInEpic)
              ProposedFeatureBlueprint(
                id: ef.id,
                title: ef.title,
                goal: SectionTextUtils.resolveGoal(ef.sections),
                doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
                estimatedHours: 0,
                included: ef.sections['lifecycle'] !=
                    FeatureLifecycleStatus.superseded.name,
                lifecycle: ef.sections['lifecycle'] ==
                        FeatureLifecycleStatus.superseded.name
                    ? FeatureLifecycleStatus.superseded
                    : FeatureLifecycleStatus.stable,
                originVersion: ef.sections['originVersion'] ?? 'v0.1',
                primarySharedScriptOrScene:
                    (ef.sections['primary_asset'] ?? '').trim().isNotEmpty
                        ? ef.sections['primary_asset']!.trim()
                        : null,
                inScope: SectionTextUtils.resolveInScope(ef.sections),
                outOfScope: const [],
                tuningParams: const [],
                edgeCases: const [],
                checkpoints: const [],
              ),
            for (final df in queuedDeferredInEpic)
              df
                ..included = true
                ..lifecycle = FeatureLifecycleStatus.newFeature
                ..originVersion = versionTag,
          ];

    for (int i = 0; i < baseFeatures.length; i++) {
      final f = baseFeatures[i];
      if (!f.isStable || f.isSuperseded) continue;
      final defaultGoal = isVs
          ? '+VFX particles, +SFX audio cues, +HUD readability'
          : (isFullProd
              ? '+Full content depth, +Vertical Slice feel polish'
              : (isPostLaunch
                  ? '+Live balance tuning, +regression state guards'
                  : '+Functional MVP depth, +collision response, +HUD sync'));
      final defaultDone = isVs
          ? 'Trigger ${f.title} → VFX particles, SFX cues, and HUD feedback appear on screen'
          : 'Trigger ${f.title} in Play mode → $versionTag $stageSuffix responds on screen';
      final tuning = _defaultTuningParamsForFeature(f.title, defaultGoal);
      final guards = <String>[
        '[STATE GUARD] Block duplicate state transition during ${f.title}',
      ];
      final tasks = isVs
          ? <String>[
              'VFX & Material Nodes',
              'Camera & Audio Cues',
              'HUD & Frame Guard',
            ]
          : <String>[
              'Collision & State Flags',
              'Core Upgrade Math',
              'Feedback & State Guard',
            ];
      baseFeatures[i] = ProposedFeatureBlueprint(
        id: f.id,
        title: f.title,
        goal: defaultGoal,
        doneWhen: defaultDone,
        estimatedHours: 3,
        included: true,
        lifecycle: FeatureLifecycleStatus.upgrade,
        originVersion: f.originVersion,
        primarySharedScriptOrScene: f.primarySharedScriptOrScene,
        inScope: <String>[defaultGoal],
        outOfScope: const [],
        tuningParams: tuning,
        edgeCases: guards,
        checkpoints: <ProposedCheckpointBlueprint>[
          ProposedCheckpointBlueprint(
            title: '${f.title} ($stageSuffix)',
            playtestCriteria: defaultDone,
            releaseVersion: versionTag,
            tasks: tasks,
            coveredScope: <String>[defaultGoal],
            tuningParams: tuning,
            edgeCases: guards,
          ),
        ],
      );
    }

    return ProposedBeatBlueprint(
      id: epicDoc.id,
      title: beatBp?.title.isNotEmpty == true ? beatBp!.title : epicDoc.title,
      goal: beatBp?.goal.isNotEmpty == true
          ? beatBp!.goal
          : SectionTextUtils.resolveGoal(epicDoc.sections),
      doneWhen: beatBp?.doneWhen.isNotEmpty == true
          ? beatBp!.doneWhen
          : SectionTextUtils.resolveDoneWhen(epicDoc.sections),
      features: baseFeatures,
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
    final task0Dur = _durationRegex.firstMatch(tasks[0])?.group(0)?.trim() ?? '(2h)';
    final task1Dur = _durationRegex.firstMatch(tasks[1])?.group(0)?.trim() ?? '(2h)';
    final task1Core = tasks[1]
        .replaceFirst(_durationRegex, '')
        .replaceFirst(_setupWordRegex, 'Logic')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();

    tasks[0] =
        '${isCharacterFeature ? "Character Setup" : "Actor Setup"} $task0Dur';
    if (!task1Core.toLowerCase().contains('input')) {
      tasks[1] = 'Input & $task1Core $task1Dur';
    }
    return tasks;
  }

  static List<String> _defaultTuningParamsForFeature(
    String featureTitle,
    String featureGoal,
  ) {
    final cleanWords = featureTitle
        .replaceAll(_nonAlphaNumSpaceRegex, ' ')
        .trim()
        .split(_whitespaceRegex)
        .where((w) => w.isNotEmpty)
        .toList();
    final stem = cleanWords.isEmpty
        ? 'action'
        : cleanWords.first.toLowerCase() +
            cleanWords
                .skip(1)
                .take(2)
                .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join();
    final corpus = '$featureTitle $featureGoal'.toLowerCase();
    if (corpus.contains('crate') ||
        corpus.contains('slot') ||
        corpus.contains('storage') ||
        corpus.contains('plant') ||
        corpus.contains('seed') ||
        corpus.contains('container')) {
      return <String>[
        '${stem}MaxSlots: 4 slots',
        '${stem}SnapRadius: 0.45 m',
      ];
    }
    if (corpus.contains('harvest') ||
        corpus.contains('pickup') ||
        corpus.contains('collect') ||
        corpus.contains('pull')) {
      return <String>[
        '${stem}ReachRange: 1.8 m',
        '${stem}HoldDuration: 0.35 s',
      ];
    }
    if (corpus.contains('corridor') ||
        corpus.contains('room') ||
        corpus.contains('arena') ||
        corpus.contains('layout') ||
        corpus.contains('blockout')) {
      return <String>[
        '${stem}WidthMeters: 4.0 m',
        '${stem}BayCount: 4 bays',
      ];
    }
    return <String>[
      '${stem}Rate: 1.0 units/s',
      '${stem}CooldownSec: 0.25 s',
    ];
  }

  /// Enforces the 3 Engineering Build Dependency Rules inside an Epic so Feature `N`
  /// only depends on scene geometry, target bodies, or base actions created in Features `1..N-1`:
  /// 1. Surface / Space Before Actor (Epic 1 blockout/layout precedes character locomotion).
  /// 2. Target Entity Before Tool / Tether / Resolver (`Scrap Core Physics` precedes `Harpoon Tow Cable`).
  /// 3. Base Mechanic Before Lock / Gate / Constraint (`Mature Crop Harvest` precedes `Tank Seal Depressurize`).
  static List<ProposedFeatureBlueprint> enforceIntraEpicBuildDependencies(
    List<ProposedFeatureBlueprint> rawFeatures, {
    required int epicIndex,
  }) {
    if (rawFeatures.length < 2) return rawFeatures;
    final list = List<ProposedFeatureBlueprint>.from(rawFeatures);

    bool isEnvironmentBlockout(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('blockout') ||
          t.contains('arena layout') ||
          t.contains('corridor layout') ||
          t.contains('station layout') ||
          t.contains('room layout') ||
          t.contains('level layout') ||
          t.contains('greybox arena') ||
          t.contains('station corridor');
    }

    // Rule 1: In Epic 1 (epicIndex == 0), move Greybox Level / Arena Blockout to index 0
    if (epicIndex == 0) {
      final blockoutIdx = list.indexWhere(isEnvironmentBlockout);
      if (blockoutIdx > 0) {
        final blockoutFeat = list.removeAt(blockoutIdx);
        list.insert(0, blockoutFeat);
      }
    }

    // Rule 2: Target Entity / Spawner must precede Tether / Harpoon / Projectile Impact
    bool isTetherOrImpactTool(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('tow cable') ||
          t.contains('harpoon') ||
          t.contains('tether') ||
          t.contains('projectile impact') ||
          t.contains('hit detection');
    }

    bool isTargetEntityOrSpawner(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return (t.contains('scrap core') ||
              t.contains('core physics') ||
              t.contains('drone spawner') ||
              t.contains('enemy spawner') ||
              t.contains('target spawner')) &&
          !isTetherOrImpactTool(f);
    }

    final toolIdx = list.indexWhere(isTetherOrImpactTool);
    final targetIdx = list.indexWhere(isTargetEntityOrSpawner);
    if (toolIdx != -1 && targetIdx > toolIdx) {
      final targetFeat = list.removeAt(targetIdx);
      list.insert(toolIdx, targetFeat);
    }

    // Rule 3: Base Harvest / Pickup Action must precede Lock / Seal / Depressurize Gate
    bool isPressureOrSealGate(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('depressuriz') ||
          t.contains('seal lock') ||
          t.contains('hatch lock') ||
          t.contains('pressure lock');
    }

    bool isBaseHarvestAction(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return (t.contains('harvest') ||
              t.contains('crop pickup') ||
              t.contains('crop extract')) &&
          !isPressureOrSealGate(f);
    }

    final gateIdx = list.indexWhere(isPressureOrSealGate);
    final harvestIdx = list.indexWhere(isBaseHarvestAction);
    if (gateIdx != -1 && harvestIdx > gateIdx) {
      final gateFeat = list.removeAt(gateIdx);
      list.insert(harvestIdx, gateFeat);
    }

    return list;
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
          final opts = _parseStringList(item['options']);
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
        final fGoal = (fMap['goal'] ?? '').toString().trim();
        final fDone = (fMap['doneWhen'] ?? '').toString().trim();
        final fTitle = disambiguateFeatureTitleFromBeat(
          (fMap['title'] ?? 'Feature ${fIdx + 1}').toString().trim(),
          beatTitle: bTitle,
          featureGoal: fGoal.isNotEmpty ? fGoal : bGoal,
          beatIndex: bIdx,
        );

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
        final primaryAsset =
            fMap['primarySharedScriptOrScene']?.toString().trim();

        final inScope = _parseStringList(fMap['inScope']);
        final outOfScope = _parseStringList(fMap['outOfScope']);
        final rawTuning = _parseStringList(fMap['tuningParams']);
        final tuning = rawTuning.isNotEmpty
            ? rawTuning
            : _defaultTuningParamsForFeature(fTitle, fGoal);
        final edges = _parseStringList(fMap['edgeCases'])
            .map((e) => e.replaceFirst(_tagPrefixRegex, '[STATE GUARD] '))
            .toList();

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
              extractCheckpointTasksFromMap(cMap),
              featureTitle: fTitle,
              beatTitle: bTitle,
              isFirstFeatureOfRelease: bIdx == 0 && fIdx == 0 && cIdx == 0,
            );
            final cScope = _parseStringList(cMap['coveredScope']);
            final cTuning = _parseStringList(cMap['tuningParams']);
            final cEdges = _parseStringList(cMap['edgeCases']);
            final cSubSteps = extractCheckpointTaskSubStepsFromMap(cMap);
            checkpoints.add(
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: cpVer,
                tasks: cpTasks,
                coveredScope: cScope.isNotEmpty ? cScope : inScope,
                tuningParams: cTuning.isNotEmpty ? cTuning : tuning,
                edgeCases: cEdges.isNotEmpty ? cEdges : edges,
                taskSubSteps: cSubSteps,
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
            primarySharedScriptOrScene:
                (primaryAsset != null && primaryAsset.isNotEmpty)
                    ? primaryAsset
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
        final orderedFeatures = (capV01Checkpoints && versionTag == 'v0.1')
            ? enforceIntraEpicBuildDependencies(features, epicIndex: bIdx)
            : features;
        beats.add(
          ProposedBeatBlueprint(
            id: (bMap['id'] ?? 'beat_${bIdx + 1}').toString(),
            title: bTitle,
            goal: bGoal,
            doneWhen: bDone,
            features: orderedFeatures,
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
    final currentDocPhase = (releaseDoc.sections['phase'] ?? '').trim();
    if (currentDocPhase == ProductionPhase.postLaunch.name ||
        currentDocPhase == ProductionPhase.fullProduction.name) {
      effectivePreset = ReleaseScope.fullProduction;
    } else if (currentDocPhase == ProductionPhase.verticalSlice.name) {
      effectivePreset = ReleaseScope.verticalSlice;
    } else if (currentDocPhase == ProductionPhase.mvp.name) {
      effectivePreset = ReleaseScope.mvp;
    } else if (isAgentReasoned &&
        releaseDoc.sections['phaseLockedByUser'] != 'true') {
      final rawPhase =
          (json['releasePhase'] ?? json['phase'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      if (rawPhase.contains('post') ||
          rawPhase.contains('live') ||
          rawPhase.contains('patch')) {
        releaseDoc.sections['phase'] = ProductionPhase.postLaunch.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.fullProduction.name;
        effectivePreset = ReleaseScope.fullProduction;
      } else if (rawPhase.contains('full') || rawPhase.contains('production')) {
        releaseDoc.sections['phase'] = ProductionPhase.fullProduction.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.fullProduction.name;
        effectivePreset = ReleaseScope.fullProduction;
      } else if (rawPhase.contains('vertical') ||
          rawPhase.contains('slice') ||
          rawPhase.contains('polish')) {
        releaseDoc.sections['phase'] = ProductionPhase.verticalSlice.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.verticalSlice.name;
        effectivePreset = ReleaseScope.verticalSlice;
      } else if (rawPhase.contains('mvp')) {
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
          : '$versionTag: ${rawRelTitle.replaceFirst(_versionPrefixStripRegex, '')}';
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

  static final RegExp _beatClauseDelimiterRegex = RegExp(
    r'\s*(?:,\s*then\s+|;\s+|,\s+and\s+|\s+and\s+|,\s+)\s*',
    caseSensitive: false,
  );
  static final RegExp _clauseWordRegex = RegExp(r'[A-Za-z0-9]+');
  static const Set<String> _clauseStopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'into',
    'from',
    'that',
    'this',
    'your',
    'their',
    'while',
    'when',
    'then',
    'over',
    'under',
    'across',
    'through',
    'onto',
    'upon',
    'build',
    'create',
    'implement',
    'verify',
    'greybox',
    'arena',
    'test',
    'scene',
    'level',
    'player',
  };

  static String _titleCaseWord(String word) {
    if (word.isEmpty) return word;
    if (word.length == 1) return word.toUpperCase();
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }

  /// Ensures a child Feature title never verbatim-clones its parent Epic (`beatTitle`).
  /// If `rawTitle` matches `beatTitle`, derives a concrete 2–3 word mechanic title from
  /// `featureGoal` (or appends a specific playable target/action word if `featureGoal` has no extra tokens).
  static String disambiguateFeatureTitleFromBeat(
    String rawTitle, {
    required String beatTitle,
    String featureGoal = '',
    int beatIndex = 0,
  }) {
    final cleaned = MechanicArchetypeProfile.concreteFeatureTitleForBeat(
      rawTitle,
      beatTitle: beatTitle,
      beatGoal: featureGoal,
      beatIndex: beatIndex,
    );
    final cleanBeat = beatTitle.trim();
    if (cleanBeat.isEmpty ||
        cleaned.toLowerCase() != cleanBeat.toLowerCase()) {
      return cleaned;
    }
    final beatWords = _clauseWordRegex
        .allMatches(cleanBeat.toLowerCase())
        .map((m) => m.group(0)!)
        .toSet();
    final goalWords = <String>[];
    for (final m in _clauseWordRegex.allMatches(featureGoal)) {
      final w = m.group(0)!;
      final lower = w.toLowerCase();
      if (lower.length < 3 || _clauseStopWords.contains(lower)) continue;
      if (beatWords.contains(lower)) continue;
      if (!goalWords.any((g) => g.toLowerCase() == lower)) {
        goalWords.add(_titleCaseWord(w));
      }
      if (goalWords.length >= 3) break;
    }
    if (goalWords.length >= 2) {
      return MechanicArchetypeProfile.concreteFeatureTitleForBeat(
        goalWords.take(3).join(' '),
        beatTitle: beatTitle,
        beatGoal: featureGoal,
        beatIndex: beatIndex,
      );
    }
    if (goalWords.length == 1) {
      final firstBeatWord = _clauseWordRegex.firstMatch(cleanBeat)?.group(0);
      final prefix = firstBeatWord != null
          ? _titleCaseWord(firstBeatWord)
          : cleaned;
      return '$prefix ${goalWords.first}';
    }
    return '$cleaned Target';
  }

  /// Dynamically decomposes a Beat's description (`rawDescPart`) into `1..N` distinct
  /// `ProposedFeatureBlueprint` items based on the action clauses present in the Beat
  /// (never hardcoding a feature count and never cloning `beatTitle` verbatim).
  static List<ProposedFeatureBlueprint> decomposeBeatIntoDynamicFeatures({
    required int beatNumber,
    required int beatIndex,
    required String beatTitle,
    required String rawBeatLine,
    required String rawDescPart,
    required String versionTag,
  }) {
    final candidateClauses = <String>[];
    if (rawDescPart.trim().isNotEmpty &&
        rawDescPart.trim().toLowerCase() != beatTitle.trim().toLowerCase()) {
      for (final rawClause
          in rawDescPart.split(_beatClauseDelimiterRegex)) {
        final c = rawClause.replaceAll(RegExp(r'\.+$'), '').trim();
        final wordCount = _clauseWordRegex.allMatches(c).length;
        if (wordCount >= 2) {
          candidateClauses.add(c);
        }
      }
    }
    if (candidateClauses.isEmpty) {
      candidateClauses.add(
        rawDescPart.trim().isNotEmpty ? rawDescPart.trim() : beatTitle,
      );
    }

    final features = <ProposedFeatureBlueprint>[];
    final usedTitlesLower = <String>{beatTitle.trim().toLowerCase()};

    for (int cIdx = 0; cIdx < candidateClauses.length; cIdx++) {
      final clause = candidateClauses[cIdx].trim();
      final clauseWords = <String>[];
      for (final m in _clauseWordRegex.allMatches(clause)) {
        final w = m.group(0)!;
        final lower = w.toLowerCase();
        if (lower.length < 3 || _clauseStopWords.contains(lower)) continue;
        if (!clauseWords.any((cw) => cw.toLowerCase() == lower)) {
          clauseWords.add(_titleCaseWord(w));
        }
        if (clauseWords.length >= 3) break;
      }
      final rawCandidateTitle = clauseWords.length >= 2
          ? clauseWords.take(3).join(' ')
          : beatTitle;
      var fTitle = disambiguateFeatureTitleFromBeat(
        rawCandidateTitle,
        beatTitle: beatTitle,
        featureGoal: clause,
        beatIndex: beatIndex,
      );
      if (usedTitlesLower.contains(fTitle.toLowerCase())) {
        fTitle = '$fTitle ${cIdx + 1}';
      }
      usedTitlesLower.add(fTitle.toLowerCase());

      final fGoal = clause.isNotEmpty
          ? (clause.endsWith('.') ? clause : '$clause.')
          : 'Build $fTitle in the greybox arena.';
      final tuning = _defaultTuningParamsForFeature(fTitle, fGoal);
      final guards = <String>[
        '[STATE GUARD] Prevent duplicate trigger while $fTitle is active',
      ];
      final tasks = normalizeFoundationFirstTasks(
        [
          (beatIndex == 0 && cIdx == 0)
              ? '$fTitle Body & Collision (2h)'
              : '$fTitle Prop & Collision (2h)',
          '$fTitle Action & Math (1h)',
          '$fTitle Cue & Boundary Clamp (1h)',
        ],
        featureTitle: fTitle,
        beatTitle: beatTitle,
        isFirstFeatureOfRelease: beatIndex == 0 && cIdx == 0,
      );

      features.add(
        ProposedFeatureBlueprint(
          id: 'feat_${beatNumber}_${cIdx + 1}',
          title: fTitle,
          goal: fGoal,
          doneWhen:
              'Playtester triggers $fTitle and verifies response on screen.',
          estimatedHours: 4,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: versionTag,
          inScope: [clause.isNotEmpty ? clause : rawBeatLine],
          outOfScope: const [],
          tuningParams: tuning,
          edgeCases: guards,
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: '$fTitle Core',
              playtestCriteria:
                  'Trigger $fTitle in playtest -> verify immediate response on screen',
              releaseVersion: versionTag,
              tasks: tasks,
              coveredScope: [clause.isNotEmpty ? clause : rawBeatLine],
              tuningParams: tuning,
              edgeCases: guards,
            ),
          ],
        ),
      );
    }
    return features;
  }

  /// Builds an immediate, deterministic `v0.1` `ReleaseBlueprint` directly from the approved
  /// Stage 1 `06 · Core Loop` Beats (`projectDoc.sections`) as a safety net when a live network
  /// timeout occurs during `v0.1` planning, ensuring `Approve & Build v0.1 →` never hangs or
  /// bounces the user back to Stage 1.
  static ReleaseBlueprint? buildImmediateInitialBaselineBlueprint({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
  }) {
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    if (coreLoopItems.isEmpty) return null;
    final preset = releaseDoc.releaseScope;
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final effectiveLoopItems =
        (prototypePart == '1' && coreLoopItems.length >= 2)
            ? coreLoopItems.take((coreLoopItems.length / 2).ceil()).toList()
            : coreLoopItems;

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < effectiveLoopItems.length; bIdx++) {
      final rawBeat = effectiveLoopItems[bIdx].trim();
      final colonIdx = rawBeat.indexOf(':');
      final rawTitlePart = colonIdx > 0
          ? rawBeat.substring(0, colonIdx).trim()
          : rawBeat;
      final rawDescPart = colonIdx > 0 && colonIdx + 1 < rawBeat.length
          ? rawBeat.substring(colonIdx + 1).trim()
          : '';

      final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
        rawTitlePart,
        beatIndex: bIdx,
      );
      final bGoal = rawDescPart.isNotEmpty
          ? (rawDescPart.endsWith('.') ? rawDescPart : '$rawDescPart.')
          : 'Build $bTitle in the greybox arena.';
      final dynamicFeatures = decomposeBeatIntoDynamicFeatures(
        beatNumber: bIdx + 1,
        beatIndex: bIdx,
        beatTitle: bTitle,
        rawBeatLine: rawBeat,
        rawDescPart: rawDescPart,
        versionTag: versionTag,
      );

      beats.add(
        ProposedBeatBlueprint(
          id: 'beat_${bIdx + 1}',
          title: bTitle,
          goal: bGoal,
          doneWhen: 'Playtester verifies $bTitle in the test arena.',
          features: dynamicFeatures,
        ),
      );
    }

    final projGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final projDone = SectionTextUtils.resolveDoneWhen(projectDoc.sections);
    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: projGoal.isNotEmpty
          ? projGoal
          : 'Build and verify the $versionTag playable greybox core loop.',
      doneWhen: projDone.isNotEmpty
          ? projDone
          : 'All $versionTag Core Loop Epics pass playtest verification.',
      questions: const [],
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Structured $versionTag Epics & Features directly from your approved Stage 1 Core Loop Beats.',
    );
  }

  /// Builds an immediate, phase-accurate `ReleaseBlueprint` for `releaseDoc` (`v0.2+`)
  /// from the existing Vault tree before the async `gemini-flash-latest` HTTP call completes
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
    final explicitVerTag = releaseDoc.sections['versionTag']?.trim();
    final versionTag = (explicitVerTag != null && explicitVerTag.isNotEmpty)
        ? explicitVerTag
        : extractReleaseVersionTag(releaseDoc.title);
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

    int defaultMvpBeatIdx = 0;
    if (targetMvpEpicIndex == null) {
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final feats =
            existingFeaturesByBeat[existingBeats[bIdx].id] ?? const <TierDocument>[];
        final anyStillV01Only = feats.any(
          (f) => FeatureStateNode.getStatesForDocument(f).length <= 1,
        );
        if (anyStillV01Only) {
          defaultMvpBeatIdx = bIdx;
          break;
        }
      }
    }

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final eb = existingBeats[bIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final isTargetEpic = targetMvpEpicIndex != null
          ? bIdx == targetMvpEpicIndex
          : (releasePhase == ProductionPhase.fullProduction.name
              ? eb.isFullProductionEpic
              : (releasePhase == ProductionPhase.verticalSlice.name ||
                      releasePhase == ProductionPhase.postLaunch.name
                  ? true
                  : bIdx == defaultMvpBeatIdx));

      final proposedFeats = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < existingFeats.length; fIdx++) {
        final ef = existingFeats[fIdx];
        if (ef.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: false,
              lifecycle: FeatureLifecycleStatus.superseded,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
          continue;
        }
        final shouldUpgrade = isTargetEpic;
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
    final defaultQuestions = releasePhase == ProductionPhase.postLaunch.name
        ? <AgentQuestion>[
            AgentQuestion(
              id: 'rel_q_post_launch',
              question: 'How should we focus $versionTag Post-Launch Live Ops?',
              options: const [
                '(Recommended) Content Expansion Pack: Add new playable roster/encounter variety and upgrade core loop depth',
                'Balance & Feel Patch: Tighten live tuning variables, resolve playtest [FIX] items, and harden [GUARD] rules',
                'Endgame Challenge Mode: Add high-intensity loop modifiers and mastery rewards using shipped v1.0 assets',
              ],
            ),
          ]
        : const <AgentQuestion>[];
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
      questions: defaultQuestions,
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
      } else if (prototypePart != '1' &&
          allCoreLoopItems.isNotEmpty &&
          parsed.beats.length < allCoreLoopItems.length) {
        // Ensure v0.1 covers every Stage 1 Core Loop Beat so trailing beats are never dropped
        Set<String> extractKeywords(String text) => text
            .toLowerCase()
            .replaceAll(_nonAlphaNumSpaceRegex, ' ')
            .split(_whitespaceRegex)
            .where((w) => w.length >= 4)
            .toSet();
        final fullBeats = List<ProposedBeatBlueprint>.from(parsed.beats);
        for (int cIdx = 0; cIdx < allCoreLoopItems.length; cIdx++) {
          final rawCore = allCoreLoopItems[cIdx].trim();
          final colonIdx = rawCore.indexOf(':');
          final rawTitlePart =
              colonIdx > 0 ? rawCore.substring(0, colonIdx).trim() : rawCore;
          final rawDescPart = colonIdx > 0 && colonIdx + 1 < rawCore.length
              ? rawCore.substring(colonIdx + 1).trim()
              : rawCore;
          final coreKeywords = extractKeywords(rawTitlePart);
          final alreadyCovered = fullBeats.any((b) {
            final bLower = b.title.toLowerCase();
            final cLower = rawTitlePart.toLowerCase();
            if (bLower.contains(cLower) || cLower.contains(bLower)) return true;
            final bKw = extractKeywords(b.title);
            return coreKeywords.isNotEmpty &&
                bKw.intersection(coreKeywords).isNotEmpty;
          });
          if (!alreadyCovered) {
            final nextBeatNum = fullBeats.length + 1;
            final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
              rawTitlePart,
              beatIndex: fullBeats.length,
            );
            final bGoal = rawDescPart.isNotEmpty
                ? (rawDescPart.endsWith('.') ? rawDescPart : '$rawDescPart.')
                : 'Build $bTitle in the greybox arena.';
            final dynamicFeatures = decomposeBeatIntoDynamicFeatures(
              beatNumber: nextBeatNum,
              beatIndex: fullBeats.length,
              beatTitle: bTitle,
              rawBeatLine: rawCore,
              rawDescPart: rawDescPart,
              versionTag: versionTag,
            );
            fullBeats.add(
              ProposedBeatBlueprint(
                id: 'beat_$nextBeatNum',
                title: bTitle,
                goal: bGoal,
                doneWhen: 'Playtester verifies $bTitle in the test arena.',
                features: dynamicFeatures,
              ),
            );
          }
        }
        parsed.beats = fullBeats;
      }
      return parsed;
    }

    if (existingBeats.isEmpty) return parsed;

    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    // Act 2 Skeleton: existing Epics match by exact ID only so brand-new Full Production Epics
    // (e.g. "Boss Wave Encounters") are never folded into a core Epic that shares a keyword.
    final isFpSkeleton = releaseDoc.sections['fpSkeleton'] == 'true';
    final matchedLlmBeatByExistingId = <String, ProposedBeatBlueprint>{};
    final unmatchedNewLlmBeats = <ProposedBeatBlueprint>[];

    Set<String> extractBeatKeywords(String text) => text
        .toLowerCase()
        .replaceAll(_nonAlphaNumSpaceRegex, ' ')
        .split(_whitespaceRegex)
        .where((w) => w.length >= 4)
        .toSet();

    for (int bIdx = 0; bIdx < parsed.beats.length; bIdx++) {
      final llmBeat = parsed.beats[bIdx];
      final cleanLlmTitle = llmBeat.title.toLowerCase().trim();
      final llmKeywords = extractBeatKeywords(llmBeat.title);
      TierDocument? matchedBeatDoc;

      if (isFpSkeleton) {
        // Core Epics stay STABLE: if the LLM reused a core Epic ID, keep only its NEW features
        // and move them into a fresh Full Production Epic so they are tracked in Act 2 coverage.
        final reusedCoreId = existingBeats.any((eb) => eb.id == llmBeat.id);
        if (reusedCoreId) {
          llmBeat.id = 'fp_${llmBeat.id}_$bIdx';
          llmBeat.features = llmBeat.features
              .where((f) => f.lifecycle == FeatureLifecycleStatus.newFeature)
              .toList();
        }
        if (llmBeat.features.isNotEmpty) {
          for (final f in llmBeat.features) {
            f.lifecycle = FeatureLifecycleStatus.newFeature;
            f.included = true;
            f.originVersion = versionTag;
          }
          unmatchedNewLlmBeats.add(llmBeat);
        }
        continue;
      }

      // 1. Exact ID or exact title match
      for (final eb in existingBeats) {
        if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
        if (eb.id == llmBeat.id ||
            eb.title.toLowerCase().trim() == cleanLlmTitle) {
          matchedBeatDoc = eb;
          break;
        }
      }
      // 2. Substring title match or shared feature ID/title match
      if (matchedBeatDoc == null && cleanLlmTitle.isNotEmpty) {
        for (final eb in existingBeats) {
          if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
          final cleanEbTitle = eb.title.toLowerCase().trim();
          final existingFeats =
              existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
          final sharesExistingFeature = llmBeat.features.any(
            (lf) => existingFeats.any(
              (ef) =>
                  ef.id == lf.id ||
                  ef.title.toLowerCase().trim() ==
                      lf.title.toLowerCase().trim(),
            ),
          );
          final sharesKeyword = llmKeywords.isNotEmpty &&
              extractBeatKeywords(eb.title)
                  .intersection(llmKeywords)
                  .isNotEmpty;
          if (cleanEbTitle.contains(cleanLlmTitle) ||
              cleanLlmTitle.contains(cleanEbTitle) ||
              sharesExistingFeature ||
              sharesKeyword) {
            matchedBeatDoc = eb;
            break;
          }
        }
      }
      // 3. Positional fallback only when not agent-reasoned delta OR when canonical beat_K ID matches
      if (matchedBeatDoc == null &&
          parsed.beats.length == existingBeats.length &&
          bIdx < existingBeats.length &&
          !matchedLlmBeatByExistingId.containsKey(existingBeats[bIdx].id)) {
        final canonicalBeatId = 'beat_${bIdx + 1}';
        final hasNonNewFeature = llmBeat.features.any(
          (f) => f.lifecycle != FeatureLifecycleStatus.newFeature,
        );
        if (!isAgentReasoned ||
            llmBeat.id == canonicalBeatId ||
            hasNonNewFeature) {
          // Only map onto existingBeats[bIdx] if it's an upgrade/canonical beat,
          // NEVER if it's a brand-new Epic with 100% new features and an unrelated title!
          final isUnrelatedNewEpic = isAgentReasoned &&
              !hasNonNewFeature &&
              extractBeatKeywords(existingBeats[bIdx].title)
                  .intersection(llmKeywords)
                  .isEmpty;
          if (!isUnrelatedNewEpic) {
            matchedBeatDoc = existingBeats[bIdx];
          }
        }
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
      llmBeat.title = eb.title;
      final matchedByExistingId = <String, ProposedFeatureBlueprint>{};
      final unmatchedNewFeats = <ProposedFeatureBlueprint>[];
      final cleanVer = versionTag.replaceAll(_nonAlphaNumRegex, '_');

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
        // Fallback for "upgrade" features when the LLM slightly reworded the feature title or used a generic feat_X_Y id
        if (matchedEf == null &&
            lf.lifecycle != FeatureLifecycleStatus.newFeature) {
          final lfKeywords = extractBeatKeywords(lf.title);
          for (final ef in existingFeats) {
            if (matchedByExistingId.containsKey(ef.id)) continue;
            if (ef.sections['lifecycle'] ==
                FeatureLifecycleStatus.superseded.name) {
              continue;
            }
            final normEfTitle = ef.title.toLowerCase().trim();
            final efKeywords = extractBeatKeywords(ef.title);
            if ((normEfTitle.isNotEmpty &&
                    normLfTitle.isNotEmpty &&
                    (normEfTitle.contains(normLfTitle) ||
                        normLfTitle.contains(normEfTitle))) ||
                (lfKeywords.isNotEmpty &&
                    efKeywords.intersection(lfKeywords).isNotEmpty)) {
              matchedEf = ef;
              break;
            }
          }
        }
        if (matchedEf != null) {
          lf.id = matchedEf.id;
          if (matchedEf.title.trim().isNotEmpty) {
            lf.title = matchedEf.title;
          }
          lf.originVersion = matchedEf.sections['originVersion'] ?? 'v0.1';
          final existingAsset =
              (matchedEf.sections['primary_asset'] ?? '').trim();
          if ((lf.primarySharedScriptOrScene == null ||
                  lf.primarySharedScriptOrScene!.trim().isEmpty) &&
              existingAsset.isNotEmpty) {
            lf.primarySharedScriptOrScene = existingAsset;
          }
          matchedByExistingId[matchedEf.id] = lf;
        } else {
          if (lf.lifecycle == FeatureLifecycleStatus.upgrade) {
            lf.lifecycle = FeatureLifecycleStatus.newFeature;
          }
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

      // Preserve canonical existing feature order first (UPGRADE, STABLE ✓, or SUPERSEDED), followed by genuinely NEW features
      final orderedFeatures = <ProposedFeatureBlueprint>[];
      for (final ef in existingFeats) {
        final matchedLf = matchedByExistingId[ef.id];
        final isAlreadySuperseded =
            ef.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;
        if (matchedLf != null) {
          orderedFeatures.add(matchedLf);
        } else {
          final existingAsset = (ef.sections['primary_asset'] ?? '').trim();
          orderedFeatures.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: !isAlreadySuperseded,
              lifecycle: isAlreadySuperseded
                  ? FeatureLifecycleStatus.superseded
                  : FeatureLifecycleStatus.stable,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              primarySharedScriptOrScene:
                  existingAsset.isNotEmpty ? existingAsset : null,
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
        final rawDocPhase = (releaseDoc.sections['phase'] ?? '').trim();
        final targetPhase = switch (rawDocPhase) {
          'postLaunch' => ProductionPhase.postLaunch,
          'fullProduction' => ProductionPhase.fullProduction,
          'verticalSlice' => ProductionPhase.verticalSlice,
          'mvp' => ProductionPhase.mvp,
          'prototype' => ProductionPhase.prototype,
          _ => ProductionPhase.mvp,
        };
        final combinedExclusions = <String>{
          ...projectExclusions,
          ...parsed.explicitExclusions,
        };
        for (final defFeat in deferredList) {
          final cleanDef = defFeat.title
              .toLowerCase()
              .replaceFirst(_noPrefixRegex, '')
              .trim();
          final isExcluded = combinedExclusions.any((ex) {
            if (!ReleaseBlueprint.isExclusionActiveForPhase(ex, targetPhase)) {
              return false;
            }
            final cleanEx = ex
                .toLowerCase()
                .replaceFirst(_cutPrefixRegex, '')
                .replaceFirst(_noPrefixRegex, '')
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
    TierDocument? projectDoc,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

    final currentBeatsSummary = blueprint.beats
        .map(
          (b) => '- ${b.id} "${b.title}": '
              '${b.features.map((f) => '"${f.title}" [id: ${f.id}, origin: ${f.originVersion.isNotEmpty ? f.originVersion : "v0.1"}, ${f.lifecycle.name}, ${f.included ? "IN" : "DEFERRED"}, ${f.activeDeltaHours}h${(f.primarySharedScriptOrScene != null && f.primarySharedScriptOrScene!.trim().isNotEmpty) ? ", asset: ${f.primarySharedScriptOrScene!.trim()}" : ""}${f.tuningParams.isNotEmpty ? ", vars: ${f.tuningParams.take(2).join("; ")}" : ""}]').join(', ')}',
        )
        .join('\n');

    final gameSpecText = (projectDoc?.sections['game_spec'] ??
            projectDoc?.sections['gameSpec'] ??
            '')
        .replaceAll('\n', ' · ')
        .trim();
    final techSpecText = (projectDoc?.sections['tech_spec'] ??
            projectDoc?.sections['techSpec'] ??
            '')
        .replaceAll('\n', ' · ')
        .trim();
    final pillarsText = (projectDoc?.sections['design_pillars'] ??
            projectDoc?.sections['designPillars'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final tradeOffsText = (projectDoc?.sections['trade_offs'] ??
            projectDoc?.sections['tradeOffs'] ??
            '')
        .replaceAll('\n', ' | ')
        .trim();
    final specCorpusLower = '$gameSpecText $techSpecText'.toLowerCase();
    final is2dPlan = specCorpusLower.contains('2d') ||
        specCorpusLower.contains('sprite') ||
        specCorpusLower.contains('pixel') ||
        specCorpusLower.contains('tilemap');
    final dimensionRule = (gameSpecText.isEmpty && techSpecText.isEmpty)
        ? ''
        : (is2dPlan
            ? 'Dimension Rule: 2D ONLY (use 2D scenes/nodes/colliders/Vector2; NEVER 3D nodes or Vector3).\n'
            : 'Dimension Rule: 3D (use 3D actors/nodes/colliders/Vector3).\n');
    final conceptHeader = projectDoc == null
        ? ''
        : 'Concept Context: Game Spec: $gameSpecText | Tech Spec: $techSpecText | Pillars: $pillarsText | Trade-Offs: $tradeOffsText\n$dimensionRule';

    final prompt = '''
You are the Antigravity Release Planner Agent updating "${blueprint.releaseTitle}" (${blueprint.releaseVersionTag}).
${conceptHeader}Current Plan:
- Goal: "${blueprint.goal}"
- Done When: "${blueprint.doneWhen}"
- Exclusions: ${blueprint.explicitExclusions.join(', ')}
- Beats:
$currentBeatsSummary

Developer Request: "$cleanMsg"
${GeminiAgentClient.compactStyleRules}
- DELTA-ONLY BEATS: In `beats`, return ONLY the specific Beat(s) that were modified or added by the developer's request (untouched Beats are preserved automatically).
- Keep `Task 1` focused on Scene/Entity/Collision foundation (never Input/Keybind) and include 2–3 `"paramName: value unit"` entries in `tuningParams`.

Call `mutate_release_plan` with the delta updates.
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: const [mutateReleasePlanTool],
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
    final cleanMsgLower = cleanMsg.toLowerCase();
    final isStrategicOptionSwitch = cleanMsgLower.startsWith('re-architect ') &&
        cleanMsgLower.contains('strategic option:');
    if (isStrategicOptionSwitch) {
      final markerIdx = cleanMsgLower.indexOf('strategic option:');
      if (markerIdx >= 0) {
        final rawOptText = cleanMsg
            .substring(markerIdx + 'strategic option:'.length)
            .replaceFirst(
              RegExp(r'^\(recommended\)\s*', caseSensitive: false),
              '',
            )
            .trim();
        final optTitle = rawOptText.split(':').first.trim();
        if (optTitle.isNotEmpty) {
          blueprint.releaseTitle =
              '${blueprint.releaseVersionTag}: $optTitle';
        }
      }
    }
    final isRemoveOrReplaceTurn = cleanMsgLower.contains('remove') ||
        cleanMsgLower.contains('delete') ||
        cleanMsgLower.contains('drop') ||
        cleanMsgLower.contains('cut') ||
        cleanMsgLower.contains('replace');
    Set<String> extractKeywords(String text) {
      return text
          .toLowerCase()
          .replaceAll(_nonAlphaNumSpaceRegex, ' ')
          .split(_whitespaceRegex)
          .where((w) => w.length >= 4 && w != 'beat' && w != 'epic' && w != 'loop')
          .toSet();
    }
    final mergedBeats = List<ProposedBeatBlueprint>.from(blueprint.beats);
    if (isStrategicOptionSwitch && updatedBp.beats.isNotEmpty) {
      for (final b in mergedBeats) {
        b.features.removeWhere(
          (f) =>
              f.lifecycle == FeatureLifecycleStatus.newFeature &&
              (f.originVersion.isEmpty ||
                  f.originVersion == blueprint.releaseVersionTag),
        );
        for (final f in b.features) {
          if (f.lifecycle == FeatureLifecycleStatus.upgrade) {
            f.lifecycle = FeatureLifecycleStatus.stable;
            f.estimatedHours = 0;
            f.included = true;
          }
        }
      }
    }
    for (final deltaBeat in updatedBp.beats) {
      final dTitle = deltaBeat.title.toLowerCase().trim();
      final dKeywords = extractKeywords(deltaBeat.title);
      // 1. Match by normalized title or substring first so generic "beat_1" schema examples
      // never overwrite Beat #1 when the LLM is actually targeting Beat #2..N by title.
      int idx = mergedBeats.indexWhere((b) {
        final bTitle = b.title.toLowerCase().trim();
        return bTitle == dTitle ||
            (bTitle.length >= 4 &&
                dTitle.length >= 4 &&
                (bTitle.contains(dTitle) || dTitle.contains(bTitle)));
      });
      // 2. Match by keyword overlap on the Beat title
      if (idx == -1 && dKeywords.isNotEmpty) {
        idx = mergedBeats.indexWhere(
          (b) => extractKeywords(b.title).intersection(dKeywords).isNotEmpty,
        );
      }
      // 3. Fall back to ID match when not a generic single-beat "beat_1" collision
      if (idx == -1) {
        idx = mergedBeats.indexWhere((b) {
          if (b.id != deltaBeat.id) return false;
          if (deltaBeat.id != 'beat_1' ||
              updatedBp.beats.length == mergedBeats.length) {
            return true;
          }
          return cleanMsgLower.contains(b.title.toLowerCase().trim()) ||
              cleanMsgLower.contains('beat 1') ||
              cleanMsgLower.contains('epic 1') ||
              cleanMsgLower.contains('e01');
        });
      }

      if (idx != -1) {
        final existingBeat = mergedBeats[idx];
        deltaBeat.id = existingBeat.id;
        if (existingBeat.title.trim().isNotEmpty) {
          deltaBeat.title = existingBeat.title;
        }
        final matchedUpdatesById = <String, ProposedFeatureBlueprint>{};
        final newlyAddedFeats = <ProposedFeatureBlueprint>[];
        for (final df in deltaBeat.features) {
          final dfTitle = df.title.toLowerCase().trim();
          ProposedFeatureBlueprint? existingFeat = existingBeat.features
              .where((ef) => ef.title.toLowerCase().trim() == dfTitle)
              .firstOrNull;
          existingFeat ??= existingBeat.features.where((ef) {
            if (matchedUpdatesById.containsKey(ef.id)) {
              return false;
            }
            if (ef.id == df.id &&
                (df.id != 'feat_1_1' ||
                    deltaBeat.features.length ==
                        existingBeat.features.length)) {
              return isRemoveOrReplaceTurn ||
                  isStrategicOptionSwitch ||
                  extractKeywords(ef.title)
                      .intersection(extractKeywords(df.title))
                      .isNotEmpty;
            }
            if (isStrategicOptionSwitch ||
                df.lifecycle != FeatureLifecycleStatus.newFeature) {
              return extractKeywords(ef.title)
                  .intersection(extractKeywords(df.title))
                  .isNotEmpty;
            }
            return false;
          }).firstOrNull;
          if (existingFeat != null) {
            df.id = existingFeat.id;
            if (existingFeat.title.trim().isNotEmpty &&
                (isStrategicOptionSwitch ||
                    df.lifecycle != FeatureLifecycleStatus.newFeature)) {
              df.title = existingFeat.title;
            }
            if (existingFeat.originVersion.isNotEmpty) {
              df.originVersion = existingFeat.originVersion;
            }
            if (df.originVersion != blueprint.releaseVersionTag &&
                df.lifecycle == FeatureLifecycleStatus.newFeature) {
              df.lifecycle = FeatureLifecycleStatus.upgrade;
            }
            if ((df.primarySharedScriptOrScene == null ||
                    df.primarySharedScriptOrScene!.trim().isEmpty) &&
                existingFeat.primarySharedScriptOrScene != null &&
                existingFeat.primarySharedScriptOrScene!.trim().isNotEmpty) {
              df.primarySharedScriptOrScene =
                  existingFeat.primarySharedScriptOrScene;
            }
            matchedUpdatesById[existingFeat.id] = df;
          } else {
            if (df.lifecycle == FeatureLifecycleStatus.upgrade &&
                blueprint.releaseVersionTag != 'v0.1') {
              df.lifecycle = FeatureLifecycleStatus.newFeature;
            }
            if (existingBeat.features.any((ef) => ef.id == df.id) ||
                newlyAddedFeats.any((nf) => nf.id == df.id) ||
                mergedBeats.any((b) => b.features.any((ef) => ef.id == df.id))) {
              df.id =
                  'feat_${existingBeat.id}_${existingBeat.features.length + newlyAddedFeats.length + 1}';
            }
            newlyAddedFeats.add(df);
          }
        }
        // Preserve existing features in existingBeat (both prior-release and same-release)
        // unless the user explicitly requested removing/replacing that feature.
        final reconciledFeats = <ProposedFeatureBlueprint>[];
        for (final ef in existingBeat.features) {
          final updatedFeat = matchedUpdatesById[ef.id];
          if (updatedFeat != null) {
            reconciledFeats.add(updatedFeat);
          } else {
            final explicitlyRemoved = isRemoveOrReplaceTurn &&
                (cleanMsgLower.contains(ef.title.toLowerCase().trim()) ||
                    deltaBeat.features.isNotEmpty &&
                        existingBeat.features.length == 1 &&
                        cleanMsgLower.contains('instead'));
            if (!explicitlyRemoved) {
              reconciledFeats.add(ef);
            }
          }
        }
        reconciledFeats.addAll(newlyAddedFeats);
        deltaBeat.features
          ..clear()
          ..addAll(reconciledFeats);
        mergedBeats[idx] = deltaBeat;
      } else {
        if (mergedBeats.any((b) => b.id == deltaBeat.id)) {
          deltaBeat.id = 'beat_${mergedBeats.length + 1}';
        }
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
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-zA-Z0-9]');
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

      final concreteBeatTitle =
          MechanicArchetypeProfile.concreteBeatDisplayTitle(
        beatBp.title,
        beatIndex: bIdx,
      );
      final existingBeat = isInitialPrototypeRelease
          ? projectScopedDocs['epic_${releaseDoc.id}_${bIdx + 1}']
          : (projectScopedDocs[beatBp.id] ??
              existingBeatsByTitle[concreteBeatTitle.toLowerCase().trim()] ??
              existingBeatsByTitle[beatBp.title.toLowerCase().trim()]);
      if (includedFeats.isEmpty &&
          (isInitialPrototypeRelease || existingBeat == null)) {
        continue;
      }

      beatTitles.add(concreteBeatTitle);
      onProgress?.call(
        'Syncing Core Loop Epic ${bIdx + 1}: $concreteBeatTitle...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

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
      // Act 2: every brand-new Epic created by a Full Production release is a Full Production Epic.
      if (existingBeat == null &&
          releaseDoc.sections['phase'] == ProductionPhase.fullProduction.name) {
        beatDoc.sections[TierDocument.actSectionKey] =
            TierDocument.fullProductionAct;
      }
      final priorBeatFeatureIds = List<String>.from(beatDoc.childrenIds);
      beatDoc.title = concreteBeatTitle;
      beatDoc.parentId = releaseDoc.id;
      beatDoc.estimatedDuration = '${beatBp.totalIncludedHours}h';
      beatDoc.sections['scope'] = 'Goal: ${beatBp.goal}\n\n'
          'In Scope:\n$featTitlesForBeat\n\n'
          '${deferredForBeat.isNotEmpty ? 'Out of Scope:\n$deferredForBeat\n\n' : ''}'
          'Done When: ${beatBp.doneWhen}';
      beatDoc.childrenIds.clear();

      beatBp.id = beatDoc.id;
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
        final existingFeat = isInitialPrototypeRelease
            ? null
            : (canMatchById
                ? candidateById
                : (candidateByTitle != null &&
                        !allocatedFeatIds.contains(candidateByTitle.id)
                    ? candidateByTitle
                    : null));

        String featId;
        if (existingFeat != null) {
          featId = existingFeat.id;
        } else {
          final defaultId = 'feat_${beatId}_${fIdx + 1}';
          if ((isInitialPrototypeRelease &&
                  !allocatedFeatIds.contains(defaultId)) ||
              (!existingDocuments.containsKey(defaultId) &&
                  !projectScopedDocs.containsKey(defaultId) &&
                  !allocatedFeatIds.contains(defaultId))) {
            featId = defaultId;
          } else {
            final cleanVer =
                versionTag.replaceAll(_nonAlphaNumRegex, '_');
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
          existingFeat.sections.remove('supersededInVersion');
          existingFeat.sections.remove('supersededByRelease');
          existingFeat.sections['activeReleaseVersion'] = versionTag;
          final stableStates =
              FeatureStateNode.getStatesForDocument(existingFeat);
          existingFeat.sections['lastVerifiedVersion'] = stableStates.isNotEmpty
              ? stableStates.last.releaseVersion
              : (existingFeat.sections['originVersion'] ?? 'v0.1');
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
        featDoc.sections.remove('supersededInVersion');
        featDoc.sections.remove('supersededByRelease');
        final effectivePrimaryAsset = (featBp.primarySharedScriptOrScene != null &&
                featBp.primarySharedScriptOrScene!.trim().isNotEmpty)
            ? featBp.primarySharedScriptOrScene!.trim()
            : (existingFeat?.sections['primary_asset'] ?? '').trim();
        if (effectivePrimaryAsset.isNotEmpty) {
          featDoc.sections['primary_asset'] = effectivePrimaryAsset;
        }
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

          final cpNode = FeatureStateNode(
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
              if (effectivePrimaryAsset.isNotEmpty)
                'primarySharedScriptOrScene': effectivePrimaryAsset,
            },
          );
          final projDocForHint =
              parentProjId != null ? existingDocuments[parentProjId] : null;
          final engineHint = projDocForHint?.sections['tech_spec'] ??
              projDocForHint?.sections['techSpec'] ??
              projDocForHint?.sections['tech_stack'] ??
              '';
          final rawPhase = (releaseDoc.sections['phase'] ?? '').trim();
          final releasePhase = switch (rawPhase) {
            'postLaunch' => ProductionPhase.postLaunch,
            'fullProduction' => ProductionPhase.fullProduction,
            'verticalSlice' => ProductionPhase.verticalSlice,
            'mvp' => ProductionPhase.mvp,
            'prototype' => ProductionPhase.prototype,
            _ => switch (blueprint.preset) {
              ReleaseScope.patch ||
              ReleaseScope.contentUpdate =>
                ProductionPhase.postLaunch,
              ReleaseScope.fullProduction => ProductionPhase.fullProduction,
              ReleaseScope.verticalSlice => ProductionPhase.verticalSlice,
              ReleaseScope.mvp => ProductionPhase.mvp,
              _ => ProductionPhase.prototype,
            },
          };
          for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
            final inlineSteps = cpBp.taskSubSteps[tIdx];
            if (inlineSteps != null && inlineSteps.isNotEmpty) {
              final parentTask = cpNode.checklist[tIdx];
              parentTask.children = [
                for (int sIdx = 0; sIdx < inlineSteps.length; sIdx++)
                  () {
                    final s = inlineSteps[sIdx];
                    final sTitle = (s['title'] ?? 'Step ${tIdx + 1}.${sIdx + 1}')
                        .replaceFirst(
                          RegExp(r'^STEP\s*\d+\.\d+\s*[·:\-–—]?\s*',
                              caseSensitive: false),
                          '',
                        )
                        .trim();
                    final sPath = (s['stepPath'] ?? '').trim();
                    final sInst = (s['instruction'] ?? '').trim();
                    final sA1 = (s['area1Hierarchy'] ?? '').trim();
                    final sA2 = (s['area2Inspector'] ?? '').trim();
                    final specLines = <String>[
                      if (sPath.isNotEmpty) 'Path: $sPath',
                      if (sInst.isNotEmpty) sInst,
                      if (sA1.isNotEmpty) 'AREA 1 · HIERARCHY: $sA1',
                      if (sA2.isNotEmpty) 'AREA 2 · INSPECTOR: $sA2',
                    ];
                    return Subtask(
                      id: '${parentTask.id}_sub_${sIdx + 1}',
                      text: 'STEP ${tIdx + 1}.${sIdx + 1} · $sTitle',
                      completed: false,
                      specNotes: specLines.join('\n'),
                      codeTargetFile: 'custom_snippet',
                      codeSnippet: (s['codeFormula'] ?? '').trim(),
                      verification: (s['verifyResult'] ?? '').trim(),
                    );
                  }(),
              ];
            } else {
              TaskHowToBlueprint.resolve(
                parentTask: cpNode.checklist[tIdx],
                taskIndex: tIdx,
                checkpointNode: cpNode,
                engineHint: engineHint,
                phase: releasePhase,
              );
            }
          }
          stateNodes.add(cpNode);
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        if (!beatDoc.childrenIds.contains(featDoc.id)) {
          beatDoc.childrenIds.add(featDoc.id);
        }
        createdOrUpdatedDocs.add(featDoc);
      }

      if (!isInitialPrototypeRelease) {
        for (final priorFeatId in priorBeatFeatureIds) {
          if (beatDoc.childrenIds.contains(priorFeatId) ||
              allocatedFeatIds.contains(priorFeatId)) {
            continue;
          }
          final priorFeatDoc =
              projectScopedDocs[priorFeatId] ?? existingDocuments[priorFeatId];
          if (priorFeatDoc == null) continue;
          if (priorFeatDoc.sections['lifecycle'] ==
              FeatureLifecycleStatus.superseded.name) {
            continue;
          }
          final explicitlySupersededInBp = beatBp.features.any(
            (f) =>
                (f.id == priorFeatId ||
                    f.title.toLowerCase().trim() ==
                        priorFeatDoc.title.toLowerCase().trim()) &&
                f.lifecycle == FeatureLifecycleStatus.superseded,
          );
          if (explicitlySupersededInBp) continue;

          priorFeatDoc.parentId = beatDoc.id;
          priorFeatDoc.sections['lifecycle'] =
              FeatureLifecycleStatus.stable.name;
          priorFeatDoc.sections.remove('supersededInVersion');
          priorFeatDoc.sections.remove('supersededByRelease');
          priorFeatDoc.sections['activeReleaseVersion'] = versionTag;
          final priorStates =
              FeatureStateNode.getStatesForDocument(priorFeatDoc);
          priorFeatDoc.sections['lastVerifiedVersion'] = priorStates.isNotEmpty
              ? priorStates.last.releaseVersion
              : (priorFeatDoc.sections['originVersion'] ?? 'v0.1');
          if (priorStates.isNotEmpty) {
            for (final s in priorStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final c in t.children) {
                  c.completed = true;
                }
              }
            }
            FeatureStateNode.saveStatesToDocument(priorFeatDoc, priorStates);
          }
          beatDoc.childrenIds.add(priorFeatDoc.id);
          createdOrUpdatedDocs.add(priorFeatDoc);
        }
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

  /// Materializes all System Epic (`E01`..`EN`) TierDocuments (`epic_${releaseDoc.id}_1` .. `epic_${releaseDoc.id}_N`)
  /// into `releaseDoc.childrenIds` immediately after Phase 1 (`planReleaseSystemEpics`) so all Epics appear in the
  /// Left Outliner Rail right away (`E01` showing `⟳`, `E02`..`EN` showing `Queued`).
  static List<TierDocument> createInitialSystemEpicDocs({
    required TierDocument releaseDoc,
    required ReleaseBlueprint blueprint,
  }) {
    final createdEpics = <TierDocument>[];
    final beatTitles = <String>[];
    final versionTag = blueprint.releaseVersionTag;
    releaseDoc.childrenIds.clear();

    for (int bIdx = 0; bIdx < blueprint.beats.length; bIdx++) {
      final beatBp = blueprint.beats[bIdx];
      final concreteBeatTitle =
          MechanicArchetypeProfile.concreteBeatDisplayTitle(
        beatBp.title,
        beatIndex: bIdx,
      );
      beatTitles.add(concreteBeatTitle);
      final beatId = 'epic_${releaseDoc.id}_${bIdx + 1}';
      beatBp.id = beatId;

      final beatDoc = TierDocument(
        id: beatId,
        title: concreteBeatTitle,
        tier: TierType.epic,
        parentId: releaseDoc.id,
        estimatedDuration: '0h',
        sections: <String, String>{
          'scope': 'Goal: ${beatBp.goal}\n\n'
              'In Scope:\n\n'
              'Done When: ${beatBp.doneWhen}',
        },
      );
      releaseDoc.childrenIds.add(beatDoc.id);
      createdEpics.add(beatDoc);
    }

    final inScopeBeats = beatTitles.map((t) => '• $t').join('\n');
    final outScopeItems =
        blueprint.effectiveOutOfScope.map((o) => '• $o').join('\n');
    releaseDoc.title = blueprint.releaseTitle;
    releaseDoc.sections['releaseScope'] = blueprint.preset.name;
    releaseDoc.sections['versionTag'] = versionTag;
    releaseDoc.sections['release_blueprint_json'] =
        jsonEncode(blueprint.toJson());
    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['scope'] = 'Goal: ${blueprint.goal}\n\n'
        'In Scope:\n$inScopeBeats\n\n'
        'Out of Scope:\n$outScopeItems\n\n'
        'Done When: ${blueprint.doneWhen}';

    return createdEpics;
  }

  /// Materializes the playable Feature TierDocuments (`feat_${beatDoc.id}_1` .. `feat_${beatDoc.id}_M`)
  /// for a SINGLE System Epic (`beatDoc` at `epicIndex`) without clearing `releaseDoc.childrenIds`
  /// or overwriting any earlier Epic or Feature documents.
  static List<TierDocument> materializeFeaturesForSingleEpic({
    required TierDocument releaseDoc,
    required TierDocument beatDoc,
    required ReleaseBlueprint blueprint,
    required ProposedBeatBlueprint beatBp,
    required int epicIndex,
    Map<String, TierDocument> existingDocuments = const {},
  }) {
    final createdFeatures = <TierDocument>[];
    final versionTag = blueprint.releaseVersionTag;
    final includedFeats = beatBp.includedFeatures;
    final concreteBeatTitle =
        MechanicArchetypeProfile.concreteBeatDisplayTitle(
      beatBp.title,
      beatIndex: epicIndex,
    );
    final featTitlesForBeat = includedFeats
        .map(
          (f) =>
              '• ${MechanicArchetypeProfile.concreteFeatureTitleForBeat(f.title, beatTitle: concreteBeatTitle, beatGoal: beatBp.goal, beatIndex: epicIndex)}: ${f.goal}',
        )
        .join('\n');
    final deferredForBeat =
        beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

    beatDoc.title = concreteBeatTitle;
    beatDoc.parentId = releaseDoc.id;
    beatDoc.estimatedDuration = '${beatBp.totalIncludedHours}h';
    beatDoc.sections['scope'] = 'Goal: ${beatBp.goal}\n\n'
        'In Scope:\n$featTitlesForBeat\n\n'
        '${deferredForBeat.isNotEmpty ? 'Out of Scope:\n$deferredForBeat\n\n' : ''}'
        'Done When: ${beatBp.doneWhen}';
    beatDoc.childrenIds.clear();

    final parentProjId = releaseDoc.parentId;
    final projDocForHint =
        parentProjId != null ? existingDocuments[parentProjId] : null;
    final engineHint = projDocForHint?.sections['tech_spec'] ??
        projDocForHint?.sections['techSpec'] ??
        projDocForHint?.sections['tech_stack'] ??
        '';
    final rawPhase = (releaseDoc.sections['phase'] ?? '').trim();
    final releasePhase = switch (rawPhase) {
      'postLaunch' => ProductionPhase.postLaunch,
      'fullProduction' => ProductionPhase.fullProduction,
      'verticalSlice' => ProductionPhase.verticalSlice,
      'mvp' => ProductionPhase.mvp,
      'prototype' => ProductionPhase.prototype,
      _ => ProductionPhase.prototype,
    };

    for (int fIdx = 0; fIdx < includedFeats.length; fIdx++) {
      final featBp = includedFeats[fIdx];
      final concreteFeatTitle =
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
        featBp.title,
        beatTitle: beatBp.title,
        beatGoal: beatBp.goal,
        beatIndex: epicIndex,
      );
      final featId = 'feat_${beatDoc.id}_${fIdx + 1}';
      featBp.id = featId;

      final inScopeText = featBp.inScope.map((s) => '• $s').join('\n');
      final outScopeText = featBp.outOfScope.map((s) => '• $s').join('\n');
      final tuningText = featBp.tuningParams.map((t) => '• $t').join('\n');
      final edgeText = featBp.edgeCases.map((e) => '• $e').join('\n');
      final effectivePrimaryAsset =
          (featBp.primarySharedScriptOrScene ?? '').trim();

      final featDoc = TierDocument(
        id: featId,
        title: concreteFeatTitle,
        tier: TierType.feature,
        parentId: beatDoc.id,
        estimatedDuration: '${featBp.activeDeltaHours}h',
        sections: <String, String>{
          'originVersion': versionTag,
          'activeReleaseVersion': versionTag,
          'lifecycle': featBp.lifecycle.name,
          if (effectivePrimaryAsset.isNotEmpty)
            'primary_asset': effectivePrimaryAsset,
          'scope': 'Goal: ${featBp.goal}\n\n'
              'In Scope:\n$inScopeText\n\n'
              '${outScopeText.isNotEmpty ? 'Out of Scope:\n$outScopeText\n\n' : ''}'
              'Done When: ${featBp.doneWhen}',
          'variables': tuningText,
          'tuning': tuningText,
          'edge_cases': edgeText,
        },
      );

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

      final stateNodes = <FeatureStateNode>[];
      for (int cIdx = 0; cIdx < effectiveCheckpoints.length; cIdx++) {
        final cpBp = effectiveCheckpoints[cIdx];
        final cpNumber = cIdx + 1;
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

        final cpNode = FeatureStateNode(
          id: '${featId}_${versionTag}_cp_$cpNumber',
          name: 'Checkpoint $cpNumber: ${cpBp.title}',
          trigger: 'Playtest: ${cpBp.playtestCriteria}',
          order: cIdx,
          checklist: checklist,
          coveredScope: List<String>.from(cpBp.coveredScope),
          tuningParams: List<String>.from(cpBp.tuningParams),
          edgeCases: List<String>.from(cpBp.edgeCases),
          parameters: {
            'releaseVersion': versionTag,
            if (effectivePrimaryAsset.isNotEmpty)
              'primarySharedScriptOrScene': effectivePrimaryAsset,
          },
        );
        for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
          TaskHowToBlueprint.resolve(
            parentTask: cpNode.checklist[tIdx],
            taskIndex: tIdx,
            checkpointNode: cpNode,
            engineHint: engineHint,
            phase: releasePhase,
          );
        }
        stateNodes.add(cpNode);
      }

      FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
      beatDoc.childrenIds.add(featDoc.id);
      createdFeatures.add(featDoc);
    }

    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['release_blueprint_json'] =
        jsonEncode(blueprint.toJson());
    return createdFeatures;
  }
}

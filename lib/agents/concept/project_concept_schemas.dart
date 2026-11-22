import '../../constants/text_style_guide.dart';
import '../../models/agent_blueprints.dart';

Map<String, dynamic> get rootSpecToolSchema => <String, dynamic>{
      'name': 'commit_unreal_root_spec',
      'description':
          'Create the Unreal Engine 5 Project Spec (PROJECT_SPEC.md -> ROOT_UNREAL_CONTEXT) with §01-§04 foundation contracts and strictly v0.1 prototype Epics in §05 using the 4-tier Epic -> Feature hierarchy.',
      'parameters': <String, dynamic>{
        'type': 'OBJECT',
        'required': [
          'gameTitle',
          'architectureMode',
          'pitch',
          'coreLoop',
          'cameraChoiceId',
          'cameraContract',
          'characterScale',
          'inputContract',
          'assetPolicy',
          'pillars',
          'tradeOffs',
          'outOfScope',
          'releaseDoneWhen',
          'initialEpics',
        ],
        'properties': <String, dynamic>{
          'gameTitle': {
            'type': 'STRING',
            'description': '2-3 word plain game title in UPPERCASE.',
          },
          'architectureMode': {
            'type': 'STRING',
            'enum': ['blueprint', 'cppHybrid'],
            'description':
                'Unreal Engine 5 architecture mode: blueprint (BP_* + WBP_*) or cppHybrid (Source/ UPROPERTY C++ base + thin BP_*).',
          },
          'pitch': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.blufVisionSchemaDesc,
          },
          'coreLoop': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.coreLoopStepSchemaDesc,
            },
          },
          'cameraChoiceId': {
            'type': 'STRING',
            'enum': [
              'isometric',
              'topdown',
              'tps',
              'fps',
              'sidescroller',
            ],
          },
          'cameraContract': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.unrealContractSchemaDesc,
          },
          'characterScale': {
            'type': 'STRING',
            'description':
                'Player ACharacter capsule size and MaxWalkSpeed in cm and cm/s.',
          },
          'inputContract': {
            'type': 'STRING',
            'description':
                'Unreal Enhanced Input Mapping Context and PascalCase actions (e.g. IMC_Gameplay: IA_Move, IA_Dash, IA_PrimaryAction).',
          },
          'assetPolicy': {
            'type': 'STRING',
            'description':
                'Greybox prototype policy (/Game/Maps/Lvl_* + /Game/Blueprints/BP_* + /Game/Data/DA_* or Source/ C++ classes) with PascalCase Exposed BP or UPROPERTY(EditAnywhere) variables.',
          },
          'cameraDecisionOptions': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['id', 'label', 'contractValue'],
              'properties': {
                'id': {'type': 'STRING'},
                'label': {'type': 'STRING'},
                'contractValue': {'type': 'STRING'},
                'note': {'type': 'STRING'},
              },
            },
          },
          'feelChoiceId': {
            'type': 'STRING',
            'enum': ['snappy', 'heavy', 'physics'],
          },
          'pillars': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.pillarSchemaDesc,
            },
          },
          'tradeOffs': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['prefer', 'avoid'],
              'properties': {
                'prefer': {'type': 'STRING'},
                'avoid': {'type': 'STRING'},
              },
            },
          },
          'outOfScope': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
            },
          },
          'releaseDoneWhen': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.causalPlaytestCheckSchemaDesc,
          },
          'initialEpics': {
            'type': 'ARRAY',
            'description':
                'Strictly 2-4 v0.1 playable prototype Epics ordered by dependency (defer v0.2+ waves/meta).',
            'items': epicJsonSchema,
          },
          'coDesignNote': {
            'type': 'STRING',
            'description': 'Short 1-line summary of the spec changes applied.',
          },
        },
      },
    };

Map<String, dynamic> get featureJsonSchema => <String, dynamic>{
      'type': 'OBJECT',
      'required': [
        'code',
        'title',
        'sliceTime',
        'goal',
        'inScope',
        'doneWhen',
        'controls',
        'tuning',
        'cues',
        'checks',
      ],
      'properties': <String, dynamic>{
        'code': {
          'type': 'STRING',
          'description': 'Sequential Feature slice code F01, F02, F03...',
        },
        'title': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.featureTitleSchemaDesc,
        },
        'sliceTime': {
          'type': 'STRING',
          'description': 'Playable build slice target such as "45 min" or "60 min".',
        },
        'goal': {
          'type': 'STRING',
          'description':
              '1 plain sentence stating what this playable slice builds in PIE.',
        },
        'inScope': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'doneWhen': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.causalPlaytestCheckSchemaDesc,
          },
        },
        'controls': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['action', 'trigger', 'rule'],
            'properties': {
              'action': {'type': 'STRING'},
              'trigger': {'type': 'STRING'},
              'rule': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.unrealControlRuleSchemaDesc,
              },
            },
          },
        },
        'tuning': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['key', 'value', 'unit'],
            'properties': {
              'key': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.unrealTuningKeySchemaDesc,
              },
              'value': {'type': 'STRING'},
              'unit': {
                'type': 'STRING',
                'description': LayersTextStyleGuide.unrealTuningUnitSchemaDesc,
              },
            },
          },
        },
        'cues': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'checks': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'required': ['text'],
            'properties': {
              'text': {
                'type': 'STRING',
                'description':
                    LayersTextStyleGuide.causalPlaytestCheckSchemaDesc,
              },
            },
          },
        },
      },
    };

Map<String, dynamic> get epicJsonSchema => <String, dynamic>{
      'type': 'OBJECT',
      'required': [
        'code',
        'title',
        'coreLoopBeat',
        'goal',
        'inScope',
        'doneWhen',
        'sceneOwnership',
        'states',
        'interrupts',
        'outOfScope',
        'features',
      ],
      'properties': <String, dynamic>{
        'code': {
          'type': 'STRING',
          'description': 'Sequential code E01, E02, E03...',
        },
        'lineageKey': {
          'type': 'STRING',
          'description':
              'Stable Epic lineage identifier across edits and releases (preserve existing value when editing).',
        },
        'title': {
          'type': 'STRING',
          'description': LayersTextStyleGuide.epicTitleSchemaDesc,
        },
        'coreLoopBeat': {
          'type': 'STRING',
          'description':
              'Which §01 Core Loop beat(s) this Epic domain proves in PIE (e.g. "Beat 1: Move & Aim").',
        },
        'goal': {
          'type': 'STRING',
          'description':
              '1 plain sentence describing the large-domain Unreal Engine 5 Epic architecture.',
        },
        'inScope': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'doneWhen': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.causalPlaytestCheckSchemaDesc,
          },
        },
        'sceneOwnership': {
          'type': 'ARRAY',
          'description': LayersTextStyleGuide.sceneOwnershipSchemaDesc,
          'items': {
            'type': 'OBJECT',
            'required': ['path', 'role'],
            'properties': {
              'path': {'type': 'STRING'},
              'role': {'type': 'STRING'},
            },
          },
        },
        'outOfScope': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
          },
        },
        'states': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'interrupts': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'features': {
          'type': 'ARRAY',
          'description':
              '2-3 sittable 30-90 min playable v0.1 Feature slices inside this domain Epic (zero Tasks, zero Steps). Include Enhanced Input controls, Exposed BP / UPROPERTY tuning in cm & cm/s, cues, and PIE Playtest Gate checks here only.',
          'items': featureJsonSchema,
        },
      },
    };

Map<String, dynamic> get patchRootSpecToolSchema => <String, dynamic>{
      'name': 'patch_unreal_root_spec',
      'description':
          'Apply a scoped partial patch to only the Stage 1 Unreal Engine 5 Project Spec sections (§01-§05) affected by the user instruction, leaving untouched sections and Epics intact.',
      'parameters': <String, dynamic>{
        'type': 'OBJECT',
        'required': ['coDesignNote', 'changedSections'],
        'properties': <String, dynamic>{
          'coDesignNote': {
            'type': 'STRING',
            'description': 'Short 1-line summary of the spec changes applied.',
          },
          'changedSections': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'enum': ['s01', 's02', 's03', 's04', 's05'],
            },
          },
          'gameTitle': {'type': 'STRING'},
          'architectureMode': {
            'type': 'STRING',
            'enum': ['blueprint', 'cppHybrid'],
          },
          'pitch': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.blufVisionSchemaDesc,
          },
          'coreLoop': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'cameraChoiceId': {
            'type': 'STRING',
            'enum': [
              'isometric',
              'topdown',
              'tps',
              'fps',
              'sidescroller',
            ],
          },
          'cameraContract': {'type': 'STRING'},
          'characterScale': {'type': 'STRING'},
          'inputContract': {'type': 'STRING'},
          'assetPolicy': {'type': 'STRING'},
          'cameraDecisionOptions': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['id', 'label', 'contractValue'],
              'properties': {
                'id': {'type': 'STRING'},
                'label': {'type': 'STRING'},
                'contractValue': {'type': 'STRING'},
                'note': {'type': 'STRING'},
              },
            },
          },
          'feelChoiceId': {
            'type': 'STRING',
            'enum': ['snappy', 'heavy', 'physics'],
          },
          'pillars': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'tradeOffs': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'required': ['prefer', 'avoid'],
              'properties': {
                'prefer': {'type': 'STRING'},
                'avoid': {'type': 'STRING'},
              },
            },
          },
          'outOfScope': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'releaseDoneWhen': {'type': 'STRING'},
          'epicUpdates': {
            'type': 'ARRAY',
            'description':
                'Only Epics created or modified by this instruction (matched by lineageKey or code). Omit untouched Epics.',
            'items': epicJsonSchema,
          },
          'removeEpicLineageKeys': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'initialEpics': {
            'type': 'ARRAY',
            'description':
                'Only include full initialEpics array when restructuring the entire §05 prototype queue.',
            'items': epicJsonSchema,
          },
        },
      },
    };

Map<String, dynamic> compactStage1JsonForPrompt(
  ProjectConceptBlueprint spec,
) {
  final full = spec.toJson();
  full.remove('v02Presets');
  full.remove('v02NewPool');
  full.remove('v02UpgradesByLineageKey');
  full.remove('v02NewFeaturesByLineageKey');
  full.remove('approved');
  full.remove('lastCoDesignNote');
  final epics = full['initialEpics'];
  if (epics is List) {
    for (final ep in epics) {
      if (ep is Map &&
          ep['features'] is List &&
          (ep['features'] as List).isNotEmpty) {
        ep.remove('controls');
        ep.remove('tuning');
        ep.remove('feedback');
        ep.remove('levelStaging');
        ep.remove('checks');
        ep.remove('links');
      }
    }
  }
  return full;
}

import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/godot_spec_guard.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Godot 4 Progressive Release Planner Agent (`v0.1 -> v0.2 -> v0.3+`).
/// Generates Co-Pilot release direction presets, `[UPGRADE]` delta checkboxes per baseline Epic,
/// and candidate `[NEW]` 6-section Godot 4 Epics without ever duplicating cards.
class ReleasePlannerAgent {
  static String extractReleaseVersionTag(String? rawTitle) {
    final text = (rawTitle ?? '').trim();
    final match = RegExp(r'\bv\d+(?:\.\d+)*\b', caseSensitive: false)
        .firstMatch(text);
    return match != null ? match.group(0)!.toLowerCase() : 'v0.1';
  }

  static String nextMinorVersionTag(String? currentVersion) {
    final tag = extractReleaseVersionTag(currentVersion);
    final match = RegExp(r'^v(\d+)\.(\d+)').firstMatch(tag);
    if (match != null) {
      final major = int.tryParse(match.group(1)!) ?? 0;
      final minor = (int.tryParse(match.group(2)!) ?? 1) + 1;
      return 'v$major.$minor';
    }
    return 'v0.2';
  }

  static int compareVersionTags(String a, String b) {
    List<int> parts(String raw) {
      final clean = extractReleaseVersionTag(raw).replaceFirst('v', '');
      return [
        for (final seg in clean.split('.')) int.tryParse(seg) ?? 0,
      ];
    }

    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static Map<String, dynamic> get _progressiveReleaseSchema => <String, dynamic>{
        'name': 'propose_progressive_godot_release',
        'description':
            'Propose next Godot 4 release presets, baseline Epic [UPGRADE] deltas, and candidate [NEW] 6-section Epics.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': ['presets', 'upgrades', 'newEpics'],
          'properties': <String, dynamic>{
            'presets': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['id', 'label', 'desc', 'upgrades', 'newEpics'],
                'properties': {
                  'id': {'type': 'STRING'},
                  'label': {'type': 'STRING'},
                  'desc': {'type': 'STRING'},
                  'upgrades': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'newEpics': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                },
              },
            },
            'upgrades': {
              'type': 'ARRAY',
              'description':
                  'Additive changelog upgrades mapped onto existing baseline Epics by lineageKey.',
              'items': {
                'type': 'OBJECT',
                'required': ['lineageKey', 'options'],
                'properties': {
                  'lineageKey': {'type': 'STRING'},
                  'options': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'OBJECT',
                      'required': ['id', 'text'],
                      'properties': {
                        'id': {'type': 'STRING'},
                        'text': {
                          'type': 'STRING',
                          'description':
                              LayersTextStyleGuide.changelogDeltaSchemaDesc,
                        },
                        'chosen': {'type': 'BOOLEAN'},
                      },
                    },
                  },
                },
              },
            },
            'newEpics': {
              'type': 'ARRAY',
              'description': 'Candidate NEW 6-section Godot 4 Epics for this release.',
              'items': {
                'type': 'OBJECT',
                'required': [
                  'id',
                  'code',
                  'title',
                  'goal',
                  'links',
                  'outOfScope',
                  'controls',
                  'states',
                  'interrupts',
                  'tuning',
                  'feedback',
                  'levelStaging',
                  'checks',
                ],
                'properties': {
                  'id': {'type': 'STRING'},
                  'code': {'type': 'STRING'},
                  'title': {
                    'type': 'STRING',
                    'description': LayersTextStyleGuide.epicTitleSchemaDesc,
                  },
                  'coreLoopBeat': {
                    'type': 'STRING',
                    'description':
                        'Which §01 Core Loop beat(s) this Epic expands in Playtest.',
                  },
                  'chosen': {'type': 'BOOLEAN'},
                  'goal': {'type': 'STRING'},
                  'links': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.godotSceneLinkSchemaDesc,
                    },
                  },
                  'outOfScope': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.exclusionItemSchemaDesc,
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
                          'description':
                              LayersTextStyleGuide.godotControlRuleSchemaDesc,
                        },
                      },
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
                  'tuning': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'OBJECT',
                      'required': ['key', 'value', 'unit'],
                      'properties': {
                        'key': {
                          'type': 'STRING',
                          'description':
                              LayersTextStyleGuide.godotTuningKeySchemaDesc,
                        },
                        'value': {'type': 'STRING'},
                        'unit': {
                          'type': 'STRING',
                          'description':
                              LayersTextStyleGuide.godotTuningUnitSchemaDesc,
                        },
                      },
                    },
                  },
                  'feedback': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'levelStaging': {
                    'type': 'STRING',
                    'description':
                        LayersTextStyleGuide.godotSceneStagingSchemaDesc,
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
              },
            },
          },
        },
      };

  /// Proposes the next progressive release Co-Pilot draft (presets + baseline `[UPGRADE]` + `[NEW]` Epics).
  static Future<ProgressiveReleaseDraft> proposeNextReleaseCopilot({
    required ProjectConceptBlueprint rootSpec,
    required List<EpicSpec> currentEpics,
    required String targetVersion,
    required String apiKey,
    String directionPrompt = '',
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    // Instant local curated Co-Pilot pack when switching v0.1 -> v0.2 with built-in presets
    if (targetVersion == 'v0.2' &&
        directionPrompt.trim().isEmpty &&
        rootSpec.v02Presets.isNotEmpty &&
        (rootSpec.v02NewPool.isNotEmpty ||
            rootSpec.v02UpgradesByLineageKey.isNotEmpty) &&
        !GeminiAgentClient.hasKey(apiKey)) {
      return _draftFromRootCache(rootSpec, currentEpics, targetVersion);
    }

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _buildOfflineProgressiveDraft(
        rootSpec: rootSpec,
        currentEpics: currentEpics,
        targetVersion: targetVersion,
        directionPrompt: directionPrompt,
      );
    }

    final existingSummary = [
      for (final e in currentEpics)
        {
          'code': e.code,
          'lineageKey': e.lineageKey,
          'title': e.title,
          'goal': e.goal,
          if (e.links.isNotEmpty) 'links': e.links.take(3).toList(),
          if (e.controls.isNotEmpty)
            'controls': e.controls.map((c) => c.action).take(4).toList(),
          if (e.levelStaging.trim().isNotEmpty)
            'levelStaging': e.levelStaging.trim(),
        },
    ];

    final unitHint = rootSpec.dimension == GodotProjectDimension.dim2d
        ? '2D px / px/s'
        : '3D 1 unit = 1 m / m/s';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are planning Godot 4 release `$targetVersion` for project `${rootSpec.normalizedTitle}`.
Target Architecture: ${rootSpec.dimension.architectureContract}
Code Policy: ${rootSpec.dimension.codePolicyContract}
Vision: ${rootSpec.pitch}
${rootSpec.releaseDoneWhen.trim().isNotEmpty ? 'Release Gate (§05): ${rootSpec.releaseDoneWhen.trim()}\n' : ''}Core Loop (§01): ${rootSpec.coreLoop.join(' -> ')}
Camera Contract (§02): ${rootSpec.cameraContract}
Character Scale (§02): ${rootSpec.characterScale}
Input Contract (§02): ${rootSpec.inputContract}
Core Feel (§03): ${rootSpec.selectedCoreFeelOption.label}
Design Pillars (§03): ${rootSpec.pillars.join(' | ')}
Trade-Offs (§03): ${rootSpec.tradeOffs.map((t) => t.formatted).join(' | ')}
Hard Scope Cuts — DO NOT VIOLATE (§04): ${rootSpec.outOfScope.join(' | ')}
${directionPrompt.trim().isNotEmpty ? 'User Direction Request: "${directionPrompt.trim()}"' : ''}

CURRENT BASELINE EPICS:
${jsonEncode(existingSummary)}

Generate:
1. 2 distinct Release Direction Presets (`presets`) matching IDs of upgrades/newEpics.
2. Small additive `[UPGRADE]` delta options for relevant baseline Epics (`lineageKey`).
3. 1-2 complete `[NEW]` 6-section Godot 4 Epics with codes `${EpicSpec.formatCode(currentEpics.length + 1)}` onward using $unitHint and snake_case `@export` vars.
CRITICAL RULES:
- Every `[UPGRADE]` delta and `[NEW]` Epic MUST obey §02 Camera/Scale/InputMap contracts, reinforce §01 Core Loop & §03 Trade-Offs, and NEVER introduce systems banned in §04 Hard Scope Cuts unless explicitly requested in User Direction Request.
- Never recreate existing baseline Epics or add Feature sub-tickets.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
      functionDeclarations: [_progressiveReleaseSchema],
    );

    if (res != null) {
      final rawPresets = res['presets'] as List? ?? const [];
      final presets = <ReleaseDirectionPreset>[
        for (final item in rawPresets)
          if (item is Map)
            () {
              final rawPreset = ReleaseDirectionPreset.fromJson(
                Map<String, dynamic>.from(item),
              );
              final cleanLabel = GodotSpecGuard.sanitizeLine(
                rawPreset.label,
                dimension: rootSpec.dimension,
              );
              return ReleaseDirectionPreset(
                id: rawPreset.id,
                label: cleanLabel.isEmpty ? 'Release Direction' : cleanLabel,
                description: GodotSpecGuard.sanitizeLine(
                  rawPreset.description,
                  dimension: rootSpec.dimension,
                ),
                upgradeIds: rawPreset.upgradeIds,
                newEpicIds: rawPreset.newEpicIds,
              );
            }(),
      ];

      final upgradesByKey = <String, List<EpicUpgradeOption>>{};
      final rawUpgrades = res['upgrades'] as List? ?? const [];
      for (final entry in rawUpgrades) {
        if (entry is! Map) continue;
        final m = Map<String, dynamic>.from(entry);
        final rawKeyOriginal = (m['lineageKey'] ?? '').toString().trim();
        final rawKey = rawKeyOriginal.toLowerCase();
        if (rawKey.isEmpty) continue;
        EpicSpec? matchedEpic = currentEpics
            .where((ep) => ep.lineageKey.trim() == rawKeyOriginal)
            .firstOrNull;
        matchedEpic ??= currentEpics
            .where((ep) => ep.code.trim() == rawKeyOriginal)
            .firstOrNull;
        matchedEpic ??= currentEpics
            .where((ep) => ep.lineageKey.trim().toLowerCase() == rawKey)
            .firstOrNull;
        matchedEpic ??= currentEpics
            .where((ep) => ep.code.trim().toLowerCase() == rawKey)
            .firstOrNull;
        final resolvedKey =
            matchedEpic?.lineageKey.trim().toLowerCase() ?? rawKey;
        final opts = m['options'] as List? ?? const [];
        final parsedOpts = <EpicUpgradeOption>[];
        for (int i = 0; i < opts.length; i++) {
          if (opts[i] is! Map) continue;
          final opt = EpicUpgradeOption.fromJson(
            Map<String, dynamic>.from(opts[i] as Map),
            i,
          );
          final cleanText = GodotSpecGuard.sanitizeLine(
            opt.text,
            dimension: rootSpec.dimension,
          );
          if (cleanText.isNotEmpty) {
            opt.text = cleanText;
          }
          parsedOpts.add(opt);
        }
        upgradesByKey[resolvedKey] = [
          ...?upgradesByKey[resolvedKey],
          ...parsedOpts,
        ];
      }

      final rawNewEpics = res['newEpics'] as List? ?? const [];
      final candidateNew = <EpicSpec>[];
      for (int i = 0; i < rawNewEpics.length; i++) {
        if (rawNewEpics[i] is! Map) continue;
        final parsed = EpicSpec.fromJson(
          Map<String, dynamic>.from(rawNewEpics[i] as Map),
          indexHint: currentEpics.length + i,
        );
        final oneBased = currentEpics.length + i + 1;
        final code = EpicSpec.formatCode(oneBased);
        parsed.code = code;
        parsed.lineageKey = code.toLowerCase();
        parsed.releaseVersion = targetVersion;
        parsed.lifecycle = EpicLifecycle.newEpic;
        if (parsed.coreLoopBeat.trim().isEmpty) {
          parsed.coreLoopBeat = rootSpec.coreLoop.isNotEmpty
              ? 'Beat ${rootSpec.coreLoop.length} · ${rootSpec.coreLoop.last}'
              : 'Loop Escalation';
        }
        parsed.chosenForNextRelease =
            (rawNewEpics[i] as Map)['chosen'] == true || i == 0;
        candidateNew.add(
          GodotSpecGuard.sanitizeEpicSpec(
            parsed,
            dimension: rootSpec.dimension,
            forceReleaseVersion: targetVersion,
          ),
        );
      }

      if (candidateNew.isNotEmpty || upgradesByKey.isNotEmpty) {
        return ProgressiveReleaseDraft(
          targetVersion: targetVersion,
          presets: presets.isNotEmpty
              ? presets
              : _defaultPresets(upgradesByKey, candidateNew),
          upgradesByLineageKey: upgradesByKey,
          candidateNewEpics: candidateNew,
          activePresetId: presets.isNotEmpty ? presets.first.id : null,
        );
      }
    }

    return _buildOfflineProgressiveDraft(
      rootSpec: rootSpec,
      currentEpics: currentEpics,
      targetVersion: targetVersion,
      directionPrompt: directionPrompt,
    );
  }

  static ProgressiveReleaseDraft _draftFromRootCache(
    ProjectConceptBlueprint rootSpec,
    List<EpicSpec> currentEpics,
    String targetVersion,
  ) {
    final upgrades = <String, List<EpicUpgradeOption>>{};
    for (final ep in currentEpics) {
      final cached = rootSpec.v02UpgradesByLineageKey[ep.lineageKey.toLowerCase()];
      if (cached != null && cached.isNotEmpty) {
        upgrades[ep.lineageKey.toLowerCase()] = [
          for (final u in cached) u.copyWith(),
        ];
      }
    }
    final newPool = [
      for (final ep in rootSpec.v02NewPool)
        ep.deepCopy(
          releaseVersionOverride: targetVersion,
          lifecycleOverride: EpicLifecycle.newEpic,
        ),
    ];
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: List<ReleaseDirectionPreset>.from(rootSpec.v02Presets),
      upgradesByLineageKey: upgrades,
      candidateNewEpics: newPool,
      activePresetId: rootSpec.v02Presets.isNotEmpty
          ? rootSpec.v02Presets.first.id
          : null,
    );
  }

  static ProgressiveReleaseDraft _buildOfflineProgressiveDraft({
    required ProjectConceptBlueprint rootSpec,
    required List<EpicSpec> currentEpics,
    required String targetVersion,
    required String directionPrompt,
  }) {
    if (targetVersion == 'v0.2' &&
        rootSpec.v02Presets.isNotEmpty &&
        directionPrompt.trim().isEmpty) {
      return _draftFromRootCache(rootSpec, currentEpics, targetVersion);
    }

    final upgradesByKey = <String, List<EpicUpgradeOption>>{};
    if (currentEpics.isNotEmpty) {
      final firstKey = currentEpics.first.lineageKey.toLowerCase();
      upgradesByKey[firstKey] = [
        EpicUpgradeOption(
          id: 'up_${firstKey}_juice',
          text: '+45ms Hit-Stop impact freeze & camera lag snap',
          chosen: true,
        ),
        EpicUpgradeOption(
          id: 'up_${firstKey}_vfx',
          text: '+Emissive trail burst during primary movement action',
        ),
      ];
    }

    final nextCode = EpicSpec.formatCode(currentEpics.length + 1);
    final focusTitle = directionPrompt.trim().isNotEmpty
        ? LayersTextStyleGuide.formatConciseTaskTitle(directionPrompt.trim())
        : 'Wave Progression & Score Loop';
    final newEpic = EpicSpec(
      id: 'ep_${targetVersion}_1',
      code: nextCode,
      lineageKey: nextCode.toLowerCase(),
      title: focusTitle,
      releaseVersion: targetVersion,
      lifecycle: EpicLifecycle.newEpic,
      coreLoopBeat: rootSpec.coreLoop.isNotEmpty
          ? 'Beat ${rootSpec.coreLoop.length} · ${rootSpec.coreLoop.last}'
          : 'Loop Escalation',
      chosenForNextRelease: true,
      goal:
          'Expand $targetVersion loop continuity with wave escalation, Control HUD counter readout, and instant quick-restart.',
      links: [
        if (currentEpics.isNotEmpty)
          'Instantiates / resets ${currentEpics.last.code} (${currentEpics.last.title}) scenes',
        'Updates Control HUD wave label and remaining enemy counter',
      ],
      outOfScope: const [
        'No main menu save-slot persistence',
      ],
      controls: [
        EpicControlBinding(
          action: 'quick_restart',
          trigger: 'Just Pressed (R)',
          rule: 'Resets round counter and player health cleanly in < 0.2s',
        ),
      ],
      states: const [
        'WaveStart (1.0s) -> ActiveWave -> RoundClear (2.0s) -> NextWave / Victory',
      ],
      interrupts: const [
        'Player defeat cleanly halts wave spawner timers and displays retry prompt',
      ],
      tuning: [
        EpicTuningParam(key: 'round_wave_count', value: '3', unit: 'count'),
        EpicTuningParam(key: 'wave_delay', value: '2.0', unit: 's'),
      ],
      feedback: const [
        'Top-center HUD wave counter flashes bright cyan on wave transition',
      ],
      levelStaging:
          'Reuse active v0.1 prototype scene with 3 SpawnPoint marker nodes',
      checks: [
        EpicPieCheck(
          id: '${nextCode.toLowerCase()}_c1',
          text: 'Clear wave 1 enemies -> HUD updates and wave 2 spawns cleanly after 2.0s',
        ),
      ],
    );

    final candidateList = [
      GodotSpecGuard.sanitizeEpicSpec(
        newEpic,
        dimension: rootSpec.dimension,
        forceReleaseVersion: targetVersion,
      ),
    ];

    final presets = _defaultPresets(upgradesByKey, candidateList);
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: presets,
      upgradesByLineageKey: upgradesByKey,
      candidateNewEpics: candidateList,
      activePresetId: presets.first.id,
    );
  }

  static List<ReleaseDirectionPreset> _defaultPresets(
    Map<String, List<EpicUpgradeOption>> upgradesByKey,
    List<EpicSpec> candidates,
  ) {
    final firstUpIds = <String>[
      for (final list in upgradesByKey.values)
        if (list.isNotEmpty) list.first.id,
    ];
    final firstNewIds = <String>[
      if (candidates.isNotEmpty) candidates.first.id,
    ];
    final allUpIds = <String>[
      for (final list in upgradesByKey.values)
        for (final o in list) o.id,
    ];
    final allNewIds = <String>[for (final c in candidates) c.id];

    return [
      ReleaseDirectionPreset(
        id: 'focused',
        label: 'Focused Feel + Loop',
        description:
            'Apply core game-feel upgrades and add the primary new Epic.',
        upgradeIds: firstUpIds,
        newEpicIds: firstNewIds,
      ),
      ReleaseDirectionPreset(
        id: 'expanded',
        label: 'Full Release Expansion',
        description:
            'Include all proposed upgrades and new Epics for maximum scope.',
        upgradeIds: allUpIds,
        newEpicIds: allNewIds,
      ),
    ];
  }
}

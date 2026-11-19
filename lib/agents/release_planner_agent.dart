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

  static Map<String, dynamic> get _featureSliceSchema => <String, dynamic>{
        'type': 'OBJECT',
        'required': ['title', 'goal', 'tuning', 'checks'],
        'properties': <String, dynamic>{
          'id': {'type': 'STRING'},
          'code': {'type': 'STRING'},
          'title': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.featureTitleSchemaDesc,
          },
          'sliceTime': {'type': 'STRING'},
          'goal': {'type': 'STRING'},
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
                  'description': LayersTextStyleGuide.godotControlRuleSchemaDesc,
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
                  'description': LayersTextStyleGuide.godotTuningKeySchemaDesc,
                },
                'value': {'type': 'STRING'},
                'unit': {
                  'type': 'STRING',
                  'description': LayersTextStyleGuide.godotTuningUnitSchemaDesc,
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

  static Map<String, dynamic> get _progressiveReleaseSchema => <String, dynamic>{
        'name': 'propose_progressive_godot_release',
        'description':
            'Propose next Godot 4 release presets, baseline [UPGRADE] deltas, [NEW] Feature slices inside existing Epics, and candidate [NEW] domain Epics.',
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
                        'targetFeatureCode': {'type': 'STRING'},
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
            'newFeatures': {
              'type': 'ARRAY',
              'description':
                  'Additive [+NEW] 30-90 min Feature slices placed inside existing permanent Epics by lineageKey.',
              'items': {
                'type': 'OBJECT',
                'required': ['lineageKey', 'features'],
                'properties': {
                  'lineageKey': {'type': 'STRING'},
                  'features': {
                    'type': 'ARRAY',
                    'items': _featureSliceSchema,
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
                  'features': {
                    'type': 'ARRAY',
                    'items': _featureSliceSchema,
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
            rootSpec.v02UpgradesByLineageKey.isNotEmpty ||
            rootSpec.v02NewFeaturesByLineageKey.isNotEmpty) &&
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
2. Small additive `[UPGRADE]` delta options for relevant baseline Epics/Features (`lineageKey` + optional `targetFeatureCode`).
3. Additive `[+NEW]` 30-90 min Feature slices in `newFeatures` attached inside existing permanent Epics (`lineageKey`) whenever a mechanic extends an existing domain.
4. 0-2 candidate `[NEW]` large-domain Godot 4 Epics with codes `${EpicSpec.formatCode(currentEpics.length + 1)}` onward (with `sceneOwnership` and child `features`) using $unitHint and snake_case `@export` vars.
CRITICAL RULES:
- Every `[UPGRADE]` delta, `[+NEW]` Feature, and `[NEW]` Epic MUST obey §02 Camera/Scale/InputMap contracts, reinforce §01 Core Loop & §03 Trade-Offs, and NEVER introduce systems banned in §04 Hard Scope Cuts unless explicitly requested in User Direction Request.
- Never duplicate existing baseline Epic cards, and NEVER emit Task/Step micro-checklists.
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
        final resolvedKey = _resolveEpicLineageKey(
          (m['lineageKey'] ?? '').toString().trim(),
          currentEpics,
        );
        if (resolvedKey.isEmpty) continue;
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

      final newFeaturesByKey = <String, List<FeatureSpec>>{};
      final rawNewFeatures = res['newFeatures'] as List? ?? const [];
      int nextFeatureOrdinal = currentEpics.fold<int>(
        1,
        (sum, ep) => sum + ep.features.length,
      );
      for (final entry in rawNewFeatures) {
        if (entry is! Map) continue;
        final m = Map<String, dynamic>.from(entry);
        final resolvedKey = _resolveEpicLineageKey(
          (m['lineageKey'] ?? '').toString().trim(),
          currentEpics,
        );
        if (resolvedKey.isEmpty) continue;
        final rawList = m['features'] as List? ?? const [];
        final parsedList = <FeatureSpec>[];
        for (int i = 0; i < rawList.length; i++) {
          if (rawList[i] is! Map) continue;
          final feat = FeatureSpec.fromJson(
            Map<String, dynamic>.from(rawList[i] as Map),
            indexHint: nextFeatureOrdinal - 1,
          );
          feat.introducedIn = targetVersion;
          if (feat.code.trim().isEmpty) {
            feat.code = FeatureSpec.formatCode(nextFeatureOrdinal);
          }
          nextFeatureOrdinal++;
          parsedList.add(
            GodotSpecGuard.sanitizeFeatureSpec(
              feat,
              dimension: rootSpec.dimension,
            ),
          );
        }
        if (parsedList.isNotEmpty) {
          newFeaturesByKey[resolvedKey] = [
            ...?newFeaturesByKey[resolvedKey],
            ...parsedList,
          ];
        }
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
        for (final feat in parsed.features) {
          feat.introducedIn = targetVersion;
        }
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

      if (candidateNew.isNotEmpty ||
          upgradesByKey.isNotEmpty ||
          newFeaturesByKey.isNotEmpty) {
        return ProgressiveReleaseDraft(
          targetVersion: targetVersion,
          presets: presets.isNotEmpty
              ? presets
              : _defaultPresets(upgradesByKey, candidateNew),
          upgradesByLineageKey: upgradesByKey,
          candidateNewFeaturesByLineageKey: newFeaturesByKey,
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

  static String _resolveEpicLineageKey(
    String rawKeyOriginal,
    List<EpicSpec> currentEpics,
  ) {
    final rawKey = rawKeyOriginal.toLowerCase();
    if (rawKey.isEmpty) return '';
    EpicSpec? matched = currentEpics
        .where((ep) => ep.lineageKey.trim() == rawKeyOriginal)
        .firstOrNull;
    matched ??=
        currentEpics.where((ep) => ep.code.trim() == rawKeyOriginal).firstOrNull;
    matched ??= currentEpics
        .where((ep) => ep.lineageKey.trim().toLowerCase() == rawKey)
        .firstOrNull;
    matched ??= currentEpics
        .where((ep) => ep.code.trim().toLowerCase() == rawKey)
        .firstOrNull;
    return matched?.lineageKey.trim().toLowerCase() ?? rawKey;
  }

  static ProgressiveReleaseDraft _draftFromRootCache(
    ProjectConceptBlueprint rootSpec,
    List<EpicSpec> currentEpics,
    String targetVersion,
  ) {
    final upgrades = <String, List<EpicUpgradeOption>>{};
    final newFeatures = <String, List<FeatureSpec>>{};
    for (final ep in currentEpics) {
      final key = ep.lineageKey.toLowerCase();
      final cached = rootSpec.v02UpgradesByLineageKey[key];
      if (cached != null && cached.isNotEmpty) {
        upgrades[key] = [for (final u in cached) u.copyWith()];
      }
      final cachedNewFeats = rootSpec.v02NewFeaturesByLineageKey[key];
      if (cachedNewFeats != null && cachedNewFeats.isNotEmpty) {
        newFeatures[key] = [
          for (final f in cachedNewFeats)
            f.deepCopy()..introducedIn = targetVersion,
        ];
      }
    }
    final newPool = [
      for (final ep in rootSpec.v02NewPool)
        () {
          final copy = ep.deepCopy(
            releaseVersionOverride: targetVersion,
            lifecycleOverride: EpicLifecycle.newEpic,
          );
          for (final feat in copy.features) {
            feat.introducedIn = targetVersion;
          }
          return copy;
        }(),
    ];
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: List<ReleaseDirectionPreset>.from(rootSpec.v02Presets),
      upgradesByLineageKey: upgrades,
      candidateNewFeaturesByLineageKey: newFeatures,
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
    final newFeaturesByKey = <String, List<FeatureSpec>>{};
    final is2d = rootSpec.dimension == GodotProjectDimension.dim2d;
    final distUnit = rootSpec.dimension.distanceUnit;
    final speedUnit = rootSpec.dimension.speedUnit;

    if (currentEpics.isNotEmpty) {
      final firstEpic = currentEpics.first;
      final firstKey = firstEpic.lineageKey.toLowerCase();
      final firstFeatCode = firstEpic.features.isNotEmpty
          ? firstEpic.features.last.code
          : 'F01';
      upgradesByKey[firstKey] = [
        EpicUpgradeOption(
          id: 'up_${firstKey}_juice',
          targetFeatureCode: firstFeatCode,
          text: '+45ms Hit-Stop impact freeze & camera lag snap',
          chosen: true,
        ),
        EpicUpgradeOption(
          id: 'up_${firstKey}_vfx',
          targetFeatureCode: firstFeatCode,
          text: '+Emissive trail burst during primary movement action',
        ),
      ];
      newFeaturesByKey[firstKey] = [
        GodotSpecGuard.sanitizeFeatureSpec(
          FeatureSpec(
            id: '${firstKey}_${targetVersion}_chain',
            code: FeatureSpec.formatCode(
              currentEpics.fold<int>(1, (sum, ep) => sum + ep.features.length),
            ),
            title: 'Counter Impulse & Quick Recover',
            introducedIn: targetVersion,
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal:
                'Grant a brief $targetVersion follow-up dash refund inside ${firstEpic.code} when landing clean counters.',
            tuning: [
              EpicTuningParam(key: 'chain_window_s', value: '0.35', unit: 's'),
              EpicTuningParam(
                key: 'counter_burst_speed',
                value: is2d ? '380' : '9.5',
                unit: speedUnit,
              ),
              EpicTuningParam(
                key: 'shockwave_radius',
                value: is2d ? '96' : '2.4',
                unit: distUnit,
              ),
            ],
            checks: [
              EpicPieCheck(
                id: 'off_feat_c1',
                text: 'Trigger counter -> Follow-up movement bursts cleanly with 0 cooldown wait',
              ),
            ],
          ),
          dimension: rootSpec.dimension,
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
      inScope: const [
        '3-wave perimeter spawn director',
        'Top-center HUD wave counter & R quick reset',
      ],
      doneWhen: const [
        'Clear wave 1 enemies -> HUD updates and wave 2 spawns cleanly after 2.0 s',
      ],
      sceneOwnership: [
        EpicSceneOwnership(
          path: 'res://scripts/wave_director.gd',
          role: 'SpawnWave timer, counter HUD signal & R quick reset',
        ),
      ],
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
      features: [
        FeatureSpec(
          id: 'ep_${targetVersion}_f01',
          code: 'F01',
          title: 'Multi-Wave Spawner & Counter',
          introducedIn: targetVersion,
          sliceTime: '45 min',
          status: FeatureStatus.queued,
          goal: 'Spawn 3 timed enemy waves and update top-center Control HUD banner.',
          tuning: [
            EpicTuningParam(key: 'round_wave_count', value: '3', unit: 'count'),
            EpicTuningParam(key: 'wave_delay', value: '2.0', unit: 's'),
          ],
          checks: [
            EpicPieCheck(
              id: 'ep_${targetVersion}_f01_c1',
              text: 'Defeat Wave 1 -> Banner updates and Wave 2 spawns after 2.0 s',
            ),
          ],
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
      candidateNewFeaturesByLineageKey: newFeaturesByKey,
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

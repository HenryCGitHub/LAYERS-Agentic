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
          'required': ['presets', 'upgrades', 'newFeatures', 'newEpics'],
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
                  'newFeatures': {
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
              'description':
                  'Candidate NEW 4-tier Godot 4 Domain Epics (architecture + child playable Feature slices) for this release.',
              'items': {
                'type': 'OBJECT',
                'required': [
                  'id',
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
                  'inScope': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'doneWhen': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.causalPlaytestCheckSchemaDesc,
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
                  'states': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'interrupts': {
                    'type': 'ARRAY',
                    'items': {'type': 'STRING'},
                  },
                  'outOfScope': {
                    'type': 'ARRAY',
                    'items': {
                      'type': 'STRING',
                      'description':
                          LayersTextStyleGuide.exclusionItemSchemaDesc,
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

  static bool _hasRootV02Cache(ProjectConceptBlueprint rootSpec) {
    return rootSpec.v02NewPool.isNotEmpty ||
        rootSpec.v02UpgradesByLineageKey.isNotEmpty ||
        rootSpec.v02NewFeaturesByLineageKey.isNotEmpty;
  }

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
    // Instant local curated Co-Pilot pack when switching v0.1 -> v0.2 with cached v0.2 data
    if (targetVersion == 'v0.2' &&
        directionPrompt.trim().isEmpty &&
        _hasRootV02Cache(rootSpec) &&
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
          if (e.inScope.isNotEmpty) 'inScope': e.inScope.take(4).toList(),
          if (e.sceneOwnership.isNotEmpty)
            'sceneOwnership': [
              for (final s in e.sceneOwnership.take(4))
                {'path': s.path, 'role': s.role},
            ],
          if (e.features.isNotEmpty)
            'features': [
              for (final f in e.features)
                {
                  'code': f.code,
                  'title': f.title,
                  'introducedIn': f.introducedIn,
                },
            ],
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
      final featureCodes = _FeatureCodeAllocator(currentEpics);

      final verSlug = targetVersion.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
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
          var feat = FeatureSpec.fromJson(
            Map<String, dynamic>.from(rawList[i] as Map),
            indexHint: featureCodes.nextOrdinal - 1,
            idPrefixHint: '${resolvedKey}_$verSlug',
          );
          feat.introducedIn = targetVersion;
          feat.code = featureCodes.allocate(feat.code);
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

      final usedLineageKeys = <String>{
        for (final ep in currentEpics)
          if (ep.lineageKey.trim().isNotEmpty) ep.lineageKey.trim().toLowerCase(),
      };
      int nextLineageOrd = currentEpics.length + 1;
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
        while (usedLineageKeys.contains(EpicSpec.formatLineageKey(nextLineageOrd))) {
          nextLineageOrd++;
        }
        parsed.lineageKey = EpicSpec.formatLineageKey(nextLineageOrd);
        usedLineageKeys.add(parsed.lineageKey);
        parsed.releaseVersion = targetVersion;
        parsed.lifecycle = EpicLifecycle.newEpic;
        if (parsed.coreLoopBeat.trim().isEmpty) {
          parsed.coreLoopBeat = rootSpec.coreLoop.isNotEmpty
              ? 'Beat ${rootSpec.coreLoop.length} · ${rootSpec.coreLoop.last}'
              : 'Loop Escalation';
        }
        if (parsed.inScope.isEmpty && parsed.goal.trim().isNotEmpty) {
          parsed.inScope = [parsed.goal.trim()];
        }
        if (parsed.doneWhen.isEmpty) {
          parsed.doneWhen = [
            'Run F6 -> ${parsed.title} operates cleanly with 0 Debugger errors',
          ];
        }
        if (parsed.sceneOwnership.isEmpty) {
          final slug = parsed.title
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
              .replaceAll(RegExp(r'^_+|_+$'), '');
          final safeSlug =
              slug.isEmpty ? 'epic_${parsed.code.toLowerCase()}' : slug;
          parsed.sceneOwnership = [
            EpicSceneOwnership(
              path: 'res://scripts/$safeSlug.gd',
              role: parsed.title,
            ),
          ];
        }
        if (parsed.features.isEmpty) {
          parsed.features = [
            FeatureSpec(
              id: '${parsed.id}_f01',
              code: featureCodes.allocate(),
              title: parsed.title,
              introducedIn: targetVersion,
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: parsed.goal.trim().isNotEmpty
                  ? parsed.goal.trim()
                  : parsed.title,
              inScope: List<String>.from(parsed.inScope),
              doneWhen: List<String>.from(parsed.doneWhen),
              checks: [
                EpicPieCheck(
                  id: '${parsed.id}_f01_c1',
                  text: parsed.doneWhen.first,
                ),
              ],
            ),
          ];
        } else {
          for (final feat in parsed.features) {
            feat.introducedIn = targetVersion;
            feat.code = featureCodes.allocate(feat.code);
          }
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
              : _defaultPresets(upgradesByKey, newFeaturesByKey, candidateNew),
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
    final cleanOrig = rawKeyOriginal.trim();
    final rawKey = cleanOrig.toLowerCase();
    if (rawKey.isEmpty) return '';
    EpicSpec? matched = currentEpics
        .where((ep) => ep.lineageKey.trim().toLowerCase() == rawKey)
        .firstOrNull;
    matched ??= currentEpics
        .where((ep) => ep.code.trim().toLowerCase() == rawKey)
        .firstOrNull;
    matched ??= currentEpics
        .where((ep) => ep.id.trim().toLowerCase() == rawKey)
        .firstOrNull;
    matched ??= currentEpics
        .where((ep) => ep.title.trim().toLowerCase() == rawKey)
        .firstOrNull;
    return matched != null ? matched.lineageKey.trim().toLowerCase() : '';
  }

  static ProgressiveReleaseDraft _draftFromRootCache(
    ProjectConceptBlueprint rootSpec,
    List<EpicSpec> currentEpics,
    String targetVersion,
  ) {
    final upgrades = <String, List<EpicUpgradeOption>>{};
    final newFeatures = <String, List<FeatureSpec>>{};
    final featureCodes = _FeatureCodeAllocator(currentEpics);

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
            () {
              final copy = f.deepCopy()..introducedIn = targetVersion;
              copy.code = featureCodes.allocate(copy.code);
              return copy;
            }(),
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
            feat.code = featureCodes.allocate(feat.code);
          }
          return copy;
        }(),
    ];
    final effectivePresets = rootSpec.v02Presets.isNotEmpty
        ? List<ReleaseDirectionPreset>.from(rootSpec.v02Presets)
        : _defaultPresets(upgrades, newFeatures, newPool);
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: effectivePresets,
      upgradesByLineageKey: upgrades,
      candidateNewFeaturesByLineageKey: newFeatures,
      candidateNewEpics: newPool,
      activePresetId:
          effectivePresets.isNotEmpty ? effectivePresets.first.id : null,
    );
  }

  static ProgressiveReleaseDraft _buildOfflineProgressiveDraft({
    required ProjectConceptBlueprint rootSpec,
    required List<EpicSpec> currentEpics,
    required String targetVersion,
    required String directionPrompt,
  }) {
    if (targetVersion == 'v0.2' &&
        directionPrompt.trim().isEmpty &&
        _hasRootV02Cache(rootSpec)) {
      return _draftFromRootCache(rootSpec, currentEpics, targetVersion);
    }

    final upgradesByKey = <String, List<EpicUpgradeOption>>{};
    final newFeaturesByKey = <String, List<FeatureSpec>>{};
    final is2d = rootSpec.dimension == GodotProjectDimension.dim2d;
    final distUnit = rootSpec.dimension.distanceUnit;
    final speedUnit = rootSpec.dimension.speedUnit;
    final featureCodes = _FeatureCodeAllocator(currentEpics);

    if (currentEpics.isNotEmpty) {
      final firstEpic = currentEpics.first;
      final firstKey = firstEpic.lineageKey.toLowerCase();
      final firstFeatCode = firstEpic.features.isNotEmpty
          ? firstEpic.features.last.code
          : 'F01';
      final newFeatCode = featureCodes.allocate();
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
            code: newFeatCode,
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
                text:
                    'Trigger counter -> Follow-up movement bursts cleanly with 0 cooldown wait',
              ),
            ],
          ),
          dimension: rootSpec.dimension,
        ),
      ];
    }

    final usedLineageKeys = <String>{
      for (final ep in currentEpics)
        if (ep.lineageKey.trim().isNotEmpty) ep.lineageKey.trim().toLowerCase(),
    };
    int nextLineageOrd = currentEpics.length + 1;
    while (usedLineageKeys.contains(EpicSpec.formatLineageKey(nextLineageOrd))) {
      nextLineageOrd++;
    }
    final nextCode = EpicSpec.formatCode(currentEpics.length + 1);
    final nextLineageKey = EpicSpec.formatLineageKey(nextLineageOrd);
    final focusTitle = directionPrompt.trim().isNotEmpty
        ? LayersTextStyleGuide.formatConciseTaskTitle(directionPrompt.trim())
        : 'Round & Score Escalation';
    final newEpicFeatCode = featureCodes.allocate();
    final newEpic = EpicSpec(
      id: 'ep_${targetVersion}_1',
      code: nextCode,
      lineageKey: nextLineageKey,
      title: focusTitle,
      releaseVersion: targetVersion,
      lifecycle: EpicLifecycle.newEpic,
      coreLoopBeat: rootSpec.coreLoop.isNotEmpty
          ? 'Beat ${rootSpec.coreLoop.length} · ${rootSpec.coreLoop.last}'
          : 'Loop Escalation',
      chosenForNextRelease: true,
      goal:
          'Expand $targetVersion loop continuity with round pacing, Control HUD counter readout, and instant quick-restart.',
      inScope: const [
        '3-stage round progression timer',
        'Top-center HUD round counter & R quick reset',
      ],
      doneWhen: const [
        'Complete Stage 1 objective -> HUD counter updates and Stage 2 starts after 2.0 s',
      ],
      sceneOwnership: [
        EpicSceneOwnership(
          path: 'res://scripts/round_director.gd',
          role: 'Stage timer progression, HUD signal & R quick reset',
        ),
      ],
      outOfScope: const [
        'No main menu save-slot persistence',
      ],
      states: const [
        'RoundStart (1.0s) -> ActiveRound -> StageClear (2.0s) -> NextStage / Victory',
      ],
      interrupts: const [
        'Run reset cleanly halts stage timers and restores initial actors in < 0.2 s',
      ],
      features: [
        FeatureSpec(
          id: 'ep_${targetVersion}_f01',
          code: newEpicFeatCode,
          title: 'Multi-Stage Pacer & HUD Counter',
          introducedIn: targetVersion,
          sliceTime: '45 min',
          status: FeatureStatus.queued,
          goal:
              'Advance 3 timed gameplay stages and update top-center Control HUD banner.',
          tuning: [
            EpicTuningParam(key: 'round_stage_count', value: '3', unit: 'count'),
            EpicTuningParam(key: 'stage_delay', value: '2.0', unit: 's'),
          ],
          checks: [
            EpicPieCheck(
              id: 'ep_${targetVersion}_f01_c1',
              text:
                  'Complete Stage 1 objective -> HUD updates and Stage 2 starts after 2.0 s',
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

    final presets = _defaultPresets(upgradesByKey, newFeaturesByKey, candidateList);
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
    Map<String, List<FeatureSpec>> newFeaturesByKey,
    List<EpicSpec> candidates,
  ) {
    final firstUpIds = <String>[
      for (final list in upgradesByKey.values)
        if (list.isNotEmpty) list.first.id,
      for (final list in newFeaturesByKey.values)
        if (list.isNotEmpty) list.first.id,
    ];
    final firstNewIds = <String>[
      if (candidates.isNotEmpty) candidates.first.id,
    ];
    final allUpIds = <String>[
      for (final list in upgradesByKey.values)
        for (final o in list) o.id,
      for (final list in newFeaturesByKey.values)
        for (final f in list) f.id,
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

/// Tracks allocated `F##` codes across baseline Epics and assigns non-colliding sequential codes.
class _FeatureCodeAllocator {
  static final RegExp _codeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
  final Set<String> _usedLower = <String>{};
  int _nextOrdinal = 1;

  int get nextOrdinal => _nextOrdinal;

  _FeatureCodeAllocator(List<EpicSpec> currentEpics) {
    for (final ep in currentEpics) {
      for (final f in ep.features) {
        final clean = f.code.trim();
        if (clean.isNotEmpty) {
          _usedLower.add(clean.toLowerCase());
        }
        final m = _codeRx.firstMatch(clean);
        final numVal = int.tryParse(m?.group(1) ?? '') ?? 0;
        if (numVal >= _nextOrdinal) _nextOrdinal = numVal + 1;
      }
    }
  }

  String allocate([String preferred = '']) {
    final cleanPref = preferred.trim();
    final prefLower = cleanPref.toLowerCase();
    if (cleanPref.isNotEmpty && !_usedLower.contains(prefLower)) {
      _usedLower.add(prefLower);
      final m = _codeRx.firstMatch(cleanPref);
      if (m != null) {
        final numVal = int.tryParse(m.group(1) ?? '') ?? 0;
        if (numVal >= _nextOrdinal) _nextOrdinal = numVal + 1;
      }
      return cleanPref;
    }
    while (_usedLower
        .contains(FeatureSpec.formatCode(_nextOrdinal).toLowerCase())) {
      _nextOrdinal++;
    }
    final allocated = FeatureSpec.formatCode(_nextOrdinal);
    _usedLower.add(allocated.toLowerCase());
    _nextOrdinal++;
    return allocated;
  }
}

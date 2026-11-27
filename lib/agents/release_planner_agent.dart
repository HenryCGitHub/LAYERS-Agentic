import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/unreal_spec_guard.dart';
import 'gemini_agent_client.dart';
import 'release_planner_fallback.dart';

/// Stage 2 Unreal Engine 5 Progressive Release Planner Agent (`v0.1 -> v0.2 -> v0.3+`).
/// Generates Co-Pilot release direction presets, `[UPGRADE]` delta checkboxes per baseline Epic,
/// and candidate `[NEW]` Domain Epics without ever duplicating cards.
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

  static Map<String, dynamic> get _progressiveReleaseSchema => <String, dynamic>{
        'name': 'propose_progressive_unreal_release',
        'description':
            'Propose next Unreal Engine 5 release presets, baseline [UPGRADE] deltas, [NEW] Features inside existing Epics, and candidate [NEW] domain Epics.',
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
                  'Additive [+NEW] 30-90 min Features placed inside existing permanent Epics by lineageKey.',
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
                  'Candidate NEW 4-tier Unreal Engine 5 Domain Epics (architecture + child playable Features) for this release.',
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

  /// Proposes the next progressive release Co-Pilot draft (presets + baseline `[UPGRADE]` + `[NEW]` Epics).
  static Future<ProgressiveReleaseDraft> proposeNextReleaseCopilot({
    required ProjectConceptBlueprint rootSpec,
    required List<EpicSpec> currentEpics,
    required String targetVersion,
    required String apiKey,
    String directionPrompt = '',
    String preferredModel = GeminiAgentClient.pinnedArchitectModel,
    String thinkingLevel = GeminiAgentClient.defaultArchitectThinkingLevel,
  }) async {
    // Instant local curated Co-Pilot pack when switching v0.1 -> v0.2 with cached v0.2 data
    if (targetVersion == 'v0.2' &&
        directionPrompt.trim().isEmpty &&
        hasRootV02Cache(rootSpec) &&
        !GeminiAgentClient.hasKey(apiKey)) {
      return draftFromRootCache(rootSpec, currentEpics, targetVersion);
    }

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return buildOfflineProgressiveDraft(
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

    final archMode = rootSpec.architectureMode;
    final tuningStyleLabel = archMode == UnrealArchitectureMode.cppHybrid
        ? 'PascalCase UPROPERTY(EditAnywhere) vars'
        : 'PascalCase Exposed BP vars';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are planning Unreal Engine 5 release `$targetVersion` for project `${rootSpec.normalizedTitle}`.
Target Architecture: ${archMode.fullLabel} (${archMode.architectureContract})
Code Policy: ${archMode.codePolicyContract}
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
3. Additive `[+NEW]` 30-90 min Features in `newFeatures` attached inside existing permanent Epics (`lineageKey`) whenever a mechanic extends an existing domain.
4. 0-2 candidate `[NEW]` large-domain Unreal Engine 5 Epics with codes `${EpicSpec.formatCode(currentEpics.length + 1)}` onward (with `sceneOwnership` and child `features`) using `cm` / `cm/s` units, Enhanced Input `IA_*` actions, and $tuningStyleLabel.
CRITICAL RULES:
- Every `[UPGRADE]` delta, `[+NEW]` Feature, and `[NEW]` Epic MUST obey §02 Camera/Scale/Enhanced Input contracts, reinforce §01 Core Loop & §03 Trade-Offs, and NEVER introduce systems banned in §04 Hard Scope Cuts unless explicitly requested in User Direction Request.
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
              final cleanLabel = UnrealSpecGuard.sanitizeLine(
                rawPreset.label,
                mode: archMode,
              );
              return ReleaseDirectionPreset(
                id: rawPreset.id,
                label: cleanLabel.isEmpty ? 'Release Direction' : cleanLabel,
                description: UnrealSpecGuard.sanitizeLine(
                  rawPreset.description,
                  mode: archMode,
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
        final resolvedKey = resolveEpicLineageKey(
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
          final cleanText = UnrealSpecGuard.sanitizeLine(
            opt.text,
            mode: archMode,
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
      final featureCodes = FeatureCodeAllocator(currentEpics);

      final verSlug = targetVersion.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
      for (final entry in rawNewFeatures) {
        if (entry is! Map) continue;
        final m = Map<String, dynamic>.from(entry);
        final resolvedKey = resolveEpicLineageKey(
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
            UnrealSpecGuard.sanitizeFeatureSpec(
              feat,
              mode: archMode,
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
            'Run PIE -> ${parsed.title} operates cleanly with 0 Message Log errors',
          ];
        }
        if (parsed.sceneOwnership.isEmpty) {
          final pascalStem = UnrealSpecGuard.toPascalCaseToken(
            parsed.title.isEmpty ? 'Epic${parsed.code}' : parsed.title,
          );
          final ownerPath = archMode == UnrealArchitectureMode.cppHybrid
              ? 'Source/$pascalStem.cpp'
              : '/Game/Blueprints/BP_$pascalStem';
          parsed.sceneOwnership = [
            EpicSceneOwnership(
              path: ownerPath,
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
          UnrealSpecGuard.sanitizeEpicSpec(
            parsed,
            mode: archMode,
            forceReleaseVersion: targetVersion,
          ),
        );
      }

      if (candidateNew.isNotEmpty ||
          upgradesByKey.isNotEmpty ||
          newFeaturesByKey.isNotEmpty) {
        final effectivePresets = presets.isNotEmpty
            ? presets
            : defaultProgressivePresets(upgradesByKey, newFeaturesByKey, candidateNew);
        return ProgressiveReleaseDraft(
          targetVersion: targetVersion,
          presets: effectivePresets,
          upgradesByLineageKey: upgradesByKey,
          candidateNewFeaturesByLineageKey: newFeaturesByKey,
          candidateNewEpics: candidateNew,
          activePresetId:
              effectivePresets.isNotEmpty ? effectivePresets.first.id : null,
        );
      }
    }

    return buildOfflineProgressiveDraft(
      rootSpec: rootSpec,
      currentEpics: currentEpics,
      targetVersion: targetVersion,
      directionPrompt: directionPrompt,
    );
  }

}

import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/godot_spec_guard.dart';
import 'gemini_agent_client.dart';

/// Stage 1 Godot 4 Co-Designer Agent (`1. Project Spec` -> `PROJECT_SPEC.md`).
/// Generates the high-level Godot 4 foundation (`§01–§04`) and strictly `v0.1` Epics (`§05`),
/// and applies natural-language Co-Designer revisions via scoped JSON patches.
class ProjectConceptAgent {
  static Map<String, dynamic> get _rootSpecToolSchema => <String, dynamic>{
        'name': 'commit_godot_root_spec',
        'description':
            'Create the Godot 4 Project Spec (PROJECT_SPEC.md -> ROOT_GODOT_CONTEXT) with §01-§04 foundation contracts and strictly v0.1 prototype Epics in §05 using the 4-tier Epic -> Feature hierarchy.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': [
            'gameTitle',
            'dimension',
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
            'dimension': {
              'type': 'STRING',
              'enum': ['dim3d', 'dim2d'],
              'description': 'Godot 4 spatial mode: dim3d (1 unit = 1 m) or dim2d (px).',
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
                'topdown2d',
                'sidescroller2d',
                'fixedarena2d',
              ],
            },
            'cameraContract': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.godotContractSchemaDesc,
            },
            'characterScale': {
              'type': 'STRING',
              'description':
                  'Player CharacterBody3D size/speed in m & m/s (for 3D), or CharacterBody2D size/speed in px & px/s (for 2D).',
            },
            'inputContract': {
              'type': 'STRING',
              'description':
                  'Godot project.godot InputMap snake_case actions (e.g. move_left/right/up/down, dodge, primary_action).',
            },
            'assetPolicy': {
              'type': 'STRING',
              'description':
                  'Greybox prototype policy (CSGBox3D/MeshInstance3D or ColorRect/Polygon2D) + snake_case @export vars / Resource (.tres).',
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
              'items': _epicJsonSchema,
            },
            'coDesignNote': {
              'type': 'STRING',
              'description': 'Short 1-line summary of the spec changes applied.',
            },
          },
        },
      };

  static Map<String, dynamic> get _featureJsonSchema => <String, dynamic>{
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
            'description': '1 plain sentence stating what this playable slice delivers.',
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

  static Map<String, dynamic> get _epicJsonSchema => <String, dynamic>{
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
                'Which §01 Core Loop beat(s) this Epic domain proves in Playtest (e.g. "Beat 1: Move & Aim").',
          },
          'goal': {
            'type': 'STRING',
            'description': '1 plain sentence describing the large-domain Epic architecture.',
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
                '2-3 sittable 30-90 min playable v0.1 Feature slices inside this domain Epic (zero Tasks, zero Steps). Include controls, @export tuning, cues, and Playtest Gate checks here only.',
            'items': _featureJsonSchema,
          },
        },
      };

  static Map<String, dynamic> get _patchRootSpecToolSchema => <String, dynamic>{
        'name': 'patch_godot_root_spec',
        'description':
            'Apply a scoped partial patch to only the Stage 1 Project Spec sections (§01-§05) affected by the user instruction, leaving untouched sections and Epics intact.',
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
            'dimension': {
              'type': 'STRING',
              'enum': ['dim3d', 'dim2d'],
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
                'topdown2d',
                'sidescroller2d',
                'fixedarena2d',
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
              'items': _epicJsonSchema,
            },
            'removeEpicLineageKeys': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'initialEpics': {
              'type': 'ARRAY',
              'description':
                  'Only include full initialEpics array when restructuring the entire §05 prototype queue.',
              'items': _epicJsonSchema,
            },
          },
        },
      };

  static String _fmtScaleNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.01) {
      return v.round().toString();
    }
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static void _convertTuningListDimension(
    List<EpicTuningParam> tuning,
    GodotProjectDimension prevDim,
    GodotProjectDimension targetDim,
  ) {
    const pxPerMeter = 40.0;
    final is2d = targetDim == GodotProjectDimension.dim2d;
    for (final param in tuning) {
      final rawUnit = param.unit.trim().toLowerCase();
      final parsed = double.tryParse(param.value.trim());
      if (prevDim == GodotProjectDimension.dim3d && is2d) {
        if (rawUnit == 'm') {
          if (parsed != null) param.value = _fmtScaleNum(parsed * pxPerMeter);
          param.unit = 'px';
        } else if (rawUnit == 'm/s') {
          if (parsed != null) param.value = _fmtScaleNum(parsed * pxPerMeter);
          param.unit = 'px/s';
        }
      } else if (prevDim == GodotProjectDimension.dim2d && !is2d) {
        if (rawUnit == 'px') {
          if (parsed != null) param.value = _fmtScaleNum(parsed / pxPerMeter);
          param.unit = 'm';
        } else if (rawUnit == 'px/s') {
          if (parsed != null) param.value = _fmtScaleNum(parsed / pxPerMeter);
          param.unit = 'm/s';
        }
      }
    }
  }

  /// Converts an active [ProjectConceptBlueprint] between Godot 4 `3D` (`m`, `m/s`)
  /// and `2D` (`px`, `px/s`), updating §02 camera/scale contracts, Epics, and Features cleanly.
  static ProjectConceptBlueprint convertBlueprintDimension(
    ProjectConceptBlueprint current,
    GodotProjectDimension targetDim,
  ) {
    final next = current.deepCopy();
    if (next.dimension == targetDim) return next;
    final prevDim = next.dimension;
    next.dimension = targetDim;

    final is2d = targetDim == GodotProjectDimension.dim2d;
    next.cameraDecisionOptions = is2d
        ? List<ConceptSectionOption>.from(
            ProjectConceptBlueprint.defaultCamera2dOptions,
          )
        : List<ConceptSectionOption>.from(
            ProjectConceptBlueprint.defaultCamera3dOptions,
          );
    next.cameraChoiceId = is2d ? 'topdown2d' : 'isometric';
    next.cameraContract = next.cameraDecisionOptions.first.contractValue;

    if (is2d) {
      next.characterScale =
          'CharacterBody2D CollisionShape 32x48 px · move_speed 260 px/s';
      next.assetPolicy =
          'ColorRect / Polygon2D Greybox Prototypes + Solid Tint Materials; @export vars & Resource (.tres)';
    } else {
      next.characterScale =
          'CharacterBody3D CapsuleRadius 0.42 m · Height 1.84 m · move_speed 6.2 m/s';
      next.assetPolicy =
          'CSGBox3D / PrimitiveMesh Greybox + StandardMaterial3D Tints; @export vars & Resource (.tres)';
    }

    for (final ep in [...next.initialEpics, ...next.v02NewPool]) {
      _convertTuningListDimension(ep.tuning, prevDim, targetDim);
      for (final feat in ep.features) {
        _convertTuningListDimension(feat.tuning, prevDim, targetDim);
      }
    }
    for (final list in next.v02NewFeaturesByLineageKey.values) {
      for (final feat in list) {
        _convertTuningListDimension(feat.tuning, prevDim, targetDim);
      }
    }

    syncEpicCameraFraming(
      next,
      optionId: next.cameraChoiceId,
      contractValue: next.cameraContract,
    );
    syncEpicCoreFeel(next, feelId: next.feelChoiceId);
    return GodotSpecGuard.sanitizeConceptBlueprint(next);
  }

  /// Keeps `E01..EN` and `F01..FM` strictly sequential across `initialEpics` without gaps or duplicate codes.
  static void normalizeSequentialEpicAndFeatureCodes(
    ProjectConceptBlueprint bp,
  ) {
    final usedLineageKeys = <String>{};
    final usedFeatIds = <String>{};
    int nextFeatNum = 1;
    int lineageOrd = 1;
    for (int i = 0; i < bp.initialEpics.length; i++) {
      final ep = bp.initialEpics[i];
      ep.code = EpicSpec.formatCode(i + 1);
      var lk = ep.lineageKey.trim().toLowerCase();
      if (lk.isEmpty || usedLineageKeys.contains(lk)) {
        while (usedLineageKeys.contains(EpicSpec.formatLineageKey(lineageOrd))) {
          lineageOrd++;
        }
        lk = EpicSpec.formatLineageKey(lineageOrd);
      }
      ep.lineageKey = lk;
      usedLineageKeys.add(lk);
      ep.releaseVersion = 'v0.1';
      if (i == 0 && ep.lifecycle == EpicLifecycle.queued) {
        ep.lifecycle = EpicLifecycle.active;
      }
      bool activatedFirstOpen = false;
      for (int fIdx = 0; fIdx < ep.features.length; fIdx++) {
        var feat = ep.features[fIdx];
        final rawFeatId = feat.id.trim();
        if (rawFeatId.isEmpty ||
            FeatureSpec.isPositionalFallbackFeatureId(rawFeatId) ||
            usedFeatIds.contains(rawFeatId)) {
          var nextId = '${ep.id}_f${nextFeatNum.toString().padLeft(2, '0')}';
          var suffix = 2;
          while (usedFeatIds.contains(nextId)) {
            nextId = '${ep.id}_f${nextFeatNum.toString().padLeft(2, '0')}_$suffix';
            suffix++;
          }
          feat = feat.deepCopy(idOverride: nextId);
          ep.features[fIdx] = feat;
        }
        usedFeatIds.add(feat.id);
        feat.code = FeatureSpec.formatCode(nextFeatNum);
        feat.introducedIn = 'v0.1';
        if (i == 0 && !activatedFirstOpen && !feat.isPassed) {
          if (feat.status == FeatureStatus.queued) {
            feat.status = FeatureStatus.active;
          }
          activatedFirstOpen = true;
        }
        nextFeatNum++;
      }
    }
  }

  /// Resolves the locomotion/camera Epic by `lineageKey` or domain keywords even after queue reordering.
  static EpicSpec _findLocomotionEpic(ProjectConceptBlueprint draft) {
    for (final ep in draft.initialEpics) {
      if (ep.lineageKey.trim().toLowerCase() == 'e01') {
        return ep;
      }
    }
    for (final ep in draft.initialEpics) {
      final text =
          '${ep.title} ${ep.goal} ${ep.sceneOwnership.map((s) => s.path).join(' ')}'
              .toLowerCase();
      if (text.contains('movement') ||
          text.contains('locomotion') ||
          text.contains('camera') ||
          text.contains('handling') ||
          text.contains('player') ||
          text.contains('skiff')) {
        return ep;
      }
    }
    return draft.initialEpics.first;
  }

  static Future<ProjectConceptBlueprint> draftSpecFromSpark({
    required String sparkPrompt,
    required String apiKey,
    GodotProjectDimension? dimensionOverride,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final outcome = await draftSpecWithStatus(
      sparkPrompt: sparkPrompt,
      apiKey: apiKey,
      dimensionOverride: dimensionOverride,
      archetypeId: archetypeId,
      viewChoiceId: viewChoiceId,
      prototypeHookId: prototypeHookId,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
    );
    if (outcome.blueprint != null) return outcome.blueprint!;
    throw StateError(outcome.errorMessage ?? 'Failed to draft Project Spec.');
  }

  /// Synthesizes a complete Godot 4 Root Project Spec + `2–4` `v0.1` Epics and surfaces real AI errors.
  static Future<Stage1AgentOutcome> draftSpecWithStatus({
    required String sparkPrompt,
    required String apiKey,
    GodotProjectDimension? dimensionOverride,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmedSpark = sparkPrompt.trim();
    final matchedPreset = GodotSparkPresets.matchSparkPrompt(trimmedSpark);
    final effectiveDim = dimensionOverride ??
        matchedPreset?.dimension ??
        GodotProjectDimension.detectFromSpark(trimmedSpark);

    if (!GeminiAgentClient.hasKey(apiKey)) {
      if (matchedPreset != null) {
        var presetCopy = matchedPreset.deepCopy();
        if (dimensionOverride != null &&
            dimensionOverride != presetCopy.dimension) {
          presetCopy = convertBlueprintDimension(presetCopy, dimensionOverride);
        }
        if (trimmedSpark.isNotEmpty) {
          presetCopy.sparkPrompt = trimmedSpark;
        }
        final sanitized = GodotSpecGuard.sanitizeConceptBlueprint(presetCopy);
        normalizeSequentialEpicAndFeatureCodes(sanitized);
        return Stage1AgentOutcome(
          blueprint: sanitized,
          usedOfflineFallback: true,
          changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
        );
      }
      final fallback = _buildSynthesizedFallback(
        trimmedSpark,
        dimension: effectiveDim,
        archetypeId: archetypeId,
        viewChoiceId: viewChoiceId,
        prototypeHookId: prototypeHookId,
      );
      if (trimmedSpark.isNotEmpty) {
        fallback.sparkPrompt = trimmedSpark;
      }
      var clean = GodotSpecGuard.sanitizeConceptBlueprint(fallback);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
      );
    }

    final unitGuide = effectiveDim == GodotProjectDimension.dim2d
        ? '2D Pixel Space (`px`, `px/s`, `deg`, `s`, `hp`) with CharacterBody2D/Area2D/Camera2D'
        : '3D 1 unit = 1 meter (`m`, `m/s`, `deg`, `s`, `hp`) with CharacterBody3D/Area3D/SpringArm3D/Camera3D';
    final archetypeHint = archetypeId != null && archetypeId.trim().isNotEmpty
        ? '\nREQUESTED GENRE ARCHETYPE: $archetypeId'
            '${viewChoiceId != null && viewChoiceId.isNotEmpty ? ' · camera=$viewChoiceId' : ''}'
            '${prototypeHookId != null && prototypeHookId.isNotEmpty ? ' · prototype_goal=$prototypeHookId' : ''}'
        : '';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are the LAYERS Godot 4 Project Co-Designer.
Generate a clean, build-ready Stage 1 Project Spec (`PROJECT_SPEC.md` -> `ROOT_GODOT_CONTEXT`) for this game idea:
USER SPARK: "$trimmedSpark"
TARGET ARCHITECTURE: ${effectiveDim.fullLabel} (${effectiveDim.architectureContract})
CODE POLICY: ${effectiveDim.codePolicyContract}$archetypeHint

CRITICAL CONSTRAINTS:
- Match the true genre of the spark cleanly: for non-combat ideas (puzzle, racing, cozy, builder, stealth), design native scenes (`room_proto.tscn`, `track_proto.tscn`, `course_proto.tscn`) and domain inputs/verbs instead of forcing enemy combat or arena brawlers.
- Produce `2–4` Large-Domain `v0.1` Prototype Epics in `initialEpics` derived directly from §01 `coreLoop` beats and §02 Camera/Scale/InputMap contracts.
- Each Epic owns shared `sceneOwnership` (`.tscn`/`.gd` files), `inScope`, `doneWhen`, `states`, `interrupts`, `outOfScope`, AND `2–3` sittable 30-90 min `v0.1` Feature slices inside `features` (`F01`, `F02`, ... sequentially across all Epics with zero duplicate `F01` resets and zero `Task`/`Step` micro-lists).
- Keep controls, `@export` tuning parameters, cues, and Playtest Gate checks inside child `features` (never duplicate them on the parent Epic).
- Populate `coreLoopBeat` on every Epic naming which §01 Core Loop beat(s) it proves, and defer waves, menus, save slots, and meta progression to `v0.2+`.
- Use $unitGuide everywhere in §02 and in every Feature `@export` tuning parameter with `snake_case` keys and `snake_case` `InputMap` action names.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.4,
      functionDeclarations: [_rootSpecToolSchema],
    );

    if (res == null) {
      return Stage1AgentOutcome(
        blueprint: null,
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini did not return a valid Project Spec. Please retry.',
      );
    }

    final parsed = ProjectConceptBlueprint.fromJson(res);
    if (trimmedSpark.isNotEmpty) {
      parsed.sparkPrompt = trimmedSpark;
    }
    if (dimensionOverride != null && parsed.dimension != dimensionOverride) {
      final converted = convertBlueprintDimension(parsed, dimensionOverride);
      if (converted.initialEpics.isEmpty) {
        return const Stage1AgentOutcome(
          blueprint: null,
          errorMessage:
              'Cloud Gemini returned an empty §05 Epic list. Please retry.',
        );
      }
      normalizeSequentialEpicAndFeatureCodes(converted);
      return Stage1AgentOutcome(
        blueprint: converted,
        changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
      );
    }
    final rawDimStr = (res['dimension'] ?? '').toString().trim();
    if (rawDimStr.isEmpty) {
      parsed.dimension = effectiveDim;
    }
    if (parsed.initialEpics.isEmpty) {
      return const Stage1AgentOutcome(
        blueprint: null,
        errorMessage:
            'Cloud Gemini returned an empty §05 Epic list. Please retry.',
      );
    }
    var clean = GodotSpecGuard.sanitizeConceptBlueprint(parsed);
    normalizeSequentialEpicAndFeatureCodes(clean);
    return Stage1AgentOutcome(
      blueprint: clean,
      changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
    );
  }

  static void _upsertTuningParam(
    List<EpicTuningParam> tuning,
    String key,
    String value,
    String unit,
  ) {
    final idx = tuning.indexWhere(
      (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
    );
    if (idx >= 0) {
      tuning[idx].key = key;
      tuning[idx].value = value;
      tuning[idx].unit = unit;
    } else {
      tuning.add(EpicTuningParam(key: key, value: value, unit: unit));
    }
  }

  static void _upsertAimControl(
    List<EpicControlBinding> controls,
    String aimAction,
    String aimTrigger,
    String aimRule,
  ) {
    final aimIdx = controls.indexWhere((c) {
      final a = c.action.toLowerCase();
      return a.contains('aim') || a.contains('look') || a.contains('camera');
    });
    if (aimIdx >= 0) {
      controls[aimIdx].action = aimAction;
      controls[aimIdx].trigger = aimTrigger;
      controls[aimIdx].rule = aimRule;
    } else {
      controls.add(
        EpicControlBinding(
          action: aimAction,
          trigger: aimTrigger,
          rule: aimRule,
        ),
      );
    }
  }

  static void _upsertCameraCheck(
    List<EpicPieCheck> checks,
    String fallbackId,
    String expectedCheck,
  ) {
    final checkIdx = checks.indexWhere((c) {
      final t = c.text.toLowerCase();
      return t.contains('cursor') ||
          t.contains('reticle') ||
          t.contains('springarm') ||
          t.contains('camera') ||
          t.contains('visualrig') ||
          t.contains('first-person') ||
          t.contains('aim');
    });
    if (checkIdx >= 0) {
      checks[checkIdx].text = expectedCheck;
    } else {
      checks.add(EpicPieCheck(id: fallbackId, text: expectedCheck));
    }
  }

  /// Synchronizes locomotion Epic & first Feature's aim/look controls, tail tuning, and playtest check
  /// whenever the Stage 1 Camera Decision (`§02`) changes, without shifting `tuning[0]`.
  static void syncEpicCameraFraming(
    ProjectConceptBlueprint draft, {
    required String optionId,
    required String contractValue,
  }) {
    if (draft.initialEpics.isEmpty) return;
    final locoEpic = _findLocomotionEpic(draft);
    final lowerId = optionId.toLowerCase();
    final lowerContract = contractValue.toLowerCase();
    final is2d = draft.dimension == GodotProjectDimension.dim2d ||
        lowerId.endsWith('2d') ||
        lowerContract.contains('camera2d');
    final isTps = !is2d &&
        (lowerId.contains('tps') ||
            lowerId.contains('shoulder') ||
            lowerId.contains('third') ||
            lowerContract.contains('offset'));
    final isFps = !is2d && (lowerId.contains('fps') || lowerId.contains('first'));

    void upsertTailTuning(String key, String value, String unit) {
      if (locoEpic.tuning.isNotEmpty || locoEpic.features.isEmpty) {
        _upsertTuningParam(locoEpic.tuning, key, value, unit);
      }
      if (locoEpic.features.isNotEmpty) {
        _upsertTuningParam(locoEpic.features.first.tuning, key, value, unit);
      }
    }

    void removeTuning(String key) {
      locoEpic.tuning.removeWhere(
        (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
      );
      for (final f in locoEpic.features) {
        f.tuning.removeWhere(
          (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
        );
      }
    }

    if (is2d) {
      removeTuning('spring_arm_length');
      removeTuning('eye_height');
      removeTuning('camera_fov');
      final zoomMatch = RegExp(
        r'Zoom\s+(\d+(?:\.\d+)?)x',
        caseSensitive: false,
      ).firstMatch(contractValue);
      if (zoomMatch != null) {
        upsertTailTuning('camera_zoom', zoomMatch.group(1)!, 'x');
      }
    } else {
      removeTuning('camera_zoom');
      final springArmMatch = RegExp(
        r'SpringArm3D\s+(\d+(?:\.\d+)?)\s*m',
        caseSensitive: false,
      ).firstMatch(contractValue);
      final eyeHeightMatch = RegExp(
        r'EyeHeight\s+(\d+(?:\.\d+)?)\s*m',
        caseSensitive: false,
      ).firstMatch(contractValue);
      if (springArmMatch != null) {
        removeTuning('eye_height');
        upsertTailTuning('spring_arm_length', springArmMatch.group(1)!, 'm');
      } else if (isFps) {
        removeTuning('spring_arm_length');
        if (eyeHeightMatch != null) {
          upsertTailTuning('eye_height', eyeHeightMatch.group(1)!, 'm');
        }
      }
      final fovMatch = RegExp(
        r'(\d+(?:\.\d+)?)\s*deg\s*FOV',
        caseSensitive: false,
      ).firstMatch(contractValue);
      if (fovMatch != null) {
        upsertTailTuning('camera_fov', fovMatch.group(1)!, 'deg');
      }
    }

    final aimAction = is2d
        ? 'mouse_aim'
        : ((isTps || isFps) ? 'look_axis' : 'mouse_aim');
    final aimTrigger = (isTps || isFps)
        ? 'InputEventMouseMotion'
        : (is2d ? 'Cursor 2D Global Pos' : 'Physics Tick XZ Raycast');
    final aimRule = is2d
        ? 'Rotates player Sprite2D/WeaponPivot toward get_global_mouse_position() cleanly'
        : isTps
            ? 'Orbits over-shoulder SpringArm3D yaw/pitch and aligns center reticle'
            : isFps
                ? 'Direct 1:1 first-person Camera3D yaw/pitch rotation'
                : 'Projects cursor ray onto ground XZ-plane to orient VisualRig aim';

    if (locoEpic.controls.isNotEmpty || locoEpic.features.isEmpty) {
      _upsertAimControl(locoEpic.controls, aimAction, aimTrigger, aimRule);
    }
    if (locoEpic.features.isNotEmpty) {
      _upsertAimControl(
        locoEpic.features.first.controls,
        aimAction,
        aimTrigger,
        aimRule,
      );
    }

    final expectedCheck = is2d
        ? 'Move cursor across 2D viewport -> player aim indicator tracks cursor immediately'
        : isTps
            ? 'Move mouse -> over-shoulder SpringArm3D orbits smoothly with center reticle alignment'
            : isFps
                ? 'Move mouse -> first-person Camera3D turns smoothly with center reticle alignment'
                : 'Move cursor across floor -> VisualRig tracks ground XZ aim smoothly';

    if (locoEpic.checks.isNotEmpty || locoEpic.features.isEmpty) {
      _upsertCameraCheck(
        locoEpic.checks,
        '${locoEpic.code.toLowerCase()}_cam',
        expectedCheck,
      );
    }
    if (locoEpic.features.isNotEmpty) {
      final firstFeat = locoEpic.features.first;
      _upsertCameraCheck(
        firstFeat.checks,
        '${firstFeat.id}_cam',
        expectedCheck,
      );
    }
  }

  /// Synchronizes `feelChoiceId`, primary §03 feel `TradeOffRule`, and locomotion Epic tail tuning (`braking_decel`)
  /// without disturbing `tuning[0]`.
  static void syncEpicCoreFeel(
    ProjectConceptBlueprint draft, {
    required String feelId,
  }) {
    final opt = ProjectConceptBlueprint.coreFeelOptionById(feelId);
    draft.feelChoiceId = opt.id;

    final feelKeywords = <String>[
      for (final f in ProjectConceptBlueprint.coreFeelOptions)
        f.tradeOff.prefer.toLowerCase(),
      'acceleration',
      'windup',
      'velocity carry',
      'hovering spring',
      'momentum',
    ];
    final updatedTrades = List<TradeOffRule>.from(draft.tradeOffs);
    final idx = updatedTrades.indexWhere((t) {
      final p = t.prefer.toLowerCase();
      return feelKeywords.any((kw) => p.contains(kw));
    });
    if (idx >= 0) {
      updatedTrades.removeAt(idx);
    }
    updatedTrades.insert(0, opt.tradeOff);
    draft.tradeOffs = updatedTrades;

    if (draft.initialEpics.isEmpty) return;
    final locoEpic = _findLocomotionEpic(draft);
    final decelVal = opt.decelFor(draft.dimension);
    final speedUnit = draft.dimension.speedUnit;
    if (locoEpic.tuning.isNotEmpty || locoEpic.features.isEmpty) {
      _upsertTuningParam(locoEpic.tuning, 'braking_decel', decelVal, speedUnit);
    }
    if (locoEpic.features.isNotEmpty) {
      _upsertTuningParam(
        locoEpic.features.first.tuning,
        'braking_decel',
        decelVal,
        speedUnit,
      );
    }
  }

  static Map<String, dynamic> _compactStage1JsonForPrompt(
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

  static FeatureSpec _reconcileStage1Feature(
    FeatureSpec incoming,
    FeatureSpec? existing,
  ) {
    if (existing == null) return incoming.deepCopy();
    final copy = incoming.deepCopy(
      idOverride: existing.id,
      statusOverride: existing.status,
    );
    copy.introducedIn = 'v0.1';
    return copy;
  }

  static EpicSpec _reconcileStage1Epic({
    required EpicSpec incoming,
    required EpicSpec prev,
  }) {
    final reconciled = incoming.deepCopy(idOverride: prev.id);
    reconciled.lineageKey = prev.lineageKey.trim().isNotEmpty
        ? prev.lineageKey
        : incoming.lineageKey;
    reconciled.releaseVersion = 'v0.1';

    final usedFeat = List<bool>.filled(prev.features.length, false);
    final syncedFeatures = <FeatureSpec>[];
    for (int fIdx = 0; fIdx < reconciled.features.length; fIdx++) {
      final incFeat = reconciled.features[fIdx];
      int? matchIdx;
      if (incFeat.id.isNotEmpty &&
          !FeatureSpec.isPositionalFallbackFeatureId(incFeat.id)) {
        for (int pIdx = 0; pIdx < prev.features.length; pIdx++) {
          if (!usedFeat[pIdx] && prev.features[pIdx].id == incFeat.id) {
            matchIdx = pIdx;
            break;
          }
        }
      }
      final incTitle = incFeat.title.trim().toLowerCase();
      if (matchIdx == null && incTitle.isNotEmpty) {
        for (int pIdx = 0; pIdx < prev.features.length; pIdx++) {
          if (!usedFeat[pIdx] &&
              prev.features[pIdx].title.trim().toLowerCase() == incTitle) {
            matchIdx = pIdx;
            break;
          }
        }
      }
      final incCode = incFeat.code.trim().toLowerCase();
      if (matchIdx == null && incCode.isNotEmpty) {
        for (int pIdx = 0; pIdx < prev.features.length; pIdx++) {
          if (!usedFeat[pIdx] &&
              prev.features[pIdx].code.trim().toLowerCase() == incCode) {
            matchIdx = pIdx;
            break;
          }
        }
      }
      if (matchIdx == null &&
          fIdx < prev.features.length &&
          !usedFeat[fIdx]) {
        matchIdx = fIdx;
      }
      final matchedPrev = matchIdx != null ? prev.features[matchIdx] : null;
      if (matchIdx != null) usedFeat[matchIdx] = true;
      syncedFeatures.add(_reconcileStage1Feature(incFeat, matchedPrev));
    }
    reconciled.features = syncedFeatures;
    return reconciled;
  }

  static List<String> _parseStringListDynamic(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'->|→|\n|,'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  /// Applies a scoped `patch_godot_root_spec` (or full spec payload) cleanly onto [currentSpec].
  static ({ProjectConceptBlueprint blueprint, Set<String> changedSections})
      applyPatchJsonToBlueprint(
    ProjectConceptBlueprint currentSpec,
    Map<String, dynamic> patchRaw, {
    String fallbackNote = 'Applied Co-Designer updates.',
  }) {
    var patch = Map<String, dynamic>.from(patchRaw);
    if (patch.length == 1 && patch.values.first is Map) {
      patch = Map<String, dynamic>.from(patch.values.first as Map);
    }

    var next = currentSpec.deepCopy();
    final changed = <String>{};
    final rawChanged = patch['changedSections'];
    if (rawChanged is List) {
      for (final item in rawChanged) {
        final sec = item.toString().trim().toLowerCase();
        if (const {'s01', 's02', 's03', 's04', 's05'}.contains(sec)) {
          changed.add(sec);
        }
      }
    }

    // Detect explicit or camera-implied dimension switch FIRST so units scale safely.
    GodotProjectDimension targetDim = next.dimension;
    final rawDim = (patch['dimension'] ?? '').toString().trim();
    if (rawDim.isNotEmpty) {
      targetDim = GodotProjectDimension.fromString(rawDim);
    } else if (patch['cameraChoiceId'] != null) {
      final camId = patch['cameraChoiceId'].toString().trim().toLowerCase();
      if (camId.endsWith('2d')) {
        targetDim = GodotProjectDimension.dim2d;
      } else if (const {'isometric', 'topdown', 'tps', 'fps'}.contains(camId)) {
        targetDim = GodotProjectDimension.dim3d;
      }
    }
    if (targetDim != next.dimension) {
      next = convertBlueprintDimension(next, targetDim);
      changed.addAll(const <String>{'s02', 's05'});
    }

    bool majorScopeShift = false;
    final incomingTitle = (patch['gameTitle'] ?? patch['title'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (incomingTitle.isNotEmpty && incomingTitle != next.gameTitle) {
      next.gameTitle = incomingTitle;
      changed.add('s01');
      majorScopeShift = true;
    }

    final incomingPitch = (patch['pitch'] ?? patch['goal'] ?? '').toString().trim();
    if (incomingPitch.isNotEmpty && incomingPitch != next.pitch) {
      next.pitch = incomingPitch;
      changed.add('s01');
      majorScopeShift = true;
    }

    if (patch.containsKey('coreLoop')) {
      final loop = _parseStringListDynamic(patch['coreLoop']);
      if (loop.isNotEmpty) {
        next.coreLoop = loop;
        changed.add('s01');
      }
    }

    if (patch['cameraDecisionOptions'] is List &&
        (patch['cameraDecisionOptions'] as List).isNotEmpty) {
      next.cameraDecisionOptions = [
        for (final item in (patch['cameraDecisionOptions'] as List))
          if (item is Map)
            ConceptSectionOption.fromJson(Map<String, dynamic>.from(item)),
      ];
      changed.add('s02');
    }

    bool cameraChanged = false;
    final incomingCamChoice = (patch['cameraChoiceId'] ?? '').toString().trim();
    if (incomingCamChoice.isNotEmpty && incomingCamChoice != next.cameraChoiceId) {
      next.cameraChoiceId = incomingCamChoice;
      cameraChanged = true;
      changed.add('s02');
    }
    final incomingCamContract =
        (patch['cameraContract'] ?? '').toString().trim();
    if (incomingCamContract.isNotEmpty &&
        incomingCamContract != next.cameraContract) {
      next.cameraContract = incomingCamContract;
      cameraChanged = true;
      changed.add('s02');
    }
    final incomingScale = (patch['characterScale'] ?? '').toString().trim();
    if (incomingScale.isNotEmpty && incomingScale != next.characterScale) {
      next.characterScale = incomingScale;
      changed.add('s02');
    }
    final incomingInput = (patch['inputContract'] ?? '').toString().trim();
    if (incomingInput.isNotEmpty && incomingInput != next.inputContract) {
      next.inputContract = incomingInput;
      changed.add('s02');
    }
    final incomingAsset = (patch['assetPolicy'] ?? '').toString().trim();
    if (incomingAsset.isNotEmpty && incomingAsset != next.assetPolicy) {
      next.assetPolicy = incomingAsset;
      changed.add('s02');
    }

    if (patch['feelChoiceId'] != null) {
      final feel = ProjectConceptBlueprint.normalizeFeelChoiceId(
        patch['feelChoiceId'].toString(),
      );
      if (feel != next.feelChoiceId) {
        syncEpicCoreFeel(next, feelId: feel);
        changed.addAll(const <String>{'s03', 's05'});
      }
    }
    if (patch.containsKey('pillars')) {
      final p = _parseStringListDynamic(patch['pillars']);
      if (p.isNotEmpty) {
        next.pillars = p;
        changed.add('s03');
      }
    }
    if (patch['tradeOffs'] is List) {
      final rawTrades = patch['tradeOffs'] as List;
      if (rawTrades.isNotEmpty) {
        next.tradeOffs = [
          for (final item in rawTrades) TradeOffRule.fromDynamic(item),
        ];
        changed.add('s03');
      }
    }
    if (patch['outOfScope'] is List) {
      next.outOfScope = _parseStringListDynamic(patch['outOfScope']);
      changed.add('s04');
    }
    final incomingRelDone = (patch['releaseDoneWhen'] ?? '').toString().trim();
    if (incomingRelDone.isNotEmpty && incomingRelDone != next.releaseDoneWhen) {
      next.releaseDoneWhen = incomingRelDone;
      changed.add('s05');
    }

    bool epicsTouched = false;
    final rawFullEpics = patch['initialEpics'];
    if (rawFullEpics is List && rawFullEpics.isNotEmpty) {
      final prevEpics = currentSpec.initialEpics;
      final usedPrev = List<bool>.filled(prevEpics.length, false);
      final rebuilt = <EpicSpec>[];
      final incomingTitles = <String>{};
      final parsedIncoming = <EpicSpec>[];
      for (int i = 0; i < rawFullEpics.length; i++) {
        if (rawFullEpics[i] is Map) {
          final e = EpicSpec.fromJson(
            Map<String, dynamic>.from(rawFullEpics[i] as Map),
            indexHint: i,
          );
          parsedIncoming.add(e);
          if (e.title.trim().isNotEmpty) {
            incomingTitles.add(e.title.trim().toLowerCase());
          }
        }
      }
      for (int i = 0; i < parsedIncoming.length; i++) {
        final inc = parsedIncoming[i];
        final incLineage = inc.lineageKey.trim().toLowerCase();
        int? matchIdx;
        if (incLineage.isNotEmpty) {
          for (int j = 0; j < prevEpics.length; j++) {
            if (!usedPrev[j] &&
                prevEpics[j].lineageKey.trim().toLowerCase() == incLineage) {
              matchIdx = j;
              break;
            }
          }
        }
        if (matchIdx == null && inc.title.trim().isNotEmpty) {
          final lowerTitle = inc.title.trim().toLowerCase();
          for (int j = 0; j < prevEpics.length; j++) {
            if (!usedPrev[j] &&
                prevEpics[j].title.trim().toLowerCase() == lowerTitle) {
              matchIdx = j;
              break;
            }
          }
        }
        if (matchIdx == null &&
            i < prevEpics.length &&
            !usedPrev[i] &&
            !incomingTitles.contains(prevEpics[i].title.trim().toLowerCase())) {
          matchIdx = i;
        }
        if (matchIdx != null) {
          usedPrev[matchIdx] = true;
          rebuilt.add(_reconcileStage1Epic(incoming: inc, prev: prevEpics[matchIdx]));
        } else {
          if (inc.lineageKey.trim().isEmpty) {
            inc.lineageKey = EpicSpec.formatLineageKey(i + 1);
          }
          rebuilt.add(inc);
        }
      }
      if (rebuilt.isNotEmpty) {
        next.initialEpics = rebuilt;
        epicsTouched = true;
        changed.add('s05');
      }
    } else {
      final rawRemoves = patch['removeEpicLineageKeys'];
      if (rawRemoves is List && rawRemoves.isNotEmpty && next.initialEpics.length > 1) {
        final removeTokens = {
          for (final r in rawRemoves) r.toString().trim().toLowerCase(),
        }..removeWhere((s) => s.isEmpty);
        final kept = next.initialEpics.where((ep) {
          final lk = ep.lineageKey.trim().toLowerCase();
          final cd = ep.code.trim().toLowerCase();
          return !removeTokens.contains(lk) && !removeTokens.contains(cd);
        }).toList();
        if (kept.isNotEmpty && kept.length != next.initialEpics.length) {
          next.initialEpics = kept;
          epicsTouched = true;
          changed.add('s05');
        }
      }

      final rawEpicUpdates = patch['epicUpdates'];
      if (rawEpicUpdates is List && rawEpicUpdates.isNotEmpty) {
        for (int i = 0; i < rawEpicUpdates.length; i++) {
          if (rawEpicUpdates[i] is! Map) continue;
          final inc = EpicSpec.fromJson(
            Map<String, dynamic>.from(rawEpicUpdates[i] as Map),
            indexHint: next.initialEpics.length + i,
          );
          final incLineage = inc.lineageKey.trim().toLowerCase();
          final incCode = inc.code.trim().toLowerCase();
          final incTitle = inc.title.trim().toLowerCase();
          int matchIdx = next.initialEpics.indexWhere(
            (e) =>
                (incLineage.isNotEmpty &&
                    e.lineageKey.trim().toLowerCase() == incLineage) ||
                (incCode.isNotEmpty && e.code.trim().toLowerCase() == incCode) ||
                (incTitle.isNotEmpty &&
                    e.title.trim().toLowerCase() == incTitle),
          );
          if (matchIdx >= 0) {
            next.initialEpics[matchIdx] = _reconcileStage1Epic(
              incoming: inc,
              prev: next.initialEpics[matchIdx],
            );
          } else {
            if (inc.lineageKey.trim().isEmpty) {
              inc.lineageKey =
                  EpicSpec.formatLineageKey(next.initialEpics.length + 1);
            }
            next.initialEpics.add(inc);
          }
          epicsTouched = true;
          changed.add('s05');
        }
      }
    }

    if (cameraChanged && !epicsTouched) {
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      changed.add('s05');
    }

    if (majorScopeShift) {
      next.v02Presets = <ReleaseDirectionPreset>[];
      next.v02NewPool = <EpicSpec>[];
      next.v02UpgradesByLineageKey = <String, List<EpicUpgradeOption>>{};
      next.v02NewFeaturesByLineageKey = <String, List<FeatureSpec>>{};
    } else if (epicsTouched) {
      final validLineages = {
        for (final ep in next.initialEpics) ep.lineageKey.trim().toLowerCase(),
      };
      next.v02UpgradesByLineageKey.removeWhere(
        (key, _) => !validLineages.contains(key.toLowerCase()),
      );
      next.v02NewFeaturesByLineageKey.removeWhere(
        (key, _) => !validLineages.contains(key.toLowerCase()),
      );
    }

    next.lastCoDesignNote =
        (patch['coDesignNote'] ?? fallbackNote).toString().trim();
    next = GodotSpecGuard.sanitizeConceptBlueprint(next);
    normalizeSequentialEpicAndFeatureCodes(next);
    return (blueprint: next, changedSections: changed);
  }

  /// Applies a user's Co-Designer instruction directly onto an active Stage 1 [ProjectConceptBlueprint].
  static Future<ProjectConceptBlueprint> applyCoDesignEdit({
    required ProjectConceptBlueprint currentSpec,
    required String instruction,
    required String apiKey,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final outcome = await applyCoDesignEditWithStatus(
      currentSpec: currentSpec,
      instruction: instruction,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
    );
    return outcome.blueprint ?? currentSpec;
  }

  /// Applies a Stage 1 Co-Designer instruction using scoped JSON patches and surfaces real errors.
  static Future<Stage1AgentOutcome> applyCoDesignEditWithStatus({
    required ProjectConceptBlueprint currentSpec,
    required String instruction,
    required String apiKey,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) {
      return Stage1AgentOutcome(blueprint: currentSpec);
    }

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _tryApplyDeterministicOfflineEdit(currentSpec, trimmed);
    }

    final compactJson = jsonEncode(_compactStage1JsonForPrompt(currentSpec));
    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Patch only the sections of the Godot 4 Root Project Spec (`§01-§05`) requested by the user instruction.
CURRENT ARCHITECTURE: ${currentSpec.dimension.fullLabel} (${currentSpec.dimension.architectureContract})
CODE POLICY: ${currentSpec.dimension.codePolicyContract}
RULES:
- Call `patch_godot_root_spec` with ONLY the fields you need to change plus `coDesignNote` and `changedSections`.
- Omit unchanged scalar/list fields and untouched Epics so untouched sections remain identical.
- If changing dimension (`dim2d` / `dim3d`) or Camera framing, update `dimension`, `cameraChoiceId`, `cameraContract`, `characterScale`, and any affected Epics in `epicUpdates`.
- Keep all `§05` Epics strictly at `2–4` `v0.1` Epics with sequential `F01..FM` Feature slices and Godot units (`m`/`m/s` for 3D, `px`/`px/s` for 2D).

CURRENT COMPACT SPEC JSON:
$compactJson

USER CO-DESIGN INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.3,
      functionDeclarations: [_patchRootSpecToolSchema],
    );

    if (res == null) {
      return Stage1AgentOutcome(
        blueprint: null,
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini could not apply that refine. Your prompt was kept so you can retry.',
      );
    }

    final patched = applyPatchJsonToBlueprint(
      currentSpec,
      res,
      fallbackNote: 'Updated spec from: $trimmed',
    );
    return Stage1AgentOutcome(
      blueprint: patched.blueprint,
      changedSections: patched.changedSections,
    );
  }

  static Stage1AgentOutcome _tryApplyDeterministicOfflineEdit(
    ProjectConceptBlueprint current,
    String instruction,
  ) {
    final next = current.deepCopy();
    final lower = instruction.toLowerCase();

    if (RegExp(r'\b2d\b').hasMatch(lower) &&
        !lower.contains('side-scroller') &&
        !lower.contains('side scroller') &&
        !lower.contains('top-down') &&
        !lower.contains('top down')) {
      final converted =
          convertBlueprintDimension(next, GodotProjectDimension.dim2d);
      normalizeSequentialEpicAndFeatureCodes(converted);
      converted.lastCoDesignNote =
          'Switched project dimension to Godot 4 · 2D (px, px/s).';
      return Stage1AgentOutcome(
        blueprint: converted,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (RegExp(r'\b3d\b').hasMatch(lower) &&
        !lower.contains('first-person') &&
        !lower.contains('first person') &&
        !lower.contains('third-person') &&
        !lower.contains('third person') &&
        !lower.contains('isometric')) {
      final converted =
          convertBlueprintDimension(next, GodotProjectDimension.dim3d);
      normalizeSequentialEpicAndFeatureCodes(converted);
      converted.lastCoDesignNote =
          'Switched project dimension to Godot 4 · 3D (m, m/s).';
      return Stage1AgentOutcome(
        blueprint: converted,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('side-scroller') ||
        lower.contains('side scroller')) {
      final base = convertBlueprintDimension(next, GodotProjectDimension.dim2d);
      base.cameraChoiceId = 'sidescroller2d';
      base.cameraContract =
          'Camera2D Zoom 1.4x · Lookahead 64 px · Horizontal floor lock';
      syncEpicCameraFraming(
        base,
        optionId: base.cameraChoiceId,
        contractValue: base.cameraContract,
      );
      base.lastCoDesignNote =
          'Switched §02 Camera contract & E01 framing to 2D Side-Scroller.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(base);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('first-person') ||
        lower.contains('first person') ||
        lower.contains('fps')) {
      final base = convertBlueprintDimension(next, GodotProjectDimension.dim3d);
      base.cameraChoiceId = 'fps';
      base.cameraContract =
          'Camera3D EyeHeight 1.65 m · 90 deg FOV · Captured mouse yaw/pitch';
      syncEpicCameraFraming(
        base,
        optionId: base.cameraChoiceId,
        contractValue: base.cameraContract,
      );
      base.lastCoDesignNote =
          'Switched §02 Camera contract & E01 look controls to First-Person.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(base);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('third person') ||
        lower.contains('third-person') ||
        lower.contains('tps') ||
        lower.contains('over-shoulder') ||
        lower.contains('over shoulder')) {
      final base = convertBlueprintDimension(next, GodotProjectDimension.dim3d);
      base.cameraChoiceId = 'tps';
      base.cameraContract =
          'SpringArm3D 3.8 m · Offset (0.65, 0.55) m · 68 deg FOV · CameraLag 10.0';
      syncEpicCameraFraming(
        base,
        optionId: base.cameraChoiceId,
        contractValue: base.cameraContract,
      );
      base.lastCoDesignNote =
          'Switched §02 Camera contract & E01 look controls to Third-Person.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(base);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('top-down') || lower.contains('top down')) {
      if (next.dimension == GodotProjectDimension.dim2d) {
        next.cameraChoiceId = 'topdown2d';
        next.cameraContract =
            'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim';
      } else {
        next.cameraChoiceId = 'topdown';
        next.cameraContract =
            'SpringArm3D 16.5 m @ -88 deg pitch, 50 deg FOV, Zero camera roll';
      }
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 cursor aim to Fixed Top-Down.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(next);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('isometric')) {
      final base = convertBlueprintDimension(next, GodotProjectDimension.dim3d);
      base.cameraChoiceId = 'isometric';
      base.cameraContract =
          'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0';
      syncEpicCameraFraming(
        base,
        optionId: base.cameraChoiceId,
        contractValue: base.cameraContract,
      );
      base.lastCoDesignNote =
          'Switched §02 Camera contract & E01 cursor aim to Isometric.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(base);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('heavy') ||
        lower.contains('deliberate') ||
        lower.contains('weighty')) {
      syncEpicCoreFeel(next, feelId: 'heavy');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Heavy Deliberate.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(next);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s03', 's05'},
      );
    } else if (lower.contains('physics') ||
        lower.contains('momentum') ||
        lower.contains('drift')) {
      syncEpicCoreFeel(next, feelId: 'physics');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Physics Momentum.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(next);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s03', 's05'},
      );
    } else if (lower.contains('snappy') || lower.contains('arcade')) {
      syncEpicCoreFeel(next, feelId: 'snappy');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Snappy Arcade.';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(next);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s03', 's05'},
      );
    } else if (lower.startsWith('no ') ||
        lower.startsWith('cut ') ||
        lower.startsWith('remove ')) {
      final cut = instruction
          .replaceFirst(RegExp(r'^(cut|remove)\s+', caseSensitive: false), '')
          .trim();
      final item = cut.toLowerCase().startsWith('no ') ? cut : 'No $cut';
      if (!next.outOfScope.contains(item)) {
        next.outOfScope = [...next.outOfScope, item];
      }
      next.lastCoDesignNote = 'Added hard scope cut: $item';
      final clean = GodotSpecGuard.sanitizeConceptBlueprint(next);
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s04'},
      );
    }

    return const Stage1AgentOutcome(
      blueprint: null,
      errorMessage:
          'Sign in with Google or add a Gemini API key for custom AI spec refines.',
    );
  }

  /// Returns 3 context-aware quick-refine chips tailored to the current Stage 1 spec.
  static List<QuickRefineSuggestion> suggestQuickRefines(
    ProjectConceptBlueprint spec,
  ) {
    final summary = Stage1ScopeSummary.fromBlueprint(spec);
    final suggestions = <QuickRefineSuggestion>[
      if (summary.featureCount > 6 || summary.epicCount > 3)
        const QuickRefineSuggestion(
          label: 'Trim to lean v0.1',
          instruction:
              'Trim v0.1 scope to 2-3 Epics (<= 6 Features total) and move extra systems into §04 Hard Scope Cuts.',
        )
      else
        const QuickRefineSuggestion(
          label: 'Tighten slices (30-45m)',
          instruction:
              'Keep each §05 Feature slice focused at 30-45 min with sharp causal Playtest checks.',
        ),
      if (spec.feelChoiceId == 'snappy')
        const QuickRefineSuggestion(
          label: 'Make feel heavier',
          instruction:
              'Shift §03 Core Feel and E01 movement toward Heavy Deliberate with committed windups.',
        )
      else
        const QuickRefineSuggestion(
          label: 'Make controls snappier',
          instruction:
              'Shift §03 Core Feel and E01 movement to Snappy Arcade instant acceleration.',
        ),
      if (spec.initialEpics.any(
        (e) =>
            e.title.toLowerCase().contains('combat') ||
            e.title.toLowerCase().contains('enemy'),
      ))
        const QuickRefineSuggestion(
          label: 'Add parry / counter',
          instruction:
              'Add a crisp risk/reward parry window Feature slice inside the combat Epic.',
        )
      else
        const QuickRefineSuggestion(
          label: 'Add timer / replay cue',
          instruction:
              'Add a clear run timer and quick-restart cue to sharpen the 30s replay loop.',
        ),
    ];
    return suggestions;
  }

  static ProjectConceptBlueprint _buildSynthesizedFallback(
    String sparkPrompt, {
    required GodotProjectDimension dimension,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
  }) {
    final cleaned = sparkPrompt.trim();
    final lower = cleaned.toLowerCase();
    final is2d = dimension == GodotProjectDimension.dim2d;

    final resolvedCamOptions = is2d
        ? ProjectConceptBlueprint.defaultCamera2dOptions
        : ProjectConceptBlueprint.defaultCamera3dOptions;

    String cameraChoice;
    if (viewChoiceId != null &&
        resolvedCamOptions.any((o) => o.id == viewChoiceId)) {
      cameraChoice = viewChoiceId;
    } else if (is2d) {
      final isSideScroller = lower.contains('side-scroller') ||
          lower.contains('side scroller') ||
          lower.contains('platformer') ||
          lower.contains('metroidvania');
      final isFixedRoom = lower.contains('puzzle') ||
          lower.contains('sokoban') ||
          lower.contains('room');
      cameraChoice = isSideScroller
          ? 'sidescroller2d'
          : (isFixedRoom ? 'fixedarena2d' : 'topdown2d');
    } else {
      final isFps = lower.contains('first-person') ||
          lower.contains('first person') ||
          lower.contains('fps');
      final isTps = !isFps &&
          (lower.contains('third-person') ||
              lower.contains('third person') ||
              lower.contains('over-shoulder') ||
              lower.contains('over shoulder') ||
              lower.contains('glider') ||
              lower.contains('wingsuit') ||
              lower.contains('grapple') ||
              lower.contains('grappling') ||
              lower.contains('racer') ||
              lower.contains('tps'));
      final isTopDown3d = !isFps &&
          !isTps &&
          (lower.contains('top-down') || lower.contains('top down'));
      cameraChoice = isFps
          ? 'fps'
          : (isTps ? 'tps' : (isTopDown3d ? 'topdown' : 'isometric'));
    }

    final cameraContract = resolvedCamOptions
        .firstWhere(
          (o) => o.id == cameraChoice,
          orElse: () => resolvedCamOptions.first,
        )
        .contractValue;

    final effectiveArchetype = (archetypeId != null &&
            const {'combat', 'movement', 'racer', 'puzzle'}
                .contains(archetypeId))
        ? archetypeId
        : (RegExp(r'\b(?:race|racer|drift|track|lap|skiff|car|kart|boost)\b')
                .hasMatch(lower)
            ? 'racer'
            : (RegExp(
                        r'\b(?:puzzle|cozy|farm|farming|card|deck|sokoban|craft|relay|mirror|cooking)\b')
                    .hasMatch(lower)
                ? 'puzzle'
                : (RegExp(
                            r'\b(?:platformer|climb|grapple|parkour|hop|jump|course)\b')
                        .hasMatch(lower) &&
                    !lower.contains('shooter') &&
                    !lower.contains('brawler') &&
                    !lower.contains('crawler')
                    ? 'movement'
                    : 'combat')));

    final feelId = (lower.contains('heavy') ||
            lower.contains('deliberate') ||
            lower.contains('souls'))
        ? 'heavy'
        : (lower.contains('drift') ||
                lower.contains('hover') ||
                lower.contains('glider') ||
                lower.contains('physics') ||
                effectiveArchetype == 'racer')
            ? 'physics'
            : 'snappy';

    final titleWords = cleaned
        .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .take(2)
        .map((w) => w.toUpperCase())
        .toList();
    final title =
        titleWords.isEmpty ? 'PROTOTYPE ZERO' : titleWords.join(' ');
    final shortSpark = cleaned.isEmpty
        ? 'Focused Godot 4 vertical prototype testing core player movement and primary interaction'
        : cleaned;

    final distUnit = dimension.distanceUnit;
    final speedUnit = dimension.speedUnit;
    final moveVal = is2d ? '260' : '6.2';
    final dodgeDist = is2d ? '180' : '5.0';
    final actionRange = is2d ? '420' : '16.0';
    final deployDist = is2d ? '72' : '2.0';
    final arenaExtent = is2d ? '1280x720 px' : '28x28 m';
    final targetDist = is2d ? '320 px' : '12 m';
    final reachVal = is2d ? '64' : '2.2';
    final snapVal = is2d ? '24' : '0.8';
    final topSpeedVal = is2d ? '520' : '24.0';
    final gateWidthVal = is2d ? '140' : '5.5';
    final bodyCls = is2d ? 'CharacterBody2D' : 'CharacterBody3D';
    final camNote = is2d ? 'Camera2D' : 'SpringArm3D';

    final List<String> loop;
    final List<EpicSpec> epics;
    String testScenePath;
    String inputSummary;

    if (effectiveArchetype == 'puzzle') {
      testScenePath = 'res://scenes/room_proto.tscn';
      inputSummary =
          'InputMap (move_left/right/up/down, interact, rotate_or_use, reset_room)';
      loop = const [
        'Move & Inspect',
        'Manipulate Relay',
        'Trigger Signal Chain',
        'Open Gate & Reset',
      ];
      epics = [
        EpicSpec(
          id: 'ep_01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Movement & Camera',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · ${loop[0]}',
          goal:
              'Own player $bodyCls room movement, collision sliding, and locked $camNote framing.',
          inScope: [
            'Smooth directional movement at $moveVal $speedUnit inside $arenaExtent puzzle room',
            'Clean corner sliding along greybox block obstacles',
          ],
          doneWhen: [
            'Walk all 4 walls of $arenaExtent -> Zero snagging with clear cursor highlight',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/room_proto.tscn',
              role: '$arenaExtent puzzle room + SpawnPoint + ExitGate',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/player.tscn',
              role: '$bodyCls + $camNote + InteractionRay',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/player.gd',
              role: 'Grid/free locomotion & focus probe',
            ),
          ],
          outOfScope: const ['No sprint stamina or combat dodge states'],
          states: const ['Idle <-> Walk -> Interacting'],
          interrupts: const ['Press R resets player back to SpawnPoint cleanly'],
          features: [
            FeatureSpec(
              id: 'ep_01_f01',
              code: 'F01',
              title: 'Room Walk & Camera Tracking',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.active,
              goal: 'Move player cleanly at $moveVal $speedUnit with crisp $camNote framing.',
              controls: [
                EpicControlBinding(
                  action: 'move_8way',
                  trigger: 'Held (WASD)',
                  rule: 'Moves smoothly at $moveVal $speedUnit across puzzle room',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
              ],
              cues: const ['Subtle footstep dust & focus reticle outline'],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f01_c1',
                  text: 'Hold WASD -> Player glides smoothly inside room with zero corner snags',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_01_f02',
              code: 'F02',
              title: 'Target Probe & Focus Outline',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Highlight nearest interactable object within $reachVal $distUnit.',
              controls: [
                EpicControlBinding(
                  action: 'interact',
                  trigger: 'Just Pressed (E / LMB)',
                  rule: 'Selects highlighted puzzle node within $reachVal $distUnit',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'interact_reach', value: reachVal, unit: distUnit),
              ],
              cues: const ['Bright cyan outline glow on active target object'],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f02_c1',
                  text: 'Approach object -> Target highlights crisply at $reachVal $distUnit',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Interactive Objects & Relays',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 2 · ${loop[1]}',
          goal:
              'Own movable/rotatable puzzle objects and clean signal state emission to room gates.',
          inScope: [
            'Push, pick, or rotate greybox relays snapping within $snapVal $distUnit',
            'Emit state_changed signal to linked receptors',
          ],
          doneWhen: [
            'Press E near relay -> State toggles visibly and linked signal beam updates immediately',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/puzzle_object.tscn',
              role: 'Interactive block / relay + trigger collider',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/puzzle_object.gd',
              role: 'Snap placement & active state signal',
            ),
          ],
          outOfScope: const ['No physics rope chains or inventory crafting tree'],
          states: const ['Resting -> Moved / Rotated -> LinkedActive'],
          interrupts: const ['Wall collision blocks push past room boundary cleanly'],
          features: [
            FeatureSpec(
              id: 'ep_02_f01',
              code: 'F03',
              title: 'Push, Place & Snap Relay',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Interact to move or rotate relay nodes with $snapVal $distUnit snap alignment.',
              controls: [
                EpicControlBinding(
                  action: 'rotate_or_use',
                  trigger: 'Just Pressed (R / RMB)',
                  rule: 'Rotates or toggles held puzzle node state cleanly',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'snap_tolerance', value: snapVal, unit: distUnit),
              ],
              cues: const ['Soft chime pitch increment on each snap step'],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f01_c1',
                  text: 'Press E/RMB on relay -> Object shifts cleanly and emits beam/color cue',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_02_f02',
              code: 'F04',
              title: 'Receptor Signal Beam Link',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Propagate active signal from aligned relays to the exit receptor.',
              tuning: [
                EpicTuningParam(key: 'signal_delay_s', value: '0.1', unit: 's'),
              ],
              cues: const ['Green signal line lights up between relay and gate'],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f02_c1',
                  text: 'Align two relays -> Exit receptor turns green immediately',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Puzzle Goal & Room Reset',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 4 · ${loop[3]}',
          goal:
              'Own room completion state detection, exit gate opening, HUD status, and instant reset.',
          inScope: [
            'Exit gate unlocks automatically when required relays stay active',
            'Instant room state reset on R without scene reload flicker',
          ],
          doneWhen: [
            'Solve room relays and enter ExitGate -> Victory banner shows and R resets room cleanly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/room_controller.gd',
              role: 'Signal aggregator + R reset snapshot',
            ),
          ],
          outOfScope: const ['No multi-level world map or save slots'],
          states: const ['Locked -> Solved -> Resetting'],
          interrupts: const ['Any relay deactivated re-locks ExitGate immediately'],
          features: [
            FeatureSpec(
              id: 'ep_03_f01',
              code: 'F05',
              title: 'Goal Gate Unlock & Banner',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Unlock ExitGate within $reachVal $distUnit trigger zone when solved.',
              tuning: [
                EpicTuningParam(key: 'goal_gate_radius', value: reachVal, unit: distUnit),
              ],
              cues: const ['Gate slides open with subtle green glow and solved banner'],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f01_c1',
                  text: 'Complete puzzle chain -> Gate opens and walking in shows Solved HUD',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_03_f02',
              code: 'F06',
              title: 'Instant Room State Reset',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Restore initial relay positions and SpawnPoint in < 0.2 s on R.',
              controls: [
                EpicControlBinding(
                  action: 'reset_room',
                  trigger: 'Just Pressed (R)',
                  rule: 'Restores player and all puzzle objects cleanly',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f02_c1',
                  text: 'Press R -> Room layout resets cleanly to starting configuration',
                ),
              ],
            ),
          ],
        ),
      ];
    } else if (effectiveArchetype == 'racer') {
      testScenePath = 'res://scenes/track_proto.tscn';
      inputSummary =
          'InputMap (throttle, brake, steer_left/steer_right, drift_boost, reset_track)';
      loop = const [
        'Throttle & Steer',
        'Drift Through Apex',
        'Hit Boost Gate',
        'Clear Lap & Restart',
      ];
      epics = [
        EpicSpec(
          id: 'ep_01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Vehicle Handling & Camera',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · ${loop[0]}',
          goal:
              'Own responsive craft throttle, steering, drift slip banking, and follow $camNote rig.',
          inScope: [
            'Forward acceleration up to $topSpeedVal $speedUnit with wall slide bounce',
            'Speed-reactive FOV/zoom pull on high velocity corners',
          ],
          doneWhen: [
            'Hold W + A/D along track -> Craft holds corner line at $topSpeedVal $speedUnit cleanly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/track_proto.tscn',
              role: 'Looping greybox test circuit + guardrails + SpawnPoint',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/racer.tscn',
              role: '$bodyCls craft + $camNote follow camera',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/racer.gd',
              role: 'Acceleration, steer banking & drift state machine',
            ),
          ],
          outOfScope: const ['No AI rubber-banding opponents or vehicle garage'],
          states: const ['Cruise -> DriftBank -> OverheatSlowdown -> Recover'],
          interrupts: const ['Guardrail bump dampens speed 25% without sticking'],
          features: [
            FeatureSpec(
              id: 'ep_01_f01',
              code: 'F01',
              title: 'Throttle, Steer & Chase Camera',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.active,
              goal: 'Drive craft smoothly up to $topSpeedVal $speedUnit with banked follow cam.',
              controls: [
                EpicControlBinding(
                  action: 'throttle',
                  trigger: 'Held (W / Up)',
                  rule: 'Accelerates craft smoothly up to $topSpeedVal $speedUnit',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'top_speed', value: topSpeedVal, unit: speedUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f01_c1',
                  text: 'Hold W + A/D -> Craft banks cleanly around corners',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_01_f02',
              code: 'F02',
              title: 'Drift Slip & Corner Hold',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Hold tight drift angle on Space with sparks trail feedback.',
              controls: [
                EpicControlBinding(
                  action: 'drift_boost',
                  trigger: 'Held / Released (Space)',
                  rule: 'Enters drift slide and triggers exit surge on straight',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'drift_grip', value: '0.65', unit: 'x'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f02_c1',
                  text: 'Hold Space in turn -> Rear slides smoothly with spark ribbon',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Boost Pads & Thruster Heat',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · ${loop[2]}',
          goal:
              'Own track boost gates, surge speed impulses, and thruster heat buildup.',
          inScope: [
            '$gateWidthVal $distUnit boost gates adding temporary speed surge',
            'HUD speed + thruster heat gauge bar',
          ],
          doneWhen: [
            'Pass through gate -> Craft surges briefly and HUD heat bar updates smoothly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/boost_pad.tscn',
              role: 'Track trigger gate + glowing chevron mesh',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/boost_pad.gd',
              role: 'Area overlap boost impulse & cooldown lock',
            ),
          ],
          outOfScope: const ['No item boxes or weapon pickups'],
          states: const ['Normal -> Boosting (0.9s) -> Cooling'],
          interrupts: const ['Exceeding 100% heat triggers 1.2s forced vent slowdown'],
          features: [
            FeatureSpec(
              id: 'ep_02_f01',
              code: 'F03',
              title: 'Track Boost Gate Surge',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Pass $gateWidthVal $distUnit gate to gain +$moveVal $speedUnit boost.',
              tuning: [
                EpicTuningParam(key: 'boost_bonus_speed', value: moveVal, unit: speedUnit),
                EpicTuningParam(key: 'gate_width', value: gateWidthVal, unit: distUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f01_c1',
                  text: 'Cross glowing gate -> Speed flashes upward cleanly for 0.9 s',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_02_f02',
              code: 'F04',
              title: 'Thruster Heat Gauge & Vent',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Track 0-100% heat meter on CanvasLayer HUD with red overheat warning.',
              tuning: [
                EpicTuningParam(key: 'overheat_vent_s', value: '1.2', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f02_c1',
                  text: 'Chain boosts to max heat -> HUD warns red and craft vents briefly',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Checkpoints & Lap Timer',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 4 · ${loop[3]}',
          goal:
              'Own sequential track checkpoints, live lap stopwatch HUD, and R instant reset.',
          inScope: [
            'Ordered checkpoint zones preventing reverse-lap skip',
            'Live lap time + best lap readout + R restart',
          ],
          doneWhen: [
            'Finish 1 lap and press R -> Best lap records cleanly and craft resets to start line',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/lap_timer.gd',
              role: 'Checkpoint sequence tracker & CanvasLayer HUD timer',
            ),
          ],
          outOfScope: const ['No online leaderboards or ghost replay saving'],
          states: const ['Countdown -> Racing -> LapFinish'],
          interrupts: const ['Press R resets lap clock and transforms craft to SpawnPoint'],
          features: [
            FeatureSpec(
              id: 'ep_03_f01',
              code: 'F05',
              title: 'Checkpoint Split Gates',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Require passing $gateWidthVal $distUnit checkpoints before start gate counts.',
              tuning: [
                EpicTuningParam(key: 'checkpoint_width', value: gateWidthVal, unit: distUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f01_c1',
                  text: 'Drive full circuit -> Split chime fires and lap counter increments cleanly',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_03_f02',
              code: 'F06',
              title: 'Lap Stopwatch & Track Reset',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Display millisecond lap timer and reset track cleanly on R.',
              controls: [
                EpicControlBinding(
                  action: 'reset_track',
                  trigger: 'Just Pressed (R)',
                  rule: 'Zeroes velocity and places craft at starting gate',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f02_c1',
                  text: 'Press R mid-lap -> Craft snaps back to start gate with 00.00 timer',
                ),
              ],
            ),
          ],
        ),
      ];
    } else if (effectiveArchetype == 'movement') {
      testScenePath = 'res://scenes/course_proto.tscn';
      inputSummary =
          'InputMap (move_left/right/up/down, jump, air_dash, reset_course)';
      loop = const [
        'Run & Jump',
        'Chain Air Dash',
        'Clear Obstacle Gap',
        'Hit Finish & Reset',
      ];
      epics = [
        EpicSpec(
          id: 'ep_01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Movement & Camera',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · ${loop[0]}',
          goal:
              'Own responsive $bodyCls run/jump physics with coyote time and smooth $camNote follow.',
          inScope: [
            'Run speed $moveVal $speedUnit + crisp jump arc across obstacle platforms',
            '$dodgeDist $distUnit air dash / grapple burst resetting on landing',
          ],
          doneWhen: [
            'Run and jump across greybox gaps -> Zero missed edges during coyote window',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/course_proto.tscn',
              role: 'Obstacle course test level + SpawnPoint + FinishGate',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/player.tscn',
              role: '$bodyCls + $camNote follow rig',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/player.gd',
              role: 'Run, jump buffer, coyote window & air dash state machine',
            ),
          ],
          outOfScope: const ['No wall-climb stamina bars or weapon combat'],
          states: const ['Grounded -> Airborne -> AirDash -> LandRecover'],
          interrupts: const ['Touching ground resets AirDash charge immediately'],
          features: [
            FeatureSpec(
              id: 'ep_01_f01',
              code: 'F01',
              title: 'Run, Jump & Coyote Buffer',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.active,
              goal: 'Run at $moveVal $speedUnit with crisp 0.12 s coyote jump grace.',
              controls: [
                EpicControlBinding(
                  action: 'jump',
                  trigger: 'Just Pressed (Space)',
                  rule: 'Jumps cleanly with coyote & pre-land input buffer',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
                EpicTuningParam(key: 'coyote_time_s', value: '0.12', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f01_c1',
                  text: 'Tap Space just past ledge -> Jump executes cleanly',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_01_f02',
              code: 'F02',
              title: 'Directional Air Dash Burst',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Burst $dodgeDist $distUnit mid-air along input vector before falling.',
              controls: [
                EpicControlBinding(
                  action: 'air_dash',
                  trigger: 'Just Pressed (Shift)',
                  rule: 'Surges $dodgeDist $distUnit mid-air once per airborne jump',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'dash_distance', value: dodgeDist, unit: distUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f02_c1',
                  text: 'Press Shift mid-jump -> Traverses $dodgeDist $distUnit cleanly with trail',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Course Obstacles & Checkpoints',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · ${loop[2]}',
          goal:
              'Own greybox moving/crumbling platforms, fall reset plane, and course checkpoints.',
          inScope: [
            'Checkpoints within $reachVal $distUnit capture safe respawn coordinates',
            'Out-of-bounds trigger teleports cleanly to active checkpoint',
          ],
          doneWhen: [
            'Touch checkpoint then miss jump -> Player respawns at checkpoint in < 0.2 s',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/checkpoint.tscn',
              role: 'Checkpoint pad + Area flag trigger',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/course_hazards.gd',
              role: 'Fall plane & checkpoint respawn manager',
            ),
          ],
          outOfScope: const ['No branching skill upgrades or collectible shop'],
          states: const ['ActiveRun -> Fell -> CheckpointRespawn'],
          interrupts: const ['Respawn clears downward velocity before placing player'],
          features: [
            FeatureSpec(
              id: 'ep_02_f01',
              code: 'F03',
              title: 'Checkpoint Pads & Safe Respawn',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Capture spawn point within $reachVal $distUnit pad radius on overlap.',
              tuning: [
                EpicTuningParam(key: 'checkpoint_radius', value: reachVal, unit: distUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f01_c1',
                  text: 'Step on pad and fall off -> Player restores at pad cleanly',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_02_f02',
              code: 'F04',
              title: 'Launch Pad & Moving Platform',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Boost upward jump velocity cleanly when crossing spring pad nodes.',
              tuning: [
                EpicTuningParam(key: 'spring_boost_mult', value: '1.6', unit: 'x'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f02_c1',
                  text: 'Land on spring pad -> Player launches cleanly onto high ledge',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Course Finish & Run Timer',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 4 · ${loop[3]}',
          goal:
              'Own speedrun stopwatch HUD, finish banner detection, and R instant course restart.',
          inScope: [
            'CanvasLayer stopwatch timer stopping on FinishGate contact',
            'Instant R full-course restart',
          ],
          doneWhen: [
            'Reach FinishGate -> Timer freezes cleanly and R restarts run from SpawnPoint',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/course_timer.gd',
              role: 'Run timer & FinishGate HUD banner',
            ),
          ],
          outOfScope: const ['No ghost race replays or unlock menus'],
          states: const ['Running -> Finished'],
          interrupts: const ['Press R resets timer to 00.00 and clears active checkpoint'],
          features: [
            FeatureSpec(
              id: 'ep_03_f01',
              code: 'F05',
              title: 'Finish Gate & Run Timer HUD',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Stop stopwatch and display clear time when crossing $gateWidthVal $distUnit finish gate.',
              tuning: [
                EpicTuningParam(key: 'finish_gate_width', value: gateWidthVal, unit: distUnit),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f01_c1',
                  text: 'Cross final gate -> Timer freezes cleanly with clear banner',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_03_f02',
              code: 'F06',
              title: 'Instant Course Quick Restart',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Reset player to SpawnPoint and zero timer in < 0.2 s on R.',
              controls: [
                EpicControlBinding(
                  action: 'reset_course',
                  trigger: 'Just Pressed (R)',
                  rule: 'Restarts course run immediately',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_f02_c1',
                  text: 'Press R -> Course & timer reset cleanly back to start',
                ),
              ],
            ),
          ],
        ),
      ];
    } else {
      final hasDeployVerb = lower.contains('deploy') ||
          lower.contains('pad') ||
          lower.contains('turret') ||
          lower.contains('build') ||
          lower.contains('beacon');
      testScenePath = 'res://scenes/arena_proto.tscn';
      inputSummary =
          'InputMap (move_left/right/up/down, dodge, primary_action, reset_proto)';
      loop = <String>[
        'Move & Orient',
        'Trigger Primary Action',
        if (hasDeployVerb) 'Deploy Field Utility',
        'React & Complete Run',
      ];
      epics = <EpicSpec>[
        EpicSpec(
          id: 'ep_01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Movement & Camera',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · ${loop[0]}',
          goal:
              'Own player $bodyCls locomotion, dash evasion impulse, and locked $camNote framing.',
          inScope: [
            'WASD movement at $moveVal $speedUnit inside $arenaExtent playtest room',
            'Forward $dodgeDist $distUnit dodge dash on 1.0 s cooldown',
          ],
          doneWhen: [
            'Move and dodge cleanly inside $arenaExtent -> Zero snagging against walls',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/arena_proto.tscn',
              role: '$arenaExtent greybox test room + SpawnPoint',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/player.tscn',
              role: '$bodyCls + $camNote follow rig',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/player.gd',
              role: 'Movement state machine & @export physics',
            ),
          ],
          outOfScope: const [
            'No climbing, swimming, or crouch stances',
          ],
          states: const [
            'Idle / Move -> DodgeImpulse (0.16s) -> Recover -> Idle / Move',
          ],
          interrupts: const [
            'DodgeImpulse grants temporary collision mask bypass on enemy bodies',
          ],
          features: [
            FeatureSpec(
              id: 'ep_01_f01',
              code: 'F01',
              title: 'Planar Walk & Camera Tracking',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.active,
              goal: 'Control player movement at $moveVal $speedUnit with smooth $camNote follow.',
              controls: [
                EpicControlBinding(
                  action: 'move_8way',
                  trigger: 'Held (WASD)',
                  rule: 'Moves smoothly at $moveVal $speedUnit across floor',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
              ],
              cues: const ['Subtle movement lean matching travel vector'],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f01_c1',
                  text: 'Hold WASD -> Player moves at $moveVal $speedUnit cleanly',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_01_f02',
              code: 'F02',
              title: 'Impulse Dodge Dash',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Execute $dodgeDist $distUnit forward dodge impulse on 1.0 s cooldown.',
              controls: [
                EpicControlBinding(
                  action: 'dodge',
                  trigger: 'Just Pressed (Space)',
                  rule: 'Dashes $dodgeDist $distUnit forward over 0.16 s',
                ),
              ],
              tuning: [
                EpicTuningParam(
                  key: 'dodge_distance',
                  value: dodgeDist,
                  unit: distUnit,
                ),
                EpicTuningParam(key: 'dodge_cooldown', value: '1.0', unit: 's'),
              ],
              cues: const ['Bright debug trail ribbon during DodgeImpulse'],
              checks: [
                EpicPieCheck(
                  id: 'ep_01_f02_c1',
                  text: 'Press Space -> Travels $dodgeDist $distUnit cleanly with cooldown ring',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ep_02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Primary Combat & Action',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 2 · ${loop[1]}',
          goal:
              'Own primary offensive actions along aim direction, impact damage, and cooldown cadence.',
          inScope: [
            '$actionRange $distUnit aimed strike with 25 hp base hit damage',
            'Brief screen impulse and impact flash on hit',
          ],
          doneWhen: [
            'Click LMB toward target -> Hit registers out to $actionRange $distUnit cleanly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/primary_action.gd',
              role: 'Input trace / projectile spawn & 0.25 s cooldown lock',
            ),
          ],
          outOfScope: const [
            'No secondary skill tree or combo upgrades',
          ],
          states: const [
            'Ready -> ActiveAction (0.18s) -> Cooldown (0.25s) -> Ready',
          ],
          interrupts: const [
            'E01 DodgeImpulse cleanly cancels cooldown wind-down',
          ],
          features: [
            FeatureSpec(
              id: 'ep_02_f01',
              code: 'F03',
              title: 'Aimed Primary Strike',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Execute $actionRange $distUnit strike toward aim vector dealing 25 hp.',
              controls: [
                EpicControlBinding(
                  action: 'primary_action',
                  trigger: 'Just Pressed (LMB)',
                  rule: 'Fires active projectile or melee trace out to $actionRange $distUnit',
                ),
              ],
              tuning: [
                EpicTuningParam(
                  key: 'action_range',
                  value: actionRange,
                  unit: distUnit,
                ),
                EpicTuningParam(key: 'action_damage', value: '25', unit: 'hp'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f01_c1',
                  text: 'Click LMB -> Strikes cleanly out to $actionRange $distUnit',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_02_f02',
              code: 'F04',
              title: 'Action Cooldown & Hit Flash',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Enforce 0.25 s strike cadence and emit white impact flash plus camera pulse.',
              tuning: [
                EpicTuningParam(key: 'action_cooldown', value: '0.25', unit: 's'),
              ],
              cues: const ['Emissive impact flash on hit + micro camera kick'],
              checks: [
                EpicPieCheck(
                  id: 'ep_02_f02_c1',
                  text: 'Spam LMB -> Respects 0.25 s fire rate with surface flash on hit',
                ),
              ],
            ),
          ],
        ),
        if (hasDeployVerb)
          EpicSpec(
            id: 'ep_03_util',
            code: 'E03',
            lineageKey: 'e03_util',
            title: 'Field Utility & Nodes',
            releaseVersion: 'v0.1',
            lifecycle: EpicLifecycle.queued,
            coreLoopBeat: 'Beat 3 · ${loop[2]}',
            goal:
                'Own deployable utility instances placed ahead of the player to shape arena space.',
            inScope: [
              'Spawn utility $deployDist $distUnit ahead on 3.0 s cooldown',
              'Cap max 2 concurrent deployed instances cleanly',
            ],
            doneWhen: [
              'Press E -> Utility node deploys $deployDist $distUnit ahead and activates on overlap',
            ],
            sceneOwnership: [
              EpicSceneOwnership(
                path: 'res://scenes/field_utility.tscn',
                role: 'Deployed utility node + trigger area',
              ),
              EpicSceneOwnership(
                path: 'res://scripts/field_utility.gd',
                role: 'Placement distance, cooldown & max count queue',
              ),
            ],
            outOfScope: const [
              'No multi-tier building upgrade grid',
            ],
            states: [
              'Ready -> DeployActive ($deployDist $distUnit offset) -> Cooldown (3.0s)',
            ],
            interrupts: const [
              'Max 2 active utility instances free oldest node automatically',
            ],
            features: [
              FeatureSpec(
                id: 'ep_03_util_f01',
                code: 'F05',
                title: 'Forward Utility Deploy',
                introducedIn: 'v0.1',
                sliceTime: '45 min',
                status: FeatureStatus.queued,
                goal: 'Place utility $deployDist $distUnit ahead on E with cyan ring indicator.',
                controls: [
                  EpicControlBinding(
                    action: 'secondary_action',
                    trigger: 'Just Pressed (E / RMB)',
                    rule: 'Deploys utility node $deployDist $distUnit ahead on a 3.0s cooldown',
                  ),
                ],
                tuning: [
                  EpicTuningParam(
                    key: 'deploy_distance',
                    value: deployDist,
                    unit: distUnit,
                  ),
                  EpicTuningParam(key: 'deploy_cooldown', value: '3.0', unit: 's'),
                ],
                checks: [
                  EpicPieCheck(
                    id: 'ep_03_util_f01_c1',
                    text: 'Press E -> Utility appears $deployDist $distUnit ahead',
                  ),
                ],
              ),
              FeatureSpec(
                id: 'ep_03_util_f02',
                code: 'F06',
                title: 'Instance Cap Recycling',
                introducedIn: 'v0.1',
                sliceTime: '30 min',
                status: FeatureStatus.queued,
                goal: 'Keep at most 2 active utilities by freeing oldest instance on third deploy.',
                tuning: [
                  EpicTuningParam(key: 'max_deployed', value: '2', unit: 'count'),
                ],
                checks: [
                  EpicPieCheck(
                    id: 'ep_03_util_f02_c1',
                    text: 'Deploy third utility -> Oldest node despawns cleanly',
                  ),
                ],
              ),
            ],
          ),
        EpicSpec(
          id: 'ep_loop_close',
          code: hasDeployVerb ? 'E04' : 'E03',
          lineageKey: hasDeployVerb ? 'e04' : 'e03',
          title: 'Enemy Encounters & Loop Reset',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat ${loop.length} · ${loop.last}',
          goal:
              'Own interactive target enemies, readable threat telegraphs, HP tracking, and arena quick reset.',
          inScope: [
            '100 hp target entities stationed $targetDist from SpawnPoint',
            '0.50 s telegraph warning before strike + R arena reset',
          ],
          doneWhen: [
            'Defeat targets and press R -> HUD updates cleanly and arena resets in < 0.2 s',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/target_enemy.tscn',
              role: 'Target body + floating HP bar + telegraph indicator',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/target_enemy.gd',
              role: 'Patrol / 0.50 s telegraph / Stagger loop',
            ),
          ],
          outOfScope: const [
            'No procedural dungeon rooms or loot chests',
          ],
          states: const [
            'Patrol -> Telegraph (0.50s) -> Execute -> Stagger / Defeated',
          ],
          interrupts: const [
            'Heavy hit triggers 0.40s brief knockback stagger without freezing player movement',
          ],
          features: [
            FeatureSpec(
              id: 'ep_loop_f01',
              code: 'F05',
              title: 'Telegraphed Target AI & HP',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Broadcast 0.50 s crimson telegraph before strike and track 100 hp.',
              tuning: [
                EpicTuningParam(key: 'target_hp', value: '100', unit: 'hp'),
                EpicTuningParam(
                  key: 'aggro_range',
                  value: is2d ? '320' : '12.0',
                  unit: distUnit,
                ),
                EpicTuningParam(
                  key: 'telegraph_duration',
                  value: '0.50',
                  unit: 's',
                ),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_loop_f01_c1',
                  text: 'Approach target -> 0.50 s telegraph warns before attack',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_loop_f02',
              code: 'F06',
              title: 'Arena Defeat & Quick Reset',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Update remaining target counter on defeat and reset arena in < 0.2 s on R.',
              controls: [
                EpicControlBinding(
                  action: 'reset_proto',
                  trigger: 'Just Pressed (R)',
                  rule: 'Respawns targets and resets player HP to 100 in < 0.2s',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_loop_f02_c1',
                  text: 'Press R after clearing room -> Arena & HP reset cleanly',
                ),
              ],
            ),
          ],
        ),
      ];
    }

    final bp = ProjectConceptBlueprint(
      sparkPrompt: cleaned,
      gameTitle: title,
      dimension: dimension,
      pitch: '$title — $shortSpark',
      coreLoop: loop,
      cameraChoiceId: cameraChoice,
      cameraContract: cameraContract,
      inputContract: inputSummary,
      feelChoiceId: feelId,
      pillars: const [
        'Instant Frame-1 Control: Player movement and actions respond immediately without sluggish inertia',
        'Clear Spatial Silhouettes: Distinct bright/dark debug shapes communicate state changes before impact',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Tight single-scene greybox playtest room',
          avoid: 'Multi-level streaming worlds',
        ),
        TradeOffRule(
          prefer: 'Readable debug geometry & Control HUD',
          avoid: 'Premature final art pipelines',
        ),
      ],
      outOfScope: const [
        'No main menu, settings modal, or save slots',
        'No multiplayer networking or lobby flows',
        'No inventory UI or equipment loadouts',
      ],
      releaseDoneWhen:
          'Run F6 on $testScenePath -> complete full 30s core loop cleanly with 0 Debugger errors',
      initialEpics: epics,
    );
    normalizeSequentialEpicAndFeatureCodes(bp);
    syncEpicCameraFraming(
      bp,
      optionId: cameraChoice,
      contractValue: cameraContract,
    );
    syncEpicCoreFeel(bp, feelId: feelId);
    return bp;
  }
}

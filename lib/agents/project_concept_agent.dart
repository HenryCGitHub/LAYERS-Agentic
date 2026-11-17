import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/godot_spec_guard.dart';
import 'gemini_agent_client.dart';

/// Stage 1 Godot 4 Co-Designer Agent (`1. Project Spec` -> `PROJECT_SPEC.md`).
/// Generates the high-level Godot 4 foundation (`§01–§04`) and strictly `v0.1` Epics (`§05`),
/// and applies natural-language Co-Designer revisions cleanly in a single pass.
class ProjectConceptAgent {
  static Map<String, dynamic> get _rootSpecToolSchema => <String, dynamic>{
        'name': 'commit_godot_root_spec',
        'description':
            'Create or update the Godot 4 Project Spec (`ROOT_GODOT_CONTEXT`) with §01-§04 foundation contracts and strictly v0.1 prototype Epics in §05 (each complete with §01-§06).',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': [
            'gameTitle',
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

  static Map<String, dynamic> get _epicJsonSchema => <String, dynamic>{
        'type': 'OBJECT',
        'required': [
          'code',
          'title',
          'coreLoopBeat',
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
                'Which §01 Core Loop beat(s) this Epic proves in Playtest (e.g. "Beat 1: Move & Aim").',
          },
          'goal': {
            'type': 'STRING',
            'description': '1 plain sentence describing the playable Epic system.',
          },
          'links': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.godotSceneLinkSchemaDesc,
            },
          },
          'outOfScope': {
            'type': 'ARRAY',
            'items': {
              'type': 'STRING',
              'description': LayersTextStyleGuide.exclusionItemSchemaDesc,
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
          'feedback': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'levelStaging': {
            'type': 'STRING',
            'description': LayersTextStyleGuide.godotSceneStagingSchemaDesc,
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

  static String _fmtScaleNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.01) {
      return v.round().toString();
    }
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Converts an active [ProjectConceptBlueprint] between Godot 4 `3D` (`m`, `m/s`)
  /// and `2D` (`px`, `px/s`), updating §02 camera/scale contracts and `E01..E04` tuning cleanly.
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

    const pxPerMeter = 40.0;
    for (final ep in next.initialEpics) {
      for (final param in ep.tuning) {
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

    syncEpicCameraFraming(
      next,
      optionId: next.cameraChoiceId,
      contractValue: next.cameraContract,
    );
    syncEpicCoreFeel(next, feelId: next.feelChoiceId);
    return GodotSpecGuard.sanitizeConceptBlueprint(next);
  }

  /// Synthesizes a complete Godot 4 Root Project Spec + `2–4` `v0.1` Epics from a 1-sentence spark.
  static Future<ProjectConceptBlueprint> draftSpecFromSpark({
    required String sparkPrompt,
    required String apiKey,
    GodotProjectDimension? dimensionOverride,
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
        return GodotSpecGuard.sanitizeConceptBlueprint(presetCopy);
      }
      final fallback = _buildSynthesizedFallback(
        trimmedSpark,
        dimension: effectiveDim,
      );
      if (trimmedSpark.isNotEmpty) {
        fallback.sparkPrompt = trimmedSpark;
      }
      return GodotSpecGuard.sanitizeConceptBlueprint(fallback);
    }

    final unitGuide = effectiveDim == GodotProjectDimension.dim2d
        ? '2D Pixel Space (`px`, `px/s`, `deg`, `s`, `hp`) with CharacterBody2D/Area2D/Camera2D'
        : '3D 1 unit = 1 meter (`m`, `m/s`, `deg`, `s`, `hp`) with CharacterBody3D/Area3D/SpringArm3D/Camera3D';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are the LAYERS Godot 4 Project Co-Designer.
Generate a clean, build-ready Stage 1 Project Spec (`PROJECT_SPEC.md` -> `ROOT_GODOT_CONTEXT`) for this game idea:
USER SPARK: "$trimmedSpark"
TARGET ARCHITECTURE: ${effectiveDim.fullLabel} (${effectiveDim.architectureContract})
CODE POLICY: ${effectiveDim.codePolicyContract}

CRITICAL CONSTRAINTS:
- Produce `2–4` strictly `v0.1` Prototype Epics in `initialEpics` derived directly from §01 `coreLoop` beats and §02 Camera/Scale/InputMap contracts.
- Order `initialEpics` strictly by playable dependency: `E01` Player Node/Camera/Movement Foundation -> Core Mechanic/Verb Epic(s) -> `v0.1` Loop Target/Closure.
- Populate `coreLoopBeat` on every Epic naming which §01 Core Loop beat(s) it proves, and strictly exclude everything listed in §04 `outOfScope` (defer waves, menus, save slots, meta to `v0.2+`).
- Use $unitGuide everywhere in §02 and every Epic's §04 tuning variables with `snake_case` `@export` keys and `snake_case` `InputMap` action names.
- Each Epic in `initialEpics` MUST include full §01–§06 sections so Godot 4 builds immediately with zero missing fields.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.4,
      functionDeclarations: [_rootSpecToolSchema],
    );

    if (res != null) {
      final parsed = ProjectConceptBlueprint.fromJson(res);
      parsed.sparkPrompt =
          trimmedSpark.isEmpty ? parsed.sparkPrompt : trimmedSpark;
      parsed.dimension = effectiveDim;
      if (parsed.initialEpics.isNotEmpty) {
        for (int i = 0; i < parsed.initialEpics.length; i++) {
          final ep = parsed.initialEpics[i];
          ep.code = 'E${(i + 1).toString().padLeft(2, '0')}';
          if (ep.lineageKey.trim().isEmpty) {
            ep.lineageKey = EpicSpec.formatLineageKey(i + 1);
          }
          ep.releaseVersion = 'v0.1';
          ep.lifecycle =
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued;
        }
        return GodotSpecGuard.sanitizeConceptBlueprint(parsed);
      }
    }

    if (matchedPreset != null) {
      var presetCopy = matchedPreset.deepCopy();
      if (dimensionOverride != null &&
          dimensionOverride != presetCopy.dimension) {
        presetCopy = convertBlueprintDimension(presetCopy, dimensionOverride);
      }
      if (trimmedSpark.isNotEmpty) {
        presetCopy.sparkPrompt = trimmedSpark;
      }
      return GodotSpecGuard.sanitizeConceptBlueprint(presetCopy);
    }
    final fallback = _buildSynthesizedFallback(
      trimmedSpark,
      dimension: effectiveDim,
    );
    if (trimmedSpark.isNotEmpty) {
      fallback.sparkPrompt = trimmedSpark;
    }
    return GodotSpecGuard.sanitizeConceptBlueprint(fallback);
  }

  /// Synchronizes `E01`'s aim/look controls, SpringArm3D/Camera2D tail tuning, and playtest check
  /// whenever the Stage 1 Camera Decision (`§02`) changes, without shifting `tuning[0]`.
  static void syncEpicCameraFraming(
    ProjectConceptBlueprint draft, {
    required String optionId,
    required String contractValue,
  }) {
    if (draft.initialEpics.isEmpty) return;
    final e01 = draft.initialEpics.first;
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
      final idx = e01.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
      );
      if (idx >= 0) {
        e01.tuning[idx].value = value;
        e01.tuning[idx].unit = unit;
      } else {
        e01.tuning.add(EpicTuningParam(key: key, value: value, unit: unit));
      }
    }

    void removeTuning(String key) {
      e01.tuning.removeWhere(
        (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
      );
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

    final aimIdx = e01.controls.indexWhere((c) {
      final a = c.action.toLowerCase();
      return a.contains('aim') || a.contains('look') || a.contains('camera');
    });
    if (aimIdx >= 0) {
      e01.controls[aimIdx].action = aimAction;
      e01.controls[aimIdx].trigger = aimTrigger;
      e01.controls[aimIdx].rule = aimRule;
    } else {
      e01.controls.add(
        EpicControlBinding(
          action: aimAction,
          trigger: aimTrigger,
          rule: aimRule,
        ),
      );
    }

    final expectedCheck = is2d
        ? 'Move cursor across 2D viewport -> player aim indicator tracks cursor immediately'
        : isTps
            ? 'Move mouse -> over-shoulder SpringArm3D orbits smoothly with center reticle alignment'
            : isFps
                ? 'Move mouse -> first-person Camera3D turns smoothly with center reticle alignment'
                : 'Move cursor across floor -> VisualRig tracks ground XZ aim smoothly';

    final checkIdx = e01.checks.indexWhere((c) {
      final t = c.text.toLowerCase();
      return t.contains('cursor') ||
          t.contains('reticle') ||
          t.contains('springarm') ||
          t.contains('camera') ||
          t.contains('visualrig') ||
          t.contains('aim');
    });
    if (checkIdx >= 0) {
      e01.checks[checkIdx].text = expectedCheck;
    } else {
      e01.checks.add(
        EpicPieCheck(
          id: '${e01.code.toLowerCase()}_cam',
          text: expectedCheck,
        ),
      );
    }
  }

  /// Synchronizes `feelChoiceId`, primary §03 feel `TradeOffRule`, and `E01` tail tuning (`braking_decel`)
  /// without disturbing `e01.tuning[0]`.
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
    final e01 = draft.initialEpics.first;
    final decelVal = opt.decelFor(draft.dimension);
    final speedUnit = draft.dimension.speedUnit;
    final decelIdx = e01.tuning.indexWhere(
      (t) =>
          t.key.trim().toLowerCase() == 'braking_decel' ||
          t.key.trim().toLowerCase() == 'brakingdecel',
    );
    if (decelIdx >= 0) {
      e01.tuning[decelIdx].key = 'braking_decel';
      e01.tuning[decelIdx].value = decelVal;
      e01.tuning[decelIdx].unit = speedUnit;
    } else {
      e01.tuning.add(
        EpicTuningParam(
          key: 'braking_decel',
          value: decelVal,
          unit: speedUnit,
        ),
      );
    }
  }

  /// Applies a user's Co-Designer instruction directly onto an active Stage 1 [ProjectConceptBlueprint].
  static Future<ProjectConceptBlueprint> applyCoDesignEdit({
    required ProjectConceptBlueprint currentSpec,
    required String instruction,
    required String apiKey,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return currentSpec;

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _applyOfflineCoDesignEdit(currentSpec, trimmed);
    }

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Update the Godot 4 Root Project Spec (`ROOT_GODOT_CONTEXT`) below according to the user's instruction.
TARGET ARCHITECTURE: ${currentSpec.dimension.fullLabel} (${currentSpec.dimension.architectureContract})
CODE POLICY: ${currentSpec.dimension.codePolicyContract}
Return the complete updated JSON via `commit_godot_root_spec`, preserving existing approved sections unless the instruction asks to change them.
Whenever §01 `coreLoop`, §02 Camera/Input/Scale contracts, or §04 `outOfScope` change, update §05 `initialEpics` in lockstep (`coreLoopBeat`, `controls`, `tuning`, `checks`, and dependency order).
Keep all `initialEpics` strictly at `2–4` `v0.1` prototype Epics with Godot units (`m`/`m/s` for 3D, `px`/`px/s` for 2D) and `snake_case` `@export` keys.

CURRENT SPEC JSON:
${jsonEncode(currentSpec.toJson())}

USER CO-DESIGN INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
      functionDeclarations: [_rootSpecToolSchema],
    );

    if (res != null) {
      final parsed = ProjectConceptBlueprint.fromJson(res);
      parsed.sparkPrompt = currentSpec.sparkPrompt;
      parsed.dimension = currentSpec.dimension;
      parsed.approved = currentSpec.approved;
      if (parsed.v02Presets.isEmpty) {
        parsed.v02Presets = List<ReleaseDirectionPreset>.from(
          currentSpec.v02Presets,
        );
      }
      if (parsed.v02NewPool.isEmpty) {
        parsed.v02NewPool = [
          for (final e in currentSpec.v02NewPool) e.deepCopy(),
        ];
      }
      if (parsed.v02UpgradesByLineageKey.isEmpty) {
        parsed.v02UpgradesByLineageKey = {
          for (final entry in currentSpec.v02UpgradesByLineageKey.entries)
            entry.key: [for (final u in entry.value) u.copyWith()],
        };
      }
      parsed.lastCoDesignNote =
          (res['coDesignNote'] ?? 'Updated spec from: $trimmed')
              .toString()
              .trim();
      if (parsed.initialEpics.isNotEmpty) {
        final rawEpicsList = res['initialEpics'] as List? ?? const [];
        final prevEpics = currentSpec.initialEpics;
        final usedPrev = List<bool>.filled(prevEpics.length, false);
        final incomingTitles = {
          for (final inc in parsed.initialEpics)
            if (inc.title.trim().isNotEmpty) inc.title.trim().toLowerCase(),
        };

        for (int i = 0; i < parsed.initialEpics.length; i++) {
          final ep = parsed.initialEpics[i];
          final rawMap = i < rawEpicsList.length && rawEpicsList[i] is Map
              ? rawEpicsList[i] as Map
              : const <String, dynamic>{};
          final explicitLineage =
              (rawMap['lineageKey'] ?? '').toString().trim();

          int? matchIdx;
          if (explicitLineage.isNotEmpty) {
            final lowerLineage = explicitLineage.toLowerCase();
            for (int j = 0; j < prevEpics.length; j++) {
              if (!usedPrev[j] &&
                  prevEpics[j].lineageKey.trim().toLowerCase() == lowerLineage) {
                matchIdx = j;
                break;
              }
            }
          }
          if (matchIdx == null) {
            final incTitle = ep.title.trim().toLowerCase();
            if (incTitle.isNotEmpty) {
              for (int j = 0; j < prevEpics.length; j++) {
                if (!usedPrev[j] &&
                    prevEpics[j].title.trim().toLowerCase() == incTitle) {
                  matchIdx = j;
                  break;
                }
              }
            }
          }
          if (matchIdx == null &&
              i < prevEpics.length &&
              !usedPrev[i] &&
              !incomingTitles.contains(prevEpics[i].title.trim().toLowerCase())) {
            matchIdx = i;
          }

          ep.code = 'E${(i + 1).toString().padLeft(2, '0')}';
          ep.releaseVersion = 'v0.1';
          if (i == 0 && ep.lifecycle == EpicLifecycle.queued) {
            ep.lifecycle = EpicLifecycle.active;
          }
          if (matchIdx != null) {
            usedPrev[matchIdx] = true;
            final prev = prevEpics[matchIdx];
            ep.lineageKey = prev.lineageKey;
            parsed.initialEpics[i] = ep.deepCopy(idOverride: prev.id);
          } else {
            ep.lineageKey = explicitLineage.isNotEmpty
                ? explicitLineage
                : EpicSpec.formatLineageKey(i + 1);
          }
        }
        return GodotSpecGuard.sanitizeConceptBlueprint(parsed);
      }
    }

    return _applyOfflineCoDesignEdit(currentSpec, trimmed);
  }

  static ProjectConceptBlueprint _applyOfflineCoDesignEdit(
    ProjectConceptBlueprint current,
    String instruction,
  ) {
    final next = current.deepCopy();
    final lower = instruction.toLowerCase();

    if (RegExp(r'\b2d\b').hasMatch(lower)) {
      final converted = convertBlueprintDimension(next, GodotProjectDimension.dim2d);
      converted.lastCoDesignNote =
          'Switched project dimension to Godot 4 · 2D (px, px/s).';
      return converted;
    } else if (RegExp(r'\b3d\b').hasMatch(lower)) {
      final converted = convertBlueprintDimension(next, GodotProjectDimension.dim3d);
      converted.lastCoDesignNote =
          'Switched project dimension to Godot 4 · 3D (m, m/s).';
      return converted;
    } else if (lower.contains('side-scroller') || lower.contains('side scroller')) {
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
      return GodotSpecGuard.sanitizeConceptBlueprint(base);
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
      return GodotSpecGuard.sanitizeConceptBlueprint(base);
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
      return GodotSpecGuard.sanitizeConceptBlueprint(base);
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
      return GodotSpecGuard.sanitizeConceptBlueprint(base);
    } else if (lower.contains('heavy') ||
        lower.contains('deliberate') ||
        lower.contains('weighty')) {
      syncEpicCoreFeel(next, feelId: 'heavy');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Heavy Deliberate.';
    } else if (lower.contains('physics') ||
        lower.contains('momentum') ||
        lower.contains('drift')) {
      syncEpicCoreFeel(next, feelId: 'physics');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Physics Momentum.';
    } else if (lower.contains('snappy') || lower.contains('arcade')) {
      syncEpicCoreFeel(next, feelId: 'snappy');
      next.lastCoDesignNote =
          'Switched §03 Core Feel & E01 locomotion to Snappy Arcade.';
    } else if (lower.startsWith('no ') ||
        lower.contains('cut ') ||
        lower.contains('remove ')) {
      final cut = instruction
          .replaceFirst(RegExp(r'^(cut|remove)\s+', caseSensitive: false), '')
          .trim();
      final item = cut.toLowerCase().startsWith('no ') ? cut : 'No $cut';
      if (!next.outOfScope.contains(item)) {
        next.outOfScope = [...next.outOfScope, item];
      }
      next.lastCoDesignNote = 'Added hard scope cut: $item';
    } else {
      next.pillars = [...next.pillars, instruction];
      next.lastCoDesignNote = 'Added Co-Design direction: $instruction';
    }
    return GodotSpecGuard.sanitizeConceptBlueprint(next);
  }

  static ProjectConceptBlueprint _buildSynthesizedFallback(
    String sparkPrompt, {
    required GodotProjectDimension dimension,
  }) {
    final cleaned = sparkPrompt.trim();
    final lower = cleaned.toLowerCase();
    final is2d = dimension == GodotProjectDimension.dim2d;
    final isSideScroller = is2d &&
        (lower.contains('side-scroller') ||
            lower.contains('side scroller') ||
            lower.contains('platformer') ||
            lower.contains('metroidvania'));
    final isFps = !is2d &&
        (lower.contains('first-person') ||
            lower.contains('first person') ||
            lower.contains('fps'));
    final isTps = !is2d &&
        !isFps &&
        (lower.contains('third-person') ||
            lower.contains('third person') ||
            lower.contains('over-shoulder') ||
            lower.contains('over shoulder') ||
            lower.contains('glider') ||
            lower.contains('wingsuit') ||
            lower.contains('grapple') ||
            lower.contains('grappling') ||
            lower.contains('tps'));
    final isTopDown3d = !is2d &&
        !isFps &&
        !isTps &&
        (lower.contains('top-down') || lower.contains('top down'));

    final cameraChoice = is2d
        ? (isSideScroller ? 'sidescroller2d' : 'topdown2d')
        : (isFps
            ? 'fps'
            : (isTps ? 'tps' : (isTopDown3d ? 'topdown' : 'isometric')));
    final cameraContract = is2d
        ? (isSideScroller
            ? 'Camera2D Zoom 1.4x · Lookahead 64 px · Horizontal floor lock'
            : 'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim')
        : (isFps
            ? 'Camera3D EyeHeight 1.65 m · 90 deg FOV · Captured mouse yaw/pitch'
            : isTps
                ? 'SpringArm3D 3.8 m · Offset (0.65, 0.55) m · 68 deg FOV · CameraLag 10.0'
                : isTopDown3d
                    ? 'SpringArm3D 16.5 m @ -88 deg pitch, 50 deg FOV, Zero camera roll'
                    : 'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0');

    final feelId = (lower.contains('heavy') ||
            lower.contains('deliberate') ||
            lower.contains('souls'))
        ? 'heavy'
        : (lower.contains('drift') ||
                lower.contains('hover') ||
                lower.contains('glider') ||
                lower.contains('physics'))
            ? 'physics'
            : 'snappy';
    final hasDeployVerb = lower.contains('deploy') ||
        lower.contains('pad') ||
        lower.contains('turret') ||
        lower.contains('build') ||
        lower.contains('beacon');

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

    final loop = <String>[
      'Move & Orient',
      'Trigger Primary Action',
      if (hasDeployVerb) 'Deploy Field Utility',
      'React & Complete Run',
    ];

    final distUnit = dimension.distanceUnit;
    final speedUnit = dimension.speedUnit;
    final moveVal = is2d ? '260' : '6.2';
    final dodgeDist = is2d ? '180' : '5.0';
    final actionRange = is2d ? '420' : '16.0';
    final deployDist = is2d ? '72' : '2.0';
    final arenaExtent = is2d ? '1280x720 px' : '28x28 m';
    final targetDist = is2d ? '320 px' : '12 m';
    final bodyCls = is2d ? 'CharacterBody2D' : 'CharacterBody3D';
    final camNote = is2d ? 'Camera2D' : 'SpringArm3D';

    final epics = <EpicSpec>[
      EpicSpec(
        id: 'ep_01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Player Movement & Camera Rig',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · ${loop[0]}',
        goal:
            'Control the player $bodyCls at fixed speed with smooth directional facing and locked $camNote framing.',
        links: const [
          'Scene res://scenes/player.tscn + res://scripts/player.gd',
          'Emits player velocity & aim vector to E02',
        ],
        outOfScope: const [
          'No climbing, swimming, or crouch stances',
        ],
        controls: [
          EpicControlBinding(
            action: 'move_left / move_right / move_up / move_down',
            trigger: 'Held (WASD)',
            rule: 'Accelerates smoothly to $moveVal $speedUnit cleanly across arena',
          ),
          EpicControlBinding(
            action: 'dodge',
            trigger: 'Just Pressed (Space)',
            rule: 'Impulses $dodgeDist $distUnit forward over 0.16s with 1.0s cooldown',
          ),
        ],
        states: const [
          'Idle / Move -> DodgeImpulse (0.16s) -> Recover -> Idle / Move',
        ],
        interrupts: const [
          'DodgeImpulse grants temporary collision mask bypass on enemy bodies',
        ],
        tuning: [
          EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
          EpicTuningParam(
              key: 'dodge_distance', value: dodgeDist, unit: distUnit),
          EpicTuningParam(key: 'dodge_cooldown', value: '1.0', unit: 's'),
        ],
        feedback: const [
          'Bright debug trail ribbon during DodgeImpulse',
          'Compact radial cooldown arc beneath player node',
        ],
        levelStaging:
            'res://scenes/arena_proto.tscn: $arenaExtent greybox arena + perimeter walls + SpawnPoint',
        checks: [
          EpicPieCheck(
            id: 'ep_01_c1',
            text:
                'Hold WASD -> player moves smoothly at $moveVal $speedUnit with zero wall snagging',
          ),
          EpicPieCheck(
            id: 'ep_01_c2',
            text:
                'Press Space -> executes crisp $dodgeDist $distUnit forward dash and obeys 1.0s cooldown',
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_02',
        code: 'E02',
        lineageKey: 'e02',
        title: 'Primary Player Action & Feedback',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 2 · ${loop[1]}',
        goal:
            'Execute the primary combat or interaction action cleanly along aim direction with crisp hit reaction.',
        links: const [
          'Reads player transform from E01 and calls take_damage(amount) on target nodes',
        ],
        outOfScope: const [
          'No secondary skill tree or combo upgrades',
        ],
        controls: [
          EpicControlBinding(
            action: 'primary_action',
            trigger: 'Just Pressed (LMB)',
            rule: 'Fires active projectile or melee trace out to $actionRange $distUnit',
          ),
        ],
        states: const [
          'Ready -> ActiveAction (0.18s) -> Cooldown (0.25s) -> Ready',
        ],
        interrupts: const [
          'E01 DodgeImpulse cleanly cancels cooldown wind-down',
        ],
        tuning: [
          EpicTuningParam(key: 'action_damage', value: '25', unit: 'hp'),
          EpicTuningParam(
              key: 'action_range', value: actionRange, unit: distUnit),
          EpicTuningParam(key: 'action_cooldown', value: '0.25', unit: 's'),
        ],
        feedback: const [
          'Emissive impact flash on target surface plus brief camera impulse',
        ],
        levelStaging:
            'res://scenes/arena_proto.tscn: add two static collision pillars along firing lane',
        checks: [
          EpicPieCheck(
            id: 'ep_02_c1',
            text:
                'Click LMB -> primary action triggers immediately with visible impact cue on hit',
          ),
        ],
      ),
      if (hasDeployVerb)
        EpicSpec(
          id: 'ep_03_util',
          code: 'E03',
          lineageKey: 'e03_util',
          title: 'Deployable Field Utility Node',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · ${loop[2]}',
          goal:
              'Place a single greybox utility scene ahead of the player to extend arena traversal or tactical control.',
          links: const [
            'Spawns res://scenes/field_utility.tscn along E01 forward aim direction',
          ],
          outOfScope: const [
            'No multi-tier building upgrade grid',
          ],
          controls: [
            EpicControlBinding(
              action: 'secondary_action',
              trigger: 'Just Pressed (E / RMB)',
              rule: 'Deploys utility node $deployDist $distUnit ahead on a 3.0s cooldown',
            ),
          ],
          states: [
            'Ready -> DeployActive ($deployDist $distUnit offset) -> Cooldown (3.0s)',
          ],
          interrupts: const [
            'Max 2 active utility instances free oldest node automatically',
          ],
          tuning: [
            EpicTuningParam(
                key: 'deploy_distance', value: deployDist, unit: distUnit),
            EpicTuningParam(key: 'deploy_cooldown', value: '3.0', unit: 's'),
            EpicTuningParam(key: 'max_deployed', value: '2', unit: 'count'),
          ],
          feedback: const [
            'Cyan ring marks active utility placement & area trigger',
          ],
          levelStaging:
              'res://scenes/arena_proto.tscn: central gap zone requiring deployed utility to trigger',
          checks: [
            EpicPieCheck(
              id: 'ep_03_util_c1',
              text:
                  'Press E -> deploys utility $deployDist $distUnit ahead and triggers cleanly on overlap',
            ),
          ],
        ),
      EpicSpec(
        id: 'ep_loop_close',
        code: hasDeployVerb ? 'E04' : 'E03',
        lineageKey: hasDeployVerb ? 'e04' : 'e03',
        title: 'Target Entity & Arena Loop Closure',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat ${loop.length} · ${loop.last}',
        goal:
            'Place interactive enemy/target nodes with readable threat telegraph, HP tracking, and quick arena reset.',
        links: const [
          'Scene res://scenes/target_enemy.tscn receives E02 damage & updates HUD counter',
        ],
        outOfScope: const [
          'No procedural dungeon rooms or loot chests',
        ],
        controls: [
          EpicControlBinding(
            action: 'reset_proto',
            trigger: 'Just Pressed (R)',
            rule: 'Respawns targets and resets player HP to 100 in < 0.2s',
          ),
        ],
        states: const [
          'Patrol -> Telegraph (0.50s) -> Execute -> Stagger / Defeated',
        ],
        interrupts: const [
          'Heavy hit triggers 0.40s brief knockback stagger without freezing player movement',
        ],
        tuning: [
          EpicTuningParam(key: 'target_hp', value: '100', unit: 'hp'),
          EpicTuningParam(key: 'telegraph_duration', value: '0.50', unit: 's'),
        ],
        feedback: const [
          'Floating HP bar + crimson telegraph flash before enemy attack',
        ],
        levelStaging:
            'res://scenes/arena_proto.tscn: 2 target nodes stationed $targetDist from SpawnPoint',
        checks: [
          EpicPieCheck(
            id: 'ep_03_c1',
            text:
                'Defeat both targets -> HUD status updates cleanly and pressing R resets arena',
          ),
        ],
      ),
    ];

    final bp = ProjectConceptBlueprint(
      sparkPrompt: cleaned,
      gameTitle: title,
      dimension: dimension,
      pitch: '$title — $shortSpark',
      coreLoop: loop,
      cameraChoiceId: cameraChoice,
      cameraContract: cameraContract,
      inputContract:
          'InputMap (move_left/right/up/down, dodge, primary_action, reset_proto)',
      feelChoiceId: feelId,
      pillars: const [
        'Instant Frame-1 Control: Player movement and actions respond immediately without sluggish inertia',
        'Clear Spatial Silhouettes: Distinct bright/dark debug shapes communicate danger before impact',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Tight single-scene greybox arena',
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
          'Run F6 on res://scenes/arena_proto.tscn -> complete full 30s core loop cleanly with 0 Debugger errors',
      initialEpics: epics,
    );
    syncEpicCameraFraming(
      bp,
      optionId: cameraChoice,
      contractValue: cameraContract,
    );
    syncEpicCoreFeel(bp, feelId: feelId);
    return bp;
  }
}

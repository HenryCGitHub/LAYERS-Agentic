import 'dart:convert';
import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/unreal_spec_guard.dart';
import 'gemini_agent_client.dart';

import 'concept/concept_fallback_synthesizer.dart';
import 'concept/project_concept_epic_sync.dart';
import 'concept/project_concept_schemas.dart';

/// Stage 1 Unreal Engine 5 Co-Designer Agent (`1. Project Spec` -> `PROJECT_SPEC.md`).
/// Generates the high-level Unreal Engine 5 foundation (`§01–§04`) and strictly `v0.1` Epics (`§05`),
/// and applies natural-language Co-Designer revisions via scoped JSON patches.
class ProjectConceptAgent {
  static ProjectConceptBlueprint convertBlueprintArchitectureMode(
    ProjectConceptBlueprint source,
    UnrealArchitectureMode targetMode,
  ) =>
      convertBlueprintArchitectureModeImpl(source, targetMode);

  /// Keeps `E01..EN` and `F01..FM` strictly sequential across `initialEpics` without gaps or duplicate codes.
  static void normalizeSequentialEpicAndFeatureCodes(
    ProjectConceptBlueprint bp,
  ) =>
      normalizeSequentialEpicAndFeatureCodesImpl(bp);

  /// Synchronizes locomotion Epic & first Feature's aim/look controls, tail tuning, and playtest check
  /// whenever the Stage 1 Camera Decision (`§02`) changes, without shifting `tuning[0]`.
  static void syncEpicCameraFraming(
    ProjectConceptBlueprint draft, {
    required String optionId,
    required String contractValue,
  }) =>
      syncEpicCameraFramingImpl(
        draft,
        optionId: optionId,
        contractValue: contractValue,
      );

  /// Synchronizes `feelChoiceId`, primary §03 feel `TradeOffRule`, and locomotion Epic tail tuning (`braking_decel`)
  /// without disturbing `tuning[0]`.
  static void syncEpicCoreFeel(
    ProjectConceptBlueprint draft, {
    required String feelId,
  }) =>
      syncEpicCoreFeelImpl(draft, feelId: feelId);

  static Future<ProjectConceptBlueprint> draftSpecFromSpark({
    required String sparkPrompt,
    required String apiKey,
    UnrealArchitectureMode? architectureModeOverride,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final outcome = await draftSpecWithStatus(
      sparkPrompt: sparkPrompt,
      apiKey: apiKey,
      architectureModeOverride: architectureModeOverride,
      archetypeId: archetypeId,
      viewChoiceId: viewChoiceId,
      prototypeHookId: prototypeHookId,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
    );
    if (outcome.blueprint != null) return outcome.blueprint!;
    throw StateError(outcome.errorMessage ?? 'Failed to draft Project Spec.');
  }

  /// Synthesizes a complete Unreal Engine 5 Root Project Spec + `2–4` `v0.1` Epics and surfaces real AI errors.
  static Future<Stage1AgentOutcome> draftSpecWithStatus({
    required String sparkPrompt,
    required String apiKey,
    UnrealArchitectureMode? architectureModeOverride,
    String? archetypeId,
    String? viewChoiceId,
    String? prototypeHookId,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = 'LOW',
  }) async {
    final trimmedSpark = sparkPrompt.trim();
    final matchedPreset = UnrealSparkPresets.matchSparkPrompt(trimmedSpark);
    final effectiveMode = architectureModeOverride ??
        matchedPreset?.architectureMode ??
        UnrealArchitectureMode.detectFromSpark(trimmedSpark);

    if (!GeminiAgentClient.hasKey(apiKey)) {
      if (matchedPreset != null) {
        var presetCopy = matchedPreset.deepCopy();
        if (architectureModeOverride != null &&
            architectureModeOverride != presetCopy.architectureMode) {
          presetCopy = convertBlueprintArchitectureMode(
            presetCopy,
            architectureModeOverride,
          );
        }
        if (trimmedSpark.isNotEmpty) {
          presetCopy.sparkPrompt = trimmedSpark;
        }
        final sanitized = UnrealSpecGuard.sanitizeConceptBlueprint(
          raw: presetCopy,
          modeOverride: effectiveMode,
        );
        normalizeSequentialEpicAndFeatureCodes(sanitized);
        return Stage1AgentOutcome(
          blueprint: sanitized,
          usedOfflineFallback: true,
          changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
        );
      }
      final fallback = buildSynthesizedFallback(
        trimmedSpark,
        architectureMode: effectiveMode,
        archetypeId: archetypeId,
        viewChoiceId: viewChoiceId,
        prototypeHookId: prototypeHookId,
      );
      if (trimmedSpark.isNotEmpty) {
        fallback.sparkPrompt = trimmedSpark;
      }
      var clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: fallback,
        modeOverride: effectiveMode,
      );
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
      );
    }

    final tuningStyleGuide = effectiveMode == UnrealArchitectureMode.cppHybrid
        ? 'Unreal Engine 5 C++ & BP Hybrid (`cm`, `cm/s`, `deg`, `s`, `hp`) with Source/ `ACharacter` `UPROPERTY(EditAnywhere)` classes and thin `BP_*` subclasses'
        : 'Unreal Engine 5 Blueprint-First (`cm`, `cm/s`, `deg`, `s`, `hp`) with `/Game/Blueprints/BP_*`, `/Game/UI/WBP_*`, `USpringArmComponent`, and `UCameraComponent`';
    final archetypeHint = archetypeId != null && archetypeId.trim().isNotEmpty
        ? '\nREQUESTED GENRE ARCHETYPE: $archetypeId'
            '${viewChoiceId != null && viewChoiceId.isNotEmpty ? ' · camera=$viewChoiceId' : ''}'
            '${prototypeHookId != null && prototypeHookId.isNotEmpty ? ' · prototype_goal=$prototypeHookId' : ''}'
        : '';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are the LAYERS Unreal Engine 5 Project Co-Designer.
Generate a clean, build-ready Stage 1 Project Spec (`PROJECT_SPEC.md` -> `ROOT_UNREAL_CONTEXT`) for this game idea:
USER SPARK: "$trimmedSpark"
TARGET ARCHITECTURE: ${effectiveMode.fullLabel} (${effectiveMode.architectureContract})
CODE POLICY: ${effectiveMode.codePolicyContract}$archetypeHint

CRITICAL CONSTRAINTS:
- Match the true genre of the spark cleanly: for non-combat ideas (puzzle, racing, cozy, builder, stealth), design native Unreal maps (`/Game/Maps/Lvl_RoomProto.umap`, `/Game/Maps/Lvl_TrackProto.umap`, `/Game/Maps/Lvl_CourseProto.umap`) and domain inputs/verbs instead of forcing enemy combat or arena brawlers.
- Produce `2–4` Large-Domain `v0.1` Prototype Epics in `initialEpics` derived directly from §01 `coreLoop` beats and §02 Camera/Scale/Enhanced Input contracts.
- Each Epic owns shared `sceneOwnership` (`/Game/Maps/Lvl_*.umap`, `/Game/Blueprints/BP_*`, `/Game/UI/WBP_*`, or `Source/*.cpp` files), `inScope`, `doneWhen`, `states`, `interrupts`, `outOfScope`, AND `2–3` sittable 30-90 min `v0.1` Feature slices inside `features` (`F01`, `F02`, ... sequentially across all Epics with zero duplicate `F01` resets and zero `Task`/`Step` micro-lists).
- Keep controls, Exposed BP / `UPROPERTY(EditAnywhere)` tuning parameters, cues, and PIE Playtest Gate checks inside child `features` (never duplicate them on the parent Epic).
- Populate `coreLoopBeat` on every Epic naming which §01 Core Loop beat(s) it proves, and defer waves, menus, save slots, and meta progression to `v0.2+`.
- Use $tuningStyleGuide everywhere in §02 and in every Feature tuning parameter with `PascalCase` keys and `IA_*` Enhanced Input action names.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.4,
      functionDeclarations: [rootSpecToolSchema],
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
    if (architectureModeOverride != null &&
        parsed.architectureMode != architectureModeOverride) {
      final converted =
          convertBlueprintArchitectureMode(parsed, architectureModeOverride);
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
    final rawModeStr =
        (res['architectureMode'] ?? res['mode'] ?? '').toString().trim();
    if (rawModeStr.isEmpty) {
      parsed.architectureMode = effectiveMode;
    }
    if (parsed.initialEpics.isEmpty) {
      return const Stage1AgentOutcome(
        blueprint: null,
        errorMessage:
            'Cloud Gemini returned an empty §05 Epic list. Please retry.',
      );
    }
    var clean = UnrealSpecGuard.sanitizeConceptBlueprint(
      raw: parsed,
      modeOverride: parsed.architectureMode,
    );
    normalizeSequentialEpicAndFeatureCodes(clean);
    return Stage1AgentOutcome(
      blueprint: clean,
      changedSections: const <String>{'s01', 's02', 's03', 's04', 's05'},
    );
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

    // Detect architectureMode switches FIRST.
    final rawArch = (patch['architectureMode'] ?? patch['mode'] ?? '').toString().trim();
    if (rawArch.isNotEmpty) {
      final targetMode = UnrealArchitectureMode.fromString(rawArch);
      if (targetMode != next.architectureMode) {
        next = convertBlueprintArchitectureMode(next, targetMode);
        changed.addAll(const <String>{'s02', 's05'});
      }
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
    next = UnrealSpecGuard.sanitizeConceptBlueprint(
      raw: next,
      modeOverride: next.architectureMode,
    );
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

    final compactJson = jsonEncode(compactStage1JsonForPrompt(currentSpec));
    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Patch only the sections of the Unreal Engine 5 Root Project Spec (`§01-§05`) requested by the user instruction.
CURRENT ARCHITECTURE: ${currentSpec.architectureMode.fullLabel} (${currentSpec.architectureMode.architectureContract})
CODE POLICY: ${currentSpec.architectureMode.codePolicyContract}
RULES:
- Call `patch_unreal_root_spec` with ONLY the fields you need to change plus `coDesignNote` and `changedSections`.
- Omit unchanged scalar/list fields and untouched Epics so untouched sections remain identical.
- If changing `architectureMode` (`blueprint` / `cppHybrid`) or Camera framing, update `architectureMode`, `cameraChoiceId`, `cameraContract`, `characterScale`, and any affected Epics in `epicUpdates`.
- Keep all `§05` Epics strictly at `2–4` `v0.1` Epics with sequential `F01..FM` Feature slices and Unreal units (`cm`/`cm/s`).

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
      functionDeclarations: [patchRootSpecToolSchema],
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

    if (RegExp(r'\b(?:c\+\+|cpp|hybrid)\b').hasMatch(lower)) {
      final converted = convertBlueprintArchitectureMode(
        next,
        UnrealArchitectureMode.cppHybrid,
      );
      normalizeSequentialEpicAndFeatureCodes(converted);
      converted.lastCoDesignNote =
          'Switched project mode to Unreal Engine 5 · C++ & BP Hybrid.';
      return Stage1AgentOutcome(
        blueprint: converted,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (RegExp(r'\bblueprint(?:-first)?\b').hasMatch(lower)) {
      final converted = convertBlueprintArchitectureMode(
        next,
        UnrealArchitectureMode.blueprint,
      );
      normalizeSequentialEpicAndFeatureCodes(converted);
      converted.lastCoDesignNote =
          'Switched project mode to Unreal Engine 5 · Blueprint-First.';
      return Stage1AgentOutcome(
        blueprint: converted,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('side-scroller') ||
        lower.contains('side scroller')) {
      next.cameraChoiceId = 'sidescroller';
      next.cameraContract =
          'USpringArmComponent TargetArmLength 950 cm · Ortho/Locked Track · 55 deg FOV · Lookahead 160 cm';
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 framing to Side-Scroller Cam.';
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('first-person') ||
        lower.contains('first person') ||
        lower.contains('fps')) {
      next.cameraChoiceId = 'fps';
      next.cameraContract =
          'UCameraComponent EyeHeight 165 cm · 90 deg FOV · Captured mouse yaw/pitch';
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 look controls to First-Person.';
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
      next.cameraChoiceId = 'tps';
      next.cameraContract =
          'USpringArmComponent TargetArmLength 360 cm · SocketOffset (0, 65, 55) cm · 68 deg FOV · CameraLagSpeed 11.0';
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 look controls to Third-Person.';
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('top-down') || lower.contains('top down')) {
      next.cameraChoiceId = 'topdown';
      next.cameraContract =
          'USpringArmComponent TargetArmLength 1650 cm @ -88 deg pitch, 50 deg FOV, Zero camera roll';
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 cursor aim to Fixed Top-Down.';
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
      normalizeSequentialEpicAndFeatureCodes(clean);
      return Stage1AgentOutcome(
        blueprint: clean,
        usedOfflineFallback: true,
        changedSections: const <String>{'s02', 's05'},
      );
    } else if (lower.contains('isometric')) {
      next.cameraChoiceId = 'isometric';
      next.cameraContract =
          'USpringArmComponent TargetArmLength 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0';
      syncEpicCameraFraming(
        next,
        optionId: next.cameraChoiceId,
        contractValue: next.cameraContract,
      );
      next.lastCoDesignNote =
          'Switched §02 Camera contract & E01 cursor aim to Isometric.';
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
      final clean = UnrealSpecGuard.sanitizeConceptBlueprint(
        raw: next,
        modeOverride: next.architectureMode,
      );
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
}

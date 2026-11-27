import 'dart:convert';

import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/unreal_spec_guard.dart';
import 'gemini_agent_client.dart';

/// Result returned from refining a Stage 2 [EpicSpec].
class Stage2EpicRefineOutcome {
  final EpicSpec? epic;
  final String summary;
  final Set<String> changedSections;
  final String? errorMessage;
  final bool usedFallback;

  const Stage2EpicRefineOutcome({
    this.epic,
    this.summary = '',
    this.changedSections = const <String>{},
    this.errorMessage,
    this.usedFallback = false,
  });
}

/// Result returned from refining a Stage 2 [FeatureSpec].
class Stage2FeatureRefineOutcome {
  final FeatureSpec? feature;
  final String summary;
  final Set<String> changedSections;
  final String? errorMessage;
  final bool usedFallback;

  const Stage2FeatureRefineOutcome({
    this.feature,
    this.summary = '',
    this.changedSections = const <String>{},
    this.errorMessage,
    this.usedFallback = false,
  });
}

/// Result returned from refining a Stage 2 Release Spec (`v0.1`, `v0.2+`).
class Stage2ReleaseRefineOutcome {
  final String? title;
  final String? goal;
  final String? doneWhen;
  final String summary;
  final String? errorMessage;
  final bool usedFallback;

  const Stage2ReleaseRefineOutcome({
    this.title,
    this.goal,
    this.doneWhen,
    this.summary = '',
    this.errorMessage,
    this.usedFallback = false,
  });
}

/// Surgical Stage 2 Gemini 4 Hydrogen (`LOW` thinking) patch agent for individual
/// Unreal Engine 5 Domain Epics (`§01-§04`), Feature Slices (`§01-§05`), and Releases.
class Stage2RefineAgent {
  const Stage2RefineAgent._();

  static Map<String, dynamic> get patchReleaseSpecToolSchema => <String, dynamic>{
        'name': 'patch_unreal_release_spec',
        'description':
            'Patch only the requested fields of an Unreal Engine 5 Release Spec (title, goal, doneWhen). Omit untouched fields.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': ['summary'],
          'properties': <String, dynamic>{
            'summary': {
              'type': 'STRING',
              'description': 'Short 6-12 word changelog of what changed.',
            },
            'title': {'type': 'STRING'},
            'goal': {'type': 'STRING'},
            'doneWhen': {'type': 'STRING'},
          },
        },
      };

  static Map<String, dynamic> get patchEpicSpecToolSchema => <String, dynamic>{
        'name': 'patch_unreal_epic_spec',
        'description':
            'Patch only the requested sections of an Unreal Engine 5 Stage 2 Epic Domain Sheet (§01 Scope, §02 Ownership, §03 State & Interrupt Rules, §04 Out-of-Scope Cuts). Omit untouched fields.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': ['summary', 'changedSections'],
          'properties': <String, dynamic>{
            'summary': {
              'type': 'STRING',
              'description': 'Short 6-12 word changelog of what changed.',
            },
            'changedSections': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'enum': ['s01', 's02', 's03', 's04'],
              },
            },
            'title': {'type': 'STRING'},
            'goal': {'type': 'STRING'},
            'inScope': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'doneWhen': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'sceneOwnership': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['path', 'role'],
                'properties': {
                  'path': {'type': 'STRING'},
                  'role': {'type': 'STRING'},
                },
              },
            },
            'stateFlow': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'interruptRules': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'outOfScope': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
      };

  static Map<String, dynamic> get patchFeatureSpecToolSchema =>
      <String, dynamic>{
        'name': 'patch_unreal_feature_spec',
        'description':
            'Patch only the requested sections of an Unreal Engine 5 Stage 2 Feature Spec (§01 Scope, §02 Enhanced Input, §03 Tuning Vars in cm/cm/s, §04 Cues, §05 PIE Checks). Omit untouched fields.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': ['summary', 'changedSections'],
          'properties': <String, dynamic>{
            'summary': {
              'type': 'STRING',
              'description': 'Short 6-12 word changelog of what changed.',
            },
            'changedSections': {
              'type': 'ARRAY',
              'items': {
                'type': 'STRING',
                'enum': ['s01', 's02', 's03', 's04', 's05'],
              },
            },
            'title': {'type': 'STRING'},
            'goal': {'type': 'STRING'},
            'inScope': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'doneWhen': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'releaseDelta': {'type': 'STRING'},
            'controls': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['action', 'trigger', 'rule'],
                'properties': {
                  'action': {'type': 'STRING'},
                  'trigger': {'type': 'STRING'},
                  'rule': {'type': 'STRING'},
                },
              },
            },
            'tuning': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['key', 'value', 'unit'],
                'properties': {
                  'key': {'type': 'STRING'},
                  'value': {'type': 'STRING'},
                  'unit': {'type': 'STRING'},
                },
              },
            },
            'cues': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'checks': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'releaseDeltaChecks': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
      };

  /// Refines [epic] using scoped JSON patching on `gemini-4-hydrogen` (`LOW` thinking),
  /// falling back deterministically when offline / no API key is configured.
  static Future<Stage2EpicRefineOutcome> refineEpicSpec({
    required ProjectConceptBlueprint? rootSpec,
    required EpicSpec epic,
    required String instruction,
    required String apiKey,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = GeminiAgentClient.defaultFastThinkingLevel,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) {
      return Stage2EpicRefineOutcome(epic: epic);
    }
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _applyDeterministicEpicRefine(epic, trimmed, mode);
    }

    final compactEpic = <String, dynamic>{
      'code': epic.code,
      'title': epic.title,
      'goal': epic.goal,
      'inScope': epic.inScope,
      'doneWhen': epic.doneWhen,
      'sceneOwnership': [for (final o in epic.sceneOwnership) o.toJson()],
      'stateFlow': epic.stateFlow,
      'interruptRules': epic.interruptRules,
      'outOfScope': epic.outOfScope,
      'childFeatures': [
        for (final f in epic.features) '${f.code}: ${f.title}',
      ],
    };

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Patch only the requested sections (§01-§04) of this Unreal Engine 5 Epic Domain Sheet.
PROJECT: ${rootSpec?.normalizedTitle ?? 'UE5 PROJECT'} (${mode.architectureContract})
CODE POLICY: ${mode.codePolicyContract}
RULES:
- Call `patch_unreal_epic_spec` with ONLY the modified fields plus `summary` and `changedSections`.
- Keep all asset ownership strictly Unreal Engine 5 (`/Game/...`, `Source/...`, `BP_*`, `WBP_*`, `IA_*`, `IMC_*`).
- Stay 100% native Unreal Engine 5 using `cm` and `cm/s` units only.
- Child Features belong in Features, not inside the Epic sheet.

CURRENT EPIC JSON:
${jsonEncode(compactEpic)}

USER REFINE INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      functionDeclarations: [patchEpicSpecToolSchema],
    );

    if (res == null) {
      return Stage2EpicRefineOutcome(
        epic: null,
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini could not refine ${epic.code}. Retry when ready.',
      );
    }

    return _applyPatchToEpic(epic, res, fallbackNote: trimmed, mode: mode);
  }

  /// Refines [feature] using scoped JSON patching on `gemini-4-hydrogen` (`LOW` thinking),
  /// falling back deterministically when offline / no API key is configured.
  static Future<Stage2FeatureRefineOutcome> refineFeatureSpec({
    required ProjectConceptBlueprint? rootSpec,
    required EpicSpec epic,
    required FeatureSpec feature,
    required String instruction,
    required String apiKey,
    String releaseVersion = 'v0.1',
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = GeminiAgentClient.defaultFastThinkingLevel,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) {
      return Stage2FeatureRefineOutcome(feature: feature);
    }
    final relVer = releaseVersion.trim();
    final isDeltaTarget = relVer.isNotEmpty &&
        relVer != 'v0.1' &&
        feature.introducedIn.trim() != relVer &&
        feature.releaseDelta.trim().isNotEmpty;
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _applyDeterministicFeatureRefine(
        feature,
        trimmed,
        mode,
        isDeltaTarget: isDeltaTarget,
      );
    }

    final compactFeat = <String, dynamic>{
      'code': feature.code,
      'title': feature.title,
      'introducedIn': feature.introducedIn,
      'goal': feature.goal,
      'inScope': feature.inScope,
      'doneWhen': feature.doneWhen,
      if (feature.releaseDelta.trim().isNotEmpty)
        'releaseDelta': feature.releaseDelta,
      'controls': [for (final c in feature.controls) c.toJson()],
      'tuning': [for (final t in feature.tuning) t.toJson()],
      'cues': feature.cues,
      'checks': [for (final chk in feature.checks) chk.text],
      if (isDeltaTarget)
        'releaseDeltaChecks': [
          for (final chk in feature.releaseDeltaChecks) chk.text,
        ],
    };

    final deltaRule = isDeltaTarget
        ? '\n- Because this feature is a $relVer delta upgrade, place new or updated playtest gate checks in `releaseDeltaChecks` and leave `${feature.introducedIn}` baseline `checks` unchanged.'
        : '';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Patch only the requested sections (§01-§05) of this Unreal Engine 5 Feature Spec.
PROJECT: ${rootSpec?.normalizedTitle ?? 'UE5 PROJECT'} (${mode.architectureContract})
PARENT EPIC: ${epic.code} · ${epic.title} (${epic.goal})
RULES:
- Call `patch_unreal_feature_spec` with ONLY the modified fields plus `summary` and `changedSections`.
- Input bindings use Enhanced Input `IA_*` action names; tuning keys use `PascalCase` in `cm`, `cm/s`, `deg`, `s`, `hp`, `x`, or `%`.
- Playtest checks use concise causal `Player Action -> Observable Viewport Result` syntax (<= 14 words).
- Stay 100% native Unreal Engine 5 using `cm` and `cm/s` units only.$deltaRule

CURRENT FEATURE JSON:
${jsonEncode(compactFeat)}

USER REFINE INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      functionDeclarations: [patchFeatureSpecToolSchema],
    );

    if (res == null) {
      return Stage2FeatureRefineOutcome(
        feature: null,
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini could not refine ${feature.code}. Retry when ready.',
      );
    }

    return _applyPatchToFeature(
      feature,
      res,
      fallbackNote: trimmed,
      mode: mode,
      isDeltaTarget: isDeltaTarget,
    );
  }

  static Stage2EpicRefineOutcome _applyPatchToEpic(
    EpicSpec source,
    Map<String, dynamic> patch, {
    required String fallbackNote,
    required UnrealArchitectureMode mode,
  }) {
    final next = source.deepCopy();
    final changed = _parseChangedSections(patch['changedSections']);

    final rawTitle = _nonEmptyString(patch['title']);
    if (rawTitle != null) {
      next.title = rawTitle;
      changed.add('s01');
    }
    final rawGoal = _nonEmptyString(patch['goal']);
    if (rawGoal != null) {
      next.goal = rawGoal;
      changed.add('s01');
    }
    final parsedInScope = _parseStringArray(patch['inScope']);
    if (parsedInScope != null) {
      next.inScope = parsedInScope;
      changed.add('s01');
    }
    final parsedDoneWhen = _parseStringArray(patch['doneWhen']);
    if (parsedDoneWhen != null) {
      next.doneWhen = parsedDoneWhen;
      changed.add('s01');
    }
    if (patch['sceneOwnership'] is List) {
      final owners = <EpicSceneOwnership>[
        for (final item in (patch['sceneOwnership'] as List))
          EpicSceneOwnership.fromJson(item),
      ].where((o) => o.path.trim().isNotEmpty).toList();
      next.sceneOwnership = owners;
      changed.add('s02');
    }
    final parsedStates = _parseStringArray(patch['stateFlow']);
    if (parsedStates != null) {
      next.stateFlow = parsedStates;
      changed.add('s03');
    }
    final parsedRules = _parseStringArray(patch['interruptRules']);
    if (parsedRules != null) {
      next.interruptRules = parsedRules;
      changed.add('s03');
    }
    final parsedCuts = _parseStringArray(patch['outOfScope']);
    if (parsedCuts != null) {
      next.outOfScope = parsedCuts;
      changed.add('s04');
    }

    final clean = UnrealSpecGuard.sanitizeEpicSpec(next, mode: mode);
    final summary = _nonEmptyString(patch['summary']) ??
        'Updated ${clean.code}: $fallbackNote';
    return Stage2EpicRefineOutcome(
      epic: clean,
      summary: UnrealSpecGuard.sanitizeLine(summary, mode: mode),
      changedSections: changed,
    );
  }

  static Stage2FeatureRefineOutcome _applyPatchToFeature(
    FeatureSpec source,
    Map<String, dynamic> patch, {
    required String fallbackNote,
    required UnrealArchitectureMode mode,
    bool isDeltaTarget = false,
  }) {
    final next = source.deepCopy();
    final changed = _parseChangedSections(patch['changedSections']);

    final rawTitle = _nonEmptyString(patch['title']);
    if (rawTitle != null) {
      next.title = rawTitle;
      changed.add('s01');
    }
    final rawGoal = _nonEmptyString(patch['goal']);
    if (rawGoal != null) {
      next.goal = rawGoal;
      changed.add('s01');
    }
    final parsedInScope = _parseStringArray(patch['inScope']);
    if (parsedInScope != null) {
      next.inScope = parsedInScope;
      changed.add('s01');
    }
    final parsedDoneWhen = _parseStringArray(patch['doneWhen']);
    if (parsedDoneWhen != null) {
      next.doneWhen = parsedDoneWhen;
      changed.add('s01');
    }
    final rawDelta = _nonEmptyString(patch['releaseDelta']);
    if (rawDelta != null) {
      next.releaseDelta = rawDelta;
      changed.add('s01');
    }
    if (patch['controls'] is List) {
      next.controls = <EpicControlBinding>[
        for (final item in (patch['controls'] as List))
          if (item is Map)
            EpicControlBinding.fromJson(Map<String, dynamic>.from(item)),
      ].where((c) => c.action.trim().isNotEmpty).toList();
      changed.add('s02');
    }
    if (patch['tuning'] is List) {
      next.tuning = <EpicTuningParam>[
        for (final item in (patch['tuning'] as List))
          if (item is Map)
            EpicTuningParam.fromJson(Map<String, dynamic>.from(item)),
      ].where((t) => t.key.trim().isNotEmpty).toList();
      changed.add('s03');
    }
    final parsedCues = _parseStringArray(patch['cues']);
    if (parsedCues != null) {
      next.cues = parsedCues;
      changed.add('s04');
    }
    if (isDeltaTarget) {
      final parsedDeltaChecks = _parseStringArray(patch['releaseDeltaChecks']) ??
          _parseStringArray(patch['checks']);
      if (parsedDeltaChecks != null) {
        final passedByText = <String, EpicPieCheck>{
          for (final existing in source.releaseDeltaChecks)
            existing.text.trim().toLowerCase(): existing,
        };
        next.releaseDeltaChecks = <EpicPieCheck>[
          for (int i = 0; i < parsedDeltaChecks.length; i++)
            _mergePieCheck(
              parsedDeltaChecks[i],
              i,
              featureId: '${source.id}_delta',
              existingByText: passedByText,
            ),
        ];
        changed.add('s05');
      }
    } else {
      final parsedChecks = _parseStringArray(patch['checks']);
      if (parsedChecks != null) {
        final passedByText = <String, EpicPieCheck>{
          for (final existing in source.checks)
            existing.text.trim().toLowerCase(): existing,
        };
        next.checks = <EpicPieCheck>[
          for (int i = 0; i < parsedChecks.length; i++)
            _mergePieCheck(
              parsedChecks[i],
              i,
              featureId: source.id,
              existingByText: passedByText,
            ),
        ];
        changed.add('s05');
      }
    }

    final clean = UnrealSpecGuard.sanitizeFeatureSpec(next, mode: mode);
    final summary = _nonEmptyString(patch['summary']) ??
        'Updated ${clean.code}: $fallbackNote';
    return Stage2FeatureRefineOutcome(
      feature: clean,
      summary: UnrealSpecGuard.sanitizeLine(summary, mode: mode),
      changedSections: changed,
    );
  }

  static EpicPieCheck _mergePieCheck(
    String rawText,
    int index, {
    required String featureId,
    required Map<String, EpicPieCheck> existingByText,
  }) {
    final prior = existingByText[rawText.trim().toLowerCase()];
    if (prior != null) {
      return EpicPieCheck(id: prior.id, text: rawText, passed: prior.passed);
    }
    return EpicPieCheck(
      id: '${featureId}_chk_${DateTime.now().microsecondsSinceEpoch}_$index',
      text: rawText,
    );
  }

  static Stage2EpicRefineOutcome _applyDeterministicEpicRefine(
    EpicSpec source,
    String instruction,
    UnrealArchitectureMode mode,
  ) {
    final next = source.deepCopy();
    final changed = <String>{};
    final pathMatch =
        RegExp(r'(/(?:Game|Script)/[^\s,;]+|Source/[^\s,;]+)')
            .firstMatch(instruction);
    if (pathMatch != null) {
      final path = pathMatch.group(1)!;
      if (!next.sceneOwnership.any((o) => o.path == path)) {
        next.sceneOwnership.add(
          EpicSceneOwnership(path: path, role: 'Shared domain owner'),
        );
      }
      changed.add('s02');
    } else if (RegExp(r'^no\s+', caseSensitive: false).hasMatch(instruction) ||
        instruction.toLowerCase().contains('cut ')) {
      final rawCut =
          instruction.replaceFirst(RegExp(r'^cut\s+', caseSensitive: false), '');
      final cleanCut = UnrealSpecGuard.sanitizeExclusion(rawCut, mode: mode);
      if (cleanCut.isNotEmpty) {
        next.outOfScope.add(cleanCut);
        changed.add('s04');
      }
    } else if (instruction.contains('->')) {
      final states = instruction
          .split('->')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (states.length >= 2) {
        next.stateFlow = states;
        changed.add('s03');
      }
    } else if (instruction.toLowerCase().contains('interrupt') ||
        instruction.toLowerCase().contains('cancel') ||
        instruction.toLowerCase().contains('rule')) {
      next.interruptRules.add(instruction);
      changed.add('s03');
    } else {
      next.inScope.add(instruction);
      changed.add('s01');
    }

    final clean = UnrealSpecGuard.sanitizeEpicSpec(next, mode: mode);
    return Stage2EpicRefineOutcome(
      epic: clean,
      summary: 'Offline refine applied to ${clean.code}',
      changedSections: changed,
      usedFallback: true,
    );
  }

  static Stage2FeatureRefineOutcome _applyDeterministicFeatureRefine(
    FeatureSpec source,
    String instruction,
    UnrealArchitectureMode mode, {
    bool isDeltaTarget = false,
  }) {
    final next = source.deepCopy();
    final changed = <String>{};
    final tuneMatch = RegExp(
      r'(?:set|tune|change|make)\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:to|=)\s*([0-9]+(?:\.[0-9]+)?|true|false)\s*([A-Za-z/%]*)',
      caseSensitive: false,
    ).firstMatch(instruction);

    if (tuneMatch != null) {
      final rawKey = tuneMatch.group(1)!.trim();
      final val = tuneMatch.group(2)!.trim();
      final unit = tuneMatch.group(3)?.trim() ?? '';
      final normKey = UnrealSpecGuard.sanitizeTuningKey(rawKey).toLowerCase();
      final idx = next.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == normKey,
      );
      if (idx >= 0) {
        next.tuning[idx].value = val;
        if (unit.isNotEmpty) next.tuning[idx].unit = unit;
      } else {
        next.tuning.add(
          EpicTuningParam(key: rawKey, value: val, unit: unit),
        );
      }
      changed.add('s03');
    } else if (instruction.contains('->')) {
      final newCheck = EpicPieCheck(
        id: '${source.id}_${isDeltaTarget ? 'dchk' : 'chk'}_${DateTime.now().microsecondsSinceEpoch}',
        text: instruction,
      );
      if (isDeltaTarget) {
        next.releaseDeltaChecks.add(newCheck);
      } else {
        next.checks.add(newCheck);
      }
      changed.add('s05');
    } else if (RegExp(r'\bIA_[A-Za-z0-9_]+').hasMatch(instruction)) {
      final action = RegExp(r'\b(IA_[A-Za-z0-9_]+)').firstMatch(instruction)!;
      next.controls.add(
        EpicControlBinding(
          action: action.group(1)!,
          trigger: 'Triggered',
          rule: instruction,
        ),
      );
      changed.add('s02');
    } else if (instruction.toLowerCase().contains('cue') ||
        instruction.toLowerCase().contains('sfx') ||
        instruction.toLowerCase().contains('vfx') ||
        instruction.toLowerCase().contains('audio')) {
      next.cues.add(instruction);
      changed.add('s04');
    } else {
      next.inScope.add(instruction);
      changed.add('s01');
    }

    final clean = UnrealSpecGuard.sanitizeFeatureSpec(next, mode: mode);
    return Stage2FeatureRefineOutcome(
      feature: clean,
      summary: 'Offline refine applied to ${clean.code}',
      changedSections: changed,
      usedFallback: true,
    );
  }

  /// Refines a Release Spec (`title`, `goal`, `doneWhen`) on `gemini-4-hydrogen` (`LOW` thinking),
  /// falling back deterministically when offline / no API key is configured.
  static Future<Stage2ReleaseRefineOutcome> refineReleaseSpec({
    required ProjectConceptBlueprint? rootSpec,
    required String versionTag,
    required String currentTitle,
    required String currentGoal,
    required String currentDoneWhen,
    required List<EpicSpec> epics,
    required String instruction,
    required String apiKey,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = GeminiAgentClient.defaultFastThinkingLevel,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) {
      return const Stage2ReleaseRefineOutcome();
    }
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return _applyDeterministicReleaseRefine(
        versionTag: versionTag,
        currentTitle: currentTitle,
        currentGoal: currentGoal,
        currentDoneWhen: currentDoneWhen,
        instruction: trimmed,
        mode: mode,
      );
    }

    final compactRelease = <String, dynamic>{
      'version': versionTag,
      'title': currentTitle,
      'goal': currentGoal,
      'doneWhen': currentDoneWhen,
      'epics': [
        for (final ep in epics)
          '${ep.code} ${ep.title}: ${[for (final f in ep.features) '${f.code} ${f.title}'].join(', ')}',
      ],
    };

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

Patch only the requested fields of this Unreal Engine 5 Release Spec ($versionTag).
PROJECT: ${rootSpec?.normalizedTitle ?? 'UE5 PROJECT'} (${mode.architectureContract})
RULES:
- Call `patch_unreal_release_spec` with ONLY modified fields (`title`, `goal`, `doneWhen`) plus `summary`.
- Keep `goal` a single plain sentence and `doneWhen` a concrete PIE playtest gate.
- Stay 100% native Unreal Engine 5 using `cm` and `cm/s` units only.

CURRENT RELEASE JSON:
${jsonEncode(compactRelease)}

USER REFINE INSTRUCTION:
"$trimmed"
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      functionDeclarations: [patchReleaseSpecToolSchema],
    );

    if (res == null) {
      return Stage2ReleaseRefineOutcome(
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini could not refine $versionTag. Retry when ready.',
      );
    }
    final rawTitle = _nonEmptyString(res['title']);
    final rawGoal = _nonEmptyString(res['goal']);
    final rawDone = _nonEmptyString(res['doneWhen']);
    final summary = _nonEmptyString(res['summary']) ??
        'Updated $versionTag release spec';
    return Stage2ReleaseRefineOutcome(
      title: rawTitle != null
          ? UnrealSpecGuard.sanitizeLine(rawTitle, mode: mode)
          : null,
      goal: rawGoal != null
          ? UnrealSpecGuard.sanitizeLine(rawGoal, mode: mode)
          : null,
      doneWhen: rawDone != null
          ? UnrealSpecGuard.sanitizeLine(rawDone, mode: mode)
          : null,
      summary: UnrealSpecGuard.sanitizeLine(summary, mode: mode),
    );
  }

  static Stage2ReleaseRefineOutcome _applyDeterministicReleaseRefine({
    required String versionTag,
    required String currentTitle,
    required String currentGoal,
    required String currentDoneWhen,
    required String instruction,
    required UnrealArchitectureMode mode,
  }) {
    final lower = instruction.toLowerCase();
    final cleanInst = UnrealSpecGuard.sanitizeLine(instruction, mode: mode);
    if (lower.contains('rename') || lower.contains('title')) {
      final cleaned = cleanInst
          .replaceFirst(
            RegExp(r'^(?:rename|set\s+title(?:\s+to)?)\s*', caseSensitive: false),
            '',
          )
          .trim();
      final nextTitle = cleaned.isEmpty
          ? currentTitle
          : (cleaned.toLowerCase().startsWith(versionTag.toLowerCase())
              ? cleaned
              : '$versionTag · $cleaned');
      return Stage2ReleaseRefineOutcome(
        title: nextTitle,
        summary: 'Updated $versionTag title',
        usedFallback: true,
      );
    }
    if (lower.contains('gate') ||
        lower.contains('pie') ||
        lower.contains('done') ||
        lower.contains('->') ||
        RegExp(r'\b\d+\s*s\b', caseSensitive: false).hasMatch(cleanInst)) {
      final base = currentDoneWhen.trim().replaceFirst(RegExp(r'\.$'), '');
      final nextDone = base.isEmpty ? cleanInst : '$base — $cleanInst.';
      return Stage2ReleaseRefineOutcome(
        doneWhen: UnrealSpecGuard.sanitizeLine(nextDone, mode: mode),
        summary: 'Updated $versionTag PIE gate',
        usedFallback: true,
      );
    }
    final baseGoal = currentGoal.trim().replaceFirst(RegExp(r'\.$'), '');
    final nextGoal = baseGoal.isEmpty ? cleanInst : '$baseGoal ($cleanInst).';
    return Stage2ReleaseRefineOutcome(
      goal: UnrealSpecGuard.sanitizeLine(nextGoal, mode: mode),
      summary: 'Updated $versionTag goal',
      usedFallback: true,
    );
  }

  static String? _nonEmptyString(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Set<String> _parseChangedSections(dynamic raw) {
    if (raw is! List) return <String>{};
    return <String>{
      for (final item in raw)
        if (item.toString().trim().isNotEmpty)
          item.toString().trim().toLowerCase(),
    };
  }

  static List<String>? _parseStringArray(dynamic raw) {
    if (raw is! List) return null;
    return <String>[
      for (final item in raw)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
  }
}
